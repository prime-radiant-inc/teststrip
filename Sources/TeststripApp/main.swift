import AppKit
import SwiftUI

struct AppWindowLayoutMetrics {
    static let minimumSplitContentWidth: CGFloat = 1_505
    static let minimumWidth: CGFloat = 1_520
    static let defaultWidth: CGFloat = minimumWidth
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
                minWidth: AppWindowLayoutMetrics.minimumWidth,
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
                AutopilotCommands(model: model)
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

            // Cull sub-view routes (Task 18): keys mirror the in-view g/c/b
            // shortcuts (CullingKeyCaptureView in loupe/compare/A-B,
            // GridKeyCaptureView in the cull grid). Menus stay the system of
            // record even though the shortcuts are also reachable by hand.
            Button("Loupe") {
                model.selectedView = .loupe
            }
            Button("Grid") {
                model.selectedView = .cullGrid
            }
            .keyboardShortcut("g", modifiers: [])
            Button("Compare") {
                model.selectedView = .compare
            }
            .keyboardShortcut("c", modifiers: [])
            Button("A/B Compare") {
                model.selectedView = .abCompare
            }
            .keyboardShortcut("b", modifiers: [])

            Divider()

            // Library sub-view toggle (Task 10): menu equivalents of the
            // Library header's Grid/Loupe/Timeline/Map segmented control.
            // Menus stay the system of record even though the header also
            // exposes these as a toggle.
            Button("Library Grid") {
                model.selectedView = .grid
            }
            Button("Library Loupe") {
                model.selectedView = .libraryLoupe
            }
            Button("Timeline") {
                model.selectedView = .timeline
            }
            Button("Map") {
                model.selectedView = .map
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

private struct AutopilotCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Find") {
            Button("Find Best Shots") {
                findBestShots()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(model.isImporting || !model.canFindBestShots)

            // A keyboard-reachable Evaluate for power users; the toolbar entry
            // (More ▸ Evaluate…) is one level deep, no longer buried under Analyze.
            Button("Evaluate Photos") {
                evaluateVisiblePhotos()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.isImporting || !model.canRequestVisibleAssetEvaluations)

            Divider()

            // Power-user entry into the same run→review machinery; a newcomer
            // never needs it — Find Best Shots subsumes it.
            Button("Run Autopilot") {
                runAutopilot()
            }
            .disabled(model.isImporting || model.assets.isEmpty)
        }
    }

    private func evaluateVisiblePhotos() {
        do {
            try model.requestVisibleAssetEvaluations()
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

private struct CullingCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Culling") {
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
