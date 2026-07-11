import XCTest
@testable import TeststripApp
@testable import TeststripCore

/// persona-2 item 5: the grid cell's right-click context menu (Rate/Flag/
/// Label) must apply to the whole batch selection when the right-clicked
/// cell is part of it, and to just the clicked cell otherwise — matching the
/// existing "Cull These" context-menu item's anchor behavior.
final class AssetGridCellContextMenuPresentationTests: XCTestCase {
    func testTargetsWholeBatchWhenRightClickedCellIsSelected() {
        let clicked = AssetID(rawValue: "clicked")
        let other = AssetID(rawValue: "other")
        let batch: Set<AssetID> = [clicked, other]

        let targets = AssetGridCellContextMenuPresentation.targetAssetIDs(
            rightClicked: clicked,
            batchSelectedAssetIDs: batch
        )

        XCTAssertEqual(targets, batch)
    }

    func testTargetsOnlyClickedCellWhenNotInBatchSelection() {
        let clicked = AssetID(rawValue: "clicked")
        let other = AssetID(rawValue: "other")
        let batch: Set<AssetID> = [other]

        let targets = AssetGridCellContextMenuPresentation.targetAssetIDs(
            rightClicked: clicked,
            batchSelectedAssetIDs: batch
        )

        XCTAssertEqual(targets, [clicked])
    }

    func testTargetsOnlyClickedCellWhenNoBatchSelectionActive() {
        let clicked = AssetID(rawValue: "clicked")

        let targets = AssetGridCellContextMenuPresentation.targetAssetIDs(
            rightClicked: clicked,
            batchSelectedAssetIDs: []
        )

        XCTAssertEqual(targets, [clicked])
    }

    func testRatingMenuCoversOneThroughFivePlusClear() {
        XCTAssertEqual(
            AssetGridCellContextMenuPresentation.ratingMenuTitles,
            ["Rate 1", "Rate 2", "Rate 3", "Rate 4", "Rate 5", "Clear Rating"]
        )
    }

    func testFlagMenuCoversPickRejectUnflag() {
        XCTAssertEqual(
            AssetGridCellContextMenuPresentation.flagMenuTitles,
            ["Pick", "Reject", "Unflag"]
        )
    }

    func testLabelMenuCoversEveryColorLabelPlusClear() {
        XCTAssertEqual(
            AssetGridCellContextMenuPresentation.labelMenuTitles,
            ["Red", "Yellow", "Green", "Blue", "Purple", "Clear Label"]
        )
    }
}
