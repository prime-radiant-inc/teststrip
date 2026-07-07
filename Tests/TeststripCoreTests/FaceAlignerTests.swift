import XCTest
import CoreGraphics
@testable import TeststripCore

final class FaceAlignerTests: XCTestCase {
    func testTransformMapsSourceLandmarksToCanonicalPositions() throws {
        // Source landmarks already at canonical positions must map ~identity.
        let canonical = FaceAligner.canonicalPoints
        let points = FaceLandmarkPoints(
            leftEye: canonical.leftEye, rightEye: canonical.rightEye,
            nose: canonical.nose, leftMouth: canonical.leftMouth, rightMouth: canonical.rightMouth
        )
        let t = try XCTUnwrap(FaceAligner.similarityTransform(from: points))
        for p in [canonical.leftEye, canonical.rightEye, canonical.nose] {
            let mapped = p.applying(t)
            XCTAssertEqual(mapped.x, p.x, accuracy: 0.5)
            XCTAssertEqual(mapped.y, p.y, accuracy: 0.5)
        }
    }

    func testTransformRecoversAKnownScaleAndTranslation() throws {
        // Source = canonical scaled 2x and shifted (+10,+20): transform must undo it.
        let c = FaceAligner.canonicalPoints
        func f(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * 2 + 10, y: p.y * 2 + 20) }
        let points = FaceLandmarkPoints(leftEye: f(c.leftEye), rightEye: f(c.rightEye),
            nose: f(c.nose), leftMouth: f(c.leftMouth), rightMouth: f(c.rightMouth))
        let t = try XCTUnwrap(FaceAligner.similarityTransform(from: points))
        let mapped = f(c.leftEye).applying(t)
        XCTAssertEqual(mapped.x, c.leftEye.x, accuracy: 0.5)
        XCTAssertEqual(mapped.y, c.leftEye.y, accuracy: 0.5)
    }

    func testDegeneratePointsReturnNil() {
        let zero = CGPoint.zero
        let points = FaceLandmarkPoints(leftEye: zero, rightEye: zero, nose: zero, leftMouth: zero, rightMouth: zero)
        XCTAssertNil(FaceAligner.similarityTransform(from: points))
    }
}
