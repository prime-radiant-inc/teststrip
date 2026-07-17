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

    // MARK: - Eyes/smile marks (always known, straight from the detector)

    func testEyesStateClosedOnlyWhenBothEyesShut() {
        let bothShut = Self.face(leftEyeClosed: true, rightEyeClosed: true)
        let oneShut = Self.face(leftEyeClosed: true, rightEyeClosed: false)
        let bothOpen = Self.face(leftEyeClosed: false, rightEyeClosed: false)

        XCTAssertEqual(
            CloseUpFacesPresentation(faces: [bothShut], imagePixelSize: Self.imageSize).crops[0].eyesState,
            .closed
        )
        // A single detected-shut eye is treated the same as the rest of the
        // codebase's blink noise floor — only both-shut reads as closed.
        XCTAssertEqual(
            CloseUpFacesPresentation(faces: [oneShut], imagePixelSize: Self.imageSize).crops[0].eyesState,
            .open
        )
        XCTAssertEqual(
            CloseUpFacesPresentation(faces: [bothOpen], imagePixelSize: Self.imageSize).crops[0].eyesState,
            .open
        )
    }

    func testSmileMarkReflectsHasSmile() {
        let smiling = Self.face(hasSmile: true)
        let notSmiling = Self.face(hasSmile: false)

        XCTAssertTrue(CloseUpFacesPresentation(faces: [smiling], imagePixelSize: Self.imageSize).crops[0].isSmiling)
        XCTAssertFalse(CloseUpFacesPresentation(faces: [notSmiling], imagePixelSize: Self.imageSize).crops[0].isSmiling)
    }

    // MARK: - Sharpness mark (asset-level signal, honestly attributed only when unambiguous)

    func testSharpnessMarkSharpWhenFaceQualityAboveThreshold() {
        let presentation = CloseUpFacesPresentation(
            faces: [Self.face()],
            imagePixelSize: Self.imageSize,
            wholePhotoSignals: [Self.signal(kind: .faceQuality, score: 0.6)]
        )

        XCTAssertEqual(presentation.crops[0].sharpnessTone, .sharp)
    }

    func testSharpnessMarkSoftWhenFaceQualityBelowThreshold() {
        let presentation = CloseUpFacesPresentation(
            faces: [Self.face()],
            imagePixelSize: Self.imageSize,
            wholePhotoSignals: [Self.signal(kind: .faceQuality, score: 0.2)]
        )

        XCTAssertEqual(presentation.crops[0].sharpnessTone, .soft)
    }

    func testSharpnessMarkFallsBackToEyeSharpnessWhenNoFaceQuality() {
        let sharp = CloseUpFacesPresentation(
            faces: [Self.face()],
            imagePixelSize: Self.imageSize,
            wholePhotoSignals: [Self.signal(kind: .eyeSharpness, score: 0.5)]
        )
        let soft = CloseUpFacesPresentation(
            faces: [Self.face()],
            imagePixelSize: Self.imageSize,
            wholePhotoSignals: [Self.signal(kind: .eyeSharpness, score: 0.1)]
        )

        XCTAssertEqual(sharp.crops[0].sharpnessTone, .sharp)
        XCTAssertEqual(soft.crops[0].sharpnessTone, .soft)
    }

    func testSharpnessMarkAbsentWithoutASignal() {
        let presentation = CloseUpFacesPresentation(faces: [Self.face()], imagePixelSize: Self.imageSize)

        XCTAssertNil(presentation.crops[0].sharpnessTone)
    }

    // faceQuality/eyeSharpness are asset-level reads — evaluation signals
    // carry no per-face location — so attributing one to a specific crop is
    // only honest when there's exactly one face on the frame. With 2+ faces,
    // no crop gets a sharpness mark rather than guessing which face it's for.
    func testSharpnessMarkAbsentOnEveryCropWhenMultipleFacesShareTheSignal() {
        let faces = [Self.face(x: 0.1), Self.face(x: 0.5)]
        let presentation = CloseUpFacesPresentation(
            faces: faces,
            imagePixelSize: CGSize(width: 2000, height: 1000),
            wholePhotoSignals: [Self.signal(kind: .faceQuality, score: 0.9)]
        )

        XCTAssertEqual(presentation.crops.count, 2)
        XCTAssertEqual(presentation.crops.map(\.sharpnessTone), [nil, nil])
    }

    private static let imageSize = CGSize(width: 1000, height: 1000)

    private static func face(
        x: Double = 0.4,
        hasSmile: Bool = false,
        leftEyeClosed: Bool = false,
        rightEyeClosed: Bool = false
    ) -> DetectedFaceExpression {
        DetectedFaceExpression(
            normalizedBounds: CGRect(x: x, y: 0.4, width: 0.2, height: 0.2),
            hasSmile: hasSmile,
            leftEyeClosed: leftEyeClosed,
            rightEyeClosed: rightEyeClosed,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )
    }

    private static func signal(kind: EvaluationKind, score: Double) -> EvaluationSignal {
        EvaluationSignal(
            assetID: AssetID(rawValue: "asset"),
            kind: kind,
            value: .score(score),
            confidence: 1.0,
            provenance: ProviderProvenance(
                provider: "local-http",
                model: "test-model",
                version: "1",
                settingsHash: "test"
            )
        )
    }
}
