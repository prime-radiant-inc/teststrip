import XCTest
@testable import TeststripApp

final class LibraryTopBarPresentationTests: XCTestCase {
    func testAllPhotographsUsesCatalogIdentityAndLibraryBreadcrumb() {
        let presentation = LibraryTopBarPresentation(
            catalogTitle: "Wedding Archive",
            libraryTitle: "All Photographs",
            libraryCountText: "486,204 photos",
            selectedView: .grid,
            activeFilterChips: []
        )

        XCTAssertEqual(presentation.catalogTitle, "Wedding Archive")
        XCTAssertEqual(presentation.catalogSubtitle, "486,204 photos")
        XCTAssertEqual(presentation.scopeTitle, "All Photographs")
        XCTAssertEqual(presentation.breadcrumbItems, ["Library", "All Photographs"])
        XCTAssertNil(presentation.filterSummaryText)
    }

    func testFilteredScopeKeepsAllPhotographsAsBreadcrumbParent() {
        let presentation = LibraryTopBarPresentation(
            catalogTitle: "Wedding Archive",
            libraryTitle: "Patagonia Picks",
            libraryCountText: "Showing 84 of 486,204 photos",
            selectedView: .grid,
            activeFilterChips: ["Rating >= 3", "Pick"]
        )

        XCTAssertEqual(presentation.breadcrumbItems, ["Library", "All Photographs", "Patagonia Picks"])
        XCTAssertEqual(presentation.filterSummaryText, "2 filters")
    }

    func testSearchTimelineCopilotAndPeopleAreDirectLibraryRoutes() {
        XCTAssertEqual(
            LibraryTopBarPresentation(
                catalogTitle: "Wedding Archive",
                libraryTitle: "Search",
                libraryCountText: "12 photos",
                selectedView: .search,
                activeFilterChips: ["Search: ceremony"]
            ).breadcrumbItems,
            ["Library", "Search"]
        )
        XCTAssertEqual(
            LibraryTopBarPresentation(
                catalogTitle: "Wedding Archive",
                libraryTitle: "Timeline",
                libraryCountText: "12 photos",
                selectedView: .timeline,
                activeFilterChips: []
            ).breadcrumbItems,
            ["Library", "Timeline"]
        )
        XCTAssertEqual(
            LibraryTopBarPresentation(
                catalogTitle: "Wedding Archive",
                libraryTitle: "Review",
                libraryCountText: "12 photos",
                selectedView: .copilot,
                activeFilterChips: []
            ).breadcrumbItems,
            ["Library", "Review"]
        )
        XCTAssertEqual(
            LibraryTopBarPresentation(
                catalogTitle: "Wedding Archive",
                libraryTitle: "People",
                libraryCountText: "12 photos",
                selectedView: .people,
                activeFilterChips: []
            ).breadcrumbItems,
            ["Library", "People"]
        )
    }

    func testModeItemsExposeOnlyImplementedGoToMarketRoutes() {
        let presentation = LibraryTopBarPresentation(
            catalogTitle: "Wedding Archive",
            libraryTitle: "All Photographs",
            libraryCountText: "1 photo",
            selectedView: .compare,
            activeFilterChips: []
        )

        XCTAssertEqual(presentation.modeItems.map(\.mode), [.grid, .loupe, .compare, .abCompare])
        XCTAssertEqual(presentation.modeItems.map(\.title), ["Grid", "Loupe", "Compare", "A/B"])
    }

    func testPartialTopBarRoutesCarryLiveMockupPlaceholders() {
        let presentation = LibraryTopBarPresentation(
            catalogTitle: "Wedding Archive",
            libraryTitle: "All Photographs",
            libraryCountText: "1 photo",
            selectedView: .grid,
            activeFilterChips: []
        )

        XCTAssertEqual(
            presentation.modeItems.map(\.mode),
            [.grid, .loupe, .compare, .abCompare]
        )
        XCTAssertEqual(
            presentation.modeItems.map { $0.liveMockupPlaceholder?.id },
            [nil, nil, "compare.survey", "compare.focus"]
        )
    }
}
