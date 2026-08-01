import CoreGraphics
import XCTest
@testable import TeststripCore

final class FaceReportGradingTests: XCTestCase {
    // Sample points chosen relative to the measured bands (Task 0): `clean`
    // sits above greenSignalFloor, `middling` strictly between the two
    // constants, `ruined` strictly below redSignalCeiling.
    private static let clean = 0.57 // greenSignalFloor (0.42) + 0.15
    private static let middling = 0.375 // midpoint of redSignalCeiling (0.33) and greenSignalFloor (0.42)
    private static let ruined = 0.165 // redSignalCeiling (0.33) / 2
    private static let prominentArea = 0.42 // prominenceFloor (0.021) * 20
    private static let bystanderArea = 0.0021 // prominenceFloor (0.021) / 10

    func testEveryCleanSignalGradesGreen() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.clean,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .green
        )
    }

    func testMiddlingSignalGradesYellow() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.middling,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .yellow
        )
    }

    func testRedSignalOnAProminentFaceGradesRed() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.ruined,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .red
        )
    }

    // The prominence-weighted roll-up's whole point: a bystander can flag
    // yellow but must never grade a frame red.
    func testRedSignalBelowTheProminenceFloorCapsAtYellow() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.ruined,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.bystanderArea
            ),
            .yellow
        )
    }

    func testClosedEyesAreARedGradeSignalOnAProminentFace() {
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: false,
                sharpness: Self.clean,
                light: Self.clean,
                facing: Self.clean,
                prominence: Self.prominentArea
            ),
            .red
        )
    }

    func testUnscoredSignalsNeverContributeAGrade() {
        // nil facing/sharpness/light must not read as 0 — that would fake a red.
        XCTAssertEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: nil,
                light: nil,
                facing: nil,
                prominence: Self.prominentArea
            ),
            .green
        )
    }

    // The corpus regression Task 0 exists to prevent: a usable off-axis head
    // (commons-glenn-1962, yaw -56.95 degrees — Task 0's measured original-level
    // worst case, superseding the plan's earlier assumed -56.2 degrees) must not
    // grade red on facing alone. `zeroAtRadians` (86 degrees) is chosen so that
    // head scores at or above redSignalCeiling.
    func testAUsableOffAxisHeadDoesNotGradeRedOnFacingAlone() {
        let facing = FaceFacingScore.score(yawRadians: -56.95 * .pi / 180, pitchRadians: 0)
        XCTAssertNotEqual(
            FaceReportGrading.grade(
                eyesOpen: true,
                sharpness: Self.clean,
                light: Self.clean,
                facing: facing,
                prominence: Self.prominentArea
            ),
            .red
        )
    }

    func testFaceReportDerivesItsGradeFromItsOwnScores() {
        let report = FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: Self.ruined,
            light: Self.clean,
            facing: Self.clean,
            prominence: Self.prominentArea
        )

        XCTAssertEqual(report.grade, .red)
        XCTAssertEqual(report.eyesScore, 1.0)
    }

    func testGradesOrderGreenBeforeYellowBeforeRed() {
        XCTAssertEqual([FaceReportGrade.yellow, .green, .red].max(), .red)
        XCTAssertEqual([FaceReportGrade.yellow, .green].max(), .yellow)
    }
}
