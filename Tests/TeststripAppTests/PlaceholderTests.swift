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

    func testDesignSurfaceRegistryCoversDesignerMockupIds() {
        let surfaces = LiveMockupDesignSurfaces.all

        XCTAssertEqual(
            surfaces.map(\.designID),
            ["1a", "1b", "1c", "2a", "2b", "3a", "3b", "4a", "4b", "5a", "5b", "5c", "5d", "5e", "5f"]
        )
        XCTAssertTrue(surfaces.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(surfaces.allSatisfy { !$0.currentImplementation.isEmpty })
        XCTAssertEqual(Set(surfaces.map(\.designID)).count, surfaces.count)
    }

    func testDeferredDesignSurfacesDoNotReopenScopedOutProductFeatures() throws {
        let places = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5b" })
        let export = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5f" })

        XCTAssertEqual(places.status, .deferred)
        XCTAssertEqual(export.status, .deferred)
        XCTAssertTrue(places.currentImplementation.localizedCaseInsensitiveContains("out of scope"))
        XCTAssertTrue(export.currentImplementation.localizedCaseInsensitiveContains("out of scope"))
    }

    func testTimelineLedgerTracksBuiltYearRibbonAndRemainingScrubberGap() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "library.timeline" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "1c" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("year-density ribbon"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("scrubber remains pending"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("year-density ribbon"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("scrubber remains pending"))
    }

    func testImportCompleteLedgerTracksLiveActionsAndRemainingDisabledFollowups() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "import.complete-summary" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "4b" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("culling, compare, and keyword actions live"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("stack and face follow-ups stay disabled"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("culling, compare, and keyword actions"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("stack grouping and face naming remain disabled"))
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
