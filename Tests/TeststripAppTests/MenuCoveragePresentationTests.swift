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

    // I1: File ▸ Import Folder…/Import From Card…/Export… (spec §6) — the
    // dev-only Import Path… item is gated by environment, not enumerated
    // in fileMenuActionIDs, so it's checked as a standalone constant.
    func testFileMenuCoversImportAndExportActions() {
        XCTAssertEqual(
            AppMenuCoveragePresentation.fileMenuActionIDs,
            ["Import Folder…", "Import From Card…", "Export…"]
        )
        XCTAssertEqual(AppMenuCoveragePresentation.importPathActionID, "Import Path…")
    }

    // I1: Culling ▸ Move Rejects… reuses AppModel.beginRejectRelocation's
    // path via the lifted request-token (Task 20's end-of-set state already
    // called this; the menu item now reaches the same place).
    func testCullingMenuCoversMoveRejectsAction() {
        XCTAssertEqual(AppMenuCoveragePresentation.moveRejectsActionID, "Move Rejects…")
    }

    // Support ▸ Check for Updates… drives the Sparkle updater.
    func testSupportMenuCoversCheckForUpdatesAction() {
        XCTAssertEqual(AppMenuCoveragePresentation.checkForUpdatesActionID, "Check for Updates…")
    }
}
