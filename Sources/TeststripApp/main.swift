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
        WindowGroup("Teststrip") {
            NavigationSplitView {
                SidebarView(model: model)
            } content: {
                LibraryGridView(model: model)
            } detail: {
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
            MetadataHistoryCommands(model: model)
            CullingCommands(model: model)
            SupportCommands(model: model)
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

private struct CullingCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Culling") {
            ForEach(Array(CullingCommandMenuPresentation.sections.enumerated()), id: \.element.id) { index, section in
                ForEach(section.items) { item in
                    Button(item.title) {
                        applyShortcut(item.shortcut)
                    }
                    .keyboardShortcut(item.key.keyEquivalent, modifiers: [])
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
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .leftArrow:
            .leftArrow
        case .rightArrow:
            .rightArrow
        case .upArrow:
            .upArrow
        case .downArrow:
            .downArrow
        case .returnKey:
            .return
        case .character(let character):
            KeyEquivalent(Character(character))
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

TeststripApplication.main()
