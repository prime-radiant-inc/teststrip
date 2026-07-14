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
}
