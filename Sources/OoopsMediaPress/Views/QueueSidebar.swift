import SwiftUI
import ImageIO
import AVFoundation

struct QueueSidebar: View {
    @EnvironmentObject private var model: AppModel
    var showsSidebarToggle = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsSidebarToggle {
                    Button(action: toggleSidebar) { Image(systemName: "sidebar.left") }
                        .buttonStyle(HoverPlainButtonStyle())
                        .help("Hide Sidebar")
                }
                Text("Queue").font(.headline)
                Spacer()
                Button(action: model.chooseInputFiles) { Image(systemName: "plus") }
                    .buttonStyle(HoverCircleButtonStyle())
                    .help("Add media")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            List(selection: $model.selectedID) {
                ForEach(model.jobs) { job in
                    QueueRow(job: job) { model.remove(job.id) }
                        .tag(job.id)
                        .contextMenu { Button("Remove from Queue") { model.remove(job.id) } }
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand(perform: model.removeSelected)
        }
        .mediaDropTarget(model)
    }

    private func toggleSidebar() {
        NotificationCenter.default.post(name: .toggleMediaSidebar, object: nil)
    }

}

private struct QueueRow: View {
    let job: MediaJob
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            QueueThumbnail(job: job)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent).lineLimit(1)
                HStack(spacing: 5) {
                    Text(job.probe?.byteCount.formattedBytes ?? "Inspecting…")
                    Text("•")
                    Text(job.state.rawValue.capitalized)
                }
                .font(.caption)
                .foregroundColor(job.state == .failed ? .red : .secondary)
            }
            Spacer(minLength: 0)
            if isHovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(HoverPlainButtonStyle(padding: 3, cornerRadius: 6))
                .help("Remove from Queue")
                .accessibilityLabel("Remove from Queue")
            } else if job.state == .previewing || job.state == .processing || job.state == .probing {
                ProgressView().controlSize(.small)
            } else if job.state == .completed {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovering = $0 }
    }

}

private struct QueueThumbnail: View {
    let job: MediaJob
    @StateObject private var loader = QueueThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let thumbnail = loader.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholderName)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onAppear { loader.load(url: job.sourceURL, kind: job.probe?.kind) }
        .onChange(of: job.sourceURL) { url in loader.load(url: url, kind: job.probe?.kind) }
        .onChange(of: job.probe?.kind) { kind in loader.load(url: job.sourceURL, kind: kind) }
        .onDisappear(perform: loader.cancel)
        .accessibilityHidden(true)
    }

    private var placeholderName: String {
        switch job.probe?.kind {
        case .video: return "film"
        case .vectorImage: return "scribble.variable"
        default: return "photo"
        }
    }

}

@MainActor
private final class QueueThumbnailLoader: ObservableObject {
    @Published private(set) var thumbnail: NSImage?
    private var videoGenerator: AVAssetImageGenerator?
    private var representedURL: URL?
    private var representedKind: MediaKind?

    func load(url: URL, kind: MediaKind?) {
        guard representedURL != url || representedKind != kind || thumbnail == nil else { return }
        cancel()
        representedURL = url
        representedKind = kind
        thumbnail = nil

        if kind == .video {
            loadVideoThumbnail(url: url)
        } else {
            loadImageThumbnail(url: url)
        }
    }

    func cancel() {
        videoGenerator?.cancelAllCGImageGeneration()
        videoGenerator = nil
    }

    private func loadImageThumbnail(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            thumbnail = NSImage(contentsOf: url)
            return
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
        thumbnail = NSImage(cgImage: image, size: .zero)
    }

    private func loadVideoThumbnail(url: URL) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 96, height: 96)
        videoGenerator = generator
        let time = NSValue(time: .zero)

        generator.generateCGImagesAsynchronously(forTimes: [time]) { [weak self] _, image, _, result, _ in
            guard result == .succeeded, let image else { return }
            let representation = NSBitmapImageRep(cgImage: image)
            guard let data = representation.representation(using: .png, properties: [:]) else { return }
            Task { @MainActor [weak self] in
                guard self?.representedURL == url, self?.representedKind == .video else { return }
                self?.thumbnail = NSImage(data: data)
                self?.videoGenerator = nil
            }
        }
    }
}
