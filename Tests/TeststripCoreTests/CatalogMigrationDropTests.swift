import XCTest
@testable import TeststripCore

// SP-D0 drops `autopilot_proposals` forward-only. The stale rows in a real
// catalog are bookkeeping, not truth; the ghosts in `metadata_json` are the
// truth and must come through the migration untouched.
final class CatalogMigrationDropTests: XCTestCase {
    private static let legacyProposalsTableSQL = """
    CREATE TABLE IF NOT EXISTS autopilot_proposals (
        id TEXT PRIMARY KEY NOT NULL,
        run_id TEXT NOT NULL,
        asset_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        keyword TEXT,
        rationale TEXT NOT NULL,
        confidence REAL NOT NULL,
        status TEXT NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    )
    """

    private func tableExists(_ name: String, in database: CatalogDatabase) throws -> Bool {
        let rows = try database.rows(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            bindings: [name]
        )
        return !rows.isEmpty
    }

    func testMigrationVersionCoversTheProposalTableDrop() {
        // autopilot_proposals was dropped at schema 23; later migrations only
        // raise the version, so assert the floor rather than pinning a literal
        // that every future migration would break.
        XCTAssertGreaterThanOrEqual(CatalogMigrations.version, 23)
    }

    func testFreshCatalogNeverCreatesTheProposalTable() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "drop-proposals-fresh")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()

        XCTAssertFalse(try tableExists("autopilot_proposals", in: database))
        XCTAssertFalse(
            CatalogMigrations.statements.contains { $0.contains("autopilot_proposals") },
            "the CREATE must be gone, not merely shadowed by the DROP"
        )
    }

    func testLegacyCatalogWithProposalRowsOpensCleanAndKeepsItsGhosts() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "drop-proposals-legacy")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")

        // Build a "legacy" catalog: current schema plus the old table, with a
        // row in it, alongside an asset carrying a ghost.
        let legacyDatabase = try CatalogDatabase.open(at: catalogURL)
        try legacyDatabase.migrate()
        try legacyDatabase.execute(Self.legacyProposalsTableSQL)
        try legacyDatabase.execute(
            "CREATE INDEX IF NOT EXISTS idx_autopilot_proposals_status ON autopilot_proposals(status)"
        )
        try legacyDatabase.execute(
            """
            INSERT INTO autopilot_proposals
                (id, run_id, asset_id, kind, keyword, rationale, confidence, status, created_at, updated_at)
            VALUES ('p-1', 'run-1', 'asset-1', 'pick', NULL, 'Sharpest frame in its burst', 0.82, 'pending', 1.0, 1.0)
            """
        )
        let ghostAsset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: URL(fileURLWithPath: "/Photos/ghost.cr2"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag])
        )
        try CatalogRepository(database: legacyDatabase).upsert(ghostAsset)
        XCTAssertTrue(try tableExists("autopilot_proposals", in: legacyDatabase))

        // Reopen: the drop runs, and nothing throws.
        let reopened = try CatalogDatabase.open(at: catalogURL)
        try reopened.migrate()

        XCTAssertFalse(try tableExists("autopilot_proposals", in: reopened))
        XCTAssertTrue(
            try reopened.rows(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_autopilot_proposals%'"
            ).isEmpty,
            "DROP TABLE takes the table's indexes with it"
        )

        // The ghost is untouched — metadata_json is the truth, not the table.
        let reopenedRepository = CatalogRepository(database: reopened)
        let restored = try reopenedRepository.asset(id: ghostAsset.id)
        XCTAssertEqual(AutopilotGhost.kind(in: restored.metadata), .pick)
        XCTAssertNil(restored.metadata.confirmedProjection.flag)
        XCTAssertEqual(try reopenedRepository.assetIDsWithAutopilotGhost(), [ghostAsset.id])
    }

    // Idempotence: the drop runs on every open, including opens where the
    // table was never there.
    func testMigrationIsIdempotentAcrossRepeatedOpens() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "drop-proposals-idempotent")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        for _ in 0..<3 {
            let database = try CatalogDatabase.open(at: catalogURL)
            try database.migrate()
            XCTAssertFalse(try tableExists("autopilot_proposals", in: database))
        }
    }
}
