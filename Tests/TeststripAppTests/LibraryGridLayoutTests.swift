import XCTest
@testable import TeststripApp

final class LibraryGridLayoutTests: XCTestCase {
    func testThumbnailWidthClampsToSupportedRange() {
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 40).thumbnailWidth, 96)
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 140).thumbnailWidth, 140)
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 400).thumbnailWidth, 260)
    }

    func testDensityLabelReflectsThumbnailWidth() {
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 96).densityLabel, "Compact")
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 140).densityLabel, "Comfortable")
        XCTAssertEqual(LibraryGridLayout(thumbnailWidth: 220).densityLabel, "Large")
    }

    func testAccessibilityValueIncludesRoundedWidthAndDensity() {
        XCTAssertEqual(
            LibraryGridLayout(thumbnailWidth: 139.7).accessibilityValue,
            "140 px, Comfortable"
        )
    }
}
