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
}
