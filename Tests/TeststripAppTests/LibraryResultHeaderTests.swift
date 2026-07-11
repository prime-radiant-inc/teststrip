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

    func testPlainTextOnlyQueryReadsAsPlainTextWithoutTokenPrefix() {
        // No structured tokens parsed at all — the original, simpler phrasing.
        let presentation = LibraryResultHeaderPresentation(
            totalAssetCount: 3,
            librarySearchText: "sunset",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true,
            canSaveManualSet: false
        )

        XCTAssertEqual(presentation.interpretation, "read as plain text: sunset")
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
}
