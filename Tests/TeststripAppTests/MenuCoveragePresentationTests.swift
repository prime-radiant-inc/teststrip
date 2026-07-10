import XCTest
@testable import TeststripApp

/// Task 22: every action id in `CullingCommandMenuPresentation` plus the
/// workspace/sub-view/inspector-tab/zoom action sets must have a menu item.
/// Menus are built ad hoc in main.swift, so `AppMenuCoveragePresentation`
/// (also in main.swift) is the small presentation layer this test enumerates
/// against the underlying action-producing enums.
final class MenuCoveragePresentationTests: XCTestCase {
    func testCullingMenuCoversEveryNonMonitorOnlyShortcutItem() {
        let expected = CullingCommandMenuPresentation.sections
            .flatMap(\.items)
            .filter { !$0.isMonitorOnly }
            .map(\.title)

        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(AppMenuCoveragePresentation.cullingShortcutActionIDs, expected)
    }

    func testViewMenuCoversEveryWorkspace() {
        XCTAssertEqual(AppMenuCoveragePresentation.workspaceActionIDs, Workspace.allCases.map(\.title))
    }

    func testViewMenuCoversEverySubViewExceptPeople() {
        // People has no sub-view switcher: it's a single view, not a
        // workspace with alternate routes.
        let expectedRawValues = Set(LibraryViewMode.allCases.filter { $0 != .people }.map(\.rawValue))
        let coveredRawValues = Set(AppMenuCoveragePresentation.subViewMenuModes.map(\.rawValue))

        XCTAssertEqual(coveredRawValues, expectedRawValues)
        for mode in AppMenuCoveragePresentation.subViewMenuModes {
            XCTAssertNotNil(mode.subViewMenuTitle, "\(mode) has no sub-view menu title")
        }
    }

    func testViewMenuCoversEveryInspectorTabAndTheInspectorToggle() {
        XCTAssertEqual(
            AppMenuCoveragePresentation.inspectorTabActionIDs,
            InspectorTab.allCases.map { "\($0.title) Tab" }
        )
        XCTAssertEqual(AppMenuCoveragePresentation.showInspectorActionID, "Show Inspector")
    }

    func testViewMenuCoversZoomInAndOut() {
        XCTAssertEqual(AppMenuCoveragePresentation.zoomActionIDs, ["Zoom In", "Zoom Out"])
    }
}
