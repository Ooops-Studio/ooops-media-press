import Foundation
import CoreGraphics

enum MediaKind: String, Codable, Sendable {
    case image
    case animatedImage
    case vectorImage
    case video
}

enum JobState: String, Codable, Sendable {
    case pending, probing, previewing, ready, processing, completed, failed, cancelled
}

struct MediaProbe: Codable, Equatable, Sendable {
    var kind: MediaKind
    var format: String
    var width: Int
    var height: Int
    var duration: Double?
    var frameRate: Double?
    var codec: String?
    var hasAudio: Bool
    var isHDR: Bool
    var isAnimated: Bool
    var byteCount: Int64

    var dimensions: CGSize { CGSize(width: width, height: height) }
}

enum ImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case jpeg, png, heic, avif, webp
    var id: String { rawValue }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var supportsLossyQuality: Bool { self != .png }
}

enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264, hevc, vp9
    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264: return "MP4 (H.264)"
        case .hevc: return "MP4 (HEVC)"
        case .vp9: return "WebM (VP9)"
        }
    }

    var fileExtension: String { self == .vp9 ? "webm" : "mp4" }
}

enum ResizeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage, dimensions
    var id: String { rawValue }
}

struct ResizeSettings: Codable, Equatable, Sendable {
    var mode: ResizeMode = .dimensions
    var percentage: Double = 100
    var width: Int = 1920
    var height: Int = 1080
    var retainAspectRatio: Bool = true

    func outputSize(for input: CGSize) -> CGSize {
        guard input.width > 0, input.height > 0 else { return input }
        switch mode {
        case .percentage:
            let scale = max(0.01, percentage / 100)
            return CGSize(width: max(1, (input.width * scale).rounded()),
                          height: max(1, (input.height * scale).rounded()))
        case .dimensions:
            guard retainAspectRatio else {
                return CGSize(width: max(1, width), height: max(1, height))
            }
            let scale = min(CGFloat(width) / input.width, CGFloat(height) / input.height)
            return CGSize(width: max(1, (input.width * scale).rounded()),
                          height: max(1, (input.height * scale).rounded()))
        }
    }
}

struct ImageOutputSettings: Codable, Equatable, Sendable {
    var format: ImageFormat = .jpeg
    var resize = ResizeSettings()
    var quality: Double = 0.78
    var targetBytes: Int64? = 500_000
    var stripSensitiveMetadata: Bool = true
}

struct VideoOutputSettings: Codable, Equatable, Sendable {
    var codec: VideoCodec = .h264
    var resize = ResizeSettings()
    var quality: Double = 0.72
    var targetBytes: Int64? = 20_000_000
    var keepAudio: Bool = true
}

enum SVGOptimizationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case safe, balanced, aggressive

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SVGOutputSettings: Codable, Equatable, Sendable {
    var preset: SVGOptimizationPreset = .balanced
    var decimalPrecision: Int = 3
    var multipass: Bool = true
    var simplifyPaths: Bool = true
    var preserveAccessibility: Bool = true
    var preserveIDsAndCSS: Bool = true
    var removeMetadata: Bool = true

    static func defaults(for preset: SVGOptimizationPreset) -> SVGOutputSettings {
        switch preset {
        case .safe:
            return SVGOutputSettings(preset: .safe, decimalPrecision: 4, multipass: false,
                                     simplifyPaths: false, preserveAccessibility: true,
                                     preserveIDsAndCSS: true, removeMetadata: true)
        case .balanced:
            return SVGOutputSettings()
        case .aggressive:
            return SVGOutputSettings(preset: .aggressive, decimalPrecision: 2, multipass: true,
                                     simplifyPaths: true, preserveAccessibility: false,
                                     preserveIDsAndCSS: false, removeMetadata: true)
        }
    }
}

enum OutputSettings: Codable, Equatable, Sendable {
    case image(ImageOutputSettings)
    case svg(SVGOutputSettings)
    case video(VideoOutputSettings)
}

struct PreviewArtifact: Sendable, Equatable {
    var outputURL: URL
    var byteCount: Int64
    var proxyStart: Double = 0
    var proxyDuration: Double?
}

struct MediaJob: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    var probe: MediaProbe?
    var settings: OutputSettings?
    var preview: PreviewArtifact?
    var destinationURL: URL?
    var progress: Double
    var state: JobState
    var errorMessage: String?

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.progress = 0
        self.state = .pending
    }
}
