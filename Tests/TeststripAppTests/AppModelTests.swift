import XCTest
import TeststripCore
import TeststripApp

final class AppModelTests: XCTestCase {
    func testAppModelStartsWithStudioLayoutSections() {
        let model = AppModel.demo()

        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Library"))
        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Work"))
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.selectedAsset?.id, model.assets.first?.id)
    }

    func testSidebarSectionCanBeConstructedByPublicClients() {
        let section = SidebarSection(title: "Library", rows: ["All Photographs"])

        XCTAssertEqual(section.title, "Library")
        XCTAssertEqual(section.rows, ["All Photographs"])
    }

    func testSelectingAssetUpdatesInspector() {
        let first = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: URL(fileURLWithPath: "/Photos/first.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "second"),
            originalURL: URL(fileURLWithPath: "/Photos/second.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 2, modificationDate: Date(timeIntervalSince1970: 2)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        XCTAssertEqual(model.selectedAsset?.id, first.id)

        model.select(second.id)

        XCTAssertEqual(model.selectedAsset?.id, second.id)
    }

    func testSelectNextAssetMovesSelectionForwardThroughLoadedAssets() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        model.selectNextAsset()
        XCTAssertEqual(model.selectedAsset?.id, second.id)

        model.selectNextAsset()
        XCTAssertEqual(model.selectedAsset?.id, second.id)
    }

    func testSelectPreviousAssetMovesSelectionBackwardThroughLoadedAssets() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])
        model.select(second.id)

        model.selectPreviousAsset()
        XCTAssertEqual(model.selectedAsset?.id, first.id)

        model.selectPreviousAsset()
        XCTAssertEqual(model.selectedAsset?.id, first.id)
    }

    func testLibraryCountTextShowsLoadedAndTotalWhenGridIsLimited() {
        let asset = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: URL(fileURLWithPath: "/Photos/first.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [asset], totalAssetCount: 3)

        XCTAssertEqual(model.libraryCountText, "Showing 1 of 3 photographs")
    }

    func testRatingSelectedAssetUpdatesCatalogAndLoadedAsset() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-rating")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "rating-target"),
            originalURL: URL(fileURLWithPath: "/Photos/rating.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setRatingForSelectedAsset(4)

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 4)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 4)
    }

    func testFlagSelectedAssetUpdatesCatalogAndLoadedAsset() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-flag")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "flag-target"),
            originalURL: URL(fileURLWithPath: "/Photos/flag.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setFlagForSelectedAsset(.reject)

        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .reject)
    }

    func testRatingCullingCommandUpdatesSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "rating-command")

        try model.applyCullingCommand(.rating(5))

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
    }

    func testFlagCullingCommandUpdatesSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "flag-command")

        try model.applyCullingCommand(.pick)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .pick)

        try model.applyCullingCommand(.clearFlag)
        XCTAssertNil(model.selectedAsset?.metadata.flag)

        try model.applyCullingCommand(.reject)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .reject)
    }

    func testCullingShortcutMovesSelectionThroughLoadedAssets() throws {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        try model.applyCullingShortcut(.nextPhoto)
        XCTAssertEqual(model.selectedAsset?.id, second.id)

        try model.applyCullingShortcut(.previousPhoto)
        XCTAssertEqual(model.selectedAsset?.id, first.id)
    }

    func testCullingShortcutAppliesMetadataToSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "shortcut-metadata")

        try model.applyCullingShortcut(.rating(5))
        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)

        try model.applyCullingShortcut(.reject)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .reject)
    }

    func testCullingShortcutInterpretsKeyboardKeys() {
        XCTAssertEqual(CullingShortcut(key: .rightArrow), .nextPhoto)
        XCTAssertEqual(CullingShortcut(key: .leftArrow), .previousPhoto)
        XCTAssertEqual(CullingShortcut(key: .character("5")), .rating(5))
        XCTAssertEqual(CullingShortcut(key: .character("P")), .pick)
        XCTAssertEqual(CullingShortcut(key: .character("x")), .reject)
        XCTAssertEqual(CullingShortcut(key: .character("u")), .clearFlag)
        XCTAssertNil(CullingShortcut(key: .character("a")))
    }

    func testUndoMetadataChangeRestoresLoadedAssetAndCatalog() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "undo-rating")

        try model.setRatingForSelectedAsset(4)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertFalse(model.canRedoMetadataChange)

        try model.undoMetadataChange()

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 0)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 0)
        XCTAssertFalse(model.canUndoMetadataChange)
        XCTAssertTrue(model.canRedoMetadataChange)
    }

    func testRedoMetadataChangeReappliesLoadedAssetAndCatalog() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "redo-flag")

        try model.setFlagForSelectedAsset(.pick)
        try model.undoMetadataChange()
        try model.redoMetadataChange()

        XCTAssertEqual(model.selectedAsset?.metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .pick)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertFalse(model.canRedoMetadataChange)
    }

    func testLoadsAssetsFromCatalogRepository() throws {
        let directory = try makeTemporaryDirectory(named: "app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "catalog-asset"),
            originalURL: URL(fileURLWithPath: "/Photos/catalog.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 5)
        )
        try repository.upsert(asset)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.selectedAsset?.id, asset.id)
    }

    func testLoadKeepsTotalAssetCountWhenGridIsLimited() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-count")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        for index in 0..<501 {
            try repository.upsert(Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets.count, 500)
        XCTAssertEqual(model.totalAssetCount, 501)
    }

    func testLoadMoreAssetsAppendsNextCatalogPage() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-load-more")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        for index in 0..<501 {
            try repository.upsert(Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.assets.count, 500)
        XCTAssertTrue(model.hasMoreAssets)

        try model.loadMoreAssets()

        XCTAssertEqual(model.assets.count, 501)
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-500"))
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertFalse(model.hasMoreAssets)
    }

    func testLoadingEmptyRepositoryLeavesSelectionEmpty() throws {
        let directory = try makeTemporaryDirectory(named: "empty-app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertNil(model.selectedAsset)
    }

    func testImportFolderReloadsAssetsAndExposesGridPreviewURL() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try model.importFolder(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        XCTAssertEqual(model.totalAssetCount, 1)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: result.importedAssets[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBackgroundImportReloadsAssetsAndExposesGridPreviewURL() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importFolderInBackground(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        XCTAssertEqual(model.totalAssetCount, 1)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: result.importedAssets[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBackgroundImportRecordsCompletedActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-activity")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importFolderInBackground(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertNil(model.activeWork)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.title, "Import photos")
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(activity.completedUnitCount, 1)
        XCTAssertEqual(activity.failureCount, 0)
    }

    @MainActor
    func testCancellingActiveImportRecordsCancelledActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-cancel-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)
        XCTAssertEqual(model.activeWork?.status, .running)

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)

        XCTAssertNil(model.activeWork)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .cancelled)
        XCTAssertEqual(activity.detail, "Cancelled import from photos")
        XCTAssertEqual(model.statusMessage, "Cancelled import")
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeTestPNG(to url: URL) throws {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
    }

    private func makeAsset(id: String, size: Int64) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: size, modificationDate: Date(timeIntervalSince1970: TimeInterval(size))),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func makeModelWithCatalogAsset(named name: String) throws -> (AppModel, CatalogRepository, Asset) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: name),
            originalURL: URL(fileURLWithPath: "/Photos/\(name).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        return (try AppModel.load(catalog: catalog), repository, asset)
    }

    @MainActor
    private func waitForActivityStatus(_ status: WorkSessionStatus, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.recentWork.first?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for activity status \(status.rawValue)")
    }
}
