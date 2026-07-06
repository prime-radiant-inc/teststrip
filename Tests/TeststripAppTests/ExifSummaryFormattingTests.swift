import XCTest
@testable import TeststripApp

final class ExifSummaryFormattingTests: XCTestCase {
    func testApertureTextShowsFractionalFStop() {
        XCTAssertEqual(ExifSummaryFormatting.apertureText(2.8), "ƒ/2.8")
    }

    func testApertureTextDropsRedundantDecimalForWholeFStop() {
        XCTAssertEqual(ExifSummaryFormatting.apertureText(4), "ƒ/4")
    }

    func testShutterSpeedTextShowsFractionForSubSecondExposures() {
        XCTAssertEqual(ExifSummaryFormatting.shutterSpeedText(1.0 / 250.0), "1/250s")
    }

    func testShutterSpeedTextShowsDecimalSecondsAtOrAboveOneSecond() {
        XCTAssertEqual(ExifSummaryFormatting.shutterSpeedText(2.5), "2.5s")
    }

    func testShutterSpeedTextDropsRedundantDecimalForWholeSeconds() {
        XCTAssertEqual(ExifSummaryFormatting.shutterSpeedText(15), "15s")
    }

    func testFocalLengthTextRoundsToWholeMillimeters() {
        XCTAssertEqual(ExifSummaryFormatting.focalLengthText(85), "85mm")
    }
}
