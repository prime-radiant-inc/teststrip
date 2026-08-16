import XCTest
@testable import TeststripCore

// The unified shell's "⚠ Preview failed" import child needs asset identity,
// not just a count: clicking it opens those photos in Grid. The count query
// already exists; this is its DISTINCT-id twin, and the agreement test is what
// keeps the badge number and the list from disagreeing.
final class PreviewFailureAssetIDsTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func recordFailure(_ repository: CatalogRepository, assetID: AssetID, message: String) throws {
        try repository.recordPreviewGenerationFailure(assetID: assetID, level: .grid, errorMessage: message)
    }

    func testReturnsOnlyAssetsWithARecordedPreviewError() throws {
        let repository = try makeRepository(named: "preview-failure-ids")
        let failed = asset(path: "/Photos/failed.cr2")
        let queuedOnly = asset(path: "/Photos/queued.cr2")
        let untouched = asset(path: "/Photos/untouched.cr2")
        try repository.upsert([failed, queuedOnly, untouched])
        try recordFailure(repository, assetID: failed.id, message: "decode failed")
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: queuedOnly.id, level: .grid))

        let ids = try repository.previewGenerationFailureAssetIDs(
            assetIDs: [failed.id, queuedOnly.id, untouched.id]
        )

        XCTAssertEqual(ids, [failed.id])
    }

    func testEmptyScopeYieldsNoIDs() throws {
        let repository = try makeRepository(named: "preview-failure-ids-empty")

        XCTAssertEqual(try repository.previewGenerationFailureAssetIDs(assetIDs: []), [])
    }

    // The child row's count and the child row's contents must be the same
    // fact read two ways.
    func testIDCountAgreesWithTheExistingFailureCount() throws {
        let repository = try makeRepository(named: "preview-failure-ids-agreement")
        let first = asset(path: "/Photos/a.cr2")
        let second = asset(path: "/Photos/b.cr2")
        let clean = asset(path: "/Photos/c.cr2")
        try repository.upsert([first, second, clean])
        try recordFailure(repository, assetID: first.id, message: "boom")
        try recordFailure(repository, assetID: second.id, message: "boom")
        let scope = [first.id, second.id, clean.id]

        XCTAssertEqual(
            try repository.previewGenerationFailureAssetIDs(assetIDs: scope).count,
            try repository.previewGenerationFailureAssetCount(assetIDs: scope)
        )
    }
}
