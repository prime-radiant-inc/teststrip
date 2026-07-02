import SwiftUI

struct InspectorView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset = model.selectedAsset {
                Text(asset.originalURL.lastPathComponent)
                    .font(.headline)
                Text("Availability: \(asset.availability.rawValue)")
                Text("Rating: \(asset.metadata.rating)")
                Text("Keywords: \(asset.metadata.keywords.joined(separator: ", "))")
            } else {
                Text("No selection")
            }
            Spacer()
            ActivityView(model: model)
        }
        .padding()
        .frame(minWidth: 260)
    }
}
