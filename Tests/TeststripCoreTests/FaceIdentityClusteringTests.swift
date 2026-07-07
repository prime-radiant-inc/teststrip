import XCTest
@testable import TeststripCore

final class FaceIdentityClusteringTests: XCTestCase {
    private func unit(_ seed: [Double]) -> [Double] {
        let n = seed.map { $0 * $0 }.reduce(0, +).squareRoot(); return seed.map { $0 / n }
    }

    private func face(_ id: String, _ vector: [Double]) -> FaceEmbedding {
        FaceEmbedding(faceID: FaceID(assetID: AssetID(rawValue: id), faceIndex: 0), vector: vector)
    }

    func testSamePersonClustersDifferentPersonDoesNot() {
        // Two "person A" vectors at cosine 0.549 → Euclidean d ≈ 0.95: above the
        // old 0.85 feature-print threshold (they would NOT group there) but well
        // within the retuned ArcFace scale. Person B is orthogonal (d ≈ 1.41).
        let a1 = unit([1, 0, 0])
        let a2 = unit([0.549, 0.836, 0])
        let b = unit([0, 0, 1])
        let faces = [face("a1", a1), face("a2", a2), face("b", b)]
        let s = FaceSuggestionBuilder().suggestions(unassignedFaces: faces, confirmedFacesByPerson: [:])
        // a1,a2 cluster together; b is a singleton and dropped by minimum cluster size.
        XCTAssertEqual(s.clusters.count, 1)
        XCTAssertEqual(Set(s.clusters[0].faceIDs.map(\.assetID.rawValue)), ["a1", "a2"])
    }
}
