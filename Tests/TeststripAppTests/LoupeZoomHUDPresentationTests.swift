import XCTest
@testable import TeststripApp

final class LoupeZoomHUDPresentationTests: XCTestCase {
    func testSatisfiedFullResolutionShowsOnlyZoomLabel() {
        let presentation = LoupeZoomHUDPresentation(scale: 1.0, fullResolutionStatus: .satisfied)

        XCTAssertEqual(presentation.zoomLabelText, "100%")
        XCTAssertNil(presentation.statusText)
        XCTAssertFalse(presentation.isLoading)
        XCTAssertEqual(presentation.accessibilityValue, "100%")
    }

    func testLoadingFullResolutionShowsHonestIndicator() {
        let presentation = LoupeZoomHUDPresentation(scale: 1.0, fullResolutionStatus: .loading)

        XCTAssertEqual(presentation.zoomLabelText, "100%")
        XCTAssertEqual(presentation.statusText, "Loading full resolution…")
        XCTAssertTrue(presentation.isLoading)
        XCTAssertEqual(presentation.accessibilityValue, "100%, loading full resolution")
    }

    func testUnavailableFullResolutionSaysSo() {
        let presentation = LoupeZoomHUDPresentation(scale: 1.0, fullResolutionStatus: .unavailable)

        XCTAssertEqual(presentation.zoomLabelText, "100%")
        XCTAssertEqual(presentation.statusText, "Full resolution unavailable")
        XCTAssertFalse(presentation.isLoading)
        XCTAssertEqual(presentation.accessibilityValue, "100%, full resolution unavailable")
    }

    func testSatisfiedWithScaleShowsPercentage() {
        let presentation = LoupeZoomHUDPresentation(scale: 2.5, fullResolutionStatus: .satisfied)
        XCTAssertEqual(presentation.zoomLabelText, "250%")
        XCTAssertNil(presentation.statusText)
    }

    func testLoadingWithScaleShowsPercentage() {
        let presentation = LoupeZoomHUDPresentation(scale: 12.0, fullResolutionStatus: .loading)
        XCTAssertEqual(presentation.zoomLabelText, "1200%")
        XCTAssertEqual(presentation.statusText, "Loading full resolution…")
    }

    func testUnavailableWithScaleShowsPercentage() {
        let presentation = LoupeZoomHUDPresentation(scale: 4.0, fullResolutionStatus: .unavailable)
        XCTAssertEqual(presentation.zoomLabelText, "400%")
        XCTAssertEqual(presentation.statusText, "Full resolution unavailable")
    }

    func testScale1Shows100() {
        let presentation = LoupeZoomHUDPresentation(scale: 1.0, fullResolutionStatus: .satisfied)
        XCTAssertEqual(presentation.zoomLabelText, "100%")
    }
}
