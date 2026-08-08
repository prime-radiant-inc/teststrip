import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Spec behaviour change 11: the Map lens showed the whole catalog whenever the
// source was a saved static set or the Selection, because those scopes lived
// only in `selectedExplicitAssetIDs` and never became a `SetQuery`.
final class MapSourceScopingTests: XCTestCase {
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
