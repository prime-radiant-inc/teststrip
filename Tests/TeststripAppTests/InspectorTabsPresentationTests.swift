import XCTest
@testable import TeststripApp

/// Anti-orphan check: every inspector element identified in the Task 11
/// brief must land in exactly one tab. If a new element is added to
/// `InspectorTabPresentation.elementsByTab` without also adding it to
/// `InspectorElement`, or vice versa, these tests fail.
final class InspectorTabsPresentationTests: XCTestCase {
    func testEveryInspectorElementAppearsInExactlyOneTab() {
        for element in InspectorElement.allCases {
            let owningTabs = InspectorTab.allCases.filter { tab in
                InspectorTabPresentation.elementsByTab[tab]?.contains(element) == true
            }
            XCTAssertEqual(
                owningTabs.count,
                1,
                "\(element) should appear in exactly one tab, found in \(owningTabs)"
            )
        }
    }

    func testNoTabListsAnElementTwice() {
        for tab in InspectorTab.allCases {
            let elements = InspectorTabPresentation.elementsByTab[tab] ?? []
            XCTAssertEqual(Set(elements).count, elements.count, "\(tab) lists a duplicate element")
        }
    }

    func testInfoTabOwnsDisplayOnlyElements() {
        let info = InspectorTabPresentation.elementsByTab[.info] ?? []
        XCTAssertTrue(info.contains(.preview))
        XCTAssertTrue(info.contains(.identityHeader))
        XCTAssertTrue(info.contains(.ratingDisplay))
        XCTAssertTrue(info.contains(.flagDisplay))
        XCTAssertTrue(info.contains(.labelDisplay))
        XCTAssertTrue(info.contains(.exifRows))
        XCTAssertTrue(info.contains(.syncStatus))
        XCTAssertTrue(info.contains(.conflictResolver))
        XCTAssertTrue(info.contains(.previewRetry))
    }

    func testDescribeTabOwnsAuthoringElements() {
        let describe = InspectorTabPresentation.elementsByTab[.describe] ?? []
        XCTAssertTrue(describe.contains(.keywordChips))
        XCTAssertTrue(describe.contains(.keywordField))
        XCTAssertTrue(describe.contains(.suggestedKeywords))
        XCTAssertTrue(describe.contains(.captionField))
        XCTAssertTrue(describe.contains(.ocrCaptionSuggestions))
        XCTAssertTrue(describe.contains(.creatorField))
        XCTAssertTrue(describe.contains(.copyrightField))
        XCTAssertTrue(describe.contains(.multiSelectNote))
        XCTAssertTrue(describe.contains(.ratingEditButtons))
        XCTAssertTrue(describe.contains(.flagEditButtons))
        XCTAssertTrue(describe.contains(.labelEditButtons))
    }

    func testAITabOwnsVerdictAndProviderElements() {
        let ai = InspectorTabPresentation.elementsByTab[.ai] ?? []
        XCTAssertTrue(ai.contains(.verdictGroups))
        XCTAssertTrue(ai.contains(.technicalDetailsDisclosure))
        XCTAssertTrue(ai.contains(.providerFailureRetry))
    }

    // MARK: - ⌘I model behavior

    func testToggleInspectorTogglesInLibrary() {
        let model = AppModel.demo()
        model.selectWorkspace(.library)
        XCTAssertFalse(model.isInspectorVisible)

        model.toggleInspector()
        XCTAssertTrue(model.isInspectorVisible)
        XCTAssertEqual(model.selectedWorkspace, .library)

        model.toggleInspector()
        XCTAssertFalse(model.isInspectorVisible)
    }

    func testToggleInspectorTogglesInPeople() {
        let model = AppModel.demo()
        model.selectedView = .people
        XCTAssertFalse(model.isInspectorVisible)

        model.toggleInspector()
        XCTAssertTrue(model.isInspectorVisible)
        // People is a Library view now, so it stays in the Library workspace.
        XCTAssertEqual(model.selectedWorkspace, .library)
        XCTAssertEqual(model.selectedView, .people)
    }

    // Task 5: the single-image inspector is reachable from the Cull loupe,
    // so ⌘I toggles it in place instead of redirecting to Library.
    func testToggleInspectorTogglesInCull() {
        let model = AppModel.demo()
        model.selectWorkspace(.cull)
        XCTAssertFalse(model.isInspectorVisible)

        model.toggleInspector()
        XCTAssertTrue(model.isInspectorVisible)
        XCTAssertEqual(model.selectedWorkspace, .cull)

        model.toggleInspector()
        XCTAssertFalse(model.isInspectorVisible)
    }

    // File ▸ Export…'s sheet is a popover hosted on the Library toolbar's
    // Export button, so bumping the token alone is a silent no-op while Cull
    // is frontmost (persona-1 Maya: "File > Export does nothing in the Cull
    // workspace"). requestExport mirrors ⌘I's switch-to-Library pattern.
    func testRequestExportInCullSwitchesToLibrary() {
        let model = AppModel.demo()
        model.selectWorkspace(.cull)
        let originalToken = model.exportRequestToken

        model.requestExport()

        XCTAssertEqual(model.selectedWorkspace, .library)
        XCTAssertEqual(model.exportRequestToken, originalToken + 1)
    }

    func testRequestExportInLibraryStaysInLibrary() {
        let model = AppModel.demo()
        model.selectWorkspace(.library)
        let originalToken = model.exportRequestToken

        model.requestExport()

        XCTAssertEqual(model.selectedWorkspace, .library)
        XCTAssertEqual(model.exportRequestToken, originalToken + 1)
    }

    // People is a Library view but suppresses the browse chrome, so the Export
    // button isn't there to host the sheet — Export must land on the grid, not
    // just "the Library workspace" (which People already is).
    func testRequestExportInPeopleSwitchesToGrid() {
        let model = AppModel.demo()
        model.selectedView = .people
        let originalToken = model.exportRequestToken

        model.requestExport()

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.exportRequestToken, originalToken + 1)
    }

    func testRequestFocusSearchInPeopleSwitchesToGrid() {
        let model = AppModel.demo()
        model.selectedView = .people
        let originalToken = model.focusSearchRequestToken

        model.requestFocusSearch()

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.focusSearchRequestToken, originalToken + 1)
    }

    func testRequestFocusSearchInCullSwitchesToGrid() {
        let model = AppModel.demo()
        model.selectWorkspace(.cull)
        let originalToken = model.focusSearchRequestToken

        model.requestFocusSearch()

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.focusSearchRequestToken, originalToken + 1)
    }

    func testScrollInspectorSetsTargetAndPresentsWhenEligible() {
        let model = AppModel.demo()
        model.selectWorkspace(.library)
        let originalToken = model.inspectorScrollRequestToken

        model.scrollInspector(to: .describe)

        XCTAssertEqual(model.inspectorScrollTarget, .describe)
        XCTAssertEqual(model.inspectorScrollRequestToken, originalToken + 1)
        XCTAssertTrue(model.isInspectorVisible)
    }

    // Task 5: Cull can show the inspector now, so scrolling to a section
    // there presents it, same as Library/People.
    func testScrollInspectorInCullSetsTargetAndPresentsInspector() {
        let model = AppModel.demo()
        model.selectWorkspace(.cull)

        model.scrollInspector(to: .ai)

        XCTAssertEqual(model.inspectorScrollTarget, .ai)
        XCTAssertTrue(model.isInspectorVisible)
    }

    // The stacked inspector has no notion of a "current" section, so
    // scrolling to the same section twice must still bump the request
    // token — otherwise InspectorView's onChange wouldn't fire the second
    // time if the user had since scrolled away manually.
    func testScrollInspectorToSameSectionStillBumpsRequestToken() {
        let model = AppModel.demo()
        model.selectWorkspace(.library)
        model.scrollInspector(to: .info)
        let tokenAfterFirstRequest = model.inspectorScrollRequestToken

        model.scrollInspector(to: .info)

        XCTAssertEqual(model.inspectorScrollRequestToken, tokenAfterFirstRequest + 1)
    }
}
