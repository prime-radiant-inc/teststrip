import XCTest
@testable import TeststripApp

final class SearchWorkspacePresentationTests: XCTestCase {
    func testBuildsRefineRailFromCurrentSearchState() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Pick 4+ Stars",
            totalAssetCount: 42,
            savedSetCount: 6,
            starredSetCount: 2,
            activeFilterChips: ["Pick", "Rating >= 4", "Camera: Canon"]
        )

        XCTAssertEqual(presentation.title, "Pick 4+ Stars")
        XCTAssertEqual(presentation.resultCountText, "42")
        XCTAssertEqual(presentation.savedSetCountText, "6")
        XCTAssertEqual(presentation.starredSetCountText, "2")
        XCTAssertEqual(presentation.refineRows, [
            SearchWorkspaceRefineRow(title: "Pick", value: "active"),
            SearchWorkspaceRefineRow(title: "Rating >= 4", value: "active"),
            SearchWorkspaceRefineRow(title: "Camera: Canon", value: "active")
        ])
    }

    func testUsesAllPhotographsRefineRowWhenNoFiltersAreActive() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "All Photographs",
            totalAssetCount: 120,
            savedSetCount: 0,
            starredSetCount: 0,
            activeFilterChips: []
        )

        XCTAssertEqual(presentation.refineRows, [
            SearchWorkspaceRefineRow(title: "All photographs", value: "current scope")
        ])
    }
}
