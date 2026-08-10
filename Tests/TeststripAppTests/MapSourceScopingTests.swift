import XCTest
@testable import TeststripCore
@testable import TeststripApp

// The Map reads three aggregate queries separately from the grid. Every source
// scope must reach both surfaces, including static sets and AI Suggestions'
// derived IDs, without an empty explicit scope falling back to All Photos.
final class MapSourceScopingTests: XCTestCase {
    func testSelectingAISuggestionsWhileMapIsActiveRefreshesGhostOnlyMapAggregates() throws {
        let fixture = try makeAISuggestionsMapFixture(named: "map-ai-active")
        fixture.model.selectLens(.map)
        try fixture.model.refreshPlaceData()
        XCTAssertEqual(
            fixture.model.geotaggedCoverage,
            CatalogGeotaggedCoverage(geotaggedCount: 3, totalCount: 3),
            "fixture check: All Photos begins with every geotagged control"
        )

        try fixture.model.selectSource(.autopilotSuggestions)

        XCTAssertEqual(fixture.model.selectedLens, .map)
        XCTAssertEqual(fixture.model.assets.map(\.id), [fixture.ghost.id])
        assertMapScope(
            fixture.model,
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 1, totalCount: 1),
            clusters: [CatalogPlaceCluster(latitude: 11.25, longitude: 21.25, assetCount: 1)],
            topLocations: [CatalogTopLocation(displayName: "Ghost Place", assetCount: 1, latitude: 11.25, longitude: 21.25)]
        )
    }

    func testEnteringMapFromAISuggestionsScopesEveryMapAggregateToGhosts() throws {
        let fixture = try makeAISuggestionsMapFixture(named: "map-ai-entry")
        try fixture.model.selectSource(.autopilotSuggestions)
        XCTAssertEqual(fixture.model.assets.map(\.id), [fixture.ghost.id])

        fixture.model.selectLens(.map)
        try fixture.model.refreshPlaceData()

        XCTAssertEqual(fixture.model.selectedLens, .map)
        assertMapScope(
            fixture.model,
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 1, totalCount: 1),
            clusters: [CatalogPlaceCluster(latitude: 11.25, longitude: 21.25, assetCount: 1)],
            topLocations: [CatalogTopLocation(displayName: "Ghost Place", assetCount: 1, latitude: 11.25, longitude: 21.25)]
        )
    }

    func testReloadingEmptyAISuggestionsClearsEveryMapAggregate() throws {
        let fixture = try makeAISuggestionsMapFixture(named: "map-ai-empty")
        try fixture.model.selectSource(.autopilotSuggestions)
        fixture.model.selectLens(.map)
        try fixture.repository.updateMetadata(assetID: fixture.ghost.id) { metadata in
            metadata.flag = nil
            metadata.aiUnconfirmedFields.remove(.flag)
        }

        try fixture.model.applyLibraryFilters()

        XCTAssertEqual(fixture.model.autopilotGhostAssetIDs, [])
        XCTAssertEqual(fixture.model.assets.map(\.id), [])
        assertMapScope(
            fixture.model,
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 0, totalCount: 0),
            clusters: [],
            topLocations: []
        )
    }

    func testSortingAISuggestionsRederivesMapScopeFromCurrentGhosts() throws {
        let oldGhost = makeGeotaggedGhostAsset(
            id: "map-sort-old",
            path: "/Photos/zulu-old.dng",
            latitude: 12.25,
            longitude: 22.25,
            flag: .pick
        )
        let newGhost = makeGeotaggedAsset(
            id: "map-sort-new",
            path: "/Photos/alpha-new.dng",
            latitude: 32.25,
            longitude: 42.25
        )
        let confirmedControl = makeGeotaggedConfirmedAsset(
            id: "map-sort-confirmed",
            path: "/Photos/middle-confirmed.dng",
            latitude: 52.25,
            longitude: 62.25,
            flag: .pick
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "map-ai-sort-membership",
            assets: [oldGhost, newGhost, confirmedControl]
        )
        try recordPlaceNames(
            [
                (oldGhost, "Old Ghost Place"),
                (newGhost, "New Ghost Place"),
                (confirmedControl, "Confirmed Place")
            ],
            repository: repository
        )
        try model.selectSource(.autopilotSuggestions)
        model.selectLens(.map)
        try model.refreshPlaceData()
        try repository.updateMetadata(assetID: oldGhost.id) { metadata in
            metadata.flag = nil
            metadata.aiUnconfirmedFields.remove(.flag)
        }
        try repository.updateMetadata(assetID: newGhost.id) { metadata in
            metadata.flag = .pick
            metadata.aiUnconfirmedFields.insert(.flag)
        }

        try model.setLibrarySortOption(.filename)

        XCTAssertEqual(model.selectedLens, .map)
        XCTAssertEqual(model.autopilotGhostAssetIDs, [newGhost.id])
        XCTAssertEqual(model.assets.map(\.id), [newGhost.id])
        assertMapScope(
            model,
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 1, totalCount: 1),
            clusters: [CatalogPlaceCluster(latitude: 32.25, longitude: 42.25, assetCount: 1)],
            topLocations: [CatalogTopLocation(displayName: "New Ghost Place", assetCount: 1, latitude: 32.25, longitude: 42.25)]
        )
    }

    func testMapScopesToASelectedStaticSet() throws {
        let inSet = makeGeotaggedAsset(id: "map-in", path: "/Photos/in.jpg", latitude: 10, longitude: 20)
        let outOfSet = makeGeotaggedAsset(id: "map-out", path: "/Photos/out.jpg", latitude: 40, longitude: 50)
        let (model, repository) = try makeModelWithCatalogAssets(named: "map-static-set", assets: [inSet, outOfSet])
        let setID = AssetSetID(rawValue: "map-keepers")
        try repository.upsert(AssetSet.manual(id: setID, name: "Keepers", assetIDs: [inSet.id]))
        try model.refreshSavedAssetSets()

        try model.applyAssetSet(id: setID)
        try model.refreshPlaceData()

        XCTAssertEqual(model.geotaggedCoverage.totalCount, 1)
        XCTAssertEqual(model.catalogPlaceClusters.map(\.assetCount).reduce(0, +), 1)
    }

    func testMapCoversTheWholeCatalogOnAllPhotos() throws {
        let first = makeGeotaggedAsset(id: "map-all-a", path: "/Photos/a.jpg", latitude: 10, longitude: 20)
        let second = makeGeotaggedAsset(id: "map-all-b", path: "/Photos/b.jpg", latitude: 40, longitude: 50)
        let (model, _) = try makeModelWithCatalogAssets(named: "map-all-photos", assets: [first, second])

        try model.refreshPlaceData()

        XCTAssertEqual(model.geotaggedCoverage.totalCount, 2)
        XCTAssertEqual(model.catalogPlaceClusters.map(\.assetCount).reduce(0, +), 2)
    }

    // The fixture needs a picked asset *outside* the set too: with only the
    // in-set pair, the flag filter alone (ignoring the set entirely) already
    // narrows to the same count the correctly-scoped answer would produce,
    // so that weaker fixture can't tell "scoped" apart from "unscoped."
    func testTheMapQueryComposesASetScopeWithAnActiveFilter() throws {
        let picked = makeGeotaggedAsset(id: "map-picked", path: "/Photos/picked.jpg", latitude: 10, longitude: 20)
        let unpicked = makeGeotaggedAsset(id: "map-unpicked", path: "/Photos/unpicked.jpg", latitude: 11, longitude: 21)
        let outsidePicked = makeGeotaggedAsset(id: "map-outside-picked", path: "/Photos/outside-picked.jpg", latitude: 12, longitude: 22)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "map-compose",
            assets: [picked, unpicked, outsidePicked]
        )
        try repository.updateMetadata(assetID: picked.id) { metadata in
            metadata.flag = .pick
        }
        try repository.updateMetadata(assetID: outsidePicked.id) { metadata in
            metadata.flag = .pick
        }
        let setID = AssetSetID(rawValue: "map-both")
        try repository.upsert(AssetSet.manual(id: setID, name: "Both", assetIDs: [picked.id, unpicked.id]))
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: setID)

        model.flagFilter = .pick
        try model.applyLibraryFilters()
        try model.refreshPlaceData()

        XCTAssertEqual(model.geotaggedCoverage.totalCount, 1)
    }

    // MARK: - Fixtures

    private struct AISuggestionsMapFixture {
        var model: AppModel
        var repository: CatalogRepository
        var ghost: Asset
    }

    private func makeAISuggestionsMapFixture(named name: String) throws -> AISuggestionsMapFixture {
        let ghost = makeGeotaggedGhostAsset(
            id: "ai-map-ghost",
            path: "/Photos/ghost.dng",
            latitude: 11.25,
            longitude: 21.25,
            flag: .pick
        )
        let ordinary = makeGeotaggedAsset(
            id: "ai-map-ordinary",
            path: "/Photos/ordinary.dng",
            latitude: 31.25,
            longitude: 41.25
        )
        let confirmed = makeGeotaggedConfirmedAsset(
            id: "ai-map-confirmed",
            path: "/Photos/confirmed.dng",
            latitude: 51.25,
            longitude: 61.25,
            flag: .pick
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [ghost, ordinary, confirmed]
        )
        try recordPlaceNames(
            [
                (ghost, "Ghost Place"),
                (ordinary, "Ordinary Place"),
                (confirmed, "Confirmed Place")
            ],
            repository: repository
        )
        return AISuggestionsMapFixture(model: model, repository: repository, ghost: ghost)
    }

    private func assertMapScope(
        _ model: AppModel,
        coverage: CatalogGeotaggedCoverage,
        clusters: [CatalogPlaceCluster],
        topLocations: [CatalogTopLocation],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(model.geotaggedCoverage, coverage, file: file, line: line)
        XCTAssertEqual(model.catalogPlaceClusters, clusters, file: file, line: line)
        XCTAssertEqual(model.catalogTopLocations, topLocations, file: file, line: line)
    }

    private func recordPlaceNames(
        _ namedAssets: [(Asset, String)],
        repository: CatalogRepository
    ) throws {
        for (asset, displayName) in namedAssets {
            let technicalMetadata = try XCTUnwrap(asset.technicalMetadata)
            let latitude = try XCTUnwrap(technicalMetadata.latitude)
            let longitude = try XCTUnwrap(technicalMetadata.longitude)
            try repository.recordPlaceName(CatalogPlaceName(
                coordinateKey: GeocodeCoordinateKey.key(latitude: latitude, longitude: longitude),
                displayName: displayName
            ))
        }
    }

    private func makeGeotaggedGhostAsset(
        id: String,
        path: String,
        latitude: Double,
        longitude: Double,
        flag: PickFlag
    ) -> Asset {
        var asset = makeGeotaggedAsset(id: id, path: path, latitude: latitude, longitude: longitude)
        asset.metadata.flag = flag
        asset.metadata.aiUnconfirmedFields = [.flag]
        return asset
    }

    private func makeGeotaggedConfirmedAsset(
        id: String,
        path: String,
        latitude: Double,
        longitude: Double,
        flag: PickFlag
    ) -> Asset {
        var asset = makeGeotaggedAsset(id: id, path: path, latitude: latitude, longitude: longitude)
        asset.metadata.flag = flag
        return asset
    }

    private func makeGeotaggedAsset(id: String, path: String, latitude: Double, longitude: Double) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 100,
                pixelHeight: 100,
                latitude: latitude,
                longitude: longitude,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-map-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
}
