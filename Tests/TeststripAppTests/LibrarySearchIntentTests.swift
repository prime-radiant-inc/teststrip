import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class LibrarySearchIntentTests: XCTestCase {
    func testParsesPhotographerFilterTermsAndKeepsResidualSearchText() {
        let intent = LibrarySearchIntent.parse("  ceremony PICKS 5 stars missing keywords camera:Canon lens:RF50 keyword:portfolio  ")

        XCTAssertEqual(intent.residualText, "ceremony")
        XCTAssertEqual(intent.predicates, [
            .flag(.pick),
            .ratingAtLeast(5),
            .missingKeywords,
            .camera("Canon"),
            .lens("RF50"),
            .keyword("portfolio")
        ])
        XCTAssertEqual(intent.chips, [
            "Pick",
            "Rating >= 5",
            "Needs Keywords",
            "Camera: Canon",
            "Lens: RF50",
            "Keyword: portfolio"
        ])
        XCTAssertEqual(intent.nameParts, [
            "Pick",
            "5+ Stars",
            "Needs Keywords",
            "Canon",
            "RF50",
            "portfolio"
        ])
    }

    func testLeavesUnsupportedNaturalLanguageAsPlainSearchText() {
        let intent = LibrarySearchIntent.parse("best group portraits")

        XCTAssertEqual(intent.residualText, "best group portraits")
        XCTAssertEqual(intent.predicates, [])
        XCTAssertEqual(intent.chips, [])
        XCTAssertEqual(intent.nameParts, [])
    }

    func testParsesReviewQueueTerms() {
        let needsEvaluation = LibrarySearchIntent.parse("unevaluated rejects")
        XCTAssertEqual(needsEvaluation.predicates, [.unevaluated, .flag(.reject)])
        XCTAssertEqual(needsEvaluation.chips, ["Needs Evaluation", "Reject"])

        let noKeywords = LibrarySearchIntent.parse("no keywords")
        XCTAssertEqual(noKeywords.predicates, [.missingKeywords])
        XCTAssertEqual(noKeywords.chips, ["Needs Keywords"])
    }

    func testParsesRatingFieldFilter() {
        let intent = LibrarySearchIntent.parse("rating:4 pick")

        XCTAssertNil(intent.residualText)
        XCTAssertEqual(intent.predicates, [.ratingAtLeast(4), .flag(.pick)])
        XCTAssertEqual(intent.chips, ["Rating >= 4", "Pick"])
        XCTAssertEqual(intent.nameParts, ["4+ Stars", "Pick"])
    }

    func testParsesAdvancedFilterFields() {
        let start = Self.utcDate(year: 2026, month: 2, day: 1)
        let end = Self.utcDate(year: 2026, month: 3, day: 1)

        let intent = LibrarySearchIntent.parse(
            "folder:/Volumes/NAS/Wedding color:green iso:800 from:2026-02-01 before:2026-03-01 source:offline signal:focus xmp:pending session:cull-42"
        )

        XCTAssertNil(intent.residualText)
        XCTAssertEqual(intent.predicates, [
            .folderPrefix("/Volumes/NAS/Wedding"),
            .colorLabel(.green),
            .isoAtLeast(800),
            .capturedAtOrAfter(start),
            .capturedBefore(end),
            .availability(.offline),
            .evaluationKind(.focus),
            .metadataSyncPending,
            .workSession("cull-42")
        ])
        XCTAssertEqual(intent.chips, [
            "Folder: Wedding",
            "Green Label",
            "ISO >= 800",
            "From 2026-02-01",
            "Before 2026-03-01",
            "Source: Offline",
            "Signal: Focus",
            "XMP Pending",
            "Session: cull-42"
        ])
        XCTAssertEqual(intent.nameParts, [
            "Wedding",
            "Green Label",
            "ISO 800+",
            "From 2026-02-01",
            "Before 2026-03-01",
            "Offline",
            "Focus",
            "XMP Pending",
            "Session cull-42"
        ])
    }

    func testParsesDateFieldAsSingleCaptureDay() {
        let start = Self.utcDate(year: 2026, month: 2, day: 4)
        let nextDay = Self.utcDate(year: 2026, month: 2, day: 5)

        let intent = LibrarySearchIntent.parse("date:2026-02-04")

        XCTAssertEqual(intent.predicates, [
            .capturedAtOrAfter(start),
            .capturedBefore(nextDay)
        ])
        XCTAssertEqual(intent.chips, ["Date: 2026-02-04"])
        XCTAssertEqual(intent.nameParts, ["2026-02-04"])
    }

    func testParsesGreaterThanOrEqualFieldSeparatorAndLeavesInvalidFieldsAsSearchText() {
        let intent = LibrarySearchIntent.parse("iso>=1600 date:2026-02-31 color:ultraviolet")

        XCTAssertEqual(intent.residualText, "date:2026-02-31 color:ultraviolet")
        XCTAssertEqual(intent.predicates, [.isoAtLeast(1600)])
        XCTAssertEqual(intent.chips, ["ISO >= 1600"])
        XCTAssertEqual(intent.nameParts, ["ISO 1600+"])
    }

    private static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
