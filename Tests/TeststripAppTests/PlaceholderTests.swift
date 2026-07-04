import XCTest
@testable import TeststripApp

final class LiveMockupPlaceholderTests: XCTestCase {
    func testRegistryUsesUniqueNonEmptyMarkers() {
        let placeholders = LiveMockupPlaceholders.all

        XCTAssertFalse(placeholders.isEmpty)
        XCTAssertEqual(Set(placeholders.map(\.id)).count, placeholders.count)
        XCTAssertTrue(placeholders.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(placeholders.allSatisfy { !$0.intendedBehavior.isEmpty })
        XCTAssertTrue(placeholders.allSatisfy { !$0.currentFallback.isEmpty })
    }

    func testRegistryTracksKnownMockupParityGaps() {
        let ids = Set(LiveMockupPlaceholders.all.map(\.id))

        XCTAssertTrue(ids.isSuperset(of: [
            "library.top-chrome",
            "search.agentic",
            "search.refine",
            "smart-collections.builder",
            "import.complete-summary",
            "culling.assist-verdict",
            "culling.filmstrip",
            "culling.stack-cull",
            "compare.survey"
        ]))
    }

    func testPeopleSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let peopleRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-people" })

        XCTAssertEqual(peopleRow.liveMockupPlaceholder, .peopleSidebar)
        XCTAssertTrue(peopleRow.isSelectable)
        XCTAssertEqual(peopleRow.target, .people)
    }

    func testSearchSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let searchRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-search" })

        XCTAssertEqual(searchRow.liveMockupPlaceholder, .agenticSearch)
        XCTAssertTrue(searchRow.isSelectable)
        XCTAssertEqual(searchRow.target, .search)
    }

    func testSelectingPeopleSidebarRowOpensPeopleView() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let peopleRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-people" })

        try model.selectSidebarRow(peopleRow)

        XCTAssertEqual(model.selectedView, .people)
    }

    func testSelectingSearchSidebarRowOpensSearchViewWithoutClearingQuery() throws {
        let model = AppModel.demo()
        model.librarySearchText = "ceremony"
        model.minimumRatingFilter = 4
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let searchRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-search" })

        try model.selectSidebarRow(searchRow)

        XCTAssertEqual(model.selectedView, .search)
        XCTAssertEqual(model.librarySearchText, "ceremony")
        XCTAssertEqual(model.minimumRatingFilter, 4)
    }

    func testEmptyWorkSidebarRowsAreMarkedAsLiveMockupPlaceholders() throws {
        let model = AppModel.demo()
        let workSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Work" })

        XCTAssertEqual(workSection.rows.map(\.title), ["Recent", "Starred"])
        XCTAssertTrue(workSection.rows.allSatisfy { $0.liveMockupPlaceholder == .workHistory })
        XCTAssertTrue(workSection.rows.allSatisfy { !$0.isSelectable })
    }
}
