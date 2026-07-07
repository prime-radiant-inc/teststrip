import XCTest
@testable import TeststripCore

final class CatalogRepositoryContentHashTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String, contentHash: String?) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: contentHash),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    func testMigrationVersionIsFifteen() {
        XCTAssertEqual(CatalogMigrations.version, 15)
    }

    func testAssetLookupByContentHashFindsUpsertedAsset() throws {
        let repository = try makeRepository(named: "content-hash-lookup")
        let stored = asset(path: "/Photos/2025/one.cr2", contentHash: "abc123")
        try repository.upsert(stored)

        let found = try repository.asset(contentHash: "abc123")

        XCTAssertEqual(found?.id, stored.id)
    }

    func testAssetLookupByContentHashReturnsNilForAbsentHash() throws {
        let repository = try makeRepository(named: "content-hash-absent")
        try repository.upsert(asset(path: "/Photos/2025/one.cr2", contentHash: "abc123"))

        XCTAssertNil(try repository.asset(contentHash: "not-present"))
    }

    func testAssetLookupByEmptyContentHashReturnsNil() throws {
        let repository = try makeRepository(named: "content-hash-empty-query")
        // An asset stored without a content hash must not be discoverable by an
        // empty-string query; empty means "no identity recorded", not a match.
        try repository.upsert(asset(path: "/Photos/2025/legacy.cr2", contentHash: nil))

        XCTAssertNil(try repository.asset(contentHash: ""))
    }

    func testHashlessAssetIsNotFoundByContentHash() throws {
        let repository = try makeRepository(named: "content-hash-legacy")
        try repository.upsert(asset(path: "/Photos/2025/legacy.cr2", contentHash: nil))

        XCTAssertNil(try repository.asset(contentHash: "abc123"))
    }

    func testContainedContentHashesReturnsOnlyPresentHashes() throws {
        let repository = try makeRepository(named: "contained-hashes")
        try repository.upsert(asset(path: "/Photos/2025/one.cr2", contentHash: "aaa"))
        try repository.upsert(asset(path: "/Photos/2025/two.cr2", contentHash: "bbb"))
        try repository.upsert(asset(path: "/Photos/2025/legacy.cr2", contentHash: nil))

        let contained = try repository.containedContentHashes(["aaa", "bbb", "ccc", ""])

        XCTAssertEqual(contained, ["aaa", "bbb"])
    }

    func testContainedContentHashesReturnsEmptyForEmptyInput() throws {
        let repository = try makeRepository(named: "contained-hashes-empty")
        try repository.upsert(asset(path: "/Photos/2025/one.cr2", contentHash: "aaa"))

        XCTAssertEqual(try repository.containedContentHashes([]), [])
    }

    func testUpsertUpdatesContentHashColumnWhenFingerprintChanges() throws {
        let repository = try makeRepository(named: "content-hash-update")
        let original = asset(path: "/Photos/2025/one.cr2", contentHash: "old-hash")
        try repository.upsert(original)
        let changed = Asset(
            id: original.id,
            originalURL: original.originalURL,
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 200, modificationDate: Date(timeIntervalSince1970: 2), contentHash: "new-hash"),
            availability: .online,
            metadata: AssetMetadata()
        )

        try repository.upsert(changed)

        XCTAssertNil(try repository.asset(contentHash: "old-hash"))
        XCTAssertEqual(try repository.asset(contentHash: "new-hash")?.id, original.id)
    }

    func testMigrateIsIdempotent() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "content-hash-idempotent")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try repository.upsert(asset(path: "/Photos/2025/one.cr2", contentHash: "abc"))

        XCTAssertNotNil(try repository.asset(contentHash: "abc"))
    }

    func testMigrateAddsContentHashColumnToPreexistingAssetsTable() throws {
        // A catalog created before this migration already has an assets table
        // without content_hash. Migrating must add the column so content-based
        // dedup works after an upgrade without recreating the catalog.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "content-hash-upgrade")
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
                technical_metadata_json TEXT,
                catalog_generation INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )

        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(asset(path: "/Photos/2025/one.cr2", contentHash: "abc"))

        XCTAssertEqual(try repository.asset(contentHash: "abc")?.originalURL.path, "/Photos/2025/one.cr2")
    }
}
