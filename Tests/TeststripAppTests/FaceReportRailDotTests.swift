import CoreGraphics
import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// The burst rail's one overlay dot per thumb: what it says, and — just as
/// load-bearing — when it says nothing at all.
final class FaceReportRailDotTests: XCTestCase {
    private static func report(sharpness: Double, prominence: Double = 0.2) -> FaceReport {
        FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: sharpness,
            light: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0),
            facing: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0),
            prominence: prominence
        )
    }

    private static func frame(_ reports: [FaceReport]) -> FrameFaceReport {
        FrameFaceReport(reports: reports, previewCacheGeneration: 1, analyzedLevel: .medium)
    }

    private static var cleanScore: Double { min(FaceReportGrading.greenSignalFloor + 0.15, 1.0) }
    private static var middlingScore: Double {
        (FaceReportGrading.redSignalCeiling + FaceReportGrading.greenSignalFloor) / 2
    }
    private static var ruinedScore: Double { FaceReportGrading.redSignalCeiling / 2 }

    func testAnUncomputedFrameSaysNothing() {
        XCTAssertNil(FaceReportRollUpPresentation.railAccessibilityText(for: nil))
    }

    func testAFacelessFrameSaysNothing() {
        // Absence means "nothing known", never "known good" — a faceless
        // frame must not announce a clean read.
        XCTAssertNil(FaceReportRollUpPresentation.railAccessibilityText(for: Self.frame([])))
    }

    func testACleanFrameAnnouncesItsGrade() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.railAccessibilityText(for: Self.frame([Self.report(sharpness: Self.cleanScore)])),
            "Faces clean"
        )
    }

    func testARuinedFrameAnnouncesItsGrade() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.railAccessibilityText(for: Self.frame([Self.report(sharpness: Self.ruinedScore)])),
            "Faces ruined"
        )
    }

    func testTheRailDotAndThePanelHeaderReadTheSameFrameTheSameWay() {
        let frame = Self.frame([Self.report(sharpness: Self.middlingScore)])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "1 face, Check")
        XCTAssertEqual(FaceReportRollUpPresentation.railAccessibilityText(for: frame), "Faces check")
    }
}
