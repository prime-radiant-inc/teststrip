import XCTest
import TeststripCore
@testable import TeststripApp

final class CullHUDPresentationTests: XCTestCase {
    func testComputesUndecidedCountFromTotalMinusPicksAndRejects() {
        let summary = CullingProgressSummary(
            selectedPosition: 2,
            positionText: "Frame 2 of 10",
            pickCount: 3,
            rejectCount: 2,
            totalCount: 10
        )

        let presentation = CullHUDPresentation(
            filename: "IMG_0042.CR2",
            rating: 4,
            colorLabel: .green,
            summary: summary,
            verdict: nil
        )

        XCTAssertEqual(presentation.filename, "IMG_0042.CR2")
        XCTAssertEqual(presentation.rating, 4)
        XCTAssertEqual(presentation.colorLabel, .green)
        XCTAssertEqual(presentation.pickCount, 3)
        XCTAssertEqual(presentation.rejectCount, 2)
        XCTAssertEqual(presentation.undecidedCount, 5)
        XCTAssertEqual(presentation.progressFraction, 0.5, accuracy: 0.0001)
        XCTAssertNil(presentation.verdict)
    }

    func testUndecidedCountNeverGoesNegativeWhenReviewedExceedsTotal() {
        let summary = CullingProgressSummary(
            selectedPosition: nil,
            positionText: nil,
            pickCount: 6,
            rejectCount: 6,
            totalCount: 10
        )

        let presentation = CullHUDPresentation(
            filename: "IMG_0001.CR2",
            rating: 0,
            colorLabel: nil,
            summary: summary,
            verdict: nil
        )

        XCTAssertEqual(presentation.undecidedCount, 0)
    }

    func testProgressFractionIsZeroWhenTotalIsZero() {
        let summary = CullingProgressSummary(
            selectedPosition: nil,
            positionText: nil,
            pickCount: 0,
            rejectCount: 0,
            totalCount: 0
        )

        let presentation = CullHUDPresentation(
            filename: "IMG_0001.CR2",
            rating: 0,
            colorLabel: nil,
            summary: summary,
            verdict: nil
        )

        XCTAssertEqual(presentation.progressFraction, 0)
        XCTAssertEqual(presentation.undecidedCount, 0)
    }

    func testVerdictPassesThroughUnchanged() {
        let summary = CullingProgressSummary(
            selectedPosition: 1,
            positionText: "Frame 1 of 1",
            pickCount: 0,
            rejectCount: 0,
            totalCount: 1
        )

        let presentation = CullHUDPresentation(
            filename: "IMG_0099.CR2",
            rating: 0,
            colorLabel: nil,
            summary: summary,
            verdict: "Keep"
        )

        XCTAssertEqual(presentation.verdict, "Keep")
    }
}
