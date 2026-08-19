import XCTest
import CoreImage
@testable import TeststripCore

final class RotationImageLoadingTests: XCTestCase {
    func testExifOrientationForRotation() {
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 0), .up)
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 90), .right)
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 180), .down)
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 270), .left)
    }

    func testRotatedDimensionsSwapFor90And270() {
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 0).0, 4000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 0).1, 3000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 90).0, 3000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 90).1, 4000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 180).0, 4000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 180).1, 3000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 270).0, 3000)
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 270).1, 4000)
    }
}
