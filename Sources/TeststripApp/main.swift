import SwiftUI

struct TeststripApplication: App {
    @State private var model = AppModel.demo()

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
