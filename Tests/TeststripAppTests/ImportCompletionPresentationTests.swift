import XCTest
@testable import TeststripApp

final class ImportCompletionPresentationTests: XCTestCase {
    func testBuildsPayoffRowsFromCompletedImportSummary() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 12,
            photoCountText: "12 photos",
            newPhotoCount: 12,
            existingPhotoCount: 0,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "Previews ready"
        ))

        XCTAssertEqual(presentation.title, "12 photos imported")
        XCTAssertEqual(presentation.detail, "Imported 12 photos from Card A")
        XCTAssertEqual(presentation.metricRows.map(\.label), ["Imported set", "Previews", "Cull scope"])
        XCTAssertEqual(presentation.metricRows.map(\.value), ["12 photos", "Ready", "Ready"])
        XCTAssertEqual(presentation.enabledActions.map(\.kind), [.startCulling, .reviewImportedFrames, .openInLibrary, .stackGrouping])
        XCTAssertEqual(presentation.placeholderActions.map(\.kind), [.faceNaming, .keywordSuggestions])
    }

    func testSurfacesPreviewFailuresWithoutBlockingImportActions() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 4,
            photoCountText: "4 photos",
            newPhotoCount: 4,
            existingPhotoCount: 0,
            previewFailureCount: 2,
            failureText: "2 preview failures",
            previewStatusText: "2 preview failures"
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

    func testAddsManualCompareAndStackCullActionsWithoutClaimingSimilarityGrouping() throws {
        let presentation = ImportCompletionPresentation.presentation(for: summary())

        let compareAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .reviewImportedFrames })
        XCTAssertTrue(compareAction.isEnabled)
        XCTAssertEqual(compareAction.title, "Review imported frames")
        XCTAssertEqual(compareAction.detail, "Manual Compare over this import")
        XCTAssertNil(compareAction.placeholder)

        let stackAction = try XCTUnwrap(presentation.actionRows.first { $0.kind == .stackGrouping })
        XCTAssertTrue(stackAction.isEnabled)
        XCTAssertEqual(stackAction.title, "Cull stacks")
        XCTAssertEqual(stackAction.detail, "Time-adjacent stack rail")
        XCTAssertNil(stackAction.placeholder)
    }

    func testEnablesKeywordSuggestionActionWhenBatchSuggestionsExist() throws {
        let presentation = ImportCompletionPresentation.presentation(
            for: summary(),
            batchKeywordSuggestions: [
                BatchKeywordSuggestion(
                    keyword: "mountain",
                    assetCount: 3,
                    averageConfidence: 0.82,
                    providerName: "apple-vision",
                    modelName: "Vision"
                )
            ]
        )

        let action = try XCTUnwrap(presentation.actionRows.first { $0.kind == .keywordSuggestions })
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.title, "Apply mountain")
        XCTAssertEqual(action.detail, "3 photos at 82%")
        XCTAssertNil(action.placeholder)
    }

    func testUnbuiltFollowUpsAreDisabledAndAnnotated() {
        let presentation = ImportCompletionPresentation.presentation(for: summary())

        XCTAssertEqual(presentation.placeholderActions.map(\.placeholder?.id), [
            LiveMockupPlaceholders.peopleFaceActions.id,
            LiveMockupPlaceholders.keywordingBatch.id
        ])
        XCTAssertTrue(presentation.placeholderActions.allSatisfy { !$0.isEnabled })

        let visibleText = presentation.metricRows.flatMap { [$0.value, $0.label, $0.detail] }
            + presentation.actionRows.flatMap { [$0.title, $0.detail] }
        XCTAssertFalse(visibleText.contains { $0.contains("28 stacks") })
        XCTAssertFalse(visibleText.contains { $0.contains("3 new faces") })
    }

    private func summary(
        importedPhotoCount: Int = 1,
        photoCountText: String = "1 photo",
        newPhotoCount: Int = 1,
        existingPhotoCount: Int = 0,
        previewFailureCount: Int = 0,
        failureText: String? = nil,
        previewStatusText: String = "Previews ready"
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
            cullingSessionName: "Imported 12 photos from Card A Cull"
        )
    }
}
