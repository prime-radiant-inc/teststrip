import XCTest
import TeststripCore
@testable import TeststripApp

final class LibraryGridChromeTests: XCTestCase {
    func testImportProgressBannerShowsBeforeAssetsAreVisible() {
        XCTAssertTrue(LibraryGridChromePolicy.shouldShowImportProgressBanner(
            isImporting: true,
            visibleAssetCount: 0
        ))
    }

    func testImportProgressBannerHidesWhenImportIsInactive() {
        XCTAssertFalse(LibraryGridChromePolicy.shouldShowImportProgressBanner(
            isImporting: false,
            visibleAssetCount: 12
        ))
    }

    func testAutopilotBadgeMapsKindToKeepOrCut() {
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .pick)?.text, "KEEP")
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .pick)?.isKeep, true)
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .reject)?.text, "CUT")
        XCTAssertEqual(AutopilotBadgePresentation.badge(for: .reject)?.isKeep, false)
        XCTAssertNil(AutopilotBadgePresentation.badge(for: .keyword))
        XCTAssertNil(AutopilotBadgePresentation.badge(for: nil))
    }

    func testImportCompletionSummaryShowsOnlyAfterImportFinishes() {
        XCTAssertTrue(LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: false,
            summaryID: "import-1",
            dismissedSummaryID: nil
        ))

        XCTAssertFalse(LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: true,
            summaryID: "import-1",
            dismissedSummaryID: nil
        ))
    }

    func testImportCompletionSummaryHidesAfterDismissal() {
        XCTAssertFalse(LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: false,
            summaryID: "import-1",
            dismissedSummaryID: "import-1"
        ))
    }

    func testPendingMetadataSyncRetryActionShowsOnlyForPendingFilter() {
        XCTAssertTrue(LibraryGridChromePolicy.shouldShowPendingMetadataSyncRetryAction(
            isPendingFilterActive: true
        ))
        XCTAssertFalse(LibraryGridChromePolicy.shouldShowPendingMetadataSyncRetryAction(
            isPendingFilterActive: false
        ))
    }

    func testPendingMetadataSyncRetryActionDisablesDuringImportOrWithoutRetryableWork() {
        XCTAssertFalse(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
            isImporting: false,
            canRetry: true
        ))
        XCTAssertTrue(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
            isImporting: true,
            canRetry: true
        ))
        XCTAssertTrue(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
            isImporting: false,
            canRetry: false
        ))
    }

    func testPrimaryCardImportUsesUserGrantedPanelRoute() {
        XCTAssertEqual(LibraryGridChromePolicy.primaryCardImportRoute, .userGrantedPanel)
    }

    func testPrimaryCardImportRouteCanUseTypedPathForAutomationOverride() {
        XCTAssertEqual(
            LibraryGridChromePolicy.primaryCardImportRoute(environment: [
                "TESTSTRIP_CARD_IMPORT_ROUTE": "typed-path"
            ]),
            .typedPathSheet
        )
        XCTAssertEqual(
            LibraryGridChromePolicy.primaryCardImportRoute(environment: [
                "TESTSTRIP_CARD_IMPORT_ROUTE": "panel"
            ]),
            .userGrantedPanel
        )
        XCTAssertEqual(
            LibraryGridChromePolicy.primaryCardImportRoute(environment: [
                "TESTSTRIP_CARD_IMPORT_ROUTE": "unexpected"
            ]),
            .userGrantedPanel
        )
    }

    func testRejectDestinationOverrideUsesEnvironmentPathWhenSet() {
        let override = LibraryGridChromePolicy.rejectDestinationDirectoryOverride(environment: [
            "TESTSTRIP_REJECT_DESTINATION_DIR": "/tmp/reject-target"
        ])
        XCTAssertEqual(override?.path, "/tmp/reject-target")
    }

    func testRejectDestinationOverrideIsNilWhenEnvironmentUnset() {
        XCTAssertNil(LibraryGridChromePolicy.rejectDestinationDirectoryOverride(environment: [:]))
        XCTAssertNil(LibraryGridChromePolicy.rejectDestinationDirectoryOverride(environment: [
            "TESTSTRIP_REJECT_DESTINATION_DIR": "   "
        ]))
    }

    func testExportDestinationOverrideUsesEnvironmentPathWhenSet() {
        let override = LibraryGridChromePolicy.exportDestinationDirectoryOverride(environment: [
            "TESTSTRIP_EXPORT_DESTINATION_DIR": "/tmp/export-target"
        ])
        XCTAssertEqual(override?.path, "/tmp/export-target")
    }

    func testExportDestinationOverrideIsNilWhenEnvironmentUnset() {
        XCTAssertNil(LibraryGridChromePolicy.exportDestinationDirectoryOverride(environment: [:]))
    }

    func testLibrarySortPresentationExposesImportCaptureTimeAndFilenameOptions() {
        let options = LibrarySortOptionPresentation.options(selected: .captureTimeNewestFirst)

        XCTAssertEqual(options.map(\.title), [
            "Import Order",
            "Capture Time",
            "Capture Time",
            "Filename"
        ])
        XCTAssertEqual(options.map(\.subtitle), [
            "Oldest import first",
            "Newest first",
            "Oldest first",
            "A to Z"
        ])
        XCTAssertEqual(options.map(\.option), [
            .importOrder,
            .captureTimeNewestFirst,
            .captureTimeOldestFirst,
            .filename
        ])
        XCTAssertEqual(options.map(\.isSelected), [false, true, false, false])
    }

    func testMetadataSyncFilterOptionMapsPendingAndConflictFlags() {
        XCTAssertEqual(MetadataSyncFilterOption(pending: false, conflict: false), .any)
        XCTAssertEqual(MetadataSyncFilterOption(pending: true, conflict: false), .pending)
        XCTAssertEqual(MetadataSyncFilterOption(pending: false, conflict: true), .conflicts)
        XCTAssertEqual(MetadataSyncFilterOption(pending: true, conflict: true), .conflicts)
        XCTAssertEqual(MetadataSyncFilterOption.pending.pendingFilter, true)
        XCTAssertEqual(MetadataSyncFilterOption.pending.conflictFilter, false)
        XCTAssertEqual(MetadataSyncFilterOption.conflicts.pendingFilter, false)
        XCTAssertEqual(MetadataSyncFilterOption.conflicts.conflictFilter, true)
    }

    func testBatchKeywordSuggestionPresentationBuildsCurrentScopeActionsFromTopSuggestions() {
        let rows = BatchKeywordSuggestionPresentation.rows(
            for: [
                BatchKeywordSuggestion(
                    keyword: "mountain",
                    assetCount: 2,
                    averageConfidence: 0.7,
                    providerName: "apple-vision",
                    modelName: "Vision"
                ),
                BatchKeywordSuggestion(
                    keyword: "lake",
                    assetCount: 1,
                    averageConfidence: 0.91,
                    providerName: "local-http-model",
                    modelName: "llava"
                ),
                BatchKeywordSuggestion(
                    keyword: "forest",
                    assetCount: 1,
                    averageConfidence: 0.62,
                    providerName: "apple-vision",
                    modelName: "Vision"
                )
            ],
            limit: 2
        )

        XCTAssertEqual(rows.map(\.keyword), ["mountain", "lake"])
        XCTAssertEqual(rows.map(\.title), ["Apply mountain", "Apply lake"])
        XCTAssertEqual(rows.map(\.detail), ["2 photos at 70%", "1 photo at 91%"])
        XCTAssertEqual(rows.map(\.isEnabled), [true, true])
        XCTAssertTrue(rows.allSatisfy { $0.placeholder == nil })
    }

    func testBatchKeywordSuggestionPresentationHidesWhenNoSuggestionsExist() {
        XCTAssertEqual(BatchKeywordSuggestionPresentation.rows(for: []), [])
    }

    func testCullingDecisionFeedbackPresentationNamesChangedFrameAndDecision() {
        let presentation = CullingDecisionFeedbackPresentation(
            feedback: CullingMetadataDecisionFeedback(
                assetID: AssetID(rawValue: "rated"),
                filename: "frame-0.dng",
                decisionText: "Rated 5"
            )
        )

        XCTAssertEqual(presentation.title, "Rated 5")
        XCTAssertEqual(presentation.detail, "frame-0.dng")
        XCTAssertEqual(presentation.accessibilityValue, "Rated 5, frame-0.dng")
    }

    func testBatchMetadataReviewPresentationSummarizesVisibleBatchAndDraft() {
        var draft = BatchMetadataDraft()
        draft.caption = "  Patagonia selects  "

        let presentation = BatchMetadataReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 121,
            selectedScope: .visible,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            suggestions: [
                BatchKeywordSuggestion(
                    keyword: "mountain",
                    assetCount: 5,
                    averageConfidence: 0.84,
                    providerName: "apple-vision",
                    modelName: "Vision"
                )
            ],
            draft: draft
        )

        XCTAssertEqual(presentation.countText, "12 visible photos")
        XCTAssertEqual(presentation.suggestionRows.map(\.keyword), ["mountain"])
        XCTAssertTrue(presentation.isApplyEnabled)
        XCTAssertEqual(presentation.applyTitle, "Apply to visible batch")
    }

    func testBatchMetadataReviewPresentationSummarizesSelectedBatch() {
        var draft = BatchMetadataDraft()
        draft.keywords = "keepers, Portfolio, keepers"

        let presentation = BatchMetadataReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 2,
            currentScopeAssetCount: 121,
            selectedScope: .selected,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            suggestions: [
                BatchKeywordSuggestion(
                    keyword: "mountain",
                    assetCount: 5,
                    averageConfidence: 0.84,
                    providerName: "apple-vision",
                    modelName: "Vision"
                )
            ],
            draft: draft
        )

        XCTAssertEqual(presentation.countText, "2 selected photos")
        XCTAssertEqual(presentation.suggestionRows.map(\.keyword), ["mountain"])
        XCTAssertTrue(presentation.isApplyEnabled)
        XCTAssertEqual(presentation.applyTitle, "Apply to selected batch")
        XCTAssertNil(presentation.confirmationText)
        XCTAssertEqual(presentation.draftKeywordChips, ["keepers", "Portfolio"])
        XCTAssertEqual(presentation.draftKeywordCountText, "2 keywords to add")
    }

    func testBatchMetadataReviewPresentationHidesDraftKeywordReviewWhenNoKeywordsAreTyped() {
        var draft = BatchMetadataDraft()
        draft.caption = "Portfolio selects"

        let presentation = BatchMetadataReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 2,
            currentScopeAssetCount: 121,
            selectedScope: .selected,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            suggestions: [],
            draft: draft
        )

        XCTAssertEqual(presentation.draftKeywordChips, [])
        XCTAssertNil(presentation.draftKeywordCountText)
    }

    func testBatchMetadataReviewPresentationSummarizesCurrentScopeAndShowsScopeSuggestions() {
        var draft = BatchMetadataDraft()
        draft.keywords = "portfolio"

        let presentation = BatchMetadataReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 121,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            suggestions: [
                BatchKeywordSuggestion(
                    keyword: "mountain",
                    assetCount: 5,
                    averageConfidence: 0.84,
                    providerName: "apple-vision",
                    modelName: "Vision"
                )
            ],
            draft: draft
        )

        XCTAssertEqual(presentation.countText, "121 photos in current scope")
        XCTAssertEqual(presentation.suggestionRows.map(\.keyword), ["mountain"])
        XCTAssertTrue(presentation.isApplyEnabled)
        XCTAssertEqual(presentation.applyTitle, "Apply to current scope")
    }

    func testBatchMetadataReviewPresentationRequiresConfirmationForAllCatalogScope() {
        var draft = BatchMetadataDraft()
        draft.creator = "Jesse"

        let unconfirmed = BatchMetadataReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 121,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: true,
            isAllCatalogConfirmed: false,
            suggestions: [],
            draft: draft
        )
        let confirmed = BatchMetadataReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 121,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: true,
            isAllCatalogConfirmed: true,
            suggestions: [],
            draft: draft
        )

        XCTAssertEqual(unconfirmed.confirmationText, "Confirm applying metadata to all 121 catalog photos.")
        XCTAssertFalse(unconfirmed.isApplyEnabled)
        XCTAssertTrue(confirmed.isApplyEnabled)
    }

    func testBatchMetadataDraftAppendsSuggestedKeywordsWithoutDuplicates() {
        var draft = BatchMetadataDraft(keywords: "Mountain, alpine lake")

        draft.appendKeyword(" mountain ")
        draft.appendKeyword("forest")

        XCTAssertEqual(draft.keywords, "Mountain, alpine lake, forest")
    }
}
