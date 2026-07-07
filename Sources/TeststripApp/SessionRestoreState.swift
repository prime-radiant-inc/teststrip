import Foundation
import TeststripCore

// Library-browsing UI state persisted across relaunches: route, saved-set scope,
// active search/filters, selection, and sort order. Deliberately excludes anything
// culling-related (in-progress culling sessions already survive as work sessions
// and are reopened explicitly via Recent Work, not auto-restored).
struct SessionRestoreState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = SessionRestoreState.currentVersion
    var selectedView: LibraryViewMode
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
