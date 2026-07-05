import XCTest
import TeststripCore
@testable import TeststripApp

final class TimelinePresentationTests: XCTestCase {
    func testGroupsLoadedAssetsByCaptureMonthAndDayNewestFirst() {
        let calendar = Self.gregorianUTC
        let newest = Self.asset(id: "newest", capturedAt: Self.date(year: 2026, month: 2, day: 4, hour: 15, calendar: calendar))
        let sameDay = Self.asset(id: "same-day", capturedAt: Self.date(year: 2026, month: 2, day: 4, hour: 9, calendar: calendar))
        let previousMonth = Self.asset(id: "previous-month", capturedAt: Self.date(year: 2026, month: 1, day: 12, calendar: calendar))
        let undated = Self.asset(id: "undated", capturedAt: nil)

        let presentation = TimelinePresentation(
            assets: [previousMonth, undated, sameDay, newest],
            totalAssetCount: 10,
            calendar: calendar
        )

        XCTAssertEqual(presentation.summaryText, "Showing 4 loaded of 10 photographs across 2 days")
        XCTAssertEqual(presentation.months.map(\.title), ["February 2026", "January 2026", "No Capture Date"])
        XCTAssertEqual(presentation.months[0].subtitle, "2 photographs across 1 day")
        XCTAssertEqual(presentation.months[0].days.map(\.title), ["February 4"])
        XCTAssertEqual(presentation.months[0].days[0].countText, "2 frames")
        XCTAssertEqual(presentation.months[0].days[0].assets.map(\.id), [newest.id, sameDay.id])
        XCTAssertEqual(presentation.months[2].days.map(\.title), ["Undated"])
        XCTAssertEqual(presentation.months[2].days[0].assets.map(\.id), [undated.id])
    }

    func testSummaryTextForFullyLoadedCatalog() {
        let asset = Self.asset(id: "only", capturedAt: nil)

        let presentation = TimelinePresentation(assets: [asset], totalAssetCount: 1, calendar: Self.gregorianUTC)

        XCTAssertEqual(presentation.summaryText, "1 photograph without capture dates")
    }

    func testUsesCatalogTimelineDayCountsAndLoadedAssetsSeparately() {
        let calendar = Self.gregorianUTC
        let loaded = Self.asset(id: "loaded", capturedAt: Self.date(year: 2026, month: 2, day: 4, calendar: calendar))
        let presentation = TimelinePresentation(
            timelineDays: [
                CatalogTimelineDay(year: 2026, month: 2, day: 5, assetCount: 8),
                CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 3)
            ],
            loadedAssets: [loaded],
            totalAssetCount: 11,
            calendar: calendar
        )

        XCTAssertEqual(presentation.summaryText, "Showing 1 loaded of 11 photographs across 2 days")
        XCTAssertEqual(presentation.months.map(\.title), ["February 2026"])
        XCTAssertEqual(presentation.months[0].year, 2026)
        XCTAssertEqual(presentation.months[0].month, 2)
        XCTAssertEqual(presentation.months[0].subtitle, "11 photographs across 2 days")
        XCTAssertEqual(presentation.months[0].days.map(\.title), ["February 5", "February 4"])
        XCTAssertEqual(presentation.months[0].days.map(\.countText), ["8 frames", "3 frames"])
        XCTAssertEqual(presentation.months[0].days[0].assets, [])
        XCTAssertEqual(presentation.months[0].days[1].assets.map(\.id), [loaded.id])
        XCTAssertEqual(presentation.months[0].days[1].timelineDay, CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 3))
    }

    func testBuildsYearDensityRibbonFromCatalogTimelineDays() {
        let calendar = Self.gregorianUTC
        let focused = Self.asset(id: "focused", capturedAt: Self.date(year: 2022, month: 5, day: 4, calendar: calendar))
        let presentation = TimelinePresentation(
            timelineDays: [
                CatalogTimelineDay(year: 2022, month: 5, day: 4, assetCount: 30),
                CatalogTimelineDay(year: 2020, month: 11, day: 12, assetCount: 10)
            ],
            loadedAssets: [focused],
            totalAssetCount: 40,
            calendar: calendar
        )

        XCTAssertEqual(presentation.yearRibbon.rangeText, "2020 - 2022")
        XCTAssertEqual(presentation.yearRibbon.summaryText, "40 photographs - 3 years")
        XCTAssertEqual(presentation.yearRibbon.years.map(\.year), [2020, 2021, 2022])
        XCTAssertEqual(presentation.yearRibbon.years.map(\.assetCount), [10, 0, 30])
        XCTAssertEqual(presentation.yearRibbon.years.map(\.tickText), ["2020", "", ""])
        XCTAssertEqual(presentation.yearRibbon.years.map(\.isFocused), [false, false, true])
        XCTAssertEqual(presentation.yearRibbon.years.map(\.heightRatio), [1.0 / 3.0, 0, 1.0])
        XCTAssertEqual(presentation.yearRibbon.focusText, "2022 - 30")
    }

    func testBuildsMonthAndDayScrubberFromCatalogTimelineDays() {
        let calendar = Self.gregorianUTC
        let focused = Self.asset(id: "focused", capturedAt: Self.date(year: 2026, month: 2, day: 4, calendar: calendar))
        let presentation = TimelinePresentation(
            timelineDays: [
                CatalogTimelineDay(year: 2026, month: 3, day: 1, assetCount: 9),
                CatalogTimelineDay(year: 2026, month: 2, day: 5, assetCount: 8),
                CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 3),
                CatalogTimelineDay(year: 2026, month: 1, day: 12, assetCount: 2)
            ],
            loadedAssets: [focused],
            totalAssetCount: 22,
            calendar: calendar
        )

        XCTAssertEqual(presentation.scrubber.months.map(\.title), ["March 2026", "February 2026", "January 2026"])
        XCTAssertEqual(presentation.scrubber.months.map(\.countText), ["9 photos / 1 day", "11 photos / 2 days", "2 photos / 1 day"])
        XCTAssertEqual(presentation.scrubber.months.map(\.isFocused), [false, true, false])
        XCTAssertEqual(presentation.scrubber.months[1].year, 2026)
        XCTAssertEqual(presentation.scrubber.months[1].month, 2)
        XCTAssertEqual(presentation.scrubber.days.map(\.title), ["February 5", "February 4"])
        XCTAssertEqual(presentation.scrubber.days.map(\.countText), ["8", "3"])
        XCTAssertEqual(presentation.scrubber.days[1].timelineDay, CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 3))
    }

    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        date(year: year, month: month, day: day, hour: 12, calendar: calendar)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func asset(id: String, capturedAt: Date?) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 4000,
                pixelHeight: 3000,
                capturedAt: capturedAt,
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        )
    }
}
