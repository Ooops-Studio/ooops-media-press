import SwiftUI
import AVKit

struct ComparisonWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var divider = 0.5

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                EmptyWorkspace()
            } else if let job = model.selectedJob, let probe = job.probe {
                VStack(spacing: 12) {
                    comparison(for: job, probe: probe)
                    ComparisonStats(job: job)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                    Text("Select media").font(.headline)
                    Text("Choose an item from the queue.").foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func comparison(for job: MediaJob, probe: MediaProbe) -> some View {
        ZStack(alignment: .top) {
            if probe.kind == .video, let preview = job.preview {
                VideoComparator(source: job.sourceURL, preview: preview, divider: $divider) { playhead in
                    model.setPlayhead(playhead, for: job.id)
                }
                .id(preview.outputURL)
            } else if let preview = job.preview,
                      let original = NSImage(contentsOf: job.sourceURL),
                      let compressed = NSImage(contentsOf: preview.outputURL) {
                ImageComparator(original: original, compressed: compressed, divider: $divider)
            } else if let original = NSImage(contentsOf: job.sourceURL) {
                Image(nsImage: original).resizable().aspectRatio(contentMode: .fit).padding(30)
            } else {
                ProgressView("Generating preview…")
            }

            HStack {
                Text("Original").comparisonLabel()
                Spacer()
                Text(probe.kind == .vectorImage ? "Optimized" : "Compressed").comparisonLabel()
            }
            .padding(12)

            if job.state == .previewing {
                ProgressView().padding(8).adaptiveGlass(cornerRadius: 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct EmptyWorkspace: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 42, weight: .light))
                .foregroundColor(model.dropIsTargeted ? .accentColor : .secondary)
            Text("Drop or paste media")
                .font(.title2.weight(.semibold))
            Text("Images, SVGs and videos stay on this Mac")
                .foregroundColor(.secondary)
            Button("Choose Files…", action: model.chooseInputFiles)
                .buttonStyle(ProminentButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ImageComparator: View {
    let original: NSImage
    let compressed: NSImage
    @Binding var divider: Double
    @State private var zoom = 1.0
    @GestureState private var gestureZoom = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                image(original, in: geometry.size)
                image(compressed, in: geometry.size)
                    .mask(Rectangle()
                        .frame(width: compressedRevealWidth(in: geometry.size.width))
                        .frame(maxWidth: .infinity, alignment: .trailing))
                DividerHandle(divider: $divider, width: geometry.size.width)
            }
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .updating($gestureZoom) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoom = clampedZoom(zoom * value)
                    }
            )
            .onTapGesture(count: 2) { divider = 0.5 }
            .focusable()
            .onMoveCommand { direction in
                if direction == .left { divider = max(0, divider - 0.02) }
                if direction == .right { divider = min(1, divider + 0.02) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Before and after comparison")
        .accessibilityValue("Divider \(Int(divider * 100)) percent")
    }

    private func image(_ image: NSImage, in canvasSize: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(clampedZoom(zoom * gestureZoom))
    }

    private func clampedZoom(_ value: Double) -> Double {
        min(8, max(1, value))
    }

    private func compressedRevealWidth(in width: CGFloat) -> CGFloat {
        guard divider > 0 else { return width }
        guard divider < 1 else { return 0 }
        // Reveal one point underneath the two-point divider so mask antialiasing
        // can never create a visible seam beside the line.
        return min(width, width * (1 - divider) + 1)
    }
}

private struct DividerHandle: View {
    @Binding var divider: Double
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 2, height: geometry.size.height)
                Circle()
                    .fill(Color(NSColor.controlAccentColor))
                    .frame(width: 30, height: 30)
                    .scaleEffect(isHovering ? 1.1 : 1)
                    .shadow(color: Color.black.opacity(isHovering ? 0.2 : 0), radius: 4, y: 2)
                    .overlay(Image(systemName: "arrow.left.and.right")
                        .font(.caption.bold())
                        .foregroundColor(Color(NSColor.alternateSelectedControlTextColor)))
            }
            .position(x: width * divider, y: geometry.size.height / 2)
            .contentShape(Rectangle().inset(by: -15))
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .gesture(DragGesture(minimumDistance: 0).onChanged { divider = min(1, max(0, $0.location.x / width)) })
            .accessibilityAdjustableAction { direction in
                divider = min(1, max(0, divider + (direction == .increment ? 0.05 : -0.05)))
            }
        }
    }
}

private struct VideoComparator: View {
    let source: URL
    let preview: PreviewArtifact
    @Binding var divider: Double
    let playheadChanged: (Double) -> Void
    @StateObject private var playback = ComparisonPlayback()
    @State private var zoom = 1.0
    @GestureState private var gestureZoom = 1.0
    @State private var pan = CGSize.zero
    @State private var gesturePan = CGSize.zero
    @State private var panStartedOnDivider: Bool?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack {
                    ComparisonPlayerView(player: playback.original)
                        .scaleEffect(effectiveZoom)
                        .offset(effectivePan(in: geometry.size))
                    ComparisonPlayerView(player: playback.compressed)
                        .scaleEffect(effectiveZoom)
                        .offset(effectivePan(in: geometry.size))
                        .mask(Rectangle().frame(width: geometry.size.width * (1 - divider)).frame(maxWidth: .infinity, alignment: .trailing))
                    DividerHandle(divider: $divider, width: geometry.size.width)
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(zoomGesture(in: geometry.size))
                .simultaneousGesture(panGesture(in: geometry.size))
                HStack {
                    Button(action: playback.toggle) { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                    Slider(value: Binding(
                        get: { playback.position },
                        set: { playback.scrub(to: $0) }
                    ), in: 0...max(0.1, preview.proxyDuration ?? 8), onEditingChanged: { editing in
                        if editing {
                            playback.beginScrubbing()
                        } else {
                            playback.endScrubbing()
                            playheadChanged(preview.proxyStart + playback.position)
                        }
                    })
                    Text(String(format: "%.1fs", preview.proxyStart + playback.position))
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.94))
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { divider = 0.5 }
            .focusable()
            .onMoveCommand { direction in
                if direction == .left { divider = max(0, divider - 0.02) }
                if direction == .right { divider = min(1, divider + 0.02) }
            }
        }
        .onAppear { playback.configure(source: source, preview: preview) }
        .onChange(of: preview.outputURL) { _ in playback.configure(source: source, preview: preview) }
        .onDisappear { playback.stop() }
    }

    private var effectiveZoom: Double {
        clampedZoom(zoom * gestureZoom)
    }

    private func effectivePan(in size: CGSize) -> CGSize {
        clampedPan(
            CGSize(width: pan.width + gesturePan.width, height: pan.height + gesturePan.height),
            zoom: effectiveZoom,
            in: size
        )
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoom) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoom = clampedZoom(zoom * value)
                pan = clampedPan(pan, zoom: zoom, in: size)
                if zoom == 1 { pan = .zero }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if panStartedOnDivider == nil {
                    panStartedOnDivider = startsOnDivider(value.startLocation, width: size.width)
                }
                guard effectiveZoom > 1, panStartedOnDivider == false else {
                    gesturePan = .zero
                    return
                }
                gesturePan = value.translation
            }
            .onEnded { value in
                if effectiveZoom > 1, panStartedOnDivider == false {
                    let proposed = CGSize(
                        width: pan.width + value.translation.width,
                        height: pan.height + value.translation.height
                    )
                    pan = clampedPan(proposed, zoom: zoom, in: size)
                }
                gesturePan = .zero
                panStartedOnDivider = nil
            }
    }

    private func startsOnDivider(_ location: CGPoint, width: CGFloat) -> Bool {
        abs(location.x - width * divider) <= 30
    }

    private func clampedZoom(_ value: Double) -> Double {
        min(8, max(1, value))
    }

    private func clampedPan(_ value: CGSize, zoom: Double, in size: CGSize) -> CGSize {
        guard zoom > 1 else { return .zero }
        let maxX = size.width * (zoom - 1) / 2
        let maxY = size.height * (zoom - 1) / 2
        return CGSize(
            width: min(maxX, max(-maxX, value.width)),
            height: min(maxY, max(-maxY, value.height))
        )
    }
}

private struct ComparisonPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: ()) {
        playerView.player = nil
    }
}

@MainActor
private final class ComparisonPlayback: ObservableObject {
    let original = AVPlayer()
    let compressed = AVPlayer()
    @Published var isPlaying = false
    @Published var position = 0.0
    private var start = 0.0
    private var duration = 8.0
    private var observer: Any?
    private var isScrubbing = false
    private var resumeAfterScrubbing = false

    func configure(source: URL, preview: PreviewArtifact) {
        stop()
        start = preview.proxyStart
        duration = max(0.1, preview.proxyDuration ?? 8)
        position = 0
        original.replaceCurrentItem(with: AVPlayerItem(url: source))
        compressed.replaceCurrentItem(with: AVPlayerItem(url: preview.outputURL))
        original.isMuted = true
        compressed.isMuted = false
        original.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        compressed.seek(to: .zero)
        observer = compressed.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isScrubbing else { return }
                self.position = max(0, time.seconds)
                let expected = self.start + self.position
                if abs(self.original.currentTime().seconds - expected) > 0.04 {
                    self.original.seek(to: CMTime(seconds: expected, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }

    func toggle() {
        if isPlaying { original.pause(); compressed.pause() }
        else { original.play(); compressed.play() }
        isPlaying.toggle()
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        resumeAfterScrubbing = isPlaying
        original.pause()
        compressed.pause()
        isPlaying = false
    }

    func scrub(to seconds: Double) {
        let target = min(duration, max(0, seconds))
        position = target
        seekBoth(to: target)
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        let target = position
        let shouldResume = resumeAfterScrubbing
        seekBoth(to: target) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.position = target
                self.isScrubbing = false
                self.resumeAfterScrubbing = false
                if shouldResume {
                    self.original.play()
                    self.compressed.play()
                    self.isPlaying = true
                }
            }
        }
    }

    private func seekBoth(to seconds: Double, completion: (@Sendable () -> Void)? = nil) {
        let tolerance = CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
        original.seek(
            to: CMTime(seconds: start + seconds, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        )
        compressed.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { _ in completion?() }
    }

    func stop() {
        original.pause(); compressed.pause(); isPlaying = false
        isScrubbing = false
        resumeAfterScrubbing = false
        if let observer { compressed.removeTimeObserver(observer); self.observer = nil }
    }
}

private struct ComparisonStats: View {
    let job: MediaJob

    var body: some View {
        HStack(spacing: 18) {
            stat("Original", job.probe?.byteCount.formattedBytes ?? "—")
            Image(systemName: "arrow.right")
            stat(job.probe?.kind == .vectorImage ? "Optimized" : "Compressed", job.preview?.byteCount.formattedBytes ?? "—")
            Divider().frame(height: 28)
            stat("Dimensions", job.probe.map { "\($0.width) × \($0.height)" } ?? "—")
            Spacer()
            if let original = job.probe?.byteCount, let compressed = job.preview?.byteCount, original > 0 {
                Text("−\(Int((1 - Double(compressed) / Double(original)) * 100))%")
                    .font(.title3.bold()).foregroundColor(compressed <= original ? .green : .orange)
            }
        }
        .padding(12)
        .adaptiveGlass(cornerRadius: 14)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption).foregroundColor(.secondary); Text(value) }
    }
}

private extension View {
    func comparisonLabel() -> some View {
        self.font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5)
            .adaptiveGlass(cornerRadius: 12)
            .foregroundColor(.primary)
    }
}
