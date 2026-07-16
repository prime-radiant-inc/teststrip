import XCTest
import TeststripCore
@testable import TeststripApp

final class FaceNamingPopoverTests: XCTestCase {
    private let faceA = FaceID(assetID: AssetID(rawValue: "asset-a"), faceIndex: 0)
    private let faceB = FaceID(assetID: AssetID(rawValue: "asset-b"), faceIndex: 1)

    func testPresentsOnlyForTheInitiatingSurface() {
        // Editing face A from the inspector: the inspector presents, the loupe does not —
        // this is the regression: two surfaces no longer present the same popover at once.
        XCTAssertTrue(FaceNamingPopover.isPresented(
            editingFaceID: faceA, editingSource: .inspector, rowFaceID: faceA, surface: .inspector))
        XCTAssertFalse(FaceNamingPopover.isPresented(
            editingFaceID: faceA, editingSource: .inspector, rowFaceID: faceA, surface: .loupe))
    }

    func testDoesNotPresentForADifferentFace() {
        XCTAssertFalse(FaceNamingPopover.isPresented(
            editingFaceID: faceA, editingSource: .loupe, rowFaceID: faceB, surface: .loupe))
    }

    func testDoesNotPresentWhenNothingIsBeingEdited() {
        XCTAssertFalse(FaceNamingPopover.isPresented(
            editingFaceID: nil, editingSource: nil, rowFaceID: faceA, surface: .inspector))
    }
}
