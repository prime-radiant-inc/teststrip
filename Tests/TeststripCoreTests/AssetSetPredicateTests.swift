import XCTest
@testable import TeststripCore

// A saved set with static membership had no query form, so every read that
// takes a `SetQuery` silently saw the whole catalog for it — which is why the
// Map lens showed every geotagged photo while the grid below showed six.
// This predicate is the missing form, built the same way `.importBatch` and
// `.workSession` already resolve set membership.
final class AssetSetPredicateTests: XCTestCase {
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

    func testAManualSetsMembersMatchThePredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-manual")
        let inSet = asset(path: "/Photos/in.jpg")
        let outOfSet = asset(path: "/Photos/out.jpg")
        try repository.upsert([inSet, outOfSet])
        let setID = AssetSetID(rawValue: "keepers")
        try repository.upsert(AssetSet.manual(id: setID, name: "Keepers", assetIDs: [inSet.id]))

        let matched = try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)]))

        XCTAssertEqual(matched, [inSet.id])
    }

    func testASnapshotSetsMembersMatchThePredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-snapshot")
        let inSet = asset(path: "/Photos/in.jpg")
        let outOfSet = asset(path: "/Photos/out.jpg")
        try repository.upsert([inSet, outOfSet])
        let setID = AssetSetID(rawValue: "frozen")
        try repository.upsert(AssetSet(id: setID, name: "Frozen", membership: .snapshot([inSet.id])))

        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)])),
            [inSet.id]
        )
    }

    // A dynamic set's membership is its query, which already reaches SQL
    // through `selectedDynamicSetQuery`; this predicate is only about static
    // membership, and must not silently match everything.
    func testADynamicSetMatchesNothingThroughThisPredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-dynamic")
        let only = asset(path: "/Photos/only.jpg")
        try repository.upsert(only)
        let setID = AssetSetID(rawValue: "dyn")
        try repository.upsert(AssetSet.dynamic(id: setID, name: "Dyn", query: SetQuery(predicates: [.flag(.pick)])))

        XCTAssertEqual(try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)])), [])
    }

    func testAnUnknownSetIDMatchesNothing() throws {
        let repository = try makeRepository(named: "asset-set-predicate-unknown")
        try repository.upsert(asset(path: "/Photos/only.jpg"))

        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(AssetSetID(rawValue: "nope"))])),
            []
        )
    }

    // Unlike the dynamic-set and unknown-id zero-row paths above, this is a
    // real manual set at a membership path that exists — just empty — so it
    // must not fall through to matching everything.
    func testAManualSetWithNoMembersMatchesNothing() throws {
        let repository = try makeRepository(named: "asset-set-predicate-empty-manual")
        try repository.upsert(asset(path: "/Photos/only.jpg"))
        let setID = AssetSetID(rawValue: "empty")
        try repository.upsert(AssetSet.manual(id: setID, name: "Empty", assetIDs: []))

        XCTAssertEqual(try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)])), [])
    }

    // Predicates are implicitly AND-ed, so a set scope composes with a filter
    // exactly the way the Map's bounds + query already compose.
    func testThePredicateComposesWithOtherPredicates() throws {
        let repository = try makeRepository(named: "asset-set-predicate-compose")
        let picked = asset(path: "/Photos/picked.jpg")
        let unpicked = asset(path: "/Photos/unpicked.jpg")
        try repository.upsert([picked, unpicked])
        try repository.updateMetadata(assetID: picked.id) { metadata in
            metadata.flag = .pick
        }
        let setID = AssetSetID(rawValue: "both")
        try repository.upsert(AssetSet.manual(id: setID, name: "Both", assetIDs: [picked.id, unpicked.id]))

        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID), .flag(.pick)])),
            [picked.id]
        )
    }

    // The three map aggregates take the same `matching:` parameter every other
    // read does, so scoping them needs no new overload. `topLocations` is the
    // one the design rationale for a single `.assetSet` predicate (rather than
    // a chunked `ids:` overload) actually rests on, so it gets the same
    // in-set/out-of-set assertion as the other two, not just a shared comment.
    func testTheMapAggregatesHonourTheSetPredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-map")
        let inSet = geotagged(path: "/Photos/in.jpg", latitude: 10, longitude: 20)
        let outOfSet = geotagged(path: "/Photos/out.jpg", latitude: 40, longitude: 50)
        try repository.upsert([inSet, outOfSet])
        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 10, longitude: 20),
            displayName: "In Place"
        ))
        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 40, longitude: 50),
            displayName: "Out Place"
        ))
        let setID = AssetSetID(rawValue: "map-set")
        try repository.upsert(AssetSet.manual(id: setID, name: "Map Set", assetIDs: [inSet.id]))
        let scope = SetQuery(predicates: [.assetSet(setID)])

        let coverage = try repository.geotaggedCoverage(matching: scope)
        let clusters = try repository.placeClusters(bounds: nil, cellSize: 10, matching: scope)
        let topLocations = try repository.topLocations(limit: 10, matching: scope)

        XCTAssertEqual(coverage.totalCount, 1)
        XCTAssertEqual(coverage.geotaggedCount, 1)
        XCTAssertEqual(clusters.map(\.assetCount).reduce(0, +), 1)
        XCTAssertEqual(topLocations.map(\.displayName), ["In Place"])
        XCTAssertEqual(topLocations.first?.assetCount, 1)
    }

    private func geotagged(path: String, latitude: Double, longitude: Double) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 100,
                pixelHeight: 100,
                latitude: latitude,
                longitude: longitude,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }
}
