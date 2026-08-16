import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class ScopeLineLoudAccountingTests: XCTestCase {
    func testSkippedSegmentAppearsWhenNonZero() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 326,
            skippedCount: 12
        )

        XCTAssertEqual(line.statusText, "854 photos · 326 stacks · ✓ 15 · ✕ 5 · ⊘ 12 skipped · 834 left")
    }

    func testUnviewedSegmentAppearsWhenNonZero() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 0,
            neverViewedCount: 3
        )

        XCTAssertEqual(line.statusText, "854 photos · ✓ 15 · ✕ 5 · ◌ 3 unviewed · 834 left")
    }

    func testAwaitingSegmentAppearsWhenNonZero() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 0,
            awaitingReviewCount: 96
        )

        XCTAssertEqual(line.statusText, "854 photos · ✓ 15 · ✕ 5 · ✨ 96 awaiting · 834 left")
    }

    func testAllNewSegmentsAppearTogether() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 326,
            skippedCount: 12,
            neverViewedCount: 3,
            awaitingReviewCount: 96
        )

        XCTAssertEqual(
            line.statusText,
            "854 photos · 326 stacks · ✓ 15 · ✕ 5 · ⊘ 12 skipped · ◌ 3 unviewed · ✨ 96 awaiting · 834 left"
        )
    }

    func testZeroCountsOmitNewSegments() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 326,
            skippedCount: 0,
            neverViewedCount: 0,
            awaitingReviewCount: 0
        )

        XCTAssertEqual(line.statusText, "854 photos · 326 stacks · ✓ 15 · ✕ 5 · 834 left")
    }

    func testExistingCallersWithoutNewParamsAreUnchanged() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 326
        )

        XCTAssertEqual(line.statusText, "854 photos · 326 stacks · ✓ 15 · ✕ 5 · 834 left")
    }
}
