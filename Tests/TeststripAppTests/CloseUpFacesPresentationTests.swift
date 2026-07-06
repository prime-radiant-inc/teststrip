import CoreGraphics
import Foundation
import TeststripCore
import XCTest
@testable import TeststripApp

final class CloseUpFacesPresentationTests: XCTestCase {
    func testCropsPadAndCenterOnTheFace() {
        let face = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )

        let presentation = CloseUpFacesPresentation(faces: [face], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 1)
        // Face is 200x200 px centered at (500, 500); padded side = 200 * 1.6 = 320.
        XCTAssertEqual(presentation.crops[0].pixelRect, CGRect(x: 340, y: 340, width: 320, height: 320))
    }

    func testCropsClampToImageBounds() {
        let cornerFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )

        let presentation = CloseUpFacesPresentation(faces: [cornerFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        let rect = presentation.crops[0].pixelRect
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1000)
        XCTAssertLessThanOrEqual(rect.maxY, 1000)
    }

    func testCropsOrderLargestFaceFirstAndCapAtFour() {
        func face(x: Double, size: Double) -> DetectedFaceExpression {
            DetectedFaceExpression(
                normalizedBounds: CGRect(x: x, y: 0.1, width: size, height: size),
                hasSmile: false,
                leftEyeClosed: false,
                rightEyeClosed: false,
                leftEyeCenter: nil,
                rightEyeCenter: nil
            )
        }
        let faces = [
            face(x: 0.05, size: 0.10),
            face(x: 0.25, size: 0.30),
            face(x: 0.60, size: 0.20),
            face(x: 0.85, size: 0.12),
            face(x: 0.45, size: 0.15)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 4)
        let sides = presentation.crops.map(\.pixelRect.width)
        XCTAssertEqual(sides, sides.sorted(by: >))
    }

    func testTinyFacesAreSkipped() {
        let tinyFace = DetectedFaceExpression(
            normalizedBounds: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )

        let presentation = CloseUpFacesPresentation(faces: [tinyFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertTrue(presentation.crops.isEmpty)
    }
}
