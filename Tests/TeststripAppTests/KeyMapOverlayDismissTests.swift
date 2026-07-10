import XCTest
@testable import TeststripApp

// While the ? key-map overlay is up it owns Esc: the grid key monitor's
// Esc-derived commands (returnToGrid from the cull loupe, the cullGrid
// return-to-loupe switch) must dismiss the overlay instead of navigating.
// Without this, Esc in the cull loupe silently switched to the Library grid
// underneath the still-visible overlay, and the culling monitor's ? toggle
// was then gated off — the overlay could never be dismissed
// (run-cull-iter2 cull-009).
final class KeyMapOverlayDismissTests: XCTestCase {
    func testEscapeDismissesKeyMapOverlayInsteadOfReturningToGrid() throws {
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [])
        model.isKeyMapOverlayVisible = true

        try model.applyGridKeyCommand(.returnToGrid, columns: 4)

        XCTAssertFalse(model.isKeyMapOverlayVisible)
        XCTAssertEqual(model.selectedView, .loupe, "Esc must only dismiss the overlay, not navigate")
    }

    func testEscapeDismissesKeyMapOverlayInsteadOfSwitchingCullSubView() throws {
        let model = AppModel(sidebarSections: [], selectedView: .cullGrid, assets: [])
        model.isKeyMapOverlayVisible = true

        try model.applyGridKeyCommand(.switchCullSubView(.loupe), columns: 4)

        XCTAssertFalse(model.isKeyMapOverlayVisible)
        XCTAssertEqual(model.selectedView, .cullGrid, "Esc must only dismiss the overlay, not navigate")
    }

    func testReturnToGridStillNavigatesWhenOverlayHidden() throws {
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [])

        try model.applyGridKeyCommand(.returnToGrid, columns: 4)

        XCTAssertEqual(model.selectedView, .grid)
    }

    func testShowKeyMapShortcutTogglesOverlay() throws {
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [])

        try model.applyCullingShortcut(.showKeyMap)
        XCTAssertTrue(model.isKeyMapOverlayVisible)
        try model.applyCullingShortcut(.showKeyMap)
        XCTAssertFalse(model.isKeyMapOverlayVisible)
    }
}
