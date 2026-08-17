import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullStartCardTests: XCTestCase {
    // MARK: - Batch stats computation

    func testBatchStatsForAllSingles() {
        let presentation = CullStartCardPresentation(
            photoCount: 10,
            stackCount: 0
        )

        XCTAssertEqual(presentation.photoCount, 10)
        XCTAssertEqual(presentation.stackCount, 0)
        XCTAssertEqual(presentation.burstPercentage, 0)
    }

    func testBatchStatsForAllBursts() {
        // 6 photos in 3 two-frame bursts
        let presentation = CullStartCardPresentation(
            photoCount: 6,
            stackCount: 3
        )

        XCTAssertEqual(presentation.burstPercentage, 50)
    }

    func testBatchStatsRoundsPercentage() {
        // 7 photos, 3 stacks → 3/7 = 42.857... → rounds to 43
        let presentation = CullStartCardPresentation(
            photoCount: 7,
            stackCount: 3
        )

        XCTAssertEqual(presentation.burstPercentage, 43)
    }

    // MARK: - Lens narrowing

    func testLensHiddenCountDefaultsToZero() {
        let presentation = CullStartCardPresentation(
            photoCount: 10,
            stackCount: 2
        )

        XCTAssertEqual(presentation.lensHiddenCount, 0)
    }

    func testLensHiddenCountIsNonZeroWhenNarrowed() {
        let presentation = CullStartCardPresentation(
            photoCount: 211,
            stackCount: 63,
            lensHiddenCount: 115
        )

        XCTAssertEqual(presentation.lensHiddenCount, 115)
    }

    // MARK: - Toggles default on

    func testTogglesDefaultOn() {
        let presentation = CullStartCardPresentation(
            photoCount: 10,
            stackCount: 0
        )

        XCTAssertTrue(presentation.autoAdvanceEnabled)
        XCTAssertTrue(presentation.landOnRecommended)
    }

    // MARK: - Batch description (tutorial §2 format)

    func testBatchDescriptionForMixedBatch() {
        let presentation = CullStartCardPresentation(
            photoCount: 211,
            stackCount: 63
        )

        XCTAssertEqual(presentation.batchDescription, "211 photos · 63 stacks (batch is 30% bursts)")
    }

    func testBatchDescriptionForAllSingles() {
        let presentation = CullStartCardPresentation(
            photoCount: 10,
            stackCount: 0
        )

        XCTAssertEqual(presentation.batchDescription, "10 photos · 0 stacks")
    }

    // MARK: - Lens description (tutorial §2 format)

    func testLensDescriptionWhenNotNarrowed() {
        let presentation = CullStartCardPresentation(
            photoCount: 100,
            stackCount: 5
        )

        XCTAssertNil(presentation.lensDescription)
    }

    func testLensDescriptionWhenNarrowed() {
        let presentation = CullStartCardPresentation(
            photoCount: 211,
            stackCount: 63,
            lensHiddenCount: 115
        )

        XCTAssertEqual(presentation.lensDescription, "Showing 96 of 211 — 115 hidden by lens")
    }
}
