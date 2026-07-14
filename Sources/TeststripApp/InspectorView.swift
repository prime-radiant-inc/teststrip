import Foundation
import SwiftUI
import TeststripCore

enum InspectorPreviewLayout {
    static let size = CGSize(width: 258, height: 186)
    static let horizontalPadding: CGFloat = 14
    static let columnWidth = size.width + horizontalPadding * 2
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
        availabilityText = Self.availabilityText(for: asset.availability)
        ratingText = "Rating: \(asset.metadata.rating)"
        accessibilityValue = "\(availabilityText), \(ratingText)"
        capturedText = asset.technicalMetadata?.capturedAt?.formatted(date: .abbreviated, time: .shortened)
    }

    private static func availabilityText(for availability: SourceAvailability) -> String {
        AssetSourceStatusPresentation.presentation(for: availability)?.detail ?? "Original available"
    }
}

struct InspectorMetadataRow: Equatable, Identifiable {
    var title: String
    var value: String

    var id: String { title }
}

struct InspectorCaptionSuggestionPresentation: Equatable {
    var suggestions: [CaptionSuggestion]

    var isVisible: Bool {
        !suggestions.isEmpty
    }

    var title: String {
        "Text found"
    }

    func actionLabel(for suggestion: CaptionSuggestion) -> String {
        "Accept OCR caption"
    }

    func detailText(for suggestion: CaptionSuggestion) -> String {
        "\(suggestion.confidenceText) - \(suggestion.provenanceText)"
    }

    func helpText(for suggestion: CaptionSuggestion) -> String {
        "\(actionLabel(for: suggestion)): \(suggestion.caption)"
    }
}

struct InspectorProviderFailurePresentation: Equatable {
    var failures: [CatalogEvaluationFailure]

    var isVisible: Bool {
        !failures.isEmpty
    }

    var title: String {
        "Analysis retry needed"
    }

    func detailText(for failure: CatalogEvaluationFailure) -> String {
        "\(failure.provider) failed: \(failure.message)"
    }

    func actionLabel(for failure: CatalogEvaluationFailure) -> String {
        "Retry \(failure.provider)"
    }
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
        if let aperture = metadata.aperture {
            rows.append(InspectorMetadataRow(title: "Aperture", value: ExifSummaryFormatting.apertureText(aperture)))
        }
        if let shutterSpeed = metadata.shutterSpeed {
            rows.append(InspectorMetadataRow(title: "Shutter Speed", value: ExifSummaryFormatting.shutterSpeedText(shutterSpeed)))
        }
        if let focalLength = metadata.focalLength {
            rows.append(InspectorMetadataRow(title: "Focal Length", value: ExifSummaryFormatting.focalLengthText(focalLength)))
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
    /// A plain-English read of the score ("Sharp", "Motion blur", "Well
    /// exposed"). nil for kinds whose value is already human (an object label,
    /// OCR text, a face count). The raw float lives in `value` (Advanced only).
    var verdict: String?
}

/// Turns a raw signal score into a photographer-facing verdict. Thresholds
/// follow the same score direction the culling ranker uses (see
/// CullingQualityScore): higher focus/aesthetics/framing/face scores are
/// better, higher motion-blur is worse, and exposure is luminance centered on
/// a well-exposed midtone. Tuned for legibility, not ranking — adjust freely.
enum SignalVerdict {
    static func text(for kind: EvaluationKind, score: Double) -> String? {
        let value = min(max(score, 0), 1)
        switch kind {
        case .focus:
            return band(value, high: "Sharp", mid: "Slightly soft", low: "Soft")
        case .eyeSharpness:
            return band(value, high: "Sharp eyes", mid: "Soft eyes", low: "Blurred eyes")
        case .motionBlur:
            // Higher score = more blur (defect).
            return band(value, high: "Motion blur", mid: "Slight motion", low: "Steady")
        case .exposure:
            // Luminance: a well-exposed frame sits near the midtones.
            if value < 0.38 { return "Dark" }
            if value > 0.66 { return "Bright" }
            return "Well exposed"
        case .aesthetics:
            return band(value, high: "Strong", mid: "Decent", low: "Weak")
        case .framing:
            return band(value, high: "Well framed", mid: "OK framing", low: "Loose framing")
        case .faceQuality:
            return band(value, high: "Clear face", mid: "Soft face", low: "Poor face")
        case .eyesOpen:
            return value >= 0.6 ? "Eyes open" : "Eyes closed"
        case .smile:
            return value >= 0.6 ? "Smiling" : "Neutral"
        case .novelty:
            return band(value, high: "Distinct", mid: "Similar", low: "Near-duplicate")
        case .object, .ocrText, .faceCount, .colorPalette, .visualSimilarity:
            return nil
        }
    }

    private static func band(_ value: Double, high: String, mid: String, low: String) -> String {
        if value >= 0.66 { return high }
        if value >= 0.4 { return mid }
        return low
    }
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
        case .faceCount, .faceQuality, .smile, .eyesOpen, .eyeSharpness:
            return "Faces"
        case .ocrText:
            return "Text"
        case .object:
            return "Objects & Content"
        case .aesthetics, .framing, .colorPalette, .novelty, .visualSimilarity:
            return "Color & Look"
        }
    }

    private static func row(for signal: EvaluationSignal, index: Int) -> InspectorEvaluationSignalRow {
        let verdict: String?
        if case .score(let score) = signal.value {
            verdict = SignalVerdict.text(for: signal.kind, score: score)
        } else {
            verdict = nil
        }
        return InspectorEvaluationSignalRow(
            id: "\(index)-\(signal.kind.rawValue)-\(signal.provenance.provider)-\(signal.provenance.model)",
            title: title(for: signal.kind),
            value: valueText(for: signal.value),
            detail: "\(confidenceText(signal.confidence)) - \(signal.provenance.provider)/\(signal.provenance.model)",
            verdict: verdict
        )
    }

    private static func title(for kind: EvaluationKind) -> String {
        switch kind {
        case .focus: "Focus"
        case .motionBlur: "Motion blur"
        case .exposure: "Exposure"
        case .aesthetics: "Aesthetics"
        case .framing: "Framing"
        case .object: "Object"
        case .faceCount: "Face count"
        case .faceQuality: "Face quality"
        case .ocrText: "OCR"
        case .colorPalette: "Color"
        case .novelty: "Novelty"
        case .visualSimilarity: "Visual similarity"
        case .smile: "Smile"
        case .eyesOpen: "Eyes open"
        case .eyeSharpness: "Eye sharpness"
        }
    }

    private static func valueText(for value: EvaluationValue) -> String {
        switch value {
        case .score(let score):
            String(format: "%.2f", score)
        case .label(let label):
            label
        case .labels(let labels):
            labels.joined(separator: ", ")
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
        case synced
    }

    enum ConflictSidecarMetadataState: Equatable {
        case notLoaded
        case readable(AssetMetadata)
        case unreadable

        init(_ state: MetadataSyncConflictSidecarMetadataState) {
            switch state {
            case .none:
                self = .notLoaded
            case .readable(let metadata):
                self = .readable(metadata)
            case .unreadable:
                self = .unreadable
            }
        }
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
    var conflictActions: [InspectorMetadataConflictActionPresentation]

    init?(
        asset: Asset,
        pendingItems: [MetadataSyncItem],
        conflictItems: [MetadataSyncItem],
        conflictSidecarMetadata: AssetMetadata? = nil,
        conflictSidecarMetadataState: ConflictSidecarMetadataState? = nil
    ) {
        if let conflict = conflictItems.first(where: { $0.assetID == asset.id }) {
            let sidecarState = conflictSidecarMetadataState
                ?? conflictSidecarMetadata.map { .readable($0) }
                ?? .notLoaded
            let sidecarMetadata: AssetMetadata?
            let sidecarMetadataReadable: Bool
            switch sidecarState {
            case .notLoaded:
                sidecarMetadata = nil
                sidecarMetadataReadable = true
            case .readable(let metadata):
                sidecarMetadata = metadata
                sidecarMetadataReadable = true
            case .unreadable:
                sidecarMetadata = nil
                sidecarMetadataReadable = false
            }
            let rows = sidecarMetadata.map {
                Self.conflictRows(catalog: asset.metadata, sidecar: $0)
            } ?? []
            self.init(
                kind: .conflict,
                item: conflict,
                title: "XMP conflict",
                detail: Self.conflictDetail(rows: rows, sidecarMetadataReadable: sidecarMetadataReadable),
                conflictRows: rows,
                conflictActions: InspectorMetadataConflictActionPresentation.actions(sidecarMetadataReadable: sidecarMetadataReadable)
            )
            return
        }
        if let pending = pendingItems.first(where: { $0.assetID == asset.id }) {
            self.init(
                kind: .pending,
                item: pending,
                title: "XMP sync pending",
                detail: "Catalog metadata is saved; sidecar write is waiting to retry.",
                conflictRows: [],
                conflictActions: []
            )
            return
        }
        // Positive confirmation: the user has written portable metadata and
        // there's nothing pending or in conflict, so the XMP sidecar is on disk
        // and current. Otherwise there is nothing to confirm.
        if asset.metadata.hasWrittenPortableMetadata {
            self.init(syncedSidecarFilename: asset.originalURL.appendingPathExtension("xmp").lastPathComponent)
            return
        }
        return nil
    }

    private init(syncedSidecarFilename: String) {
        self.kind = .synced
        self.title = "Saved to sidecar"
        self.detail = ""
        self.sidecarFilename = syncedSidecarFilename
        self.sidecarPath = ""
        self.catalogGenerationText = ""
        self.conflictRows = []
        self.conflictActions = []
    }

    private init(
        kind: Kind,
        item: MetadataSyncItem,
        title: String,
        detail: String,
        conflictRows: [ConflictRow],
        conflictActions: [InspectorMetadataConflictActionPresentation]
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.sidecarFilename = item.sidecarURL.lastPathComponent
        self.sidecarPath = item.sidecarURL.path
        self.catalogGenerationText = "Catalog generation \(item.catalogGeneration)"
        self.conflictRows = conflictRows
        self.conflictActions = conflictActions
    }

    private static func conflictDetail(rows: [ConflictRow], sidecarMetadataReadable: Bool) -> String {
        guard sidecarMetadataReadable else {
            return "XMP sidecar metadata could not be read. Use Catalog to recreate the sidecar, or restore the sidecar before importing it."
        }
        return rows.isEmpty
            ? "Catalog and sidecar both changed since the last sync."
            : "Review changed fields before choosing whether Catalog or XMP wins."
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

/// Identifies the three inspector sections that carry a ⌥⌘1..3 menu
/// shortcut (Task 11). Task 6 restacked the inspector from tabs into one
/// continuous scroll, but these enumerate the sections' menu-driven
/// scroll-to targets and (via `InspectorTabPresentation`) their element
/// coverage; People has no shortcut and so isn't a case here.
public enum InspectorTab: String, CaseIterable, Identifiable, Sendable {
    case info
    case describe
    case ai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .info: "Info"
        case .describe: "Describe"
        case .ai: "AI"
        }
    }

    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .info: "1"
        case .describe: "2"
        case .ai: "3"
        }
    }
}

/// Every element the on-demand inspector renders, so the tab assignment can
/// be enumerated and checked for orphans (see `InspectorTabsPresentationTests`).
public enum InspectorElement: CaseIterable, Sendable {
    // Info
    case preview
    case identityHeader
    case ratingDisplay
    case flagDisplay
    case labelDisplay
    case exifRows
    case syncStatus
    case conflictResolver
    case previewRetry
    // Describe
    case keywordChips
    case keywordField
    case suggestedKeywords
    case captionField
    case ocrCaptionSuggestions
    case creatorField
    case copyrightField
    case multiSelectNote
    case ratingEditButtons
    case flagEditButtons
    case labelEditButtons
    // AI
    case verdictGroups
    case technicalDetailsDisclosure
    case providerFailureRetry
}

/// The binding assignment of every inspector element to exactly one tab,
/// per the Task 11 brief. Data (not a switch), so the anti-orphan tests can
/// actually catch a missed or duplicated assignment.
public enum InspectorTabPresentation {
    public static let elementsByTab: [InspectorTab: [InspectorElement]] = [
        .info: [
            .preview,
            .identityHeader,
            .ratingDisplay,
            .flagDisplay,
            .labelDisplay,
            .exifRows,
            .syncStatus,
            .conflictResolver,
            .previewRetry
        ],
        .describe: [
            .keywordChips,
            .keywordField,
            .suggestedKeywords,
            .captionField,
            .ocrCaptionSuggestions,
            .creatorField,
            .copyrightField,
            .multiSelectNote,
            .ratingEditButtons,
            .flagEditButtons,
            .labelEditButtons
        ],
        .ai: [
            .verdictGroups,
            .technicalDetailsDisclosure,
            .providerFailureRetry
        ]
    ]
}

struct InspectorView: View {
    var model: AppModel
    @State private var metadataDraft = InspectorMetadataDraft()
    @State private var isShowingSignalDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if let asset = model.selectedAsset {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            inspectorSection(InspectorTab.info.title) {
                                infoTabBody(for: asset)
                            }
                            .id(InspectorTab.info)

                            inspectorSection(InspectorTab.describe.title) {
                                describeTabBody(for: asset)
                            }
                            .id(InspectorTab.describe)
                            .onAppear {
                                metadataDraft.sync(to: asset)
                            }
                            .onChange(of: asset.id) { _, _ in
                                metadataDraft.sync(to: asset)
                            }

                            inspectorSection(InspectorTab.ai.title) {
                                aiTabBody(for: asset)
                            }
                            .id(InspectorTab.ai)

                            inspectorSection("People") {
                                peopleSectionBody(for: asset)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.inspectorScrollRequestToken) { _, _ in
                        withAnimation {
                            proxy.scrollTo(model.inspectorScrollTarget, anchor: .top)
                        }
                    }
                }
            } else {
                ScrollView {
                    Text("No selection")
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: InspectorPreviewLayout.columnWidth)
    }

    /// One stacked inspector section: a header label above its content, and
    /// a trailing divider against whatever follows it in the stack.
    @ViewBuilder
    private func inspectorSection(
        _ title: String,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }

    @ViewBuilder
    private func infoTabBody(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            selectedPreview(for: asset)
            assetHeader(for: asset)
            metadataDisplaySummary(for: asset)
            infoStatusAlerts(for: asset)
            if let technicalMetadata = asset.technicalMetadata {
                technicalMetadataView(technicalMetadata)
            }
        }
    }

    @ViewBuilder
    private func describeTabBody(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            metadataControls(for: asset)
            portableTextControls(for: asset)
        }
    }

    @ViewBuilder
    private func aiTabBody(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            providerFailureAlert(for: asset)
            let signals = model.selectedEvaluationSignals
            if !signals.isEmpty {
                evaluationSignals(signals)
            }
        }
    }

    private func peopleSectionBody(for asset: Asset) -> some View {
        PhotoFacesSectionView(model: model, asset: asset)
    }

    /// Read-only rating/flag/label summary for the Info tab. The interactive
    /// editing controls (star buttons, flag buttons, label swatches) live in
    /// the Describe tab as metadata-authoring actions.
    private func metadataDisplaySummary(for asset: Asset) -> some View {
        HStack(spacing: 10) {
            Text(ratingDisplayText(asset.metadata.rating))
            Text(flagDisplayText(asset.metadata.flag))
            Text(labelDisplayText(asset.metadata.colorLabel))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rating, flag, and label")
    }

    private func ratingDisplayText(_ rating: Int) -> String {
        rating > 0 ? String(repeating: "\u{2605}", count: rating) : "No rating"
    }

    private func flagDisplayText(_ flag: PickFlag?) -> String {
        switch flag {
        case .pick: "Pick"
        case .reject: "Reject"
        case nil: "No flag"
        }
    }

    private func labelDisplayText(_ label: ColorLabel?) -> String {
        label?.rawValue.capitalized ?? "No label"
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
    private func infoStatusAlerts(for asset: Asset) -> some View {
        if let syncStatus = InspectorMetadataSyncStatus(
            asset: asset,
            pendingItems: model.pendingMetadataSyncItems,
            conflictItems: model.metadataSyncConflictItems,
            conflictSidecarMetadataState: InspectorMetadataSyncStatus.ConflictSidecarMetadataState(
                model.selectedMetadataSyncConflictSidecarMetadataState
            )
        ) {
            metadataSyncStatus(syncStatus)
        }
        if !model.selectedPreviewGenerationFailures.isEmpty {
            previewFailureStatus(model.selectedPreviewGenerationFailures)
        }
    }

    @ViewBuilder
    private func providerFailureAlert(for asset: Asset) -> some View {
        let providerFailurePresentation = InspectorProviderFailurePresentation(failures: model.selectedProviderFailures)
        if providerFailurePresentation.isVisible {
            providerFailureStatus(providerFailurePresentation)
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

    private func providerFailureStatus(_ presentation: InspectorProviderFailurePresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(presentation.title, systemImage: "bolt.horizontal.circle")
                .font(.caption)
                .foregroundStyle(.yellow)
            ForEach(presentation.failures, id: \.provider) { failure in
                Text(presentation.detailText(for: failure))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button {
                    apply { try model.retrySelectedProviderFailure(provider: failure.provider) }
                } label: {
                    Label(presentation.actionLabel(for: failure), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!model.canRetrySelectedProviderFailure(provider: failure.provider))
            }
        }
    }

    @ViewBuilder
    private func metadataSyncStatus(_ status: InspectorMetadataSyncStatus) -> some View {
        if status.kind == .synced {
            // A calm, human confirmation — not the pending/conflict diagnostics.
            Label("\(status.title) · \(status.sidecarFilename)", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
        } else {
            metadataSyncDiagnostics(status)
        }
    }

    private func metadataSyncDiagnostics(_ status: InspectorMetadataSyncStatus) -> some View {
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
                metadataConflictControls(status.conflictActions)
            case .synced:
                EmptyView()
            }
        }
    }

    private func metadataConflictControls(_ actions: [InspectorMetadataConflictActionPresentation]) -> some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    applyMetadataConflictAction(action.kind)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
                .help(action.help)
                .disabled(!action.isEnabled)
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

            if model.selectedBatchAssetCount > 1 {
                Text("Rating, flag, and label apply to all \(model.selectedBatchAssetCount) selected photos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ratingButtons(for asset: Asset) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(1...5), id: \.self) { rating in
                Button {
                    apply { try model.setRatingForSelectedAssets(rating) }
                } label: {
                    Image(systemName: DesignGlyph.rating.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rating <= asset.metadata.rating ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(rating)")
                .accessibilityLabel("Rate \(rating)")
            }
            Button {
                apply { try model.setRatingForSelectedAssets(0) }
            } label: {
                Text("0")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(asset.metadata.rating == 0 ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Clear rating")
            .accessibilityLabel("Clear rating")
        }
    }

    private func flagButtons(for asset: Asset) -> some View {
        HStack(spacing: 6) {
            Button {
                apply { try model.setFlagForSelectedAssets(.pick) }
            } label: {
                Image(systemName: DesignGlyph.pick.symbolName)
                    .foregroundStyle(asset.metadata.flag == .pick ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Pick")
            .accessibilityLabel("Pick")
            Button {
                apply { try model.setFlagForSelectedAssets(.reject) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(asset.metadata.flag == .reject ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help("Reject")
            .accessibilityLabel("Reject")
            Button {
                apply { try model.setFlagForSelectedAssets(nil) }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(asset.metadata.flag == nil ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Clear flag")
            .accessibilityLabel("Clear flag")
        }
    }

    private func labelButtons(for asset: Asset) -> some View {
        HStack(spacing: 8) {
            Text("Label")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                apply { try model.setColorLabelForSelectedAssets(nil) }
            } label: {
                Image(systemName: "slash.circle")
                    .foregroundStyle(asset.metadata.colorLabel == nil ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Clear label")
            .accessibilityLabel("Clear label")
            ForEach(ColorLabel.allCases, id: \.self) { label in
                Button {
                    apply { try model.setColorLabelForSelectedAssets(label) }
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
                .accessibilityLabel("\(label.rawValue.capitalized) label")
            }
        }
    }

    private func portableTextControls(for asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !asset.metadata.keywords.isEmpty {
                keywordChips(asset.metadata.keywords)
            }
            metadataTextField("Keywords", text: $metadataDraft.keywords) {
                try model.setKeywordTextForSelectedAssets(metadataDraft.keywords)
            }
            let suggestions = model.selectedSuggestedKeywords
            if !suggestions.isEmpty {
                suggestedKeywordChips(suggestions)
            }
            metadataTextField("Caption", text: $metadataDraft.caption) {
                try model.setCaptionForSelectedAssets(metadataDraft.caption)
            }
            let captionPresentation = InspectorCaptionSuggestionPresentation(suggestions: model.selectedSuggestedCaptions)
            if captionPresentation.isVisible {
                suggestedCaptionButtons(captionPresentation)
            }
            metadataTextField("Creator", text: $metadataDraft.creator) {
                try model.setCreatorForSelectedAssets(metadataDraft.creator)
            }
            metadataTextField("Copyright", text: $metadataDraft.copyright) {
                try model.setCopyrightForSelectedAssets(metadataDraft.copyright)
            }
            if model.selectedBatchAssetCount > 1 {
                Text("Keywords, caption, creator, and copyright apply to all \(model.selectedBatchAssetCount) selected photos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                    apply { try model.removeKeywordFromSelectedAssets(keyword) }
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
                Image(systemName: DesignGlyph.ai.symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Suggestions")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 5)], alignment: .leading, spacing: 5) {
                ForEach(suggestions) { suggestion in
                    Button {
                        apply { try model.acceptSuggestedKeywordForSelectedAssets(suggestion.keyword) }
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

    private func suggestedCaptionButtons(_ presentation: InspectorCaptionSuggestionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "text.viewfinder")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(presentation.title)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(presentation.suggestions) { suggestion in
                    Button {
                        apply {
                            try model.acceptSuggestedCaptionForSelectedAssets(suggestion.caption)
                            metadataDraft.caption = suggestion.caption
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text(presentation.actionLabel(for: suggestion))
                                    .font(.caption2.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(presentation.detailText(for: suggestion))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(suggestion.caption)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.orange.opacity(0.18))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(presentation.helpText(for: suggestion))
                    .accessibilityLabel(presentation.helpText(for: suggestion))
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
                    // Carve-in per spec §2c/Out-of-scope: these AXTextFields
                    // were untargetable by role+label once populated (the
                    // placeholder-derived title stops standing in for an
                    // accessibility label), so they get an explicit one.
                    .accessibilityLabel(title)
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
                .accessibilityLabel("Apply \(title)")
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
                Image(systemName: DesignGlyph.ai.symbolName)
                    .foregroundStyle(.orange)
                Text("What Teststrip sees")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(row.verdict ?? row.value)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $isShowingSignalDetails) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(groups) { group in
                        ForEach(group.rows) { row in
                            Text("\(row.title): \(row.value) · \(row.detail)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Technical details")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
    var isEnabled: Bool

    var id: Kind { kind }

    static let actions = actions(sidecarMetadataReadable: true)

    static func actions(sidecarMetadataReadable: Bool) -> [InspectorMetadataConflictActionPresentation] {
        [
        InspectorMetadataConflictActionPresentation(
            kind: .mergeMissingSidecarFields,
            title: "Merge Missing",
            systemImage: "arrow.triangle.merge",
            help: "Fill missing catalog metadata from XMP and write the merged sidecar",
            isEnabled: sidecarMetadataReadable
        ),
        InspectorMetadataConflictActionPresentation(
            kind: .useCatalog,
            title: "Use Catalog",
            systemImage: "internaldrive",
            help: "Keep catalog metadata and overwrite the XMP sidecar",
            isEnabled: true
        ),
        InspectorMetadataConflictActionPresentation(
            kind: .useSidecar,
            title: "Use XMP",
            systemImage: "doc.text",
            help: "Import XMP sidecar metadata into the catalog",
            isEnabled: sidecarMetadataReadable
        )
        ]
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
