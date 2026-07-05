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
            "library.copilot",
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

    func testTimelineLedgerTracksBuiltYearRibbonAndMonthYearControls() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "library.timeline" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "1c" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("year-density ribbon"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("month and year drill-down"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("year-density ribbon"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("month and year drill-down"))
    }

    func testImportCompleteLedgerTracksLiveActionsAndRemainingDisabledFollowups() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "import.complete-summary" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "4b" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("culling, stack-cull, compare, and keyword actions live"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("face follow-ups stay disabled"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("culling, stack-cull, compare, and keyword actions"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("face naming remains a disabled placeholder"))
    }

    func testCompareLedgerTracksStackCullActionsAndRemainingSimilarityGap() throws {
        let stackPlaceholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "culling.stack-cull" })
        let comparePlaceholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "compare.survey" })
        let rapidCullSurface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "2a" })
        let compareSurface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "2b" })
        let stackSurface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "3a" })

        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("keep a selected"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("keep frame"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("keep top"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("keep all"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("disabled"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("similarity"))
        XCTAssertTrue(comparePlaceholder.currentFallback.localizedCaseInsensitiveContains("loaded-scope candidate stacks"))
        XCTAssertTrue(rapidCullSurface.currentImplementation.localizedCaseInsensitiveContains("Space advances"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("Return accepts"))
        XCTAssertTrue(compareSurface.currentImplementation.localizedCaseInsensitiveContains("candidate stacks"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("keep-selected/reject-alternates"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("near-duplicate"))
    }

    func testPeopleSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let peopleRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-people" })

        XCTAssertEqual(peopleRow.liveMockupPlaceholder, .peopleSidebar)
        XCTAssertTrue(peopleRow.isSelectable)
        XCTAssertEqual(peopleRow.target, .people)
    }

    func testPeopleLedgerTracksUnnamedFaceReviewEntrypointsWithoutNamedIdentities() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "sidebar.people" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5a" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("unnamed face review"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("naming remains disabled"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("no named identities"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("unnamed face review"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("naming remains disabled"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("no named identities"))
    }

    func testCopilotLedgerTracksLiveRouteWithoutAutonomousActions() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "library.copilot" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "1b" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("copilot route"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("review queues"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("autonomous"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("copilot route"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("autonomous"))
    }

    func testKeywordingLedgerTracksCurrentScopeSuggestionsWithoutFullBatchMetadataEditing() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "keywording.batch" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5e" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("current-scope keyword suggestions"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("full batch metadata review is not built"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("current-scope keyword suggestions"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("full batch metadata review is not built"))
    }

    func testSearchRefineLedgerTracksActionableKnownTargetsWithoutAgentSuggestions() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "search.refine" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("known target rows are actionable"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("agent set actions are not built"))
    }

    func testSearchSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let searchRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-search" })

        XCTAssertEqual(searchRow.liveMockupPlaceholder, .agenticSearch)
        XCTAssertTrue(searchRow.isSelectable)
        XCTAssertEqual(searchRow.target, .search)
    }

    func testCopilotSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let copilotRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-copilot" })

        XCTAssertEqual(copilotRow.liveMockupPlaceholder, .copilotLibrary)
        XCTAssertTrue(copilotRow.isSelectable)
        XCTAssertEqual(copilotRow.target, .copilot)
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

    func testSelectingCopilotSidebarRowOpensCopilotWithoutClearingScope() throws {
        let model = AppModel.demo()
        model.librarySearchText = "ceremony"
        model.minimumRatingFilter = 4
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let copilotRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-copilot" })

        try model.selectSidebarRow(copilotRow)

        XCTAssertEqual(model.selectedView, .copilot)
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
