import XCTest
import TeststripCore

final class SearchSetTests: XCTestCase {
    func testManualSetPreservesExplicitMembershipAndOrdering() {
        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "set-1"),
            name: "Portfolio candidates",
            assetIDs: [AssetID(rawValue: "b"), AssetID(rawValue: "a")]
        )

        XCTAssertEqual(set.membership, .manual([AssetID(rawValue: "b"), AssetID(rawValue: "a")]))
        XCTAssertFalse(set.isDynamic)
        XCTAssertFalse(set.starred)
    }

    func testDynamicSetStoresStructuredQuery() {
        let query = SetQuery(predicates: [
            .ratingAtLeast(4),
            .keyword("Patagonia"),
            .availability(.online)
        ])
        let set = AssetSet.dynamic(id: AssetSetID(rawValue: "set-2"), name: "Online Patagonia Picks", query: query)

        XCTAssertTrue(set.isDynamic)
        XCTAssertEqual(set.membership, .dynamic(query))
        XCTAssertFalse(set.starred)
    }

    func testPublicInitializerSupportsSnapshotMembershipAndStarredState() {
        let assetID = AssetID(rawValue: "asset-1")
        let set = AssetSet(
            id: AssetSetID(rawValue: "set-3"),
            name: "Session snapshot",
            membership: .snapshot([assetID]),
            starred: true
        )

        XCTAssertEqual(set.membership, .snapshot([assetID]))
        XCTAssertTrue(set.starred)
        XCTAssertFalse(set.isDynamic)
    }
}
