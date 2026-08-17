import XCTest
import TeststripCore
@testable import TeststripApp

/// Regression tests for the `replaceAssets` persistence hazard (issue #14).
///
/// `replaceAssets` used to unconditionally assign `selectedAssetID`, firing its
/// `didSet { persistSessionState() }` and saving ALL ~20 session-restore
/// properties on every call.  That masked persistence-trigger regressions: if a
/// `didSet` was removed from one of those properties, the regression was
/// invisible because `replaceAssets` saved everything anyway.
///
/// The fix: `replaceAssets` now defers persistence (increments
/// `sessionPersistenceDeferralDepth` without flushing), and each caller that
/// needs a save calls `persistSessionState()` explicitly.  `applyRestoredSessionState`
/// wraps its entire body in the same deferral so a single restore no longer
/// fires ~20 redundant saves that just rewrite the state that was read.
final class ReplaceAssetsPersistenceTests: XCTestCase {

    private func makePaths(directory: URL) throws -> AppCatalogPaths {
        AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
    }

    private func makeCatalog(directory: URL) throws -> AppCatalog {
        try AppCatalog.open(paths: try makePaths(directory: directory))
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "teststrip.replace-assets-persistence.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "ReplaceAssetsPersistenceTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func seedAssets(
        count: Int,
        in repository: CatalogRepository
    ) throws {
        let assets = (0..<count).map { index in
            makeAsset(id: "asset-\(index)", filename: "frame-\(index).dng")
        }
        try repository.upsert(assets)
    }

    private func makeAsset(
        id: String,
        filename: String,
        rating: Int = 0,
        flag: PickFlag? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(filename)"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(rating: rating, flag: flag)
        )
    }

    // MARK: - Tests

    /// `reload()` calls `replaceAssets` (which no longer triggers persistence)
    /// and then explicitly calls `persistSessionState()`.  The explicit save
    /// must persist `selectedAssetID` — previously this was saved as a side
    /// effect of `selectedAssetID.didSet` inside `replaceAssets`.
    func testReloadPersistsSelectedAssetIDViaExplicitSave() throws {
        let directory = try makeTemporaryDirectory(named: "reload-persists-selection")
        let defaults = try makeIsolatedDefaults()
        let catalog = try makeCatalog(directory: directory)
        try seedAssets(count: 5, in: catalog.repository)

        let model = try AppModel.load(catalog: catalog, sessionRestoreDefaults: defaults)
        try model.selectSource(.allPhotos)
        // selectSource sets selectedSource.didSet → persistSessionState() →
        // saves the state.  Verify the baseline save happened.
        let catalogRoot = try makePaths(directory: directory).root
        let baselineState = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertNotNil(baselineState, "selectSource should have persisted session state")

        // Now reload — replaceAssets is called but does NOT save; reload's
        // explicit persistSessionState() does.
        try model.reload()

        let savedState = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertNotNil(savedState, "reload() must persist session state via its explicit persistSessionState() call")
        // The selectedAssetID in the saved state must match the model's current selection.
        XCTAssertEqual(savedState?.selectedAssetID, model.selectedAssetID)
    }

    /// After setting `librarySearchText` (which saves via its `didSet`),
    /// calling `reload()` must NOT lose the search text.  The explicit
    /// `persistSessionState()` in `reload()` snapshots ALL properties,
    /// so `librarySearchText` survives.
    func testReloadDoesNotLoseLibrarySearchText() throws {
        let directory = try makeTemporaryDirectory(named: "reload-keeps-search-text")
        let defaults = try makeIsolatedDefaults()
        let catalog = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalog.repository)

        let model = try AppModel.load(catalog: catalog, sessionRestoreDefaults: defaults)
        try model.selectSource(.allPhotos)
        model.librarySearchText = "patagonia"

        let catalogRoot = try makePaths(directory: directory).root
        // Verify the didSet save captured the search text.
        let stateBeforeReload = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertEqual(stateBeforeReload?.librarySearchText, "patagonia")

        // reload() calls replaceAssets (no save) then persistSessionState() (saves all).
        try model.reload()

        let stateAfterReload = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertEqual(stateAfterReload?.librarySearchText, "patagonia",
                       "reload() must not lose librarySearchText — the explicit save snapshots all properties")
    }

    /// `applyRestoredSessionState` restores ~20 properties each carrying
    /// `didSet { persistSessionState() }`, then calls `replaceAssets` (which
    /// also used to fire `selectedAssetID.didSet`).  Without the deferral
    /// guard, a single restore fired ~20 redundant saves that simply
    /// rewrote the state just read — and crucially, `replaceAssets` would
    /// overwrite the persisted `selectedAssetID` with a fallback value when
    /// the restored ID no longer exists in the catalog.
    ///
    /// This test saves a state with a `selectedAssetID` that does NOT exist
    /// in the catalog, then loads a fresh model (which restores).  With the
    /// deferral fix, the persisted state must be unchanged — `replaceAssets`
    /// falls back to `assets.first` in memory but does NOT overwrite the
    /// saved state.
    func testApplyRestoredSessionStateDoesNotOverwritePersistedState() throws {
        let directory = try makeTemporaryDirectory(named: "restore-no-redundant-saves")
        let defaults = try makeIsolatedDefaults()
        let catalog = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalog.repository)

        // Save a state with a selectedAssetID that does NOT exist in the catalog.
        // When applyRestoredSessionState runs, replaceAssets cannot find this ID
        // and falls back to assets.first — but the deferral must prevent that
        // fallback from being persisted.
        let catalogRoot = try makePaths(directory: directory).root
        let savedAssetID = AssetID(rawValue: "nonexistent-asset")
        SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).save(
            SessionRestoreState(
                lens: .grid,
                source: .allPhotos,
                selectedAssetSetID: nil,
                selectedAssetID: savedAssetID,
                sortOption: .importOrder,
                librarySearchText: "",
                keywordFilterText: "",
                folderFilterText: "",
                minimumRatingFilter: nil,
                flagFilter: nil,
                colorLabelFilter: nil,
                cameraFilterText: "",
                lensFilterText: "",
                minimumISOFilter: nil,
                captureDateStartFilter: nil,
                captureDateEndFilter: nil,
                availabilityFilter: nil,
                evaluationKindFilter: nil,
                needsKeywordsFilter: false,
                needsEvaluationFilter: false,
                likelyIssuesFilter: false,
                potentialPicksFilter: false,
                providerFailuresFilter: false,
                metadataSyncPendingFilter: false,
                metadataSyncConflictFilter: false,
                detachedFilterPredicates: []
            )
        )

        // Load a fresh model — this calls restoreSessionStateIfAvailable →
        // applyRestoredSessionState, which restores all properties and calls
        // replaceAssets.  The deferral must suppress all saves during restore.
        let catalogB = try makeCatalog(directory: directory)
        let model = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        // In memory, replaceAssets fell back to the first asset since the
        // restored selectedAssetID doesn't exist.
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-0"),
                       "replaceAssets should fall back to first asset when restored ID is missing")

        // But the persisted state must NOT have been overwritten — the
        // deferral suppressed all didSet saves during restore, including
        // replaceAssets' selectedAssetID.didSet and selectedSource.didSet.
        let persistedState = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertNotNil(persistedState, "Persisted state should still exist after restore")
        XCTAssertEqual(persistedState?.selectedAssetID, savedAssetID,
                       "applyRestoredSessionState must not overwrite persisted state — the deferral suppresses redundant saves during restore")
    }

    /// A persisted property's `didSet` must save independently of
    /// `replaceAssets`.  After the fix, `replaceAssets` no longer saves, so
    /// the only way a property change reaches disk is through its own
    /// `didSet` (or an explicit `persistSessionState()` call).  This test
    /// verifies that setting `librarySearchText` persists it, and a
    /// subsequent `reload()` does NOT lose the value.
    func testPersistedPropertySavesIndependentlyOfReplaceAssets() throws {
        let directory = try makeTemporaryDirectory(named: "independent-persistence")
        let defaults = try makeIsolatedDefaults()
        let catalog = try makeCatalog(directory: directory)
        try seedAssets(count: 4, in: catalog.repository)

        let model = try AppModel.load(catalog: catalog, sessionRestoreDefaults: defaults)
        try model.selectSource(.allPhotos)

        let catalogRoot = try makePaths(directory: directory).root

        // Set a property — its didSet must persist it.
        model.librarySearchText = "independent-save"
        var state = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertEqual(state?.librarySearchText, "independent-save")

        // reload() calls replaceAssets (no save) then persistSessionState().
        // The explicit save must still include librarySearchText.
        try model.reload()

        state = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load()
        XCTAssertEqual(state?.librarySearchText, "independent-save",
                       "librarySearchText's didSet save must not be masked by replaceAssets")
        XCTAssertEqual(state?.selectedAssetID, model.selectedAssetID,
                       "reload()'s explicit persistSessionState() must save selectedAssetID")
    }
}
