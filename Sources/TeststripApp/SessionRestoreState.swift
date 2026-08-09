import Foundation
import TeststripCore

// UI state persisted across relaunches: the selected source, the lens it was
// seen through, the saved-set scope, active search/filters, selection, and sort
// order. A mid-cull quit relaunches on the same source in Grid — actual run
// resume is the SP-D lifecycle spec's job, and in-progress culling sessions
// already survive as work sessions.
struct SessionRestoreState: Codable, Equatable, Sendable {
    // No back-compat: v1 persisted a `selectedView` route and no source at
    // all. `load()` discards a mismatched version, so a v1 blob simply
    // cold-starts the app.
    static let currentVersion = 2

    var version: Int = SessionRestoreState.currentVersion
    var lens: LibraryLens
    var source: LibrarySource
    var selectedAssetSetID: AssetSetID?
    var selectedAssetID: AssetID?
    var sortOption: LibrarySortOption
    var librarySearchText: String
    var keywordFilterText: String
    var folderFilterText: String
    var minimumRatingFilter: Int?
    var flagFilter: PickFlag?
    var colorLabelFilter: ColorLabel?
    var cameraFilterText: String
    var lensFilterText: String
    var minimumISOFilter: Int?
    var captureDateStartFilter: Date?
    var captureDateEndFilter: Date?
    var availabilityFilter: SourceAvailability?
    var evaluationKindFilter: EvaluationKind?
    var needsKeywordsFilter: Bool
    var needsEvaluationFilter: Bool
    var likelyIssuesFilter: Bool
    var potentialPicksFilter: Bool
    var providerFailuresFilter: Bool
    var metadataSyncPendingFilter: Bool
    var metadataSyncConflictFilter: Bool
    /// Predicates installed by a smart-collection selection. Without these a
    /// relaunch drops the user out of the collection they were in, because a
    /// smart collection is no longer expressible as the boolean filter
    /// properties above.
    var detachedFilterPredicates: [SetQuery.Predicate]
}

// Reads and writes SessionRestoreState via app preferences (the same mechanism
// LibraryGridView.thumbnailWidth uses), namespaced per catalog root so switching
// catalogs never cross-restores another catalog's browsing state. Injecting a nil
// `defaults` (the AppModel default) disables session restore entirely, which keeps
// it opt-in for callers that don't pass a UserDefaults suite of their own — in
// particular, every AppModel test fixture that doesn't ask for this feature.
struct SessionRestoreStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, catalogRoot: URL) {
        self.defaults = defaults
        self.key = Self.key(forCatalogRoot: catalogRoot)
    }

    static func key(forCatalogRoot catalogRoot: URL) -> String {
        "SessionRestoreState.\(catalogRoot.standardizedFileURL.path)"
    }

    func save(_ state: SessionRestoreState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> SessionRestoreState? {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(SessionRestoreState.self, from: data),
              state.version == SessionRestoreState.currentVersion else {
            return nil
        }
        return state
    }
}
