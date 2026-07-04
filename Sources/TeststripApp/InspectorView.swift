import Foundation
import SwiftUI
import TeststripCore

enum InspectorPreviewLayout {
    static let size = CGSize(width: 258, height: 186)
}

struct InspectorAssetIdentity: Equatable {
    var fullFilename: String
    var displayName: String
    var extensionBadge: String?
    var availabilityText: String
    var ratingText: String
    var capturedText: String?

    init(asset: Asset) {
        let extensionText = asset.originalURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        fullFilename = asset.originalURL.lastPathComponent
        extensionBadge = extensionText.isEmpty ? nil : extensionText.uppercased()
        displayName = extensionText.isEmpty
            ? asset.originalURL.lastPathComponent
            : asset.originalURL.deletingPathExtension().lastPathComponent
        availabilityText = "Availability: \(asset.availability.rawValue)"
        ratingText = "Rating: \(asset.metadata.rating)"
        capturedText = asset.technicalMetadata?.capturedAt?.formatted(date: .abbreviated, time: .shortened)
    }
}

struct InspectorMetadataRow: Equatable, Identifiable {
    var title: String
    var value: String

    var id: String { title }
}

struct InspectorTechnicalRows: Equatable {
    var rows: [InspectorMetadataRow]

    init(metadata: AssetTechnicalMetadata) {
        var rows = [
            InspectorMetadataRow(title: "Dimensions", value: "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
        ]
        let camera = [metadata.cameraMake, metadata.cameraModel]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " ")
        if !camera.isEmpty {
            rows.append(InspectorMetadataRow(title: "Camera", value: camera))
        }
        if let lensModel = metadata.lensModel?.trimmingCharacters(in: .whitespacesAndNewlines), !lensModel.isEmpty {
            rows.append(InspectorMetadataRow(title: "Lens", value: lensModel))
        }
        if let isoSpeed = metadata.isoSpeed {
            rows.append(InspectorMetadataRow(title: "ISO", value: "\(isoSpeed)"))
        }
        if let capturedAt = metadata.capturedAt {
            rows.append(InspectorMetadataRow(title: "Captured", value: capturedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        self.rows = rows
    }
}

struct InspectorView: View {
    var model: AppModel
    @State private var metadataDraft = InspectorMetadataDraft()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let asset = model.selectedAsset {
                        selectedPreview(for: asset)
                        assetHeader(for: asset)
                        metadataControls(for: asset)
                            .onAppear {
                                metadataDraft.sync(to: asset)
                            }
                            .onChange(of: asset.id) { _, _ in
                                metadataDraft.sync(to: asset)
                            }
                        statusAlerts(for: asset)
                        if let technicalMetadata = asset.technicalMetadata {
                            technicalMetadataView(technicalMetadata)
                        }
                        portableTextControls(for: asset)
                        let signals = model.selectedEvaluationSignals
                        if !signals.isEmpty {
                            evaluationSignals(signals)
                        }
                    } else {
                        Text("No selection")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ActivityView(model: model)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 286)
    }

    private func selectedPreview(for asset: Asset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.18))
            CachedPreviewImage(
                previewURL: model.selectedPreviewURL,
                scaling: .fit,
                cornerRadius: 5,
                cacheGeneration: model.previewCacheGeneration(for: asset.id)
            )
            .padding(4)
        }
        .frame(width: InspectorPreviewLayout.size.width, height: InspectorPreviewLayout.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("Selected preview")
    }

    @ViewBuilder
    private func assetHeader(for asset: Asset) -> some View {
        let identity = InspectorAssetIdentity(asset: asset)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(identity.displayName)
                    .font(.system(.headline, design: .monospaced))
                    .lineLimit(1)
                if let extensionBadge = identity.extensionBadge {
                    Text(extensionBadge)
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            HStack(spacing: 8) {
                if let capturedText = identity.capturedText {
                    Text(capturedText)
                } else {
                    Text(identity.availabilityText)
                }
                Text(identity.ratingText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if identity.capturedText != nil {
                Text(identity.availabilityText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(identity.fullFilename)
    }

    @ViewBuilder
    private func statusAlerts(for asset: Asset) -> some View {
        if model.pendingMetadataSyncItems.contains(where: { $0.assetID == asset.id }) {
            Label("XMP sync pending", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.yellow)
        }
        if model.metadataSyncConflictItems.contains(where: { $0.assetID == asset.id }) {
            metadataConflictControls()
        }
        if !model.selectedPreviewGenerationFailures.isEmpty {
            previewFailureStatus(model.selectedPreviewGenerationFailures)
        }
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
            HStack(spacing: 10) {
                ratingButtons(for: asset)
                Divider()
                    .frame(height: 18)
                flagButtons(for: asset)
            }

            labelButtons(for: asset)
        }
    }

    private func ratingButtons(for asset: Asset) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(1...5), id: \.self) { rating in
                Button {
                    apply { try model.setRatingForSelectedAsset(rating) }
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rating <= asset.metadata.rating ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(rating)")
            }
            Button {
                apply { try model.setRatingForSelectedAsset(0) }
            } label: {
                Text("0")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(asset.metadata.rating == 0 ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Clear rating")
        }
    }

    private func flagButtons(for asset: Asset) -> some View {
        HStack(spacing: 6) {
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
    }

    private func labelButtons(for asset: Asset) -> some View {
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

    private func portableTextControls(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !asset.metadata.keywords.isEmpty {
                keywordChips(asset.metadata.keywords)
            }
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

    private func keywordChips(_ keywords: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(keywords, id: \.self) { keyword in
                Text(keyword)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
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
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Technical")
                .padding(.bottom, 4)
            ForEach(InspectorTechnicalRows(metadata: metadata).rows) { row in
                metadataRow(row)
            }
        }
    }

    private func metadataRow(_ row: InspectorMetadataRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(row.value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func evaluationSignals(_ signals: [EvaluationSignal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text("TESTSTRIP TAGS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }
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
        .padding(10)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.18))
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
