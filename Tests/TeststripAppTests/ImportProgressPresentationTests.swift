import XCTest
import TeststripCore
@testable import TeststripApp

final class ImportProgressPresentationTests: XCTestCase {
    func testMissingActivityShowsStartingState() {
        let presentation = ImportProgressPresentation.presentation(for: nil)

        XCTAssertEqual(presentation.title, "Import photos")
        XCTAssertEqual(presentation.phaseText, "Starting")
        XCTAssertEqual(presentation.detail, "Preparing import")
        XCTAssertNil(presentation.countText)
    }

    func testUnknownTotalShowsScanningState() {
        let presentation = ImportProgressPresentation.presentation(for: activity(
            detail: "Importing from photos",
            completed: 0,
            total: nil
        ))

        XCTAssertEqual(presentation.phaseText, "Scanning source")
        XCTAssertEqual(presentation.detail, "Importing from photos")
        XCTAssertNil(presentation.countText)
    }

    func testQueuedActivityShowsWaitingState() {
        let presentation = ImportProgressPresentation.presentation(for: activity(
            status: .queued,
            detail: "Importing from photos",
            completed: 0,
            total: nil
        ))

        XCTAssertEqual(presentation.phaseText, "Waiting")
        XCTAssertEqual(presentation.detail, "Importing from photos")
        XCTAssertNil(presentation.countText)
    }

    func testCancelHelpNamesTheActiveImportSource() {
        let folderPresentation = ImportProgressPresentation.presentation(for: activity(
            detail: "Importing from photos",
            completed: 0,
            total: nil
        ))
        let cardPresentation = ImportProgressPresentation.presentation(for: activity(
            detail: "Importing from DCIM to Library",
            completed: 0,
            total: nil
        ))

        XCTAssertEqual(folderPresentation.cancelHelp, "Cancel import from photos")
        XCTAssertEqual(cardPresentation.cancelHelp, "Cancel import from DCIM to Library")
    }

    func testPausedActivityShowsPausedState() {
        let presentation = ImportProgressPresentation.presentation(for: activity(
            status: .paused,
            detail: "Cataloging 12 of 100 photos",
            completed: 12,
            total: 100
        ))

        XCTAssertEqual(presentation.phaseText, "Paused")
        XCTAssertEqual(presentation.detail, "Cataloging 12 of 100 photos")
        XCTAssertEqual(presentation.countText, "12 of 100")
    }

    func testCatalogingProgressShowsCatalogingPhaseAndCount() {
        let presentation = ImportProgressPresentation.presentation(for: activity(
            detail: "Cataloging 12 of 100 photos",
            completed: 12,
            total: 100
        ))

        XCTAssertEqual(presentation.phaseText, "Cataloging")
        XCTAssertEqual(presentation.detail, "Cataloging 12 of 100 photos")
        XCTAssertEqual(presentation.countText, "12 of 100")
    }

    func testPreviewProgressShowsPreviewPhase() {
        let presentation = ImportProgressPresentation.presentation(for: activity(
            detail: "Generated 2 of 10 previews",
            completed: 2,
            total: 10
        ))

        XCTAssertEqual(presentation.phaseText, "Building previews")
        XCTAssertEqual(presentation.countText, "2 of 10")
    }

    private func activity(
        status: WorkSessionStatus = .running,
        detail: String,
        completed: Int,
        total: Int?
    ) -> AppWorkActivity {
        AppWorkActivity(
            kind: .ingest,
            status: status,
            title: "Import photos",
            detail: detail,
            completedUnitCount: completed,
            totalUnitCount: total,
            failureCount: 0
        )
    }
}
