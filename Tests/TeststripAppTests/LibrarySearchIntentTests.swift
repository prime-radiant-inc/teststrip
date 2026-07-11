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
        XCTAssertEqual(needsEvaluation.chips, ["Not analyzed yet", "Reject"])

        let noKeywords = LibrarySearchIntent.parse("no keywords")
        XCTAssertEqual(noKeywords.predicates, [.missingKeywords])
        XCTAssertEqual(noKeywords.chips, ["Needs Keywords"])

        let recognitionQueues = LibrarySearchIntent.parse("faces found ocr found likely issues provider failures xmp pending xmp conflicts")
        XCTAssertNil(recognitionQueues.residualText)
        XCTAssertEqual(recognitionQueues.predicates, [
            .evaluationKind(.faceCount),
            .evaluationKind(.ocrText),
            .likelyIssue,
            .evaluationFailure,
            .metadataSyncPending,
            .metadataSyncConflict
        ])
        XCTAssertEqual(recognitionQueues.chips, [
            "Faces Found",
            "OCR Found",
            "Likely Issues",
            "Analysis Failures",
            "XMP Pending",
            "XMP Conflicts"
        ])

        let aliases = LibrarySearchIntent.parse("people found text found")
        XCTAssertEqual(aliases.predicates, [
            .evaluationKind(.faceCount),
            .evaluationKind(.ocrText)
        ])
        XCTAssertEqual(aliases.chips, ["Faces Found", "OCR Found"])
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

    func testParsesExpressionSignalFieldTokens() {
        let eyesOpen = LibrarySearchIntent.parse("signal:eyesopen")
        XCTAssertEqual(eyesOpen.predicates, [.evaluationKind(.eyesOpen)])
        XCTAssertEqual(eyesOpen.chips, ["Signal: Eyes Open"])

        let smile = LibrarySearchIntent.parse("signal:smile")
        XCTAssertEqual(smile.predicates, [.evaluationKind(.smile)])

        let eyeSharpness = LibrarySearchIntent.parse("signal:eyesharpness")
        XCTAssertEqual(eyeSharpness.predicates, [.evaluationKind(.eyeSharpness)])
    }

    func testParsesQuotedFieldValuesAndImportBatch() {
        let intent = LibrarySearchIntent.parse(
            "folder:\"/Volumes/NAS/Wedding 2026\" keyword:\"New York\" import:import-42 \"quiet moments\""
        )

        XCTAssertEqual(intent.residualText, "quiet moments")
        XCTAssertEqual(intent.predicates, [
            .folderPrefix("/Volumes/NAS/Wedding 2026"),
            .keyword("New York"),
            .importBatch("import-42")
        ])
        XCTAssertEqual(intent.chips, [
            "Folder: Wedding 2026",
            "Keyword: New York",
            "Import: import-42"
        ])
        XCTAssertEqual(intent.nameParts, [
            "Wedding 2026",
            "New York",
            "Import import-42"
        ])
    }

    func testParsesPersonFilterTokens() {
        let intent = LibrarySearchIntent.parse("person:\"Anna Lee\" person:Ben ceremony")

        XCTAssertEqual(intent.residualText, "ceremony")
        XCTAssertEqual(intent.predicates, [
            .person("Anna Lee"),
            .person("Ben")
        ])
        XCTAssertEqual(intent.chips, [
            "Person: Anna Lee",
            "Person: Ben"
        ])
        XCTAssertEqual(intent.nameParts, [
            "Anna Lee",
            "Ben"
        ])
    }

    func testSearchFieldHelpDocumentsPersonIntersection() {
        XCTAssertTrue(LibrarySearchIntent.searchFieldHelp.contains("person:\"Name\""))
        XCTAssertTrue(LibrarySearchIntent.searchFieldHelp.contains("every"))
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
