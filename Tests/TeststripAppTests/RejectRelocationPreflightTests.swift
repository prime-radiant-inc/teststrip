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

    // The armed-looking dead confirm button (persona-7 Marcus, "the ghost"):
    // an enabled-looking primary that silently swallows presses until a
    // checkbox is ticked reads as broken — AXPress reports success and
    // nothing happens. The gate is the sheet template's standard one
    // instead: the primary is genuinely disabled (AX reports it) until the
    // confirm toggle is checked, and a standing hint says exactly what
    // arms it, so the disabled state is never mystery furniture
    // (persona-1 Maya's "THE WALL").
    func testSheetPresentationGatesMoveOnConfirmationToggle() {
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
        let unconfirmed = RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: false)
        XCTAssertFalse(unconfirmed.isMoveEnabled)
        XCTAssertEqual(unconfirmed.confirmationHintText, "Check the box above to enable “Move 1 reject photo to Rejects”.")
        let confirmed = RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: true)
        XCTAssertTrue(confirmed.isMoveEnabled)
        XCTAssertNil(confirmed.confirmationHintText)
    }

    // Trash and folder sheets share one gate: unconfirmed disables the
    // primary with the same standing hint in both modes.
    func testTrashSheetPresentationGatesMoveIdentically() {
        let unconfirmed = RejectRelocationSheetPresentation(preflight: makeTrashPreflight(), isConfirmed: false)
        XCTAssertFalse(unconfirmed.isMoveEnabled)
        XCTAssertEqual(unconfirmed.confirmationHintText, "Check the box above to enable “Move 2 to Trash”.")
        let confirmed = RejectRelocationSheetPresentation(preflight: makeTrashPreflight(), isConfirmed: true)
        XCTAssertTrue(confirmed.isMoveEnabled)
        XCTAssertNil(confirmed.confirmationHintText)
    }

    func testSheetPresentationEnablesMoveWhenConfirmed() {
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
        let presentation = RejectRelocationSheetPresentation(preflight: empty, isConfirmed: true)
        XCTAssertFalse(presentation.isMoveEnabled)
        // No confirm toggle renders without movable files, so no hint about it.
        XCTAssertNil(presentation.confirmationHintText)
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

    // MARK: - Scope disclosure (spec's honesty principle): a filtered view
    // that hides all rejects must say so, not silently report "0 files".

    func testSummaryDisclosesFilesOutsideCurrentFilterWhenNothingInScope() {
        let empty = RejectRelocationPreflight(
            assetIDs: [],
            originalURLs: [],
            plans: [],
            sidecarCount: 0,
            totalByteCount: 0,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder,
            mode: .trash,
            outsideScopeCount: 6
        )
        let presentation = RejectRelocationSheetPresentation(preflight: empty, isConfirmed: true)
        XCTAssertEqual(
            presentation.summaryText,
            "0 in current view — 6 more outside filters"
        )
        XCTAssertTrue(presentation.showsClearFiltersAffordance)
    }

    func testSummaryStaysPlainWhenScopeMatchesWholeCatalog() {
        let presentation = RejectRelocationSheetPresentation(preflight: makeTrashPreflight(), isConfirmed: true)
        XCTAssertEqual(presentation.summaryText, "2 files · 0 sidecars · 200 bytes")
        XCTAssertFalse(presentation.showsClearFiltersAffordance)
    }

    func testSummaryStaysPlainWhenNothingMovableAndNothingOutsideScopeEither() {
        let empty = RejectRelocationPreflight(
            assetIDs: [],
            originalURLs: [],
            plans: [],
            sidecarCount: 0,
            totalByteCount: 0,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: RejectRelocationPreflight.trashDisplayFolder,
            mode: .trash,
            outsideScopeCount: 0
        )
        let presentation = RejectRelocationSheetPresentation(preflight: empty, isConfirmed: true)
        XCTAssertEqual(presentation.summaryText, "0 files · 0 sidecars · Zero KB")
        XCTAssertFalse(presentation.showsClearFiltersAffordance)
    }
}
