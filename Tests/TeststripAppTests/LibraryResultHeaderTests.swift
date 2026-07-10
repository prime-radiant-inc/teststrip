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
        XCTAssertEqual(presentation.interpretation, "read as plain text: sunset")
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
