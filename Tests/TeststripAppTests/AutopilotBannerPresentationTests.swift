import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class AutopilotBannerPresentationTests: XCTestCase {
    func testBannerSummarizesKeepersRejectsAndStacks() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 890, rejectCount: 340, keywordCount: 12, stackCount: 27
        )
        let presentation = AutopilotBannerPresentation(summary: summary)
        XCTAssertEqual(presentation.title, "Autopilot reviewed 1,230 frames")
        XCTAssertEqual(presentation.detailText, "890 keepers · 340 rejects · dupes→stacks")
        XCTAssertTrue(presentation.canUndoAll == false) // no committed batch yet
    }

    func testBannerHidesStacksSegmentWithoutStacks() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 5, rejectCount: 2, keywordCount: 0, stackCount: 0
        )
        XCTAssertEqual(AutopilotBannerPresentation(summary: summary).detailText, "5 keepers · 2 rejects")
    }
}
