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
        model.selectWorkspace(.people)
        XCTAssertFalse(model.isInspectorVisible)

        model.toggleInspector()
        XCTAssertTrue(model.isInspectorVisible)
        XCTAssertEqual(model.selectedWorkspace, .people)
    }

    func testToggleInspectorInCullSwitchesToLibraryAndShowsInspector() {
        let model = AppModel.demo()
        model.selectWorkspace(.cull)
        XCTAssertFalse(model.isInspectorVisible)

        model.toggleInspector()

        XCTAssertEqual(model.selectedWorkspace, .library)
        XCTAssertTrue(model.isInspectorVisible)
    }

    func testSelectInspectorTabSetsTabAndPresentsWhenEligible() {
        let model = AppModel.demo()
        model.selectWorkspace(.library)
        XCTAssertEqual(model.inspectorTab, .info)

        model.selectInspectorTab(.describe)

        XCTAssertEqual(model.inspectorTab, .describe)
        XCTAssertTrue(model.isInspectorVisible)
    }

    func testSelectInspectorTabInCullSetsTabWithoutForcingVisibility() {
        let model = AppModel.demo()
        model.selectWorkspace(.cull)

        model.selectInspectorTab(.ai)

        XCTAssertEqual(model.inspectorTab, .ai)
        XCTAssertFalse(model.isInspectorVisible)
    }
}
