import Foundation
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
                if let technicalMetadata = asset.technicalMetadata {
                    technicalMetadataView(technicalMetadata)
                }
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
                let signals = model.selectedEvaluationSignals
                if !signals.isEmpty {
                    evaluationSignals(signals)
                }
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

    private func technicalMetadataView(_ metadata: AssetTechnicalMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Technical")
                .font(.caption)
                .foregroundStyle(.secondary)
            metadataRow("Dimensions", "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
            if let camera = cameraText(metadata) {
                metadataRow("Camera", camera)
            }
            if let lensModel = metadata.lensModel {
                metadataRow("Lens", lensModel)
            }
            if let isoSpeed = metadata.isoSpeed {
                metadataRow("ISO", "\(isoSpeed)")
            }
            if let capturedAt = metadata.capturedAt {
                metadataRow("Captured", capturedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func evaluationSignals(_ signals: [EvaluationSignal]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Signals")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(signals.enumerated()), id: \.offset) { _, signal in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title(for: signal.kind)): \(valueText(for: signal.value))")
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(confidenceText(signal.confidence)) - \(signal.provenance.provider)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    private func cameraText(_ metadata: AssetTechnicalMetadata) -> String? {
        [metadata.cameraMake, metadata.cameraModel]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " ")
            .nilIfEmpty
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

    private func title(for kind: EvaluationKind) -> String {
        switch kind {
        case .focus: "Focus"
        case .motionBlur: "Motion blur"
        case .exposure: "Exposure"
        case .aesthetics: "Aesthetics"
        case .object: "Object"
        case .faceQuality: "Face quality"
        case .ocrText: "OCR"
        case .colorPalette: "Color"
        case .novelty: "Novelty"
        }
    }

    private func valueText(for value: EvaluationValue) -> String {
        switch value {
        case .score(let score):
            String(format: "%.2f", score)
        case .label(let label):
            label
        case .text(let text):
            text
        case .vector(let values):
            values.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: ", ")
        }
    }

    private func confidenceText(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
