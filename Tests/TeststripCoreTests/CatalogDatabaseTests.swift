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
        Asset(
            id: id,
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1.25), contentHash: "hash"),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
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
