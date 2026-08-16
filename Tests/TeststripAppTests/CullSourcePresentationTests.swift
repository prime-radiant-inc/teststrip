import XCTest
@testable import TeststripCore
@testable import TeststripApp

// "Which sources exist and when" now lives entirely in
// UnifiedSidebarPresentationTests — CullSource/CullSourceGroup/
// CullSourcePresentation are gone. This file keeps only "Cull These": the
// batch-selection shortcut that scopes a fresh culling session to whatever
// is selected and switches to the Cull lens.
final class CullSelectionSourceTests: XCTestCase {
    func testCullCurrentSelectionScopesToSelectedBatchAndSwitchesToCull() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/Cull/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/Cull/reject.jpg", rating: 1)
        let bystander = makeAsset(id: "bystander", path: "/Photos/Cull/bystander.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "cull-current-selection",
            assets: [keeper, reject, bystander]
        )

        model.setBatchSelection(keeper.id, isSelected: true)
        model.setBatchSelection(reject.id, isSelected: true)

        _ = try model.cullCurrentSelection()

        XCTAssertEqual(model.selectedLens, .cull)
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([keeper.id, reject.id]))
    }

    func testCullCurrentSelectionFallsBackToSingleSelectedAsset() throws {
        let onlyAsset = makeAsset(id: "solo", path: "/Photos/Cull/solo.jpg", rating: 4)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "cull-current-selection-single",
            assets: [onlyAsset]
        )
        model.select(onlyAsset.id)

        _ = try model.cullCurrentSelection()

        XCTAssertEqual(model.selectedLens, .cull)
        XCTAssertEqual(model.assets.map(\.id), [onlyAsset.id])
    }

    func testCullCurrentSelectionThrowsWhenNothingSelected() throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-current-selection-empty", assets: [])

        XCTAssertThrowsError(try model.cullCurrentSelection())
    }

    // MARK: - Fixtures

    private func makeAsset(
        id: String,
        path: String,
        rating: Int
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: .online,
            metadata: AssetMetadata(rating: rating, colorLabel: nil, flag: nil, keywords: [])
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
