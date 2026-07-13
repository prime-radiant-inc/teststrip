import XCTest
import TeststripCore
@testable import TeststripApp

final class ActivityCenterPresentationTests: XCTestCase {
    func testHealthyIdleShowsNoBadgeAndNotWorking() {
        let presentation = ActivityCenterPresentation(
            kindRows: [],
            importActivity: nil,
            importError: nil,
            sources: [],
            xmpConflicts: [],
            providerFailureCount: 0
        )

        XCTAssertEqual(presentation.badge, .none)
        XCTAssertFalse(presentation.isWorking)
        XCTAssertNil(presentation.importProgress)
        XCTAssertNil(presentation.importError)
    }

    func testRunningKindRowsSetWorkingButNoBadge() {
        let runningRow = ActivityKindRow(
            id: WorkSessionKind.previewGeneration.rawValue,
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Generated 2 of 10 previews",
            completedUnitCount: 2,
            totalUnitCount: 10,
            status: .running,
            activeItemCount: 1,
            canPause: true,
            canResume: false,
            canCancel: true
        )

        let presentation = ActivityCenterPresentation(
            kindRows: [runningRow],
            importActivity: nil,
            importError: nil,
            sources: [],
            xmpConflicts: [],
            providerFailureCount: 0
        )

        XCTAssertTrue(presentation.isWorking)
        XCTAssertEqual(presentation.badge, .none)
    }

    func testConflictsAndOfflineSourcesSumIntoProblemBadge() {
        let conflicts = (1...3).map { index in
            ConflictRow(assetID: AssetID(rawValue: "asset-\(index)"), displayName: "Photo \(index)")
        }
        let sources = [
            SourceStatusRow(id: "root-1", name: "Card A", availability: .online),
            SourceStatusRow(id: "root-2", name: "Card B", availability: .offline)
        ]

        let presentation = ActivityCenterPresentation(
            kindRows: [],
            importActivity: nil,
            importError: nil,
            sources: sources,
            xmpConflicts: conflicts,
            providerFailureCount: 0
        )

        XCTAssertEqual(presentation.badge, .problems(4))
    }

    func testEveryNonOnlineSourceAvailabilityCountsTowardProblemBadge() {
        for availability in [SourceAvailability.offline, .missing, .moved, .stale] {
            let presentation = ActivityCenterPresentation(
                kindRows: [],
                importActivity: nil,
                importError: nil,
                sources: [
                    SourceStatusRow(id: "root-ok", name: "Library", availability: .online),
                    SourceStatusRow(id: "root-bad", name: "Card", availability: availability)
                ],
                xmpConflicts: [],
                providerFailureCount: 0
            )

            XCTAssertEqual(
                presentation.badge,
                .problems(1),
                "\(availability) source should count toward the problem badge"
            )
        }
    }

    func testImportProgressAndErrorSurface() {
        let importActivity = AppWorkActivity(
            kind: .ingest,
            status: .running,
            title: "Import photos",
            detail: "Cataloging 12 of 100 photos",
            completedUnitCount: 12,
            totalUnitCount: 100,
            failureCount: 0
        )

        let presentation = ActivityCenterPresentation(
            kindRows: [],
            importActivity: importActivity,
            importError: "Import failed: disk full",
            sources: [],
            xmpConflicts: [],
            providerFailureCount: 0
        )

        XCTAssertNotNil(presentation.importProgress)
        XCTAssertEqual(presentation.importProgress?.cancelActionID, importActivity.id)
        XCTAssertEqual(presentation.importError, "Import failed: disk full")
        XCTAssertTrue(presentation.isWorking)
    }
}
