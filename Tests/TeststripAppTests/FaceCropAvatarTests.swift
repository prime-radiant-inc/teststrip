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
