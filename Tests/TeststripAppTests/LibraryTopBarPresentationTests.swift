import XCTest
@testable import TeststripApp

final class LibraryTopBarPresentationTests: XCTestCase {
    func testAllPhotographsUsesCatalogIdentityAndLibraryBreadcrumb() {
        let presentation = LibraryTopBarPresentation(
            libraryTitle: "All Photographs",
            libraryCountText: "486,204 photographs",
            selectedView: .grid,
            activeFilterChips: []
        )

        XCTAssertEqual(presentation.catalogTitle, "Master Catalog")
        XCTAssertEqual(presentation.catalogSubtitle, "486,204 photographs")
        XCTAssertEqual(presentation.scopeTitle, "All Photographs")
        XCTAssertEqual(presentation.breadcrumbItems, ["Library", "All Photographs"])
        XCTAssertNil(presentation.filterSummaryText)
    }

    func testFilteredScopeKeepsAllPhotographsAsBreadcrumbParent() {
        let presentation = LibraryTopBarPresentation(
            libraryTitle: "Patagonia Picks",
            libraryCountText: "Showing 84 of 486,204 photographs",
            selectedView: .grid,
            activeFilterChips: ["Rating >= 3", "Pick"]
        )

        XCTAssertEqual(presentation.breadcrumbItems, ["Library", "All Photographs", "Patagonia Picks"])
        XCTAssertEqual(presentation.filterSummaryText, "2 filters")
    }

    func testSearchTimelineAndPeopleAreDirectLibraryRoutes() {
        XCTAssertEqual(
            LibraryTopBarPresentation(
                libraryTitle: "Search",
                libraryCountText: "12 photographs",
                selectedView: .search,
                activeFilterChips: ["Search: ceremony"]
            ).breadcrumbItems,
            ["Library", "Search"]
        )
        XCTAssertEqual(
            LibraryTopBarPresentation(
                libraryTitle: "Timeline",
                libraryCountText: "12 photographs",
                selectedView: .timeline,
                activeFilterChips: []
            ).breadcrumbItems,
            ["Library", "Timeline"]
        )
        XCTAssertEqual(
            LibraryTopBarPresentation(
                libraryTitle: "People",
                libraryCountText: "12 photographs",
                selectedView: .people,
                activeFilterChips: []
            ).breadcrumbItems,
            ["Library", "People"]
        )
    }

    func testModeItemsExposeOnlyImplementedGoToMarketRoutes() {
        let presentation = LibraryTopBarPresentation(
            libraryTitle: "All Photographs",
            libraryCountText: "1 photograph",
            selectedView: .compare,
            activeFilterChips: []
        )

        XCTAssertEqual(presentation.modeItems.map(\.mode), [.grid, .search, .timeline, .loupe, .compare, .people])
        XCTAssertEqual(presentation.modeItems.map(\.title), ["Grid", "Search", "Timeline", "Loupe", "Compare", "People"])
    }
}
