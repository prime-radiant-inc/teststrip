import XCTest
@testable import TeststripCore
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

    func testSelectedAssetPositionTextShowsFrameWithinLibrary() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let third = makeAsset(id: "third", size: 3)
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second, third])

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetPositionText, "Frame 2 of 3")
    }

    func testCullingProgressSummaryCountsVisibleDecisions() {
        let pick = makeAsset(id: "pick", path: "/Photos/pick.jpg", rating: 0, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 0, flag: .reject)
        let unreviewed = makeAsset(id: "unreviewed", path: "/Photos/unreviewed.jpg", rating: 0)
        let secondPick = makeAsset(id: "second-pick", path: "/Photos/second-pick.jpg", rating: 0, flag: .pick)
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [pick, reject, unreviewed, secondPick])

        model.select(unreviewed.id)

        XCTAssertEqual(
            model.cullingProgressSummary,
            CullingProgressSummary(
                selectedPosition: 3,
                positionText: "Frame 3 of 4",
                pickCount: 2,
                rejectCount: 1,
                totalCount: 4
            )
        )
        XCTAssertEqual(model.cullingProgressSummary.reviewedCount, 3)
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

    func testSelectingMetadataConflictSidebarRowLoadsConflictedAssets() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-conflict-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let conflicted = makeAsset(id: "conflicted", path: "/Photos/conflicted.jpg", rating: 0)
        let clean = makeAsset(id: "clean", path: "/Photos/clean.jpg", rating: 0)
        try repository.upsert([conflicted, clean])
        try repository.recordMetadataSyncConflict(MetadataSyncItem(
            assetID: conflicted.id,
            sidecarURL: conflicted.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        let syncSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sync" })
        XCTAssertEqual(syncSection.rowTitles, ["XMP Conflicts (1)"])

        try model.selectSidebarRow(try XCTUnwrap(syncSection.rows.first))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.metadataSyncConflictFilter)
        XCTAssertEqual(model.assets.map(\.id), [conflicted.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSelectingPendingMetadataSyncSidebarRowLoadsPendingAssets() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-pending-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let pending = makeAsset(id: "pending-xmp", path: "/Photos/pending.jpg", rating: 0)
        let clean = makeAsset(id: "clean-xmp", path: "/Photos/clean.jpg", rating: 0)
        try repository.upsert([pending, clean])
        try repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: pending.id,
            sidecarURL: pending.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        let syncSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sync" })
        XCTAssertEqual(syncSection.rowTitles, ["XMP Pending (1)"])

        try model.selectSidebarRow(try XCTUnwrap(syncSection.rows.first))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.metadataSyncPendingFilter)
        XCTAssertEqual(model.assets.map(\.id), [pending.id])
        XCTAssertEqual(model.totalAssetCount, 1)
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

    func testResolvingMetadataConflictRemovesAssetFromConflictFilter() throws {
        let catalogMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["catalog"])
        let sidecarMetadata = AssetMetadata(rating: 2, colorLabel: .red, flag: .reject, keywords: ["sidecar"])
        let (model, _, asset, _, _) = try makeModelWithXMPConflict(
            named: "resolve-conflict-filter",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )
        model.metadataSyncConflictFilter = true
        try model.reload()
        XCTAssertEqual(model.assets.map(\.id), [asset.id])

        try model.resolveSelectedMetadataConflictUsingCatalog()

        XCTAssertEqual(model.assets, [])
        XCTAssertEqual(model.totalAssetCount, 0)
        XCTAssertNil(model.sidebarSections.first { $0.title == "Sync" })
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
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "app-model-worker-xmp",
            assetID: "worker-xmp-target"
        )

        try model.setRatingForSelectedAsset(5)

        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [pending])
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appendingPathExtension("xmp").path))
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Writing XMP sidecar")
    }

    @MainActor
    func testCompletedWorkerMetadataSyncClearsPendingMetadataSync() async throws {
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "app-model-worker-xmp-complete",
            assetID: "worker-xmp-complete-target"
        )

        try model.setRatingForSelectedAsset(5)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: try repository.asset(id: asset.id).metadata).xmlData()
        try sidecarData.write(to: sidecarURL)
        try repository.markMetadataSynced(
            assetID: asset.id,
            sidecarURL: sidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "synced metadata for frame.cr2"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
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
    func testSelectingThroughAssetsCancelsStaleQueuedMetadataSyncChecks() async throws {
        let first = makeAsset(id: "stale-selection-xmp-first", size: 1)
        let second = makeAsset(id: "stale-selection-xmp-second", size: 2)
        let third = makeAsset(id: "stale-selection-xmp-third", size: 3)
        let fourth = makeAsset(id: "stale-selection-xmp-fourth", size: 4)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "stale-selection-worker-xmp-check",
            assets: [first, second, third, fourth],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        let runningItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        model.select(third.id)
        model.select(fourth.id)

        let queuedChecks = model.backgroundWorkQueue.queuedItems.filter { $0.title == "Check XMP" }
        XCTAssertEqual(queuedChecks.count, 1)
        XCTAssertTrue(queuedChecks[0].id.rawValue.hasPrefix("xmp-check-\(fourth.id.rawValue)-"))
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: second.id)])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: runningItemID,
            message: "metadata up to date for second.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: runningItemID, in: model)
        XCTAssertEqual(try transport.commands(), [
            .syncMetadata(assetID: second.id),
            .syncMetadata(assetID: fourth.id)
        ])

        let fourthItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: fourthItemID,
            message: "metadata up to date for fourth.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: fourthItemID, in: model)
        XCTAssertNil(model.visibleWorkActivity)
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

    @MainActor
    func testCompletedMetadataSyncRefreshesLoadedAssetMetadata() async throws {
        let first = makeAsset(id: "completed-xmp-refresh-first", size: 1)
        let second = makeAsset(id: "completed-xmp-refresh-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "completed-xmp-refresh",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["sidecar"])
        try repository.updateMetadata(assetID: second.id) { metadata in
            metadata = sidecarMetadata
        }

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "imported metadata for completed-xmp-refresh-second.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.selectedAsset?.metadata, sidecarMetadata)
        XCTAssertEqual(model.assets.first { $0.id == second.id }?.metadata, sidecarMetadata)
    }

    func testLoadQueuesPendingMetadataSyncWhenSupervisorConfigured() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let originalURL = photoFolder.appendingPathComponent("frame.cr2")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "pending-worker-xmp-target"),
            originalURL: originalURL,
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

    func testLoadSkipsPendingMetadataSyncForUnavailableOriginal() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp-offline")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let originalURL = photoFolder.appendingPathComponent("frame.cr2")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "pending-worker-xmp-offline"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .offline,
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
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }, [])
        XCTAssertEqual(try transport.commands(), [])
    }

    func testLoadBoundsPendingMetadataSyncRetries() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp-limit")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<205).map { index in
            Asset(
                id: AssetID(rawValue: "pending-worker-xmp-limit-\(index)"),
                originalURL: photoFolder.appendingPathComponent("frame-\(index).cr2"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata(rating: 4)
            )
        }
        try repository.upsert(assets)
        for asset in assets {
            try repository.recordMetadataSyncPending(MetadataSyncItem(
                assetID: asset.id,
                sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
                catalogGeneration: 1,
                lastSyncedFingerprint: nil
            ))
        }
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

        XCTAssertEqual(model.pendingMetadataSyncItems.count, 205)
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }.count, 200)
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
        let model = try makeModelWithSeededCatalog(named: "culling-next-page", count: 121)
        model.select(AssetID(rawValue: "asset-119"))

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-120"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-120"))
        XCTAssertFalse(model.hasMoreAssets)
    }

    func testCullingShortcutLoadsPreviousPageWhenMovingBeforeLoadedAssets() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-previous-page", count: 360)
        try model.loadMoreAssets()
        try model.loadMoreAssets()
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-120"))
        model.select(AssetID(rawValue: "asset-120"))

        try model.applyCullingShortcut(.previousPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-119"))
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

    func testLibraryStatusTextShowsPreviewGenerationAfterImportCompletes() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        model.statusMessage = "Imported 12 photos"

        model.enqueueBackgroundWork(BackgroundWorkItem.testItem(id: "preview-after-import"))

        XCTAssertEqual(model.libraryStatusText, "Imported 12 photos; generating previews")
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
        XCTAssertNil(model.backgroundWorkPauseNotice)

        model.pauseBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
        XCTAssertEqual(model.backgroundWorkPauseNotice, "Queue paused after current task")
        XCTAssertFalse(model.canPauseBackgroundWork)
        XCTAssertTrue(model.canResumeBackgroundWork)

        model.resumeBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
        XCTAssertNil(model.backgroundWorkPauseNotice)
        XCTAssertTrue(model.canPauseBackgroundWork)
        XCTAssertFalse(model.canResumeBackgroundWork)

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

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertEqual(model.libraryCountText, "Showing 120 of 501 photographs")
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

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertTrue(model.hasMoreAssets)

        try model.loadMoreAssets()

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-239"))
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 240 of 501 photographs")
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

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 100_000)

        for _ in 0..<20 {
            try model.loadMoreAssets()
        }

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-2280"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-2519"))
        XCTAssertEqual(model.totalAssetCount, 100_000)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 2281-2520 of 100000 photographs")
    }

    func testLoadPreviousAssetsKeepsLoadedAssetWindowBounded() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-previous-window")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 600, repository: repository)
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

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-120"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-359"))
        XCTAssertEqual(model.totalAssetCount, 600)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 121-360 of 600 photographs")
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

    func testLoadExposesReviewQueuesAndSelectingQueueAppliesFilter() throws {
        let pick = makeAsset(id: "pick", path: "/Photos/Job/pick.jpg", rating: 4, flag: .pick, keywords: ["tagged"])
        let reject = makeAsset(id: "reject", path: "/Photos/Job/reject.jpg", rating: 1, flag: .reject, keywords: ["tagged"])
        let fiveStar = makeAsset(id: "five-star", path: "/Photos/Job/five-star.jpg", rating: 5, keywords: ["tagged"])
        let unreviewed = makeAsset(id: "unreviewed", path: "/Photos/Job/unreviewed.jpg", rating: 0, keywords: ["tagged"])
        let needsKeywords = makeAsset(id: "needs-keywords", path: "/Photos/Job/needs-keywords.jpg", rating: 3)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-review-queue-sidebar",
            assets: [pick, reject, fiveStar, unreviewed, needsKeywords]
        )

        let reviewSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Review" })
        XCTAssertEqual(reviewSection.rowTitles, ["Picks", "Rejects", "5 Stars", "Needs Keywords"])

        let picksRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Picks" })
        try model.selectSidebarRow(picksRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let rejectsRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Rejects" })
        try model.selectSidebarRow(rejectsRow)

        XCTAssertEqual(model.flagFilter, .reject)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [reject.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let fiveStarsRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "5 Stars" })
        try model.selectSidebarRow(fiveStarsRow)

        XCTAssertNil(model.flagFilter)
        XCTAssertEqual(model.minimumRatingFilter, 5)
        XCTAssertEqual(model.assets.map(\.id), [fiveStar.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let needsKeywordsRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Needs Keywords" })
        try model.selectSidebarRow(needsKeywordsRow)

        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertTrue(model.needsKeywordsFilter)
        XCTAssertEqual(model.assets.map(\.id), [needsKeywords.id])
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

    func testLoadExposesSourceAvailabilityRowsInSidebarAndSelectingRowAppliesFilter() throws {
        let online = makeAsset(id: "online", path: "/Volumes/NAS/Job/online.cr2", rating: 4)
        let offline = makeAsset(id: "offline", path: "/Volumes/NAS/Job/offline.cr2", rating: 4, availability: .offline)
        let firstMissing = makeAsset(id: "missing-a", path: "/Volumes/NAS/Job/missing-a.cr2", rating: 4, availability: .missing)
        let secondMissing = makeAsset(id: "missing-b", path: "/Volumes/NAS/Job/missing-b.cr2", rating: 4, availability: .missing)
        let moved = makeAsset(id: "moved", path: "/Volumes/NAS/Job/moved.cr2", rating: 4, availability: .moved)
        let stale = makeAsset(id: "stale", path: "/Volumes/NAS/Job/stale.cr2", rating: 4, availability: .stale)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-source-availability-sidebar",
            assets: [online, offline, firstMissing, secondMissing, moved, stale]
        )

        let sourceSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sources" })
        XCTAssertEqual(sourceSection.rowTitles, [
            "Offline Originals (1)",
            "Missing Originals (2)",
            "Moved Originals (1)",
            "Stale Originals (1)"
        ])
        let missingRow = try XCTUnwrap(sourceSection.rows.first { $0.title == "Missing Originals (2)" })

        try model.selectSidebarRow(missingRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.availabilityFilter, .missing)
        XCTAssertEqual(model.assets.map(\.id), [firstMissing.id, secondMissing.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testReconnectSourceRootRefreshesLoadedAssetsAndSourceSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
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
        let model = try AppModel.load(catalog: catalog)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Sources" }?.rowTitles, ["Missing Originals (1)"])

        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [newOriginalURL])
        XCTAssertEqual(model.assets.map(\.availability), [.online])
        XCTAssertNil(model.sidebarSections.first { $0.title == "Sources" })
        XCTAssertEqual(model.statusMessage, "Reconnected 1 source")
    }

    func testReconnectSourceRootEnqueuesPendingPreviewForRestoredOriginal() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect-preview")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-preview"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        let pendingPreview = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(pendingPreview)
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

        XCTAssertEqual(try transport.commands(), [])
        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .grid)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [pendingPreview])
    }

    func testSuggestedReconnectOldRootUsesVisibleUnavailableAssets() {
        let online = makeAsset(id: "online", path: "/Volumes/Current/Job/online.jpg", rating: 0)
        let firstMissing = makeAsset(id: "missing-a", path: "/Volumes/Archive/Job/a.jpg", rating: 0, availability: .missing)
        let secondMissing = makeAsset(id: "missing-b", path: "/Volumes/Archive/Job/Nested/b.jpg", rating: 0, availability: .offline)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [online, firstMissing, secondMissing])

        XCTAssertEqual(model.suggestedReconnectOldRootPath, "/Volumes/Archive/Job")
    }

    func testSuggestedReconnectOldRootUsesCatalogSourceRootsBeyondLoadedWindow() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-root-history")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 500, repository: repository)
        let missingArchiveAsset = makeAsset(
            id: "archive-missing",
            path: "/Volumes/Archive/Job/Nested/missing.jpg",
            rating: 0,
            availability: .missing
        )
        try repository.upsert(missingArchiveAsset)
        try repository.recordSourceRoot(URL(fileURLWithPath: "/Volumes/Archive/Job", isDirectory: true))
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

        XCTAssertFalse(model.assets.contains { $0.id == missingArchiveAsset.id })
        XCTAssertEqual(model.suggestedReconnectOldRootPath, "/Volumes/Archive/Job")
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

    func testSelectingCullingWorkSessionReopensLoupeView() throws {
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
        XCTAssertEqual(model.selectedView, .loupe)
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

    func testActiveLibraryFilterChipsSummarizeCurrentFilters() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.librarySearchText = " ceremony "
        model.keywordFilterText = "portfolio"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        model.colorLabelFilter = .green
        model.cameraFilterText = "Sony"
        model.minimumISOFilter = 800

        XCTAssertEqual(model.activeLibraryFilterChips, [
            "Search: ceremony",
            "Keyword: portfolio",
            "Rating >= 4",
            "Pick",
            "Green Label",
            "Camera: Sony",
            "ISO >= 800"
        ])
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
        XCTAssertEqual(model.selectedView, .loupe)
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
        XCTAssertEqual(model.selectedView, .loupe)
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

    func testReimportFolderReportsNoNewPhotos() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-reimport")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let firstResult = try model.importFolder(photoFolder)
        let secondResult = try model.importFolder(photoFolder)

        XCTAssertEqual(firstResult.newAssetCount, 1)
        XCTAssertEqual(firstResult.existingAssetCount, 0)
        XCTAssertEqual(secondResult.importedAssets.map(\.id), firstResult.importedAssets.map(\.id))
        XCTAssertEqual(secondResult.newAssetCount, 0)
        XCTAssertEqual(secondResult.existingAssetCount, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.statusMessage, "No new photos found")
        XCTAssertEqual(model.recentWork.first?.detail, "No new photos found in photos")
        XCTAssertNil(model.errorMessage)
    }

    func testImportFolderReportsNoSupportedPhotosWhenFolderIsEmpty() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-empty-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: photoFolder.appendingPathComponent("notes.txt"))
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try model.importFolder(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 0)
        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertEqual(model.totalAssetCount, 0)
        XCTAssertEqual(model.statusMessage, "No supported photos found")
        XCTAssertEqual(model.recentWork.first?.detail, "No supported photos found in photos")
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
        for index in 0..<120 {
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
        XCTAssertEqual(model.totalAssetCount, 121)
        XCTAssertEqual(model.libraryCountText, "Showing 121-121 of 121 photographs")
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

    func testSelectedPreviewURLUsesSelectedAssetLoupePreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "selected-preview")
        let largePreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large))
        try writePreviewPlaceholder(to: largePreview)

        model.select(asset.id)

        XCTAssertEqual(model.selectedPreviewURL, largePreview)
    }

    func testGridPreviewURLFallsBackToMicroPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "grid-micro")
        let microPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
        try writePreviewPlaceholder(to: microPreview)

        XCTAssertEqual(model.gridPreviewURL(for: asset.id), microPreview)
    }

    func testOriginalAccessURLReturnsOnlineOriginalOnlyWhenRequested() throws {
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "explicit-original-access",
            sourceIsPresent: true
        )

        XCTAssertNil(model.loupePreviewURL(for: asset.id))
        XCTAssertEqual(try model.originalAccessURL(for: asset.id), asset.originalURL)
    }

    func testOriginalAccessURLMarksUnavailableOriginalMissing() throws {
        let (model, _, asset) = try makeModelWithPreviewCache(named: "explicit-original-missing")

        XCTAssertNil(try model.originalAccessURL(for: asset.id))
        XCTAssertEqual(model.selectedAsset?.availability, .missing)
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

    func testRefreshVisibleAvailabilityRefreshesSourceAvailabilitySidebarCounts() throws {
        let directory = try makeTemporaryDirectory(named: "visible-availability-sidebar")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let imageURL = photosDirectory.appendingPathComponent("online.jpg")
        try Data("online".utf8).write(to: imageURL)
        let asset = Asset(
            id: AssetID(rawValue: "online"),
            originalURL: imageURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: imageURL),
            availability: .missing,
            metadata: AssetMetadata()
        )
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
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
        let model = try AppModel.load(catalog: catalog)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Sources" }?.rowTitles, ["Missing Originals (1)"])

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(model.assets.map(\.availability), [.online])
        XCTAssertNil(model.sidebarSections.first { $0.title == "Sources" })
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
            detail: "Checked 1 of 2 sources",
            catalogedAssetIDs: []
        )))
        try await waitForVisibleWorkDetail("Checked 1 of 2 sources", in: model)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "checked 2 sources"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.assets.map(\.availability), [.missing, .stale])
    }

    @MainActor
    func testCompletedSourceScanEnqueuesPendingPreviewWhenOriginalComesOnline() async throws {
        let directory = try makeTemporaryDirectory(named: "source-scan-recovers-preview")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(
            id: "restored-source",
            path: "/Volumes/NAS/Job/restored-source.cr2",
            rating: 0,
            availability: .offline
        )
        let pendingPreview = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(pendingPreview)
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

        XCTAssertEqual(try transport.commands(), [])
        try model.refreshVisibleAssetAvailability()
        XCTAssertEqual(try transport.commands(), [
            .refreshAvailabilityBatch(assetIDs: [asset.id])
        ])
        let scanItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)

        try repository.updateAvailability(assetID: asset.id, availability: .online)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: scanItemID,
            message: "checked 1 source"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: scanItemID, in: model)
        XCTAssertEqual(model.assets.first { $0.id == asset.id }?.availability, .online)
        XCTAssertTrue(waitForCommands([
            .refreshAvailabilityBatch(assetIDs: [asset.id]),
            .generatePreview(assetID: asset.id, level: .grid)
        ], in: transport), commandDescription(transport))
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [pendingPreview])
    }

    @MainActor
    func testRefreshVisibleAvailabilityWithWorkerBatchesLargeSourceScansByVolume() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        func sourceAsset(id: String, volume: String) -> Asset {
            Asset(
                id: AssetID(rawValue: id),
                originalURL: URL(fileURLWithPath: "/Volumes/\(volume)/Photos/\(id).jpg"),
                volumeIdentifier: volume,
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
        let nasAssets = (0...AppModel.sourceAvailabilityBatchSize).map {
            sourceAsset(id: "nas-\($0)", volume: "NAS")
        }
        let archiveAsset = sourceAsset(id: "archive-0", volume: "Archive")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "worker-visible-availability-batched",
            assets: [nasAssets[0], archiveAsset] + Array(nasAssets.dropFirst()),
            workerSupervisor: supervisor
        )

        try model.refreshVisibleAssetAvailability()

        let firstBatch = Array(nasAssets.prefix(AppModel.sourceAvailabilityBatchSize).map(\.id))
        let secondBatch = Array(nasAssets.dropFirst(AppModel.sourceAvailabilityBatchSize).map(\.id))
        let archiveBatch = [archiveAsset.id]
        let expectedFirstCommands: [WorkerCommand] = [
            .refreshAvailabilityBatch(assetIDs: firstBatch)
        ]
        XCTAssertTrue(waitForCommands(expectedFirstCommands, in: transport), commandDescription(transport))
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.first?.totalUnitCount, AppModel.sourceAvailabilityBatchSize)
        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.totalUnitCount), [1, 1])

        let firstItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "checked \(AppModel.sourceAvailabilityBatchSize) sources"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: firstItemID, in: model)

        let expectedSecondCommands: [WorkerCommand] = [
            .refreshAvailabilityBatch(assetIDs: firstBatch),
            .refreshAvailabilityBatch(assetIDs: secondBatch)
        ]
        XCTAssertTrue(waitForCommands(expectedSecondCommands, in: transport), commandDescription(transport))
        let secondItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: secondItemID,
            message: "checked 1 source"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: secondItemID, in: model)

        let expectedThirdCommands: [WorkerCommand] = [
            .refreshAvailabilityBatch(assetIDs: firstBatch),
            .refreshAvailabilityBatch(assetIDs: secondBatch),
            .refreshAvailabilityBatch(assetIDs: archiveBatch)
        ]
        XCTAssertTrue(waitForCommands(expectedThirdCommands, in: transport), commandDescription(transport))
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

    func testRequestMissingPreviewRecordsDurablePendingPreviewBeforeDispatch() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "durable-preview", size: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "request-preview-durable-pending",
            assets: [asset],
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .large)
        ])
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .large)])
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

    func testLoadSkipsAutomaticPreviewRetryAfterRepeatedFailures() throws {
        let directory = try makeTemporaryDirectory(named: "pending-preview-retry-exhausted")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "retry-exhausted", size: 1)
        let item = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(item)
        for attempt in 1...3 {
            try repository.recordPreviewGenerationFailure(
                assetID: asset.id,
                level: .grid,
                errorMessage: "render failed \(attempt)"
            )
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

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [item])
        let failureState = try XCTUnwrap(model.previewGenerationQueueStates.first)
        XCTAssertEqual(failureState.item, item)
        XCTAssertEqual(failureState.attemptCount, 3)
        XCTAssertEqual(failureState.lastErrorMessage, "render failed 3")
    }

    func testRetrySelectedPreviewGenerationFailureDispatchesWorkerPreview() throws {
        let directory = try makeTemporaryDirectory(named: "selected-preview-retry")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "retry-selected-preview", size: 1)
        try repository.upsert(asset)
        for attempt in 1...3 {
            try repository.recordPreviewGenerationFailure(
                assetID: asset.id,
                level: .grid,
                errorMessage: "render failed \(attempt)"
            )
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

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertTrue(model.canRetrySelectedPreviewGenerationFailures)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.attemptCount, 3)

        try model.retrySelectedPreviewGenerationFailures()

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .grid)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.attemptCount, 3)
    }

    func testLoadSkipsAutomaticPreviewRecoveryForOfflineOriginal() throws {
        let directory = try makeTemporaryDirectory(named: "pending-preview-offline-source")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(
            id: "offline-source",
            path: "/Volumes/NAS/Job/offline-source.cr2",
            rating: 0,
            availability: .offline
        )
        let item = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(item)
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

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [item])
        let state = try XCTUnwrap(model.previewGenerationQueueStates.first)
        XCTAssertEqual(state.item, item)
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastErrorMessage)
    }

    func testLoadExposesSelectedPreviewGenerationFailures() throws {
        let directory = try makeTemporaryDirectory(named: "selected-preview-failure")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let failedAsset = makeAsset(id: "failed", path: "/Photos/failed.jpg", rating: 0)
        let pendingAsset = makeAsset(id: "pending", path: "/Photos/pending.jpg", rating: 0)
        try repository.upsert([failedAsset, pendingAsset])
        try repository.recordPreviewGenerationFailure(
            assetID: failedAsset.id,
            level: .grid,
            errorMessage: "could not render preview"
        )
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: pendingAsset.id, level: .grid))
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

        XCTAssertEqual(model.selectedAssetID, failedAsset.id)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.map(\.item), [
            PreviewGenerationItem(assetID: failedAsset.id, level: .grid)
        ])
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.attemptCount, 1)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.lastErrorMessage, "could not render preview")

        model.select(pendingAsset.id)

        XCTAssertEqual(model.selectedPreviewGenerationFailures, [])
    }

    func testPreviewCompletionRefillsPendingPreviewRecoveryBatch() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill",
            assetCount: 41,
            workerSupervisor: supervisor
        )
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        XCTAssertEqual(model.backgroundWorkQueue.items.count, 40)
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

    @MainActor
    func testCompletedPreviewGenerationKeepsOnlyLatestCompletedPreviewInBackgroundQueue() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = makeAsset(id: "completed-preview-first", size: 1)
        let second = makeAsset(id: "completed-preview-second", size: 2)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "completed-preview-pruned",
            assets: [first, second],
            workerSupervisor: supervisor
        )
        let firstItemID = WorkSessionID(rawValue: "preview-\(first.id.rawValue)-grid")
        let secondItemID = WorkSessionID(rawValue: "preview-\(second.id.rawValue)-grid")
        try model.requestPreview(assetID: first.id, level: .grid)
        try model.requestPreview(assetID: second.id, level: .grid)
        try repository.markPreviewGenerated(assetID: first.id, level: .grid)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: firstItemID, in: model)

        try repository.markPreviewGenerated(assetID: second.id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: secondItemID,
            message: "generated grid preview"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: secondItemID, in: model)
        XCTAssertTrue(waitForBackgroundWorkItemRemoval(firstItemID, in: model))
        XCTAssertEqual(model.backgroundWorkQueue.item(id: secondItemID)?.status, .completed)
    }

    func testPreviewRecoveryRefreshesQueueStateOncePerBatch() throws {
        var queueStateQueryCount = 0
        var assetLookupCount = 0
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill-query-count",
            assetCount: 41,
            workerSupervisor: supervisor
        ) { database in
            database.rowQueryObserver = { sql in
                if sql.contains("SELECT asset_id, level, attempt_count"),
                   sql.contains("FROM preview_generation_queue") {
                    queueStateQueryCount += 1
                }
                if sql == "SELECT * FROM assets WHERE id = ?" {
                    assetLookupCount += 1
                }
            }
        }
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        XCTAssertEqual(queueStateQueryCount, 2)

        queueStateQueryCount = 0
        assetLookupCount = 0
        try repository.markPreviewGenerated(assetID: assets[0].id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview for asset-0"
        )))

        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
        XCTAssertEqual(queueStateQueryCount, 1)
        XCTAssertEqual(assetLookupCount, 1)
    }

    func testPreviewCompletionDoesNotRefreshMetadataSyncState() throws {
        var metadataSyncQueryCount = 0
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill-xmp-query-count",
            assetCount: 41,
            workerSupervisor: supervisor
        ) { database in
            database.rowQueryObserver = { sql in
                if sql.contains("FROM metadata_sync_state") {
                    metadataSyncQueryCount += 1
                }
            }
        }
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        metadataSyncQueryCount = 0
        try repository.markPreviewGenerated(assetID: assets[0].id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview for asset-0"
        )))

        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
        XCTAssertEqual(metadataSyncQueryCount, 0)
    }

    func testRequestQueuedPreviewDoesNotRewriteDurablePendingState() throws {
        let directory = try makeTemporaryDirectory(named: "request-preview-dedup-pending")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = makeAsset(id: "asset-0", path: "/Photos/asset-0.jpg", rating: 0)
        let second = makeAsset(id: "asset-1", path: "/Photos/asset-1.jpg", rating: 0)
        try repository.upsert([first, second])
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: first.id, level: .grid))
        Thread.sleep(forTimeInterval: 0.01)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: second.id, level: .grid))
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
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        Thread.sleep(forTimeInterval: 0.01)

        try model.requestPreview(assetID: first.id, level: .grid)

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: first.id, level: .grid),
            PreviewGenerationItem(assetID: second.id, level: .grid)
        ])
    }

    func testVisibleGridPreviewCutsAheadOfPendingPreviewRecoveryBacklog() throws {
        let directory = try makeTemporaryDirectory(named: "visible-preview-priority")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let recoveryFirst = makeAsset(id: "recovery-first", path: "/Photos/recovery-first.jpg", rating: 0)
        let recoverySecond = makeAsset(id: "recovery-second", path: "/Photos/recovery-second.jpg", rating: 0)
        let visible = makeAsset(id: "visible", path: "/Photos/visible.jpg", rating: 0)
        try repository.upsert([recoveryFirst, recoverySecond, visible])
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: recoveryFirst.id, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: recoverySecond.id, level: .grid))
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

        try model.requestVisibleGridPreview(assetID: visible.id)
        try repository.markPreviewGenerated(assetID: recoveryFirst.id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(recoveryFirst.id.rawValue)-grid"),
            message: "generated grid preview"
        )))

        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: recoveryFirst.id, level: .grid),
            .generatePreview(assetID: visible.id, level: .grid)
        ], in: transport))
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(visible.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(recoverySecond.id.rawValue)-grid"))?.status, .queued)
    }

    func testRequestEvaluationDispatchesWorkerRecognitionCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-evaluation",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")

        XCTAssertEqual(try transport.commands(), [.runEvaluation(assetID: asset.id, provider: "local-image-metrics")])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .recognition)
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
    }

    func testRequestEvaluationRequiresCachedPreview() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-evaluation-no-preview",
            workerSupervisor: supervisor
        )

        XCTAssertThrowsError(try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics"))
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testRequestSelectedAssetEvaluationUsesDefaultLocalProvider() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-selected-evaluation",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestSelectedAssetEvaluation()

        XCTAssertEqual(try transport.commands(), [.runEvaluation(assetID: asset.id, provider: "local-image-metrics")])
    }

    func testRequestSelectedAssetEvaluationsDispatchesDefaultLocalProviders() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-selected-evaluations",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

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
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation",
            assets: [first, second],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: first.id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: second.id, level: .grid)))

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

    func testRequestVisibleAssetEvaluationsSkipsAssetsWithoutCachedPreviews() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let cached = makeAsset(id: "cached", size: 1)
        let uncached = makeAsset(id: "uncached", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation-skips-uncached",
            assets: [cached, uncached],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: cached.id, level: .grid)))

        try model.requestVisibleAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(cached.id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: cached.id, provider: "local-image-metrics")
        ])
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
            named: "evaluation-preview-required",
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestSelectedAssetEvaluation)
    }

    func testCanRequestVisibleAssetEvaluationsRequiresLoadedAssetsAndWorker() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "visible", size: 1)

        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [asset]).canRequestVisibleAssetEvaluations)
        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [], workerSupervisor: supervisor).canRequestVisibleAssetEvaluations)

        let (model, _, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation-preview-required",
            assets: [asset],
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestVisibleAssetEvaluations)
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
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

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
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
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

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
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
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: []
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
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: []
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

    @MainActor
    func testWorkerPreviewFailureRefreshesDurableFailureState() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "preview-durable-failure", size: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "preview-durable-failure",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .grid)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid")
        try repository.recordPreviewGenerationFailure(
            assetID: asset.id,
            level: .grid,
            errorMessage: "could not render preview"
        )

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "could not render preview"
        )))

        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)
        XCTAssertEqual(model.previewGenerationQueueStates.first?.lastErrorMessage, "could not render preview")
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

    func testVisibleLoupePreviewDoesNotDispatchWhenOriginalVolumeIsOffline() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(
            id: "offline-loupe",
            path: "/Volumes/TeststripOfflineVolume/offline-loupe.jpg",
            rating: 0
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "loupe-progressive-offline-original",
            assets: [asset],
            workerSupervisor: supervisor
        )

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(model.selectedAsset?.availability, .offline)
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

    func testVisibleComparePreviewsDoNotDispatchForUnavailableOriginals() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let offline = makeAsset(
            id: "offline-compare",
            path: "/Volumes/TeststripOfflineVolume/offline-compare.jpg",
            rating: 0,
            availability: .offline
        )
        let missing = makeAsset(
            id: "missing-compare",
            path: "/Photos/missing-compare.jpg",
            rating: 0,
            availability: .missing
        )
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "compare-unavailable-originals",
            assets: [offline, missing],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: offline.id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: missing.id, level: .grid)))

        try model.requestVisibleComparePreviews()

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(model.loupePreviewURL(for: offline.id), previewCache.url(for: PreviewCacheKey(assetID: offline.id, level: .grid)))
        XCTAssertEqual(model.loupePreviewURL(for: missing.id), previewCache.url(for: PreviewCacheKey(assetID: missing.id, level: .grid)))
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

    func testVisibleGridPreviewPromotesExistingQueuedPreviewWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let running = makeAsset(id: "running", size: 1)
        let olderQueued = makeAsset(id: "older", size: 2)
        let visible = makeAsset(id: "visible", size: 3)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "grid-promotes-existing-preview",
            assets: [running, olderQueued, visible],
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: running.id, level: .grid)
        try model.requestPreview(assetID: olderQueued.id, level: .grid)
        try model.requestPreview(assetID: visible.id, level: .grid)

        try model.requestVisibleGridPreview(assetID: visible.id)

        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.id.rawValue), [
            "preview-\(visible.id.rawValue)-grid",
            "preview-\(olderQueued.id.rawValue)-grid"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: running.id, level: .grid)
        ])
    }

    func testVisibleGridPreviewDoesNotDispatchForKnownUnavailableOriginals() throws {
        for availability in [SourceAvailability.offline, .missing, .moved] {
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
            PreviewGenerationItem(assetID: assetID, level: .micro),
            PreviewGenerationItem(assetID: assetID, level: .grid)
        ])
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: assetID, level: .micro)])
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
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .micro))
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .grid))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0
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
            .generatePreview(assetID: importedAsset.id, level: .micro)
        ])
    }

    @MainActor
    func testWorkerImportPersistsRunningActivityAndReloadMarksItInterrupted() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-interrupted")
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
        let runningSession = try catalog.repository.session(id: importItem.id)
        XCTAssertEqual(runningSession.kind, .ingest)
        XCTAssertEqual(runningSession.status, .running)
        XCTAssertEqual(runningSession.detail, "Importing from photos")

        let reloaded = try AppModel.load(catalog: catalog)
        let interruptedSession = try catalog.repository.session(id: importItem.id)
        XCTAssertEqual(interruptedSession.status, .failed)
        XCTAssertEqual(interruptedSession.detail, "Import interrupted before completion")
        XCTAssertEqual(interruptedSession.failureCount, 1)
        XCTAssertEqual(reloaded.recentWork.first?.id, importItem.id.rawValue)
        XCTAssertEqual(reloaded.recentWork.first?.status, .failed)
    }

    @MainActor
    func testInterruptedWorkerImportPreservesLastProgressDetail() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-interrupted-progress")
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
            completedUnitCount: 7,
            totalUnitCount: 20,
            detail: "Cataloging 7 of 20 photos",
            catalogedAssetIDs: []
        )))
        try await waitForPersistedWorkDetail("Cataloging 7 of 20 photos", itemID: itemID, repository: catalog.repository)

        let reloaded = try AppModel.load(catalog: catalog)
        let interruptedSession = try catalog.repository.session(id: itemID)
        XCTAssertEqual(interruptedSession.status, .failed)
        XCTAssertEqual(interruptedSession.completedUnitCount, 7)
        XCTAssertEqual(interruptedSession.totalUnitCount, 20)
        XCTAssertEqual(interruptedSession.detail, "Import interrupted before completion (last progress: Cataloging 7 of 20 photos)")
        XCTAssertEqual(reloaded.recentWork.first?.detail, interruptedSession.detail)
    }

    @MainActor
    func testWorkerImportProgressShowsCatalogedAssetsBeforeCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("early.png")
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
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-early-import"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 10,
            detail: "Cataloging 1 of 10 photos",
            catalogedAssetIDs: [importedAsset.id]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(model.visibleWorkActivity?.completedUnitCount, 1)
        XCTAssertEqual(model.visibleWorkActivity?.totalUnitCount, 10)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Cataloging 1 of 10 photos")
    }

    @MainActor
    func testWorkerImportProgressDoesNotReloadForEveryCatalogedAsset() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-coalesced-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let firstImage = photoFolder.appendingPathComponent("first.png")
        let secondImage = photoFolder.appendingPathComponent("second.png")
        try writeTestPNG(to: firstImage)
        try writeTestPNG(to: secondImage)
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
        let firstAsset = Asset(
            id: AssetID(rawValue: "worker-early-import-first"),
            originalURL: firstImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let secondAsset = Asset(
            id: AssetID(rawValue: "worker-early-import-second"),
            originalURL: secondImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(firstAsset)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 10,
            detail: "Cataloging 1 of 10 photos",
            catalogedAssetIDs: [firstAsset.id]
        )))
        try await waitForSelectedAsset(firstAsset.id, in: model)

        try catalog.repository.upsert(secondAsset)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 2,
            totalUnitCount: 10,
            detail: "Cataloging 2 of 10 photos",
            catalogedAssetIDs: [secondAsset.id]
        )))

        try await waitForVisibleWorkDetail("Cataloging 2 of 10 photos", in: model)
        XCTAssertEqual(model.selectedAssetID, firstAsset.id)
        XCTAssertEqual(model.assets.map(\.id), [firstAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    @MainActor
    func testWorkerImportProgressPersistsRunningSessionDetail() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-progress-session")
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
            completedUnitCount: 7,
            totalUnitCount: 20,
            detail: "Cataloging 7 of 20 photos",
            catalogedAssetIDs: []
        )))

        try await waitForPersistedWorkDetail("Cataloging 7 of 20 photos", itemID: itemID, repository: catalog.repository)
        let session = try catalog.repository.session(id: itemID)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.completedUnitCount, 7)
        XCTAssertEqual(session.totalUnitCount, 20)
        XCTAssertEqual(session.detail, "Cataloging 7 of 20 photos")
    }

    @MainActor
    func testWorkerImportProgressPrefersCatalogedAssetWhenCurrentPageIsFull() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-full-page-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("new.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        for index in 0..<120 {
            try catalog.repository.upsert(Asset(
                id: AssetID(rawValue: "existing-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/existing-\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "existing-0"))

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-early-import-full-page"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10_000, modificationDate: Date(timeIntervalSince1970: 10_000)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 121,
            detail: "Cataloging 1 of 121 photos",
            catalogedAssetIDs: [importedAsset.id]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertEqual(model.totalAssetCount, 121)
        XCTAssertEqual(model.libraryCountText, "Showing 121-121 of 121 photographs")
        XCTAssertTrue(model.isImporting)
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
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0
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

    private func makeModelWithPendingPreviewBacklog(
        named name: String,
        assetCount: Int,
        workerSupervisor: WorkerSupervisor,
        configureDatabase: ((CatalogDatabase) -> Void)? = nil
    ) throws -> (AppModel, CatalogRepository, [Asset]) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        configureDatabase?(database)
        let repository = CatalogRepository(database: database)
        let assets = (0..<assetCount).map { index in
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, assets)
    }

    private func makeModelWithCatalogAsset(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, CatalogRepository, Asset) {
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, asset)
    }

    private func makeWorkerMetadataSyncModel(
        named name: String,
        assetID: String
    ) throws -> (AppModel, CatalogRepository, Asset, URL, RecordingWorkerTransport) {
        let directory = try makeTemporaryDirectory(named: name)
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: assetID),
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: supervisor), repository, asset, originalURL, transport)
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
    private func waitForPersistedWorkDetail(
        _ detail: String,
        itemID: WorkSessionID,
        repository: CatalogRepository
    ) async throws {
        for _ in 0..<100 {
            if try repository.session(id: itemID).detail == detail {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for persisted work detail \(detail)")
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

    private func commandDescription(_ transport: RecordingWorkerTransport) -> String {
        (try? "\(transport.commands())") ?? "could not decode commands"
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

    private func waitForBackgroundWorkItemRemoval(
        _ itemID: WorkSessionID,
        in model: AppModel,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.backgroundWorkQueue.item(id: itemID) == nil {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return model.backgroundWorkQueue.item(id: itemID) == nil
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
