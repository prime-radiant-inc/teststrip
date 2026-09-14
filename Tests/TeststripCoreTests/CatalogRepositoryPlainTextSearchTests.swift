import XCTest
@testable import TeststripCore

/// Plain text search (`SetQuery.Predicate.text`) must find photos by the text a
/// user can see on an asset — not just the filename and evaluation signals.
/// Regression coverage: typing `batch-0` or a caption phrase returned zero
/// photos even though the word exists as a keyword/caption.
final class CatalogRepositoryPlainTextSearchTests: XCTestCase {
    func testPlainTextSearchMatchesMetadataKeywordsAndCaption() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-plain-text-metadata")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let keywordHit = Asset.testAsset(
            id: AssetID(rawValue: "keyword-hit"),
            path: "/Volumes/NAS/Job/frame-001.jpg",
            metadata: AssetMetadata(rating: 0, keywords: ["batch-0"])
        )
        let captionHit = Asset.testAsset(
            id: AssetID(rawValue: "caption-hit"),
            path: "/Volumes/NAS/Job/frame-002.jpg",
            metadata: AssetMetadata(rating: 0, caption: "Smoke frame 4")
        )
        let filenameHit = Asset.testAsset(
            id: AssetID(rawValue: "filename-hit"),
            path: "/Volumes/NAS/Job/beach-sunset.jpg",
            metadata: AssetMetadata(rating: 0)
        )
        let miss = Asset.testAsset(
            id: AssetID(rawValue: "miss"),
            path: "/Volumes/NAS/Job/frame-003.jpg",
            metadata: AssetMetadata(rating: 0)
        )
        try repository.upsert([keywordHit, captionHit, filenameHit, miss])

        // Keyword hit (the live regression: `batch-0` as plain text).
        let keywordQuery = SetQuery(predicates: [.text("batch-0")])
        XCTAssertEqual(try repository.allAssets(matching: keywordQuery, limit: 10).map(\.id), [keywordHit.id])
        XCTAssertEqual(try repository.assetCount(matching: keywordQuery), 1)

        // Caption hit, case-insensitively.
        let captionQuery = SetQuery(predicates: [.text("smoke frame 4")])
        XCTAssertEqual(try repository.allAssets(matching: captionQuery, limit: 10).map(\.id), [captionHit.id])
        XCTAssertEqual(try repository.assetCount(matching: captionQuery), 1)

        // Filename hit still works, case-insensitively (unchanged behavior).
        let filenameQuery = SetQuery(predicates: [.text("BEACH-SUNSET")])
        XCTAssertEqual(try repository.allAssets(matching: filenameQuery, limit: 10).map(\.id), [filenameHit.id])
        XCTAssertEqual(try repository.assetCount(matching: filenameQuery), 1)

        // Genuine miss returns nothing.
        let missQuery = SetQuery(predicates: [.text("no-such-token-anywhere")])
        XCTAssertTrue(try repository.allAssets(matching: missQuery, limit: 10).isEmpty)
        XCTAssertEqual(try repository.assetCount(matching: missQuery), 0)
    }

    func testPlainTextSearchMatchesCreatorAndCopyright() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-plain-text-credit")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let creatorHit = Asset.testAsset(
            id: AssetID(rawValue: "creator-hit"),
            path: "/Volumes/NAS/Job/frame-001.jpg",
            metadata: AssetMetadata(rating: 0, creator: "Ada Lovelace")
        )
        let copyrightHit = Asset.testAsset(
            id: AssetID(rawValue: "copyright-hit"),
            path: "/Volumes/NAS/Job/frame-002.jpg",
            metadata: AssetMetadata(rating: 0, copyright: "© 2026 Teststrip")
        )
        let miss = Asset.testAsset(
            id: AssetID(rawValue: "miss"),
            path: "/Volumes/NAS/Job/frame-003.jpg",
            metadata: AssetMetadata(rating: 0)
        )
        try repository.upsert([creatorHit, copyrightHit, miss])

        let creatorQuery = SetQuery(predicates: [.text("ada lovelace")])
        XCTAssertEqual(try repository.allAssets(matching: creatorQuery, limit: 10).map(\.id), [creatorHit.id])

        let copyrightQuery = SetQuery(predicates: [.text("teststrip")])
        XCTAssertEqual(try repository.allAssets(matching: copyrightQuery, limit: 10).map(\.id), [copyrightHit.id])
    }
}

private extension Asset {
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
