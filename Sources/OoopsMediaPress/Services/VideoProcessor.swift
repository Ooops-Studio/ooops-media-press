import Foundation
import CoreGraphics

protocol VideoProcessing: Sendable {
    func render(source: URL, probe: MediaProbe, settings: VideoOutputSettings, destination: URL,
                progress: @escaping @Sendable (Double) -> Void) async throws -> PreviewArtifact
    func renderProxy(source: URL, probe: MediaProbe, settings: VideoOutputSettings, playhead: Double, destination: URL) async throws -> PreviewArtifact
}

struct VideoProcessor: VideoProcessing {
    let runner: ProcessRunner

    func render(source: URL, probe: MediaProbe, settings: VideoOutputSettings, destination: URL,
                progress: @escaping @Sendable (Double) -> Void) async throws -> PreviewArtifact {
        let tools = try FFmpegLocator.locate()
        if let target = settings.targetBytes {
            try await renderTwoPass(tools: tools, source: source, probe: probe, settings: settings, target: target, destination: destination, progress: progress)
        } else {
            var args = baseArguments(source: source, probe: probe, settings: settings)
            args += videoArguments(settings: settings, probe: probe, proxy: false)
            args += audioArguments(settings)
            args += containerArguments(settings.codec)
            args += ["-map_metadata", "-1", destination.path]
            try await runWithProgress(tools: tools, arguments: args, duration: probe.duration ?? 1, progress: progress)
        }
        return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
    }

    func renderProxy(source: URL, probe: MediaProbe, settings: VideoOutputSettings, playhead: Double, destination: URL) async throws -> PreviewArtifact {
        let tools = try FFmpegLocator.locate()
        let duration = min(8, probe.duration ?? 8)
        let maxStart = max(0, (probe.duration ?? duration) - duration)
        let start = min(max(0, playhead - duration / 2), maxStart)
        var proxySettings = settings
        proxySettings.targetBytes = nil
        proxySettings.resize = Self.proxyResizeSettings(probe: probe, settings: settings)
        let encodedDestination = settings.codec == .vp9
            ? destination.deletingPathExtension().appendingPathExtension("encoded.webm")
            : destination
        defer {
            if encodedDestination != destination { try? FileManager.default.removeItem(at: encodedDestination) }
        }
        var args = ["-y", "-ss", String(start), "-t", String(duration), "-i", source.path]
        args += filterArguments(probe: probe, settings: proxySettings)
        args += videoArguments(settings: proxySettings, probe: probe, proxy: true)
        args += audioArguments(settings)
        args += containerArguments(settings.codec)
        args += ["-map_metadata", "-1", encodedDestination.path]
        _ = try await runner.run(executable: tools.ffmpeg, arguments: args)
        let encodedByteCount = encodedDestination.fileByteCount
        if settings.codec == .vp9 {
            var playbackArguments = ["-y", "-i", encodedDestination.path, "-map", "0:v:0", "-map", "0:a?"]
            if probe.isHDR {
                playbackArguments += ["-c:v", "hevc_videotoolbox", "-q:v", "100", "-pix_fmt", "p010le", "-tag:v", "hvc1"]
            } else {
                playbackArguments += ["-c:v", "h264_videotoolbox", "-q:v", "100", "-tag:v", "avc1"]
            }
            playbackArguments += settings.keepAudio ? ["-c:a", "aac", "-b:a", "160k"] : ["-an"]
            playbackArguments += ["-movflags", "+faststart", "-map_metadata", "-1", destination.path]
            _ = try await runner.run(executable: tools.ffmpeg, arguments: playbackArguments)
        }
        return PreviewArtifact(outputURL: destination, byteCount: encodedByteCount, proxyStart: start, proxyDuration: duration)
    }

    static func videoToolboxQuality(_ quality: Double) -> Int {
        min(100, max(1, Int((quality * 100).rounded())))
    }

    static func vp9CRF(_ quality: Double) -> Int {
        min(63, max(0, Int(((1 - quality) * 63).rounded())))
    }

    static func proxyResizeSettings(probe: MediaProbe, settings: VideoOutputSettings) -> ResizeSettings {
        let requested = settings.resize.outputSize(for: probe.dimensions)
        guard requested.width > 0, requested.height > 0 else {
            return ResizeSettings(mode: .dimensions, width: 1280, height: 720)
        }
        let viewportScale = min(1, 1280 / requested.width, 720 / requested.height)
        let width = max(2, Int((requested.width * viewportScale).rounded()))
        let height = max(2, Int((requested.height * viewportScale).rounded()))
        return ResizeSettings(mode: .dimensions, width: width, height: height, retainAspectRatio: false)
    }

    private func renderTwoPass(tools: FFmpegTools, source: URL, probe: MediaProbe, settings: VideoOutputSettings, target: Int64,
                               destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let duration = probe.duration, duration > 0 else { throw MediaPressError.invalidMedia("Missing duration") }
        let audioRate = settings.keepAudio && probe.hasAudio ? (settings.codec == .vp9 ? 128_000 : 160_000) : 0
        let overheadAllowance = settings.codec == .vp9 ? 0.99 : 0.97
        let totalBits = Double(target) * 8 * overheadAllowance
        let videoRate = Int(totalBits / duration) - audioRate
        guard videoRate >= 100_000 else { throw MediaPressError.targetImpossible }
        let passlog = FileManager.default.temporaryDirectory.appendingPathComponent("media-press-\(UUID().uuidString)").path
        defer {
            for suffix in ["-0.log", "-0.log.mbtree"] { try? FileManager.default.removeItem(atPath: passlog + suffix) }
        }
        let encoder: String
        switch settings.codec {
        case .h264: encoder = "libx264"
        case .hevc: encoder = "libx265"
        case .vp9: encoder = "libvpx-vp9"
        }
        var first = baseArguments(source: source, probe: probe, settings: settings)
        first += ["-c:v", encoder, "-b:v", String(videoRate), "-pass", "1", "-passlogfile", passlog, "-an", "-f", "null", "/dev/null"]
        if settings.codec == .vp9 {
            first.insert(contentsOf: vp9CompatibilityArguments(probe: probe) + ["-deadline", "good", "-cpu-used", "2", "-row-mt", "1"], at: first.count - 4)
        }
        try await runWithProgress(tools: tools, arguments: first, duration: duration, offset: 0, scale: 0.5, progress: progress)
        var second = baseArguments(source: source, probe: probe, settings: settings)
        second += ["-c:v", encoder, "-b:v", String(videoRate), "-pass", "2", "-passlogfile", passlog]
        if settings.codec == .vp9 { second += vp9CompatibilityArguments(probe: probe) + ["-deadline", "good", "-cpu-used", "2", "-row-mt", "1"] }
        second += audioArguments(settings)
        second += containerArguments(settings.codec)
        second += ["-map_metadata", "-1", destination.path]
        try await runWithProgress(tools: tools, arguments: second, duration: duration, offset: 0.5, scale: 0.5, progress: progress)
    }

    private func baseArguments(source: URL, probe: MediaProbe, settings: VideoOutputSettings) -> [String] {
        ["-y", "-i", source.path] + filterArguments(probe: probe, settings: settings)
    }

    private func filterArguments(probe: MediaProbe, settings: VideoOutputSettings) -> [String] {
        let size = settings.resize.outputSize(for: probe.dimensions)
        let scaledWidth = max(2, Int(size.width / 2) * 2)
        let scaledHeight = max(2, Int(size.height / 2) * 2)
        let scale = settings.resize.mode == .dimensions && !settings.resize.retainAspectRatio
            ? "scale=\(scaledWidth):\(scaledHeight)"
            : "scale=\(scaledWidth):\(scaledHeight):force_original_aspect_ratio=decrease"
        var filters = [scale]
        if probe.isHDR && settings.codec == .h264 {
            filters = ["zscale=t=linear:npl=100", "tonemap=hable:desat=0", "zscale=p=bt709:t=bt709:m=bt709", filters[0]]
        }
        return ["-vf", filters.joined(separator: ",")]
    }

    private func videoArguments(settings: VideoOutputSettings, probe: MediaProbe, proxy: Bool) -> [String] {
        switch settings.codec {
        case .h264:
            return ["-c:v", "h264_videotoolbox", "-q:v", String(Self.videoToolboxQuality(settings.quality)), "-tag:v", "avc1"]
        case .hevc:
            return ["-c:v", "hevc_videotoolbox", "-q:v", String(Self.videoToolboxQuality(settings.quality)), "-tag:v", "hvc1"]
        case .vp9:
            return ["-c:v", "libvpx-vp9", "-crf", String(Self.vp9CRF(settings.quality)), "-b:v", "0",
                    "-deadline", "good", "-cpu-used", proxy ? "5" : "2", "-row-mt", "1"]
                + vp9CompatibilityArguments(probe: probe)
        }
    }

    private func vp9CompatibilityArguments(probe: MediaProbe) -> [String] {
        probe.isHDR ? ["-pix_fmt", "yuv420p10le", "-profile:v", "2"] : ["-pix_fmt", "yuv420p"]
    }

    private func containerArguments(_ codec: VideoCodec) -> [String] {
        codec == .vp9 ? ["-f", "webm"] : ["-movflags", "+faststart"]
    }

    private func audioArguments(_ settings: VideoOutputSettings) -> [String] {
        guard settings.keepAudio else { return ["-an"] }
        return settings.codec == .vp9
            ? ["-c:a", "libopus", "-b:a", "128k"]
            : ["-c:a", "aac", "-b:a", "160k"]
    }

    private func runWithProgress(tools: FFmpegTools, arguments: [String], duration: Double, offset: Double = 0, scale: Double = 1,
                                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let parser = FFmpegProgressParser(duration: duration) { value in progress(offset + value * scale) }
        var args = arguments
        args.insert(contentsOf: ["-progress", "pipe:1", "-nostats"], at: max(0, args.count - 1))
        _ = try await runner.run(executable: tools.ffmpeg, arguments: args) { parser.consume($0) }
        progress(offset + scale)
    }
}

private final class FFmpegProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private let duration: Double
    private let callback: @Sendable (Double) -> Void
    private var buffer = ""

    init(duration: Double, callback: @escaping @Sendable (Double) -> Void) {
        self.duration = max(0.001, duration)
        self.callback = callback
    }

    func consume(_ data: Data) {
        lock.lock()
        buffer += String(decoding: data, as: UTF8.self)
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        buffer = String(lines.last ?? "")
        let complete = lines.dropLast().map(String.init)
        lock.unlock()
        for line in complete where line.hasPrefix("out_time_us=") {
            if let microseconds = Double(line.dropFirst("out_time_us=".count)) {
                callback(min(1, max(0, microseconds / 1_000_000 / duration)))
            }
        }
    }
}
