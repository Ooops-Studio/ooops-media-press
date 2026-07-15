import Foundation

struct FFmpegTools: Sendable {
    let ffmpeg: URL
    let ffprobe: URL
}

enum FFmpegLocator {
    static func locate() throws -> FFmpegTools {
        let names = ["ffmpeg", "ffprobe"]
        var found: [String: URL] = [:]
        for name in names {
            let bundledCandidates = [
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Tools/\(name)"),
                Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Tools"),
                Bundle.module.url(forResource: name, withExtension: nil)
            ].compactMap { $0 }
            if let bundled = bundledCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
                found[name] = bundled
            }
        }
        guard let ffmpeg = found["ffmpeg"] else { throw MediaPressError.toolMissing("ffmpeg") }
        guard let ffprobe = found["ffprobe"] else { throw MediaPressError.toolMissing("ffprobe") }
        return FFmpegTools(ffmpeg: ffmpeg, ffprobe: ffprobe)
    }
}
