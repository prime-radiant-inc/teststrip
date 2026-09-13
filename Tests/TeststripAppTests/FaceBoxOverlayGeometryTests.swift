import TeststripCore
import XCTest
@testable import TeststripApp

final class FaceBoxOverlayGeometryTests: XCTestCase {
    private func assertEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        accuracy: CGFloat = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    func testMapsWholeImageBoxToTheFittedRect() {
        // Same 4000x2000-into-1000x800 fit as LoupeZoomGeometryTests: fitted
        // size is 1000x500, centered with a 150pt letterbox band top/bottom.
        let rect = FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
            imagePixelSize: CGSize(width: 4000, height: 2000),
            containerSize: CGSize(width: 1000, height: 800)
        )
        assertEqual(rect!, CGRect(x: 0, y: 150, width: 1000, height: 500))
    }

    func testFlipsVisionBottomOriginBoxToTheBottomOfTheFittedRect() {
        // Vision's y is bottom-left-origin, so a box at y: 0...0.25 sits in
        // the BOTTOM quarter of the original image and must land at the
        // bottom of the fitted rect in SwiftUI's top-left space, not the top.
        let rect = FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0, width: 0.25, height: 0.25),
            imagePixelSize: CGSize(width: 4000, height: 2000),
            containerSize: CGSize(width: 1000, height: 800)
        )
        // Fitted image spans y: 150...650. The box's bottom edge must sit
        // exactly on the fitted image's bottom edge (650).
        assertEqual(rect!, CGRect(x: 0, y: 525, width: 250, height: 125))
        XCTAssertEqual(rect!.maxY, 650, accuracy: 0.0001)
    }

    func testFlipsVisionTopOriginBoxToTheTopOfTheFittedRect() {
        // A box near Vision's y = 0.75 (near the TOP of the image, since
        // Vision measures up from the bottom) must land near the top of the
        // fitted rect in SwiftUI's coordinate space.
        let rect = FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0.4, y: 0.75, width: 0.2, height: 0.2),
            imagePixelSize: CGSize(width: 1000, height: 1000),
            containerSize: CGSize(width: 500, height: 500)
        )
        // Square image fits exactly (no letterbox); topLeftY = 1 - 0.75 - 0.2 = 0.05.
        assertEqual(rect!, CGRect(x: 200, y: 25, width: 100, height: 100))
    }

    func testCentersLetterboxedImageWithinAWiderContainer() {
        // Square image in a wider container: fit is height-limited, so the
        // fitted image is letterboxed left/right, not top/bottom.
        let rect = FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
            imagePixelSize: CGSize(width: 500, height: 500),
            containerSize: CGSize(width: 1000, height: 800)
        )
        assertEqual(rect!, CGRect(x: 100, y: 0, width: 800, height: 800))
    }

    func testReturnsNilForDegenerateImageOrContainerSize() {
        XCTAssertNil(FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
            imagePixelSize: .zero,
            containerSize: CGSize(width: 1000, height: 800)
        ))
        XCTAssertNil(FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
            imagePixelSize: CGSize(width: 4000, height: 2000),
            containerSize: .zero
        ))
    }

    // MARK: - Rotation-aware mapping

    /// The same top-left face on a square image, mapped through each display
    /// rotation: a clockwise quarter turn carries the top-left quarter of the
    /// image to the top-right, half a turn to the bottom-right, three quarters
    /// to the bottom-left. Square image → square fitted rect, so the corners
    /// are easy to assert exactly.
    private func topLeftFaceRect(rotation: Int) -> CGRect {
        // Vision bottom-left origin: y 0.75...1.0 is the TOP quarter, x
        // 0...0.25 the LEFT quarter. 1000x1000 image into a 500x500 container
        // fits exactly (no letterbox); each quarter is 125pt.
        FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0.75, width: 0.25, height: 0.25),
            imagePixelSize: CGSize(width: 1000, height: 1000),
            containerSize: CGSize(width: 500, height: 500),
            rotation: rotation
        )!
    }

    func testTopLeftFaceStaysTopLeftWithNoRotation() {
        assertEqual(topLeftFaceRect(rotation: 0), CGRect(x: 0, y: 0, width: 125, height: 125))
    }

    func testTopLeftFaceMovesToTopRightWith90DegreeRotation() {
        assertEqual(topLeftFaceRect(rotation: 90), CGRect(x: 375, y: 0, width: 125, height: 125))
    }

    func testTopLeftFaceMovesToBottomRightWith180DegreeRotation() {
        assertEqual(topLeftFaceRect(rotation: 180), CGRect(x: 375, y: 375, width: 125, height: 125))
    }

    func testTopLeftFaceMovesToBottomLeftWith270DegreeRotation() {
        assertEqual(topLeftFaceRect(rotation: 270), CGRect(x: 0, y: 375, width: 125, height: 125))
    }

    func testQuarterTurnSwapsTheFittedFrameAndTheBox() {
        // 1000x500 image (2:1) into a 400x400 container: unrotated it fits
        // 400x200 with a 100pt top/bottom band; rotated 90° it becomes 500x1000,
        // fitting 200x400 with a 100pt left/right band.
        let unrotated = FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0.75, width: 0.25, height: 0.25),
            imagePixelSize: CGSize(width: 1000, height: 500),
            containerSize: CGSize(width: 400, height: 400)
        )!
        assertEqual(unrotated, CGRect(x: 0, y: 100, width: 100, height: 50))

        let rotated = FaceBoxOverlayGeometry.displayRect(
            boundingBox: FaceBoundingBox(x: 0, y: 0.75, width: 0.25, height: 0.25),
            imagePixelSize: CGSize(width: 1000, height: 500),
            containerSize: CGSize(width: 400, height: 400),
            rotation: 90
        )!
        assertEqual(rotated, CGRect(x: 250, y: 0, width: 50, height: 100))
    }

    func testNormalizesRotationDegreesToQuarterTurns() {
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(0), 0)
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(90), 90)
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(180), 180)
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(270), 270)
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(360), 0)
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(450), 90)
        XCTAssertEqual(FaceBoxOverlayGeometry.normalizedRotation(-90), 270)
    }
}
