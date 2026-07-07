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

    func testSheetPresentationDisablesMoveUntilConfirmed() {
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
        XCTAssertFalse(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: false).isMoveEnabled)
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
}
