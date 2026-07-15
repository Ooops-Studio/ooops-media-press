import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var jobs: [MediaJob] = []
    @Published var selectedID: UUID?
    @Published var dropIsTargeted = false
    @Published var statusMessage: String?
    @Published var outputDirectory: URL?

    private let runner = ProcessRunner()
    private lazy var probeService = MediaProbeService(runner: runner)
    private lazy var imageProcessor = ImageProcessor(runner: runner)
    private let svgProcessor = SVGProcessor()
    private lazy var videoProcessor = VideoProcessor(runner: runner)
    private let imageLimiter = WorkLimiter(limit: 4)
    private let videoLimiter = WorkLimiter(limit: 1)
    private var previewTasks: [UUID: Task<Void, Never>] = [:]
    private var exportTasks: [UUID: Task<Void, Never>] = [:]
    private var playheads: [UUID: Double] = [:]
    private var retiredVideoPreviews: [UUID: URL] = [:]

    init() {
        cleanupTemporaryFiles()
    }

    var selectedJob: MediaJob? { jobs.first { $0.id == selectedID } }
    var isExporting: Bool { jobs.contains { $0.state == .processing } }
    var overallProgress: Double {
        let active = jobs.filter { $0.state == .processing }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }
    var completedSavings: Int64 {
        jobs.compactMap { job -> Int64? in
            guard job.state == .completed, let output = job.destinationURL else { return nil }
            return max(0, (job.probe?.byteCount ?? 0) - output.fileByteCount)
        }.reduce(0, +)
    }

    func addURLs(_ urls: [URL]) {
        let files = urls.flatMap(expandURL).filter { candidate in
            !jobs.contains { $0.sourceURL.standardizedFileURL == candidate.standardizedFileURL }
        }
        guard !files.isEmpty else { return }
        let newJobs = files.map(MediaJob.init(sourceURL:))
        jobs.append(contentsOf: newJobs)
        if selectedID == nil { selectedID = newJobs.first?.id }
        for job in newJobs { beginProbe(job.id) }
    }

    func importFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addURLs(urls)
            return
        }
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation else {
            statusMessage = "The clipboard does not contain supported media."
            return
        }
        let url = temporaryDirectory.appendingPathComponent("Pasted-\(UUID().uuidString).tiff")
        do {
            try tiff.write(to: url)
            addURLs([url])
        } catch { statusMessage = error.localizedDescription }
    }

    func chooseInputFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK { addURLs(panel.urls) }
    }

    func addDroppedMediaData(_ data: Data, typeIdentifier: String) {
        guard !data.isEmpty else { return }
        let pathExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "data"
        let url = temporaryDirectory
            .appendingPathComponent("Dropped-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        do {
            try data.write(to: url, options: .atomic)
            addURLs([url])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func remove(_ id: UUID) {
        guard let removedIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
        previewTasks[id]?.cancel()
        exportTasks[id]?.cancel()
        previewTasks[id] = nil
        exportTasks[id] = nil
        playheads[id] = nil
        if let preview = jobs.first(where: { $0.id == id })?.preview { try? FileManager.default.removeItem(at: preview.outputURL) }
        if let retiredPreview = retiredVideoPreviews.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: retiredPreview)
        }
        jobs.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = jobs.isEmpty ? nil : jobs[min(removedIndex, jobs.count - 1)].id
        }
    }

    func removeSelected() {
        guard let selectedID else { return }
        remove(selectedID)
    }

    func select(_ id: UUID) { selectedID = id }

    func settings(for id: UUID) -> OutputSettings? { jobs.first { $0.id == id }?.settings }

    func updateSettings(_ settings: OutputSettings, for id: UUID) {
        mutate(id) { $0.settings = settings }
        schedulePreview(id)
    }

    func setPlayhead(_ seconds: Double, for id: UUID) {
        playheads[id] = seconds
    }

    func regenerateVideoPreview(_ id: UUID) { schedulePreview(id, immediate: true) }

    func exportSelected() {
        guard let id = selectedID else { return }
        export(id)
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }

    func exportAll() {
        jobs.filter { $0.probe != nil && $0.settings != nil && $0.state != .processing }.forEach { export($0.id) }
    }

    func cancelAll() {
        previewTasks.values.forEach { $0.cancel() }
        exportTasks.values.forEach { $0.cancel() }
        runner.cancelAll()
        for job in jobs where job.state == .processing || job.state == .previewing {
            mutate(job.id) { $0.state = .cancelled }
        }
    }

    private func beginProbe(_ id: UUID) {
        mutate(id) { $0.state = .probing }
        guard let source = jobs.first(where: { $0.id == id })?.sourceURL else { return }
        Task {
            do {
                let probe = try await probeService.probe(source)
                mutate(id) { job in
                    job.probe = probe
                    job.settings = Self.defaultSettings(for: probe)
                    job.state = .ready
                }
                schedulePreview(id, immediate: true)
            } catch {
                mutate(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }
            }
        }
    }

    private func schedulePreview(_ id: UUID, immediate: Bool = false) {
        previewTasks[id]?.cancel()
        previewTasks[id] = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 500_000_000) }
            guard !Task.isCancelled else { return }
            await self?.generatePreview(id)
        }
    }

    private func generatePreview(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }), let probe = job.probe, let settings = job.settings,
              job.state != .processing else { return }
        mutate(id) { $0.state = .previewing; $0.errorMessage = nil }
        let ext: String
        switch settings {
        case .image(let image): ext = probe.isAnimated ? "webp" : image.format.fileExtension
        case .svg: ext = "svg"
        case .video: ext = "mp4"
        }
        let output = temporaryDirectory.appendingPathComponent("preview-\(id.uuidString)-\(UUID().uuidString).\(ext)")
        do {
            let artifact: PreviewArtifact
            switch settings {
            case .image(var image):
                if probe.isAnimated { image.format = .webp }
                artifact = try await imageProcessor.render(source: job.sourceURL, settings: image, destination: output)
            case .svg(let svg):
                artifact = try await svgProcessor.render(source: job.sourceURL, settings: svg, destination: output)
            case .video(let video):
                artifact = try await videoProcessor.renderProxy(source: job.sourceURL, probe: probe, settings: video,
                                                                 playhead: playheads[id] ?? 0, destination: output)
            }
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: output); return }
            let old = jobs.first(where: { $0.id == id })?.preview?.outputURL
            mutate(id) { $0.preview = artifact; $0.state = .ready }
            if let old, old != output {
                if probe.kind == .video {
                    if let retiredPreview = retiredVideoPreviews.updateValue(old, forKey: id) {
                        try? FileManager.default.removeItem(at: retiredPreview)
                    }
                } else {
                    try? FileManager.default.removeItem(at: old)
                }
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: output)
        } catch {
            mutate(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }
            try? FileManager.default.removeItem(at: output)
        }
    }

    private func export(_ id: UUID) {
        guard exportTasks[id] == nil, let job = jobs.first(where: { $0.id == id }),
              let probe = job.probe, let settings = job.settings else { return }
        previewTasks[id]?.cancel()
        let converted = outputDirectory ?? job.sourceURL.deletingLastPathComponent().appendingPathComponent("Converted", isDirectory: true)
        do { try FileManager.default.createDirectory(at: converted, withIntermediateDirectories: true) }
        catch { mutate(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }; return }
        let ext: String
        switch settings {
        case .image(let image): ext = probe.isAnimated ? "webp" : image.format.fileExtension
        case .svg: ext = "svg"
        case .video(let video): ext = video.codec.fileExtension
        }
        let destination = job.sourceURL.uniqueSibling(in: converted, extension: ext)
        mutate(id) { $0.state = .processing; $0.progress = 0; $0.destinationURL = destination }
        exportTasks[id] = Task { [weak self] in
            guard let self else { return }
            let limiter = probe.kind == .video || probe.kind == .animatedImage ? videoLimiter : imageLimiter
            await limiter.acquire()
            do {
                switch settings {
                case .image(var image):
                    mutate(id) { $0.progress = 0.1 }
                    if probe.isAnimated { image.format = .webp }
                    _ = try await imageProcessor.render(source: job.sourceURL, settings: image, destination: destination)
                case .svg(let svg):
                    mutate(id) { $0.progress = 0.1 }
                    _ = try await svgProcessor.render(source: job.sourceURL, settings: svg, destination: destination)
                case .video(let video):
                    _ = try await videoProcessor.render(source: job.sourceURL, probe: probe, settings: video, destination: destination) { [weak self] value in
                        Task { @MainActor in self?.mutate(id) { $0.progress = value } }
                    }
                }
                mutate(id) { $0.state = .completed; $0.progress = 1 }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: destination)
                mutate(id) { $0.state = .cancelled }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                mutate(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }
            }
            await limiter.release()
            exportTasks[id] = nil
        }
    }

    private func mutate(_ id: UUID, _ body: (inout MediaJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        body(&jobs[index])
    }

    private func expandURL(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }
    }

    private var temporaryDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OoopsMediaPress", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanupTemporaryFiles() {
        let directory = temporaryDirectory
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func defaultSettings(for probe: MediaProbe) -> OutputSettings {
        let sourceSize = ResizeSettings(
            mode: .dimensions,
            width: max(1, probe.width),
            height: max(1, probe.height)
        )
        switch probe.kind {
        case .video:
            return .video(.init(codec: .h264, resize: sourceSize))
        case .animatedImage:
            return .image(.init(format: .webp, resize: sourceSize, quality: 0.78))
        case .vectorImage:
            return .svg(.defaults(for: .balanced))
        case .image:
            return .image(.init(format: .jpeg, resize: sourceSize, quality: 0.78))
        }
    }
}

private actor WorkLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { active = max(0, active - 1) }
        else { waiters.removeFirst().resume() }
    }
}
