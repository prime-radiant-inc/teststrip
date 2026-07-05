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

    func testTimelineLedgerTracksBuiltYearRibbonAndFocusedScrubberControls() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "library.timeline" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "1c" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("year-density ribbon"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("focused month/day scrubber"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("scroll-position syncing centers focused chips and sections"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("year-density ribbon"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("focused month/day scrubber"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("scroll-position syncing centers focused chips and sections"))
    }

    func testTopChromeLedgerTracksRealCatalogIdentity() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "library.top-chrome" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("real catalog identity"))
        XCTAssertFalse(placeholder.currentFallback.localizedCaseInsensitiveContains("static placeholder copy"))
    }

    func testImportCompleteLedgerTracksLiveActionsAndFaceReviewHandoff() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "import.complete-summary" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "4b" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("culling, stack-cull, compare, keyword, and face-review actions live"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("automatic identity naming remains disabled"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("culling, stack-cull, compare, and keyword actions"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("faces found review handoff"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("automatic naming remains disabled"))
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
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("keep all frames"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("keep top remains disabled"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("session progress"))
        XCTAssertTrue(stackPlaceholder.currentFallback.localizedCaseInsensitiveContains("similarity"))
        XCTAssertTrue(comparePlaceholder.currentFallback.localizedCaseInsensitiveContains("persisted culling stack sets"))
        XCTAssertTrue(comparePlaceholder.currentFallback.localizedCaseInsensitiveContains("loaded-scope candidate stacks"))
        XCTAssertTrue(comparePlaceholder.currentFallback.localizedCaseInsensitiveContains("up to eight"))
        XCTAssertTrue(comparePlaceholder.currentFallback.localizedCaseInsensitiveContains("4x2"))
        XCTAssertTrue(rapidCullSurface.currentImplementation.localizedCaseInsensitiveContains("Space advances"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("Return accepts"))
        XCTAssertEqual(stackSurface.status, .partial)
        XCTAssertTrue(compareSurface.currentImplementation.localizedCaseInsensitiveContains("persisted culling stack membership"))
        XCTAssertTrue(compareSurface.currentImplementation.localizedCaseInsensitiveContains("loaded-scope candidate stacks"))
        XCTAssertTrue(compareSurface.currentImplementation.localizedCaseInsensitiveContains("up to eight"))
        XCTAssertTrue(compareSurface.currentImplementation.localizedCaseInsensitiveContains("four-column"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("persisted import stack sets"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("keep-selected/reject-alternates and keep-all"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("sessions refresh progress"))
        XCTAssertTrue(stackSurface.currentImplementation.localizedCaseInsensitiveContains("near-duplicate"))
    }

    func testPeopleSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let peopleRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-people" })

        XCTAssertEqual(peopleRow.liveMockupPlaceholder, .peopleSidebar)
        XCTAssertEqual(peopleRow.detailText, "Face review")
        XCTAssertTrue(peopleRow.isSelectable)
        XCTAssertEqual(peopleRow.target, .people)
    }

    func testPeopleLedgerTracksUnnamedFaceReviewAndPersistedNamedRows() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "sidebar.people" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5a" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("unnamed face review"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("Apple Vision scan action"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("face-review strip"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("Name selection"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("face-review dismissal"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("persisted named people rows"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("manual merge"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("automatic clustering"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("face-box-level naming remain disabled"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("unnamed face review"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("Apple Vision scan action"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("face-review strip"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("Name selection"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("face-review dismissal"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("persisted named people rows"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("manual merge"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("automatic clustering"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("face-box-level naming remain disabled"))
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

    func testKeywordingLedgerTracksCurrentScopeBatchMetadataGaps() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "keywording.batch" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5e" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("selected/visible/current-scope metadata popover"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("latest-import keyword review"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("command and shift selected assets"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("all-catalog confirmation"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("freeform bulk keyword review is not built"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("selected/visible/current-scope metadata popover"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("latest-import keyword review"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("command and shift selected assets"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("all-catalog confirmation"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("freeform bulk keyword review is not built"))
    }

    func testSmartCollectionsLedgerTracksRulePresetsWithoutFreeformEditing() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "smart-collections.builder" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "5d" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("add rule presets"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("suggestion rows are actionable"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("review queue counts"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("delete set confirmation"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("current library query"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("freeform rule editing"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("provider-generated suggestions are not built"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("add rule presets"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("suggestion rows are actionable"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("review queue counts"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("delete set confirmation"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("loaded-result preview"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("freeform rule editing"))
        XCTAssertTrue(surface.currentImplementation.localizedCaseInsensitiveContains("provider-generated suggestions are not built"))
    }

    func testSearchRefineLedgerTracksGeneratedRefinementsAndSuggestedActions() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "search.refine" })

        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("known target rows are actionable"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("related filters"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("generated refinements"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("suggested actions"))
        XCTAssertTrue(placeholder.currentFallback.localizedCaseInsensitiveContains("broader natural-language planning is not built"))
    }

    func testEmptyFoldersSidebarRowIsMarkedAsLiveMockupPlaceholder() throws {
        let model = AppModel.demo()
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let foldersRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-folders" })

        XCTAssertEqual(foldersRow.title, "Folders")
        XCTAssertEqual(foldersRow.detailText, "No folders yet")
        XCTAssertEqual(foldersRow.liveMockupPlaceholder?.id, "sidebar.folders-empty")
        XCTAssertFalse(foldersRow.isSelectable)
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
