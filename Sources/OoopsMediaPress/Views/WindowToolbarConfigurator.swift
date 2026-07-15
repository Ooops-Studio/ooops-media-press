import AppKit
import SwiftUI

struct WindowToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfigurationView {
        WindowConfigurationView(frame: .zero)
    }

    func updateNSView(_ view: WindowConfigurationView, context: Context) {
        view.configureWindow()
    }
}

final class WindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        if #unavailable(macOS 15.0) {
            window.toolbar?.showsBaselineSeparator = false
        }
    }
}
