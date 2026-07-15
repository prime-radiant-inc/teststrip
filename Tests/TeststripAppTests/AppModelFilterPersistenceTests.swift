import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Locks the invariant from docs/superpowers/specs/2026-07-14-global-filter-persistence-design.md:
// the active library filter scope persists across every view and mode switch,
// and the whole-scope "Cull" entry culls within the filtered scope instead of
// clobbering it.
final class AppModelFilterPersistenceTests: XCTestCase {
    // MARK: - Task 1: bare view/mode switches never clear filters (regression guards)

    func testModeSwitchLibraryToCullToLibraryPreservesFilters() throws {
        let five = makeAsset(id: "five", path: "/Photos/five.jpg", rating: 5)
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let two = makeAsset(id: "two", path: "/Photos/two.jpg", rating: 2)
        let one = makeAsset(id: "one", path: "/Photos/one.jpg", rating: 1)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "filter-persistence-mode-switch",
            assets: [five, four, two, one]
        )
        model.librarySearchText = "Photos"
        model.minimumRatingFilter = 4
        try model.setLibrarySortOption(.ratingHighestFirst)
        try model.applyLibraryFilters()

        let expectedAssetIDs = model.assets.map(\.id)
        XCTAssertEqual(Set(expectedAssetIDs), Set([five.id, four.id]))

        func assertFiltersUnchanged(line: UInt = #line) {
            XCTAssertEqual(model.librarySearchText, "Photos", line: line)
            XCTAssertEqual(model.minimumRatingFilter, 4, line: line)
            XCTAssertEqual(model.librarySortOption, .ratingHighestFirst, line: line)
            XCTAssertNil(model.selectedAssetSetID, line: line)
            XCTAssertEqual(model.assets.map(\.id), expectedAssetIDs, line: line)
        }

        model.selectWorkspace(.cull)
        assertFiltersUnchanged()

        model.selectWorkspace(.library)
        assertFiltersUnchanged()
    }

    func testEnteringCullNavigatesWithinFilteredSet() throws {
        let five = makeAsset(id: "five", path: "/Photos/five.jpg", rating: 5)
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let two = makeAsset(id: "two", path: "/Photos/two.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "filter-persistence-cull-navigates-filtered",
            assets: [five, four, two]
        )
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        model.selectWorkspace(.cull)

        XCTAssertFalse(model.assets.isEmpty)
        XCTAssertTrue(model.assets.allSatisfy { $0.metadata.rating >= 4 })
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([five.id, four.id]))
    }

    func testLibraryViewToggleAcrossViewsPreservesFilters() throws {
        let five = makeAsset(id: "five", path: "/Photos/five.jpg", rating: 5)
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let two = makeAsset(id: "two", path: "/Photos/two.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "filter-persistence-view-toggle",
            assets: [five, four, two]
        )
        model.librarySearchText = "Photos"
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        let expectedAssetIDs = Set(model.assets.map(\.id))

        for view in [LibraryViewMode.timeline, .map, .libraryLoupe, .grid] {
            model.selectedView = view
            XCTAssertEqual(model.librarySearchText, "Photos")
            XCTAssertEqual(model.minimumRatingFilter, 4)
            XCTAssertNil(model.selectedAssetSetID)
            XCTAssertEqual(Set(model.assets.map(\.id)), expectedAssetIDs)
        }
    }

    func testViewSwitchToPeoplePreservesFilters() throws {
        let five = makeAsset(id: "five", path: "/Photos/five.jpg", rating: 5)
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let two = makeAsset(id: "two", path: "/Photos/two.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "filter-persistence-mode-switch-people",
            assets: [five, four, two]
        )
        model.librarySearchText = "Photos"
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        let expectedAssetIDs = model.assets.map(\.id)

        model.selectedView = .people
        XCTAssertEqual(model.librarySearchText, "Photos")
        XCTAssertEqual(model.minimumRatingFilter, 4)
        XCTAssertNil(model.selectedAssetSetID)

        model.selectedView = .grid
        XCTAssertEqual(model.librarySearchText, "Photos")
        XCTAssertEqual(model.minimumRatingFilter, 4)
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.assets.map(\.id), expectedAssetIDs)
    }

    // MARK: - Task 2: whole-scope Cull preserves the filter scope

    func testCullingWholeFilterScopePreservesFiltersAndKeepsSetNil() throws {
        let five = makeAsset(id: "five", path: "/Photos/five.jpg", rating: 5)
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let two = makeAsset(id: "two", path: "/Photos/two.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "filter-scope-cull-preserves-filters",
            assets: [five, four, two]
        )
        model.librarySearchText = "Photos"
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()
        XCTAssertNil(model.selectedAssetSetID)

        let expectedAssetIDs = model.assets.map(\.id)
        XCTAssertEqual(Set(expectedAssetIDs), Set([five.id, four.id]))

        let session = try model.beginCullingSession(named: "Scope Cull")

        XCTAssertEqual(model.librarySearchText, "Photos")
        XCTAssertEqual(model.minimumRatingFilter, 4)
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.assets.map(\.id), expectedAssetIDs)

        let inputSetID = try XCTUnwrap(session.inputSetIDs.first)
        XCTAssertTrue(inputSetID.rawValue.hasPrefix("work-input-"))
        XCTAssertEqual(model.recentWork.first?.id, session.id.rawValue)
    }

    func testCullingWholeFilterScopeTracksProgressToCompletion() throws {
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let alsoFour = makeAsset(id: "also-four", path: "/Photos/also-four.jpg", rating: 4)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "filter-scope-cull-tracks-progress",
            assets: [four, alsoFour]
        )
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([four.id, alsoFour.id]))

        let startedSession = try model.beginCullingSession(named: "Scope Cull")
        XCTAssertNil(model.selectedAssetSetID)

        model.select(four.id)
        try model.applyCullingCommand(.pick)
        model.select(alsoFour.id)
        try model.applyCullingCommand(.reject)

        let session = try repository.session(id: startedSession.id)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.completedUnitCount, 2)

        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        let outputSet = try repository.assetSet(id: outputSetID)
        XCTAssertEqual(outputSet.membership, .snapshot([four.id]))
    }

    func testReturningToLibraryAfterFilterScopeCullShowsLiveFilteredGrid() throws {
        let five = makeAsset(id: "five", path: "/Photos/five.jpg", rating: 5)
        let four = makeAsset(id: "four", path: "/Photos/four.jpg", rating: 4)
        let two = makeAsset(id: "two", path: "/Photos/two.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "filter-scope-cull-return-to-library",
            assets: [five, four, two]
        )
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        _ = try model.beginCullingSession(named: "Scope Cull")

        model.selectWorkspace(.library)

        XCTAssertEqual(model.minimumRatingFilter, 4)
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([five.id, four.id]))
    }

    // A "Cull From" review-queue source is a filter-field scope (applyReviewQueue
    // sets flagFilter, not a snapshot set), so culling from it keeps that filter
    // live and it persists back to Library — the same single-scope behavior the
    // queue has when reached from the Library sidebar. Locks the emergent
    // behavior documented in the spec's "Cull From sources" section.
    func testCullingFromReviewQueueSourcePersistsQueueFilter() throws {
        let pick = makeAsset(id: "pick", path: "/Photos/pick.jpg", rating: 5, flag: .pick)
        let unflagged = makeAsset(id: "unflagged", path: "/Photos/unflagged.jpg", rating: 3)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "cull-source-review-queue-persists-filter",
            assets: [pick, unflagged]
        )

        try model.activateCullSource(.reviewQueue(.picks))

        // Preserve branch was taken (else branch would clear flagFilter and
        // switch selectedAssetSetID to the hidden work-input snapshot).
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])

        model.selectWorkspace(.library)

        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
    }

    // MARK: - Test helpers

    private func makeAsset(
        id: String,
        path: String,
        rating: Int,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = []
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: .online,
            metadata: AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords)
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
