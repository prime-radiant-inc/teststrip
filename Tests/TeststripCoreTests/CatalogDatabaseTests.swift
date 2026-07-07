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

    func testPersistsApertureShutterSpeedAndFocalLengthThroughExistingTechnicalMetadataStorage() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-metadata-exif")
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
            aperture: 2.8,
            shutterSpeed: 1.0 / 250.0,
            focalLength: 85,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
        let asset = Asset.testAsset(
            path: "/Volumes/NAS/Job/frame-exif.cr2",
            rating: 3,
            technicalMetadata: technicalMetadata
        )

        try repository.upsert(asset)

        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.technicalMetadata, technicalMetadata)
    }

    func testPersistsGPSCoordinatesThroughExistingTechnicalMetadataStorage() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-metadata-gps")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let technicalMetadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            latitude: 37.8199,
            longitude: -122.4783,
            altitude: 67.5,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 3, technicalMetadata: technicalMetadata)

        try repository.upsert(asset)

        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.technicalMetadata?.latitude, 37.8199)
        XCTAssertEqual(fetched.technicalMetadata?.longitude, -122.4783)
        XCTAssertEqual(fetched.technicalMetadata?.altitude, 67.5)
        XCTAssertEqual(fetched.technicalMetadata, technicalMetadata)
    }

    func testWithinGeoBoundsPredicateFiltersByCoordinate() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geo-bounds")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        func asset(_ name: String, latitude: Double, longitude: Double) -> Asset {
            Asset.testAsset(
                path: "/Volumes/NAS/\(name).cr2",
                rating: 0,
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 100, pixelHeight: 100,
                    latitude: latitude, longitude: longitude,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            )
        }
        try repository.upsert(asset("sf", latitude: 37.77, longitude: -122.42))
        try repository.upsert(asset("oakland", latitude: 37.80, longitude: -122.27))
        try repository.upsert(asset("sydney", latitude: -33.87, longitude: 151.21))
        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/no-gps.cr2", rating: 0))

        let bayArea = GeoBounds(minLatitude: 37.5, maxLatitude: 38.0, minLongitude: -122.6, maxLongitude: -122.2)
        let count = try repository.assetCount(matching: SetQuery(predicates: [.withinGeoBounds(bayArea)]))

        XCTAssertEqual(count, 2)
    }

    func testGeoBoundsQueryUsesCoordinateExpressionIndex() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geo-index")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()

        let plan = try database.rows(
            """
            EXPLAIN QUERY PLAN
            SELECT COUNT(*) FROM assets
            WHERE json_valid(technical_metadata_json)
              AND \(CatalogRepository.latitudeExpressionSQL) BETWEEN -1 AND 1
              AND \(CatalogRepository.longitudeExpressionSQL) BETWEEN -1 AND 1
            """
        )
        let detail = plan.compactMap { $0["detail"] }.joined(separator: " ")
        XCTAssertTrue(detail.contains("idx_assets_gps"), "expected the geo expression index, got: \(detail)")
    }

    // Proves the audit's no-migration claim: `technical_metadata_json` is a JSON blob
    // decoded into AssetTechnicalMetadata, and the new aperture/shutterSpeed/focalLength
    // fields are optional, so a row written before this change (missing those keys
    // entirely) still decodes cleanly with the new fields as nil.
    func testDecodesLegacyTechnicalMetadataJSONMissingApertureShutterAndFocalLengthKeys() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-metadata-legacy-json")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/legacy-exif.cr2", rating: 1)
        try repository.upsert(asset)
        let legacyTechnicalMetadataJSON = """
        {"pixelWidth":6000,"pixelHeight":4000,"cameraMake":"Canon","cameraModel":"EOS R5",\
        "lensModel":"RF 50mm F1.2L USM","isoSpeed":800,"capturedAt":1800000000,\
        "provenance":{"provider":"ImageIO","model":"ImageIO","version":"1","settingsHash":"default"}}
        """

        try database.execute(
            "UPDATE assets SET technical_metadata_json = ? WHERE id = ?",
            bindings: [legacyTechnicalMetadataJSON, asset.id.rawValue]
        )

        let fetched = try repository.asset(id: asset.id)

        XCTAssertEqual(fetched.technicalMetadata?.cameraMake, "Canon")
        XCTAssertEqual(fetched.technicalMetadata?.isoSpeed, 800)
        XCTAssertNil(fetched.technicalMetadata?.aperture)
        XCTAssertNil(fetched.technicalMetadata?.shutterSpeed)
        XCTAssertNil(fetched.technicalMetadata?.focalLength)
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

    func testReupsertingDecodedAssetKeepsCatalogGenerationAndCanonicalMetadataJSON() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-generation-roundtrip")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 4)
        try repository.upsert(asset)

        // Re-upserting an asset decoded from the catalog must never look like a
        // metadata edit: encoding has to be byte-stable across decode round trips
        // or reconnect/availability refreshes spuriously bump the generation and
        // create false XMP conflicts.
        let storedJSON = try XCTUnwrap(
            try database.rows(
                "SELECT metadata_json FROM assets WHERE id = ?",
                bindings: [asset.id.rawValue]
            ).first?["metadata_json"]
        )
        XCTAssertEqual(storedJSON, #"{"keywords":[],"rating":4}"#)

        let decoded = try repository.asset(id: asset.id)
        try repository.upsert(decoded)

        XCTAssertEqual(try repository.catalogGeneration(assetID: asset.id), 1)
    }

    func testReupsertingLegacyUnsortedMetadataJSONKeepsCatalogGeneration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-generation-legacy-key-order")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 4)
        try repository.upsert(asset)
        // Catalogs written before the sorted-keys encoder hold metadata_json in
        // per-process-random key order; re-upserting an unchanged asset must
        // not read as a metadata edit just because today's canonical text
        // differs from the legacy key order.
        try database.execute(
            "UPDATE assets SET metadata_json = ? WHERE id = ?",
            bindings: [#"{"rating":4,"keywords":[]}"#, asset.id.rawValue]
        )

        let decoded = try repository.asset(id: asset.id)
        try repository.upsert(decoded)

        XCTAssertEqual(try repository.catalogGeneration(assetID: asset.id), 1)
        let storedJSON = try XCTUnwrap(
            try database.rows(
                "SELECT metadata_json FROM assets WHERE id = ?",
                bindings: [asset.id.rawValue]
            ).first?["metadata_json"]
        )
        XCTAssertEqual(storedJSON, #"{"keywords":[],"rating":4}"#)
    }

    func testEditingAssetWithLegacyUnsortedMetadataJSONStillBumpsCatalogGeneration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-generation-legacy-key-order-edit")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 4)
        try repository.upsert(asset)
        try database.execute(
            "UPDATE assets SET metadata_json = ? WHERE id = ?",
            bindings: [#"{"rating":4,"keywords":[]}"#, asset.id.rawValue]
        )

        try repository.updateMetadata(assetID: asset.id) { metadata in
            metadata.rating = 5
        }

        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try repository.catalogGeneration(assetID: asset.id), 2)
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

    func testFetchesAllAssetsSortedByNewestCaptureTimeWithUndatedAssetsLast() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-capture-sort")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let old = Asset.testAsset(
            id: AssetID(rawValue: "old"),
            path: "/Volumes/NAS/Job/b.cr2",
            rating: 3,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 100))
        )
        let newestLaterPath = Asset.testAsset(
            id: AssetID(rawValue: "newest-later-path"),
            path: "/Volumes/NAS/Job/c.cr2",
            rating: 4,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 300))
        )
        let undated = Asset.testAsset(
            id: AssetID(rawValue: "undated"),
            path: "/Volumes/NAS/Job/z.cr2",
            rating: 5
        )
        let newestEarlierPath = Asset.testAsset(
            id: AssetID(rawValue: "newest-earlier-path"),
            path: "/Volumes/NAS/Job/a.cr2",
            rating: 5,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 300))
        )
        try repository.upsert([old, newestLaterPath, undated, newestEarlierPath])

        let assets = try repository.allAssets(limit: 100, sort: .captureTimeNewestFirst)

        XCTAssertEqual(assets.map(\.id), [
            newestEarlierPath.id,
            newestLaterPath.id,
            old.id,
            undated.id
        ])
    }

    func testFetchesFilteredAssetsUsingSelectedSortOrder() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-filtered-sort")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let matchingOld = Asset.testAsset(
            id: AssetID(rawValue: "matching-old"),
            path: "/Volumes/NAS/Job/old.cr2",
            rating: 4,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 100))
        )
        let matchingNew = Asset.testAsset(
            id: AssetID(rawValue: "matching-new"),
            path: "/Volumes/NAS/Job/new.cr2",
            rating: 5,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 200))
        )
        let filteredOut = Asset.testAsset(
            id: AssetID(rawValue: "filtered-out"),
            path: "/Volumes/NAS/Job/filtered.cr2",
            rating: 1,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 300))
        )
        try repository.upsert([matchingOld, matchingNew, filteredOut])

        let assets = try repository.allAssets(
            matching: SetQuery(predicates: [.ratingAtLeast(4)]),
            limit: 100,
            sort: .captureTimeOldestFirst
        )

        XCTAssertEqual(assets.map(\.id), [matchingOld.id, matchingNew.id])
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

    func testSourceRootsPersistSecurityScopedBookmarkData() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-source-root-bookmark")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let sourceRoot = URL(fileURLWithPath: "/Volumes/NAS/Job", isDirectory: true)
        let bookmarkData = Data("bookmark-data".utf8)

        try repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
        let reopenedDatabase = try CatalogDatabase.open(at: catalogURL)
        try reopenedDatabase.migrate()
        let reopenedRepository = CatalogRepository(database: reopenedDatabase)

        XCTAssertEqual(try reopenedRepository.sourceRoots().first?.securityScopedBookmarkData, bookmarkData)
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

    func testPreviewGenerationFailureAssetCountCountsDistinctFailedAssetsInScope() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-failure-count")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let failedBothLevels = AssetID(rawValue: "failed-both-levels")
        let failedGridOnly = AssetID(rawValue: "failed-grid-only")
        let pendingOnly = AssetID(rawValue: "pending-only")
        let failedOutsideScope = AssetID(rawValue: "failed-outside-scope")

        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: failedBothLevels, level: .micro))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: failedBothLevels, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: failedGridOnly, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: pendingOnly, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: failedOutsideScope, level: .grid))
        try repository.recordPreviewGenerationFailure(
            assetID: failedBothLevels,
            level: .micro,
            errorMessage: "could not render micro preview"
        )
        try repository.recordPreviewGenerationFailure(
            assetID: failedBothLevels,
            level: .grid,
            errorMessage: "could not render grid preview"
        )
        try repository.recordPreviewGenerationFailure(
            assetID: failedGridOnly,
            level: .grid,
            errorMessage: "could not render grid preview"
        )
        try repository.recordPreviewGenerationFailure(
            assetID: failedOutsideScope,
            level: .grid,
            errorMessage: "outside current import"
        )

        let count = try repository.previewGenerationFailureAssetCount(assetIDs: [
            failedBothLevels,
            failedGridOnly,
            pendingOnly
        ])

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try repository.previewGenerationFailureAssetCount(assetIDs: []), 0)
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

    func testPendingPreviewGenerationItemsCanRequireAvailableOriginals() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-preview-queue-available-originals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let online = Asset.testAsset(id: AssetID(rawValue: "online"), path: "/Photos/online.jpg", rating: 0)
        var stale = Asset.testAsset(id: AssetID(rawValue: "stale"), path: "/Photos/stale.jpg", rating: 0)
        var offline = Asset.testAsset(id: AssetID(rawValue: "offline"), path: "/Volumes/NAS/offline.jpg", rating: 0)
        var missing = Asset.testAsset(id: AssetID(rawValue: "missing"), path: "/Photos/missing.jpg", rating: 0)
        var moved = Asset.testAsset(id: AssetID(rawValue: "moved"), path: "/Photos/moved.jpg", rating: 0)
        stale.availability = .stale
        offline.availability = .offline
        missing.availability = .missing
        moved.availability = .moved
        try repository.upsert([offline, missing, moved, online, stale])
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: offline.id, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: missing.id, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: moved.id, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: online.id, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: stale.id, level: .grid))

        let runnableItems = try repository.pendingPreviewGenerationItems(requiresAvailableOriginal: true)

        XCTAssertEqual(runnableItems.map(\.assetID), [online.id, stale.id])
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
        XCTAssertEqual(
            try repository.assetIDs(ids: [reject.id, landscape.id, keeper.id], matching: pickQuery),
            [keeper.id]
        )

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

    func testCatalogFoldersAreAggregatedInDatabase() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-folders-aggregate-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([
            Asset.testAsset(id: AssetID(rawValue: "ceremony-1"), path: "/Volumes/NAS/Wedding/Ceremony/frame-1.jpg", rating: 0),
            Asset.testAsset(id: AssetID(rawValue: "ceremony-2"), path: "/Volumes/NAS/Wedding/Ceremony/frame-2.jpg", rating: 0),
            Asset.testAsset(id: AssetID(rawValue: "travel"), path: "/Volumes/NAS/Travel/frame-3.jpg", rating: 0)
        ])
        var rowQueries: [String] = []
        database.rowQueryObserver = { sql in
            rowQueries.append(sql.replacingOccurrences(of: "\n", with: " "))
        }

        XCTAssertEqual(try repository.folders(), [
            CatalogFolder(path: "/Volumes/NAS/Travel/", name: "Travel", assetCount: 1),
            CatalogFolder(path: "/Volumes/NAS/Wedding/Ceremony/", name: "Ceremony", assetCount: 2)
        ])
        let folderQuery = try XCTUnwrap(rowQueries.first)
        XCTAssertTrue(folderQuery.contains("COUNT(*) AS asset_count"))
        XCTAssertTrue(folderQuery.contains("GROUP BY folder_path"))
        XCTAssertFalse(folderQuery.contains("SELECT original_path FROM assets"))
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
            EvaluationSignal(assetID: portrait.id, kind: .object, value: .labels(["mountain", "alpine lake"]), confidence: 0.78, provenance: ProviderProvenance(provider: "apple-vision", model: "Vision-labels", version: "1", settingsHash: "default")),
            EvaluationSignal(assetID: document.id, kind: .ocrText, value: .text("Invoice 123\nTotal 45"), confidence: 1.0, provenance: provenance)
        ])

        let labelQuery = SetQuery(predicates: [.text("PORTRAIT")])
        XCTAssertEqual(try repository.allAssets(matching: labelQuery, limit: 10).map(\.id), [portrait.id])
        XCTAssertEqual(try repository.assetCount(matching: labelQuery), 1)

        let ocrQuery = SetQuery(predicates: [.text("invoice 123")])
        XCTAssertEqual(try repository.allAssets(matching: ocrQuery, limit: 10).map(\.id), [document.id])

        let multiLabelQuery = SetQuery(predicates: [.text("alpine lake")])
        XCTAssertEqual(try repository.allAssets(matching: multiLabelQuery, limit: 10).map(\.id), [portrait.id])
        XCTAssertEqual(try repository.assetCount(matching: multiLabelQuery), 1)
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

    func testSearchesAssetsWithPersonPredicateCaseInsensitively() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-person-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let confirmed = Asset.testAsset(id: AssetID(rawValue: "confirmed"), path: "/Volumes/NAS/Job/confirmed.jpg", rating: 0)
        let unconfirmedFace = Asset.testAsset(id: AssetID(rawValue: "unconfirmed-face"), path: "/Volumes/NAS/Job/unconfirmed-face.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([confirmed, unconfirmedFace])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: unconfirmedFace.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance)
        ])
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignAssets([confirmed.id], toPersonID: "person-maya")

        let personQuery = SetQuery(predicates: [.person("maya")])
        XCTAssertEqual(try repository.allAssets(matching: personQuery, limit: 10).map(\.id), [confirmed.id])
        XCTAssertEqual(try repository.assetCount(matching: personQuery), 1)

        let unknownQuery = SetQuery(predicates: [.person("Anna")])
        XCTAssertEqual(try repository.allAssets(matching: unknownQuery, limit: 10).map(\.id), [])

        let blankQuery = SetQuery(predicates: [.person("   ")])
        XCTAssertEqual(try repository.assetCount(matching: blankQuery), 2)
    }

    func testPersonPredicatesIntersectAndComposeWithMetadataPredicates() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-person-intersection")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let bothPicked = Asset.testAsset(
            id: AssetID(rawValue: "both-picked"),
            path: "/Volumes/NAS/Job/both-picked.jpg",
            metadata: AssetMetadata(rating: 5, flag: .pick)
        )
        let bothUnrated = Asset.testAsset(
            id: AssetID(rawValue: "both-unrated"),
            path: "/Volumes/NAS/Job/both-unrated.jpg",
            metadata: AssetMetadata(rating: 0)
        )
        let annaOnly = Asset.testAsset(
            id: AssetID(rawValue: "anna-only"),
            path: "/Volumes/NAS/Job/anna-only.jpg",
            metadata: AssetMetadata(rating: 5, flag: .pick)
        )
        try repository.upsert([bothPicked, bothUnrated, annaOnly])
        try repository.upsertPerson(id: "person-anna", name: "Anna")
        try repository.upsertPerson(id: "person-ben", name: "Ben")
        try repository.assignAssets([bothPicked.id, bothUnrated.id, annaOnly.id], toPersonID: "person-anna")
        try repository.assignAssets([bothPicked.id, bothUnrated.id], toPersonID: "person-ben")

        let intersectionQuery = SetQuery(predicates: [.person("Anna"), .person("Ben")])
        XCTAssertEqual(
            try repository.allAssets(matching: intersectionQuery, limit: 10).map(\.id),
            [bothPicked.id, bothUnrated.id]
        )

        let composedQuery = SetQuery(predicates: [.person("Anna"), .person("Ben"), .ratingAtLeast(4), .flag(.pick)])
        XCTAssertEqual(try repository.allAssets(matching: composedQuery, limit: 10).map(\.id), [bothPicked.id])
        XCTAssertEqual(try repository.assetCount(matching: composedQuery), 1)
    }

    func testDynamicSetWithPersonPredicatePersistsAndResolvesMembers() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-person-dynamic-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let confirmed = Asset.testAsset(id: AssetID(rawValue: "confirmed"), path: "/Volumes/NAS/Job/confirmed.jpg", rating: 0)
        let other = Asset.testAsset(id: AssetID(rawValue: "other"), path: "/Volumes/NAS/Job/other.jpg", rating: 0)
        try repository.upsert([confirmed, other])
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignAssets([confirmed.id], toPersonID: "person-maya")

        let set = AssetSet.dynamic(
            id: AssetSetID(rawValue: "set-maya"),
            name: "Maya",
            query: SetQuery(predicates: [.person("Maya")])
        )
        try repository.upsert(set)

        let loaded = try repository.assetSet(id: set.id)
        XCTAssertEqual(loaded.membership, .dynamic(SetQuery(predicates: [.person("Maya")])))
        XCTAssertEqual(try repository.assetIDs(matching: SetQuery(predicates: [.person("Maya")])), [confirmed.id])
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

    func testPersistsNamedPeopleAndAssetAssignments() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-people")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(id: AssetID(rawValue: "first"), path: "/Volumes/NAS/Job/first.jpg", rating: 0)
        let second = Asset.testAsset(id: AssetID(rawValue: "second"), path: "/Volumes/NAS/Job/second.jpg", rating: 0)
        try repository.upsert([first, second])

        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignAssets([first.id, second.id], toPersonID: "person-maya")

        XCTAssertEqual(try repository.people(), [
            CatalogPerson(id: "person-maya", name: "Maya", assetCount: 2)
        ])
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [first.id, second.id])
    }

    func testMergesPeopleWithoutDuplicatingAssignments() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-people-merge")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let shared = Asset.testAsset(id: AssetID(rawValue: "shared"), path: "/Volumes/NAS/Job/shared.jpg", rating: 0)
        let sourceOnly = Asset.testAsset(id: AssetID(rawValue: "source-only"), path: "/Volumes/NAS/Job/source.jpg", rating: 0)
        try repository.upsert([shared, sourceOnly])
        try repository.upsertPerson(id: "target", name: "Maya")
        try repository.upsertPerson(id: "source", name: "Maya duplicate")
        try repository.assignAssets([shared.id], toPersonID: "target")
        try repository.assignAssets([shared.id, sourceOnly.id], toPersonID: "source")

        try repository.mergePerson(sourceID: "source", into: "target")

        XCTAssertEqual(try repository.people(), [
            CatalogPerson(id: "target", name: "Maya", assetCount: 2)
        ])
        XCTAssertEqual(try repository.assetIDs(personID: "target"), [shared.id, sourceOnly.id])
        XCTAssertEqual(try repository.assetIDs(personID: "source"), [])
    }

    func testDismissingFaceAssetRemovesPersonAssignments() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-dismiss-face")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(id: AssetID(rawValue: "false-positive"), path: "/Volumes/NAS/Job/false-positive.jpg", rating: 0)
        try repository.upsert(asset)
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignAssets([asset.id], toPersonID: "person-maya")

        try repository.dismissFaceAssets([asset.id])

        XCTAssertEqual(try repository.people(), [
            CatalogPerson(id: "person-maya", name: "Maya", assetCount: 0)
        ])
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [])
        XCTAssertEqual(try repository.dismissedFaceAssetIDs(), [asset.id])
    }

    func testDismissingFaceAssetRemovesItFromFaceReviewQueries() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-dismiss-face-review-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let dismissed = Asset.testAsset(id: AssetID(rawValue: "dismissed"), path: "/Volumes/NAS/Job/dismissed.jpg", rating: 0)
        let active = Asset.testAsset(id: AssetID(rawValue: "active"), path: "/Volumes/NAS/Job/active.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([dismissed, active])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: dismissed.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: dismissed.id, kind: .faceQuality, value: .score(0.08), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: active.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: active.id, kind: .faceQuality, value: .score(0.08), confidence: 0.8, provenance: provenance)
        ])

        try repository.dismissFaceAssets([dismissed.id])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.evaluationKind(.faceCount)]), limit: 10).map(\.id),
            [active.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.evaluationKind(.faceQuality)]), limit: 10).map(\.id),
            [active.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            [active.id]
        )
        XCTAssertEqual(try repository.evaluationKindSummaries(), [
            CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 1),
            CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 1)
        ])
        XCTAssertEqual(try repository.evaluationSignals(assetID: dismissed.id).map(\.kind), [.faceCount, .faceQuality])
    }

    func testAssignedPersonAssetRemovesItFromFaceReviewQueries() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-assigned-face-review-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assigned = Asset.testAsset(id: AssetID(rawValue: "assigned"), path: "/Volumes/NAS/Job/assigned.jpg", rating: 0)
        let unnamed = Asset.testAsset(id: AssetID(rawValue: "unnamed"), path: "/Volumes/NAS/Job/unnamed.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([assigned, unnamed])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: assigned.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assigned.id, kind: .faceQuality, value: .score(0.08), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: unnamed.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: unnamed.id, kind: .faceQuality, value: .score(0.08), confidence: 0.8, provenance: provenance)
        ])

        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignAssets([assigned.id], toPersonID: "person-maya")

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.evaluationKind(.faceCount)]), limit: 10).map(\.id),
            [unnamed.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.evaluationKind(.faceQuality)]), limit: 10).map(\.id),
            [unnamed.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            [unnamed.id]
        )
        XCTAssertEqual(try repository.evaluationKindSummaries(), [
            CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 1),
            CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 1)
        ])
        XCTAssertEqual(try repository.evaluationSignals(assetID: assigned.id).map(\.kind), [.faceCount, .faceQuality])
    }

    func testFaceObservationsReplacePerAssetAndProvenance() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-observations")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(id: AssetID(rawValue: "group-frame"), path: "/Volumes/NAS/Job/group-frame.jpg", rating: 0)
        try repository.upsert(asset)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let firstRun = [
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                captureQuality: 0.8,
                embedding: [0.1, 0.2, 0.3],
                provenance: provenance
            ),
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 1,
                boundingBox: FaceBoundingBox(x: 0.6, y: 0.5, width: 0.2, height: 0.25),
                captureQuality: nil,
                embedding: [0.9, 0.8, 0.7],
                provenance: provenance
            )
        ]

        try repository.replaceFaceObservations(assetID: asset.id, provenance: provenance, with: firstRun)

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), firstRun)

        let secondRun = [firstRun[0]]
        try repository.replaceFaceObservations(assetID: asset.id, provenance: provenance, with: secondRun)

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), secondRun)
        XCTAssertEqual(try repository.faceObservations(assetID: AssetID(rawValue: "other")), [])
    }

    func testReplaceFaceObservationsWithChangedFacesClearsConfirmedAndDismissedFaceLinks() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-rescan-cascade")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let confirmed = Asset.testAsset(id: AssetID(rawValue: "confirmed-frame"), path: "/Volumes/NAS/Job/confirmed-frame.jpg", rating: 0)
        let dismissed = Asset.testAsset(id: AssetID(rawValue: "dismissed-frame"), path: "/Volumes/NAS/Job/dismissed-frame.jpg", rating: 0)
        try repository.upsert([confirmed, dismissed])
        let boxA = FaceBoundingBox(x: 0.1, y: 0.2, width: 0.2, height: 0.2)
        let boxB = FaceBoundingBox(x: 0.6, y: 0.5, width: 0.2, height: 0.25)
        func face(_ asset: Asset, _ index: Int, _ box: FaceBoundingBox, _ embedding: [Double]) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: index,
                boundingBox: box,
                captureQuality: 0.5,
                embedding: embedding,
                provenance: provenance
            )
        }
        try repository.replaceFaceObservations(assetID: confirmed.id, provenance: provenance, with: [
            face(confirmed, 0, boxA, [1, 0, 0]),
            face(confirmed, 1, boxB, [0, 1, 0])
        ])
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignFaces([FaceID(assetID: confirmed.id, faceIndex: 1)], toPersonID: "person-maya")
        try repository.replaceFaceObservations(assetID: dismissed.id, provenance: provenance, with: [
            face(dismissed, 0, boxA, [0, 0, 1]),
            face(dismissed, 1, boxB, [0.5, 0, 1])
        ])
        try repository.dismissFaces([FaceID(assetID: dismissed.id, faceIndex: 0)])

        // A re-scan detects the same photos with swapped face order, so the old
        // indexes now point at different faces and the links must be cleared.
        try repository.replaceFaceObservations(assetID: confirmed.id, provenance: provenance, with: [
            face(confirmed, 0, boxB, [0, 1, 0]),
            face(confirmed, 1, boxA, [1, 0, 0])
        ])
        try repository.replaceFaceObservations(assetID: dismissed.id, provenance: provenance, with: [
            face(dismissed, 0, boxB, [0.5, 0, 1]),
            face(dismissed, 1, boxA, [0, 0, 1])
        ])

        XCTAssertEqual(try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance), [:])
        let unassigned = try repository.unassignedFaceObservations(provenance: provenance, limit: 10)
        XCTAssertEqual(Set(unassigned.map(\.faceID)), [
            FaceID(assetID: dismissed.id, faceIndex: 0),
            FaceID(assetID: dismissed.id, faceIndex: 1)
        ])
        // The asset-level assignment does not depend on face indexes and survives.
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [confirmed.id])
    }

    func testReplaceFaceObservationsWithUnchangedFacesKeepsConfirmedAndDismissedFaceLinks() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-rescan-stable")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let frame = Asset.testAsset(id: AssetID(rawValue: "stable-frame"), path: "/Volumes/NAS/Job/stable-frame.jpg", rating: 0)
        try repository.upsert(frame)
        let observations = [
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.2, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [1, 0, 0],
                provenance: provenance
            ),
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 1,
                boundingBox: FaceBoundingBox(x: 0.6, y: 0.5, width: 0.2, height: 0.25),
                captureQuality: 0.5,
                embedding: [0, 1, 0],
                provenance: provenance
            )
        ]
        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: observations)
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignFaces([FaceID(assetID: frame.id, faceIndex: 1)], toPersonID: "person-maya")
        try repository.dismissFaces([FaceID(assetID: frame.id, faceIndex: 0)])

        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: observations)

        XCTAssertEqual(
            try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance),
            ["person-maya": [[0, 1, 0]]]
        )
        XCTAssertEqual(try repository.unassignedFaceObservations(provenance: provenance, limit: 10), [])
    }

    func testUnassignedFaceObservationsExcludeConfirmedDismissedAndAssignedAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-unassigned-faces")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let otherProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "2", settingsHash: "face-crop-pad-25")
        let open = Asset.testAsset(id: AssetID(rawValue: "open"), path: "/Volumes/NAS/Job/open.jpg", rating: 0)
        let confirmed = Asset.testAsset(id: AssetID(rawValue: "confirmed"), path: "/Volumes/NAS/Job/confirmed.jpg", rating: 0)
        let dismissedFace = Asset.testAsset(id: AssetID(rawValue: "dismissed-face"), path: "/Volumes/NAS/Job/dismissed-face.jpg", rating: 0)
        let dismissedAsset = Asset.testAsset(id: AssetID(rawValue: "dismissed-asset"), path: "/Volumes/NAS/Job/dismissed-asset.jpg", rating: 0)
        try repository.upsert([open, confirmed, dismissedFace, dismissedAsset])
        func face(_ asset: Asset, _ index: Int, _ prov: ProviderProvenance = provenance) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: index,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [1, 0, 0],
                provenance: prov
            )
        }
        try repository.replaceFaceObservations(assetID: open.id, provenance: provenance, with: [face(open, 0)])
        try repository.replaceFaceObservations(assetID: open.id, provenance: otherProvenance, with: [face(open, 0, otherProvenance)])
        try repository.replaceFaceObservations(assetID: confirmed.id, provenance: provenance, with: [face(confirmed, 0)])
        try repository.replaceFaceObservations(assetID: dismissedFace.id, provenance: provenance, with: [face(dismissedFace, 0)])
        try repository.replaceFaceObservations(assetID: dismissedAsset.id, provenance: provenance, with: [face(dismissedAsset, 0)])
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignFaces([FaceID(assetID: confirmed.id, faceIndex: 0)], toPersonID: "person-maya")
        try repository.dismissFaces([FaceID(assetID: dismissedFace.id, faceIndex: 0)])
        try repository.dismissFaceAssets([dismissedAsset.id])

        let unassigned = try repository.unassignedFaceObservations(provenance: provenance, limit: 10)

        XCTAssertEqual(unassigned.map(\.faceID), [FaceID(assetID: open.id, faceIndex: 0)])
        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance), 4)
    }

    func testAssignFacesRecordsPersonFacesAndPersonAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-assign-faces")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let frame = Asset.testAsset(id: AssetID(rawValue: "frame"), path: "/Volumes/NAS/Job/frame.jpg", rating: 0)
        try repository.upsert(frame)
        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: [
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [0.6, 0.8, 0],
                provenance: provenance
            )
        ])
        try repository.upsertPerson(id: "person-maya", name: "Maya")

        try repository.assignFaces([FaceID(assetID: frame.id, faceIndex: 0)], toPersonID: "person-maya")

        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [frame.id])
        XCTAssertEqual(
            try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance),
            ["person-maya": [[0.6, 0.8, 0]]]
        )
        XCTAssertEqual(try repository.unassignedFaceObservations(provenance: provenance, limit: 10), [])
    }

    func testAssignFacesToMissingPersonThrowsNotFound() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-assign-faces-missing-person")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let frame = Asset.testAsset(id: AssetID(rawValue: "frame"), path: "/Volumes/NAS/Job/frame.jpg", rating: 0)
        try repository.upsert(frame)
        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: [
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [1, 0, 0],
                provenance: provenance
            )
        ])

        XCTAssertThrowsError(try repository.assignFaces([FaceID(assetID: frame.id, faceIndex: 0)], toPersonID: "person-ghost")) { error in
            XCTAssertEqual(error as? CatalogError, .notFound("person-ghost"))
        }
        XCTAssertEqual(try repository.assetIDs(personID: "person-ghost"), [])
        XCTAssertEqual(
            try repository.unassignedFaceObservations(provenance: provenance, limit: 10).map(\.faceID),
            [FaceID(assetID: frame.id, faceIndex: 0)]
        )
    }

    func testAssignAssetsToMissingPersonThrowsNotFound() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-assign-assets-missing-person")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let frame = Asset.testAsset(id: AssetID(rawValue: "frame"), path: "/Volumes/NAS/Job/frame.jpg", rating: 0)
        try repository.upsert(frame)
        try repository.dismissFaceAssets([frame.id])

        XCTAssertThrowsError(try repository.assignAssets([frame.id], toPersonID: "person-ghost")) { error in
            XCTAssertEqual(error as? CatalogError, .notFound("person-ghost"))
        }
        XCTAssertEqual(try repository.assetIDs(personID: "person-ghost"), [])
        XCTAssertEqual(try repository.dismissedFaceAssetIDs(), [frame.id])
    }

    func testMergePersonMovesConfirmedFacesAndDismissFaceAssetsClearsThem() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-merge-dismiss")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "face-crop-pad-25")
        let frame = Asset.testAsset(id: AssetID(rawValue: "frame"), path: "/Volumes/NAS/Job/frame.jpg", rating: 0)
        try repository.upsert(frame)
        try repository.replaceFaceObservations(assetID: frame.id, provenance: provenance, with: [
            CatalogFaceObservation(
                assetID: frame.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.5,
                embedding: [1, 0, 0],
                provenance: provenance
            )
        ])
        try repository.upsertPerson(id: "source", name: "Maya duplicate")
        try repository.upsertPerson(id: "target", name: "Maya")
        try repository.assignFaces([FaceID(assetID: frame.id, faceIndex: 0)], toPersonID: "source")

        try repository.mergePerson(sourceID: "source", into: "target")

        XCTAssertEqual(
            try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance),
            ["target": [[1, 0, 0]]]
        )

        try repository.dismissFaceAssets([frame.id])

        XCTAssertEqual(try repository.confirmedFaceEmbeddingsByPerson(provenance: provenance), [:])
    }

    func testEyesClosedSignalJoinsLikelyIssueQueue() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-eyes-closed-likely-issue")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let closed = Asset.testAsset(id: AssetID(rawValue: "closed"), path: "/Volumes/NAS/Job/closed.jpg", rating: 0)
        let open = Asset.testAsset(id: AssetID(rawValue: "open"), path: "/Volumes/NAS/Job/open.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "1", settingsHash: "default")
        try repository.upsert([closed, open])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: closed.id, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: open.id, kind: .eyesOpen, value: .score(1.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            [closed.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.evaluationKind(.eyesOpen)]), limit: 10)
                .map(\.id.rawValue)
                .sorted(),
            ["closed", "open"]
        )
    }

    func testLikelyPickMatchesStrongUnflaggedFramesWithoutDefects() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-pick")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let strong = Asset.testAsset(id: AssetID(rawValue: "strong"), path: "/Volumes/NAS/Job/strong.jpg", rating: 0)
        let soft = Asset.testAsset(id: AssetID(rawValue: "soft"), path: "/Volumes/NAS/Job/soft.jpg", rating: 0)
        let strongButBlownOut = Asset.testAsset(id: AssetID(rawValue: "strong-blown-out"), path: "/Volumes/NAS/Job/strong-blown-out.jpg", rating: 0)
        let alreadyPicked = Asset.testAsset(
            id: AssetID(rawValue: "already-picked"),
            path: "/Volumes/NAS/Job/already-picked.jpg",
            metadata: AssetMetadata(flag: .pick)
        )
        let unread = Asset.testAsset(id: AssetID(rawValue: "unread"), path: "/Volumes/NAS/Job/unread.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.upsert([strong, soft, strongButBlownOut, alreadyPicked, unread])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: strong.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: soft.id, kind: .focus, value: .score(0.55), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: strongButBlownOut.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: strongButBlownOut.id, kind: .exposure, value: .score(0.95), confidence: 1.0, provenance: provenance),
            EvaluationSignal(assetID: alreadyPicked.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10).map(\.id),
            [strong.id]
        )
    }

    func testLikelyIssueUsesCalibratedDefectTerms() throws {
        // Defect anchors from the 2026-07-06 calibration study:
        // - focus defect at the calibrated p5 (study raw 0.06 / 0.15 = 0.4);
        //   the old 0.5 sits at ~p25 calibrated and over-flags.
        // - motionBlur is exactly 1 - focus: zero independent information,
        //   so it is no longer a defect term at all.
        // - fractional eyesOpen is CIDetector noise on tiny/occluded faces
        //   (it flips between renders of identical frames); only 0.0 - all
        //   eyes shut - stays a defect.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-issue-calibrated")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let softFocus = Asset.testAsset(id: AssetID(rawValue: "soft-focus"), path: "/Volumes/NAS/Job/soft-focus.jpg", rating: 0)
        let midFocus = Asset.testAsset(id: AssetID(rawValue: "mid-focus"), path: "/Volumes/NAS/Job/mid-focus.jpg", rating: 0)
        let blurOnly = Asset.testAsset(id: AssetID(rawValue: "blur-only"), path: "/Volumes/NAS/Job/blur-only.jpg", rating: 0)
        let partialBlink = Asset.testAsset(id: AssetID(rawValue: "partial-blink"), path: "/Volumes/NAS/Job/partial-blink.jpg", rating: 0)
        let allShut = Asset.testAsset(id: AssetID(rawValue: "all-shut"), path: "/Volumes/NAS/Job/all-shut.jpg", rating: 0)
        let metricsProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        let facesProvenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "2", settingsHash: "default")
        try repository.upsert([softFocus, midFocus, blurOnly, partialBlink, allShut])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: softFocus.id, kind: .focus, value: .score(0.35), confidence: 0.9, provenance: metricsProvenance),
            EvaluationSignal(assetID: midFocus.id, kind: .focus, value: .score(0.45), confidence: 0.9, provenance: metricsProvenance),
            EvaluationSignal(assetID: blurOnly.id, kind: .motionBlur, value: .score(0.9), confidence: 0.7, provenance: metricsProvenance),
            EvaluationSignal(assetID: partialBlink.id, kind: .eyesOpen, value: .score(0.5), confidence: 0.7, provenance: facesProvenance),
            EvaluationSignal(assetID: allShut.id, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: facesProvenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10)
                .map(\.id.rawValue)
                .sorted(),
            ["all-shut", "soft-focus"]
        )
    }

    func testLikelyPickToleratesNoisyDefectSignalsButExcludesRealDefects() throws {
        // Same calibrated defect terms on the likelyPick exclusion side:
        // partial blinks and the redundant motionBlur read no longer
        // disqualify a strong frame; all-eyes-shut and bottom-p5 focus do.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-pick-calibrated-defects")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let partialBlinkPick = Asset.testAsset(id: AssetID(rawValue: "partial-blink-pick"), path: "/Volumes/NAS/Job/partial-blink-pick.jpg", rating: 0)
        let midFocusFacePick = Asset.testAsset(id: AssetID(rawValue: "mid-focus-face-pick"), path: "/Volumes/NAS/Job/mid-focus-face-pick.jpg", rating: 0)
        let allShutFace = Asset.testAsset(id: AssetID(rawValue: "all-shut-face"), path: "/Volumes/NAS/Job/all-shut-face.jpg", rating: 0)
        let softFocusFace = Asset.testAsset(id: AssetID(rawValue: "soft-focus-face"), path: "/Volumes/NAS/Job/soft-focus-face.jpg", rating: 0)
        let metricsProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        let facesProvenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "2", settingsHash: "default")
        let visionProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([partialBlinkPick, midFocusFacePick, allShutFace, softFocusFace])
        try repository.recordEvaluationSignals([
            // Sharp frame where one background face reads half-blinked.
            EvaluationSignal(assetID: partialBlinkPick.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: metricsProvenance),
            EvaluationSignal(assetID: partialBlinkPick.id, kind: .eyesOpen, value: .score(0.5), confidence: 0.7, provenance: facesProvenance),
            // Strong face frame at ~p20 calibrated focus: above the p5 defect
            // floor, and its 1 - focus motionBlur read must not disqualify it.
            EvaluationSignal(assetID: midFocusFacePick.id, kind: .faceQuality, value: .score(0.5), confidence: 0.5, provenance: visionProvenance),
            EvaluationSignal(assetID: midFocusFacePick.id, kind: .focus, value: .score(0.45), confidence: 0.9, provenance: metricsProvenance),
            EvaluationSignal(assetID: midFocusFacePick.id, kind: .motionBlur, value: .score(0.55), confidence: 0.7, provenance: metricsProvenance),
            // Strong face frame, but every subject's eyes are shut.
            EvaluationSignal(assetID: allShutFace.id, kind: .faceQuality, value: .score(0.5), confidence: 0.5, provenance: visionProvenance),
            EvaluationSignal(assetID: allShutFace.id, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: facesProvenance),
            // Strong face frame below the calibrated p5 focus floor.
            EvaluationSignal(assetID: softFocusFace.id, kind: .faceQuality, value: .score(0.5), confidence: 0.5, provenance: visionProvenance),
            EvaluationSignal(assetID: softFocusFace.id, kind: .focus, value: .score(0.35), confidence: 0.9, provenance: metricsProvenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10)
                .map(\.id.rawValue)
                .sorted(),
            ["mid-focus-face-pick", "partial-blink-pick"]
        )
    }

    func testLikelyPickUsesPerKindStrongReadThresholds() throws {
        // Per-kind anchors from the 2026-07-06 calibration study: the three
        // strong-read kinds live on incompatible scales, so a shared 0.65
        // cannot work. Calibrated focus >= 0.8 (raw p75 0.12 / 0.15),
        // aesthetics >= 0.65 (calibrated p90), faceQuality >= 0.45 (p75).
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-pick-per-kind")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let sharpFocus = Asset.testAsset(id: AssetID(rawValue: "sharp-focus"), path: "/Volumes/NAS/Job/sharp-focus.jpg", rating: 0)
        let midFocus = Asset.testAsset(id: AssetID(rawValue: "mid-focus"), path: "/Volumes/NAS/Job/mid-focus.jpg", rating: 0)
        let strongFace = Asset.testAsset(id: AssetID(rawValue: "strong-face"), path: "/Volumes/NAS/Job/strong-face.jpg", rating: 0)
        let weakFace = Asset.testAsset(id: AssetID(rawValue: "weak-face"), path: "/Volumes/NAS/Job/weak-face.jpg", rating: 0)
        let strongAesthetics = Asset.testAsset(id: AssetID(rawValue: "strong-aesthetics"), path: "/Volumes/NAS/Job/strong-aesthetics.jpg", rating: 0)
        let midAesthetics = Asset.testAsset(id: AssetID(rawValue: "mid-aesthetics"), path: "/Volumes/NAS/Job/mid-aesthetics.jpg", rating: 0)
        let metricsProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        let visionProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([sharpFocus, midFocus, strongFace, weakFace, strongAesthetics, midAesthetics])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: sharpFocus.id, kind: .focus, value: .score(0.85), confidence: 0.9, provenance: metricsProvenance),
            EvaluationSignal(assetID: midFocus.id, kind: .focus, value: .score(0.7), confidence: 0.9, provenance: metricsProvenance),
            EvaluationSignal(assetID: strongFace.id, kind: .faceQuality, value: .score(0.5), confidence: 0.5, provenance: visionProvenance),
            EvaluationSignal(assetID: weakFace.id, kind: .faceQuality, value: .score(0.4), confidence: 0.4, provenance: visionProvenance),
            EvaluationSignal(assetID: strongAesthetics.id, kind: .aesthetics, value: .score(0.66), confidence: 0.55, provenance: metricsProvenance),
            EvaluationSignal(assetID: midAesthetics.id, kind: .aesthetics, value: .score(0.6), confidence: 0.55, provenance: metricsProvenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10)
                .map(\.id.rawValue)
                .sorted(),
            ["sharp-focus", "strong-aesthetics", "strong-face"]
        )
    }

    func testLikelyIssueIgnoresRawScaleFocusRowsFromSupersededProviderVersion() throws {
        // Version-1 local-image-metrics focus rows are raw luminance deltas
        // (0.044-0.148 on the study corpus), all below the calibrated 0.4
        // defect anchor. Reading them would flag every asset evaluated
        // before the calibration, so superseded-version focus-family rows
        // must be invisible to the queue.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-issue-raw-scale")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let rawOnly = Asset.testAsset(id: AssetID(rawValue: "raw-only"), path: "/Volumes/NAS/Job/raw-only.jpg", rating: 0)
        let calibratedSoft = Asset.testAsset(id: AssetID(rawValue: "calibrated-soft"), path: "/Volumes/NAS/Job/calibrated-soft.jpg", rating: 0)
        let rawProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "1", settingsHash: "default")
        let calibratedProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        try repository.upsert([rawOnly, calibratedSoft])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: rawOnly.id, kind: .focus, value: .score(0.09), confidence: 1.0, provenance: rawProvenance),
            EvaluationSignal(assetID: calibratedSoft.id, kind: .focus, value: .score(0.35), confidence: 1.0, provenance: calibratedProvenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            [calibratedSoft.id]
        )
    }

    func testLikelyPickDefectExclusionIgnoresRawScaleFocusRows() throws {
        // A stale raw-scale focus row (always <= 0.148) must not permanently
        // veto an asset out of Potential Picks; a current-scale focus defect
        // still must.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-likely-pick-raw-scale")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let staleVeto = Asset.testAsset(id: AssetID(rawValue: "stale-veto"), path: "/Volumes/NAS/Job/stale-veto.jpg", rating: 0)
        let realDefect = Asset.testAsset(id: AssetID(rawValue: "real-defect"), path: "/Volumes/NAS/Job/real-defect.jpg", rating: 0)
        let rawProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "1", settingsHash: "default")
        let calibratedProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        try repository.upsert([staleVeto, realDefect])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: staleVeto.id, kind: .focus, value: .score(0.09), confidence: 1.0, provenance: rawProvenance),
            EvaluationSignal(assetID: staleVeto.id, kind: .aesthetics, value: .score(0.7), confidence: 0.55, provenance: calibratedProvenance),
            EvaluationSignal(assetID: realDefect.id, kind: .focus, value: .score(0.3), confidence: 1.0, provenance: calibratedProvenance),
            EvaluationSignal(assetID: realDefect.id, kind: .aesthetics, value: .score(0.7), confidence: 0.55, provenance: calibratedProvenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10).map(\.id),
            [staleVeto.id]
        )
    }

    func testReEvaluationDeletesSupersededVersionRowsForSameKindAndProvider() throws {
        // The primary key includes version, so a bare upsert would leave one
        // row per version forever. Recording a signal must delete the same
        // provider's rows for that kind at other versions, and the repaired
        // asset must land in the right queues.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-reevaluation-prunes-versions")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(id: AssetID(rawValue: "re-evaluated"), path: "/Volumes/NAS/Job/re-evaluated.jpg", rating: 0)
        let rawProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "1", settingsHash: "default")
        let calibratedProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        try repository.upsert(asset)
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .focus, value: .score(0.09), confidence: 1.0, provenance: rawProvenance),
            EvaluationSignal(assetID: asset.id, kind: .exposure, value: .score(0.5), confidence: 1.0, provenance: rawProvenance)
        ])

        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .focus, value: .score(0.9), confidence: 1.0, provenance: calibratedProvenance),
            EvaluationSignal(assetID: asset.id, kind: .exposure, value: .score(0.5), confidence: 1.0, provenance: calibratedProvenance)
        ])

        let versions = try database.rows(
            "SELECT version FROM evaluation_signals WHERE asset_id = ? ORDER BY kind",
            bindings: [asset.id.rawValue]
        ).compactMap { $0["version"] }
        XCTAssertEqual(versions, ["2", "2"])
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            []
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10).map(\.id),
            [asset.id]
        )
    }

    func testFaceQualityDefectAnchorSitsBelowStrongReadAnchor() throws {
        // Calibration-study percentile anchors: strong faceQuality at p75
        // (0.45), defect at p5 (0.1). The defect anchor must sit below the
        // strong anchor so no value is simultaneously the strong read that
        // makes an asset a Potential Pick and the defect that lists it under
        // Likely Issues; the old 0.5 defect line covered ~82% of face photos
        // and straddled the strong anchor.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-face-quality-anchors")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let strongFace = Asset.testAsset(id: AssetID(rawValue: "strong-face"), path: "/Volumes/NAS/Job/strong-face.jpg", rating: 0)
        let weakFace = Asset.testAsset(id: AssetID(rawValue: "weak-face"), path: "/Volumes/NAS/Job/weak-face.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([strongFace, weakFace])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: strongFace.id, kind: .faceQuality, value: .score(0.47), confidence: 0.5, provenance: provenance),
            EvaluationSignal(assetID: weakFace.id, kind: .faceQuality, value: .score(0.08), confidence: 0.5, provenance: provenance)
        ])

        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyPick]), limit: 10).map(\.id),
            [strongFace.id]
        )
        XCTAssertEqual(
            try repository.allAssets(matching: SetQuery(predicates: [.likelyIssue]), limit: 10).map(\.id),
            [weakFace.id]
        )
    }

    func testEvaluationSignalsHideRawScaleFocusFamilyRows() throws {
        // Focus-family rows from the recalibrated providers are readable
        // only at each provider's current version: raw-scale rows must not
        // feed badges, rankings, or verdicts. Non-focus-family rows and
        // focus rows from other providers stay visible, and an asset left
        // with only raw-scale focus-family rows honestly has no such read.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-hide-raw-scale-signals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let neverReEvaluated = Asset.testAsset(id: AssetID(rawValue: "never-re-evaluated"), path: "/Volumes/NAS/Job/never-re-evaluated.jpg", rating: 0)
        let mixed = Asset.testAsset(id: AssetID(rawValue: "mixed-versions"), path: "/Volumes/NAS/Job/mixed-versions.jpg", rating: 0)
        let rawMetricsProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "1", settingsHash: "default")
        let rawFacesProvenance = ProviderProvenance(provider: "core-image-faces", model: "CIDetectorFace", version: "1", settingsHash: "default")
        let httpProvenance = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        let calibratedProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        try repository.upsert([neverReEvaluated, mixed])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: neverReEvaluated.id, kind: .focus, value: .score(0.14), confidence: 1.0, provenance: rawMetricsProvenance),
            EvaluationSignal(assetID: neverReEvaluated.id, kind: .motionBlur, value: .score(0.86), confidence: 0.7, provenance: rawMetricsProvenance),
            EvaluationSignal(assetID: neverReEvaluated.id, kind: .exposure, value: .score(0.5), confidence: 1.0, provenance: rawMetricsProvenance),
            EvaluationSignal(assetID: neverReEvaluated.id, kind: .eyeSharpness, value: .score(0.05), confidence: 0.6, provenance: rawFacesProvenance),
            EvaluationSignal(assetID: neverReEvaluated.id, kind: .focus, value: .score(0.9), confidence: 0.8, provenance: httpProvenance)
        ])

        let visible = try repository.evaluationSignals(assetID: neverReEvaluated.id)

        XCTAssertEqual(visible.map(\.kind), [.exposure, .focus])
        XCTAssertEqual(visible.map(\.provenance.provider), ["local-image-metrics", "local-http-model"])

        // Catalogs evaluated across the calibration hold version-1 rows
        // beside version-2 rows (nothing pruned them at write time back
        // then); only the calibrated row may be read.
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: mixed.id, kind: .focus, value: .score(0.93), confidence: 1.0, provenance: calibratedProvenance)
        ])
        try database.execute(
            """
            INSERT INTO evaluation_signals (
                asset_id, kind, value_json, confidence, provenance_json,
                provider, model, version, settings_hash, created_at, updated_at
            )
            VALUES (
                ?, 'focus', '{"score":{"_0":0.14}}', 1.0,
                '{"provider":"local-image-metrics","model":"preview-color-focus-metrics","version":"1","settingsHash":"default"}',
                'local-image-metrics', 'preview-color-focus-metrics', '1', 'default', 0, 0
            )
            """,
            bindings: [mixed.id.rawValue]
        )

        let mixedSignals = try repository.evaluationSignals(assetID: mixed.id)

        XCTAssertEqual(mixedSignals.map(\.kind), [.focus])
        XCTAssertEqual(mixedSignals.map(\.value), [.score(0.93)])
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

    func testDeletesAssetSetWithoutDeletingAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-sets-delete")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(id: AssetID(rawValue: "keeper"), path: "/Photos/keeper.jpg", rating: 0)
        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "keepers"),
            name: "Keepers",
            assetIDs: [asset.id]
        )
        try repository.upsert(asset)
        try repository.upsert(set)

        try repository.deleteAssetSet(id: set.id)

        XCTAssertThrowsError(try repository.assetSet(id: set.id))
        XCTAssertEqual(try repository.assetSets(), [])
        XCTAssertEqual(try repository.asset(id: asset.id), asset)
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

    func testWorkSessionQueryMatchesInputAndOutputSets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-work-session-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let input = Asset.testAsset(id: AssetID(rawValue: "input"), path: "/Volumes/NAS/Job/input.cr2", rating: 5)
        let output = Asset.testAsset(id: AssetID(rawValue: "output"), path: "/Volumes/NAS/Job/output.cr2", rating: 5)
        let lowRatedOutput = Asset.testAsset(id: AssetID(rawValue: "low-rated-output"), path: "/Volumes/NAS/Job/low.cr2", rating: 3)
        let outside = Asset.testAsset(id: AssetID(rawValue: "outside"), path: "/Volumes/NAS/Job/outside.cr2", rating: 5)
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-input-cull"),
            name: "Cull Input",
            assetIDs: [input.id]
        )
        let outputSet = AssetSet(
            id: AssetSetID(rawValue: "work-output-cull"),
            name: "Cull Output",
            membership: .snapshot([lowRatedOutput.id, output.id])
        )
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-1"),
            kind: .culling,
            intent: "Choose the keepers",
            title: "Cull Job",
            detail: "Session over a manual selection",
            status: .completed,
            inputSetIDs: [inputSet.id],
            outputSetIDs: [outputSet.id],
            completedUnitCount: 3,
            totalUnitCount: 3,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.upsert([input, output, lowRatedOutput, outside])
        try repository.upsert(inputSet)
        try repository.upsert(outputSet)
        try repository.save(session)

        let query = SetQuery(predicates: [.workSession(session.id.rawValue), .ratingAtLeast(5)])

        XCTAssertEqual(try repository.allAssets(matching: query, limit: 10).map(\.id), [input.id, output.id])
        XCTAssertEqual(try repository.assetIDs(matching: query), [input.id, output.id])
        XCTAssertEqual(try repository.assetCount(matching: query), 2)
    }

    func testWorkSessionQueryMatchesDynamicInputSets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-work-session-dynamic-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = Asset.testAsset(id: AssetID(rawValue: "dynamic-input-keeper"), path: "/Volumes/NAS/Job/keeper.cr2", rating: 5)
        let reject = Asset.testAsset(id: AssetID(rawValue: "dynamic-input-reject"), path: "/Volumes/NAS/Job/reject.cr2", rating: 2)
        let inputSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "dynamic-work-input"),
            name: "Dynamic Work Input",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let session = WorkSession(
            id: WorkSessionID(rawValue: "dynamic-cull"),
            kind: .culling,
            intent: "Review rated work",
            title: "Dynamic Cull",
            detail: "Dynamic input",
            status: .running,
            inputSetIDs: [inputSet.id],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.upsert([keeper, reject])
        try repository.upsert(inputSet)
        try repository.save(session)

        let query = SetQuery(predicates: [.workSession(session.id.rawValue)])

        XCTAssertEqual(try repository.allAssets(matching: query, limit: 10).map(\.id), [keeper.id])
        XCTAssertEqual(try repository.assetIDs(matching: query), [keeper.id])
        XCTAssertEqual(try repository.assetCount(matching: query), 1)
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

    func testEvaluationFailuresCanBeListedForAsset() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-evaluation-failures-by-asset")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let selected = Asset.testAsset(id: AssetID(rawValue: "selected"), path: "/Volumes/NAS/Job/selected.jpg", rating: 0)
        let other = Asset.testAsset(id: AssetID(rawValue: "other"), path: "/Volumes/NAS/Job/other.jpg", rating: 0)
        try repository.upsert([selected, other])

        try repository.recordEvaluationFailure(assetID: selected.id, provider: "local-http-model", message: "model timed out")
        try repository.recordEvaluationFailure(assetID: selected.id, provider: "apple-vision", message: "vision unavailable")
        try repository.recordEvaluationFailure(assetID: other.id, provider: "local-http-model", message: "other timed out")

        let failures = try repository.evaluationFailures(assetID: selected.id)

        XCTAssertEqual(failures.map(\.assetID), [selected.id, selected.id])
        XCTAssertEqual(failures.map(\.provider), ["apple-vision", "local-http-model"])
        XCTAssertEqual(failures.map(\.message), ["vision unavailable", "model timed out"])
        XCTAssertTrue(failures.allSatisfy { $0.failedAt.timeIntervalSince1970 > 0 })
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
            issues: [
                WorkSessionIssue(
                    kind: .skippedSourceFile,
                    sourceURL: URL(fileURLWithPath: "/Photos/Ceremony/missing.cr2"),
                    message: "could not fingerprint /Photos/Ceremony/missing.cr2"
                )
            ],
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

    func testSearchesWorkSessionsByHistoryText() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-work-session-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let olderCeremony = WorkSession(
            id: WorkSessionID(rawValue: "older-ceremony"),
            kind: .culling,
            intent: "Pick ceremony keepers",
            title: "Cull Ceremony",
            detail: "Reviewed ceremony bursts",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 40,
            totalUnitCount: 50,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newerCeremony = WorkSession(
            id: WorkSessionID(rawValue: "newer-ceremony"),
            kind: .keywording,
            intent: "Keyword reception photos",
            title: "Reception Keywords",
            detail: "Added ceremony and family tags",
            status: .running,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 12,
            totalUnitCount: 30,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let failedImport = WorkSession(
            id: WorkSessionID(rawValue: "failed-import"),
            kind: .ingest,
            intent: "Import card",
            title: "Import Photos",
            detail: "Card reader disconnected",
            status: .failed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 100,
            failureCount: 1,
            createdAt: Date(timeIntervalSince1970: 12),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try repository.save(olderCeremony)
        try repository.save(newerCeremony)
        try repository.save(failedImport)

        XCTAssertEqual(
            try repository.workSessions(matching: "ceremony", limit: 10).map(\.id),
            [newerCeremony.id, olderCeremony.id]
        )
        XCTAssertEqual(try repository.workSessions(matching: "failed", limit: 10).map(\.id), [failedImport.id])
        XCTAssertEqual(try repository.workSessions(matching: "ceremony", limit: 1).map(\.id), [newerCeremony.id])
        XCTAssertEqual(try repository.workSessions(matching: "ceremony", limit: 0), [])
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

private extension CatalogDatabaseTests {
    static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
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
