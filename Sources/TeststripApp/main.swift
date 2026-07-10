import AppKit
import SwiftUI

struct AppWindowLayoutMetrics {
    /// Per-workspace minimum window width (Task 22): the prior single global
    /// 1520pt floor forced every workspace to pay for Library's chrome
    /// (sidebar + inspector + footer). Library keeps the widest floor; Cull's
    /// rail is narrower; People has neither inspector nor filter chrome.
    /// Sidebar/inspector collapse before content squeezes below these.
    static func minimumWidth(for workspace: Workspace) -> CGFloat {
        switch workspace {
        case .library: return 1_000
        case .cull: return 800
        case .people: return 700
        }
    }

    static let defaultWidth: CGFloat = 1_520
    static let minimumHeight: CGFloat = 720
    static let defaultHeight: CGFloat = 820
}

struct TeststripApplication: App {
    @State private var model: AppModel

    init() {
        do {
            _model = State(initialValue: try AppCatalog.loadModel(
                paths: AppCatalog.defaultPaths(),
                workerExecutableURL: AppCatalog.bundledWorkerExecutableURL(),
                sessionRestoreDefaults: .standard
            ))
        } catch {
            fatalError("Unable to open Teststrip catalog: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                if model.selectedWorkspace == .cull {
                    CullSidebarView(model: model)
                } else {
                    SidebarView(model: model)
                }
            } detail: {
                LibraryGridView(model: model)
            }
            .inspector(isPresented: Binding(
                get: { model.isInspectorVisible && WorkspaceChromePolicy.showsInspector(model.selectedWorkspace) },
                set: { model.isInspectorVisible = $0 }
            )) {
                InspectorView(model: model)
            }
            .frame(
                minWidth: AppWindowLayoutMetrics.minimumWidth(for: model.selectedWorkspace),
                minHeight: AppWindowLayoutMetrics.minimumHeight
            )
            .preferredColorScheme(.dark)
        }
        .defaultSize(
            width: AppWindowLayoutMetrics.defaultWidth,
            height: AppWindowLayoutMetrics.defaultHeight
        )
        .commands {
            Group {
                WorkspaceCommands(model: model)
                MetadataHistoryCommands(model: model)
                NavigationCommands(model: model)
                MetadataActionCommands(model: model)
            }
            Group {
                CullingCommands(model: model)
                PeopleCommands(model: model)
                SupportCommands(model: model)
                ActivityCommands(model: model)
                InspectorCommands(model: model)
                ZoomCommands()
            }
        }

        Settings {
            PreferencesView(model: model)
        }
    }
}

/// Canonical menu action ids (Task 22): the workspace/sub-view/inspector-tab/
/// zoom menu items below are built ad hoc as SwiftUI `Button`s rather than
/// from a data-driven presentation type (as `CullingCommands` is), so this
/// gives `MenuCoveragePresentationTests` something to enumerate against the
/// underlying action-producing enums. Update alongside the Commands below
/// whenever a menu item is added, renamed, or removed.
enum AppMenuCoveragePresentation {
    static let workspaceActionIDs: [String] = Workspace.allCases.map(\.title)

    /// Sub-view switcher items (Task 10 Library / Task 18 Cull). `.people`
    /// has no switcher — People is a single view, not a workspace with
    /// alternate routes — so it's excluded.
    static let subViewMenuModes: [LibraryViewMode] = [
        .loupe, .cullGrid, .compare, .abCompare,
        .grid, .libraryLoupe, .timeline, .map
    ]

    static let inspectorTabActionIDs: [String] = InspectorTab.allCases.map { "\($0.title) Tab" }
    static let showInspectorActionID = "Show Inspector"

    static let zoomActionIDs: [String] = ["Zoom In", "Zoom Out"]

    static var cullingShortcutActionIDs: [String] {
        CullingCommandMenuPresentation.sections
            .flatMap(\.items)
            .filter { !$0.isMonitorOnly }
            .map(\.title)
    }
}

extension LibraryViewMode {
    /// Title shown in the View menu's sub-view switcher; `nil` excludes the
    /// mode (currently only `.people`, which has no switcher).
    var subViewMenuTitle: String? {
        switch self {
        case .loupe: return "Loupe"
        case .cullGrid: return "Grid"
        case .compare: return "Compare"
        case .abCompare: return "A/B Compare"
        case .grid: return "Library Grid"
        case .libraryLoupe: return "Library Loupe"
        case .timeline: return "Timeline"
        case .map: return "Map"
        case .people: return nil
        }
    }

    /// Bare (no-modifier) key equivalent mirroring the in-view g/c/b key
    /// captures for the cull sub-views (CullingKeyCaptureView in loupe/
    /// compare/A-B, GridKeyCaptureView in the cull grid). Library sub-views
    /// have no bare shortcut.
    var subViewMenuKey: Character? {
        switch self {
        case .cullGrid: return "g"
        case .compare: return "c"
        case .abCompare: return "b"
        default: return nil
        }
    }
}

private struct WorkspaceCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ForEach(Workspace.allCases, id: \.self) { workspace in
                Button(workspace.title) {
                    model.selectWorkspace(workspace)
                }
                .keyboardShortcut(workspace.keyEquivalent, modifiers: [.command])
            }

            Divider()

            // Menus stay the system of record even though the sub-view
            // switchers (in-view key captures, header toggle) also reach
            // these routes.
            ForEach(AppMenuCoveragePresentation.subViewMenuModes, id: \.self) { mode in
                subViewButton(for: mode)
            }
        }
    }

    @ViewBuilder
    private func subViewButton(for mode: LibraryViewMode) -> some View {
        // Divider between the cull and library sub-view groups (Tasks 18/10).
        if mode == .grid {
            Divider()
        }
        if let title = mode.subViewMenuTitle {
            if let key = mode.subViewMenuKey {
                Button(title) {
                    model.selectedView = mode
                }
                .keyboardShortcut(KeyEquivalent(key), modifiers: [])
            } else {
                Button(title) {
                    model.selectedView = mode
                }
            }
        }
    }
}

private struct MetadataHistoryCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Metadata Change") {
                undo()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(!model.canUndoMetadataChange)

            Button("Redo Metadata Change") {
                redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.canRedoMetadataChange)
        }
    }

    private func undo() {
        do {
            try model.undoMetadataChange()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func redo() {
        do {
            try model.redoMetadataChange()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct NavigationCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            Button("Back") {
                navigateBack()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(!model.canNavigateBack)

            Button("Forward") {
                navigateForward()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(!model.canNavigateForward)
        }
    }

    private func navigateBack() {
        do {
            try model.navigateBack()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func navigateForward() {
        do {
            try model.navigateForward()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct MetadataActionCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Metadata") {
            Button("Batch Metadata…") {
                model.requestBatchMetadataSheet()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(model.isImporting || model.assets.isEmpty)
        }
    }
}

// The People workspace's scan trigger (Task 21): it leaves the canvas so
// the queue can own the Return-confirm keystroke without a stray button
// stealing focus. Progress reports through the Activity item like any
// other evaluation pass (requestPeopleFaceScan reuses the same
// requestEvaluation path as Find ▸ Evaluate Photos).
private struct PeopleCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("People") {
            Button("Scan for Faces") {
                requestPeopleFaceScan()
            }
            .disabled(!model.canRequestPeopleFaceScan)
        }
    }

    private func requestPeopleFaceScan() {
        do {
            try model.requestPeopleFaceScan()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

// Find Best Shots / Evaluate / Run Autopilot / auto-cull used to live in a
// standalone "Find" menu; spec §6 folds them into Culling alongside the
// existing shortcut sections so Culling is the one place for cull-workflow
// actions. Shortcuts are unchanged (⇧⌘B, ⇧⌘E on Evaluate Visible).
private struct CullingCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Culling") {
            Button("Find Best Shots") {
                findBestShots()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(model.isImporting || !model.canFindBestShots)

            Button("Run Autopilot") {
                runAutopilot()
            }
            .disabled(model.isImporting || model.assets.isEmpty)

            Divider()

            Button("Evaluate Photo") {
                evaluateSelectedPhoto()
            }
            .disabled(model.isImporting || !model.canRequestSelectedAssetEvaluation)

            // The keyboard-reachable Evaluate for power users; the toolbar
            // entry (More ▸ Evaluate Visible) is one level deep.
            Button("Evaluate Visible") {
                evaluateVisiblePhotos()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.isImporting || !model.canRequestVisibleAssetEvaluations)

            Button("Evaluate Scope") {
                evaluateCurrentScope()
            }
            .disabled(model.isImporting || !model.canRequestCurrentScopeAssetEvaluations)

            Toggle(isOn: Binding(
                get: { model.autopilotEnabled },
                set: { model.autopilotEnabled = $0 }
            )) {
                Text("Auto-cull After Import")
            }

            Divider()

            ForEach(Array(CullingCommandMenuPresentation.sections.enumerated()), id: \.element.id) { index, section in
                ForEach(section.items.filter { !$0.isMonitorOnly }) { item in
                    Button(item.title) {
                        applyShortcut(item.shortcut)
                    }
                    .keyboardShortcut(item.key.menuKeyboardShortcut)
                }
                if index < CullingCommandMenuPresentation.sections.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func applyShortcut(_ shortcut: CullingShortcut) {
        do {
            try model.applyCullingShortcut(shortcut)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func findBestShots() {
        do {
            try model.findBestShots()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func runAutopilot() {
        do {
            try model.runAutopilotOnCurrentScope()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func evaluateSelectedPhoto() {
        do {
            try model.requestSelectedAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func evaluateVisiblePhotos() {
        do {
            try model.requestVisibleAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func evaluateCurrentScope() {
        do {
            try model.requestCurrentScopeAssetEvaluations()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private extension CullingShortcutKey {
    // The arrow and Return keys are owned by the in-view key captures
    // (GridKeyCaptureView in the grid, CullingKeyCaptureView in loupe/culling),
    // which handle them through an app-wide key monitor. Binding those same keys
    // as bare menu equivalents makes AppKit fire the shortcut a second time per
    // press — the double-step regression. Only character keys, which AppKit does
    // not honour as bare (modifier-less) menu equivalents, get a shortcut here so
    // the menu still displays them for discoverability.
    var menuKeyboardShortcut: KeyboardShortcut? {
        switch self {
        case .leftArrow, .rightArrow, .upArrow, .downArrow, .returnKey:
            return nil
        case .optionLeftArrow, .optionRightArrow:
            // Monitor-only: never reached since CullingCommands filters
            // isMonitorOnly items out before building menu bindings.
            return nil
        case .character(let character):
            return KeyboardShortcut(KeyEquivalent(Character(character)), modifiers: [])
        }
    }
}

private struct SupportCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Support") {
            Button("Copy Diagnostics") {
                copyDiagnostics()
            }
        }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.diagnosticsReportText, forType: .string)
        model.statusMessage = "Copied diagnostics"
    }
}

private struct ActivityCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Activity") {
                model.isActivityCenterPresented.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
        }
    }
}

private struct InspectorCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Show Inspector") {
                model.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command])

            ForEach(InspectorTab.allCases) { tab in
                Button("\(tab.title) Tab") {
                    model.selectInspectorTab(tab)
                }
                .keyboardShortcut(tab.keyEquivalent, modifiers: [.command, .option])
            }
        }
    }
}

private struct ZoomCommands: Commands {
    @AppStorage("LibraryGridView.thumbnailWidth") private var storedThumbnailWidth = LibraryGridLayout.defaultThumbnailWidth

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") {
                storedThumbnailWidth = LibraryGridLayout.zoomedThumbnailWidth(storedThumbnailWidth, zoomingIn: true)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                storedThumbnailWidth = LibraryGridLayout.zoomedThumbnailWidth(storedThumbnailWidth, zoomingIn: false)
            }
            .keyboardShortcut("-", modifiers: .command)
        }
    }
}

TeststripApplication.main()
