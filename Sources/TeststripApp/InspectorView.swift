import Foundation
import SwiftUI
import TeststripCore

struct InspectorView: View {
    var model: AppModel
    @State private var metadataDraft = InspectorMetadataDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset = model.selectedAsset {
                Text(asset.originalURL.lastPathComponent)
                    .font(.headline)
                Text("Availability: \(asset.availability.rawValue)")
                Text("Rating: \(asset.metadata.rating)")
                if let technicalMetadata = asset.technicalMetadata {
                    technicalMetadataView(technicalMetadata)
                }
                if model.pendingMetadataSyncItems.contains(where: { $0.assetID == asset.id }) {
                    Text("XMP sync pending")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                if model.metadataSyncConflictItems.contains(where: { $0.assetID == asset.id }) {
                    metadataConflictControls()
                }
                if !model.selectedPreviewGenerationFailures.isEmpty {
                    previewFailureStatus(model.selectedPreviewGenerationFailures)
                }
                metadataControls(for: asset)
                    .onAppear {
                        metadataDraft.sync(to: asset)
                    }
                    .onChange(of: asset.id) { _, _ in
                        metadataDraft.sync(to: asset)
                    }
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

    private func previewFailureStatus(_ failures: [PreviewGenerationQueueState]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Preview retry pending", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.yellow)
            ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                Text(previewFailureText(failure))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button {
                apply { try model.retrySelectedPreviewGenerationFailures() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(!model.canRetrySelectedPreviewGenerationFailures)
        }
    }

    private func metadataConflictControls() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XMP conflict")
                .font(.caption)
                .foregroundStyle(.red)
            HStack(spacing: 8) {
                Button {
                    apply { try model.resolveSelectedMetadataConflictUsingCatalog() }
                } label: {
                    Label("Use Catalog", systemImage: "internaldrive")
                }
                .help("Keep catalog metadata and overwrite the XMP sidecar")

                Button {
                    apply { try model.resolveSelectedMetadataConflictUsingSidecar() }
                } label: {
                    Label("Use XMP", systemImage: "doc.text")
                }
                .help("Import XMP sidecar metadata into the catalog")
            }
            .controlSize(.small)
        }
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

            portableTextControls(for: asset)
        }
    }

    private func portableTextControls(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataTextField("Keywords", text: $metadataDraft.keywords) {
                try model.setKeywordTextForSelectedAsset(metadataDraft.keywords)
            }
            metadataTextField("Caption", text: $metadataDraft.caption) {
                try model.setCaptionForSelectedAsset(metadataDraft.caption)
            }
            metadataTextField("Creator", text: $metadataDraft.creator) {
                try model.setCreatorForSelectedAsset(metadataDraft.creator)
            }
            metadataTextField("Copyright", text: $metadataDraft.copyright) {
                try model.setCopyrightForSelectedAsset(metadataDraft.copyright)
            }
        }
        .onChange(of: asset.metadata) { _, _ in
            metadataDraft.sync(to: asset)
        }
    }

    private func metadataTextField(_ title: String, text: Binding<String>, commit: @escaping () throws -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        apply(commit)
                    }
                Button {
                    apply(commit)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.plain)
                .help("Apply \(title.lowercased())")
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

    private func previewFailureText(_ failure: PreviewGenerationQueueState) -> String {
        let attemptText = failure.attemptCount == 1 ? "1 attempt" : "\(failure.attemptCount) attempts"
        if let message = failure.lastErrorMessage, !message.isEmpty {
            return "\(failure.item.level.rawValue.capitalized) preview failed after \(attemptText): \(message)"
        }
        return "\(failure.item.level.rawValue.capitalized) preview failed after \(attemptText)"
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
        case .faceCount: "Face count"
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
        case .count(let count):
            "\(count)"
        case .vector(let values):
            values.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: ", ")
        }
    }

    private func confidenceText(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

struct InspectorMetadataDraft: Equatable {
    var assetID: AssetID?
    var syncedMetadata: AssetMetadata?
    var keywords: String
    var caption: String
    var creator: String
    var copyright: String

    init(asset: Asset? = nil) {
        assetID = asset?.id
        syncedMetadata = asset?.metadata
        keywords = asset?.metadata.keywords.joined(separator: ", ") ?? ""
        caption = asset?.metadata.caption ?? ""
        creator = asset?.metadata.creator ?? ""
        copyright = asset?.metadata.copyright ?? ""
    }

    mutating func sync(to asset: Asset) {
        guard assetID == asset.id else {
            self = InspectorMetadataDraft(asset: asset)
            return
        }
        guard syncedMetadata != asset.metadata else { return }
        if matches(asset.metadata) {
            syncedMetadata = asset.metadata
            return
        }
        guard !hasUnsavedChanges else { return }
        self = InspectorMetadataDraft(asset: asset)
    }

    private var hasUnsavedChanges: Bool {
        guard let syncedMetadata else { return false }
        return !matches(syncedMetadata)
    }

    private func matches(_ metadata: AssetMetadata) -> Bool {
        keywords == metadata.keywords.joined(separator: ", ")
            && caption == (metadata.caption ?? "")
            && creator == (metadata.creator ?? "")
            && copyright == (metadata.copyright ?? "")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
