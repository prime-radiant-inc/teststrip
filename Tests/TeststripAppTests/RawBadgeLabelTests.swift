import XCTest
@testable import TeststripApp

final class RawBadgeLabelTests: XCTestCase {
    func testRawPrimaryWithBondedStillReadsRawPlusJPEG() {
        XCTAssertEqual(RawBadgeLabel.text(isRaw: true, hasBondedStill: true), "RAW+JPEG")
    }

    func testRawPrimaryWithoutBondedStillReadsRaw() {
        XCTAssertEqual(RawBadgeLabel.text(isRaw: true, hasBondedStill: false), "RAW")
    }

    func testNonRawAssetRendersNoBadge() {
        XCTAssertNil(RawBadgeLabel.text(isRaw: false, hasBondedStill: false))
    }
}
