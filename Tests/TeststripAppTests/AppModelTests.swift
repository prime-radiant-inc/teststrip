import XCTest
import TeststripCore
@testable import TeststripApp

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

    func testWorkActivityShowsProgressOnlyForActiveWorkWithKnownTotal() {
        var activity = AppWorkActivity(
            kind: .previewGeneration,
            status: .running,
            title: "Generate preview",
            detail: "Rendering",
            completedUnitCount: 1,
            totalUnitCount: 8,
            failureCount: 0
        )

        XCTAssertTrue(activity.showsProgress)

        activity.status = .queued
        XCTAssertTrue(activity.showsProgress)

        activity.status = .paused
        XCTAssertTrue(activity.showsProgress)

        activity.status = .completed
        XCTAssertFalse(activity.showsProgress)

        activity.status = .failed
        XCTAssertFalse(activity.showsProgress)

        activity.status = .cancelled
        XCTAssertFalse(activity.showsProgress)

        activity.status = .running
        activity.totalUnitCount = nil
        XCTAssertFalse(activity.showsProgress)
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

    func testCompareAssetsReturnWindowAroundSelectionWhenSelectionLeavesCurrentSet() {
        let assets = (0..<6).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .compare, assets: assets)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[0..<4].map(\.id))

        model.select(assets[5].id)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[2..<6].map(\.id))
    }

    func testCompareAssetsStayStableWhenSelectingAssetInsideCurrentCompareSet() {
        let assets = (0..<6).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)
        model.selectedView = .compare
        let initialCompareIDs = model.compareAssets().map(\.id)

        model.select(assets[3].id)

        XCTAssertEqual(model.compareAssets().map(\.id), initialCompareIDs)
    }

    func testComparePreviewRequestIDChangesWhenSelectionChangesInsideSameWindow() {
        let assets = (0..<6).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .compare, assets: assets)
        let initialRequestID = ComparePreviewRequestID.make(for: model)

        model.select(assets[1].id)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[0..<4].map(\.id))
        XCTAssertNotEqual(ComparePreviewRequestID.make(for: model), initialRequestID)
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

    func testLibraryTitleReflectsSelectedCatalogScope() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        XCTAssertEqual(model.libraryTitle, "All Photographs")

        model.folderFilterText = "/Volumes/NAS/Wedding/Ceremony/"
        XCTAssertEqual(model.libraryTitle, "Ceremony")

        model.evaluationKindFilter = .faceQuality
        model.folderFilterText = ""
        XCTAssertEqual(model.libraryTitle, "Face Quality Signal")

        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "ceremony-picks"),
            name: "Ceremony Picks",
            assetIDs: []
        )
        model.savedAssetSets = [set]
        model.selectedAssetSetID = set.id
        XCTAssertEqual(model.libraryTitle, "Ceremony Picks")
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

    func testKeywordTextSelectedAssetNormalizesKeywordsAndWritesXmpSidecar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-keyword-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "keyword-xmp-write-target"),
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

        try model.setKeywordTextForSelectedAsset(" Patagonia, keeper, , Patagonia ")

        let expectedKeywords = ["Patagonia", "keeper"]
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, expectedKeywords)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testPortableTextMetadataSelectedAssetWritesXmpSidecar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-portable-text-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "portable-text-xmp-write-target"),
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

        try model.setCaptionForSelectedAsset("  Fitz Roy sunrise  ")
        try model.setCreatorForSelectedAsset("  Jesse  ")
        try model.setCopyrightForSelectedAsset("  Copyright Jesse  ")

        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        let catalogMetadata = try repository.asset(id: asset.id).metadata
        let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata
        XCTAssertEqual(model.selectedAsset?.metadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(model.selectedAsset?.metadata.creator, "Jesse")
        XCTAssertEqual(model.selectedAsset?.metadata.copyright, "Copyright Jesse")
        XCTAssertEqual(catalogMetadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(catalogMetadata.creator, "Jesse")
        XCTAssertEqual(catalogMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(sidecarMetadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(sidecarMetadata.creator, "Jesse")
        XCTAssertEqual(sidecarMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
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

    func testResolveSelectedMetadataConflictUsingCatalogOverwritesSidecar() throws {
        let catalogMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["catalog"])
        let sidecarMetadata = AssetMetadata(rating: 2, colorLabel: .red, flag: .reject, keywords: ["sidecar"])
        let (model, repository, asset, originalURL, sidecarURL) = try makeModelWithXMPConflict(
            named: "resolve-conflict-catalog",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )

        try model.resolveSelectedMetadataConflictUsingCatalog()

        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, catalogMetadata)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, catalogMetadata)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [])
        XCTAssertEqual(model.metadataSyncConflictItems, [])
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testResolveSelectedMetadataConflictUsingSidecarImportsSidecarMetadata() throws {
        let catalogMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["catalog"])
        let sidecarMetadata = AssetMetadata(rating: 2, colorLabel: .red, flag: .reject, keywords: ["sidecar"])
        let (model, repository, asset, originalURL, sidecarURL) = try makeModelWithXMPConflict(
            named: "resolve-conflict-sidecar",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )

        try model.resolveSelectedMetadataConflictUsingSidecar()

        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, sidecarMetadata)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, sidecarMetadata)
        XCTAssertEqual(model.selectedAsset?.metadata, sidecarMetadata)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [])
        XCTAssertEqual(model.metadataSyncConflictItems, [])
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
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

    func testSelectingAssetQueuesWorkerMetadataSyncCheckWhenSupervisorConfigured() throws {
        let first = makeAsset(id: "selection-xmp-first", size: 1)
        let second = makeAsset(id: "selection-xmp-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "selection-worker-xmp-check",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: second.id)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Checking XMP sidecar")
    }

    func testSelectingAssetDoesNotSynchronouslyWriteXmpWithoutWorker() throws {
        let directory = try makeTemporaryDirectory(named: "selection-no-worker-xmp")
        let firstURL = directory.appendingPathComponent("first.dng")
        let secondURL = directory.appendingPathComponent("second.dng")
        try Data("first original".utf8).write(to: firstURL)
        try Data("second original".utf8).write(to: secondURL)
        let first = Asset(
            id: AssetID(rawValue: "selection-no-worker-first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: firstURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "selection-no-worker-second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: secondURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "selection-no-worker-xmp-catalog",
            assets: [first, second]
        )

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.appendingPathExtension("xmp").path))
    }

    func testSelectingAssetDoesNotQueueDuplicateActiveMetadataSyncCheck() throws {
        let first = makeAsset(id: "duplicate-selection-xmp-first", size: 1)
        let second = makeAsset(id: "duplicate-selection-xmp-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "duplicate-selection-worker-xmp-check",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        model.select(second.id)

        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: second.id)])
    }

    @MainActor
    func testCompletedSelectionMetadataCheckDoesNotReplaceVisibleActivity() async throws {
        let first = makeAsset(id: "completed-selection-xmp-first", size: 1)
        let second = makeAsset(id: "completed-selection-xmp-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "completed-selection-worker-xmp-check",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "metadata up to date for second.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertNil(model.visibleWorkActivity)
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

    func testColorLabelCullingCommandUpdatesSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "color-label-command")

        try model.applyCullingCommand(.colorLabel(.green))
        XCTAssertEqual(model.selectedAsset?.metadata.colorLabel, .green)

        try model.applyCullingCommand(.colorLabel(nil))
        XCTAssertNil(model.selectedAsset?.metadata.colorLabel)
        XCTAssertNil(try repository.asset(id: asset.id).metadata.colorLabel)
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

        try model.applyCullingShortcut(.colorLabel(.green))
        XCTAssertEqual(model.selectedAsset?.metadata.colorLabel, .green)

        try model.applyCullingShortcut(.reject)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.colorLabel, .green)
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

    func testCullingShortcutLoadsNextPageWhenAdvancingPastLoadedAssets() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-next-page", count: 501)
        model.select(AssetID(rawValue: "asset-499"))

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-500"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-500"))
        XCTAssertFalse(model.hasMoreAssets)
    }

    func testCullingShortcutLoadsPreviousPageWhenMovingBeforeLoadedAssets() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-previous-page", count: 1_500)
        try model.loadMoreAssets()
        try model.loadMoreAssets()
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-500"))
        model.select(AssetID(rawValue: "asset-500"))

        try model.applyCullingShortcut(.previousPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-499"))
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-0"))
        XCTAssertTrue(model.hasMoreAssets)
    }

    func testCullingShortcutInterpretsKeyboardKeys() {
        XCTAssertEqual(CullingShortcut(key: .rightArrow), .nextPhoto)
        XCTAssertEqual(CullingShortcut(key: .leftArrow), .previousPhoto)
        XCTAssertEqual(CullingShortcut(key: .character("5")), .rating(5))
        XCTAssertEqual(CullingShortcut(key: .character("6")), .colorLabel(.red))
        XCTAssertEqual(CullingShortcut(key: .character("7")), .colorLabel(.yellow))
        XCTAssertEqual(CullingShortcut(key: .character("8")), .colorLabel(.green))
        XCTAssertEqual(CullingShortcut(key: .character("9")), .colorLabel(.blue))
        XCTAssertEqual(CullingShortcut(key: .character("v")), .colorLabel(.purple))
        XCTAssertEqual(CullingShortcut(key: .character("-")), .colorLabel(nil))
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

    func testVisibleWorkActivitiesExposeBackgroundQueueShape() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let third = BackgroundWorkItem.testItem(id: "third")

        model.enqueueBackgroundWork(first)
        model.enqueueBackgroundWork(second)
        model.enqueueBackgroundWork(third)

        XCTAssertEqual(model.visibleWorkActivities.map(\.id), [
            first.id.rawValue,
            second.id.rawValue,
            third.id.rawValue
        ])
        XCTAssertEqual(model.visibleWorkActivities.map(\.status), [.running, .queued, .queued])
        XCTAssertEqual(model.visibleWorkActivity?.id, first.id.rawValue)
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
                metadata: AssetMetadata(rating: 5, colorLabel: .green, flag: .pick)
            ),
            Asset(
                id: AssetID(rawValue: "reject"),
                originalURL: URL(fileURLWithPath: "/Photos/Wedding/ceremony-blink.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 2, modificationDate: Date(timeIntervalSince1970: 2)),
                availability: .online,
                metadata: AssetMetadata(rating: 1, colorLabel: .red, flag: .reject)
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
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "keeper")])
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "keeper"))
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.libraryCountText, "1 photograph")
    }

    func testApplyingLibraryFiltersUsesFolderPrefix() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-filter",
            assets: [ceremony, portraits, travel]
        )

        model.folderFilterText = "/Volumes/NAS/Wedding/"
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [portraits.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        let savedSet = try model.saveCurrentLibraryQuery(named: "Wedding Five Stars")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .folderPrefix("/Volumes/NAS/Wedding/"),
            .ratingAtLeast(5)
        ])))
    }

    func testApplyingLibraryFiltersUsesTechnicalMetadata() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-technical-filters")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_086_400)
        let canon = makeAsset(
            id: "canon",
            path: "/Photos/Job/canon.cr3",
            rating: 4,
            availability: .offline,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                cameraMake: "Canon",
                cameraModel: "EOS R5",
                lensModel: "RF 50mm F1.2L USM",
                isoSpeed: 1600,
                capturedAt: Date(timeIntervalSince1970: 1_800_010_000),
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
        let fuji = makeAsset(
            id: "fuji",
            path: "/Photos/Job/fuji.raf",
            rating: 5,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 8256,
                pixelHeight: 5504,
                cameraMake: "Fujifilm",
                cameraModel: "GFX 100S",
                lensModel: "GF80mmF1.7 R WR",
                isoSpeed: 400,
                capturedAt: Date(timeIntervalSince1970: 1_800_020_000),
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
        try repository.upsert([canon, fuji])
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
        model.cameraFilterText = "canon"
        model.lensFilterText = "RF 50"
        model.minimumISOFilter = 800
        model.captureDateStartFilter = start
        model.captureDateEndFilter = end
        model.availabilityFilter = .offline

        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [canon.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertTrue(model.canSaveCurrentLibraryQuery)
        let savedSet = try model.saveCurrentLibraryQuery(named: "Canon High ISO")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .camera("canon"),
            .lens("RF 50"),
            .isoAtLeast(800),
            .capturedAtOrAfter(start),
            .capturedBefore(end),
            .availability(.offline)
        ])))
    }

    func testApplyingLibraryFiltersUsesEvaluationKind() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-evaluation-kind-filter")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let focused = makeAsset(id: "focused", path: "/Photos/Job/focused.jpg", rating: 0)
        let object = makeAsset(id: "object", path: "/Photos/Job/object.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([focused, object])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: focused.id, kind: .focus, value: .score(0.91), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance)
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
        model.evaluationKindFilter = .focus

        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [focused.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        let savedSet = try model.saveCurrentLibraryQuery(named: "Focused")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [.evaluationKind(.focus)])))
    }

    func testLoadExposesEvaluationSignalSidebarAndSelectingSignalAppliesFilter() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-evaluation-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let face = makeAsset(id: "face", path: "/Photos/Job/face.jpg", rating: 0)
        let object = makeAsset(id: "object", path: "/Photos/Job/object.jpg", rating: 0)
        let unevaluated = makeAsset(id: "unevaluated", path: "/Photos/Job/unevaluated.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([face, object, unevaluated])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: face.id, kind: .faceQuality, value: .score(0.82), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance)
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

        let signalSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "AI" })
        XCTAssertEqual(signalSection.rowTitles, ["Faces", "Objects"])
        let faceRow = try XCTUnwrap(signalSection.rows.first { $0.title == "Faces" })

        try model.selectSidebarRow(faceRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.evaluationKindFilter, .faceQuality)
        XCTAssertEqual(model.assets.map(\.id), [face.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testTechnicalFiltersCountAsActiveLibraryFiltersAndClear() throws {
        let (model, _, _) = try makeModelWithCatalogAsset(named: "active-technical-filter")

        model.cameraFilterText = "Canon"
        model.folderFilterText = "/Photos/Jobs/"
        model.keywordFilterText = "portfolio"
        model.colorLabelFilter = .green
        model.availabilityFilter = .offline
        XCTAssertTrue(model.hasActiveLibraryFilters)

        try model.clearLibraryFilters()

        XCTAssertFalse(model.hasActiveLibraryFilters)
        XCTAssertNil(model.colorLabelFilter)
        XCTAssertNil(model.availabilityFilter)
        XCTAssertEqual(model.keywordFilterText, "")
        XCTAssertEqual(model.folderFilterText, "")
        XCTAssertEqual(model.cameraFilterText, "")
        XCTAssertEqual(model.lensFilterText, "")
        XCTAssertNil(model.minimumISOFilter)
        XCTAssertNil(model.captureDateStartFilter)
        XCTAssertNil(model.captureDateEndFilter)
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

    func testLoadExposesCatalogFoldersInSidebarAndSelectingFolderAppliesFilter() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-sidebar",
            assets: [ceremony, portraits, travel]
        )

        let folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        XCTAssertEqual(folderSection.rowTitles, ["Travel", "Ceremony", "Portraits"])
        let ceremonyRow = try XCTUnwrap(folderSection.rows.first { $0.title == "Ceremony" })

        try model.selectSidebarRow(ceremonyRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.folderFilterText, "/Volumes/NAS/Wedding/Ceremony/")
        XCTAssertEqual(model.assets.map(\.id), [ceremony.id])
        XCTAssertEqual(model.totalAssetCount, 1)
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
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Work" }?.rowTitles, [recent.detail, starred.title])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Work" }?.rows.map(\.target), [
            .workSession(recent.id),
            .workSession(starred.id)
        ])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Work" }?.rows.map(\.isSelectable), [true, true])
    }

    func testSettingWorkSessionStarredRefreshesWorkLists() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-star-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Pick strongest frame",
            status: .running,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 10,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
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

        try model.setWorkSessionStarred(id: session.id, starred: true)

        XCTAssertEqual(try repository.session(id: session.id).starred, true)
        XCTAssertEqual(model.recentWork.first?.id, session.id.rawValue)
        XCTAssertEqual(model.recentWork.first?.starred, true)
        XCTAssertEqual(model.starredWork.map(\.id), [session.id.rawValue])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Work" }?.rowTitles, [session.title])

        try model.setWorkSessionStarred(id: session.id, starred: false)

        XCTAssertEqual(try repository.session(id: session.id).starred, false)
        XCTAssertEqual(model.recentWork.first?.starred, false)
        XCTAssertEqual(model.starredWork, [])
    }

    func testSelectingWorkSessionAppliesAssociatedOutputSet() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-select-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-output"),
            name: "Work Output",
            assetIDs: [keeper.id]
        )
        try repository.upsert(outputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Selected one keeper",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: 2,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
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
        let model = try AppModel.load(catalog: catalog)
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Work" }?.rows.first)

        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, outputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
    }

    func testSelectingCullingWorkSessionReopensCompareView() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-select-culling-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "cull-input"),
            name: "Cull Input",
            query: SetQuery(predicates: [.ratingAtLeast(4)])
        )
        try repository.upsert(inputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Pick strongest frame",
            status: .running,
            inputSetIDs: [inputSet.id],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
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
        let model = try AppModel.load(catalog: catalog)
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Work" }?.rows.first)

        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, inputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.selectedView, .compare)
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
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            colorLabel: .green,
            flag: .pick,
            keywords: ["portfolio"]
        )
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/ceremony-blink.jpg", rating: 1, colorLabel: .red, flag: .reject)
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
        model.keywordFilterText = "portfolio"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()

        let savedSet = try model.saveCurrentLibraryQuery(named: " Ceremony Picks ", starred: true)

        XCTAssertEqual(savedSet.name, "Ceremony Picks")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [.text("ceremony"), .keyword("portfolio"), .ratingAtLeast(4), .flag(.pick), .colorLabel(.green)])))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.savedAssetSets, [savedSet])
        XCTAssertEqual(model.starredAssetSets, [savedSet])
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.librarySearchText, "")
        XCTAssertEqual(model.keywordFilterText, "")
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.colorLabelFilter)
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

    func testBeginningCullingSessionUsesSelectedAssetSetAsInput() throws {
        let directory = try makeTemporaryDirectory(named: "culling-session-selected-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        try repository.upsert(inputSet)
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
        let model = try AppModel.load(catalog: catalog)
        try model.applyAssetSet(id: inputSet.id)

        let session = try model.beginCullingSession(named: " Ceremony Cull ", intent: " One hero per burst ")

        XCTAssertTrue(model.canBeginCullingSession)
        XCTAssertEqual(session.kind, .culling)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.title, "Ceremony Cull")
        XCTAssertEqual(session.intent, "One hero per burst")
        XCTAssertEqual(session.inputSetIDs, [inputSet.id])
        XCTAssertEqual(session.totalUnitCount, 1)
        XCTAssertEqual(model.selectedView, .compare)
        XCTAssertEqual(model.recentWork.first?.id, session.id.rawValue)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Work" }?.rowTitles.first, "Ceremony Cull")

        try model.clearLibraryFilters()
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Work" }?.rows.first)
        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, inputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
    }

    func testBeginningCullingSessionCreatesHiddenInputSetForAdhocSearch() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/Wedding/keeper.jpg", rating: 5, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/reject.jpg", rating: 1, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "culling-session-adhoc-search",
            assets: [keeper, reject]
        )
        model.librarySearchText = "Wedding"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        try model.applyLibraryFilters()

        let session = try model.beginCullingSession(named: "Wedding Cull")

        let inputSetID = try XCTUnwrap(session.inputSetIDs.first)
        let inputSet = try repository.assetSet(id: inputSetID)
        XCTAssertTrue(inputSetID.rawValue.hasPrefix("work-input-"))
        XCTAssertEqual(inputSet.name, "Wedding Cull Input")
        XCTAssertEqual(inputSet.membership, .dynamic(SetQuery(predicates: [.text("Wedding"), .ratingAtLeast(4), .flag(.pick)])))
        XCTAssertEqual(model.selectedAssetSetID, inputSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.selectedView, .compare)
        XCTAssertFalse(model.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Wedding Cull Input")
        })

        try model.clearLibraryFilters()
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Work" }?.rows.first)
        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, inputSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
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
        XCTAssertEqual(model.catalogFolders, [
            CatalogFolder(path: "\(photoFolder.path)/", name: "photos", assetCount: 1)
        ])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Folders" }?.rowTitles, ["photos"])
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

    func testLoupePreviewURLFallsBackToMicroPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-micro")
        let microPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
        try writePreviewPlaceholder(to: microPreview)

        XCTAssertEqual(model.loupePreviewURL(for: asset.id), microPreview)
    }

    func testGridPreviewURLFallsBackToMicroPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "grid-micro")
        let microPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
        try writePreviewPlaceholder(to: microPreview)

        XCTAssertEqual(model.gridPreviewURL(for: asset.id), microPreview)
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

    func testRefreshVisibleAvailabilityUpdatesLoadedAssetsAndCatalog() throws {
        let directory = try makeTemporaryDirectory(named: "visible-availability")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let onlineURL = photosDirectory.appendingPathComponent("online.jpg")
        let missingURL = photosDirectory.appendingPathComponent("missing.jpg")
        try Data("online".utf8).write(to: onlineURL)
        try Data("missing".utf8).write(to: missingURL)
        let onlineAsset = Asset(
            id: AssetID(rawValue: "online"),
            originalURL: onlineURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: onlineURL),
            availability: .missing,
            metadata: AssetMetadata()
        )
        let missingAsset = Asset(
            id: AssetID(rawValue: "missing"),
            originalURL: missingURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: missingURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(onlineAsset)
        try repository.upsert(missingAsset)
        try FileManager.default.removeItem(at: missingURL)
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

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(model.assets.map(\.availability), [.online, .missing])
        XCTAssertEqual(try repository.asset(id: onlineAsset.id).availability, .online)
        XCTAssertEqual(try repository.asset(id: missingAsset.id).availability, .missing)
    }

    @MainActor
    func testRefreshVisibleAvailabilityWithWorkerEnqueuesManagedBatchSourceScan() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = makeAsset(id: "source-first", size: 1)
        let second = makeAsset(id: "source-second", size: 2)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "worker-visible-availability",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(try transport.commands(), [
            .refreshAvailabilityBatch(assetIDs: [first.id, second.id])
        ])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.kind), [.sourceScan])
        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.kind), [])
        XCTAssertEqual(model.visibleWorkActivity?.title, "Refresh sources")
        XCTAssertEqual(model.visibleWorkActivity?.completedUnitCount, 0)
        XCTAssertEqual(model.visibleWorkActivity?.totalUnitCount, 2)
        XCTAssertEqual(model.assets.map(\.availability), [.online, .online])

        try repository.updateAvailability(assetID: first.id, availability: .missing)
        try repository.updateAvailability(assetID: second.id, availability: .stale)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 2,
            detail: "Checked 1 of 2 sources"
        )))
        try await waitForVisibleWorkDetail("Checked 1 of 2 sources", in: model)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "checked 2 sources"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.assets.map(\.availability), [.missing, .stale])
    }

    func testCanRefreshVisibleAvailabilityRequiresCatalogAndLoadedAssets() throws {
        let (model, _, _) = try makeModelWithPreviewCache(named: "visible-availability-enabled")

        XCTAssertTrue(model.canRefreshVisibleAssetAvailability)

        model.assets = []
        XCTAssertFalse(model.canRefreshVisibleAssetAvailability)

        let localAsset = makeAsset(id: "local-only", size: 1)
        let localOnlyModel = AppModel(sidebarSections: [], selectedView: .grid, assets: [localAsset])

        XCTAssertFalse(localOnlyModel.canRefreshVisibleAssetAvailability)
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

    func testPreviewCompletionRefillsPendingPreviewRecoveryBatch() throws {
        let directory = try makeTemporaryDirectory(named: "pending-preview-refill")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<201).map { index in
            makeAsset(id: "asset-\(index)", path: "/Photos/asset-\(index).jpg", rating: 0)
        }
        try repository.upsert(assets)
        for asset in assets {
            try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-200-grid")

        XCTAssertEqual(model.backgroundWorkQueue.items.count, 200)
        XCTAssertNil(model.backgroundWorkQueue.item(id: refillItemID))
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: assets[0].id, level: .grid)])

        try repository.markPreviewGenerated(assetID: assets[0].id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview for asset-0"
        )))

        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: assets[0].id, level: .grid),
            .generatePreview(assetID: assets[1].id, level: .grid)
        ], in: transport))
        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
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

    func testRequestSelectedAssetEvaluationsDispatchesDefaultLocalProviders() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-selected-evaluations",
            workerSupervisor: supervisor
        )

        try model.requestSelectedAssetEvaluations()

        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: asset.id, provider: "local-image-metrics")
        ])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-image-metrics"),
            message: "completed local-image-metrics"
        )))

        XCTAssertTrue(waitForCommands([
            .runEvaluation(assetID: asset.id, provider: "local-image-metrics"),
            .runEvaluation(assetID: asset.id, provider: "apple-vision")
        ], in: transport))
    }

    func testRequestVisibleAssetEvaluationsDispatchesForLoadedAssets() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [first, second],
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestVisibleAssetEvaluations)

        try model.requestVisibleAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(first.id.rawValue)-local-image-metrics"),
            WorkSessionID(rawValue: "evaluation-\(second.id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: first.id, provider: "local-image-metrics")
        ])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(first.id.rawValue)-local-image-metrics"),
            message: "completed local-image-metrics"
        )))
        XCTAssertTrue(waitForCommands([
            .runEvaluation(assetID: first.id, provider: "local-image-metrics"),
            .runEvaluation(assetID: second.id, provider: "local-image-metrics")
        ], in: transport))
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

    func testCanRequestVisibleAssetEvaluationsRequiresLoadedAssetsAndWorker() {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "visible", size: 1)

        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [asset]).canRequestVisibleAssetEvaluations)
        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [], workerSupervisor: supervisor).canRequestVisibleAssetEvaluations)
        XCTAssertTrue(AppModel(sidebarSections: [], selectedView: .grid, assets: [asset], workerSupervisor: supervisor).canRequestVisibleAssetEvaluations)
    }

    func testSelectedEvaluationSignalsLoadFromCatalog() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "selected-signals")
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .exposure,
            value: .score(0.72),
            confidence: 0.9,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "average-preview-metrics", version: "1", settingsHash: "default")
        )
        try repository.recordEvaluationSignals([signal])

        XCTAssertEqual(model.selectedEvaluationSignals, [signal])
    }

    @MainActor
    func testEvaluationCompletionInvalidatesSelectedEvaluationSignals() async throws {
        let directory = try makeTemporaryDirectory(named: "evaluation-completion-signals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: directory.appendingPathComponent("asset.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .exposure,
            value: .score(0.42),
            confidence: 0.9,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "average-preview-metrics", version: "1", settingsHash: "default")
        )

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-image-metrics"),
            message: "evaluated \(asset.id.rawValue) with local-image-metrics"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(model.selectedEvaluationSignals, [signal])
    }

    @MainActor
    func testEvaluationCompletionRefreshesSignalSidebarRows() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "evaluation-sidebar-refresh", path: "/Photos/evaluation-sidebar-refresh.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "evaluation-sidebar-refresh",
            assets: [asset],
            workerSupervisor: supervisor
        )
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .faceQuality,
            value: .score(0.82),
            confidence: 0.82,
            provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        )

        XCTAssertNil(model.sidebarSections.first { $0.title == "AI" })

        try model.requestEvaluation(assetID: asset.id, provider: "apple-vision")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-apple-vision"),
            message: "evaluated \(asset.id.rawValue) with apple-vision"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "AI" }?.rowTitles, ["Faces"])
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
    func testWorkerImportProgressRefreshesVisibleBackgroundWork() async throws {
        let directory = try makeTemporaryDirectory(named: "worker-import-progress-refresh")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos"
        )))

        try await waitForVisibleWorkDetail("Cataloged 3 photos", in: model)
        XCTAssertEqual(model.visibleWorkActivity?.completedUnitCount, 3)
        XCTAssertEqual(model.visibleWorkActivity?.totalUnitCount, 8)
    }

    @MainActor
    func testVisibleImportActivityUsesWorkerImportProgress() async throws {
        let directory = try makeTemporaryDirectory(named: "visible-import-progress")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        XCTAssertEqual(model.visibleImportActivity?.detail, "Importing from photos")

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos"
        )))

        try await waitForVisibleWorkDetail("Cataloged 3 photos", in: model)
        let activity = try XCTUnwrap(model.visibleImportActivity)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.detail, "Cataloged 3 photos")
        XCTAssertEqual(activity.completedUnitCount, 3)
        XCTAssertEqual(activity.totalUnitCount, 8)
        XCTAssertTrue(activity.showsProgress)
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
            workerSupervisor: supervisor,
            sourceIsPresent: true
        )

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .medium)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-\(asset.id.rawValue)-medium",
            "preview-\(asset.id.rawValue)-large"
        ])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium"),
            message: "generated medium preview"
        )))

        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: asset.id, level: .medium),
            .generatePreview(assetID: asset.id, level: .large)
        ], in: transport))
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

    func testVisibleLoupePreviewUsesCachedPreviewWhenOriginalIsMissing() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "loupe-progressive-missing-original",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(model.selectedAsset?.availability, .missing)
        XCTAssertEqual(model.loupePreviewURL(for: asset.id), previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testVisibleComparePreviewsRequestMediumForCompareAssetsBeforeLarge() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let (model, _, first, _) = try makeComparePreviewModel(
            named: "compare-progressive-previews",
            workerSupervisor: supervisor
        )

        try model.requestVisibleComparePreviews()

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-first-medium",
            "preview-second-medium"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: first.id, level: .medium)
        ])
    }

    func testVisibleComparePreviewsPromoteSelectedAssetToLargeWhenMediumIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let (model, previewCache, first, _) = try makeComparePreviewModel(
            named: "compare-progressive-selected-large",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: first.id, level: .medium)))

        try model.requestVisibleComparePreviews()

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-first-large",
            "preview-second-medium"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: first.id, level: .large)
        ])
    }

    @MainActor
    func testComparePreviewRequestIDChangesWhenSelectedPreviewGenerationChanges() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, first, _) = try makeComparePreviewModel(
            named: "compare-request-id-preview-generation",
            workerSupervisor: supervisor
        )
        let initialRequestID = ComparePreviewRequestID.make(for: model)

        try model.requestPreview(assetID: first.id, level: .medium)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: first.id, level: .medium)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(first.id.rawValue)-medium"),
            message: "generated medium preview"
        )))

        try await waitForPreviewCacheGeneration(1, for: first.id, in: model)
        XCTAssertNotEqual(ComparePreviewRequestID.make(for: model), initialRequestID)
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

    func testVisibleGridPreviewDoesNotDispatchForKnownUnavailableOriginals() throws {
        for availability in [SourceAvailability.offline, .missing] {
            let transport = RecordingWorkerTransport()
            let supervisor = WorkerSupervisor(
                queue: BackgroundWorkQueue(maxRunningCount: 1),
                transport: transport
            )
            let directory = try makeTemporaryDirectory(named: "grid-known-\(availability.rawValue)")
            let asset = Asset(
                id: AssetID(rawValue: "known-\(availability.rawValue)"),
                originalURL: directory.appendingPathComponent("unavailable.jpg"),
                volumeIdentifier: "local",
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: availability,
                metadata: AssetMetadata()
            )
            let (model, _) = try makeModelWithCatalogAssets(
                named: "grid-known-\(availability.rawValue)",
                assets: [asset],
                workerSupervisor: supervisor
            )

            try model.requestVisibleGridPreview(assetID: asset.id)

            XCTAssertEqual(try transport.commands(), [], "unexpected grid preview command for \(availability.rawValue) asset")
            XCTAssertEqual(model.backgroundWorkQueue.items, [], "unexpected grid preview work for \(availability.rawValue) asset")
        }
    }

    @MainActor
    func testPreviewCompletionInvalidatesPreviewCacheGeneration() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-completion-invalidation")
        let source = directory.appendingPathComponent("source.jpg")
        try writeTestPNG(to: source)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let otherAsset = Asset(
            id: AssetID(rawValue: "asset-2"),
            originalURL: directory.appendingPathComponent("other.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(asset)
        try catalog.repository.upsert(otherAsset)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        try model.requestVisibleGridPreview(assetID: asset.id)
        let previewURL = catalog.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try writePreviewPlaceholder(to: previewURL)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"),
            message: "generated grid preview for \(asset.id.rawValue)"
        )))

        try await waitForPreviewCacheGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(model.previewCacheGeneration(for: otherAsset.id), 0)
        XCTAssertEqual(model.gridPreviewURL(for: asset.id), previewURL)
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
    func testBeginImportFolderWithWorkerEnqueuesManagedImportAndReloadsOnCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-folder-import")
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

        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        XCTAssertNil(model.activeWork)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(importItem.kind, .ingest)
        XCTAssertEqual(importItem.title, "Import photos")
        XCTAssertEqual(importItem.detail, "Importing from photos")
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder)])

        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .grid))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder),
            .generatePreview(assetID: importedAsset.id, level: .grid)
        ])
    }

    @MainActor
    func testFailedWorkerImportRecordsFailedActivityForReload() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-failure-activity")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: importItem.id,
            message: "disk read failed"
        )))

        try await waitForActivityStatus(.failed, in: model)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.id, importItem.id.rawValue)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from photos: disk read failed")
        XCTAssertEqual(activity.failureCount, 1)

        let reloaded = try AppModel.load(catalog: catalog)
        XCTAssertEqual(reloaded.recentWork.first?.id, importItem.id.rawValue)
        XCTAssertEqual(reloaded.recentWork.first?.status, .failed)
        XCTAssertEqual(reloaded.recentWork.first?.detail, "Import failed from photos: disk read failed")
    }

    @MainActor
    func testCancellingWorkerImportCancelsManagedBackgroundWork() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-cancel")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        XCTAssertTrue(model.isImporting)

        model.cancelBackgroundWork()

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.backgroundWorkQueue.items.first?.status, .cancelled)
        XCTAssertEqual(model.statusMessage, "Cancelled import")
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder),
            .cancelAll
        ])

        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.id, model.backgroundWorkQueue.items.first?.id.rawValue)
        XCTAssertEqual(activity.status, .cancelled)
        XCTAssertEqual(activity.detail, "Cancelled import from photos")

        let reloaded = try AppModel.load(catalog: catalog)
        XCTAssertEqual(reloaded.recentWork.first?.id, activity.id)
        XCTAssertEqual(reloaded.recentWork.first?.status, .cancelled)
        XCTAssertEqual(reloaded.recentWork.first?.detail, "Cancelled import from photos")
    }

    @MainActor
    func testCancellingVisibleWorkerImportPreservesOtherBackgroundWork() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-targeted-cancel")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        let previewItem = BackgroundWorkItem.testItem(id: "preview")
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        try supervisor.enqueue(previewItem, command: previewCommand)

        model.cancelImportWork()

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: importItem.id)?.status, .cancelled)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: previewItem.id)?.status, .running)
        XCTAssertEqual(model.statusMessage, "Cancelled import")
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder),
            .cancelAll,
            previewCommand
        ])
        XCTAssertEqual(model.recentWork.first?.id, importItem.id.rawValue)
        XCTAssertEqual(model.recentWork.first?.status, .cancelled)
        XCTAssertEqual(model.recentWork.first?.detail, "Cancelled import from photos")
    }

    @MainActor
    func testBeginImportCardWithWorkerEnqueuesManagedCopyAndRecordsDestination() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-import")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sourceImage = source.appendingPathComponent("one.png")
        try writeTestPNG(to: sourceImage)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportCard(source: source, destinationRoot: destinationRoot)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(importItem.kind, .ingest)
        XCTAssertEqual(importItem.detail, "Importing from DCIM to Library")
        XCTAssertEqual(try transport.commands(), [.importCard(source: source, destinationRoot: destinationRoot)])

        let destinationImage = destinationRoot.appendingPathComponent("one.png")
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-card-imported"),
            originalURL: destinationImage,
            volumeIdentifier: "Library",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from DCIM to Library",
            importedAssetIDs: [importedAsset.id]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.originalURL), [destinationImage])
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertEqual(model.recentWork.first?.detail, "Imported 1 photo from DCIM to Library")
        XCTAssertFalse(model.isImporting)
    }

    @MainActor
    func testBackgroundImportWithMissingWorkerExecutableGeneratesPreviewLocally() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import-missing-worker")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let model = try AppCatalog.loadModel(
            paths: paths,
            workerExecutableURL: directory.appendingPathComponent("missing-worker")
        )

        let result = try await model.importFolderInBackground(photoFolder)

        let assetID = result.importedAssets[0].id
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: assetID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertFalse(model.canRequestSelectedAssetEvaluation)
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
    func testBackgroundCardImportCopiesIntoDestinationAndRecordsActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-card-import")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destination = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let image = source.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: image)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importCardInBackground(source: source, destinationRoot: destination)

        let destinationImage = destination.appendingPathComponent("one.png")
        let destinationSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: destinationImage)
        let assetID = result.importedAssets[0].id
        XCTAssertEqual(result.importedAssets.map(\.originalURL), [destinationImage])
        XCTAssertEqual(model.assets.map(\.originalURL), [destinationImage])
        XCTAssertEqual(model.selectedAssetID, assetID)
        XCTAssertEqual(try catalog.repository.asset(id: assetID).metadata, metadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceSidecar.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationImage.path))
        XCTAssertEqual(try Data(contentsOf: destinationSidecar), sidecarData)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: assetID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.detail, "Imported 1 photo from DCIM to Library")
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
        XCTAssertFalse(model.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Imported 1 photo from photos")
        })

        let reloaded = try AppModel.load(catalog: catalog)
        let activity = try XCTUnwrap(reloaded.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.title, "Import photos")
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(activity.completedUnitCount, 1)
        XCTAssertEqual(activity.totalUnitCount, 1)
        XCTAssertEqual(activity.failureCount, 0)
        XCTAssertFalse(reloaded.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Imported 1 photo from photos")
        })
        XCTAssertEqual(reloaded.sidebarSections.first { $0.title == "Work" }?.rowTitles.first, "Imported 1 photo from photos")
        let session = try catalog.repository.session(id: WorkSessionID(rawValue: activity.id))
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        let outputSet = try catalog.repository.assetSet(id: outputSetID)
        if case .manual(let assetIDs) = outputSet.membership {
            XCTAssertEqual(assetIDs, [reloaded.assets[0].id])
        } else {
            XCTFail("import output set should be manual")
        }

        let row = try XCTUnwrap(reloaded.sidebarSections.first { $0.title == "Work" }?.rows.first)
        try reloaded.selectSidebarRow(row)

        XCTAssertEqual(reloaded.selectedAssetSetID, outputSetID)
        XCTAssertEqual(reloaded.assets.map(\.originalURL), [image])
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
    func testCancellingActiveCardImportRecordsCancelledActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-cancel-card-import")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destination = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _ in
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

        model.beginImportCard(source: source, destinationRoot: destination)
        XCTAssertEqual(model.activeWork?.detail, "Importing from DCIM to Library")

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)

        XCTAssertNil(model.activeWork)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .cancelled)
        XCTAssertEqual(activity.detail, "Cancelled import from DCIM to Library")
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

    private func fileFingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
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

    private func makeModelWithSeededCatalog(named name: String, count: Int) throws -> AppModel {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: count, repository: repository)
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
        return try AppModel.load(catalog: catalog)
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
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        availability: SourceAvailability = .online,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: availability,
            metadata: AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords),
            technicalMetadata: technicalMetadata
        )
    }

    private func makeModelWithPreviewCache(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil,
        pendingPreviewLevel: PreviewLevel? = nil,
        sourceIsPresent: Bool = false
    ) throws -> (AppModel, PreviewCache, Asset) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let originalURL = sourceIsPresent
            ? directory.appendingPathComponent("\(name).jpg")
            : URL(fileURLWithPath: "/Photos/\(name).jpg")
        if sourceIsPresent {
            try Data("original".utf8).write(to: originalURL)
        }
        let originalFingerprint = sourceIsPresent
            ? try fileFingerprint(for: originalURL)
            : FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10))
        let asset = Asset(
            id: AssetID(rawValue: name),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: originalFingerprint,
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

    private func makeModelWithXMPConflict(
        named name: String,
        catalogMetadata: AssetMetadata,
        sidecarMetadata: AssetMetadata
    ) throws -> (AppModel, CatalogRepository, Asset, URL, URL) {
        let directory = try makeTemporaryDirectory(named: name)
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: name),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: catalogMetadata
        )
        try repository.upsert(asset)
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        try sidecarData.write(to: sidecarURL)
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: sidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            lastSyncedFingerprint: "old"
        )
        try repository.recordMetadataSyncConflict(conflict)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        return (try AppModel.load(catalog: catalog), repository, asset, originalURL, sidecarURL)
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset],
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, CatalogRepository) {
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: name,
            assets: assets,
            workerSupervisor: workerSupervisor
        )
        return (result.model, result.repository)
    }

    private func makeModelWithCatalogAssetsAndPreviewCache(
        named name: String,
        assets: [Asset],
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, previewCache)
    }

    private func makeComparePreviewModel(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, PreviewCache, Asset, Asset) {
        let directory = try makeTemporaryDirectory(named: name)
        let firstURL = directory.appendingPathComponent("first.jpg")
        let secondURL = directory.appendingPathComponent("second.jpg")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)
        let first = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: firstURL,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: firstURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "second"),
            originalURL: secondURL,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: secondURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: name,
            assets: [first, second],
            workerSupervisor: workerSupervisor
        )
        return (result.model, result.previewCache, first, second)
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
    private func waitForBackgroundWorkStatus(
        _ status: WorkSessionStatus,
        itemID: WorkSessionID,
        in model: AppModel
    ) async throws {
        for _ in 0..<100 {
            if model.backgroundWorkQueue.item(id: itemID)?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for background work status \(status.rawValue)")
    }

    @MainActor
    private func waitForVisibleWorkDetail(_ detail: String, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.visibleWorkActivity?.detail == detail {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for visible work detail \(detail)")
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

    private func waitForCommands(
        _ expected: [WorkerCommand],
        in transport: RecordingWorkerTransport,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? transport.commands()) == expected {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return (try? transport.commands()) == expected
    }

    private func waitForBackgroundWorkItem(
        _ itemID: WorkSessionID,
        in model: AppModel,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.backgroundWorkQueue.item(id: itemID) != nil {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return model.backgroundWorkQueue.item(id: itemID) != nil
    }

    @MainActor
    private func waitForPreviewCacheGeneration(_ generation: Int, for assetID: AssetID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.previewCacheGeneration(for: assetID) == generation {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for preview cache generation \(generation)")
    }

    @MainActor
    private func waitForEvaluationSignalGeneration(_ generation: Int, for assetID: AssetID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.evaluationSignalGeneration(for: assetID) == generation {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for evaluation signal generation \(generation)")
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
