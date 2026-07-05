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

    func testGroupsActiveFiltersIntoMockupRefineSections() {
        let presentation = SearchWorkspacePresentation(
            suggestedName: "Ceremony Review",
            totalAssetCount: 18,
            savedSetCount: 3,
            starredSetCount: 1,
            activeFilterChips: [
                "Pick",
                "Rating >= 4",
                "Camera: Canon",
                "Needs Keywords",
                "Signal: Face Quality",
                "Source: Offline",
                "XMP Pending",
                "Search: ceremony"
            ]
        )

        XCTAssertEqual(presentation.refineGroups, [
            SearchWorkspaceRefineGroup(title: "Decisions", rows: [
                SearchWorkspaceRefineRow(title: "Pick", value: "active"),
                SearchWorkspaceRefineRow(title: "Rating >= 4", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Metadata", rows: [
                SearchWorkspaceRefineRow(title: "Camera: Canon", value: "active"),
                SearchWorkspaceRefineRow(title: "Search: ceremony", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Review Queues", rows: [
                SearchWorkspaceRefineRow(title: "Needs Keywords", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Signals", rows: [
                SearchWorkspaceRefineRow(title: "Signal: Face Quality", value: "active")
            ]),
            SearchWorkspaceRefineGroup(title: "Source & XMP", rows: [
                SearchWorkspaceRefineRow(title: "Source: Offline", value: "active"),
                SearchWorkspaceRefineRow(title: "XMP Pending", value: "active")
            ])
        ])
    }
}
