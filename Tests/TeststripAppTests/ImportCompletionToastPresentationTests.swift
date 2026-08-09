import XCTest
@testable import TeststripCore
@testable import TeststripApp

// One capsule, top-right, ~10s, then it docks into the bell as the receipt.
// It replaces roughly 280pt of banner chrome whose nine actions collapsed to
// four intents.
final class ImportCompletionToastPresentationTests: XCTestCase {
    private func summary(
        activityID: String = "import-1",
        imported: Int = 24,
        new: Int = 24,
        existing: Int = 0,
        issues: Int = 0
    ) -> ImportCompletionSummary {
        ImportCompletionSummary(
            activityID: activityID,
            title: "Import complete",
            detail: "Imported \(imported) photos from /Cards/A",
            importedPhotoCount: imported,
            photoCountText: "\(imported) \(imported == 1 ? "photo" : "photos")",
            newPhotoCount: new,
            existingPhotoCount: existing,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "Previews ready",
            issues: (0..<issues).map { index in
                WorkSessionIssue(kind: .skippedSourceFile, sourceURL: nil, message: "skipped \(index)")
            },
            cullingSessionName: "/Cards/A Cull"
        )
    }

    func testAFullImportOffersStartCulling() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.headline, "Imported 24 photos")
        XCTAssertNil(toast.warningText)
        XCTAssertTrue(toast.showsStartCulling)
        XCTAssertEqual(toast.sessionID, WorkSessionID(rawValue: "import-1"))
        XCTAssertEqual(toast.cullingSessionName, "/Cards/A Cull")
    }

    func testASkippedFileCountSurfacesAsAWarning() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(issues: 2),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.warningText, "2 files skipped")
        XCTAssertTrue(toast.showsStartCulling)
    }

    func testOneSkippedFileIsSingular() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(issues: 1),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.warningText, "1 file skipped")
    }

    // Existing-only imports get the same shape with that copy and no Start
    // culling button — there is nothing new to cull.
    func testAnExistingOnlyImportGetsItsOwnCopyAndNoStartCulling() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(imported: 24, new: 0, existing: 24),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.headline, "No new photos imported — 24 already in catalog")
        XCTAssertFalse(toast.showsStartCulling)
    }

    // The persona-7 zombie-panel lesson: a summary restored from persisted
    // work history must never resurrect the toast on relaunch.
    func testARestoredSummaryFromAPreviousSessionProducesNoToast() {
        XCTAssertNil(
            ImportCompletionToastPresentation.toast(
                for: summary(),
                isCurrentSessionActivity: false,
                isImporting: false
            )
        )
    }

    func testNoToastWhileAnImportIsStillRunning() {
        XCTAssertNil(
            ImportCompletionToastPresentation.toast(
                for: summary(),
                isCurrentSessionActivity: true,
                isImporting: true
            )
        )
    }

    func testNoSummaryMeansNoToast() {
        XCTAssertNil(
            ImportCompletionToastPresentation.toast(
                for: nil,
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )
    }

    func testTheToastFadesAfterAboutTenSeconds() {
        XCTAssertEqual(ImportCompletionToastPresentation.visibleDuration, 10)
    }

    // The banner presentation types are gone at compile level. This test does
    // not reference them — their absence is proven by this file compiling
    // after ImportCompletionPresentationTests.swift is deleted.
}
