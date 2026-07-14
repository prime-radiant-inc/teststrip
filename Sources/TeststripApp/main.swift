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
        _ = Updater.shared   // start Sparkle's background update checks
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
            // Catalog-open sidecar rescan (Jesse's ruling 2026-07-11):
            // detect out-of-band sidecar edits made while the app was
            // closed; batched off the main actor, quiet when clean.
            .task { await model.performLaunchSidecarRescan() }
        }
        .defaultSize(
            width: AppWindowLayoutMetrics.defaultWidth,
            height: AppWindowLayoutMetrics.defaultHeight
        )
        .commands {
            // Teststrip is single-window/single-catalog: suppress AppKit's
            // default File > New Window item (⌘N), which would otherwise
            // mint a second window over the same catalog (app-001).
            CommandGroup(replacing: .newItem) {}
            Group {
                FileCommands(model: model)
                WorkspaceCommands(model: model)
                MetadataHistoryCommands(model: model)
                SearchCommands(model: model)
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

    static let zoomInActionID = "Zoom In"
    static let zoomOutActionID = "Zoom Out"
    static let zoomActionIDs: [String] = [zoomInActionID, zoomOutActionID]

    static var cullingShortcutActionIDs: [String] {
        CullingCommandMenuPresentation.sections
            .flatMap(\.items)
            .map(\.title)
    }

    // File ▸ Import Folder…/Import From Card…/Import Path…/Export… (spec §6).
    static let importFolderActionID = "Import Folder…"
    static let importFromCardActionID = "Import From Card…"
    static let importPathActionID = "Import Path…"
    static let exportActionID = "Export…"
    static let fileMenuActionIDs: [String] = [importFolderActionID, importFromCardActionID, exportActionID]

    // File ▸ New Set from Selection… (persona-2 item 2): the only prior path
    // to save-as-set was the result-header "Save ▾" control, undiscoverable
    // without an existing selection already visible. Reuses the manual-set
    // save popover via the same request-token pattern as Move Rejects….
    static let newSetFromSelectionActionID = "New Set from Selection…"

    // Culling ▸ Move Rejects… (spec §6), reusing the same beginRejectRelocation
    // path Task 20's end-of-set state already calls.
    static let moveRejectsActionID = "Move Rejects…"

    // Culling ▸ Move Rejects to Trash… (trash-and-ux-coherence spec Part 1),
    // a sibling of Move Rejects… reusing the same request-token pattern.
    static let moveRejectsToTrashActionID = "Move Rejects to Trash…"

    // Support ▸ Check for Updates… (Sparkle auto-updater).
    static let checkForUpdatesActionID = "Check for Updates…"
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

    // The cull sub-view keys (g/c/b) are owned solely by the in-view key
    // monitors (CullingKeyCaptureView in loupe/compare/A-B,
    // GridKeyCaptureView in the cull grid). Binding them here as bare menu
    // key equivalents dispatched a second, mode-blind `selectedView = mode`
    // ~150ms after the monitor's switch — from the cull grid, G flipped to
    // loupe and the menu equivalent immediately flipped back to cullGrid,
    // making G/Esc appear inert (run-cull-iter2 cull-008). Menus stay
    // clickable; the ? key map documents the keys.
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
            Button(title) {
                model.selectedView = mode
            }
        }
    }
}

// File ▸ Import Folder…/Import From Card…/Export… (+ dev Import Path…),
// spec §6: menus are the system of record, so every toolbar import/export
// action also has a File menu equivalent, calling the same model actions
// via the request-token path (AppModel.requestImportFolder, etc.).
private struct FileCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(AppMenuCoveragePresentation.importFolderActionID) {
                model.requestImportFolder()
            }
            .disabled(model.isImporting)

            Button(AppMenuCoveragePresentation.importFromCardActionID) {
                model.requestImportFromCard()
            }
            .disabled(model.isImporting)

            if LibraryGridChromePolicy.shouldExposeImportPathControl(
                environment: ProcessInfo.processInfo.environment
            ) {
                Button(AppMenuCoveragePresentation.importPathActionID) {
                    model.requestImportPath()
                }
                .disabled(model.isImporting)
            }

            Divider()

            Button(AppMenuCoveragePresentation.exportActionID) {
                model.requestExport()
            }
            .disabled(model.isImporting || model.assets.isEmpty || model.isExporting)

            Divider()

            Button(AppMenuCoveragePresentation.newSetFromSelectionActionID) {
                model.requestNewSetFromSelection()
            }
            .disabled(!model.canSaveSelectedAssetAsManualSet)
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

// Edit ▸ Find ⌘F: the standard macOS Find placement (below Paste/Select,
// same slot AppKit text views use for their own Find item), not a
// CommandGroup(replacing: .textEditing) — that would blow away Cut/Copy/
// Paste/Select All for every text field in the app. Focuses the Library
// query field; from Cull/People it switches to Library first (see
// AppModel.requestFocusSearch).
private struct SearchCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find") {
                model.requestFocusSearch()
            }
            .keyboardShortcut("f", modifiers: [.command])
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

            // On-demand sidecar rescan over the current scope (Jesse's
            // ruling 2026-07-11) — same check the app runs at launch.
            Button("Check Sidecars for Changes") {
                Task { await model.checkSidecarsForChangesInCurrentScope() }
            }
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

            Button("Evaluate Matches") {
                evaluateCurrentScope()
            }
            .disabled(model.isImporting || !model.canRequestCurrentScopeAssetEvaluations)

            Button(AppMenuCoveragePresentation.moveRejectsActionID) {
                model.requestMoveRejects()
            }
            .disabled(model.isImporting || model.assets.isEmpty || model.isRelocatingRejects)

            Button(AppMenuCoveragePresentation.moveRejectsToTrashActionID) {
                model.requestMoveRejectsToTrash()
            }
            .disabled(model.isImporting || model.assets.isEmpty || model.isRelocatingRejects)

            Toggle(isOn: Binding(
                get: { model.autopilotEnabled },
                set: { model.autopilotEnabled = $0 }
            )) {
                Text("Auto-cull After Import")
            }

            Divider()

            ForEach(Array(CullingCommandMenuPresentation.sections.enumerated()), id: \.element.id) { index, section in
                ForEach(section.items) { item in
                    Button(item.menuDisplayTitle) {
                        applyShortcut(item.shortcut)
                    }
                    .keyboardShortcut(item.key.menuKeyboardShortcut)
                    // These bare (no-modifier) shortcuts mirror
                    // CullingKeyCaptureView's local key monitor, which
                    // CullingKeyCaptureGate scopes to the Cull workspace's
                    // loupe/compare/A-B sub-views only. SwiftUI menu
                    // .keyboardShortcut bindings are workspace-blind, so
                    // without this the menu (and its keyboard equivalent)
                    // would leak flag/rating writes into e.g. Library Loupe.
                    .disabled(!model.isCullingMenuShortcutActive)
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

extension CullingShortcutKey {
    // Every bare (modifier-less) culling key is owned by exactly one
    // dispatcher: the in-view key monitors (GridKeyCaptureView in the grids,
    // CullingKeyCaptureView in loupe/compare/A-B). A bare menu key equivalent
    // fires through AppKit's performKeyEquivalent path *independently* of
    // those monitors — a monitor consuming the NSEvent does not stop it — so
    // binding any of these keys in the menu double-dispatches the shortcut
    // (one keypress wrote two assets and advanced two frames; verified live,
    // run-cull-iter2 cull-003/005/007). The menu items stay clickable for
    // mouse users (gated by isCullingMenuShortcutActive) and the ? key-map
    // overlay carries keyboard discoverability.
    var menuKeyboardShortcut: KeyboardShortcut? {
        nil
    }
}

private struct SupportCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Support") {
            Button("Copy Diagnostics") {
                copyDiagnostics()
            }

            Divider()

            Button(AppMenuCoveragePresentation.checkForUpdatesActionID) {
                Updater.shared.checkForUpdates()
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
            Button(AppMenuCoveragePresentation.showInspectorActionID) {
                model.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command])

            // Titles come from the same presentation list the coverage test
            // enumerates, so the menu and test can't drift apart.
            ForEach(Array(zip(InspectorTab.allCases, AppMenuCoveragePresentation.inspectorTabActionIDs)), id: \.0) { tab, title in
                Button(title) {
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
            Button(AppMenuCoveragePresentation.zoomInActionID) {
                storedThumbnailWidth = LibraryGridLayout.zoomedThumbnailWidth(storedThumbnailWidth, zoomingIn: true)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button(AppMenuCoveragePresentation.zoomOutActionID) {
                storedThumbnailWidth = LibraryGridLayout.zoomedThumbnailWidth(storedThumbnailWidth, zoomingIn: false)
            }
            .keyboardShortcut("-", modifiers: .command)
        }
    }
}

TeststripApplication.main()
