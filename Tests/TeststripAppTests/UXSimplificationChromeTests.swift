import XCTest
@testable import TeststripApp

/// Covers the presentation-level contracts of the UX simplification sweep:
/// the "Find Best Shots" routing decision, the filter-bar default/more
/// partition, the trimmed view switcher, and the de-jargon labels.
final class UXSimplificationChromeTests: XCTestCase {
    // MARK: Find Best Shots routing

    func testFindBestShotsLandsOnPotentialPicksWhenTheyRank() {
        let plan = FindBestShotsRouter.plan(
            pickCount: 0,
            potentialPickCount: 12,
            canEvaluateScope: true,
            needsEvaluationCount: 3
        )
        XCTAssertEqual(plan.route, .reviewQueue(.potentialPicks))
        XCTAssertTrue(plan.shouldTriggerEvaluation)
    }

    func testFindBestShotsPrefersPotentialPicksOverCommittedPicks() {
        let plan = FindBestShotsRouter.plan(
            pickCount: 5,
            potentialPickCount: 8,
            canEvaluateScope: false,
            needsEvaluationCount: 0
        )
        XCTAssertEqual(plan.route, .reviewQueue(.potentialPicks))
        XCTAssertFalse(plan.shouldTriggerEvaluation)
    }

    func testFindBestShotsFallsBackToCommittedPicksWhenNothingRanksYet() {
        let plan = FindBestShotsRouter.plan(
            pickCount: 4,
            potentialPickCount: 0,
            canEvaluateScope: false,
            needsEvaluationCount: 0
        )
        XCTAssertEqual(plan.route, .reviewQueue(.picks))
    }

    func testFindBestShotsTriggersEvaluationAndRoutesToPotentialPicksOnAFreshScope() {
        // Nothing ranks yet but frames still need reading — kick off the pass
        // and land on Potential Picks so it fills in, never a dead end.
        let plan = FindBestShotsRouter.plan(
            pickCount: 0,
            potentialPickCount: 0,
            canEvaluateScope: true,
            needsEvaluationCount: 24
        )
        XCTAssertTrue(plan.shouldTriggerEvaluation)
        XCTAssertEqual(plan.route, .reviewQueue(.potentialPicks))
    }

    func testFindBestShotsNeverShowsABareZeroWhenNothingCanRank() {
        // Fully evaluated, genuinely distinct frames: plain language, no queue.
        let plan = FindBestShotsRouter.plan(
            pickCount: 0,
            potentialPickCount: 0,
            canEvaluateScope: false,
            needsEvaluationCount: 0
        )
        XCTAssertFalse(plan.shouldTriggerEvaluation)
        XCTAssertEqual(plan.route, .nothingRanked(message: FindBestShotsRouter.nothingRankedMessage))
        XCTAssertFalse(FindBestShotsRouter.nothingRankedMessage.contains("0"))
    }

    // MARK: Filter bar default/more partition

    func testFilterBarDefaultsToSortRatingFlagKeyword() {
        XCTAssertEqual(LibraryFilterBarLayout.defaultControls, [.sort, .rating, .flag, .keyword])
    }

    func testFilterBarTucksTechnicalControlsBehindMoreFilters() {
        XCTAssertEqual(LibraryFilterBarLayout.moreControls, [
            .folder, .camera, .lens, .iso, .date, .colorLabel, .source, .aiScore, .metadataSync
        ])
    }

    func testFilterBarPartitionIsCompleteAndNonOverlapping() {
        let all = LibraryFilterBarLayout.defaultControls + LibraryFilterBarLayout.moreControls
        XCTAssertEqual(Set(all), Set(LibraryFilterControl.allCases))
        XCTAssertEqual(all.count, LibraryFilterControl.allCases.count, "no control appears in both rows")
    }

    // MARK: View switcher de-duplication

    func testViewSwitcherExposesOnlyHowToViewModes() {
        let presentation = LibraryTopBarPresentation(
            catalogTitle: "Wedding Archive",
            libraryTitle: "All Photographs",
            libraryCountText: "1 photo",
            selectedView: .grid,
            activeFilterChips: []
        )
        XCTAssertEqual(presentation.modeItems.map(\.mode), [.grid, .loupe, .compare, .abCompare])
    }

    // MARK: De-jargon labels

    func testReviewQueueRenamesNeedsEvaluationToNotAnalyzedYet() {
        XCTAssertEqual(ReviewQueue.needsEvaluation.presentation.title, "Not analyzed yet")
    }

    // MARK: Import Path dev-control gating

    func testImportPathControlHiddenForRealUsersButShownForAutomation() {
        XCTAssertFalse(LibraryGridChromePolicy.shouldExposeImportPathControl(environment: [:]))
        XCTAssertTrue(LibraryGridChromePolicy.shouldExposeImportPathControl(environment: [
            "TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY": "/tmp/isolated"
        ]))
        XCTAssertFalse(LibraryGridChromePolicy.shouldExposeImportPathControl(environment: [
            "TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY": "   "
        ]))
    }
}
