import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

protocol ImageProcessing: Sendable {
    func render(source: URL, settings: ImageOutputSettings, destination: URL) async throws -> PreviewArtifact
}

struct ImageProcessor: ImageProcessing {
    let runner: ProcessRunner

    func render(source: URL, settings: ImageOutputSettings, destination: URL) async throws -> PreviewArtifact {
        try Task.checkCancellation()
        if settings.format == .webp || isAnimated(source) || !supportsNativeEncoding(settings.format) {
            if let target = settings.targetBytes {
                return try await renderFFmpegToTarget(source: source, settings: settings, target: target, destination: destination)
            }
            return try await renderWithFFmpeg(source: source, settings: settings, destination: destination)
        }
        if let target = settings.targetBytes {
            return try await renderToTarget(source: source, settings: settings, target: target, destination: destination)
        }
        try encodeNative(source: source, settings: settings, destination: destination)
        return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
    }

    private func supportsNativeEncoding(_ format: ImageFormat) -> Bool {
        let identifier: String
        switch format {
        case .jpeg: identifier = UTType.jpeg.identifier
        case .png: identifier = UTType.png.identifier
        case .heic: identifier = UTType.heic.identifier
        case .avif: identifier = "public.avif"
        case .webp: return false
        }
        return (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(identifier) == true
    }

    private func isAnimated(_ source: URL) -> Bool {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
        return CGImageSourceGetCount(image) > 1
    }

    private func renderToTarget(source: URL, settings: ImageOutputSettings, target: Int64, destination: URL) async throws -> PreviewArtifact {
        var candidate = settings
        var dimensionsScale = 1.0
        while dimensionsScale > 0 {
            try Task.checkCancellation()
            if candidate.format.supportsLossyQuality {
                var low = 0.35
                var high = 1.0
                var bestURL: URL?
                for _ in 0..<8 {
                    candidate.quality = (low + high) / 2
                    let trial = temporaryURL(extension: candidate.format.fileExtension)
                    try encodeNative(source: source, settings: candidate, destination: trial)
                    if trial.fileByteCount <= target {
                        bestURL.map { try? FileManager.default.removeItem(at: $0) }
                        bestURL = trial
                        low = candidate.quality
                    } else {
                        high = candidate.quality
                        try? FileManager.default.removeItem(at: trial)
                    }
                }
                if let bestURL {
                    try FileManager.default.moveItem(at: bestURL, to: destination)
                    return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
                }
                candidate.quality = 0.35
            } else {
                let trial = temporaryURL(extension: candidate.format.fileExtension)
                try encodeNative(source: source, settings: candidate, destination: trial)
                if trial.fileByteCount <= target {
                    try FileManager.default.moveItem(at: trial, to: destination)
                    return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
                }
                try? FileManager.default.removeItem(at: trial)
            }

            dimensionsScale *= 0.85
            guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { break }
            let outputWidth = Int(width * dimensionsScale)
            let outputHeight = Int(height * dimensionsScale)
            guard max(outputWidth, outputHeight) >= 256 else { break }
            candidate.resize = ResizeSettings(mode: .dimensions, width: outputWidth, height: outputHeight)
        }
        throw MediaPressError.targetImpossible
    }

    private func encodeNative(source: URL, settings: ImageOutputSettings, destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            throw MediaPressError.invalidMedia(source.lastPathComponent)
        }
        let outputSize = settings.resize.outputSize(for: CGSize(width: width, height: height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(outputSize.width, outputSize.height)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw MediaPressError.processingFailed("Could not resize \(source.lastPathComponent)")
        }
        let image: CGImage
        if settings.resize.mode == .dimensions, !settings.resize.retainAspectRatio {
            image = try stretchedImage(thumbnail, size: outputSize)
        } else {
            image = thumbnail
        }
        let uti: CFString
        switch settings.format {
        case .jpeg: uti = UTType.jpeg.identifier as CFString
        case .png: uti = UTType.png.identifier as CFString
        case .heic: uti = UTType.heic.identifier as CFString
        case .avif: uti = "public.avif" as CFString
        case .webp: throw MediaPressError.unsupported("Native WebP encoding")
        }
        guard let destinationRef = CGImageDestinationCreateWithURL(destination as CFURL, uti, 1, nil) else {
            throw MediaPressError.unsupported(settings.format.rawValue.uppercased())
        }
        var outputProperties: [CFString: Any] = [:]
        if settings.format.supportsLossyQuality {
            outputProperties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, settings.quality))
        }
        CGImageDestinationAddImage(destinationRef, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destinationRef) else {
            throw MediaPressError.processingFailed("Failed to encode \(settings.format.rawValue.uppercased())")
        }
    }

    private func renderWithFFmpeg(source: URL, settings: ImageOutputSettings, destination: URL) async throws -> PreviewArtifact {
        let tools = try FFmpegLocator.locate()
        let size = try sourceImageSize(source)
        let output = settings.resize.outputSize(for: size)
        let scaleFilter = settings.resize.mode == .dimensions && !settings.resize.retainAspectRatio
            ? "scale=\(Int(output.width)):\(Int(output.height))"
            : "scale=\(Int(output.width)):\(Int(output.height)):force_original_aspect_ratio=decrease"
        var arguments = ["-y", "-i", source.path, "-vf", scaleFilter]
        if settings.format == .webp {
            arguments += ["-c:v", isAnimated(source) ? "libwebp_anim" : "libwebp", "-q:v", String(Int(settings.quality * 100)), "-loop", "0"]
        } else if settings.format == .avif {
            let crf = Int((1 - settings.quality) * 55 + 8)
            arguments += ["-c:v", "libaom-av1", "-still-picture", "1", "-crf", String(crf), "-cpu-used", "6", "-frames:v", "1"]
        }
        arguments += ["-map_metadata", "-1", destination.path]
        _ = try await runner.run(executable: tools.ffmpeg, arguments: arguments)
        return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
    }

    private func renderFFmpegToTarget(source: URL, settings: ImageOutputSettings, target: Int64, destination: URL) async throws -> PreviewArtifact {
        let originalSize = try sourceImageSize(source)
        var dimensionScale = 1.0
        while max(originalSize.width * dimensionScale, originalSize.height * dimensionScale) >= 256 {
            var low = 0.35
            var high = 1.0
            var bestURL: URL?
            for _ in 0..<8 {
                try Task.checkCancellation()
                var candidate = settings
                candidate.targetBytes = nil
                candidate.quality = (low + high) / 2
                let width = Int(originalSize.width * dimensionScale)
                let height = Int(originalSize.height * dimensionScale)
                candidate.resize = ResizeSettings(mode: .dimensions, width: width, height: height)
                let trial = temporaryURL(extension: candidate.format.fileExtension)
                _ = try await renderWithFFmpeg(source: source, settings: candidate, destination: trial)
                if trial.fileByteCount <= target {
                    bestURL.map { try? FileManager.default.removeItem(at: $0) }
                    bestURL = trial
                    low = candidate.quality
                } else {
                    try? FileManager.default.removeItem(at: trial)
                    high = candidate.quality
                }
            }
            if let bestURL {
                try FileManager.default.moveItem(at: bestURL, to: destination)
                return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
            }
            dimensionScale *= 0.85
        }
        throw MediaPressError.targetImpossible
    }

    private func sourceImageSize(_ source: URL) throws -> CGSize {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            throw MediaPressError.invalidMedia(source.lastPathComponent)
        }
        return CGSize(width: width, height: height)
    }

    private func stretchedImage(_ image: CGImage, size: CGSize) throws -> CGImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MediaPressError.processingFailed("Could not create the exact image dimensions")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else {
            throw MediaPressError.processingFailed("Could not create the exact image dimensions")
        }
        return output
    }

    private func temporaryURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}
