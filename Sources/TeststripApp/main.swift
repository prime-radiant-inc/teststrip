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
    }
}

TeststripApplication.main()
