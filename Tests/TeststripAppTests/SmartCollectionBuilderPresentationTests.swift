import XCTest
@testable import TeststripApp

final class SmartCollectionBuilderPresentationTests: XCTestCase {
    func testRuleAndMatchSummariesPluralize() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Portfolio Picks",
            ruleChips: ["Rating >= 4", "Pick"],
            matchCount: 42
        )

        XCTAssertEqual(presentation.ruleCountText, "2 rules")
        XCTAssertEqual(presentation.matchCountText, "42 matches")
        XCTAssertTrue(presentation.canCreate)
    }

    func testSingleRuleAndMatchSummariesUseSingularText() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "One Keeper",
            ruleChips: ["Pick"],
            matchCount: 1
        )

        XCTAssertEqual(presentation.ruleCountText, "1 rule")
        XCTAssertEqual(presentation.matchCountText, "1 match")
        XCTAssertTrue(presentation.canCreate)
    }

    func testCreateRequiresNameAndRules() {
        XCTAssertFalse(SmartCollectionBuilderPresentation(
            proposedName: "   ",
            ruleChips: ["Pick"],
            matchCount: 1
        ).canCreate)
        XCTAssertFalse(SmartCollectionBuilderPresentation(
            proposedName: "No Rules",
            ruleChips: [],
            matchCount: 12
        ).canCreate)
    }

    func testRuleRowsParseCommonFilterChipShapes() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Filtered",
            ruleChips: ["Search: Patagonia", "Rating >= 4", "Flag"],
            matchCount: 12
        )

        XCTAssertEqual(presentation.ruleRows, [
            SmartCollectionRuleRow(field: "Search", operation: "matches", value: "Patagonia"),
            SmartCollectionRuleRow(field: "Rating", operation: "is at least", value: "4"),
            SmartCollectionRuleRow(field: "Filter", operation: "matches", value: "Flag")
        ])
    }

    func testPreviewCountTextCapsAtMatchCount() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Preview",
            ruleChips: ["Pick"],
            matchCount: 3
        )

        XCTAssertEqual(presentation.previewCountText(visibleCount: 18), "showing 3")
        XCTAssertEqual(presentation.previewCountText(visibleCount: 2), "showing 2")
    }

    func testPreviewCountTextHandlesNoMatches() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Empty",
            ruleChips: ["Pick"],
            matchCount: 0
        )

        XCTAssertEqual(presentation.previewCountText(visibleCount: 0), "no live preview yet")
    }

    func testSuggestedTemplatesStayStable() {
        XCTAssertEqual(SmartCollectionBuilderPresentation.suggestedTemplates, [
            "Sharp keepers",
            "Golden hour",
            "Best of each trip"
        ])
    }

    func testAddRuleRowsExposeConcretePresetFilters() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Needs Review",
            ruleChips: ["Pick"],
            matchCount: 12
        )

        XCTAssertEqual(
            presentation.addRuleRows.map(\.title),
            [
                "4+ stars",
                "Picked",
                "Rejected",
                "Needs keywords",
                "Needs evaluation",
                "Online sources",
                "Offline sources",
                "Faces found",
                "OCR found",
                "Object signals",
                "Likely issues",
                "Provider failures",
                "XMP pending",
                "XMP conflicts"
            ]
        )
        XCTAssertTrue(presentation.addRuleRows.allSatisfy { !$0.systemImage.isEmpty })
    }
}
