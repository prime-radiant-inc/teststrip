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

    func testBannerNamesKeywordSuggestionsWhenNoKeepCutVerdicts() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 0, rejectCount: 0, keywordCount: 95, stackCount: 0
        )
        let detail = AutopilotBannerPresentation(summary: summary).detailText
        XCTAssertEqual(detail, "No clear cuts to propose — 95 keyword suggestions ready to review")
        XCTAssertFalse(detail.contains("0 keepers"))
    }

    func testBannerSingularKeywordSuggestion() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 0, rejectCount: 0, keywordCount: 1, stackCount: 0
        )
        XCTAssertEqual(
            AutopilotBannerPresentation(summary: summary).detailText,
            "No clear cuts to propose — 1 keyword suggestion ready to review"
        )
    }

    func testBannerReportsTooDistinctWhenNothingToPropose() {
        let summary = AutopilotRunSummary(
            runID: AutopilotRunID(rawValue: "r"),
            keeperCount: 0, rejectCount: 0, keywordCount: 0, stackCount: 0
        )
        let detail = AutopilotBannerPresentation(summary: summary).detailText
        XCTAssertEqual(detail, "These look too distinct to auto-rank — rate a few to rank")
        XCTAssertFalse(detail.contains("0 keepers"))
    }
}
