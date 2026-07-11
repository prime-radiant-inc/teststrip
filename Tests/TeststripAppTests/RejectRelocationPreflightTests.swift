import XCTest
import TeststripCore
@testable import TeststripApp

final class RejectRelocationPreflightTests: XCTestCase {
    func testConfirmationTextSingularizesOnePhoto() {
        let preflight = RejectRelocationPreflight(
            assetIDs: [AssetID(rawValue: "a")],
            originalURLs: [URL(fileURLWithPath: "/Shoot/a.cr2")],
            plans: [RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/a.cr2")
            )],
            sidecarCount: 0,
            totalByteCount: 100,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        XCTAssertEqual(preflight.confirmationText, "Move 1 reject photo to Rejects")
        XCTAssertEqual(preflight.moveCount, 1)
    }

    // Disabled-furniture trap (persona-1 Maya, "THE WALL"): a primary button
    // that's silently disabled until a checkbox is ticked reads as dead —
    // AXPress and real clicks alike appear to do nothing. The primary stays
    // enabled whenever there are movable files; the confirm toggle gates the
    // *action* (LibraryGridView shows an inline error if pressed unconfirmed),
    // not the button's enabled state.
    func testSheetPresentationEnablesMoveRegardlessOfConfirmationToggle() {
        let preflight = RejectRelocationPreflight(
            assetIDs: [AssetID(rawValue: "a")],
            originalURLs: [URL(fileURLWithPath: "/Shoot/a.cr2")],
            plans: [RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/a.cr2")
            )],
            sidecarCount: 0,
            totalByteCount: 100,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        XCTAssertTrue(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: false).isMoveEnabled)
        XCTAssertTrue(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: true).isMoveEnabled)
        XCTAssertEqual(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: true).destinationPreviewRows, ["a.cr2"])
    }

    func testSheetPresentationDisablesMoveWhenNothingMovable() {
        let empty = RejectRelocationPreflight(
            assetIDs: [],
            originalURLs: [],
            plans: [],
            sidecarCount: 0,
            totalByteCount: 0,
            unavailableCount: 2,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        XCTAssertFalse(RejectRelocationSheetPresentation(preflight: empty, isConfirmed: true).isMoveEnabled)
    }

    // MARK: - Trash-mode preflight sheet copy (spec Part 1)

    private func makeTrashPreflight(unavailableCount: Int = 0) -> RejectRelocationPreflight {
        RejectRelocationPreflight(
            assetIDs: [AssetID(rawValue: "a"), AssetID(rawValue: "b")],
            originalURLs: [URL(fileURLWithPath: "/Shoot/a.cr2"), URL(fileURLWithPath: "/Shoot/b.cr2")],
            plans: [
                RejectRelocationPlan(
                    originalFrom: URL(fileURLWithPath: "/Shoot/a.cr2"),
                    originalTo: URL(fileURLWithPath: "/Shoot/a.cr2")
                ),
                RejectRelocationPlan(
                    originalFrom: URL(fileURLWithPath: "/Shoot/b.cr2"),
                    originalTo: URL(fileURLWithPath: "/Shoot/b.cr2")
                ),
            ],
            sidecarCount: 0,
            totalByteCount: 200,
            unavailableCount: unavailableCount,
            alreadyInDestinationCount: 0,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder,
            mode: .trash
        )
    }

    func testTrashSheetPresentationTitleAndButtonSayTrash() {
        let presentation = RejectRelocationSheetPresentation(preflight: makeTrashPreflight(), isConfirmed: true)
        XCTAssertEqual(presentation.titleText, "Move Rejects to Trash")
        XCTAssertEqual(presentation.moveButtonTitle, "Move 2 to Trash")
    }

    func testTrashSheetPresentationWarnsThatTheCatalogForgetsTheFiles() {
        let presentation = RejectRelocationSheetPresentation(preflight: makeTrashPreflight(), isConfirmed: true)
        XCTAssertEqual(
            presentation.warningText,
            "Files go to the macOS Trash and the catalog forgets them."
        )
    }

    func testTrashSheetPresentationCombinesTrashWarningWithUnavailableWarning() {
        let presentation = RejectRelocationSheetPresentation(
            preflight: makeTrashPreflight(unavailableCount: 1),
            isConfirmed: true
        )
        XCTAssertEqual(
            presentation.warningText,
            "Files go to the macOS Trash and the catalog forgets them. · 1 unavailable original is skipped"
        )
    }

    func testFolderSheetPresentationUnaffectedByTrashCopy() {
        let preflight = RejectRelocationPreflight(
            assetIDs: [AssetID(rawValue: "a")],
            originalURLs: [URL(fileURLWithPath: "/Shoot/a.cr2")],
            plans: [RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/a.cr2")
            )],
            sidecarCount: 0,
            totalByteCount: 100,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        let presentation = RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: true)
        XCTAssertEqual(presentation.titleText, "Move rejects to Rejects")
        XCTAssertEqual(presentation.moveButtonTitle, "Move 1 reject photo to Rejects")
        XCTAssertNil(presentation.warningText)
    }
}
