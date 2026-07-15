import XCTest
import AppKit
@testable import OoopsMediaPress

final class MediaModelsTests: XCTestCase {
    func testFinderDropFileURLDataIsDecoded() throws {
        let expected = URL(fileURLWithPath: "/tmp/ooops-drop-test.png")
        let data = try XCTUnwrap(expected.absoluteString.data(using: .utf8))

        XCTAssertEqual(MediaDropHandler.fileURL(from: data as NSData), expected)
    }

    func testDimensionsRetainAspectRatioWithinBounds() {
        let settings = ResizeSettings(mode: .dimensions, width: 1920, height: 1080)
        XCTAssertEqual(settings.outputSize(for: .init(width: 640, height: 480)), .init(width: 1440, height: 1080))
    }

    func testDimensionsCanIgnoreAspectRatio() {
        let settings = ResizeSettings(mode: .dimensions, width: 1920, height: 1080, retainAspectRatio: false)
        XCTAssertEqual(settings.outputSize(for: .init(width: 640, height: 480)), .init(width: 1920, height: 1080))
    }

    func testTargetSizeAndDimensionsAreTheDefaults() {
        XCTAssertEqual(ResizeSettings().mode, .dimensions)
        XCTAssertEqual(ImageOutputSettings().targetBytes, 500_000)
        XCTAssertEqual(VideoOutputSettings().targetBytes, 20_000_000)
    }

    func testVideoProxyHonorsPercentageWhileStayingInsideViewport() {
        let probe = MediaProbe(kind: .video, format: "mov", width: 1920, height: 1080,
                               duration: 8, frameRate: 30, codec: "h264", hasAudio: true,
                               isHDR: false, isAnimated: false, byteCount: 1_000_000)
        var settings = VideoOutputSettings()
        settings.resize = ResizeSettings(mode: .percentage, percentage: 50)

        let halfSize = VideoProcessor.proxyResizeSettings(probe: probe, settings: settings)
        XCTAssertEqual(halfSize.width, 960)
        XCTAssertEqual(halfSize.height, 540)

        settings.resize.percentage = 100
        let cappedSize = VideoProcessor.proxyResizeSettings(probe: probe, settings: settings)
        XCTAssertEqual(cappedSize.width, 1280)
        XCTAssertEqual(cappedSize.height, 720)
    }

    func testVideoToolboxQualityPercentageIsNotInverted() {
        XCTAssertEqual(VideoProcessor.videoToolboxQuality(0.35), 35)
        XCTAssertEqual(VideoProcessor.videoToolboxQuality(0.78), 78)
        XCTAssertEqual(VideoProcessor.videoToolboxQuality(1), 100)
        XCTAssertGreaterThan(VideoProcessor.videoToolboxQuality(1), VideoProcessor.videoToolboxQuality(0.35))
    }

    func testWebMUsesVP9ContainerAndQualityDirection() {
        XCTAssertEqual(VideoCodec.vp9.fileExtension, "webm")
        XCTAssertEqual(VideoCodec.vp9.title, "WebM (VP9)")
        XCTAssertGreaterThan(VideoProcessor.vp9CRF(0.35), VideoProcessor.vp9CRF(0.78))
        XCTAssertEqual(VideoProcessor.vp9CRF(1), 0)
    }

    func testCancelledProcessReportsCancellation() async throws {
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled preview process must not be reported as a processing failure")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testOutputConflictGetsSuffix() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("photo.png")
        let existing = directory.appendingPathComponent("photo.jpg")
        XCTAssertTrue(FileManager.default.createFile(atPath: existing.path, contents: Data()))
        XCTAssertEqual(source.uniqueSibling(in: directory, extension: "jpg").lastPathComponent, "photo-1.jpg")
    }

    func testInspectorHidesBeforePreviewWouldFallBelowMinimumWidth() {
        let state = WindowChromeState(sidebarVisible: true, inspectorVisible: true)
        XCTAssertFalse(state.layout(for: 1_099).showsInspector)
        XCTAssertTrue(state.layout(for: 1_100).showsInspector)
        XCTAssertEqual(state.layout(for: 1_100).previewWidth, WindowChromeState.minimumPreviewWidth)
    }

    func testHiddenSidebarMakesRoomForInspector() {
        let state = WindowChromeState(sidebarVisible: false, inspectorVisible: true)
        let layout = state.layout(for: 850)
        XCTAssertTrue(layout.showsInspector)
        XCTAssertEqual(layout.previewWidth, WindowChromeState.minimumPreviewWidth)
    }

    func testInspectorReturnsAfterResponsiveHideWhenPreferenceRemainsEnabled() {
        let state = WindowChromeState(sidebarVisible: true, inspectorVisible: true)
        XCTAssertFalse(state.layout(for: 900).showsInspector)
        XCTAssertTrue(state.layout(for: 1_320).showsInspector)
    }

    func testWindowChromeStateRestorationRoundTrip() throws {
        let state = WindowChromeState(sidebarVisible: false, inspectorVisible: true)
        XCTAssertEqual(WindowChromeState(rawValue: state.rawValue), state)
        XCTAssertNil(WindowChromeState(rawValue: "invalid"))
    }

    @MainActor
    func testWindowToolbarHasNoBottomSeparator() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.toolbar = NSToolbar(identifier: "ToolbarSeparatorTest")
        let configurationView = WindowConfigurationView(frame: .zero)
        window.contentView = configurationView
        configurationView.configureWindow()

        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        if #unavailable(macOS 15.0) {
            XCTAssertFalse(window.toolbar?.showsBaselineSeparator ?? true)
        }
    }

    func testSVGSettingsRoundTrip() throws {
        let settings = SVGOutputSettings.defaults(for: .aggressive)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(SVGOutputSettings.self, from: data), settings)
    }

    func testSVGProbeUsesViewBoxDimensions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("drawing.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 640 360\"><path d=\"M0 0h640v360H0z\"/></svg>"
            .write(to: source, atomically: true, encoding: .utf8)

        let probe = try await MediaProbeService(runner: ProcessRunner()).probe(source)
        XCTAssertEqual(probe.kind, .vectorImage)
        XCTAssertEqual(probe.format, "svg")
        XCTAssertEqual(probe.width, 640)
        XCTAssertEqual(probe.height, 360)
    }

    func testSVGOptimizationRemovesActiveAndExternalContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("unsafe.svg")
        let destination = directory.appendingPathComponent("optimized.svg")
        let input = """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
          <title>Accessible artwork</title>
          <metadata>Editor metadata that should be removed from the optimized document.</metadata>
          <script>alert('no')</script>
          <image href="https://example.com/tracker.png" width="20" height="20"/>
          <image href="data:image/svg+xml;base64,PHN2Zz48c2NyaXB0Lz48L3N2Zz4=" width="20" height="20"/>
          <foreignObject width="10" height="10"><div>HTML</div></foreignObject>
          <rect id="important-shape" onclick="alert('no')" x="0.0000" y="0.0000" width="200.0000" height="100.0000" fill="#ff0000"/>
        </svg>
        """
        try input.write(to: source, atomically: true, encoding: .utf8)

        let artifact = try await SVGProcessor().render(source: source, settings: .defaults(for: .balanced), destination: destination)
        let output = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertLessThan(artifact.byteCount, Int64(input.utf8.count))
        XCTAssertTrue(output.contains("<title>Accessible artwork</title>"))
        XCTAssertTrue(output.contains("viewBox="))
        XCTAssertTrue(output.contains("important-shape"))
        XCTAssertFalse(output.contains("<metadata"))
        XCTAssertFalse(output.contains("<script"))
        XCTAssertFalse(output.contains("onclick"))
        XCTAssertFalse(output.contains("example.com"))
        XCTAssertFalse(output.contains("image/svg+xml"))
        XCTAssertFalse(output.contains("foreignObject"))
        XCTAssertNotNil(NSImage(contentsOf: destination))
    }

    func testAggressiveSVGOptimizationCanRemoveAccessibilityAndIDs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("drawing.svg")
        let destination = directory.appendingPathComponent("optimized.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 20 20\"><title>Title</title><desc>Description</desc><path id=\"unused-long-id\" d=\"M0 0 L20 0 L20 20 L0 20 Z\"/></svg>"
            .write(to: source, atomically: true, encoding: .utf8)

        _ = try await SVGProcessor().render(source: source, settings: .defaults(for: .aggressive), destination: destination)
        let output = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertFalse(output.contains("<title"))
        XCTAssertFalse(output.contains("<desc"))
        XCTAssertFalse(output.contains("unused-long-id"))
    }
}
