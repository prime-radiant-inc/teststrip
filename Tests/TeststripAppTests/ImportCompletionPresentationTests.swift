import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class ImportCompletionPresentationTests: XCTestCase {
    func testBuildsPayoffRowsFromCompletedImportSummary() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 12,
            photoCountText: "12 photos",
            newPhotoCount: 12,
            existingPhotoCount: 0,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "Previews ready",
            stackCount: 3,
            stackedPhotoCount: 8
        ))

        XCTAssertEqual(presentation.title, "12 photos imported")
        XCTAssertEqual(presentation.detail, "Imported 12 photos from Card A")
        XCTAssertEqual(presentation.metricRows.map(\.label), ["Imported set", "Previews", "Cull scope"])
        XCTAssertEqual(presentation.metricRows.map(\.value), ["12 photos", "Ready", "3 stacks"])
        XCTAssertEqual(presentation.enabledActions.map(\.kind), [.startCulling, .reviewImportedFrames, .openInLibrary, .stackGrouping])
        XCTAssertEqual(presentation.placeholderActions.map(\.kind), [])
    }

    func testSurfacesPreviewFailuresWithoutBlockingImportActions() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 4,
            photoCountText: "4 photos",
            newPhotoCount: 4,
            existingPhotoCount: 0,
            previewFailureCount: 2,
            failureText: "2 preview failures",
            previewStatusText: "2 preview failures",
            stackCount: 1,
            stackedPhotoCount: 3
        ))

        XCTAssertEqual(presentation.metricRows.first { $0.id == "previews" }?.value, "2 issues")
        XCTAssertEqual(presentation.metricRows.first { $0.id == "previews" }?.detail, "2 preview failures")
        XCTAssertEqual(presentation.enabledActions.map(\.kind), [.startCulling, .reviewImportedFrames, .openInLibrary, .stackGrouping])
    }

    func testExistingOnlyImportDoesNotClaimNewPhotos() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 1,
            photoCountText: "1 photo",
            newPhotoCount: 0,
            existingPhotoCount: 1,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "No previews needed"
        ))

        XCTAssertEqual(presentation.title, "No new photos imported")
        XCTAssertEqual(presentation.metricRows.first?.value, "1 photo already in catalog")
        XCTAssertEqual(presentation.metricRows.first?.label, "Matched set")
    }

    func testExistingOnlyImportActionsNameMatchedSet() throws {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 2,
            photoCountText: "2 photos",
            newPhotoCount: 0,
            existingPhotoCount: 2,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "No previews needed"
        ))

        let reviewAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .reviewImportedFrames })
        XCTAssertEqual(reviewAction.title, "Review matched frames")
        XCTAssertEqual(reviewAction.detail, "Manual Compare over already-cataloged photos")

        let openAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .openInLibrary })
        XCTAssertEqual(openAction.title, "Open matched set")
        XCTAssertEqual(openAction.detail, "Browse already-cataloged photos")

        let cullScopeMetric = try XCTUnwrap(presentation.metricRows.first { $0.id == "cull-scope" })
        XCTAssertEqual(cullScopeMetric.detail, "Uses the matched set")
    }

    func testEmptyImportShowsTerminalResultWithoutImportedSetActions() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 0,
            photoCountText: "0 photos",
            newPhotoCount: 0,
            existingPhotoCount: 0,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "No previews needed"
        ))

        XCTAssertEqual(presentation.title, "No photos imported")
        XCTAssertEqual(presentation.metricRows.first?.value, "0 photos")
        XCTAssertEqual(presentation.metricRows.first?.label, "Import result")
        XCTAssertEqual(presentation.metricRows.first?.detail, "Nothing was added")
        XCTAssertEqual(presentation.metricRows.first { $0.id == "previews" }?.value, "Not needed")
        XCTAssertEqual(presentation.metricRows.first { $0.id == "cull-scope" }?.value, "Unavailable")
        XCTAssertNil(presentation.actionRows.first { $0.kind == .startCulling })
        XCTAssertNil(presentation.actionRows.first { $0.kind == .reviewImportedFrames })
        XCTAssertNil(presentation.actionRows.first { $0.kind == .openInLibrary })
        XCTAssertNil(presentation.actionRows.first { $0.kind == .evaluateImport })
        XCTAssertNil(presentation.actionRows.first { $0.kind == .stackGrouping })
        XCTAssertFalse(presentation.enabledActions.contains { action in
            action.kind == .startCulling || action.kind == .reviewImportedFrames || action.kind == .openInLibrary
        })
    }

    func testAddsManualCompareAndStackCullActionsWithoutClaimingSimilarityGrouping() throws {
        let presentation = ImportCompletionPresentation.presentation(for: summary(stackCount: 2, stackedPhotoCount: 5))

        let compareAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .reviewImportedFrames })
        XCTAssertTrue(compareAction.isEnabled)
        XCTAssertEqual(compareAction.title, "Review imported frames")
        XCTAssertEqual(compareAction.detail, "Manual Compare over this import")
        XCTAssertNil(compareAction.placeholder)

        let stackAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .stackGrouping })
        XCTAssertTrue(stackAction.isEnabled)
        XCTAssertEqual(stackAction.title, "Cull stacks")
        XCTAssertEqual(stackAction.detail, "2 stacks · 5 photos")
        XCTAssertNil(stackAction.placeholder)
    }

    func testDisablesStackCullActionWhenNoStacksAreDetected() throws {
        let presentation = ImportCompletionPresentation.presentation(for: summary(stackCount: 0, stackedPhotoCount: 0))

        let stackAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .stackGrouping })
        XCTAssertFalse(stackAction.isEnabled)
        XCTAssertEqual(stackAction.detail, "No time-adjacent stacks")
        XCTAssertNil(stackAction.placeholder)
        XCTAssertFalse(presentation.enabledActions.contains { $0.kind == .stackGrouping })
    }

    func testOpenImportActionNamesImportedSetInsteadOfWholeLibrary() throws {
        let presentation = ImportCompletionPresentation.presentation(for: summary())

        let openAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .openInLibrary })
        XCTAssertTrue(openAction.isEnabled)
        XCTAssertEqual(openAction.title, "Open imported set")
        XCTAssertEqual(openAction.detail, "Browse this import")
        XCTAssertNil(openAction.placeholder)
    }

    func testEvaluateImportActionIsEnabledWhenLatestImportCanBeEvaluated() throws {
        let presentation = ImportCompletionPresentation.presentation(
            for: summary(),
            canEvaluateImport: true
        )

        let action = try XCTUnwrap(presentation.actionRows.first { $0.kind == .evaluateImport })
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.title, "Evaluate import")
        XCTAssertEqual(action.detail, "Run local reads on this import")
        XCTAssertNil(action.placeholder)
    }

    func testEnablesFlaggedReviewActionWhenLatestImportHasReviewCandidates() throws {
        let presentation = ImportCompletionPresentation.presentation(
            for: summary(),
            flaggedReviewAssetCount: 3
        )

        let action = try XCTUnwrap(presentation.actionRows.first { $0.kind == .reviewFlaggedFrames })
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.title, "Review 3 flagged")
        XCTAssertEqual(action.detail, "Review likely issues from this import")
        XCTAssertNil(action.placeholder)
    }

    func testOmitsUnavailableOptionalReviewActionsWithoutCandidates() {
        let presentation = ImportCompletionPresentation.presentation(for: summary())

        XCTAssertNil(presentation.actionRows.first { $0.kind == .reviewFlaggedFrames })
        XCTAssertNil(presentation.actionRows.first { $0.kind == .keywordSuggestions })
        XCTAssertNil(presentation.actionRows.first { $0.kind == .faceNaming })

        let visibleText = presentation.metricRows.flatMap { [$0.value, $0.label, $0.detail] }
            + presentation.actionRows.flatMap { [$0.title, $0.detail] }
        XCTAssertFalse(visibleText.contains("No flagged frames yet"))
        XCTAssertFalse(visibleText.contains("No suggested keywords yet"))
        XCTAssertFalse(visibleText.contains("No face signals yet"))
        XCTAssertFalse(visibleText.contains { $0.contains("28 stacks") })
        XCTAssertFalse(visibleText.contains { $0.contains("3 new faces") })
    }

    func testSurfacesImportIssuesAsMetricRows() throws {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            issues: [
                WorkSessionIssue(
                    kind: .skippedSourceFile,
                    sourceURL: URL(fileURLWithPath: "/Photos/Import/bad.cr2"),
                    message: "could not fingerprint /Photos/Import/bad.cr2"
                )
            ]
        ))

        let issueMetric = try XCTUnwrap(presentation.metricRows.first { $0.id == "import-issues" })
        XCTAssertEqual(issueMetric.value, "1 issue")
        XCTAssertEqual(issueMetric.label, "Skipped files")
        XCTAssertEqual(issueMetric.detail, "bad.cr2: could not fingerprint /Photos/Import/bad.cr2")
        XCTAssertEqual(issueMetric.tone, .yellow)

        let action = try XCTUnwrap(presentation.actionRows.first { $0.kind == .reviewImportIssues })
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.title, "Review 1 skipped file")
        XCTAssertEqual(action.detail, "bad.cr2: could not fingerprint /Photos/Import/bad.cr2")
    }

    func testEnablesKeywordReviewActionWhenBatchSuggestionsExist() throws {
        let presentation = ImportCompletionPresentation.presentation(
            for: summary(),
            batchKeywordSuggestions: [
                BatchKeywordSuggestion(
                    keyword: "mountain",
                    assetCount: 3,
                    averageConfidence: 0.82,
                    providerName: "apple-vision",
                    modelName: "Vision"
                ),
                BatchKeywordSuggestion(
                    keyword: "lake",
                    assetCount: 1,
                    averageConfidence: 0.91,
                    providerName: "apple-vision",
                    modelName: "Vision"
                )
            ]
        )

        let action = try XCTUnwrap(presentation.actionRows.first { $0.kind == .keywordSuggestions })
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.title, "Review 2 keyword suggestions")
        XCTAssertEqual(action.detail, "Top: mountain - 3 photos at 82%")
        XCTAssertNil(action.placeholder)
    }

    func testEnablesFaceReviewActionWhenFaceSignalsExist() throws {
        let presentation = ImportCompletionPresentation.presentation(
            for: summary(),
            faceReviewAssetCount: 3
        )

        let action = try XCTUnwrap(presentation.actionRows.first { $0.kind == .faceNaming })
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.title, "Review 3 face photos")
        XCTAssertEqual(action.detail, "Open Faces Found review")
        XCTAssertNil(action.placeholder)
    }

    private func summary(
        importedPhotoCount: Int = 1,
        photoCountText: String = "1 photo",
        newPhotoCount: Int = 1,
        existingPhotoCount: Int = 0,
        previewFailureCount: Int = 0,
        failureText: String? = nil,
        previewStatusText: String = "Previews ready",
        issues: [WorkSessionIssue] = [],
        stackCount: Int = 0,
        stackedPhotoCount: Int = 0
    ) -> ImportCompletionSummary {
        ImportCompletionSummary(
            activityID: "import-1",
            title: "Import complete",
            detail: "Imported 12 photos from Card A",
            importedPhotoCount: importedPhotoCount,
            photoCountText: photoCountText,
            newPhotoCount: newPhotoCount,
            existingPhotoCount: existingPhotoCount,
            previewFailureCount: previewFailureCount,
            failureText: failureText,
            previewStatusText: previewStatusText,
            issues: issues,
            stackCount: stackCount,
            stackedPhotoCount: stackedPhotoCount,
            cullingSessionName: "Imported 12 photos from Card A Cull"
        )
    }
}
