import CoreGraphics
import Foundation
import Vision
import XCTest
@testable import TeststripCore

final class FaceReportAnalyzerTests: XCTestCase {
    // MARK: - Fixtures

    /// Flat mid-gray everywhere, with an optional checkerboard patch (a
    /// stand-in for real face detail) and an optional flat-black patch (a
    /// stand-in for a crushed face).
    private func makeImage(
        width: Int = 400,
        height: Int = 400,
        checkerboard: CGRect? = nil,
        black: CGRect? = nil
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create face report test bitmap")
        }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let black {
            context.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
            context.fill(black)
        }
        if let checkerboard {
            let cell = 4
            for y in stride(from: 0, to: Int(checkerboard.height), by: cell) {
                for x in stride(from: 0, to: Int(checkerboard.width), by: cell) {
                    let isLight = ((x / cell) + (y / cell)).isMultiple(of: 2)
                    context.setFillColor(CGColor(gray: isLight ? 1.0 : 0.0, alpha: 1.0))
                    context.fill(CGRect(
                        x: checkerboard.minX + Double(x),
                        y: checkerboard.minY + Double(y),
                        width: Double(cell),
                        height: Double(cell)
                    ))
                }
            }
        }
        guard let image = context.makeImage() else {
            throw TeststripError.io("could not render face report test bitmap")
        }
        return image
    }

    private func face(
        x: Double = 0.0,
        y: Double = 0.0,
        side: Double = 0.5,
        hasSmile: Bool = false,
        leftEyeClosed: Bool = false,
        rightEyeClosed: Bool = false
    ) -> DetectedFaceExpression {
        DetectedFaceExpression(
            normalizedBounds: CGRect(x: x, y: y, width: side, height: side),
            hasSmile: hasSmile,
            leftEyeClosed: leftEyeClosed,
            rightEyeClosed: rightEyeClosed,
            leftEyeCenter: nil,
            rightEyeCenter: nil
        )
    }

    // `shouldFail` rather than a stored `any Error` so the stub stays
    // Sendable, which `FaceOrientationDetecting` requires.
    private struct StubOrientationDetector: FaceOrientationDetecting {
        var observations: [FaceOrientationObservation] = []
        var shouldFail = false

        func orientations(in image: CGImage) throws -> [FaceOrientationObservation] {
            if shouldFail { throw TeststripError.io("vision unavailable") }
            return observations
        }
    }

    // MARK: - Per-face sharpness and light

    func testDetailedFaceCropScoresSharperThanFlatFaceCrop() throws {
        // Top-left quadrant carries checkerboard detail; bottom-right is flat.
        let image = try makeImage(checkerboard: CGRect(x: 0, y: 200, width: 200, height: 200))
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(
            in: image,
            detections: [face(x: 0.0, y: 0.0, side: 0.5), face(x: 0.5, y: 0.5, side: 0.5)]
        )

        let detailed = try XCTUnwrap(reports[0].sharpness)
        let flat = try XCTUnwrap(reports[1].sharpness)
        XCTAssertGreaterThan(detailed, flat)
        XCTAssertLessThan(flat, 0.05)
    }

    func testMidGrayFaceCropScoresBetterLightThanCrushedBlackCrop() throws {
        let image = try makeImage(black: CGRect(x: 200, y: 0, width: 200, height: 200))
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(
            in: image,
            detections: [face(x: 0.0, y: 0.0, side: 0.5), face(x: 0.5, y: 0.5, side: 0.5)]
        )

        let balanced = try XCTUnwrap(reports[0].light)
        let crushed = try XCTUnwrap(reports[1].light)
        XCTAssertGreaterThan(balanced, crushed)
        XCTAssertGreaterThan(balanced, 0.8)
        XCTAssertLessThan(crushed, 0.1)
    }

    func testCropTooSmallToMeasureLeavesSharpnessAndLightUnscored() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        // 0.01 * 400 = 4 px, below the 8 px measurement floor.
        let reports = analyzer.reports(in: image, detections: [face(x: 0.5, y: 0.5, side: 0.01)])

        XCTAssertNil(reports[0].sharpness)
        XCTAssertNil(reports[0].light)
    }

    // MARK: - Prominence

    func testProminenceIsFaceAreaOverFrameArea() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [face(x: 0.1, y: 0.1, side: 0.5)])

        XCTAssertEqual(reports[0].prominence, 0.25, accuracy: 0.0001)
    }

    // MARK: - Eyes and smile carried through

    func testEyesOpenUsesTheSharedBothShutNoiseFloor() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [
            face(leftEyeClosed: true, rightEyeClosed: true),
            face(x: 0.5, leftEyeClosed: true, rightEyeClosed: false)
        ])

        XCTAssertFalse(reports[0].eyesOpen)
        // A single detected-shut eye is detector noise, not closed eyes.
        XCTAssertTrue(reports[1].eyesOpen)
    }

    func testBothEyesShutIsTheOneSharedRule() {
        XCTAssertTrue(face(leftEyeClosed: true, rightEyeClosed: true).bothEyesShut)
        XCTAssertFalse(face(leftEyeClosed: true, rightEyeClosed: false).bothEyesShut)
        XCTAssertFalse(face().bothEyesShut)
    }

    func testSmileIsCarriedThroughForHoverAndAccessibility() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [face(hasSmile: true)])

        XCTAssertTrue(reports[0].hasSmile)
    }

    // MARK: - Facing

    func testFacingComesFromTheMatchedOrientationObservation() throws {
        let image = try makeImage()
        let bounds = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        let detector = StubOrientationDetector(observations: [
            FaceOrientationObservation(normalizedBounds: bounds, yawRadians: 0, pitchRadians: 0)
        ])
        let analyzer = FaceReportAnalyzer(orientationDetector: detector)

        let reports = analyzer.reports(in: image, detections: [face(x: 0.0, y: 0.0, side: 0.5)])

        XCTAssertEqual(reports[0].facing, 1.0)
    }

    func testFailedOrientationRequestLeavesEveryFacingUnscored() throws {
        let image = try makeImage()
        let detector = StubOrientationDetector(shouldFail: true)
        let analyzer = FaceReportAnalyzer(orientationDetector: detector)

        let reports = analyzer.reports(in: image, detections: [face(), face(x: 0.5)])

        XCTAssertEqual(reports.map(\.facing), [nil, nil])
        // A failed request must not fake a green: nothing here claims a score.
        XCTAssertEqual(reports.count, 2)
    }

    func testReportsAreReturnedOnePerDetectionInDetectionOrder() throws {
        let image = try makeImage()
        let analyzer = FaceReportAnalyzer(orientationDetector: StubOrientationDetector())

        let reports = analyzer.reports(in: image, detections: [
            face(x: 0.0, side: 0.2),
            face(x: 0.5, side: 0.4)
        ])

        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].normalizedBounds.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(reports[1].normalizedBounds.width, 0.4, accuracy: 0.0001)
    }

    // MARK: - The real Vision detector's coordinate and pose mapping

    // Vision's boundingBox is bottom-left origin; report cards are top-left.
    // A constructed observation exercises the flip directly, which a
    // faceless-image test can never reach.
    func testVisionObservationBoundingBoxFlipsToTopLeftOrigin() {
        let observation = VNFaceObservation(
            requestRevision: VNDetectFaceRectanglesRequestRevision3,
            boundingBox: CGRect(x: 0.2, y: 0.7, width: 0.1, height: 0.2),
            roll: nil,
            yaw: NSNumber(value: 0.3),
            pitch: NSNumber(value: -0.1)
        )

        let mapped = VisionFaceOrientationDetector.orientation(from: observation)

        XCTAssertEqual(Double(mapped.normalizedBounds.minX), 0.2, accuracy: 0.0001)
        // bottom-left maxY 0.9 -> top-left minY 0.1
        XCTAssertEqual(Double(mapped.normalizedBounds.minY), 0.1, accuracy: 0.0001)
        XCTAssertEqual(Double(mapped.normalizedBounds.width), 0.1, accuracy: 0.0001)
        XCTAssertEqual(Double(mapped.normalizedBounds.height), 0.2, accuracy: 0.0001)
        XCTAssertEqual(mapped.yawRadians ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(mapped.pitchRadians ?? 0, -0.1, accuracy: 0.0001)
    }

    func testVisionObservationWithoutPoseMapsToUnscoredAxes() {
        let observation = VNFaceObservation(
            requestRevision: VNDetectFaceRectanglesRequestRevision3,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            roll: nil,
            yaw: nil,
            pitch: nil
        )

        let mapped = VisionFaceOrientationDetector.orientation(from: observation)

        XCTAssertNil(mapped.yawRadians)
        XCTAssertNil(mapped.pitchRadians)
        XCTAssertNil(FaceFacingScore.score(yawRadians: mapped.yawRadians, pitchRadians: mapped.pitchRadians))
    }

    func testVisionOrientationDetectorFindsNoFacesInAFacelessImage() throws {
        let image = try makeImage()

        XCTAssertEqual(try VisionFaceOrientationDetector().orientations(in: image), [])
    }

    // MARK: - Shared exposure helper

    func testBalancedExposurePeaksAtMidGrayAndBottomsOutAtTheExtremes() {
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 0.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 0.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewPixelMetrics.balancedExposure(meanLuminance: 0.25), 0.5, accuracy: 0.0001)
    }
}
