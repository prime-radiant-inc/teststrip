import SwiftUI

struct SidebarView: View {
    var model: AppModel

    var body: some View {
        List {
            ForEach(model.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        Button {
                            select(row)
                        } label: {
                            Label(row.title, systemImage: iconName(for: row.target))
                        }
                        .buttonStyle(.plain)
                        .disabled(!row.isSelectable)
                    }
                }
            }
        }
        .navigationTitle("Teststrip")
    }

    private func select(_ row: SidebarRow) {
        do {
            try model.selectSidebarRow(row)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func iconName(for target: SidebarRowTarget) -> String {
        switch target {
        case .allPhotographs:
            return "photo.on.rectangle"
        case .folder:
            return "folder"
        case .assetSet:
            return "rectangle.stack"
        case .workSession:
            return "clock.arrow.circlepath"
        case .placeholder:
            return "circle"
        }
    }
}
