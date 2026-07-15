import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("windowChrome.state") private var chromeState = WindowChromeState()

    var body: some View {
        GeometryReader { geometry in
            let layout = chromeState.layout(for: geometry.size.width)
            Group {
                if #available(macOS 13.0, *) {
                    ModernWindowLayout(chromeState: $chromeState, layout: layout)
                } else {
                    LegacyWindowLayout(chromeState: $chromeState, layout: layout)
                }
            }
        }
        .background(WindowToolbarConfigurator())
        .onReceive(NotificationCenter.default.publisher(for: .toggleMediaSidebar)) { _ in toggleSidebar() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMediaInspector)) { _ in toggleInspector() }
        .alert(isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
            Alert(title: Text("Ooops Media Press"), message: Text(model.statusMessage ?? ""), dismissButton: .default(Text("OK")) { model.statusMessage = nil })
        }
    }

    private func toggleSidebar() {
        var updated = chromeState
        updated.sidebarVisible.toggle()
        chromeState = updated
    }

    private func toggleInspector() {
        var updated = chromeState
        updated.inspectorVisible.toggle()
        chromeState = updated
    }
}

@available(macOS 13.0, *)
private struct ModernWindowLayout: View {
    @Binding var chromeState: WindowChromeState
    let layout: WindowChromeLayout
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                navigationContent
                    .inspector(isPresented: inspectorPresentation) {
                        InspectorSurface()
                            .inspectorColumnWidth(min: 300, ideal: 330, max: 360)
                    }
            } else {
                HSplitView {
                    navigationContent
                    if layout.showsInspector {
                        InspectorSurface().frame(minWidth: 300, idealWidth: 330, maxWidth: 360)
                    }
                }
            }
        }
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { synchronizeSidebar() }
        .onChange(of: chromeState.sidebarVisible) { _ in synchronizeSidebar() }
        .onChange(of: layout.showsSidebar) { _ in synchronizeSidebar() }
    }

    private var navigationContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            QueueSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            WorkspaceDetail()
        }
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding(
            get: { layout.showsInspector },
            set: { value in
                guard value || layout.showsInspector else { return }
                var updated = chromeState
                updated.inspectorVisible = value
                chromeState = updated
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            SplitExportControl()
        }
    }

    private func synchronizeSidebar() {
        columnVisibility = layout.showsSidebar && chromeState.sidebarVisible ? .all : .detailOnly
    }
}

private struct LegacyWindowLayout: View {
    @Binding var chromeState: WindowChromeState
    let layout: WindowChromeLayout

    var body: some View {
        HSplitView {
            if layout.showsSidebar {
                QueueSidebar(showsSidebarToggle: true).frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
            }
            WorkspaceDetail().frame(minWidth: WindowChromeState.minimumPreviewWidth)
            if layout.showsInspector {
                InspectorSurface().frame(minWidth: 300, idealWidth: 330, maxWidth: 360)
            }
        }
        .toolbar {
            ToolbarItem {
                SplitExportControl()
            }
        }
    }
}

private struct WorkspaceDetail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            ComparisonWorkspace()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mediaDropTarget(model)
        }
    }
}

private struct InspectorSurface: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        InspectorView()
            .frame(maxHeight: .infinity)
            .mediaDropTarget(model)
    }
}

private struct SplitExportControl: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var exportIsHovering = false
    @State private var optionsAreHovering = false

    var body: some View {
        unifiedControl
        .help("Export Options")
        .accessibilityLabel("Export Options")
    }

    @ViewBuilder
    private var menuContent: some View {
            Button(action: model.exportAll) {
                Label {
                    Text("Export All") + Text(" (\(model.jobs.count))")
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
            }
                .disabled(model.jobs.isEmpty)

            Divider()

            Button {
                model.outputDirectory = nil
            } label: {
                if model.outputDirectory == nil {
                    Label("Converted beside originals", systemImage: "checkmark")
                } else {
                    Text("Converted beside originals")
                }
            }

            Button(action: model.chooseOutputDirectory) {
                Label("Choose Output Folder…", systemImage: "folder.badge.plus")
            }

            if let outputDirectory = model.outputDirectory {
                Label(outputDirectory.lastPathComponent, systemImage: "checkmark")
            }

            if model.isExporting {
                Divider()
                Button("Cancel Exports") { model.cancelAll() }
            }
    }

    private var unifiedControl: some View {
        HStack(spacing: 0) {
            Button(action: model.exportSelected) {
                Text("Export")
                    .padding(.leading, 16)
                    .padding(.trailing, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(model.selectedJob == nil)
            .opacity(model.selectedJob == nil ? 0.55 : 1)
            .background(
                Capsule()
                    .fill(Color.white.opacity(exportSegmentOpacity))
                    .padding(3)
            )
            .contentShape(Rectangle())
            .onHover { exportIsHovering = model.selectedJob != nil && $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: exportIsHovering)

            Rectangle()
                .fill(Color.white.opacity(0.32))
                .frame(width: 1, height: 18)

            optionsMenu
        }
        .foregroundColor(.white)
        .background(Capsule().fill(Color.accentColor))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var optionsMenu: some View {
        if #available(macOS 12.0, *) {
            Menu {
                menuContent
            } label: {
                Color.clear.frame(width: 42, height: 34)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .frame(width: 42, height: 34)
            .background(
                Circle()
                    .fill(Color.white.opacity(optionsAreHovering ? 0.14 : 0))
                    .frame(width: 30, height: 30)
            )
            .overlay(whiteChevron)
            .contentShape(Rectangle())
            .onHover { optionsAreHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: optionsAreHovering)
        } else {
            Menu {
                menuContent
            } label: {
                Color.clear.frame(width: 42, height: 34)
            }
            .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false))
            .frame(width: 42, height: 34)
            .background(
                Circle()
                    .fill(Color.white.opacity(optionsAreHovering ? 0.14 : 0))
                    .frame(width: 30, height: 30)
            )
            .overlay(whiteChevron)
            .contentShape(Rectangle())
            .onHover { optionsAreHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: optionsAreHovering)
        }
    }

    private var exportSegmentOpacity: Double {
        exportIsHovering && model.selectedJob != nil ? 0.14 : 0
    }

    private var whiteChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.bold())
            .foregroundColor(.white)
            .allowsHitTesting(false)
    }
}
