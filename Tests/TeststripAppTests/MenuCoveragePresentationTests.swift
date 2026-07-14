import XCTest
@testable import TeststripApp

/// Task 22: every action id in `CullingCommandMenuPresentation` plus the
/// workspace/sub-view/inspector-tab/zoom action sets must have a menu item.
/// Menus are built ad hoc in main.swift, so `AppMenuCoveragePresentation`
/// (also in main.swift) is the small presentation layer this test enumerates
/// against the underlying action-producing enums.
final class MenuCoveragePresentationTests: XCTestCase {
    func testCullingMenuCoversEveryShortcutItem() {
        let expected = CullingCommandMenuPresentation.sections
            .flatMap(\.items)
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

    // Trash Part 1: Culling ▸ Move Rejects to Trash… sits beside Move
    // Rejects…, reusing the same request-token pattern.
    func testCullingMenuCoversMoveRejectsToTrashAction() {
        XCTAssertEqual(AppMenuCoveragePresentation.moveRejectsToTrashActionID, "Move Rejects to Trash…")
    }

    // persona-2 item 2: File ▸ New Set from Selection… is the only File/
    // sidebar-menu path to discover set creation; it reuses the manual-set
    // save flow behind the same request-token pattern as Move Rejects….
    func testFileMenuCoversNewSetFromSelectionAction() {
        XCTAssertEqual(AppMenuCoveragePresentation.newSetFromSelectionActionID, "New Set from Selection…")
    }

    // Support ▸ Check for Updates… drives the Sparkle updater.
    func testSupportMenuCoversCheckForUpdatesAction() {
        XCTAssertEqual(AppMenuCoveragePresentation.checkForUpdatesActionID, "Check for Updates…")
    }

    // persona-3 item 1: bare culling keys can't carry a real menu
    // .keyboardShortcut (double-fires against the in-view key monitors — see
    // menuKeyboardShortcut in main.swift), so the menu advertises the key as
    // a title suffix instead, e.g. "Pick (P)". Every item must carry its key
    // glyph, sourced from the same CullingShortcutKey .displayText the ?
    // key-map overlay uses.
    func testCullingMenuItemsAdvertiseTheirKeyInTheTitle() {
        let items = CullingCommandMenuPresentation.sections.flatMap(\.items)

        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertEqual(item.menuDisplayTitle, "\(item.title) (\(item.key.displayText))")
            XCTAssertTrue(item.menuDisplayTitle.hasSuffix(")"), "\(item.title) menu title missing key suffix")
        }
    }
}
