import XCTest
@testable import TeststripCore

// Scope-filtered count queries backing the Cull HUD: the ✓/✕/left cluster is
// answered from the catalog for the current cull scope, not the loaded set.
// Scope membership is the RAW flag (matching `CullScope.matches(_:)`), while
// the pick/reject counts are confirmed-only — an AI-tentative flag is in the
// picks/rejects scope but still counts as undecided.
final class CatalogRepositoryCullScopeCountTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String, metadata: AssetMetadata) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: metadata
        )
    }

    private func makeSeededRepository(named name: String) throws -> (CatalogRepository, [Asset]) {
        let repository = try makeRepository(named: name)
        let userPick = asset(path: "/Photos/pick.cr2", metadata: AssetMetadata(flag: .pick))
        let userReject = asset(path: "/Photos/reject.cr2", metadata: AssetMetadata(flag: .reject))
        let ghostPick = asset(path: "/Photos/ghost-pick.cr2", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        let unratedA = asset(path: "/Photos/unrated-a.cr2", metadata: AssetMetadata())
        let unratedB = asset(path: "/Photos/unrated-b.cr2", metadata: AssetMetadata(rating: 3))
        let assets = [userPick, userReject, ghostPick, unratedA, unratedB]
        for stored in assets {
            try repository.upsert(stored)
        }
        return (repository, assets)
    }

    func testAllScopeCountsEveryFrame() throws {
        let (repository, assets) = try makeSeededRepository(named: "cull-scope-all")
        let query = SetQuery(predicates: [])

        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .all), assets.count)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .all, confirmedFlag: .pick), 1)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .all, confirmedFlag: .reject), 1)
    }

    func testPicksScopeExcludesRejectsAndUnrated() throws {
        let (repository, _) = try makeSeededRepository(named: "cull-scope-picks")
        let query = SetQuery(predicates: [])

        // The user pick AND the AI-tentative pick are in the picks scope ...
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .picks), 2)
        // ... but only the confirmed one is a decision; the ghost is undecided.
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .picks, confirmedFlag: .pick), 1)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .picks, confirmedFlag: .reject), 0)
    }

    func testRejectsScopeCountsOnlyRejects() throws {
        let (repository, _) = try makeSeededRepository(named: "cull-scope-rejects")
        let query = SetQuery(predicates: [])

        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .rejects), 1)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .rejects, confirmedFlag: .reject), 1)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .rejects, confirmedFlag: .pick), 0)
    }

    func testUnratedScopeMatchesOnlyFlaglessFrames() throws {
        let (repository, _) = try makeSeededRepository(named: "cull-scope-unrated")
        let query = SetQuery(predicates: [])

        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .unrated), 2)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .unrated, confirmedFlag: .pick), 0)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .unrated, confirmedFlag: .reject), 0)
    }

    func testQueryPredicatesAndScopeAreAnded() throws {
        let repository = try makeRepository(named: "cull-scope-and")
        let inScope = asset(path: "/Photos/keep/a.cr2", metadata: AssetMetadata(flag: .pick))
        let outOfScopeFlag = asset(path: "/Photos/keep/b.cr2", metadata: AssetMetadata())
        let outOfScopeFolder = asset(path: "/Photos/other/c.cr2", metadata: AssetMetadata(flag: .pick))
        try repository.upsert(inScope)
        try repository.upsert(outOfScopeFlag)
        try repository.upsert(outOfScopeFolder)
        let query = SetQuery(predicates: [.folderPrefix("/Photos/keep")])

        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .picks), 1)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .picks, confirmedFlag: .pick), 1)
        XCTAssertEqual(try repository.assetCount(matching: query, cullScope: .unrated), 1)
    }

    func testIDSetScopedCounts() throws {
        let (repository, assets) = try makeSeededRepository(named: "cull-scope-ids")
        let ids = assets.map(\.id)

        XCTAssertEqual(try repository.assetCount(ids: ids, cullScope: .all), assets.count)
        XCTAssertEqual(try repository.assetCount(ids: ids, cullScope: .picks), 2)
        XCTAssertEqual(try repository.assetCount(ids: ids, cullScope: .picks, confirmedFlag: .pick), 1)
        XCTAssertEqual(try repository.assetCount(ids: ids, cullScope: .unrated), 2)
    }

    func testEmptyIDSetScopeCountsAreZero() throws {
        let (repository, _) = try makeSeededRepository(named: "cull-scope-ids-empty")

        XCTAssertEqual(try repository.assetCount(ids: [], cullScope: .picks), 0)
        XCTAssertEqual(try repository.assetCount(ids: [], cullScope: .picks, confirmedFlag: .pick), 0)
    }
}
