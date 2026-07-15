import Foundation

struct ProcessResult: Sendable {
    let stdout: Data
    let stderr: Data
    let status: Int32

    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var running: [UUID: Process] = [:]

    func run(executable: URL, arguments: [String], stdoutChunk: (@Sendable (Data) -> Void)? = nil) async throws -> ProcessResult {
        let identifier = UUID()
        let cancellation = CancellationState()
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        let streamedOutput = OutputBuffer()
        if let stdoutChunk {
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                streamedOutput.append(data)
                stdoutChunk(data)
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] process in
                    output.fileHandleForReading.readabilityHandler = nil
                    let tail = output.fileHandleForReading.readDataToEndOfFile()
                    if stdoutChunk != nil { streamedOutput.append(tail); stdoutChunk?(tail) }
                    let stdout = stdoutChunk == nil ? tail : streamedOutput.data
                    let stderr = error.fileHandleForReading.readDataToEndOfFile()
                    self?.lock.withLock { self?.running.removeValue(forKey: identifier) }
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: ProcessResult(stdout: stdout, stderr: stderr, status: 0))
                    } else if cancellation.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: MediaPressError.processingFailed(String(decoding: stderr, as: UTF8.self)))
                    }
                }
                do {
                    lock.withLock { running[identifier] = process }
                    try process.run()
                    if cancellation.isCancelled, process.isRunning {
                        process.terminate()
                    }
                } catch {
                    lock.withLock { running.removeValue(forKey: identifier) }
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: { [weak self] in
            cancellation.cancel()
            self?.lock.withLock {
                guard let process = self?.running[identifier], process.isRunning else { return }
                process.terminate()
            }
        }
    }

    func cancelAll() {
        lock.withLock {
            running.values.filter(\.isRunning).forEach { $0.terminate() }
            running.removeAll()
        }
    }
}

private final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ data: Data) { lock.withLock { storage.append(data) } }
    var data: Data { lock.withLock { storage } }
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
