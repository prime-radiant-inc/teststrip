import XCTest
import TeststripCore
@testable import TeststripApp

final class AppModelSessionRestoreTests: XCTestCase {
    func testRestoresSelectedViewSearchTextAndFilters() throws {
        let directory = try makeTemporaryDirectory(named: "restore-filters")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 5, in: catalogA.repository)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.allPhotos)
        modelA.librarySearchText = "patagonia"
        modelA.minimumRatingFilter = 4
        modelA.flagFilter = .pick
        try modelA.applyLibraryFilters()

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedView, .grid)
        XCTAssertEqual(modelB.librarySearchText, "patagonia")
        XCTAssertEqual(modelB.minimumRatingFilter, 4)
        XCTAssertEqual(modelB.flagFilter, .pick)
    }

    func testRestoresDefaultByline() throws {
        let directory = try makeTemporaryDirectory(named: "restore-byline")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        modelA.defaultCreator = "Jesse Vincent"
        modelA.defaultCopyright = "© 2026 Jesse Vincent"

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.defaultCreator, "Jesse Vincent")
        XCTAssertEqual(modelB.defaultCopyright, "© 2026 Jesse Vincent")
    }

    func testRestoresDefaultCardImportDestination() throws {
        let directory = try makeTemporaryDirectory(named: "restore-card-import-destination")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        XCTAssertEqual(modelA.defaultCardImportDestination, "")

        modelA.defaultCardImportDestination = "/Volumes/Photos"

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.defaultCardImportDestination, "/Volumes/Photos")
    }

    func testRestoresBurstIntervalSeconds() throws {
        let directory = try makeTemporaryDirectory(named: "restore-burst-interval")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        XCTAssertEqual(modelA.burstIntervalSeconds, AssetStackBuilder.defaultMaximumCaptureGap)

        modelA.burstIntervalSeconds = 8

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.burstIntervalSeconds, 8)
    }

    func testRestoresSelectedAssetSetScope() throws {
        let directory = try makeTemporaryDirectory(named: "restore-scope")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 6, in: catalogA.repository, ratingForIndex: { $0 < 3 ? 5 : 1 })
        let assetSetID = AssetSetID(rawValue: "top-picks")
        try catalogA.repository.upsert(AssetSet.dynamic(
            id: assetSetID,
            name: "Top Picks",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        ))

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.applyAssetSet(id: assetSetID)
        XCTAssertEqual(modelA.assets.count, 3)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedAssetSetID, assetSetID)
        XCTAssertEqual(modelB.assets.count, 3)
        XCTAssertTrue(modelB.assets.allSatisfy { $0.metadata.rating == 5 })
    }

    // Pins the claim in SessionRestoreState.detachedFilterPredicates' doc
    // comment: a smart collection is only expressible through its query
    // predicates, so without restoring them a relaunch silently drops the
    // user back to the unfiltered library. `.picks` has no legacy boolean
    // counterpart on SessionRestoreState (unlike, say, `.fiveStars`'
    // `.ratingAtLeast` overlapping `minimumRatingFilter`), so this can only
    // pass via `detachedFilterPredicates`.
    func testRestoresSmartCollectionScope() throws {
        let directory = try makeTemporaryDirectory(named: "restore-smart-collection")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        let pick = makeAsset(id: "asset-pick", filename: "pick.dng", flag: .pick)
        let plain = makeAsset(id: "asset-plain", filename: "plain.dng")
        try catalogA.repository.upsert([pick, plain])

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.smartCollection(.picks))
        XCTAssertEqual(modelA.activeLibraryFilterChips, ["Pick"])
        XCTAssertEqual(modelA.assets.map(\.id), [pick.id])

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.activeLibraryFilterChips, ["Pick"])
        XCTAssertEqual(modelB.assets.map(\.id), [pick.id])
        XCTAssertEqual(modelB.totalAssetCount, 1)
        // The persisted source has to name the scope the chips/assets above
        // actually belong to — otherwise the scope line would say "All
        // Photos" while the grid shows the Picks smart collection.
        XCTAssertEqual(modelB.selectedSource, LibrarySource.smartCollection(.picks))
    }

    // The inverse of testRestoresSmartCollectionScope: widening back out of a
    // scope (removing its only filter chip) has to persist just as faithfully
    // as narrowing into one. `applySource`/`applySmartCollection` write the
    // filter properties first and `selectedSource` last with no save after
    // it; `removeActiveLibraryFilter` resets `selectedSource` to `.allPhotos`
    // only after `reload()` has already saved the cleared filters under the
    // stale scope. A relaunch must show all photos under the "All Photos"
    // name, not all photos mislabeled "Picks".
    func testRestoresAllPhotosAfterRemovingTheLastFilterChip() throws {
        let directory = try makeTemporaryDirectory(named: "restore-remove-last-chip")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        let pick = makeAsset(id: "asset-pick", filename: "pick.dng", flag: .pick)
        let plain = makeAsset(id: "asset-plain", filename: "plain.dng")
        try catalogA.repository.upsert([pick, plain])

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.smartCollection(.picks))
        let pickRow = try XCTUnwrap(modelA.activeLibraryFilterRows.first { $0.title == "Pick" })
        try modelA.removeActiveLibraryFilter(pickRow)
        XCTAssertEqual(modelA.selectedSource, .allPhotos)
        XCTAssertTrue(modelA.activeLibraryFilterChips.isEmpty)
        XCTAssertEqual(Set(modelA.assets.map(\.id)), Set([pick.id, plain.id]))

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertTrue(modelB.activeLibraryFilterChips.isEmpty)
        XCTAssertEqual(Set(modelB.assets.map(\.id)), Set([pick.id, plain.id]))
        // The persisted source has to match what's actually shown above (all
        // photos, unfiltered) — not the smart collection the user backed out
        // of.
        XCTAssertEqual(modelB.selectedSource, LibrarySource.allPhotos)
    }

    func testRestoresSortOptionAndAppliesItToLoadedAssets() throws {
        let directory = try makeTemporaryDirectory(named: "restore-sort")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try catalogA.repository.upsert([
            makeAsset(id: "charlie", filename: "charlie.jpg"),
            makeAsset(id: "alpha", filename: "alpha.jpg"),
            makeAsset(id: "bravo", filename: "bravo.jpg")
        ])

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        XCTAssertEqual(modelA.assets.map(\.id.rawValue), ["charlie", "alpha", "bravo"])
        try modelA.setLibrarySortOption(.filename)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.librarySortOption, .filename)
        XCTAssertEqual(modelB.assets.map(\.id.rawValue), ["alpha", "bravo", "charlie"])
    }

    func testRestoresSelectedAssetIDWhenStillPresent() throws {
        let directory = try makeTemporaryDirectory(named: "restore-selection")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 5, in: catalogA.repository)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        let targetID = AssetID(rawValue: "asset-3")
        modelA.select(targetID)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedAssetID, targetID)
    }

    func testFallsBackSilentlyWhenSelectedAssetSetWasDeleted() throws {
        let directory = try makeTemporaryDirectory(named: "restore-deleted-set")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 4, in: catalogA.repository)
        let assetSetID = AssetSetID(rawValue: "gone-by-relaunch")
        try catalogA.repository.upsert(AssetSet.dynamic(
            id: assetSetID,
            name: "Gone Set",
            query: SetQuery(predicates: [.ratingAtLeast(1)])
        ))

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.applyAssetSet(id: assetSetID)
        try catalogA.repository.deleteAssetSet(id: assetSetID)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertNil(modelB.selectedAssetSetID)
        XCTAssertEqual(modelB.assets.count, 4)
    }

    func testFallsBackSilentlyWhenSelectedAssetIsGone() throws {
        let directory = try makeTemporaryDirectory(named: "restore-deleted-asset")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)
        let catalogRoot = try makePaths(directory: directory).root
        SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).save(
            Self.stateReferencing(assetID: AssetID(rawValue: "never-existed"))
        )

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertNotNil(modelB.selectedAssetID)
        XCTAssertTrue(modelB.assets.contains { $0.id == modelB.selectedAssetID })
    }

    func testDoesNotRestoreCullingViewRoutes() throws {
        let directory = try makeTemporaryDirectory(named: "restore-no-culling-route")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)
        let catalogRoot = try makePaths(directory: directory).root
        SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).save(
            Self.stateReferencing(lens: .cull)
        )

        let modelB = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedView, .grid)
    }

    func testDoesNotRestoreWorkStackAssetSetScope() throws {
        let directory = try makeTemporaryDirectory(named: "restore-no-work-stack")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)
        let workStackSetID = AssetSetID(rawValue: "work-stack-in-progress")
        try catalogA.repository.upsert(AssetSet.manual(
            id: workStackSetID,
            name: "In-progress cull stack",
            assetIDs: [AssetID(rawValue: "asset-0")]
        ))
        let catalogRoot = try makePaths(directory: directory).root
        SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).save(
            Self.stateReferencing(selectedAssetSetID: workStackSetID)
        )

        let modelB = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)

        XCTAssertNil(modelB.selectedAssetSetID)
    }

    func testDoesNotCrossRestoreBetweenDifferentCatalogPaths() throws {
        let directoryA = try makeTemporaryDirectory(named: "restore-catalog-a")
        let directoryB = try makeTemporaryDirectory(named: "restore-catalog-b")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directoryA)
        try seedAssets(count: 3, in: catalogA.repository)
        let catalogB = try makeCatalog(directory: directoryB)
        try seedAssets(count: 3, in: catalogB.repository)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.allPhotos)
        modelA.librarySearchText = "only in A"
        try modelA.applyLibraryFilters()

        let modelC = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelC.selectedView, .grid)
        XCTAssertEqual(modelC.librarySearchText, "")
    }

    // SP-D0: ghost badges survive relaunch natively — the unconfirmed AI flag
    // lives in metadata_json, so nothing has to be reconstructed for them.
    func testGhostsSurviveRelaunch() throws {
        let directory = try makeTemporaryDirectory(named: "restore-ghosts")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        var ghostAsset = makeAsset(id: "ghost-1", filename: "ghost-1.dng")
        ghostAsset.metadata.flag = .pick
        ghostAsset.metadata.aiUnconfirmedFields = [.flag]
        let plainAsset = makeAsset(id: "plain-1", filename: "plain-1.dng")
        try catalogA.repository.upsert([ghostAsset, plainAsset])
        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        XCTAssertEqual(modelA.autopilotGhostAssetIDs, [ghostAsset.id])

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.autopilotGhostAssetIDs, [ghostAsset.id])
        XCTAssertEqual(
            AutopilotGhost.kind(in: try catalogB.repository.asset(id: ghostAsset.id).metadata),
            .pick
        )

        // The banner is run-time only: `load(...)` restores ghosts from
        // metadata_json and nothing else, so a relaunched model has no run
        // summary to render a banner from.
        XCTAssertNil(modelB.autopilotRunSummary)
    }

    func testSessionRestoreDisabledByDefaultDoesNotPersistOrRestore() throws {
        let directory = try makeTemporaryDirectory(named: "restore-disabled-by-default")
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)

        let modelA = try AppModel.load(catalog: catalogA)
        try modelA.selectSource(.allPhotos)
        modelA.librarySearchText = "should not survive"
        try modelA.applyLibraryFilters()

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB)

        XCTAssertEqual(modelB.selectedView, .grid)
        XCTAssertEqual(modelB.librarySearchText, "")
    }

    // Relaunch restores the selected source and the browse lens it was seen
    // through.
    func testRestoresTheSourceAndTheBrowseLens() throws {
        let directory = try makeTemporaryDirectory(named: "restore-source-lens")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 4, in: catalogA.repository, ratingForIndex: { $0 < 2 ? 5 : 1 })

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.smartCollection(.fiveStars))
        modelA.selectLens(.timeline)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedLens, .timeline)
        XCTAssertEqual(modelB.selectedSource, LibrarySource.smartCollection(.fiveStars))
        XCTAssertEqual(modelB.assets.count, 2)
    }

    // Quitting mid-cull relaunches on the same source in Grid — actual run
    // resume is the SP-D lifecycle spec's job.
    func testAMidCullQuitRelaunchesOnTheSameSourceInGrid() throws {
        let directory = try makeTemporaryDirectory(named: "restore-mid-cull")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.folder("/Photos"))
        modelA.selectLens(.cull)
        XCTAssertEqual(modelA.selectedLens, .cull)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedLens, .grid)
        XCTAssertEqual(modelB.selectedSource, LibrarySource.folder("/Photos"))
    }

    // Behaviour change 8: restore returns source + browse lens, and only
    // .cull falls back to Grid. Table-driven over every case so a lens added
    // later can't silently go unchecked the way Cull/Timeline-only coverage
    // would have.
    func testEveryLensRestoresItselfExceptCullWhichFallsBackToGrid() throws {
        for lens in LibraryLens.allCases {
            let directory = try makeTemporaryDirectory(named: "restore-every-lens-\(lens.rawValue)")
            let defaults = try makeIsolatedDefaults()
            let catalogA = try makeCatalog(directory: directory)
            try seedAssets(count: 3, in: catalogA.repository)

            let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
            try modelA.selectSource(.folder("/Photos"))
            modelA.selectLens(lens)
            XCTAssertEqual(modelA.selectedLens, lens, "sanity: selecting \(lens) should select \(lens)")

            let catalogB = try makeCatalog(directory: directory)
            let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

            let expectedLens: LibraryLens = lens == .cull ? .grid : lens
            XCTAssertEqual(modelB.selectedLens, expectedLens, "relaunching from \(lens) should restore to \(expectedLens)")
            XCTAssertEqual(modelB.selectedSource, LibrarySource.folder("/Photos"), "relaunching from \(lens) should keep the source")
        }
    }

    func testAFreshCatalogColdStartsOnAllPhotosInGrid() throws {
        let directory = try makeTemporaryDirectory(named: "restore-cold-start")
        let defaults = try makeIsolatedDefaults()
        let catalog = try makeCatalog(directory: directory)
        try seedAssets(count: 2, in: catalog.repository)

        let model = try AppModel.load(catalog: catalog, sessionRestoreDefaults: defaults)

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(model.selectedSource, LibrarySource.allPhotos)
    }

    // MARK: - Helpers

    private static func stateReferencing(
        lens: LibraryLens = .grid,
        source: LibrarySource = .allPhotos,
        selectedAssetSetID: AssetSetID? = nil,
        assetID: AssetID? = nil
    ) -> SessionRestoreState {
        SessionRestoreState(
            lens: lens,
            source: source,
            selectedAssetSetID: selectedAssetSetID,
            selectedAssetID: assetID,
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
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-session-restore-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePaths(directory: URL) throws -> AppCatalogPaths {
        AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
    }

    private func makeCatalog(directory: URL) throws -> AppCatalog {
        try AppCatalog.open(paths: try makePaths(directory: directory))
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "teststrip.session-restore-app.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "AppModelSessionRestoreTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func seedAssets(
        count: Int,
        in repository: CatalogRepository,
        ratingForIndex: (Int) -> Int = { _ in 0 }
    ) throws {
        let assets = (0..<count).map { index in
            makeAsset(id: "asset-\(index)", filename: "frame-\(index).dng", rating: ratingForIndex(index))
        }
        try repository.upsert(assets)
    }

    private func makeAsset(id: String, filename: String, rating: Int = 0, flag: PickFlag? = nil) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(filename)"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(rating: rating, flag: flag)
        )
    }
}
