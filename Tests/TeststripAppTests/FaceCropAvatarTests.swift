import CoreGraphics
import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class FaceCropAvatarTests: XCTestCase {
    func testPixelCropRectFlipsPadsAndClamps() {
        let rect = FaceCropGeometry.pixelCropRect(
            boundingBox: FaceBoundingBox(x: 0.4, y: 0.2, width: 0.2, height: 0.2),
            imagePixelWidth: 1000,
            imagePixelHeight: 500,
            padding: 0.25
        )
        // Padded unit box: x 0.35...0.65; Vision y 0.15...0.45 flips to top-left y 0.55...0.85.
        XCTAssertEqual(rect.minX, 350, accuracy: 1)
        XCTAssertEqual(rect.minY, 275, accuracy: 1)
        XCTAssertEqual(rect.width, 300, accuracy: 1)
        XCTAssertEqual(rect.height, 150, accuracy: 1)

        let clamped = FaceCropGeometry.pixelCropRect(
            boundingBox: FaceBoundingBox(x: 0.9, y: 0.0, width: 0.2, height: 0.2),
            imagePixelWidth: 100,
            imagePixelHeight: 100,
            padding: 0.25
        )
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 100, height: 100).contains(clamped))
    }

    func testCropReloadKeyChangesWhenBoundingBoxChangesUnderSameURL() {
        // Suggestion refreshes can promote a different face within the same
        // representative asset: the preview URL stays identical while the
        // bounding box moves, and the avatar must re-crop.
        let url = URL(fileURLWithPath: "/tmp/preview.jpg")
        let first = FaceCropAvatar.CropKey(url: url, box: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let sameFace = FaceCropAvatar.CropKey(url: url, box: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let movedFace = FaceCropAvatar.CropKey(url: url, box: FaceBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.2))

        XCTAssertEqual(first, sameFace)
        XCTAssertNotEqual(first, movedFace)
    }

    func testDegenerateBoxFallsBackToFullImage() {
        XCTAssertEqual(
            FaceCropGeometry.pixelCropRect(
                boundingBox: FaceBoundingBox(x: 0.5, y: 0.5, width: 0, height: 0),
                imagePixelWidth: 640,
                imagePixelHeight: 480
            ),
            CGRect(x: 0, y: 0, width: 640, height: 480)
        )
    }
}
