import XCTest
@testable import TeststripCore

final class PersonCandidateRankerTests: XCTestCase {
    private let names = ["p1": "Ann", "p2": "Bob", "p3": "Cy"]

    func testRanksByDistanceNearestFirstWithPercent() {
        let centroids: [String: [Double]] = ["p1": [1, 0, 0], "p2": [0, 1, 0]]
        let result = PersonCandidateRanker.rank(
            targetEmbedding: [1, 0, 0], centroidsByPerson: centroids,
            namesByID: names, recentPersonIDs: [])
        // p1 (distance 0) first at 100%; p2 (distance √2) next at 0%; p3 (no centroid) tail nil.
        XCTAssertEqual(result.map(\.id), ["p1", "p2", "p3"])
        XCTAssertEqual(result[0].similarityPercent, 100)
        XCTAssertEqual(result[1].similarityPercent, 0)
        XCTAssertNil(result[2].similarityPercent)
    }

    func testNoTargetOrdersByRecencyThenAlpha() {
        let result = PersonCandidateRanker.rank(
            targetEmbedding: nil, centroidsByPerson: ["p1": [1, 0, 0]],
            namesByID: names, recentPersonIDs: ["p3"]) // p3 most-recent
        // No target → all tail: p3 (recent) first, then Ann, Bob alpha.
        XCTAssertEqual(result.map(\.id), ["p3", "p1", "p2"])
        XCTAssertTrue(result.allSatisfy { $0.similarityPercent == nil })
    }

    func testNoCentroidPeopleGoToRecencyTail() {
        let centroids: [String: [Double]] = ["p2": [0, 1, 0]]
        let result = PersonCandidateRanker.rank(
            targetEmbedding: [1, 0, 0], centroidsByPerson: centroids,
            namesByID: names, recentPersonIDs: ["p3", "p1"])
        // p2 has a centroid → first (with %); p3, p1 tail by recency order.
        XCTAssertEqual(result.map(\.id), ["p2", "p3", "p1"])
        XCTAssertNotNil(result[0].similarityPercent)
        XCTAssertNil(result[1].similarityPercent)
    }

    func testContactOnlyPersonIsIncludedAndRankable() {
        // A person present only via a contact reference (centroid + name) ranks like any other.
        let result = PersonCandidateRanker.rank(
            targetEmbedding: [1, 0, 0],
            centroidsByPerson: ["contact:C1": [0.99, 0.01, 0]],
            namesByID: ["contact:C1": "Dan"], recentPersonIDs: [])
        XCTAssertEqual(result.map(\.id), ["contact:C1"])
        XCTAssertNotNil(result[0].similarityPercent)
    }
}
