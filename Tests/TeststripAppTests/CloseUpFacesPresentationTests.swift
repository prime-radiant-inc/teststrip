import CoreGraphics
import Foundation
import TeststripCore
import XCTest
@testable import TeststripApp

final class CloseUpFacesPresentationTests: XCTestCase {
    func testCropsPadAndCenterOnTheFace() {
        let face = Self.face(x: 0.4, y: 0.4, size: 0.2)

        let presentation = CloseUpFacesPresentation(faces: [face], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 1)
        // Face is 200x200 px centered at (500, 500); padded side = 200 * 1.6 = 320.
        XCTAssertEqual(presentation.crops[0].pixelRect, CGRect(x: 340, y: 340, width: 320, height: 320))
    }

    func testCropsClampToImageBounds() {
        let cornerFace = Self.face(x: 0.0, size: 0.2)

        let presentation = CloseUpFacesPresentation(faces: [cornerFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        let rect = presentation.crops[0].pixelRect
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1000)
        XCTAssertLessThanOrEqual(rect.maxY, 1000)
    }

    func testCropsOrderLargestFaceFirstAndCapAtFour() {
        let faces = [
            Self.face(x: 0.05, size: 0.10),
            Self.face(x: 0.25, size: 0.30),
            Self.face(x: 0.60, size: 0.20),
            Self.face(x: 0.85, size: 0.12),
            Self.face(x: 0.45, size: 0.15)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.count, 4)
        let sides = presentation.crops.map(\.pixelRect.width)
        XCTAssertEqual(sides, sides.sorted(by: >))
    }

    func testTinyFacesAreSkipped() {
        let tinyFace = Self.face(x: 0.5, y: 0.5, size: 0.01)

        let presentation = CloseUpFacesPresentation(faces: [tinyFace], imagePixelSize: CGSize(width: 1000, height: 1000))

        XCTAssertTrue(presentation.crops.isEmpty)
    }

    // Crops are sorted largest-first while reports stay in detection order,
    // so each crop has to say which detection it came from or the tile would
    // show another face's report card.
    func testEachCropCarriesTheIndexOfTheFaceItCameFrom() {
        let faces = [
            Self.face(x: 0.05, size: 0.10),
            Self.face(x: 0.25, size: 0.30),
            Self.face(x: 0.60, size: 0.20)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.map(\.faceIndex), [1, 2, 0])
        XCTAssertEqual(presentation.crops.map(\.id), [0, 1, 2])
    }

    func testSkippedTinyFacesDoNotShiftTheRemainingFaceIndices() {
        let faces = [
            Self.face(x: 0.05, size: 0.005),
            Self.face(x: 0.40, size: 0.30)
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.map(\.faceIndex), [1])
    }

    private static func face(x: Double, y: Double = 0.1, size: Double) -> DetectedFaceExpression {
        DetectedFaceExpression(
            normalizedBounds: CGRect(x: x, y: y, width: size, height: size),
            hasSmile: false,
            leftEyeClosed: false,
            rightEyeClosed: false,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )
    }
}
