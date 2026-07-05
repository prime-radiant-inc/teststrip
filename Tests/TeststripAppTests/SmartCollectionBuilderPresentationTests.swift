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

    func testSuggestedTemplateRowsExposeConcretePresetActions() {
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Filtered",
            ruleChips: ["Search: ceremony"],
            matchCount: 12,
            reviewQueueCounts: [
                .fiveStars: 5,
                .picks: 4,
                .facesFound: 2,
                .needsKeywords: 6
            ]
        )

        XCTAssertEqual(presentation.suggestedTemplateRows, [
            SmartCollectionSuggestedTemplateRow(
                title: "Picked keepers",
                detail: "4 picks, 5 rated",
                systemImage: "star.circle",
                presets: [.ratingFourPlus, .picked]
            ),
            SmartCollectionSuggestedTemplateRow(
                title: "Face review",
                detail: "2 photos have faces",
                systemImage: "person.2.circle",
                presets: [.facesFound]
            ),
            SmartCollectionSuggestedTemplateRow(
                title: "Needs keywords",
                detail: "6 photos need keywords",
                systemImage: "tag.circle",
                presets: [.needsKeywords]
            )
        ])
    }

    func testSuggestedTemplateRowsSkipActiveRulesAndRequireCatalogSignals() {
        XCTAssertEqual(SmartCollectionBuilderPresentation(
            proposedName: "No Signals",
            ruleChips: [],
            matchCount: 12,
            reviewQueueCounts: [:]
        ).suggestedTemplateRows, [])

        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Picked",
            ruleChips: ["Pick"],
            matchCount: 12,
            reviewQueueCounts: [
                .fiveStars: 5,
                .picks: 4,
                .facesFound: 1,
                .needsEvaluation: 3
            ]
        )

        XCTAssertEqual(presentation.suggestedTemplateRows, [
            SmartCollectionSuggestedTemplateRow(
                title: "Face review",
                detail: "1 photo has faces",
                systemImage: "person.2.circle",
                presets: [.facesFound]
            ),
            SmartCollectionSuggestedTemplateRow(
                title: "Needs evaluation",
                detail: "3 photos need evaluation",
                systemImage: "wand.and.stars.inverse",
                presets: [.needsEvaluation]
            )
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
