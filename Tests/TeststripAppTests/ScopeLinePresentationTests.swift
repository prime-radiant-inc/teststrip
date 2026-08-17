import XCTest
@testable import TeststripCore
@testable import TeststripApp

// A persistent line under the toolbar names the source and shows
// lens-appropriate status: run progress in Cull, result count and active
// filters in the browse lenses.
final class ScopeLinePresentationTests: XCTestCase {
    func testBrowseLensesShowTheResultCount() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .grid,
            resultCount: 42,
            activeFilterChips: [],
            cullProgress: nil,
            stackCount: 0
        )

        XCTAssertEqual(line.sourceTitle, "All Photos")
        XCTAssertEqual(line.statusText, "42 photos")
    }

    func testBrowseLensesAppendActiveFilters() {
        let line = ScopeLinePresentation.line(
            source: .smartCollection(.likelyIssues),
            lens: .grid,
            resultCount: 1,
            activeFilterChips: ["Likely Issues", "Pick"],
            cullProgress: nil,
            stackCount: 0
        )

        XCTAssertEqual(line.sourceTitle, "Likely Issues")
        XCTAssertEqual(line.statusText, "1 photo · Likely Issues + Pick")
    }

    func testTheCullLensShowsRunProgress() {
        let line = ScopeLinePresentation.line(
            source: .workSession(WorkSessionID(rawValue: "import-1"), titled: "Aug 7 · Imported from /Cards/A"),
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854,
                viewedCount: 20
            ),
            stackCount: 326
        )

        XCTAssertEqual(line.sourceTitle, "Aug 7 · Imported from /Cards/A")
        XCTAssertEqual(line.statusText, "854 photos · 326 stacks · ✓ 15 · ✕ 5 · 834 left")
    }

    func testTheCullLensOmitsStacksWhenThereAreNone() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 4,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 4",
                pickCount: 1,
                rejectCount: 1,
                totalCount: 4,
                viewedCount: 2
            ),
            stackCount: 0
        )

        XCTAssertEqual(line.statusText, "4 photos · ✓ 1 · ✕ 1 · 2 left")
    }

    /// When a cull session is active, `cullProgress.totalCount` is the source
    /// of truth for the photo count — `resultCount` is dead in that branch and
    /// must not win even when the two differ.
    func testCullProgressTotalCountWinsOverResultCount() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 999,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 12",
                pickCount: 0,
                rejectCount: 0,
                totalCount: 12
            ),
            stackCount: 0
        )

        // 12 (cullProgress.totalCount), not 999 (resultCount)
        XCTAssertEqual(line.statusText, "12 photos · ✓ 0 · ✕ 0 · 12 left")
    }

    func testTheCullLensFallsBackToTheResultCountWithNoRun() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 9,
            activeFilterChips: [],
            cullProgress: nil,
            stackCount: 0
        )

        XCTAssertEqual(line.statusText, "9 photos")
    }

    func testTheLineAlwaysNamesTheSourceInEveryLens() {
        for lens in LibraryLens.allCases {
            let line = ScopeLinePresentation.line(
                source: .folder("/Photos/2026"),
                lens: lens,
                resultCount: 3,
                activeFilterChips: [],
                cullProgress: nil,
                stackCount: 0
            )
            XCTAssertEqual(line.sourceTitle, "2026", "\(lens)")
        }
    }
}
