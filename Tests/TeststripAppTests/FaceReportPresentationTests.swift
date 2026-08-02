import AppKit
import CoreGraphics
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class FaceReportPresentationTests: XCTestCase {
    private static func report(
        eyesOpen: Bool = true,
        hasSmile: Bool = false,
        sharpness: Double? = 0.82,
        light: Double? = 0.61,
        facing: Double? = 0.94,
        prominence: Double = 0.2
    ) -> FaceReport {
        FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: eyesOpen,
            hasSmile: hasSmile,
            sharpness: sharpness,
            light: light,
            facing: facing,
            prominence: prominence
        )
    }

    /// Band-relative fixtures so these tests survive a re-measurement of the
    /// Task 0 constants.
    private static var cleanScore: Double { min(FaceReportGrading.greenSignalFloor + 0.15, 1.0) }
    private static var middlingScore: Double {
        (FaceReportGrading.redSignalCeiling + FaceReportGrading.greenSignalFloor) / 2
    }
    private static var ruinedScore: Double { FaceReportGrading.redSignalCeiling / 2 }

    private static func frame(_ reports: [FaceReport]) -> FrameFaceReport {
        FrameFaceReport(reports: reports, previewCacheGeneration: 1, analyzedLevel: .medium)
    }

    // MARK: - Chips

    func testChipRowIsAlwaysAllFourSignalsInFixedOrder() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.signal), [.eyes, .sharpness, .facing, .light])
    }

    func testEveryChipIsPresentEvenWhenNothingWasMeasured() {
        let presentation = FaceReportChipPresentation(
            report: Self.report(sharpness: nil, light: nil, facing: nil)
        )

        XCTAssertEqual(presentation.entries.count, 4)
        XCTAssertEqual(presentation.entries.map(\.score), [1.0, nil, nil, nil])
    }

    func testChipScoresMirrorTheReport() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.score), [1.0, 0.82, 0.94, 0.61])
    }

    func testClosedEyesScoreZeroRatherThanGoingUnscored() {
        let presentation = FaceReportChipPresentation(report: Self.report(eyesOpen: false))

        XCTAssertEqual(presentation.entries[0].score, 0.0)
        XCTAssertEqual(presentation.entries[0].accessibilityText, "Eyes 0%")
    }

    func testChipAccessibilityTextIsTheSignalWordAndPercent() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.accessibilityText), [
            "Eyes 100%",
            "Sharpness 82%",
            "Facing 94%",
            "Light 61%"
        ])
    }

    func testAnUnscoredSignalSaysNoReadRatherThanZeroPercent() {
        let presentation = FaceReportChipPresentation(report: Self.report(facing: nil))

        XCTAssertEqual(presentation.entries[2].score, nil)
        XCTAssertEqual(presentation.entries[2].accessibilityText, "Facing no read")
    }

    func testChipEntryIdentityIsItsSignal() {
        let presentation = FaceReportChipPresentation(report: Self.report())

        XCTAssertEqual(presentation.entries.map(\.id), ["eyes", "sharpness", "facing", "light"])
    }

    // MARK: - Chip symbol names (Task 5 review fix 1: pin the exact SF Symbol names)

    func testChipSymbolNamesArePinnedPerSignal() {
        XCTAssertEqual(FaceReportSignal.eyes.symbolName, "eye.fill")
        XCTAssertEqual(FaceReportSignal.sharpness.symbolName, "scope")
        XCTAssertEqual(FaceReportSignal.facing.symbolName, "person.fill")
        XCTAssertEqual(FaceReportSignal.light.symbolName, "sun.max.fill")
    }

    func testEveryChipSymbolNameExistsAsARealSFSymbol() {
        for signal in FaceReportSignal.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: signal.symbolName, accessibilityDescription: nil),
                "\(signal) symbol name \"\(signal.symbolName)\" is not a real SF Symbol"
            )
        }
    }

    // MARK: - Percentage rounding (Task 5 review fix 2: pin the half-boundary rule)

    // 98.5% is an exact tie: `.rounded()` (half away from zero) rounds up to
    // 99%, while `.rounded(.toNearestOrEven)` would round down to 98% (98 is
    // even). This pins the current away-from-zero behavior so a switch to
    // toNearestOrEven silently changing displayed chip percentages gets caught.
    func testHalfBoundaryPercentRoundsAwayFromZeroNotToEven() {
        let presentation = FaceReportChipPresentation(report: Self.report(sharpness: 0.985))

        XCTAssertEqual(presentation.entries[1].score, 0.985)
        XCTAssertEqual(presentation.entries[1].accessibilityText, "Sharpness 99%")
    }

    // MARK: - Tile accessibility

    // The tile is an `.accessibilityElement(children: .combine)`, which
    // collapses the chips' own labels into one composed value — so a card
    // driving the live app can only assert what THIS string carries. It
    // therefore has to carry every signal's percentage, not just the grade.
    func testTileAccessibilityValueCarriesGradeEyesSmileAndEveryChipPercentage() {
        XCTAssertEqual(
            FaceReportRollUpPresentation.tileAccessibilityValue(
                for: Self.report(hasSmile: true, sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore)
            ),
            "Clean, Eyes open, Smiling, Eyes 100%, "
                + "Sharpness \(Int((Self.cleanScore * 100).rounded()))%, "
                + "Facing \(Int((Self.cleanScore * 100).rounded()))%, "
                + "Light \(Int((Self.cleanScore * 100).rounded()))%"
        )
    }

    func testTileAccessibilityValueChipStringsAreExactlyTheChipRowsStrings() {
        let report = Self.report(facing: nil)
        let chipStrings = FaceReportChipPresentation(report: report).entries.map(\.accessibilityText)

        let value = FaceReportRollUpPresentation.tileAccessibilityValue(for: report)

        for chipString in chipStrings {
            XCTAssertTrue(value.contains(chipString), "tile value is missing chip string \(chipString)")
        }
        // Closed eyes still read as a word, not only as a percentage.
        XCTAssertTrue(
            FaceReportRollUpPresentation
                .tileAccessibilityValue(for: Self.report(eyesOpen: false))
                .contains("Eyes closed")
        )
    }

    // The negative leg of the smile rule: a non-smiling face is not a defect,
    // so the value must say nothing at all about the smile rather than
    // announcing "Not smiling" — and a scenario card asserting on the absence
    // of "Smiling" has to be able to trust that absence.
    func testANonSmilingFaceSaysNothingAboutSmilingAtAll() {
        let value = FaceReportRollUpPresentation.tileAccessibilityValue(for: Self.report(hasSmile: false))

        XCTAssertFalse(
            value.lowercased().contains("smil"),
            "non-smiling tile value must not mention a smile at all: \(value)"
        )
        // …and the rest of the value is unchanged by the omission.
        XCTAssertEqual(
            value,
            FaceReportRollUpPresentation
                .tileAccessibilityValue(for: Self.report(hasSmile: true))
                .replacingOccurrences(of: "Smiling, ", with: "")
        )
    }

    // MARK: - Roll-up

    func testGradeWordsAreTheTrafficLightVocabulary() {
        XCTAssertEqual(FaceReportRollUpPresentation.word(for: .green), "Clean")
        XCTAssertEqual(FaceReportRollUpPresentation.word(for: .yellow), "Check")
        XCTAssertEqual(FaceReportRollUpPresentation.word(for: .red), "Ruined")
    }

    func testAnUncomputedFrameHasNoDotAndSaysSoInTheHeader() {
        XCTAssertNil(FaceReportRollUpPresentation.dotGrade(for: nil))
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: nil), "Faces not read yet")
    }

    func testAFacelessFrameHasNoDotAndKeepsTheHonestEmptyState() {
        let frame = Self.frame([])

        XCTAssertNil(FaceReportRollUpPresentation.dotGrade(for: frame))
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "No faces")
    }

    func testTheDotIsTheWorstProminentFacesGrade() {
        let frame = Self.frame([
            Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3),
            Self.report(sharpness: Self.ruinedScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3)
        ])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .red)
    }

    func testABelowFloorRuinedFaceCapsTheDotAtYellow() {
        let frame = Self.frame([
            Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3),
            Self.report(
                sharpness: Self.ruinedScore,
                light: Self.cleanScore,
                facing: Self.cleanScore,
                prominence: FaceReportGrading.prominenceFloor / 10
            )
        ])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
    }

    func testTheHeaderReportsTheSameGradeAsTheDotForTheSameFrame() {
        let frame = Self.frame([
            Self.report(sharpness: Self.middlingScore, light: Self.cleanScore, facing: Self.cleanScore, prominence: 0.3)
        ])

        XCTAssertEqual(FaceReportRollUpPresentation.dotGrade(for: frame), .yellow)
        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "1 face, Check")
    }

    func testTheHeaderPluralizesTheFaceCount() {
        let clean = Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore)
        let frame = Self.frame([clean, clean, clean])

        XCTAssertEqual(FaceReportRollUpPresentation.headerValue(for: frame), "3 faces, Clean")
    }

    // MARK: - Rail state (the panel's text and its dot come from one source)

    func testRailStateIsNotReadForAnUncomputedFrame() {
        XCTAssertEqual(FaceReportRollUpPresentation.railState(for: nil), .notRead)
    }

    func testRailStateIsNoFacesForAFacelessFrame() {
        XCTAssertEqual(FaceReportRollUpPresentation.railState(for: Self.frame([])), .noFaces)
    }

    func testRailStateIsFacesWithCountAndGradeOtherwise() {
        let clean = Self.report(sharpness: Self.cleanScore, light: Self.cleanScore, facing: Self.cleanScore)

        XCTAssertEqual(
            FaceReportRollUpPresentation.railState(for: Self.frame([clean, clean])),
            .faces(count: 2, grade: .green)
        )
    }
}
