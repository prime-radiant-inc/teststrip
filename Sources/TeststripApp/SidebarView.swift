import SwiftUI

struct SidebarView: View {
    var model: AppModel

    var body: some View {
        List {
            ForEach(model.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.self) { row in
                        Text(row)
                    }
                }
            }
        }
        .navigationTitle("Teststrip")
    }
}
