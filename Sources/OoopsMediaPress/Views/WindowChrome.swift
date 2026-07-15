import CoreGraphics
import Foundation

struct WindowChromeState: RawRepresentable, Equatable, Sendable {
    static let minimumPreviewWidth: CGFloat = 480
    static let sidebarWidth: CGFloat = 250
    static let inspectorWidth: CGFloat = 330
    static let chromeSpacing: CGFloat = 40

    var sidebarVisible: Bool
    var inspectorVisible: Bool

    init(sidebarVisible: Bool = true, inspectorVisible: Bool = true) {
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
    }

    init?(rawValue: String) {
        let values = rawValue.split(separator: "|")
        guard values.count == 2 else { return nil }
        sidebarVisible = values[0] == "1"
        inspectorVisible = values[1] == "1"
    }

    var rawValue: String {
        "\(sidebarVisible ? 1 : 0)|\(inspectorVisible ? 1 : 0)"
    }

    func layout(for windowWidth: CGFloat) -> WindowChromeLayout {
        let showsSidebar = sidebarVisible && windowWidth >= 720
        let sidebarSpace = showsSidebar ? Self.sidebarWidth : 0
        let availableWithInspector = windowWidth - sidebarSpace - Self.inspectorWidth - Self.chromeSpacing
        let showsInspector = inspectorVisible && availableWithInspector >= Self.minimumPreviewWidth
        let previewWidth = max(0, windowWidth - sidebarSpace - (showsInspector ? Self.inspectorWidth + Self.chromeSpacing : 0))
        return WindowChromeLayout(showsSidebar: showsSidebar, showsInspector: showsInspector, previewWidth: previewWidth)
    }
}

struct WindowChromeLayout: Equatable, Sendable {
    var showsSidebar: Bool
    var showsInspector: Bool
    var previewWidth: CGFloat
}

extension Notification.Name {
    static let toggleMediaSidebar = Notification.Name("studio.ooops.OoopsMediaPress.toggleSidebar")
    static let toggleMediaInspector = Notification.Name("studio.ooops.OoopsMediaPress.toggleInspector")
}
