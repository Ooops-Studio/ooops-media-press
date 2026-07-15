import Foundation
import ImageIO
import AVFoundation

protocol MediaProbing: Sendable {
    func probe(_ url: URL) async throws -> MediaProbe
}

struct MediaProbeService: MediaProbing {
    let runner: ProcessRunner

    func probe(_ url: URL) async throws -> MediaProbe {
        if let svgProbe = probeSVG(url) { return svgProbe }
        if let imageProbe = probeImage(url) { return imageProbe }
        return try await probeWithFFprobe(url)
    }

    private func probeSVG(_ url: URL) -> MediaProbe? {
        guard url.pathExtension.lowercased() == "svg",
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let dimensions = SVGRootDimensions.parse(data) else { return nil }
        return MediaProbe(kind: .vectorImage, format: "svg",
                          width: max(1, Int(dimensions.width.rounded())),
                          height: max(1, Int(dimensions.height.rounded())),
                          duration: nil, frameRate: nil, codec: "SVG",
                          hasAudio: false, isHDR: false, isAnimated: false,
                          byteCount: url.fileByteCount)
    }

    private func probeImage(_ url: URL) -> MediaProbe? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        let count = CGImageSourceGetCount(source)
        let uti = (CGImageSourceGetType(source) as String?) ?? url.pathExtension.lowercased()
        let isAnimated = count > 1
        return MediaProbe(kind: isAnimated ? .animatedImage : .image,
                          format: uti, width: width, height: height, duration: nil,
                          frameRate: nil, codec: nil, hasAudio: false, isHDR: false,
                          isAnimated: isAnimated, byteCount: url.fileByteCount)
    }

    private func probeWithFFprobe(_ url: URL) async throws -> MediaProbe {
        let tools = try FFmpegLocator.locate()
        let result = try await runner.run(executable: tools.ffprobe, arguments: [
            "-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path
        ])
        let root = try JSONDecoder().decode(FFProbeRoot.self, from: result.stdout)
        guard let video = root.streams.first(where: { $0.codecType == "video" }) else {
            throw MediaPressError.invalidMedia(url.lastPathComponent)
        }
        let duration = Double(video.duration ?? root.format?.duration ?? "")
        let fps = Self.parseRate(video.avgFrameRate)
        let transfer = video.colorTransfer?.lowercased() ?? ""
        let hdr = transfer.contains("smpte2084") || transfer.contains("arib-std-b67") || (video.bitsPerRawSample.flatMap(Int.init) ?? 8) > 8
        return MediaProbe(kind: .video, format: root.format?.formatName ?? url.pathExtension,
                          width: video.width ?? 0, height: video.height ?? 0, duration: duration,
                          frameRate: fps, codec: video.codecName, hasAudio: root.streams.contains { $0.codecType == "audio" },
                          isHDR: hdr, isAnimated: false, byteCount: url.fileByteCount)
    }

    private static func parseRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let pieces = value.split(separator: "/").compactMap { Double($0) }
        guard pieces.count == 2, pieces[1] != 0 else { return Double(value) }
        return pieces[0] / pieces[1]
    }
}

private final class SVGRootDimensions: NSObject, XMLParserDelegate {
    private var size: CGSize?

    static func parse(_ data: Data) -> CGSize? {
        let delegate = SVGRootDimensions()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        _ = parser.parse()
        return delegate.size
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = (qName ?? elementName).lowercased()
        guard name == "svg" || name.hasSuffix(":svg") else { return }
        let width = Self.numberPrefix(attributeDict["width"])
        let height = Self.numberPrefix(attributeDict["height"])
        let viewBox = Self.viewBox(attributeDict["viewBox"] ?? attributeDict["viewbox"])

        if let width, let height, width > 0, height > 0 {
            size = CGSize(width: width, height: height)
        } else if let viewBox, viewBox.width > 0, viewBox.height > 0 {
            if let width, width > 0 {
                size = CGSize(width: width, height: width * viewBox.height / viewBox.width)
            } else if let height, height > 0 {
                size = CGSize(width: height * viewBox.width / viewBox.height, height: height)
            } else {
                size = viewBox
            }
        } else {
            size = CGSize(width: 300, height: 150)
        }
        parser.abortParsing()
    }

    private static func numberPrefix(_ value: String?) -> CGFloat? {
        guard let value, !value.contains("%") else { return nil }
        let scanner = Scanner(string: value)
        guard let number = scanner.scanDouble(), number.isFinite else { return nil }
        return CGFloat(number)
    }

    private static func viewBox(_ value: String?) -> CGSize? {
        guard let value else { return nil }
        let values = value.split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { Double($0) }
        guard values.count == 4, values[2].isFinite, values[3].isFinite else { return nil }
        return CGSize(width: values[2], height: values[3])
    }
}

private struct FFProbeRoot: Decodable {
    let streams: [FFProbeStream]
    let format: FFProbeFormat?
}

private struct FFProbeStream: Decodable {
    let codecType: String?
    let codecName: String?
    let width: Int?
    let height: Int?
    let duration: String?
    let avgFrameRate: String?
    let colorTransfer: String?
    let bitsPerRawSample: String?

    enum CodingKeys: String, CodingKey {
        case codecType = "codec_type", codecName = "codec_name", width, height, duration
        case avgFrameRate = "avg_frame_rate", colorTransfer = "color_transfer"
        case bitsPerRawSample = "bits_per_raw_sample"
    }
}

private struct FFProbeFormat: Decodable {
    let formatName: String?
    let duration: String?
    enum CodingKeys: String, CodingKey { case formatName = "format_name", duration }
}
