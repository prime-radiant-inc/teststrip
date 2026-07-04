import XCTest
@testable import TeststripApp

final class ImportCompletionPresentationTests: XCTestCase {
    func testBuildsPayoffRowsFromCompletedImportSummary() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 12,
            photoCountText: "12 photos",
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "Previews ready"
        ))

        XCTAssertEqual(presentation.title, "12 photos imported")
        XCTAssertEqual(presentation.detail, "Imported 12 photos from Card A")
        XCTAssertEqual(presentation.metricRows.map(\.label), ["Imported set", "Previews", "Cull scope"])
        XCTAssertEqual(presentation.metricRows.map(\.value), ["12 photos", "Ready", "Ready"])
        XCTAssertEqual(presentation.enabledActions.map(\.kind), [.startCulling, .openInLibrary])
        XCTAssertEqual(presentation.placeholderActions.map(\.kind), [.stackGrouping, .faceNaming, .keywordSuggestions])
    }

    func testSurfacesPreviewFailuresWithoutBlockingImportActions() {
        let presentation = ImportCompletionPresentation.presentation(for: summary(
            importedPhotoCount: 4,
            photoCountText: "4 photos",
            previewFailureCount: 2,
            failureText: "2 preview failures",
            previewStatusText: "2 preview failures"
        ))

        XCTAssertEqual(presentation.metricRows.first { $0.id == "previews" }?.value, "2 issues")
        XCTAssertEqual(presentation.metricRows.first { $0.id == "previews" }?.detail, "2 preview failures")
        XCTAssertEqual(presentation.enabledActions.map(\.kind), [.startCulling, .openInLibrary])
    }

    func testUnbuiltFollowUpsAreDisabledAndAnnotated() {
        let presentation = ImportCompletionPresentation.presentation(for: summary())

        XCTAssertEqual(presentation.placeholderActions.map(\.placeholder?.id), [
            LiveMockupPlaceholders.cullingStackCull.id,
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
            previewFailureCount: previewFailureCount,
            failureText: failureText,
            previewStatusText: previewStatusText,
            cullingSessionName: "Imported 12 photos from Card A Cull"
        )
    }
}
