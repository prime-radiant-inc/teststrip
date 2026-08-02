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

    // The three-way interaction the two tests above only cover in pairs: a
    // scrambled detection order, faces below the crop floor, AND more
    // croppable faces than the cap. Get any leg wrong and a tile renders
    // another face's report card, which is the one failure mode `faceIndex`
    // exists to prevent. (Sub-floor faces are also the smallest by area, so
    // they always sort last and can never consume cap budget — asserted here
    // by the cap landing on exactly the four largest.)
    func testTheCapKeepsTheFourLargestFacesIndicesEvenWithSubFloorFacesInTheMix() {
        // side = max(width * 2000, height * 1000) * 1.6, floor 24px, so
        // anything under size 0.0075 is sub-floor here.
        let faces = [
            Self.face(x: 0.02, size: 0.11),  // 0 — croppable, 5th largest
            Self.face(x: 0.14, size: 0.004), // 1 — sub-floor
            Self.face(x: 0.22, size: 0.30),  // 2 — largest
            Self.face(x: 0.40, size: 0.18),  // 3 — 3rd largest
            Self.face(x: 0.56, size: 0.006), // 4 — sub-floor
            Self.face(x: 0.70, size: 0.25),  // 5 — 2nd largest
            Self.face(x: 0.88, size: 0.15)   // 6 — 4th largest
        ]

        let presentation = CloseUpFacesPresentation(faces: faces, imagePixelSize: CGSize(width: 2000, height: 1000))

        XCTAssertEqual(presentation.crops.count, CloseUpFacesPresentation.maximumCropCount)
        // Descending area: 0.30 (2), 0.25 (5), 0.18 (3), 0.15 (6).
        XCTAssertEqual(presentation.crops.map(\.faceIndex), [2, 5, 3, 6])
        XCTAssertEqual(presentation.crops.map(\.id), [0, 1, 2, 3])
        // The sub-floor faces are excluded outright, never merely reordered.
        XCTAssertFalse(presentation.crops.map(\.faceIndex).contains(1))
        XCTAssertFalse(presentation.crops.map(\.faceIndex).contains(4))
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
