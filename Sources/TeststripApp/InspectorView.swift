import SwiftUI
import TeststripCore

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
                if model.pendingMetadataSyncItems.contains(where: { $0.assetID == asset.id }) {
                    Text("XMP sync pending")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                if model.metadataSyncConflictItems.contains(where: { $0.assetID == asset.id }) {
                    Text("XMP conflict")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                metadataControls(for: asset)
            } else {
                Text("No selection")
            }
            Spacer()
            ActivityView(model: model)
        }
        .padding()
        .frame(minWidth: 260)
    }

    private func metadataControls(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Rating", selection: Binding(
                get: { asset.metadata.rating },
                set: { rating in apply { try model.setRatingForSelectedAsset(rating) } }
            )) {
                ForEach(Array(0...5), id: \.self) { rating in
                    Text("\(rating)").tag(rating)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Text("Flag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    apply { try model.setFlagForSelectedAsset(.pick) }
                } label: {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(asset.metadata.flag == .pick ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Pick")
                Button {
                    apply { try model.setFlagForSelectedAsset(.reject) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(asset.metadata.flag == .reject ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Reject")
                Button {
                    apply { try model.setFlagForSelectedAsset(nil) }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(asset.metadata.flag == nil ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Clear flag")
            }

            HStack(spacing: 8) {
                Text("Label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    apply { try model.setColorLabelForSelectedAsset(nil) }
                } label: {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(asset.metadata.colorLabel == nil ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Clear label")
                ForEach(ColorLabel.allCases, id: \.self) { label in
                    Button {
                        apply { try model.setColorLabelForSelectedAsset(label) }
                    } label: {
                        Circle()
                            .fill(color(for: label))
                            .frame(width: 12, height: 12)
                            .overlay {
                                if asset.metadata.colorLabel == label {
                                    Circle()
                                        .stroke(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(label.rawValue.capitalized)
                }
            }
        }
    }

    private func apply(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func color(for label: ColorLabel) -> Color {
        switch label {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}
