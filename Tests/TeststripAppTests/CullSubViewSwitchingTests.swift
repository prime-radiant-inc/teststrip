import XCTest
@testable import TeststripApp

// Task 18: g/c/b switch Cull's sub-views (grid/compare/A-B) without leaving
// the Cull workspace. CullingKeyCaptureView carries g/c/b while in
// loupe/compare/A-B; GridKeyCaptureView carries the same letters (plus
// Escape) to get back out of the cull grid, since that view's key capture
// belongs to GridKeyCaptureView, not CullingKeyCaptureView (matching the
// existing `.grid`/`.libraryLoupe` split).
final class CullSubViewSwitchingTests: XCTestCase {
    func testCharacterShortcutsMapToCullSubViewSwitches() {
        XCTAssertEqual(CullingShortcut(key: .character("g")), .showCullGrid)
        XCTAssertEqual(CullingShortcut(key: .character("c")), .showCompare)
        XCTAssertEqual(CullingShortcut(key: .character("b")), .showABCompare)
    }

    func testApplyingCullingShortcutSwitchesSubViewWithoutLeavingCullWorkspace() throws {
        let model = AppModel.demo()
        model.selectedView = .loupe

        try model.applyCullingShortcut(.showCullGrid)
        XCTAssertEqual(model.selectedView, .cullGrid)
        XCTAssertEqual(model.selectedWorkspace, .cull)

        try model.applyCullingShortcut(.showCompare)
        XCTAssertEqual(model.selectedView, .compare)

        try model.applyCullingShortcut(.showABCompare)
        XCTAssertEqual(model.selectedView, .abCompare)
    }

    func testGridKeyCaptureTranslatesGCBAndEscapeOnlyInCullGrid() {
        XCTAssertEqual(GridKeyCommand.cullSubViewSwitch(for: .character("g")), .switchCullSubView(.loupe))
        XCTAssertEqual(GridKeyCommand.cullSubViewSwitch(for: .character("c")), .switchCullSubView(.compare))
        XCTAssertEqual(GridKeyCommand.cullSubViewSwitch(for: .character("b")), .switchCullSubView(.abCompare))
        XCTAssertEqual(GridKeyCommand.cullSubViewSwitch(for: .escape), .switchCullSubView(.loupe))
        XCTAssertNil(GridKeyCommand.cullSubViewSwitch(for: .character("p")))
    }

    func testSwitchCullSubViewCommandSetsSelectedView() {
        let model = AppModel.demo()
        model.selectedView = .cullGrid

        try? model.applyGridKeyCommand(.switchCullSubView(.loupe), columns: 4)
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testOpeningLoupeFromCullGridStaysInCullLoupeNotLibraryLoupe() throws {
        let model = AppModel.demo()
        model.selectedView = .cullGrid
        guard let firstAssetID = model.assets.first?.id else {
            XCTFail("demo model has no assets to select")
            return
        }
        model.select(firstAssetID)

        try model.applyGridKeyCommand(.openLoupe, columns: 4)

        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testCullGridBelongsToCullWorkspace() {
        XCTAssertEqual(LibraryViewMode.cullGrid.workspace, .cull)
    }

    // Persona-3 item 3: pure index arithmetic for scrolling the ? overlay,
    // clamped at both edges.
    func testKeyMapOverlayScrollingClampsAtEdges() {
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 0, direction: .up, sectionCount: 6), 0)
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 5, direction: .down, sectionCount: 6), 5)
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 2, direction: .down, sectionCount: 6), 3)
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 2, direction: .up, sectionCount: 6), 1)
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 1, direction: .pageDown, sectionCount: 6), 4)
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 4, direction: .pageUp, sectionCount: 6), 1)
        XCTAssertEqual(KeyMapOverlayScrolling.nextIndex(current: 0, direction: .up, sectionCount: 0), 0)
    }
}
