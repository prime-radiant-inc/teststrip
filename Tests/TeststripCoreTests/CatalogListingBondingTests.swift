import XCTest
@testable import TeststripCore

/// A bonded RAW+JPEG shot must show/count once on every user-facing listing
/// surface, while processing/enqueue paths and fetch-by-id keep seeing both
/// rows (Task 3 of the RAW+JPEG bonding plan).
final class CatalogListingBondingTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    /// A RAW primary with one bonded JPEG secondary, plus one unrelated
    /// standalone asset — the minimal fixture for "one tile per shot."
    private func seedBondedTrio(_ repository: CatalogRepository) throws -> (primary: AssetID, secondary: AssetID, standalone: AssetID) {
        let primary = AssetID(rawValue: "raw")
        let secondary = AssetID(rawValue: "jpg")
        let standalone = AssetID(rawValue: "standalone")
        try repository.upsert(asset(id: primary.rawValue, path: "/photos/IMG_1.CR3"))
        try repository.upsert(asset(id: secondary.rawValue, path: "/photos/IMG_1.JPG"))
        try repository.upsert(asset(id: standalone.rawValue, path: "/photos/IMG_2.JPG"))
        try repository.setBond(secondaryID: secondary, primaryID: primary)
        return (primary, secondary, standalone)
    }

    func testAllAssetsExcludesBondedSecondaryByDefault() throws {
        let repository = try makeRepository(named: "listing-allassets-default")
        let (primary, secondary, standalone) = try seedBondedTrio(repository)

        let ids = Set(try repository.allAssets().map(\.id))

        XCTAssertEqual(ids, [primary, standalone])
        XCTAssertFalse(ids.contains(secondary))
    }

    func testAllAssetsIncludesBondedSecondaryWhenRequested() throws {
        let repository = try makeRepository(named: "listing-allassets-include")
        let (primary, secondary, standalone) = try seedBondedTrio(repository)

        let ids = Set(try repository.allAssets(includeBondedSecondaries: true).map(\.id))

        XCTAssertEqual(ids, [primary, secondary, standalone])
    }

    func testFetchByIDStillResolvesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-assets-by-id")
        let (_, secondary, _) = try seedBondedTrio(repository)

        let fetched = try repository.assets(ids: [secondary], limit: 1)

        XCTAssertEqual(fetched.map(\.id), [secondary])
    }

    func testAssetCountExcludesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-assetcount")
        _ = try seedBondedTrio(repository)

        XCTAssertEqual(try repository.assetCount(), 2)
    }

    // `assetIDs()` backs AppModel's current-scope/latest-import evaluation
    // triggers (`currentAssetScopeIDs`, `latestImportOutputAssetIDs`), which
    // must still see a bonded shot's hidden JPEG so it keeps getting
    // evaluated. The default (display) call excludes it; the explicit opt-in
    // those processing paths use does not.
    func testAssetIDsExcludesBondedSecondaryByDefaultButIncludesWhenRequested() throws {
        let repository = try makeRepository(named: "listing-assetids")
        let (primary, secondary, standalone) = try seedBondedTrio(repository)

        let displayIDs = Set(try repository.assetIDs())
        XCTAssertEqual(displayIDs, [primary, standalone])

        let processingIDs = Set(try repository.assetIDs(includeBondedSecondaries: true))
        XCTAssertEqual(processingIDs, [primary, secondary, standalone])
    }

    // Guards against a "" vs NULL storage regression: clearing the bond must
    // make the secondary reappear through the real filter, not just via a
    // separately-maintained flag.
    func testClearingBondRestoresSecondaryToListings() throws {
        let repository = try makeRepository(named: "listing-unbond")
        let (primary, secondary, standalone) = try seedBondedTrio(repository)

        try repository.setBond(secondaryID: secondary, primaryID: nil)

        let ids = Set(try repository.allAssets().map(\.id))
        XCTAssertEqual(ids, [primary, secondary, standalone])
        XCTAssertEqual(try repository.assetCount(), 3)
    }
}
