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

        XCTAssertTrue(label.contains("IMG_0412–0417"), "Should collapse numeric range")
        XCTAssertTrue(label.contains("6"), "Should include frame count")
        XCTAssertTrue(label.contains("·"), "Should use middle dot separator")
        // Verify it contains a time formatted via Date.FormatStyle
        let timeFormatted = firstTime.formatted(date: .omitted, time: .shortened)
        XCTAssertTrue(label.contains(timeFormatted), "Should include formatted time: \(timeFormatted)")
    }

    func testMixedStemsFallBackToFirstLast() {
        let firstTime = Date(timeIntervalSince1970: 2000)
        let assets = [
            Self.asset(filename: "IMG_0412.jpg", capturedAt: firstTime),
            Self.asset(filename: "R5A_0413.jpg", capturedAt: firstTime.addingTimeInterval(1)),
            Self.asset(filename: "R5A_0414.jpg", capturedAt: firstTime.addingTimeInterval(2))
        ]

        let label = CullStackLabelPresentation.label(for: assets)

        XCTAssertTrue(label.contains("IMG_0412…R5A_0414"), "Should use first…last for mixed stems")
        XCTAssertTrue(label.contains("3"), "Should include frame count")
    }

    func testNonNumericSuffixesFallBackToFirstLast() {
        let firstTime = Date(timeIntervalSince1970: 3000)
        let assets = [
            Self.asset(filename: "photo_a.jpg", capturedAt: firstTime),
            Self.asset(filename: "photo_b.jpg", capturedAt: firstTime.addingTimeInterval(1)),
            Self.asset(filename: "photo_c.jpg", capturedAt: firstTime.addingTimeInterval(2))
        ]

        let label = CullStackLabelPresentation.label(for: assets)

        XCTAssertTrue(label.contains("photo_a…photo_c"), "Should use first…last for non-numeric suffixes")
        XCTAssertTrue(label.contains("3"), "Should include frame count")
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

        XCTAssertTrue(label.contains("IMG_0430"), "Should include filename stem")
        let timeFormatted = time.formatted(date: .omitted, time: .shortened)
        XCTAssertTrue(label.contains(timeFormatted), "Should include formatted time")
        XCTAssertTrue(label.contains("·"), "Should use middle dot separator")
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
        let expectedTime = time.formatted(date: .omitted, time: .shortened)

        XCTAssertTrue(label.contains(expectedTime), "Should use Date.FormatStyle .shortened for time")
    }

    func testEmptyAssetListReturnsEmpty() {
        let label = CullStackLabelPresentation.label(for: [])

        XCTAssertEqual(label, "", "Should return empty string for empty asset list")
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
