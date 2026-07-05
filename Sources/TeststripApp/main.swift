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
                workerExecutableURL: AppCatalog.bundledWorkerExecutableURL()
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
            Button("Previous Photo") {
                applyShortcut(.previousPhoto)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Next Photo") {
                applyShortcut(.nextPhoto)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Divider()

            Button("Clear Rating") {
                applyShortcut(.rating(0))
            }
            .keyboardShortcut("0", modifiers: [])

            Button("1 Star") {
                applyShortcut(.rating(1))
            }
            .keyboardShortcut("1", modifiers: [])

            Button("2 Stars") {
                applyShortcut(.rating(2))
            }
            .keyboardShortcut("2", modifiers: [])

            Button("3 Stars") {
                applyShortcut(.rating(3))
            }
            .keyboardShortcut("3", modifiers: [])

            Button("4 Stars") {
                applyShortcut(.rating(4))
            }
            .keyboardShortcut("4", modifiers: [])

            Button("5 Stars") {
                applyShortcut(.rating(5))
            }
            .keyboardShortcut("5", modifiers: [])

            Divider()

            Button("Red Label") {
                applyShortcut(.colorLabel(.red))
            }
            .keyboardShortcut("6", modifiers: [])

            Button("Yellow Label") {
                applyShortcut(.colorLabel(.yellow))
            }
            .keyboardShortcut("7", modifiers: [])

            Button("Green Label") {
                applyShortcut(.colorLabel(.green))
            }
            .keyboardShortcut("8", modifiers: [])

            Button("Blue Label") {
                applyShortcut(.colorLabel(.blue))
            }
            .keyboardShortcut("9", modifiers: [])

            Button("Purple Label") {
                applyShortcut(.colorLabel(.purple))
            }
            .keyboardShortcut("v", modifiers: [])

            Button("Clear Label") {
                applyShortcut(.colorLabel(nil))
            }
            .keyboardShortcut("-", modifiers: [])

            Divider()

            Button("Pick") {
                applyShortcut(.pick)
            }
            .keyboardShortcut("p", modifiers: [])

            Button("Reject") {
                applyShortcut(.reject)
            }
            .keyboardShortcut("x", modifiers: [])

            Button("Clear Flag") {
                applyShortcut(.clearFlag)
            }
            .keyboardShortcut("u", modifiers: [])
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
