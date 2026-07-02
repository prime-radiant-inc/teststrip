import SwiftUI

struct LibraryGridView: View {
    var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(model.assets, id: \.id.rawValue) { asset in
                    Button {
                        model.select(asset.id)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.gray.opacity(0.35))
                                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                            Text(asset.metadata.rating > 0 ? String(repeating: "★", count: asset.metadata.rating) : " ")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(6)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .navigationTitle("All Photographs")
    }
}
