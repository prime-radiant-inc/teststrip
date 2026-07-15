import XCTest
@testable import TeststripCore

final class FaceSimilarityTests: XCTestCase {
    func testPercentAtZeroDistanceIs100() {
        XCTAssertEqual(FaceSimilarity.percent(distance: 0), 100) // s = 1 − 0 = 1
    }

    func testPercentAtOrthogonalIsZero() {
        // d = √2 → s = 1 − 2/2 = 0
        XCTAssertEqual(FaceSimilarity.percent(distance: 2.0.squareRoot()), 0)
    }

    func testPercentAtMatchThreshold() {
        // d = 1.23 → s = 1 − 1.23²/2 = 0.24355 → 24%
        XCTAssertEqual(FaceSimilarity.percent(distance: 1.23), 24)
    }

    func testPercentClampsNegativeCosineToZero() {
        // d = 2 (antipodal) → s = 1 − 2 = −1 → clamped to 0
        XCTAssertEqual(FaceSimilarity.percent(distance: 2.0), 0)
    }

    func testCentroidAndDistanceArePublic() {
        // Compiles only if the helpers are public.
        let c = FaceSuggestionBuilder.centroid(of: [[1, 0, 0], [1, 0, 0]])
        XCTAssertEqual(c, [1, 0, 0])
        XCTAssertEqual(FaceSuggestionBuilder.distance([1, 0, 0], [1, 0, 0]), 0)
        XCTAssertEqual(FaceSuggestionBuilder.normalized([2, 0, 0]), [1, 0, 0])
    }
}
