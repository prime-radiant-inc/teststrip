import XCTest
@testable import TeststripCore

final class CatalogDatabaseTests: XCTestCase {
    func testMigratesAndPersistsAsset() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 3)
        try repository.upsert(asset)

        let fetched = try repository.asset(id: asset.id)

        XCTAssertEqual(fetched, asset)
    }

    func testSecondConnectionWaitsForBusyWriter() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-busy-timeout")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        let writer = try CatalogDatabase.open(at: catalogURL)
        try writer.migrate()
        let contendingWriter = try CatalogDatabase.open(at: catalogURL)
        try contendingWriter.migrate()
        let releasedLock = expectation(description: "released write lock")
        try writer.execute("BEGIN IMMEDIATE TRANSACTION")
        defer { try? writer.execute("ROLLBACK") }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            try? writer.execute("COMMIT")
            releasedLock.fulfill()
        }

        try contendingWriter.execute(
            "INSERT OR REPLACE INTO catalog_meta (key, value) VALUES ('busy_timeout_probe', 'ok')"
        )

        wait(for: [releasedLock], timeout: 1)
        let rows = try contendingWriter.rows(
            "SELECT value FROM catalog_meta WHERE key = 'busy_timeout_probe'"
        )
        XCTAssertEqual(rows.first?["value"], "ok")
    }

    func testMigratesAndPersistsAssetTechnicalMetadata() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-metadata")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let technicalMetadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            cameraMake: "Canon",
            cameraModel: "EOS R5",
            lensModel: "RF 50mm F1.2L USM",
            isoSpeed: 800,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
        let asset = Asset.testAsset(
            path: "/Volumes/NAS/Job/frame.cr2",
            rating: 3,
            technicalMetadata: technicalMetadata
        )

        try repository.upsert(asset)

        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.technicalMetadata, technicalMetadata)
    }

    func testMigrationAddsTechnicalMetadataStorageToExistingCatalog() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-metadata-migration")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.execute(
            """
            CREATE TABLE assets (
                id TEXT PRIMARY KEY NOT NULL,
                original_path TEXT NOT NULL,
                volume_identifier TEXT,
                fingerprint_json TEXT NOT NULL,
                availability TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                catalog_generation INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        let legacyAsset = Asset.testAsset(id: AssetID(rawValue: "legacy"), path: "/Volumes/NAS/Job/legacy.cr2", rating: 2)
        try database.insertTestAsset(legacyAsset, createdAt: "1")

        try database.migrate()
        let repository = CatalogRepository(database: database)
        var refreshedAsset = try repository.asset(id: legacyAsset.id)
        XCTAssertNil(refreshedAsset.technicalMetadata)
        refreshedAsset.technicalMetadata = AssetTechnicalMetadata(
            pixelWidth: 8256,
            pixelHeight: 5504,
            cameraMake: "Fujifilm",
            cameraModel: "GFX 100S",
            lensModel: "GF80mmF1.7 R WR",
            isoSpeed: 400,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_100),
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        try repository.upsert(refreshedAsset)

        XCTAssertEqual(try repository.asset(id: legacyAsset.id), refreshedAsset)
    }

    func testMetadataUpdateIncrementsCatalogGeneration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 1)
        try repository.upsert(asset)

        try repository.updateMetadata(assetID: asset.id) { metadata in
            metadata.rating = 5
            metadata.flag = .pick
        }

        let fetched = try repository.asset(id: asset.id)
        let generation = try repository.catalogGeneration(assetID: asset.id)
        XCTAssertEqual(fetched.metadata.rating, 5)
        XCTAssertEqual(fetched.metadata.flag, .pick)
        XCTAssertEqual(generation, 2)
    }

    func testNonMetadataAssetRefreshDoesNotIncrementCatalogGeneration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-generation-refresh")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 4)
        try repository.upsert(asset)
        let refreshedFingerprint = FileFingerprint(
            size: 200,
            modificationDate: Date(timeIntervalSince1970: 2.5),
            contentHash: "new-hash"
        )
        let refreshedAsset = Asset(
            id: asset.id,
            originalURL: asset.originalURL,
            volumeIdentifier: asset.volumeIdentifier,
            fingerprint: refreshedFingerprint,
            availability: .stale,
            metadata: asset.metadata
        )

        try repository.upsert(refreshedAsset)

        let fetched = try repository.asset(id: asset.id)
        let generation = try repository.catalogGeneration(assetID: asset.id)
        XCTAssertEqual(fetched.fingerprint, refreshedFingerprint)
        XCTAssertEqual(fetched.availability, .stale)
        XCTAssertEqual(fetched.metadata, asset.metadata)
        XCTAssertEqual(generation, 1)
    }

    func testFetchesAllAssetsForGridLoading() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(path: "/Volumes/NAS/Job/a.cr2", rating: 2)
        let second = Asset.testAsset(path: "/Volumes/NAS/Job/b.cr2", rating: 5)
        try repository.upsert(first)
        try repository.upsert(second)

        let assets = try repository.allAssets(limit: 100)

        XCTAssertEqual(assets.map(\.id), [first.id, second.id])
    }

    func testCountsAssetsWithoutLoadingRows() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/Job/a.cr2", rating: 2))
        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/Job/b.cr2", rating: 5))

        XCTAssertEqual(try repository.assetCount(), 2)
    }

    func testPersistsPendingPreviewGenerationItems() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let item = PreviewGenerationItem(assetID: AssetID(rawValue: "asset-1"), level: .grid)

        try repository.recordPreviewGenerationPending(item)
        let reopenedDatabase = try CatalogDatabase.open(at: catalogURL)
        try reopenedDatabase.migrate()
        let reopenedRepository = CatalogRepository(database: reopenedDatabase)

        XCTAssertEqual(try reopenedRepository.pendingPreviewGenerationItems(), [item])
    }

    func testPersistsPendingPreviewGenerationItemsInBatch() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-batch")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let items = [
            PreviewGenerationItem(assetID: AssetID(rawValue: "asset-1"), level: .micro),
            PreviewGenerationItem(assetID: AssetID(rawValue: "asset-1"), level: .grid),
            PreviewGenerationItem(assetID: AssetID(rawValue: "asset-2"), level: .micro),
            PreviewGenerationItem(assetID: AssetID(rawValue: "asset-2"), level: .grid)
        ]

        try repository.recordPreviewGenerationPending(items)
        let reopenedDatabase = try CatalogDatabase.open(at: catalogURL)
        try reopenedDatabase.migrate()
        let reopenedRepository = CatalogRepository(database: reopenedDatabase)

        XCTAssertEqual(try reopenedRepository.pendingPreviewGenerationItems(), items)
    }

    func testLimitsPendingPreviewGenerationItems() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-limit")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: AssetID(rawValue: "asset-1"), level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: AssetID(rawValue: "asset-2"), level: .grid))

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(limit: 1).count, 1)
    }

    func testRecordsPreviewGenerationFailureStateWithoutClearingPendingItem() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-failure")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let item = PreviewGenerationItem(assetID: AssetID(rawValue: "asset-1"), level: .grid)

        try repository.recordPreviewGenerationPending(item)
        try repository.recordPreviewGenerationFailure(
            assetID: item.assetID,
            level: item.level,
            errorMessage: "unsupported image"
        )
        try repository.recordPreviewGenerationFailure(
            assetID: item.assetID,
            level: item.level,
            errorMessage: "still unsupported"
        )

        let state = try XCTUnwrap(repository.previewGenerationQueueState(assetID: item.assetID, level: item.level))
        XCTAssertEqual(state.item, item)
        XCTAssertEqual(state.attemptCount, 2)
        XCTAssertEqual(state.lastErrorMessage, "still unsupported")
        XCTAssertNotNil(state.lastAttemptedAt)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [item])
    }

    func testPendingPreviewGenerationItemsCanFilterByAttemptCount() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-attempt-filter")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let exhausted = PreviewGenerationItem(assetID: AssetID(rawValue: "exhausted"), level: .grid)
        let retryable = PreviewGenerationItem(assetID: AssetID(rawValue: "retryable"), level: .grid)
        let pending = PreviewGenerationItem(assetID: AssetID(rawValue: "pending"), level: .grid)
        try repository.recordPreviewGenerationPending(exhausted)
        try repository.recordPreviewGenerationPending(retryable)
        try repository.recordPreviewGenerationPending(pending)
        for attempt in 1...3 {
            try repository.recordPreviewGenerationFailure(
                assetID: exhausted.assetID,
                level: exhausted.level,
                errorMessage: "exhausted \(attempt)"
            )
        }
        for attempt in 1...2 {
            try repository.recordPreviewGenerationFailure(
                assetID: retryable.assetID,
                level: retryable.level,
                errorMessage: "retryable \(attempt)"
            )
        }

        let allItems = try repository.pendingPreviewGenerationItems()
        let retryableItems = try repository.pendingPreviewGenerationItems(maximumAttemptCount: 3)

        XCTAssertEqual(allItems.count, 3)
        XCTAssertEqual(retryableItems.map(\.assetID.rawValue).sorted(), ["pending", "retryable"])
    }

    func testFetchesPreviewGenerationQueueStates() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-states")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let failed = PreviewGenerationItem(assetID: AssetID(rawValue: "failed"), level: .grid)
        let pending = PreviewGenerationItem(assetID: AssetID(rawValue: "pending"), level: .large)

        try repository.recordPreviewGenerationPending(failed)
        try repository.recordPreviewGenerationPending(pending)
        try repository.recordPreviewGenerationFailure(
            assetID: failed.assetID,
            level: failed.level,
            errorMessage: "could not render preview"
        )

        let states = try repository.previewGenerationQueueStates()

        XCTAssertEqual(states.count, 2)
        let failedState = try XCTUnwrap(states.first { $0.item == failed })
        let pendingState = try XCTUnwrap(states.first { $0.item == pending })
        XCTAssertEqual(failedState.attemptCount, 1)
        XCTAssertEqual(failedState.lastErrorMessage, "could not render preview")
        XCTAssertEqual(pendingState.attemptCount, 0)
        XCTAssertNil(pendingState.lastErrorMessage)
    }

    func testMigrationAddsPreviewGenerationFailureStateToExistingQueue() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-failure-migration")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.execute(
            """
            CREATE TABLE preview_generation_queue (
                asset_id TEXT NOT NULL,
                level TEXT NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (asset_id, level)
            )
            """
        )
        try database.execute(
            """
            INSERT INTO preview_generation_queue (asset_id, level, updated_at)
            VALUES ('asset-1', 'grid', '1')
            """
        )

        try database.migrate()
        let repository = CatalogRepository(database: database)

        let state = try XCTUnwrap(repository.previewGenerationQueueState(
            assetID: AssetID(rawValue: "asset-1"),
            level: .grid
        ))
        XCTAssertEqual(state.item, PreviewGenerationItem(assetID: AssetID(rawValue: "asset-1"), level: .grid))
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastErrorMessage)
        XCTAssertNil(state.lastAttemptedAt)
    }

    func testFetchesAssetPageWithOffset() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(path: "/Volumes/NAS/Job/a.cr2", rating: 1)
        let second = Asset.testAsset(path: "/Volumes/NAS/Job/b.cr2", rating: 2)
        let third = Asset.testAsset(path: "/Volumes/NAS/Job/c.cr2", rating: 3)
        try repository.upsert(first)
        try repository.upsert(second)
        try repository.upsert(third)

        let page = try repository.allAssets(limit: 1, offset: 1)

        XCTAssertEqual(page.map(\.id), [second.id])
    }

    func testFindsAssetOffsetInCatalogOrder() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-offset")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(path: "/Volumes/NAS/Job/a.cr2", rating: 1)
        let second = Asset.testAsset(path: "/Volumes/NAS/Job/b.cr2", rating: 2)
        let third = Asset.testAsset(path: "/Volumes/NAS/Job/c.cr2", rating: 3)
        try repository.upsert(first)
        try repository.upsert(second)
        try repository.upsert(third)

        XCTAssertEqual(try repository.assetOffset(id: first.id), 0)
        XCTAssertEqual(try repository.assetOffset(id: second.id), 1)
        XCTAssertEqual(try repository.assetOffset(id: third.id), 2)
    }

    func testSearchesAssetsWithCatalogBackedPredicates() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = Asset.testAsset(
            id: AssetID(rawValue: "keeper"),
            path: "/Volumes/NAS/Wedding/ceremony-keeper.jpg",
            metadata: AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["ceremony"])
        )
        let reject = Asset.testAsset(
            id: AssetID(rawValue: "reject"),
            path: "/Volumes/NAS/Wedding/ceremony-blink.jpg",
            metadata: AssetMetadata(rating: 1, colorLabel: .red, flag: .reject, keywords: ["ceremony"])
        )
        let landscape = Asset.testAsset(
            id: AssetID(rawValue: "landscape"),
            path: "/Volumes/NAS/Travel/mountain.jpg",
            metadata: AssetMetadata(rating: 4, colorLabel: .green, flag: nil, keywords: ["patagonia"])
        )
        let needsKeywords = Asset.testAsset(
            id: AssetID(rawValue: "needs-keywords"),
            path: "/Volumes/NAS/Wedding/untagged.jpg",
            metadata: AssetMetadata(rating: 3)
        )
        try repository.upsert([keeper, reject, landscape, needsKeywords])

        let pickQuery = SetQuery(predicates: [.text("CEREMONY"), .ratingAtLeast(4), .flag(.pick)])
        XCTAssertEqual(try repository.allAssets(matching: pickQuery, limit: 10).map(\.id), [keeper.id])
        XCTAssertEqual(try repository.assetCount(matching: pickQuery), 1)

        let colorKeywordQuery = SetQuery(predicates: [.colorLabel(.green), .keyword("patagonia")])
        XCTAssertEqual(try repository.allAssets(matching: colorKeywordQuery, limit: 10).map(\.id), [landscape.id])

        let missingKeywordsQuery = SetQuery(predicates: [.missingKeywords])
        XCTAssertEqual(try repository.allAssets(matching: missingKeywordsQuery, limit: 10).map(\.id), [needsKeywords.id])
        XCTAssertEqual(try repository.assetCount(matching: missingKeywordsQuery), 1)
    }

    func testListsCatalogFoldersWithAssetCounts() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-folders")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([
            Asset.testAsset(id: AssetID(rawValue: "ceremony-1"), path: "/Volumes/NAS/Wedding/Ceremony/frame-1.jpg", rating: 0),
            Asset.testAsset(id: AssetID(rawValue: "ceremony-2"), path: "/Volumes/NAS/Wedding/Ceremony/frame-2.jpg", rating: 0),
            Asset.testAsset(id: AssetID(rawValue: "travel"), path: "/Volumes/NAS/Travel/frame-3.jpg", rating: 0)
        ])

        XCTAssertEqual(try repository.folders(), [
            CatalogFolder(path: "/Volumes/NAS/Travel/", name: "Travel", assetCount: 1),
            CatalogFolder(path: "/Volumes/NAS/Wedding/Ceremony/", name: "Ceremony", assetCount: 2)
        ])
    }

    func testTextSearchMatchesEvaluationLabelsAndText() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let portrait = Asset.testAsset(id: AssetID(rawValue: "portrait"), path: "/Volumes/NAS/Job/frame-001.jpg", rating: 0)
        let document = Asset.testAsset(id: AssetID(rawValue: "document"), path: "/Volumes/NAS/Job/frame-002.jpg", rating: 0)
        let untagged = Asset.testAsset(id: AssetID(rawValue: "untagged"), path: "/Volumes/NAS/Job/frame-003.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([portrait, document, untagged])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: portrait.id, kind: .object, value: .label("outdoor portrait"), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: document.id, kind: .ocrText, value: .text("Invoice 123\nTotal 45"), confidence: 1.0, provenance: provenance)
        ])

        let labelQuery = SetQuery(predicates: [.text("PORTRAIT")])
        XCTAssertEqual(try repository.allAssets(matching: labelQuery, limit: 10).map(\.id), [portrait.id])
        XCTAssertEqual(try repository.assetCount(matching: labelQuery), 1)

        let ocrQuery = SetQuery(predicates: [.text("invoice 123")])
        XCTAssertEqual(try repository.allAssets(matching: ocrQuery, limit: 10).map(\.id), [document.id])
    }

    func testSearchesAssetsWithEvaluationKindPredicate() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-kind-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let focused = Asset.testAsset(id: AssetID(rawValue: "focused"), path: "/Volumes/NAS/Job/focused.jpg", rating: 0)
        let object = Asset.testAsset(id: AssetID(rawValue: "object"), path: "/Volumes/NAS/Job/object.jpg", rating: 0)
        let unevaluated = Asset.testAsset(id: AssetID(rawValue: "unevaluated"), path: "/Volumes/NAS/Job/unevaluated.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([focused, object, unevaluated])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: focused.id, kind: .focus, value: .score(0.91), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance)
        ])

        let focusQuery = SetQuery(predicates: [.evaluationKind(.focus)])

        XCTAssertEqual(try repository.allAssets(matching: focusQuery, limit: 10).map(\.id), [focused.id])
        XCTAssertEqual(try repository.assetCount(matching: focusQuery), 1)
    }

    func testSearchesAssetsWithMetadataSyncConflictPredicate() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-xmp-conflict-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let conflicted = Asset.testAsset(id: AssetID(rawValue: "conflicted"), path: "/Volumes/NAS/Job/conflicted.cr2", rating: 0)
        let clean = Asset.testAsset(id: AssetID(rawValue: "clean"), path: "/Volumes/NAS/Job/clean.cr2", rating: 0)
        try repository.upsert([conflicted, clean])
        try repository.recordMetadataSyncConflict(MetadataSyncItem(
            assetID: conflicted.id,
            sidecarURL: conflicted.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))

        let conflictQuery = SetQuery(predicates: [.metadataSyncConflict])

        XCTAssertEqual(try repository.allAssets(matching: conflictQuery, limit: 10).map(\.id), [conflicted.id])
        XCTAssertEqual(try repository.assetCount(matching: conflictQuery), 1)
    }

    func testSearchesAssetsWithMetadataSyncPendingPredicate() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-xmp-pending-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let pending = Asset.testAsset(id: AssetID(rawValue: "pending"), path: "/Volumes/NAS/Job/pending.cr2", rating: 0)
        let clean = Asset.testAsset(id: AssetID(rawValue: "clean"), path: "/Volumes/NAS/Job/clean.cr2", rating: 0)
        try repository.upsert([pending, clean])
        try repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: pending.id,
            sidecarURL: pending.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))

        let pendingQuery = SetQuery(predicates: [.metadataSyncPending])

        XCTAssertEqual(try repository.allAssets(matching: pendingQuery, limit: 10).map(\.id), [pending.id])
        XCTAssertEqual(try repository.assetCount(matching: pendingQuery), 1)
    }

    func testListsEvaluationKindSummariesWithDistinctAssetCounts() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-kind-summary")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let firstFace = Asset.testAsset(id: AssetID(rawValue: "first-face"), path: "/Volumes/NAS/Job/first-face.jpg", rating: 0)
        let secondFace = Asset.testAsset(id: AssetID(rawValue: "second-face"), path: "/Volumes/NAS/Job/second-face.jpg", rating: 0)
        let object = Asset.testAsset(id: AssetID(rawValue: "object"), path: "/Volumes/NAS/Job/object.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let alternateProvenance = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        try repository.upsert([firstFace, secondFace, object])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: firstFace.id, kind: .faceQuality, value: .score(0.8), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: firstFace.id, kind: .faceQuality, value: .score(0.7), confidence: 0.7, provenance: alternateProvenance),
            EvaluationSignal(assetID: secondFace.id, kind: .faceQuality, value: .score(0.6), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance)
        ])

        XCTAssertEqual(try repository.evaluationKindSummaries(), [
            CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 2),
            CatalogEvaluationKindSummary(kind: .object, assetCount: 1)
        ])
    }

    func testSearchesAssetsWithTechnicalMetadataPredicates() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_086_400)
        let canon = Asset.testAsset(
            id: AssetID(rawValue: "canon"),
            path: "/Volumes/NAS/Job/canon.cr3",
            rating: 4,
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
        let fuji = Asset.testAsset(
            id: AssetID(rawValue: "fuji"),
            path: "/Volumes/NAS/Job/fuji.raf",
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
        let missingTechnicalMetadata = Asset.testAsset(
            id: AssetID(rawValue: "missing"),
            path: "/Volumes/NAS/Job/missing.jpg",
            rating: 5
        )
        try repository.upsert([canon, fuji, missingTechnicalMetadata])

        let query = SetQuery(predicates: [
            .camera("canon"),
            .lens("RF 50"),
            .isoAtLeast(800),
            .capturedAtOrAfter(start),
            .capturedBefore(end)
        ])

        XCTAssertEqual(try repository.allAssets(matching: query, limit: 10).map(\.id), [canon.id])
        XCTAssertEqual(try repository.assetCount(matching: query), 1)
    }

    func testSummarizesCaptureDatesForTimelineWithoutLoadingAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-timeline-days")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        let first = Asset.testAsset(
            id: AssetID(rawValue: "first"),
            path: "/Volumes/NAS/Job/first.cr3",
            rating: 0,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: Date(timeIntervalSince1970: 1_800_010_000),
                provenance: provenance
            )
        )
        let sameDay = Asset.testAsset(
            id: AssetID(rawValue: "same-day"),
            path: "/Volumes/NAS/Job/same-day.cr3",
            rating: 0,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: Date(timeIntervalSince1970: 1_800_020_000),
                provenance: provenance
            )
        )
        let nextDay = Asset.testAsset(
            id: AssetID(rawValue: "next-day"),
            path: "/Volumes/NAS/Job/next-day.cr3",
            rating: 0,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: Date(timeIntervalSince1970: 1_800_096_400),
                provenance: provenance
            )
        )
        let undated = Asset.testAsset(
            id: AssetID(rawValue: "undated"),
            path: "/Volumes/NAS/Job/undated.cr3",
            rating: 0
        )
        try repository.upsert([first, sameDay, nextDay, undated])

        XCTAssertEqual(try repository.timelineDays(), [
            CatalogTimelineDay(year: 2027, month: 1, day: 16, assetCount: 1),
            CatalogTimelineDay(year: 2027, month: 1, day: 15, assetCount: 2)
        ])
    }

    func testPersistsDynamicAssetSet() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-sets")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let set = AssetSet(
            id: AssetSetID(rawValue: "ceremony-picks"),
            name: "Ceremony Picks",
            membership: .dynamic(SetQuery(predicates: [.text("ceremony"), .ratingAtLeast(4), .flag(.pick)])),
            starred: true
        )

        try repository.upsert(set)

        XCTAssertEqual(try repository.assetSet(id: set.id), set)
    }

    func testListsAssetSetsWithStarredFilter() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-sets-list")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let recent = AssetSet.manual(
            id: AssetSetID(rawValue: "recent-import"),
            name: "Recent Import",
            assetIDs: [AssetID(rawValue: "a")]
        )
        let starred = AssetSet(
            id: AssetSetID(rawValue: "long-running"),
            name: "Long Running",
            membership: .snapshot([AssetID(rawValue: "b")]),
            starred: true
        )

        try repository.upsert(recent)
        try repository.upsert(starred)

        XCTAssertEqual(try repository.assetSets().map(\.id), [recent.id, starred.id])
        XCTAssertEqual(try repository.assetSets(starredOnly: true), [starred])
    }

    func testUpsertAssetSetReplacesMembershipAndStarredState() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-sets-upsert")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let id = AssetSetID(rawValue: "keepers")

        try repository.upsert(AssetSet.manual(id: id, name: "Keepers", assetIDs: [AssetID(rawValue: "old")]))
        try repository.upsert(AssetSet(
            id: id,
            name: "Five Star Keepers",
            membership: .dynamic(SetQuery(predicates: [.ratingAtLeast(5)])),
            starred: true
        ))

        XCTAssertEqual(
            try repository.assetSet(id: id),
            AssetSet(
                id: id,
                name: "Five Star Keepers",
                membership: .dynamic(SetQuery(predicates: [.ratingAtLeast(5)])),
                starred: true
            )
        )
    }

    func testFetchesAssetsForExplicitSetMembershipInSavedOrder() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-set-assets")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(id: AssetID(rawValue: "first"), path: "/Volumes/NAS/Job/first.cr2", rating: 1)
        let second = Asset.testAsset(id: AssetID(rawValue: "second"), path: "/Volumes/NAS/Job/second.cr2", rating: 2)
        let third = Asset.testAsset(id: AssetID(rawValue: "third"), path: "/Volumes/NAS/Job/third.cr2", rating: 3)
        try repository.upsert([first, second, third])

        let assets = try repository.assets(ids: [
            second.id,
            AssetID(rawValue: "missing"),
            first.id,
            third.id
        ], limit: 2)

        XCTAssertEqual(assets.map(\.id), [second.id, first.id])
        XCTAssertEqual(try repository.assetCount(ids: [second.id, AssetID(rawValue: "missing"), first.id]), 2)
    }

    func testImportBatchQueryMatchesWorkSessionOutputSets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-import-batch-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(id: AssetID(rawValue: "first"), path: "/Volumes/NAS/Job/first.cr2", rating: 5)
        let second = Asset.testAsset(id: AssetID(rawValue: "second"), path: "/Volumes/NAS/Job/second.cr2", rating: 3)
        let third = Asset.testAsset(id: AssetID(rawValue: "third"), path: "/Volumes/NAS/Job/third.cr2", rating: 5)
        let outside = Asset.testAsset(id: AssetID(rawValue: "outside"), path: "/Volumes/NAS/Job/outside.cr2", rating: 5)
        let manualSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-output-manual"),
            name: "Import Output",
            assetIDs: [second.id, first.id]
        )
        let snapshotSet = AssetSet(
            id: AssetSetID(rawValue: "work-output-snapshot"),
            name: "Import Snapshot",
            membership: .snapshot([third.id])
        )
        let session = WorkSession(
            id: WorkSessionID(rawValue: "import-1"),
            kind: .ingest,
            intent: "Import card",
            title: "Import Photos",
            detail: "Imported 3 photos",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [manualSet.id, snapshotSet.id],
            completedUnitCount: 3,
            totalUnitCount: 3,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.upsert([first, second, third, outside])
        try repository.upsert(manualSet)
        try repository.upsert(snapshotSet)
        try repository.save(session)

        let query = SetQuery(predicates: [.importBatch(session.id.rawValue), .ratingAtLeast(5)])

        XCTAssertEqual(try repository.allAssets(matching: query, limit: 10).map(\.id), [first.id, third.id])
        XCTAssertEqual(try repository.assetIDs(matching: query), [first.id, third.id])
        XCTAssertEqual(try repository.assetCount(matching: query), 2)
    }

    func testMissingImportBatchQueryMatchesNoAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-missing-import-batch-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(id: AssetID(rawValue: "asset"), path: "/Volumes/NAS/Job/asset.cr2", rating: 5)
        try repository.upsert(asset)

        let query = SetQuery(predicates: [.importBatch("missing-import")])

        XCTAssertEqual(try repository.allAssets(matching: query, limit: 10), [])
        XCTAssertEqual(try repository.assetIDs(matching: query), [])
        XCTAssertEqual(try repository.assetCount(matching: query), 0)
    }

    func testPersistsEvaluationSignalsForAsset() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-signals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assetID = AssetID(rawValue: "asset-1")
        let signal = EvaluationSignal(
            assetID: assetID,
            kind: .focus,
            value: .score(0.92),
            confidence: 0.81,
            provenance: ProviderProvenance(provider: "LocalVision", model: "focus", version: "1", settingsHash: "default")
        )

        try repository.recordEvaluationSignals([signal])

        XCTAssertEqual(try repository.evaluationSignals(assetID: assetID), [signal])
    }

    func testUnevaluatedQueryMatchesAssetsWithoutSignals() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-unevaluated-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let evaluated = Asset.testAsset(id: AssetID(rawValue: "evaluated"), path: "/Volumes/NAS/Job/evaluated.jpg", rating: 0)
        let unevaluated = Asset.testAsset(id: AssetID(rawValue: "unevaluated"), path: "/Volumes/NAS/Job/unevaluated.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([evaluated, unevaluated])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: evaluated.id, kind: .faceQuality, value: .score(0.82), confidence: 0.82, provenance: provenance)
        ])
        let query = SetQuery(predicates: [.unevaluated])

        XCTAssertEqual(try repository.allAssets(matching: query, limit: 10).map(\.id), [unevaluated.id])
        XCTAssertEqual(try repository.assetCount(matching: query), 1)
    }

    func testEvaluationFailureQueryMatchesProviderFailuresAndClearsAfterSameProviderSuccess() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-failure-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let failed = Asset.testAsset(id: AssetID(rawValue: "failed"), path: "/Volumes/NAS/Job/failed.jpg", rating: 0)
        let clean = Asset.testAsset(id: AssetID(rawValue: "clean"), path: "/Volumes/NAS/Job/clean.jpg", rating: 0)
        let localProvenance = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        let appleProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let failureQuery = SetQuery(predicates: [.evaluationFailure])
        try repository.upsert([failed, clean])

        try repository.recordEvaluationFailure(assetID: failed.id, provider: "local-http-model", message: "model timed out")

        XCTAssertEqual(try repository.allAssets(matching: failureQuery, limit: 10).map(\.id), [failed.id])
        XCTAssertEqual(try repository.assetCount(matching: failureQuery), 1)

        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: failed.id, kind: .object, value: .label("person"), confidence: 0.77, provenance: appleProvenance)
        ])

        XCTAssertEqual(try repository.allAssets(matching: failureQuery, limit: 10).map(\.id), [failed.id])
        XCTAssertEqual(try repository.assetCount(matching: failureQuery), 1)

        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: failed.id, kind: .focus, value: .score(0.91), confidence: 0.82, provenance: localProvenance)
        ])

        XCTAssertEqual(try repository.allAssets(matching: failureQuery, limit: 10), [])
        XCTAssertEqual(try repository.assetCount(matching: failureQuery), 0)
    }

    func testRecordingEvaluationSignalReplacesSameProviderSignal() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-upsert")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assetID = AssetID(rawValue: "asset-1")
        let provenance = ProviderProvenance(provider: "LocalVision", model: "focus", version: "1", settingsHash: "default")
        let first = EvaluationSignal(
            assetID: assetID,
            kind: .focus,
            value: .score(0.4),
            confidence: 0.5,
            provenance: provenance
        )
        let replacement = EvaluationSignal(
            assetID: assetID,
            kind: .focus,
            value: .score(0.9),
            confidence: 0.8,
            provenance: provenance
        )

        try repository.recordEvaluationSignals([first])
        try repository.recordEvaluationSignals([replacement])

        XCTAssertEqual(try repository.evaluationSignals(assetID: assetID), [replacement])
    }

    func testPersistsAndListsWorkSessionsByRecencyAndStarredState() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-work-sessions")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let older = WorkSession(
            id: WorkSessionID(rawValue: "older"),
            kind: .culling,
            intent: "Cull ceremony",
            title: "Cull Ceremony",
            detail: "Reviewing ceremony picks",
            status: .completed,
            inputSetIDs: [AssetSetID(rawValue: "input")],
            outputSetIDs: [AssetSetID(rawValue: "keepers")],
            completedUnitCount: 4,
            totalUnitCount: 5,
            failureCount: 1,
            starred: true,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = WorkSession(
            id: WorkSessionID(rawValue: "newer"),
            kind: .ingest,
            intent: "Import card",
            title: "Import Photos",
            detail: "Imported 100 photos",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 100,
            totalUnitCount: 100,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 30)
        )

        try repository.save(older)
        try repository.save(newer)

        XCTAssertEqual(try repository.session(id: older.id), older)
        XCTAssertEqual(try repository.workSessions(limit: 2).map(\.id), [newer.id, older.id])
        XCTAssertEqual(try repository.workSessions(limit: 10, starredOnly: true), [older])
    }

    func testFetchesAllAssetsInInsertionOrderWhenCreatedAtTies() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(id: AssetID(rawValue: "z-first"), path: "/Volumes/NAS/Job/a.cr2", rating: 2)
        let second = Asset.testAsset(id: AssetID(rawValue: "a-second"), path: "/Volumes/NAS/Job/b.cr2", rating: 5)
        let createdAt = "10.0"
        try database.insertTestAsset(first, createdAt: createdAt)
        try database.insertTestAsset(second, createdAt: createdAt)

        let assets = try repository.allAssets(limit: 100)

        XCTAssertEqual(assets.map(\.id), [first.id, second.id])
    }

    func testDatabaseRejectsDuplicateOriginalPaths() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(id: AssetID(rawValue: "first"), path: "/Volumes/NAS/Job/a.cr2", rating: 2)
        let duplicate = Asset.testAsset(id: AssetID(rawValue: "second"), path: "/Volumes/NAS/Job/a.cr2", rating: 5)
        try repository.upsert(first)

        XCTAssertThrowsError(try database.insertTestAsset(duplicate, createdAt: "11.0")) { error in
            guard case CatalogError.sqlite = error else {
                return XCTFail("expected sqlite error, got \(error)")
            }
        }
        XCTAssertEqual(try repository.allAssets(limit: 100).map(\.id), [first.id])
    }

    func testBulkUpsertPersistsAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-bulk")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<3).map {
            Asset.testAsset(path: "/Volumes/NAS/Job/frame-\($0).cr2", rating: $0)
        }

        try repository.upsert(assets)

        XCTAssertEqual(try repository.assetCount(), 3)
        XCTAssertEqual(try repository.allAssets(limit: 10).map(\.originalURL.path), assets.map(\.originalURL.path))
    }

    func testBulkUpsertRollsBackWhenAnyAssetFails() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-bulk-rollback")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(id: AssetID(rawValue: "first"), path: "/Volumes/NAS/Job/duplicate.cr2", rating: 1)
        let duplicate = Asset.testAsset(id: AssetID(rawValue: "second"), path: "/Volumes/NAS/Job/duplicate.cr2", rating: 2)

        XCTAssertThrowsError(try repository.upsert([first, duplicate])) { error in
            guard case CatalogError.sqlite = error else {
                return XCTFail("expected sqlite error, got \(error)")
            }
        }
        XCTAssertEqual(try repository.assetCount(), 0)
    }

    func testRowsThrowsWhenSQLiteStepFails() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))

        XCTAssertThrowsError(try database.rows("SELECT abs(-9223372036854775808)")) { error in
            guard case CatalogError.sqlite = error else {
                return XCTFail("expected sqlite error, got \(error)")
            }
        }
    }
}

private extension Asset {
    static func testAsset(
        id: AssetID = .new(),
        path: String,
        rating: Int,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        testAsset(
            id: id,
            path: path,
            metadata: AssetMetadata(rating: rating),
            technicalMetadata: technicalMetadata
        )
    }

    static func testAsset(
        id: AssetID = .new(),
        path: String,
        metadata: AssetMetadata,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: id,
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1.25), contentHash: "hash"),
            availability: .online,
            metadata: metadata,
            technicalMetadata: technicalMetadata
        )
    }
}

private extension CatalogDatabase {
    func insertTestAsset(_ asset: Asset, createdAt: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try execute(
            """
            INSERT INTO assets (id, original_path, volume_identifier, fingerprint_json, availability, metadata_json, catalog_generation, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
            """,
            bindings: [
                asset.id.rawValue,
                asset.originalURL.path,
                asset.volumeIdentifier ?? "",
                String(data: try encoder.encode(asset.fingerprint), encoding: .utf8)!,
                asset.availability.rawValue,
                String(data: try encoder.encode(asset.metadata), encoding: .utf8)!,
                createdAt,
                createdAt
            ]
        )
    }
}
