import Foundation

enum MediaPressError: LocalizedError {
    case unsupported(String)
    case invalidMedia(String)
    case processingFailed(String)
    case targetImpossible
    case toolMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let value): return "Unsupported media: \(value)"
        case .invalidMedia(let value): return "Invalid media: \(value)"
        case .processingFailed(let value): return value
        case .targetImpossible: return "The requested target size cannot be reached above the quality and dimension floor."
        case .toolMissing(let value): return "Required tool not found: \(value)"
        }
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    func uniqueSibling(in directory: URL, extension ext: String) -> URL {
        let base = deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    var fileByteCount: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}
