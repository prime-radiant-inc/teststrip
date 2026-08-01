import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore

final class FaceFacingScoreTests: XCTestCase {
    private static func degrees(_ value: Double) -> Double { value * .pi / 180.0 }

    // MARK: - Score

    func testFullFrontalScoresOne() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: 0, pitchRadians: 0), 1.0)
    }

    func testHalfWayToTheZeroAngleScoresHalf() {
        let score = FaceFacingScore.score(yawRadians: FaceFacingScore.zeroAtRadians / 2, pitchRadians: 0)
        XCTAssertEqual(score ?? 0, 0.5, accuracy: 0.0001)
    }

    func testDirectionOfTurnDoesNotMatter() {
        XCTAssertEqual(
            FaceFacingScore.score(yawRadians: -FaceFacingScore.zeroAtRadians / 3, pitchRadians: 0),
            FaceFacingScore.score(yawRadians: FaceFacingScore.zeroAtRadians / 3, pitchRadians: 0)
        )
    }

    func testAtOrBeyondTheZeroAngleScoresZero() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: FaceFacingScore.zeroAtRadians, pitchRadians: 0), 0.0)
        // Vision reports yaw in [-Pi/2, Pi/2]; a full profile clamps, never
        // goes negative.
        XCTAssertEqual(FaceFacingScore.score(yawRadians: .pi / 2, pitchRadians: 0), 0.0)
    }

    func testTheWorseAxisGovernsRatherThanABlend() {
        let score = FaceFacingScore.score(yawRadians: 0, pitchRadians: -FaceFacingScore.zeroAtRadians / 2)
        XCTAssertEqual(score ?? 0, 0.5, accuracy: 0.0001)
    }

    func testAMissingAxisIsTreatedAsLevel() {
        XCTAssertEqual(FaceFacingScore.score(yawRadians: 0, pitchRadians: nil), 1.0)
    }

    func testBothAxesMissingIsUnscored() {
        XCTAssertNil(FaceFacingScore.score(yawRadians: nil, pitchRadians: nil))
    }

    // The corpus regression `zeroAtRadians` was measured to prevent
    // (commons-glenn-1962, yaw -56.95 degrees — Task 0's measured
    // original-level worst case; supersedes the plan's earlier assumed
    // -56.2 degrees, same correction Task 1A made): a usable off-axis head
    // must score at or above redSignalCeiling so facing alone cannot grade
    // it red.
    func testTheCorpusStrongestOffAxisHeadStaysOutOfTheRedBand() {
        let score = FaceFacingScore.score(yawRadians: Self.degrees(-56.95), pitchRadians: 0)
        XCTAssertGreaterThanOrEqual(score ?? 0, FaceReportGrading.redSignalCeiling)
    }

    // MARK: - Matching

    func testGreatestOverlapObservationWins() {
        let detection = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let partial = CGRect(x: 0.45, y: 0.45, width: 0.2, height: 0.2)
        // Both candidates must clear the floor, so this test is about ranking
        // rather than filtering. If the measured floor ever rises above this,
        // the assertion fails loudly instead of quietly changing meaning.
        XCTAssertGreaterThan(
            FaceFacingScore.intersectionOverUnion(detection, partial),
            FaceFacingScore.minimumBoxOverlap
        )
        let poorOverlap = FaceOrientationObservation(
            normalizedBounds: partial,
            yawRadians: FaceFacingScore.zeroAtRadians,
            pitchRadians: 0
        )
        let exactOverlap = FaceOrientationObservation(
            normalizedBounds: detection,
            yawRadians: 0,
            pitchRadians: 0
        )

        let facing = FaceFacingScore.matched(
            detectionBounds: [detection],
            orientations: [poorOverlap, exactOverlap]
        )

        XCTAssertEqual(facing, [1.0])
    }

    // The amendment-1 finding: the two detectors' boxes for the SAME face
    // agreed at IoU 0.228 at 1600px (and 0.510 at 512px). A floor that
    // rejects 0.228 throws away a correct match and blanks the facing chip on
    // a frame that has a perfectly good head-pose read.
    func testTheCorpusWorstCorrectMatchIsStillMatched() {
        // Two concentric boxes whose IoU is 0.228: side ratio r satisfies
        // r^2 = 0.228 for nested squares, so r ~= 0.4775.
        let detection = CGRect(x: 0.3, y: 0.3, width: 0.40, height: 0.40)
        let observationBounds = CGRect(x: 0.3955, y: 0.3955, width: 0.191, height: 0.191)
        XCTAssertEqual(
            FaceFacingScore.intersectionOverUnion(detection, observationBounds),
            0.228,
            accuracy: 0.01
        )

        let facing = FaceFacingScore.matched(
            detectionBounds: [detection],
            orientations: [
                FaceOrientationObservation(normalizedBounds: observationBounds, yawRadians: 0, pitchRadians: 0)
            ]
        )

        XCTAssertEqual(facing, [1.0])
    }

    func testADetectionWithNoOverlappingObservationIsUnscored() {
        let facing = FaceFacingScore.matched(
            detectionBounds: [CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1)],
            orientations: [
                FaceOrientationObservation(
                    normalizedBounds: CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1),
                    yawRadians: 0,
                    pitchRadians: 0
                )
            ]
        )

        XCTAssertEqual(facing, [nil])
    }

    func testOneObservationIsClaimedByOnlyOneDetection() {
        let close = CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.20)
        let overlapping = CGRect(x: 0.42, y: 0.42, width: 0.20, height: 0.20)
        let observation = FaceOrientationObservation(
            normalizedBounds: close,
            yawRadians: 0,
            pitchRadians: 0
        )

        let facing = FaceFacingScore.matched(
            detectionBounds: [overlapping, close],
            orientations: [observation]
        )

        // The exact-overlap detection wins the single observation; the other
        // is left unscored rather than borrowing a stranger's angles.
        XCTAssertEqual(facing, [nil, 1.0])
    }

    func testMatchedReturnsOneEntryPerDetectionInOrder() {
        XCTAssertEqual(FaceFacingScore.matched(detectionBounds: [], orientations: []), [])
    }
}
