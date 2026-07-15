import SwiftUI
import Sparkle

@main
struct OoopsMediaPressApp: App {
    @StateObject private var model = AppModel()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup("Ooops Media Press") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 900, idealWidth: 1320, minHeight: 640, idealHeight: 820)
        }
        .commands {
            CommandMenu("Media") {
                Button("Import Media…") { model.chooseInputFiles() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Paste Media") { model.importFromPasteboard() }
                    .keyboardShortcut("v", modifiers: [.command])
                Button("Export Selected") { model.exportSelected() }
                    .keyboardShortcut("e", modifiers: [.command])
                Button("Export All") { model.exportAll() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.jobs.isEmpty)
                Button("Choose Output Folder…") { model.chooseOutputDirectory() }
                Divider()
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
            CommandGroup(after: .sidebar) {
                Button("Show/Hide Sidebar") {
                    NotificationCenter.default.post(name: .toggleMediaSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button("Show/Hide Inspector") {
                    NotificationCenter.default.post(name: .toggleMediaInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        Settings {
            SettingsView(updater: updaterController.updater)
                .environmentObject(model)
        }
    }
}

private struct SettingsView: View {
    let updater: SPUUpdater
    @AppStorage("automaticallyChecksForUpdates") private var automaticUpdates = true

    var body: some View {
        Form {
            Toggle("Automatically check for updates", isOn: $automaticUpdates)
                .onChange(of: automaticUpdates) { value in updater.automaticallyChecksForUpdates = value }
            Text("Media processing is always local. Update checks are the app's only network activity.")
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }
}
