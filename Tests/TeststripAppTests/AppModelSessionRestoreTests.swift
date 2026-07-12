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
        try modelA.selectSidebarTarget(.search)
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
            Self.stateReferencing(selectedView: .loupe)
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
        try modelA.selectSidebarTarget(.search)
        modelA.librarySearchText = "only in A"
        try modelA.applyLibraryFilters()

        let modelC = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelC.selectedView, .grid)
        XCTAssertEqual(modelC.librarySearchText, "")
    }

    func testSessionRestoreDisabledByDefaultDoesNotPersistOrRestore() throws {
        let directory = try makeTemporaryDirectory(named: "restore-disabled-by-default")
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)

        let modelA = try AppModel.load(catalog: catalogA)
        try modelA.selectSidebarTarget(.search)
        modelA.librarySearchText = "should not survive"
        try modelA.applyLibraryFilters()

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB)

        XCTAssertEqual(modelB.selectedView, .grid)
        XCTAssertEqual(modelB.librarySearchText, "")
    }

    // MARK: - Helpers

    private static func stateReferencing(
        selectedView: LibraryViewMode = .grid,
        selectedAssetSetID: AssetSetID? = nil,
        assetID: AssetID? = nil
    ) -> SessionRestoreState {
        SessionRestoreState(
            selectedView: selectedView,
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
            metadataSyncConflictFilter: false
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

    private func makeAsset(id: String, filename: String, rating: Int = 0) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(filename)"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
        )
    }
}
