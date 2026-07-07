import XCTest
@testable import TeststripApp

final class LoupeZoomHUDPresentationTests: XCTestCase {
    func testSatisfiedFullResolutionShowsOnlyZoomLabel() {
        let presentation = LoupeZoomHUDPresentation(fullResolutionStatus: .satisfied)

        XCTAssertEqual(presentation.zoomLabelText, "100%")
        XCTAssertNil(presentation.statusText)
        XCTAssertFalse(presentation.isLoading)
        XCTAssertEqual(presentation.accessibilityValue, "100%")
    }

    func testLoadingFullResolutionShowsHonestIndicator() {
        let presentation = LoupeZoomHUDPresentation(fullResolutionStatus: .loading)

        XCTAssertEqual(presentation.zoomLabelText, "100%")
        XCTAssertEqual(presentation.statusText, "Loading full resolution…")
        XCTAssertTrue(presentation.isLoading)
        XCTAssertEqual(presentation.accessibilityValue, "100%, loading full resolution")
    }

    func testUnavailableFullResolutionSaysSo() {
        let presentation = LoupeZoomHUDPresentation(fullResolutionStatus: .unavailable)

        XCTAssertEqual(presentation.zoomLabelText, "100%")
        XCTAssertEqual(presentation.statusText, "Full resolution unavailable")
        XCTAssertFalse(presentation.isLoading)
        XCTAssertEqual(presentation.accessibilityValue, "100%, full resolution unavailable")
    }
}
