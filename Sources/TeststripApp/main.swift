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
                SidebarView(model: model)
            } content: {
                LibraryGridView(model: model)
            } detail: {
                if WorkspaceChromePolicy.showsInspector(model.selectedWorkspace) {
                    InspectorView(model: model)
                }
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
            WorkspaceCommands(model: model)
            MetadataHistoryCommands(model: model)
            NavigationCommands(model: model)
            MetadataActionCommands(model: model)
            AutopilotCommands(model: model)
            CullingCommands(model: model)
            SupportCommands(model: model)
            ActivityCommands(model: model)
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

            // Temporary sub-view routes so grid/loupe/compare/A-B stay
            // reachable after the old top-bar switcher's removal; Task 18
            // rebuilds Cull sub-view switching (and assigns key equivalents).
            Button("Grid") {
                model.selectedView = .grid
            }
            Button("Loupe") {
                model.selectedView = .loupe
            }
            Button("Compare") {
                model.selectedView = .compare
            }
            Button("A/B Compare") {
                model.selectedView = .abCompare
            }

            // Temporary routes for destinations whose sidebar rows Task 7
            // deleted (Search/Review/Timeline/People/Places); Task 9 (search),
            // Task 10 (Library view toggle), and Task 13 (Cull source picker)
            // give them permanent homes.
            Button("Search") {
                model.selectedView = .search
            }
            Button("Review") {
                model.selectedView = .copilot
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

private struct CullingCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Culling") {
            ForEach(Array(CullingCommandMenuPresentation.sections.enumerated()), id: \.element.id) { index, section in
                ForEach(section.items) { item in
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

TeststripApplication.main()
