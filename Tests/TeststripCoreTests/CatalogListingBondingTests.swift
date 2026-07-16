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

    private func asset(id: String, path: String, technicalMetadata: AssetTechnicalMetadata? = nil) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata
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

    /// A RAW primary with one bonded JPEG secondary sharing folder, capture
    /// time, and GPS coordinates, plus one unrelated standalone — the
    /// fixture for the hand-rolled `GROUP BY COUNT(*)` aggregates
    /// (folders/timelineDays/placeClusters/geotaggedCoverage/source-root
    /// counts): every one of them would double-count the shot if the
    /// secondary weren't excluded, since primary and secondary land in the
    /// same folder/day/place/source-root bucket.
    private func seedBondedTrioForAggregates(
        _ repository: CatalogRepository
    ) throws -> (primary: AssetID, secondary: AssetID, standalone: AssetID) {
        let primary = AssetID(rawValue: "raw")
        let secondary = AssetID(rawValue: "jpg")
        let standalone = AssetID(rawValue: "standalone")
        let provenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        let technicalMetadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            latitude: 37.7749,
            longitude: -122.4194,
            capturedAt: Date(timeIntervalSince1970: 1_800_010_000),
            provenance: provenance
        )
        try repository.upsert(asset(id: primary.rawValue, path: "/photos/IMG_1.CR3", technicalMetadata: technicalMetadata))
        try repository.upsert(asset(id: secondary.rawValue, path: "/photos/IMG_1.JPG", technicalMetadata: technicalMetadata))
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

    // The following six tests cover the hand-rolled `GROUP BY COUNT(*)`
    // aggregates a code review found still counting bonded secondaries
    // (Task 3 only filtered the allAssets/assetIDs/assetCount family). Each
    // seeds a bonded pair that shares a folder/day/place/source-root, so an
    // unfiltered aggregate double-counts the shot.

    func testFoldersExcludesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-folders")
        _ = try seedBondedTrioForAggregates(repository)

        let folders = try repository.folders()

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.assetCount, 2)
    }

    func testTimelineDaysExcludesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-timeline")
        _ = try seedBondedTrioForAggregates(repository)

        let days = try repository.timelineDays()

        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.assetCount, 1)
    }

    func testPlaceClustersExcludesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-place-clusters")
        _ = try seedBondedTrioForAggregates(repository)

        let clusters = try repository.placeClusters(bounds: nil, cellSize: 10.0)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.assetCount, 1)
    }

    func testGeotaggedCoverageExcludesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-coverage")
        _ = try seedBondedTrioForAggregates(repository)

        let coverage = try repository.geotaggedCoverage()

        // Total: primary + standalone (secondary excluded). Geotagged: only
        // the primary (the standalone has no coordinates).
        XCTAssertEqual(coverage.totalCount, 2)
        XCTAssertEqual(coverage.geotaggedCount, 1)
    }

    func testSourceRootAssetCountExcludesBondedSecondary() throws {
        let repository = try makeRepository(named: "listing-source-root")
        _ = try seedBondedTrioForAggregates(repository)
        try repository.recordSourceRoot(URL(fileURLWithPath: "/photos", isDirectory: true))

        let sourceRoot = try repository.sourceRoots().first

        XCTAssertEqual(sourceRoot?.assetCount, 2)
    }

    // Defensive: evaluation doesn't currently populate a bonded secondary's
    // person_assets row, so this doesn't double-count in practice today.
    // Simulate the latent case directly via assignAssets(...) so the guard
    // is proven regardless of whether evaluation ever changes.
    func testPeopleCountExcludesBondedSecondaryDefensively() throws {
        let repository = try makeRepository(named: "listing-people")
        let (primary, secondary, _) = try seedBondedTrioForAggregates(repository)
        try repository.upsertPerson(id: "person-1", name: "Alex")
        try repository.assignAssets([primary, secondary], toPersonID: "person-1")

        let people = try repository.people()

        XCTAssertEqual(people.first(where: { $0.id == "person-1" })?.assetCount, 1)
    }
}
