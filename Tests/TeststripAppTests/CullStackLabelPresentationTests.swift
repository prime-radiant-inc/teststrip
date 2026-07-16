import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class CullStackLabelPresentationTests: XCTestCase {
    func testMultiFrameNumericRangeCollapseWithTime() {
        let firstTime = Date(timeIntervalSince1970: 1000)
        let assets = [
            Self.asset(filename: "IMG_0412.jpg", capturedAt: firstTime),
            Self.asset(filename: "IMG_0413.jpg", capturedAt: firstTime.addingTimeInterval(1)),
            Self.asset(filename: "IMG_0414.jpg", capturedAt: firstTime.addingTimeInterval(2)),
            Self.asset(filename: "IMG_0415.jpg", capturedAt: firstTime.addingTimeInterval(3)),
            Self.asset(filename: "IMG_0416.jpg", capturedAt: firstTime.addingTimeInterval(4)),
            Self.asset(filename: "IMG_0417.jpg", capturedAt: firstTime.addingTimeInterval(5))
        ]

        let label = CullStackLabelPresentation.label(for: assets)
        let timeFormatted = firstTime.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "IMG_0412–0417 · 6 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should collapse numeric range with count and time")
    }

    func testMixedStemsFallBackToFirstLast() {
        let firstTime = Date(timeIntervalSince1970: 2000)
        let assets = [
            Self.asset(filename: "IMG_0412.jpg", capturedAt: firstTime),
            Self.asset(filename: "R5A_0413.jpg", capturedAt: firstTime.addingTimeInterval(1)),
            Self.asset(filename: "R5A_0414.jpg", capturedAt: firstTime.addingTimeInterval(2))
        ]

        let label = CullStackLabelPresentation.label(for: assets)
        let timeFormatted = firstTime.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "IMG_0412…R5A_0414 · 3 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should use first…last for mixed stems with count and time")
    }

    func testNonNumericSuffixesFallBackToFirstLast() {
        let firstTime = Date(timeIntervalSince1970: 3000)
        let assets = [
            Self.asset(filename: "photo_a.jpg", capturedAt: firstTime),
            Self.asset(filename: "photo_b.jpg", capturedAt: firstTime.addingTimeInterval(1)),
            Self.asset(filename: "photo_c.jpg", capturedAt: firstTime.addingTimeInterval(2))
        ]

        let label = CullStackLabelPresentation.label(for: assets)
        let timeFormatted = firstTime.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "photo_a…photo_c · 3 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should use first…last for non-numeric suffixes with count and time")
    }

    func testMissingCapturedAtOmitsTimeSegment() {
        let assets = [
            Self.asset(filename: "IMG_0412.jpg", capturedAt: nil),
            Self.asset(filename: "IMG_0413.jpg", capturedAt: nil),
            Self.asset(filename: "IMG_0414.jpg", capturedAt: nil)
        ]

        let label = CullStackLabelPresentation.label(for: assets)

        XCTAssertTrue(label.contains("IMG_0412–0414"), "Should include file range")
        XCTAssertTrue(label.contains("3"), "Should include frame count")
        // Verify no trailing separator or orphaned time segment
        XCTAssertFalse(label.hasSuffix("·"), "Should not have trailing separator")
        XCTAssertEqual(label, "IMG_0412–0414 · 3", "Should end with count, no time")
    }

    func testSingleAssetStandaloneLabel() {
        let time = Date(timeIntervalSince1970: 4000)
        let asset = Self.asset(filename: "IMG_0430.jpg", capturedAt: time)

        let label = CullStackLabelPresentation.standaloneLabel(for: asset)
        let timeFormatted = time.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "IMG_0430 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should format single asset with stem and time")
    }

    func testSingleAssetWithoutTimeStandalone() {
        let asset = Self.asset(filename: "IMG_0430.jpg", capturedAt: nil)

        let label = CullStackLabelPresentation.standaloneLabel(for: asset)

        XCTAssertEqual(label, "IMG_0430", "Should be just the stem with no time")
    }

    func testTimeFormattingUsesDateFormatStyle() {
        let time = Date(timeIntervalSince1970: 5000)
        let asset = Self.asset(filename: "IMG_0440.jpg", capturedAt: time)

        let label = CullStackLabelPresentation.standaloneLabel(for: asset)
        let timeFormatted = time.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "IMG_0440 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should use Date.FormatStyle .shortened for time")
    }

    func testEmptyAssetListReturnsEmpty() {
        let label = CullStackLabelPresentation.label(for: [])

        XCTAssertEqual(label, "", "Should return empty string for empty asset list")
    }

    func testIdenticalStemReturnsJustStem() {
        let firstTime = Date(timeIntervalSince1970: 6000)
        let assets = [
            Self.asset(filename: "IMG_0412.jpg", capturedAt: firstTime),
            Self.asset(filename: "IMG_0412.jpg", capturedAt: firstTime.addingTimeInterval(1))
        ]

        let label = CullStackLabelPresentation.label(for: assets)
        let timeFormatted = firstTime.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "IMG_0412 · 2 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should return just stem when first and last are identical")
    }

    func testDigitWidthRolloverIMG0999to1000() {
        let firstTime = Date(timeIntervalSince1970: 7000)
        let assets = [
            Self.asset(filename: "IMG_0999.jpg", capturedAt: firstTime),
            Self.asset(filename: "IMG_1000.jpg", capturedAt: firstTime.addingTimeInterval(1))
        ]

        let label = CullStackLabelPresentation.label(for: assets)
        let timeFormatted = firstTime.formatted(date: .omitted, time: .shortened)
        let expectedLabel = "IMG_0999–1000 · 2 · \(timeFormatted)"

        XCTAssertEqual(label, expectedLabel, "Should collapse digit-width rollover correctly")
    }

    // MARK: - Fixture helpers

    private static func asset(filename: String, capturedAt: Date?) -> Asset {
        Asset(
            id: AssetID(rawValue: UUID().uuidString),
            originalURL: URL(fileURLWithPath: "/Photos/\(filename)"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: capturedAt.map { date in
                AssetTechnicalMetadata(
                    pixelWidth: 6000,
                    pixelHeight: 4000,
                    capturedAt: date,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            }
        )
    }
}
