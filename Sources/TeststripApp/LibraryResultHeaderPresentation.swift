import Foundation
import TeststripCore

/// The Library grid's result header: match count, a plain-English read of
/// the current query, filter suggestions drawn from what's actually in the
/// catalog, and the three distinct "save this" actions. Replaces
/// `SearchWorkspaceView`'s dedicated route — search results are just the
/// Library in a filtered state, not a separate surface.
public struct LibraryResultHeaderPresentation: Equatable {
    /// The three save semantics `SearchWorkspaceView` and the filter bar both
    /// offered, unified behind one menu:
    /// - `dynamicSearch`: a saved set that re-runs the query and updates as
    ///   the catalog changes (`AppModel.saveCurrentLibraryQuery`).
    /// - `frozenSnapshot`: a saved set capturing exactly today's result list
    ///   (`AppModel.saveCurrentAssetScopeSnapshot`).
    /// - `manualSet`: the selected photos only, independent of the query
    ///   (`AppModel.saveSelectedAssetAsManualSet`).
    public enum SaveAction: Equatable, Identifiable, CaseIterable {
        case dynamicSearch
        case frozenSnapshot
        case manualSet

        public var id: String { title }

        public var title: String {
            switch self {
            case .dynamicSearch: return "Save Search…"
            case .frozenSnapshot: return "Save as Snapshot…"
            case .manualSet: return "Save Selection as Set…"
            }
        }

        public var systemImage: String {
            switch self {
            case .dynamicSearch: return "bookmark"
            case .frozenSnapshot: return "camera.viewfinder"
            case .manualSet: return "rectangle.stack.badge.plus"
            }
        }
    }

    public var matchCount: Int
    public var interpretation: String?
    public var suggestedTokens: [LibraryQueryToken]
    public var saveActions: [SaveAction]
    /// True when a non-empty search produced zero results (persona-2 item 4:
    /// the reload is synchronous, but a search that finds nothing looks
    /// identical to any other "0 photos" state — a bare match, catalog-loaded
    /// empty catalog, etc — unless it's called out explicitly).
    public let isZeroMatchSearch: Bool

    public init(
        totalAssetCount: Int,
        librarySearchText: String,
        canSaveDynamicSet: Bool,
        canSaveSnapshotSet: Bool,
        canSaveManualSet: Bool,
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        evaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        activeTokens: [LibraryQueryToken] = []
    ) {
        matchCount = totalAssetCount
        interpretation = Self.interpretation(for: librarySearchText)
        suggestedTokens = Self.suggestedTokens(
            reviewQueueCounts: reviewQueueCounts,
            evaluationKindSummaries: evaluationKindSummaries,
            activeTokens: activeTokens
        )
        let trimmedSearchText = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isZeroMatchSearch = totalAssetCount == 0 && !trimmedSearchText.isEmpty
        searchTextForSummary = trimmedSearchText

        var actions: [SaveAction] = []
        if canSaveDynamicSet { actions.append(.dynamicSearch) }
        if canSaveSnapshotSet { actions.append(.frozenSnapshot) }
        if canSaveManualSet { actions.append(.manualSet) }
        saveActions = actions
    }

    /// The header's headline text: an explicit "No matches for …" when a
    /// search ran and found nothing, otherwise the plain match count.
    public var matchSummary: String {
        guard isZeroMatchSearch else {
            return matchCount == 1 ? "1 photo" : "\(matchCount) photos"
        }
        return "No matches for \u{201c}\(searchTextForSummary)\u{201d}"
    }

    private var searchTextForSummary: String = ""

    /// spec §2b: the row renders only when it has content — active tokens
    /// (`suggestedTokens`, the catalog-backed chips this row draws), a
    /// residual-text interpretation, or save-worthy state. A bare match
    /// count is not, on its own, reason to show the row (the footer already
    /// carries the count).
    public var hasContent: Bool {
        interpretation != nil || !suggestedTokens.isEmpty || !saveActions.isEmpty || isZeroMatchSearch
    }

    /// Non-nil only when plain text remains after `LibrarySearchIntent`
    /// pulls out every structured filter it recognizes — the same condition
    /// `SearchWorkspaceView`'s "Ask interpretation" row used to gate on. When
    /// the parse also produced structured tokens (e.g. an unquoted multi-word
    /// value like `camera:SmokeCam 1` splits into a `camera:` token plus a
    /// residual `"1"`), the line names the split explicitly rather than
    /// silently hiding where the structured part went.
    private static func interpretation(for searchText: String) -> String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let intent = LibrarySearchIntent.parse(trimmed)
        guard let residual = intent.residualText else { return nil }
        guard !intent.chips.isEmpty else { return "read as plain text: \(residual)" }
        return "read as \(intent.chips.joined(separator: " + ")) + plain text \"\(residual)\""
    }

    /// Absorbs `SearchWorkspaceView`'s "Generated Refinements" and "Related
    /// Filters" rails: catalog-backed suggestions for narrowing the current
    /// result set, expressed as tokens the query field's Add-filter menu
    /// already knows how to apply and remove.
    private static func suggestedTokens(
        reviewQueueCounts: [ReviewQueue: Int],
        evaluationKindSummaries: [CatalogEvaluationKindSummary],
        activeTokens: [LibraryQueryToken]
    ) -> [LibraryQueryToken] {
        let activeFields = Set(activeTokens.map(\.field))
        var tokens: [LibraryQueryToken] = []

        func addIfNeeded(_ token: LibraryQueryToken) {
            guard !activeFields.contains(token.field) else { return }
            tokens.append(token)
        }

        func hasResults(_ queue: ReviewQueue) -> Bool {
            (reviewQueueCounts[queue] ?? 0) > 0
        }

        if hasResults(.fiveStars) {
            addIfNeeded(LibraryQueryToken(field: .rating, display: "Rating >= 4", value: .int(4)))
        }
        if hasResults(.picks) {
            addIfNeeded(LibraryQueryToken(field: .flag, display: "Pick", value: .flag(.pick)))
        }
        if hasResults(.rejects) {
            addIfNeeded(LibraryQueryToken(field: .flag, display: "Reject", value: .flag(.reject)))
        }
        if hasResults(.needsKeywords) {
            addIfNeeded(LibraryQueryToken(field: .needsKeywords, display: "Needs Keywords", value: .int(0)))
        }
        if hasResults(.needsEvaluation) {
            addIfNeeded(LibraryQueryToken(field: .needsEvaluation, display: "Not analyzed yet", value: .int(0)))
        }
        if hasResults(.likelyIssues) {
            addIfNeeded(LibraryQueryToken(field: .likelyIssues, display: "Likely Issues", value: .int(0)))
        }
        if hasResults(.providerFailures) {
            addIfNeeded(LibraryQueryToken(field: .providerFailures, display: "Analysis Failures", value: .int(0)))
        }

        let summariesByKind = Dictionary(uniqueKeysWithValues: evaluationKindSummaries.map { ($0.kind, $0) })
        let signalCandidates: [(kind: EvaluationKind, display: String)] = [
            (.focus, "Signal: Focus"),
            (.object, "Signal: Object"),
            (.ocrText, "Signal: OCR Text"),
            (.faceCount, "Signal: Face Count")
        ]
        for candidate in signalCandidates {
            guard let summary = summariesByKind[candidate.kind], summary.assetCount > 0 else { continue }
            addIfNeeded(LibraryQueryToken(field: .signal, display: candidate.display, value: .signal(candidate.kind)))
        }

        return tokens
    }
}
