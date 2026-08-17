import XCTest
@testable import TeststripCore

// The review queue's and sidebar count's universe is catalog-wide, not the
// loaded scope. This is the SQL twin of `AutopilotGhost.kind(in:)`; the
// agreement test below is what keeps the two derivations honest.
final class AutopilotGhostQueryTests: XCTestCase {
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

    func testFindsOnlyGhostCarryingAssets() throws {
        let repository = try makeRepository(named: "ghost-query-basic")
        let ghostPick = asset(path: "/Photos/ghost-pick.cr2", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        let ghostReject = asset(path: "/Photos/ghost-reject.cr2", metadata: AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag]))
        let userFlag = asset(path: "/Photos/user-flag.cr2", metadata: AssetMetadata(flag: .pick))
        let noFlag = asset(path: "/Photos/no-flag.cr2", metadata: AssetMetadata())
        for stored in [ghostPick, ghostReject, userFlag, noFlag] {
            try repository.upsert(stored)
        }

        XCTAssertEqual(
            Set(try repository.assetIDsWithAutopilotGhost()),
            Set([ghostPick.id, ghostReject.id])
        )
    }

    // Ambient AI keywords never enroll an asset in the review queue.
    func testAmbientAIKeywordsDoNotEnrollAnAsset() throws {
        let repository = try makeRepository(named: "ghost-query-keywords")
        let keywordsOnly = asset(
            path: "/Photos/keywords.cr2",
            metadata: AssetMetadata(keywords: ["dog"], aiUnconfirmedKeywords: ["dog"])
        )
        let captionOnly = asset(
            path: "/Photos/caption.cr2",
            metadata: AssetMetadata(caption: "a dog", aiUnconfirmedFields: [.caption])
        )
        let ratingOnly = asset(
            path: "/Photos/rating.cr2",
            metadata: AssetMetadata(rating: 4, aiUnconfirmedFields: [.rating])
        )
        for stored in [keywordsOnly, captionOnly, ratingOnly] {
            try repository.upsert(stored)
        }

        XCTAssertEqual(try repository.assetIDsWithAutopilotGhost(), [])
    }

    func testEmptyCatalogYieldsNoGhosts() throws {
        let repository = try makeRepository(named: "ghost-query-empty")

        XCTAssertEqual(try repository.assetIDsWithAutopilotGhost(), [])
    }

    // Display-facing listing: a bonded JPEG secondary must never surface as its
    // own smart-collection row, same rule the other id listings follow.
    func testBondedSecondaryIsExcluded() throws {
        let repository = try makeRepository(named: "ghost-query-bonded")
        let primary = asset(path: "/Photos/frame.cr2", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        let secondary = asset(path: "/Photos/frame.jpg", metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]))
        try repository.upsert(primary)
        try repository.upsert(secondary)
        try repository.setBonds([secondary.id: primary.id])

        XCTAssertEqual(try repository.assetIDsWithAutopilotGhost(), [primary.id])
    }

    // The two sanctioned derivations must never disagree: whatever the pure
    // helper calls a ghost is exactly what the SQL finder returns, across the
    // whole matrix of metadata shapes.
    func testSQLFinderAgreesWithTheDerivationHelperAcrossTheMatrix() throws {
        let repository = try makeRepository(named: "ghost-query-agreement")
        let matrix: [AssetMetadata] = [
            AssetMetadata(),
            AssetMetadata(flag: .pick),
            AssetMetadata(flag: .reject),
            AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]),
            AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag]),
            AssetMetadata(flag: nil, aiUnconfirmedFields: [.flag]),
            AssetMetadata(rating: 4, aiUnconfirmedFields: [.rating]),
            AssetMetadata(caption: "x", aiUnconfirmedFields: [.caption]),
            AssetMetadata(keywords: ["dog"], aiUnconfirmedKeywords: ["dog"]),
            AssetMetadata(rating: 5, flag: .pick, keywords: ["dog"], caption: "x", aiUnconfirmedKeywords: ["dog"], aiUnconfirmedFields: [.flag, .caption]),
            AssetMetadata(rating: 5, flag: .pick, keywords: ["dog"], caption: "x", aiUnconfirmedKeywords: ["dog"], aiUnconfirmedFields: [.caption])
        ]
        var expected: Set<AssetID> = []
        for (index, metadata) in matrix.enumerated() {
            let stored = asset(path: "/Photos/matrix-\(index).cr2", metadata: metadata)
            try repository.upsert(stored)
            if AutopilotGhost.kind(in: metadata) != nil {
                expected.insert(stored.id)
            }
        }

        XCTAssertEqual(Set(try repository.assetIDsWithAutopilotGhost()), expected)
        XCTAssertEqual(expected.count, 3, "matrix must contain exactly three ghosts, or the agreement check is vacuous")
    }
}
