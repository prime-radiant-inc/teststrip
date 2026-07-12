import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class LibraryResultHeaderTests: XCTestCase {
    func testEmptyQueryHasNoInterpretation() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 42,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false
        )

        XCTAssertEqual(presentation.matchCount, 42)
        XCTAssertNil(presentation.interpretation)
    }

    func testStructuredOnlyQueryHasNoInterpretation() {
        // "rating:4" parses entirely into a structured predicate — nothing
        // plain-text remains, so there's nothing to "read as" free text.
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 5,
            librarySearchText: "rating:4",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertNil(presentation.interpretation)
    }

    func testTokenedQueryWithResidualTextProducesInterpretationAndCount() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 12,
            librarySearchText: "rating:4 sunset",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertEqual(presentation.matchCount, 12)
        // "rating:4" is a structured token, so the interpretation names it
        // alongside the residual plain text rather than hiding the split.
        XCTAssertEqual(presentation.interpretation, "read as Rating >= 4 + plain text \"sunset\"")
    }

    func testPlainTextOnlyQueryExplainsWhatIsBeingMatched() {
        // No structured tokens parsed at all — say what the search is doing
        // in user language, not parser language (persona-8: "read as plain
        // text" explained nothing).
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 3,
            librarySearchText: "sunset",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertEqual(presentation.interpretation, "No filter matched — searching file names and photo text for “sunset”")
    }

    func testUnquotedMultiWordTokenSplitExposesStructuredTokenAndResidual() {
        // "camera:SmokeCam 1" commits as a `camera:SmokeCam` token plus a
        // residual bare word "1" — the interpretation line must name both,
        // not just the residual, so the silent split is visible to the user.
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 8,
            librarySearchText: "camera:SmokeCam 1",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertEqual(presentation.interpretation, "read as Camera: SmokeCam + plain text \"1\"")
    }

    func testSaveActionsMapToTheThreeDistinctSaveSemantics() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 12,
            librarySearchText: "rating:4",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: true
        )

        XCTAssertEqual(presentation.saveActions, [.dynamicSearch, .frozenSnapshot, .manualSet])
    }

    func testSaveActionsOmitDisabledSemantics() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 0,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false
        )

        XCTAssertTrue(presentation.saveActions.isEmpty)
    }

    func testSuggestedTokensAbsorbReviewQueueAndSignalSuggestions() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 100,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false,
            reviewQueueCounts: [.fiveStars: 3, .needsKeywords: 4, .rejects: 2],
            evaluationKindSummaries: [
                CatalogEvaluationKindSummary(kind: .focus, assetCount: 7)
            ]
        )

        XCTAssertTrue(presentation.suggestedTokens.contains { $0.field == .rating })
        XCTAssertTrue(presentation.suggestedTokens.contains { $0.display == "Reject" })
        XCTAssertTrue(presentation.suggestedTokens.contains { $0.field == .needsKeywords })
        XCTAssertTrue(presentation.suggestedTokens.contains { $0.field == .signal })
    }

    // spec §2b: the chip/result row renders only when it has content (active
    // tokens, a residual-text interpretation, or save-worthy state) — no
    // empty second row for a default, filter-free, unselected library view.
    func testHasContentIsFalseWithNoInterpretationNoSuggestionsNoSaveActions() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 0,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false
        )

        XCTAssertTrue(presentation.suggestedTokens.isEmpty)
        XCTAssertNil(presentation.interpretation)
        XCTAssertTrue(presentation.saveActions.isEmpty)
        XCTAssertFalse(presentation.hasContent)
    }

    func testHasContentIsTrueWhenInterpretationPresent() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 3,
            librarySearchText: "sunset",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false
        )

        XCTAssertTrue(presentation.hasContent)
    }

    func testHasContentIsTrueWhenSuggestedTokensPresent() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 5,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false,
            reviewQueueCounts: [.fiveStars: 3]
        )

        XCTAssertFalse(presentation.suggestedTokens.isEmpty)
        XCTAssertTrue(presentation.hasContent)
    }

    func testHasContentIsTrueWhenSaveActionsPresent() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 5,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertTrue(presentation.hasContent)
    }

    func testSuggestedTokensOmitFieldsAlreadyActive() {
        let activeRatingToken = LibraryQueryToken(field: .rating, display: "Rating >= 5", value: .int(5))
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 3,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false,
            reviewQueueCounts: [.fiveStars: 3],
            activeTokens: [activeRatingToken]
        )

        XCTAssertFalse(presentation.suggestedTokens.contains { $0.field == .rating })
    }

    // persona-2 item 4: Ruth typed a search and had no idea whether anything
    // happened — the reload path is synchronous (no spinner needed), but a
    // zero-result search reads identically to "0 photos" in an unrelated
    // empty state unless it's called out explicitly.
    func testZeroMatchSearchIsFlaggedAsNoMatches() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 0,
            librarySearchText: "Grandma Rose",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false
        )

        XCTAssertTrue(presentation.isZeroMatchSearch)
        XCTAssertEqual(presentation.matchSummary, "No matches for \u{201c}Grandma Rose\u{201d}")
    }

    func testNonZeroMatchIsNotFlaggedAsNoMatches() {
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 3,
            librarySearchText: "sunset",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertFalse(presentation.isZeroMatchSearch)
        XCTAssertEqual(presentation.matchSummary, "3 photos")
    }

    func testEmptySearchWithNoMatchesIsNotFlaggedAsNoMatchSearch() {
        // A bare (no search text) catalog with 0 assets is an empty catalog,
        // not a failed search — don't claim "no matches for" nothing.
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 0,
            librarySearchText: "",
            canSaveDynamicSet: false,
            canSaveSnapshotSet: false,
            canSaveManualSet: false
        )

        XCTAssertFalse(presentation.isZeroMatchSearch)
        XCTAssertEqual(presentation.matchSummary, "0 photos")
    }
}
