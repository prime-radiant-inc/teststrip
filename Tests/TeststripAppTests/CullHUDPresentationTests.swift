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
            verdict: nil,
            scope: .all
        )

        XCTAssertEqual(presentation.filename, "IMG_0042.CR2")
        XCTAssertEqual(presentation.rating, 4)
        XCTAssertEqual(presentation.colorLabel, .green)
        XCTAssertEqual(presentation.pickCount, 3)
        XCTAssertEqual(presentation.rejectCount, 2)
        XCTAssertEqual(presentation.undecidedCount, 5)
        XCTAssertEqual(presentation.progressFraction, 0.5, accuracy: 0.0001)
        XCTAssertNil(presentation.verdict)
        XCTAssertEqual(presentation.scope, .all)
    }

    func testScopePassesThroughUnchanged() {
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
            verdict: nil,
            scope: .picks
        )

        XCTAssertEqual(presentation.scope, .picks)
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

    // MARK: - Progressive disclosure visibility matrix

    private func makePresentation(
        rating: Int = 0,
        colorLabel: ColorLabel? = nil,
        scope: CullScope = .all,
        isRatingEchoActive: Bool = false,
        pickCount: Int = 0,
        rejectCount: Int = 0,
        totalCount: Int = 0
    ) -> CullHUDPresentation {
        let summary = CullingProgressSummary(
            selectedPosition: nil,
            positionText: nil,
            pickCount: pickCount,
            rejectCount: rejectCount,
            totalCount: totalCount
        )
        return CullHUDPresentation(
            filename: "IMG_0001.CR2",
            rating: rating,
            colorLabel: colorLabel,
            summary: summary,
            verdict: nil,
            scope: scope,
            isRatingEchoActive: isRatingEchoActive
        )
    }

    func testScopeChipHiddenWhenScopeIsAll() {
        XCTAssertFalse(makePresentation(scope: .all).showsScopeChip)
    }

    func testScopeChipShownWhenScopeIsNotAll() {
        XCTAssertTrue(makePresentation(scope: .picks).showsScopeChip)
    }

    func testRatingHiddenWhenZeroAndNoEcho() {
        XCTAssertFalse(makePresentation(rating: 0, isRatingEchoActive: false).showsRating)
    }

    func testRatingShownWhenGreaterThanZero() {
        XCTAssertTrue(makePresentation(rating: 3, isRatingEchoActive: false).showsRating)
    }

    func testRatingShownDuringEchoWindowEvenWhenZero() {
        XCTAssertTrue(makePresentation(rating: 0, isRatingEchoActive: true).showsRating)
    }

    func testLabelDotHiddenWhenNoColorLabel() {
        XCTAssertFalse(makePresentation(colorLabel: nil).showsLabelDot)
    }

    func testLabelDotShownWhenColorLabelSet() {
        XCTAssertTrue(makePresentation(colorLabel: .green).showsLabelDot)
    }

    func testSessionClusterTextFormatsPicksRejectsAndUndecided() {
        let presentation = makePresentation(pickCount: 38, rejectCount: 71, totalCount: 318)
        // undecided = 318 - 38 - 71 = 209
        XCTAssertEqual(presentation.sessionClusterText, "\u{2713} 38 \u{00B7} \u{2715} 71 \u{00B7} 209 left")
    }

    func testUndecidedDefaultScopeFrameShowsOnlyFilenameAndCluster() {
        let presentation = makePresentation(
            rating: 0,
            colorLabel: nil,
            scope: .all,
            isRatingEchoActive: false,
            pickCount: 3,
            rejectCount: 2,
            totalCount: 10
        )
        XCTAssertFalse(presentation.showsScopeChip)
        XCTAssertFalse(presentation.showsRating)
        XCTAssertFalse(presentation.showsLabelDot)
        XCTAssertEqual(presentation.sessionClusterText, "\u{2713} 3 \u{00B7} \u{2715} 2 \u{00B7} 5 left")
    }
}
