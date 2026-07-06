import Foundation
import SwiftUI
import TeststripCore

enum InspectorPreviewLayout {
    static let size = CGSize(width: 258, height: 186)
    static let pinsPreviewAboveMetadataScroll = true
}

struct InspectorAssetIdentity: Equatable {
    var fullFilename: String
    var displayName: String
    var extensionBadge: String?
    var availabilityText: String
    var ratingText: String
    var accessibilityValue: String
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
        accessibilityValue = "\(availabilityText), \(ratingText)"
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

struct InspectorEvaluationSignalRow: Equatable, Identifiable {
    var id: String
    var title: String
    var value: String
    var detail: String
}

struct InspectorEvaluationSignalGroup: Equatable, Identifiable {
    var title: String
    var rows: [InspectorEvaluationSignalRow]

    var id: String { title }

    static func groups(for signals: [EvaluationSignal]) -> [InspectorEvaluationSignalGroup] {
        var rowsByGroup: [String: [InspectorEvaluationSignalRow]] = [:]
        for (index, signal) in signals.enumerated() {
            let groupTitle = groupTitle(for: signal.kind)
            rowsByGroup[groupTitle, default: []].append(row(for: signal, index: index))
        }
        return groupOrder.compactMap { title in
            guard let rows = rowsByGroup[title], !rows.isEmpty else { return nil }
            return InspectorEvaluationSignalGroup(title: title, rows: rows)
        }
    }

    private static let groupOrder = [
        "Technical Quality",
        "Faces",
        "Text",
        "Objects & Content",
        "Color & Look"
    ]

    private static func groupTitle(for kind: EvaluationKind) -> String {
        switch kind {
        case .focus, .motionBlur, .exposure:
            return "Technical Quality"
        case .faceCount, .faceQuality:
            return "Faces"
        case .ocrText:
            return "Text"
        case .object:
            return "Objects & Content"
        case .aesthetics, .colorPalette, .novelty, .visualSimilarity:
            return "Color & Look"
        }
    }

    private static func row(for signal: EvaluationSignal, index: Int) -> InspectorEvaluationSignalRow {
        InspectorEvaluationSignalRow(
            id: "\(index)-\(signal.kind.rawValue)-\(signal.provenance.provider)-\(signal.provenance.model)",
            title: title(for: signal.kind),
            value: valueText(for: signal.value),
            detail: "\(confidenceText(signal.confidence)) - \(signal.provenance.provider)/\(signal.provenance.model)"
        )
    }

    private static func title(for kind: EvaluationKind) -> String {
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
        case .visualSimilarity: "Visual similarity"
        }
    }

    private static func valueText(for value: EvaluationValue) -> String {
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

    private static func confidenceText(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

struct InspectorMetadataSyncStatus: Equatable {
    enum Kind: Equatable {
        case pending
        case conflict
    }

    struct ConflictRow: Equatable, Identifiable {
        var id: String { title }
        var title: String
        var catalogValue: String
        var sidecarValue: String
    }

    var kind: Kind
    var title: String
    var detail: String
    var sidecarFilename: String
    var sidecarPath: String
    var catalogGenerationText: String
    var conflictRows: [ConflictRow]

    init?(
        asset: Asset,
        pendingItems: [MetadataSyncItem],
        conflictItems: [MetadataSyncItem],
        conflictSidecarMetadata: AssetMetadata? = nil
    ) {
        if let conflict = conflictItems.first(where: { $0.assetID == asset.id }) {
            let rows = conflictSidecarMetadata.map {
                Self.conflictRows(catalog: asset.metadata, sidecar: $0)
            } ?? []
            self.init(
                kind: .conflict,
                item: conflict,
                title: "XMP conflict",
                detail: rows.isEmpty
                    ? "Catalog and sidecar both changed since the last sync."
                    : "Review changed fields before choosing whether Catalog or XMP wins.",
                conflictRows: rows
            )
            return
        }
        if let pending = pendingItems.first(where: { $0.assetID == asset.id }) {
            self.init(
                kind: .pending,
                item: pending,
                title: "XMP sync pending",
                detail: "Catalog metadata is saved; sidecar write is waiting to retry.",
                conflictRows: []
            )
            return
        }
        return nil
    }

    private init(kind: Kind, item: MetadataSyncItem, title: String, detail: String, conflictRows: [ConflictRow]) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.sidecarFilename = item.sidecarURL.lastPathComponent
        self.sidecarPath = item.sidecarURL.path
        self.catalogGenerationText = "Catalog generation \(item.catalogGeneration)"
        self.conflictRows = conflictRows
    }

    private static func conflictRows(catalog: AssetMetadata, sidecar: AssetMetadata) -> [ConflictRow] {
        [
            conflictRow(title: "Rating", catalogValue: "\(catalog.rating)", sidecarValue: "\(sidecar.rating)"),
            conflictRow(title: "Color label", catalogValue: valueText(catalog.colorLabel), sidecarValue: valueText(sidecar.colorLabel)),
            conflictRow(title: "Flag", catalogValue: valueText(catalog.flag), sidecarValue: valueText(sidecar.flag)),
            conflictRow(title: "Keywords", catalogValue: catalog.keywords.joined(separator: ", "), sidecarValue: sidecar.keywords.joined(separator: ", ")),
            conflictRow(title: "Caption", catalogValue: valueText(catalog.caption), sidecarValue: valueText(sidecar.caption)),
            conflictRow(title: "Creator", catalogValue: valueText(catalog.creator), sidecarValue: valueText(sidecar.creator)),
            conflictRow(title: "Copyright", catalogValue: valueText(catalog.copyright), sidecarValue: valueText(sidecar.copyright))
        ].compactMap { $0 }
    }

    private static func conflictRow(title: String, catalogValue: String, sidecarValue: String) -> ConflictRow? {
        guard catalogValue != sidecarValue else { return nil }
        return ConflictRow(title: title, catalogValue: catalogValue, sidecarValue: sidecarValue)
    }

    private static func valueText(_ label: ColorLabel?) -> String {
        label?.rawValue ?? "-"
    }

    private static func valueText(_ flag: PickFlag?) -> String {
        flag?.rawValue ?? "-"
    }

    private static func valueText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }
}

struct InspectorView: View {
    var model: AppModel
    @State private var metadataDraft = InspectorMetadataDraft()

    var body: some View {
        VStack(spacing: 0) {
            if let asset = model.selectedAsset {
                VStack(alignment: .leading, spacing: 10) {
                    selectedPreview(for: asset)
                    assetHeader(for: asset)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView {
                    Text("No selection")
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .accessibilityValue(identity.accessibilityValue)
    }

    @ViewBuilder
    private func statusAlerts(for asset: Asset) -> some View {
        if let syncStatus = InspectorMetadataSyncStatus(
            asset: asset,
            pendingItems: model.pendingMetadataSyncItems,
            conflictItems: model.metadataSyncConflictItems,
            conflictSidecarMetadata: model.selectedMetadataSyncConflictSidecarMetadata
        ) {
            metadataSyncStatus(syncStatus)
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

    private func metadataSyncStatus(_ status: InspectorMetadataSyncStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(status.title, systemImage: status.kind == .conflict ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(status.kind == .conflict ? .red : .yellow)
            Text(status.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.sidecarFilename)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                Text(status.catalogGenerationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(status.sidecarPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !status.conflictRows.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(status.conflictRows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(row.catalogValue)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(row.sidecarValue)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                        }
                    }
                }
            }
            switch status.kind {
            case .pending:
                Button {
                    apply { try model.retrySelectedMetadataSync() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!model.canRetrySelectedMetadataSync)
            case .conflict:
                metadataConflictControls()
            }
        }
    }

    private func metadataConflictControls() -> some View {
        HStack(spacing: 8) {
            ForEach(InspectorMetadataConflictActionPresentation.actions) { action in
                Button {
                    applyMetadataConflictAction(action.kind)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
                .help(action.help)
            }
        }
        .controlSize(.small)
    }

    private func applyMetadataConflictAction(_ action: InspectorMetadataConflictActionPresentation.Kind) {
        switch action {
        case .mergeMissingSidecarFields:
            apply { try model.resolveSelectedMetadataConflictByMergingMissingSidecarFields() }
        case .useCatalog:
            apply { try model.resolveSelectedMetadataConflictUsingCatalog() }
        case .useSidecar:
            apply { try model.resolveSelectedMetadataConflictUsingSidecar() }
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
            let suggestions = model.selectedSuggestedKeywords
            if !suggestions.isEmpty {
                suggestedKeywordChips(suggestions)
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
                Button {
                    apply { try model.removeKeywordFromSelectedAsset(keyword) }
                } label: {
                    HStack(spacing: 5) {
                        Text(keyword)
                            .lineLimit(1)
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Remove \(keyword)")
                .accessibilityLabel("Remove keyword \(keyword)")
            }
        }
    }

    private func suggestedKeywordChips(_ suggestions: [KeywordSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("TESTSTRIP SUGGESTS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 5)], alignment: .leading, spacing: 5) {
                ForEach(suggestions) { suggestion in
                    Button {
                        apply { try model.acceptSuggestedKeywordForSelectedAsset(suggestion.keyword) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(suggestion.keyword)
                                .lineLimit(1)
                            Text(suggestion.confidenceText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.orange.opacity(0.18))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Accept \(suggestion.keyword)")
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
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
        let groups = InspectorEvaluationSignalGroup.groups(for: signals)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text("TESTSTRIP SIGNALS")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.title): \(row.value)")
                                .font(.caption)
                                .lineLimit(1)
                            Text(row.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct InspectorMetadataConflictActionPresentation: Equatable, Identifiable {
    enum Kind: Equatable {
        case mergeMissingSidecarFields
        case useCatalog
        case useSidecar
    }

    var kind: Kind
    var title: String
    var systemImage: String
    var help: String

    var id: Kind { kind }

    static let actions = [
        InspectorMetadataConflictActionPresentation(
            kind: .mergeMissingSidecarFields,
            title: "Merge Missing",
            systemImage: "arrow.triangle.merge",
            help: "Fill missing catalog metadata from XMP and write the merged sidecar"
        ),
        InspectorMetadataConflictActionPresentation(
            kind: .useCatalog,
            title: "Use Catalog",
            systemImage: "internaldrive",
            help: "Keep catalog metadata and overwrite the XMP sidecar"
        ),
        InspectorMetadataConflictActionPresentation(
            kind: .useSidecar,
            title: "Use XMP",
            systemImage: "doc.text",
            help: "Import XMP sidecar metadata into the catalog"
        )
    ]
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
