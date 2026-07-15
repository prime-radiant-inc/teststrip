import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// The pure projection behind the face-group review surface: title, tiles,
/// counts, and confirm semantics for a matched-person group vs a new cluster.
final class FaceGroupReviewPresentationTests: XCTestCase {
    private func tile(_ assetID: String, _ faceIndex: Int) -> FaceReviewTile {
        FaceReviewTile(
            faceID: FaceID(assetID: AssetID(rawValue: assetID), faceIndex: faceIndex),
            boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
    }

    func testMatchExistingGroupIsAskingToConfirmAName() {
        let review = FaceGroupReviewPresentation(
            suggestionID: "face-match-person-maya",
            kind: .matchExisting(personID: "person-maya", personName: "Maya"),
            tiles: [tile("a", 0), tile("a", 1), tile("b", 0)]
        )

        XCTAssertEqual(review.title, "Is this Maya?")
        XCTAssertEqual(review.confirmActionTitle, "Maya")
        XCTAssertTrue(review.isOneTapConfirm)
        XCTAssertEqual(review.personName, "Maya")
        XCTAssertEqual(review.remainingFaceCount, 3)
        XCTAssertEqual(review.remainingPhotoCount, 2) // asset a and b
        XCTAssertEqual(review.summary, "3 faces \u{00B7} 2 photos")
        XCTAssertTrue(review.isConfirmEnabled)
    }

    func testNewClusterGroupIsAskingWhoTheFaceIs() {
        let review = FaceGroupReviewPresentation(
            suggestionID: "face-cluster-a-0",
            kind: .newPerson,
            tiles: [tile("a", 0)]
        )

        XCTAssertEqual(review.title, "Who is this?")
        XCTAssertEqual(review.confirmActionTitle, "Name\u{2026}")
        XCTAssertFalse(review.isOneTapConfirm)
        XCTAssertNil(review.personName)
        XCTAssertEqual(review.remainingFaceCount, 1)
        XCTAssertEqual(review.remainingPhotoCount, 1)
        XCTAssertEqual(review.summary, "1 face \u{00B7} 1 photo")
    }

    func testEmptyGroupDisablesConfirm() {
        let review = FaceGroupReviewPresentation(
            suggestionID: "face-match-person-maya",
            kind: .matchExisting(personID: "person-maya", personName: "Maya"),
            tiles: []
        )

        XCTAssertFalse(review.isConfirmEnabled)
        XCTAssertEqual(review.remainingFaceCount, 0)
        XCTAssertEqual(review.summary, "0 faces \u{00B7} 0 photos")
    }
}
