import SwiftUI

struct TeststripApplication: App {
    @State private var model: AppModel

    init() {
        do {
            _model = State(initialValue: try AppCatalog.loadModel(paths: AppCatalog.defaultPaths()))
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
            .frame(minWidth: 1100, minHeight: 720)
        }
        .commands {
            CullingCommands(model: model)
        }
    }
}

private struct CullingCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Culling") {
            Button("Previous Photo") {
                model.selectPreviousAsset()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.option])

            Button("Next Photo") {
                model.selectNextAsset()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.option])

            Divider()

            Button("Clear Rating") {
                apply(.rating(0))
            }
            .keyboardShortcut("0", modifiers: [.option])

            Button("1 Star") {
                apply(.rating(1))
            }
            .keyboardShortcut("1", modifiers: [.option])

            Button("2 Stars") {
                apply(.rating(2))
            }
            .keyboardShortcut("2", modifiers: [.option])

            Button("3 Stars") {
                apply(.rating(3))
            }
            .keyboardShortcut("3", modifiers: [.option])

            Button("4 Stars") {
                apply(.rating(4))
            }
            .keyboardShortcut("4", modifiers: [.option])

            Button("5 Stars") {
                apply(.rating(5))
            }
            .keyboardShortcut("5", modifiers: [.option])

            Divider()

            Button("Pick") {
                apply(.pick)
            }
            .keyboardShortcut("p", modifiers: [.option])

            Button("Reject") {
                apply(.reject)
            }
            .keyboardShortcut("x", modifiers: [.option])

            Button("Clear Flag") {
                apply(.clearFlag)
            }
            .keyboardShortcut("u", modifiers: [.option])
        }
    }

    private func apply(_ command: CullingCommand) {
        do {
            try model.applyCullingCommand(command)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

TeststripApplication.main()
