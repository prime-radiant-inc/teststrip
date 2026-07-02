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
        try repository.upsert([keeper, reject, landscape])

        let pickQuery = SetQuery(predicates: [.text("CEREMONY"), .ratingAtLeast(4), .flag(.pick)])
        XCTAssertEqual(try repository.allAssets(matching: pickQuery, limit: 10).map(\.id), [keeper.id])
        XCTAssertEqual(try repository.assetCount(matching: pickQuery), 1)

        let colorKeywordQuery = SetQuery(predicates: [.colorLabel(.green), .keyword("patagonia")])
        XCTAssertEqual(try repository.allAssets(matching: colorKeywordQuery, limit: 10).map(\.id), [landscape.id])
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
    static func testAsset(id: AssetID = .new(), path: String, rating: Int) -> Asset {
        testAsset(id: id, path: path, metadata: AssetMetadata(rating: rating))
    }

    static func testAsset(id: AssetID = .new(), path: String, metadata: AssetMetadata) -> Asset {
        Asset(
            id: id,
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1.25), contentHash: "hash"),
            availability: .online,
            metadata: metadata
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
