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
        XCTAssertEqual(section.rowTitles, ["All Photographs"])
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

    func testOpenAssetInLoupeSelectsAssetAndSwitchesView() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        model.openAssetInLoupe(second.id)

        XCTAssertEqual(model.selectedAsset?.id, second.id)
        XCTAssertEqual(model.selectedView, .loupe)
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

    func testCompareAssetsReturnWindowAroundSelection() {
        let assets = (0..<6).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .compare, assets: assets)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[0..<4].map(\.id))

        model.select(assets[3].id)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[2..<6].map(\.id))
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

    func testRatingSelectedAssetWritesXmpSidecarWhenOriginalIsAvailable() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "xmp-write-target"),
            originalURL: originalURL,
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

        try model.setRatingForSelectedAsset(5)

        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.rating, 5)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
    }

    func testRatingSelectedAssetQueuesXmpWhenSidecarCannotBeWritten() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "xmp-pending")

        try model.setRatingForSelectedAsset(5)

        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [pending])
    }

    func testLoadExposesMetadataSyncConflicts() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-conflict")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "conflict-target"),
            originalURL: URL(fileURLWithPath: "/Photos/conflict.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        )
        try repository.recordMetadataSyncConflict(conflict)

        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        XCTAssertEqual(model.metadataSyncConflictItems, [conflict])
    }

    func testRatingSelectedAssetDispatchesWorkerMetadataSyncWhenSupervisorConfigured() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-xmp")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "worker-xmp-target"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(
            catalog: AppCatalog(
                paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
                repository: repository,
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
                importService: LibraryImportService(
                    ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                    previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
                )
            ),
            workerSupervisor: supervisor
        )

        try model.setRatingForSelectedAsset(5)

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appendingPathExtension("xmp").path))
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Writing XMP sidecar")
    }

    func testLoadQueuesPendingMetadataSyncWhenSupervisorConfigured() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "pending-worker-xmp-target"),
            originalURL: URL(fileURLWithPath: "/Volumes/NAS/frame.cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: nil
        )
        try repository.recordMetadataSyncPending(pending)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let model = try AppModel.load(
            catalog: AppCatalog(
                paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
                repository: repository,
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
                importService: LibraryImportService(
                    ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                    previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
                )
            ),
            workerSupervisor: supervisor
        )

        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Writing XMP sidecar")
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

    func testCullingShortcutAdvancesAfterRatingSelectedAsset() throws {
        let directory = try makeTemporaryDirectory(named: "culling-shortcut-advance")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 2, repository: repository)
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
        let firstID = AssetID(rawValue: "asset-0")
        let secondID = AssetID(rawValue: "asset-1")

        try model.applyCullingShortcut(.rating(5))

        XCTAssertEqual(try repository.asset(id: firstID).metadata.rating, 5)
        XCTAssertEqual(model.selectedAssetID, secondID)
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

    func testBackgroundWorkQueueIsVisibleAndBounded() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")

        model.enqueueBackgroundWork(first)
        model.enqueueBackgroundWork(second)

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id), [first.id])
        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.id), [second.id])
        XCTAssertEqual(model.visibleWorkActivity?.id, first.id.rawValue)
        XCTAssertEqual(model.visibleWorkActivity?.title, "Generate previews")
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
        XCTAssertTrue(model.canPauseBackgroundWork)
    }

    func testBackgroundWorkCanPauseResumeAndCancel() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        let item = BackgroundWorkItem.testItem(id: "pause-target")
        model.enqueueBackgroundWork(item)

        model.pauseBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .paused)
        XCTAssertTrue(model.canResumeBackgroundWork)

        model.resumeBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)

        model.cancelBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .cancelled)
        XCTAssertFalse(model.canPauseBackgroundWork)
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

    func testPagingSynthetic100kCatalogKeepsLoadedAssetWindowBounded() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-100k-window")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 100_000, repository: repository)
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
        XCTAssertEqual(model.totalAssetCount, 100_000)

        for _ in 0..<20 {
            try model.loadMoreAssets()
        }

        XCTAssertEqual(model.assets.count, 1_000)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-9500"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-10499"))
        XCTAssertEqual(model.totalAssetCount, 100_000)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 9501-10500 of 100000 photographs")
    }

    func testLoadPreviousAssetsKeepsLoadedAssetWindowBounded() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-previous-window")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 2_500, repository: repository)
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
        for _ in 0..<3 {
            try model.loadMoreAssets()
        }

        try model.loadPreviousAssets()

        XCTAssertEqual(model.assets.count, 1_000)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-500"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-1499"))
        XCTAssertEqual(model.totalAssetCount, 2_500)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 501-1500 of 2500 photographs")
    }

    func testApplyingLibraryFiltersLoadsMatchingCatalogAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-filter")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([
            Asset(
                id: AssetID(rawValue: "keeper"),
                originalURL: URL(fileURLWithPath: "/Photos/Wedding/ceremony-keeper.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: .online,
                metadata: AssetMetadata(rating: 5, flag: .pick)
            ),
            Asset(
                id: AssetID(rawValue: "reject"),
                originalURL: URL(fileURLWithPath: "/Photos/Wedding/ceremony-blink.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 2, modificationDate: Date(timeIntervalSince1970: 2)),
                availability: .online,
                metadata: AssetMetadata(rating: 1, flag: .reject)
            ),
            Asset(
                id: AssetID(rawValue: "travel"),
                originalURL: URL(fileURLWithPath: "/Photos/Travel/mountain.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 3, modificationDate: Date(timeIntervalSince1970: 3)),
                availability: .online,
                metadata: AssetMetadata(rating: 5)
            )
        ])
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

        model.librarySearchText = "CEREMONY"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "keeper")])
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "keeper"))
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.libraryCountText, "1 photograph")
    }

    func testLoadExposesSavedAndStarredAssetSetsInSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-saved-sets")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let starred = AssetSet(
            id: AssetSetID(rawValue: "starred"),
            name: "Portfolio Shortlist",
            membership: .dynamic(SetQuery(predicates: [.ratingAtLeast(5)])),
            starred: true
        )
        let saved = AssetSet.dynamic(
            id: AssetSetID(rawValue: "saved"),
            name: "Ceremony Picks",
            query: SetQuery(predicates: [.text("ceremony"), .flag(.pick)])
        )
        try repository.upsert(starred)
        try repository.upsert(saved)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.savedAssetSets.map(\.id), [starred.id, saved.id])
        XCTAssertEqual(model.starredAssetSets.map(\.id), [starred.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, [starred.name])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Saved Sets" }?.rowTitles, [starred.name, saved.name])
    }

    func testLoadExposesRecentAndStarredWorkSessionsInSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-work-sessions")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let recent = WorkSession(
            id: WorkSessionID(rawValue: "recent-import"),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported 12 photos",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 12,
            totalUnitCount: 12,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let starred = WorkSession(
            id: WorkSessionID(rawValue: "starred-cull"),
            kind: .culling,
            intent: "One hero per burst",
            title: "Cull Ceremony",
            detail: "Reviewing ceremony candidates",
            status: .paused,
            inputSetIDs: [AssetSetID(rawValue: "candidates")],
            outputSetIDs: [],
            completedUnitCount: 25,
            totalUnitCount: 100,
            failureCount: 0,
            starred: true,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 15)
        )
        try repository.save(recent)
        try repository.save(starred)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.recentWork.map(\.id), [recent.id.rawValue, starred.id.rawValue])
        XCTAssertEqual(model.starredWork.map(\.id), [starred.id.rawValue])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Work" }?.rowTitles, [recent.title, starred.title])
    }

    func testApplyingDynamicSavedSetLoadsMatchingCatalogAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-dynamic-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/Wedding/ceremony-keeper.jpg", rating: 5, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/ceremony-blink.jpg", rating: 1, flag: .reject)
        try repository.upsert([keeper, reject])
        let set = AssetSet.dynamic(
            id: AssetSetID(rawValue: "ceremony-picks"),
            name: "Ceremony Picks",
            query: SetQuery(predicates: [.text("ceremony"), .ratingAtLeast(4), .flag(.pick)])
        )
        try repository.upsert(set)
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

        try model.applyAssetSet(id: set.id)

        XCTAssertEqual(model.selectedAssetSetID, set.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.selectedView, .grid)
    }

    func testApplyingSnapshotSavedSetLoadsCatalogAssetsInSavedOrder() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-snapshot-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = makeAsset(id: "first", path: "/Photos/first.jpg", rating: 1)
        let second = makeAsset(id: "second", path: "/Photos/second.jpg", rating: 2)
        let third = makeAsset(id: "third", path: "/Photos/third.jpg", rating: 3)
        try repository.upsert([first, second, third])
        let set = AssetSet(
            id: AssetSetID(rawValue: "portfolio"),
            name: "Portfolio",
            membership: .snapshot([third.id, first.id])
        )
        try repository.upsert(set)
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

        try model.applyAssetSet(id: set.id)

        XCTAssertEqual(model.selectedAssetSetID, set.id)
        XCTAssertEqual(model.assets.map(\.id), [third.id, first.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testSavingCurrentLibraryQueryCreatesSelectedStarredSet() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-save-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/Wedding/ceremony-keeper.jpg", rating: 5, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/ceremony-blink.jpg", rating: 1, flag: .reject)
        try repository.upsert([keeper, reject])
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
        model.librarySearchText = "ceremony"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        try model.applyLibraryFilters()

        let savedSet = try model.saveCurrentLibraryQuery(named: " Ceremony Picks ", starred: true)

        XCTAssertEqual(savedSet.name, "Ceremony Picks")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [.text("ceremony"), .ratingAtLeast(4), .flag(.pick)])))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.savedAssetSets, [savedSet])
        XCTAssertEqual(model.starredAssetSets, [savedSet])
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.librarySearchText, "")
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertNil(model.flagFilter)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, ["Ceremony Picks"])
    }

    func testSavingCurrentLibraryQueryRequiresActiveQuery() throws {
        let (model, _, _) = try makeModelWithCatalogAsset(named: "empty-save-search")

        XCTAssertFalse(model.canSaveCurrentLibraryQuery)
        XCTAssertThrowsError(try model.saveCurrentLibraryQuery(named: "No Filter"))
    }

    func testSavingSelectedAssetCreatesSelectedManualSet() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "manual-set-photo")

        let savedSet = try model.saveSelectedAssetAsManualSet(named: " Keeper ", starred: true)

        XCTAssertEqual(savedSet.name, "Keeper")
        XCTAssertEqual(savedSet.membership, .manual([asset.id]))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.savedAssetSets, [savedSet])
        XCTAssertEqual(model.starredAssetSets, [savedSet])
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, ["Keeper"])
    }

    func testSavingSelectedAssetAsManualSetRequiresSelection() throws {
        let directory = try makeTemporaryDirectory(named: "manual-set-no-selection")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let model = try AppModel.load(repository: repository)

        XCTAssertThrowsError(try model.saveSelectedAssetAsManualSet(named: "No Selection"))
    }

    func testManualSetSaveAffordancesReflectSelectionAndCatalog() throws {
        let (model, _, asset) = try makeModelWithCatalogAsset(named: "manual-set-photo")

        XCTAssertTrue(model.canSaveSelectedAssetAsManualSet)
        XCTAssertEqual(model.suggestedManualSetName, "manual-set-photo")

        model.selectedAssetID = nil

        XCTAssertFalse(model.canSaveSelectedAssetAsManualSet)
        XCTAssertEqual(model.suggestedManualSetName, "Selection")

        let uncatalogedModel = AppModel(sidebarSections: [], selectedView: .grid, assets: [asset])

        XCTAssertFalse(uncatalogedModel.canSaveSelectedAssetAsManualSet)
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
    func testBackgroundImportShowsImportedAssetWhenFirstCatalogPageIsFull() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-page")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("new.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        for index in 0..<500 {
            try catalog.repository.upsert(Asset(
                id: AssetID(rawValue: "existing-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/existing-\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }
        let model = try AppModel.load(catalog: catalog)
        XCTAssertFalse(model.assets.contains { $0.originalURL == image })

        model.beginImportFolder(photoFolder)
        try await waitForActivityStatus(.completed, in: model)

        let importedAsset = try XCTUnwrap(model.selectedAsset)
        XCTAssertTrue(model.assets.contains { $0.id == importedAsset.id })
        XCTAssertEqual(model.selectedAssetID, importedAsset.id)
        XCTAssertEqual(importedAsset.originalURL, image)
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertEqual(model.libraryCountText, "Showing 501-501 of 501 photographs")
        XCTAssertTrue(model.hasPreviousAssets)

        try model.loadPreviousAssets()

        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "existing-0"))
        XCTAssertEqual(model.assets.last?.id, importedAsset.id)
        XCTAssertFalse(model.hasPreviousAssets)
    }

    func testLoupePreviewURLPrefersLargePreviewOverGridPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-large")
        let gridPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        let largePreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large))
        try writePreviewPlaceholder(to: gridPreview)
        try writePreviewPlaceholder(to: largePreview)

        XCTAssertEqual(model.loupePreviewURL(for: asset.id), largePreview)
    }

    func testLoupePreviewURLFallsBackToGridPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-grid")
        let gridPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try writePreviewPlaceholder(to: gridPreview)

        XCTAssertEqual(model.loupePreviewURL(for: asset.id), gridPreview)
    }

    func testRefreshSelectedAvailabilityKeepsCachedPreviewsForMissingOriginal() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "offline-preview")
        let gridPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try writePreviewPlaceholder(to: gridPreview)

        try model.refreshSelectedAssetAvailability()

        XCTAssertEqual(model.selectedAsset?.availability, .missing)
        XCTAssertEqual(model.gridPreviewURL(for: asset.id), gridPreview)
        XCTAssertEqual(model.loupePreviewURL(for: asset.id), gridPreview)
    }

    func testRequestMissingPreviewDispatchesWorkerPreviewCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-preview",
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .large)])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .previewGeneration)
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
    }

    func testRequestCachedPreviewDoesNotDispatchWorkerPreviewCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-cached-preview",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testRequestMissingPreviewDoesNotDispatchDuplicateInFlightWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-preview-dedup",
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: asset.id, level: .large)
        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .large)])
        XCTAssertEqual(model.backgroundWorkQueue.items.count, 1)
    }

    func testLoadEnqueuesPendingPreviewGenerationWithWorker() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "pending-preview",
            workerSupervisor: supervisor,
            pendingPreviewLevel: .grid
        )

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .grid)])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .previewGeneration)
    }

    func testRequestEvaluationDispatchesWorkerRecognitionCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-evaluation",
            workerSupervisor: supervisor
        )

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")

        XCTAssertEqual(try transport.commands(), [.runEvaluation(assetID: asset.id, provider: "local-image-metrics")])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .recognition)
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
    }

    func testRequestSelectedAssetEvaluationUsesDefaultLocalProvider() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-selected-evaluation",
            workerSupervisor: supervisor
        )

        try model.requestSelectedAssetEvaluation()

        XCTAssertEqual(try transport.commands(), [.runEvaluation(assetID: asset.id, provider: "local-image-metrics")])
    }

    func testCanRequestSelectedAssetEvaluationRequiresSelectionAndWorker() throws {
        let (modelWithoutWorker, _, _) = try makeModelWithPreviewCache(named: "evaluation-without-worker")
        XCTAssertFalse(modelWithoutWorker.canRequestSelectedAssetEvaluation)

        let modelWithoutSelection = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        XCTAssertFalse(modelWithoutSelection.canRequestSelectedAssetEvaluation)

        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: RecordingWorkerTransport()
        )
        let (model, _, _) = try makeModelWithPreviewCache(
            named: "evaluation-available",
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestSelectedAssetEvaluation)
    }

    @MainActor
    func testWorkerCompletionRefreshesVisibleBackgroundWork() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "preview-completion-refresh",
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .large)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-large"),
            message: "generated large preview for \(asset.id.rawValue)"
        )))

        try await waitForVisibleWorkStatus(.completed, in: model)
    }

    @MainActor
    func testWorkerFailureRefreshesVisibleBackgroundWork() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "preview-failure-refresh",
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .large)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-large"),
            message: "could not render preview"
        )))

        try await waitForVisibleWorkStatus(.failed, in: model)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "could not render preview")
    }

    func testVisibleLoupePreviewRequestsMediumThenLargeWhenNeitherIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "loupe-progressive-preview",
            workerSupervisor: supervisor
        )

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .medium),
            .generatePreview(assetID: asset.id, level: .large)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-\(asset.id.rawValue)-medium",
            "preview-\(asset.id.rawValue)-large"
        ])
    }

    func testVisibleLoupePreviewDoesNotDispatchWhenLargePreviewIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "loupe-progressive-cached-large",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testVisibleGridPreviewRequestsGridPreviewWhenMissing() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "grid-visible-preview",
            workerSupervisor: supervisor
        )

        try model.requestVisibleGridPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .grid)])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-\(asset.id.rawValue)-grid"
        ])
    }

    func testBackgroundControlsForwardToWorkerSupervisor() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "preview-controls",
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .medium)

        model.pauseBackgroundWork()
        model.resumeBackgroundWork()
        model.cancelBackgroundWork()

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .medium),
            .pause,
            .resume,
            .cancelAll
        ])
        XCTAssertEqual(model.visibleWorkActivity?.status, .cancelled)
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
    func testBackgroundImportWithWorkerDefersPreviewGenerationToWorker() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import-worker-previews")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        let result = try await model.importFolderInBackground(photoFolder)

        let assetID = result.importedAssets[0].id
        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertNil(model.gridPreviewURL(for: assetID))
        XCTAssertEqual(try catalog.repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: assetID, level: .grid)
        ])
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: assetID, level: .grid)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .previewGeneration)
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
    func testBackgroundImportPersistsCompletedActivityForReload() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-activity-reload")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try await model.importFolderInBackground(photoFolder)

        let reloaded = try AppModel.load(catalog: catalog)
        let activity = try XCTUnwrap(reloaded.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.title, "Import photos")
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(activity.completedUnitCount, 1)
        XCTAssertEqual(activity.totalUnitCount, 1)
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
            importTaskFactory: { _, _, _ in
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

    @MainActor
    func testBackgroundImportAppliesProgressUpdatesBeforeCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-progress")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, progress in
                Task {
                    progress(LibraryImportProgress(
                        completedUnitCount: 1,
                        totalUnitCount: 2,
                        detail: "Generated 1 of 2 previews"
                    ))
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

        try await waitForActiveWorkProgress(
            completedUnitCount: 1,
            totalUnitCount: 2,
            detail: "Generated 1 of 2 previews",
            in: model
        )
        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)
    }

    @MainActor
    func testBackgroundImportShowsCatalogedAssetsBeforePreviewCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("early.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let importedAsset = Asset(
            id: AssetID(rawValue: "early-import"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { paths, _, progress in
                Task.detached {
                    let backgroundCatalog = try AppCatalog.open(paths: paths)
                    try backgroundCatalog.repository.upsert(importedAsset)
                    progress(LibraryImportProgress(
                        completedUnitCount: 1,
                        totalUnitCount: 1,
                        detail: "Cataloged 1 photo",
                        catalogedAssetIDs: [importedAsset.id]
                    ))
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [importedAsset], previewFailures: []),
                        assets: try backgroundCatalog.repository.allAssets(limit: 500),
                        totalAssetCount: try backgroundCatalog.repository.assetCount()
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.activeWork?.status, .running)

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)
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

    private func writePreviewPlaceholder(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: url)
    }

    private func seedCatalogAssets(count: Int, repository: CatalogRepository) throws {
        let batchSize = 1_000
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, count)
            let assets = (batchStart..<batchEnd).map { index in
                Asset(
                    id: AssetID(rawValue: "asset-\(index)"),
                    originalURL: URL(fileURLWithPath: "/Volumes/NAS/Photos/frame-\(index).dng"),
                    volumeIdentifier: "NAS",
                    fingerprint: FileFingerprint(
                        size: Int64(index + 1),
                        modificationDate: Date(timeIntervalSince1970: TimeInterval(index))
                    ),
                    availability: index.isMultiple(of: 2) ? .online : .offline,
                    metadata: AssetMetadata(rating: index % 6)
                )
            }
            try repository.upsert(assets)
        }
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

    private func makeAsset(
        id: String,
        path: String,
        rating: Int,
        flag: PickFlag? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: .online,
            metadata: AssetMetadata(rating: rating, flag: flag)
        )
    }

    private func makeModelWithPreviewCache(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil,
        pendingPreviewLevel: PreviewLevel? = nil
    ) throws -> (AppModel, PreviewCache, Asset) {
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
        if let pendingPreviewLevel {
            try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: pendingPreviewLevel))
        }
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), previewCache, asset)
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

    @MainActor
    private func waitForVisibleWorkStatus(_ status: WorkSessionStatus, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.visibleWorkActivity?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for visible work status \(status.rawValue)")
    }

    @MainActor
    private func waitForSelectedAsset(_ assetID: AssetID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.selectedAssetID == assetID {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for selected asset \(assetID.rawValue)")
    }

    @MainActor
    private func waitForActiveWorkProgress(
        completedUnitCount: Int,
        totalUnitCount: Int?,
        detail: String,
        in model: AppModel
    ) async throws {
        for _ in 0..<100 {
            if model.activeWork?.completedUnitCount == completedUnitCount,
               model.activeWork?.totalUnitCount == totalUnitCount,
               model.activeWork?.detail == detail {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for active import progress")
    }
}

private extension BackgroundWorkItem {
    static func testItem(id: String) -> BackgroundWorkItem {
        BackgroundWorkItem(
            id: WorkSessionID(rawValue: id),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Rendering cached previews",
            completedUnitCount: 0,
            totalUnitCount: 10
        )
    }
}

private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?

    private(set) var lines: [String] = []
    private(set) var isRunning = false

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        lines.append(line)
    }

    func terminate() {
        isRunning = false
    }

    func commands() throws -> [WorkerCommand] {
        try lines.map { try WorkerProtocolEncoder.decode($0) }
    }

    func emitOutputLine(_ line: String) {
        outputHandler?(line)
    }

    func emitErrorLine(_ line: String) {
        errorHandler?(line)
    }
}
