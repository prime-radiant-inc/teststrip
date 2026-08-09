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
            receipts: [],
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
            receipts: [],
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
            receipts: [],
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
                receipts: [],
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
            receipts: [],
            providerFailureCount: 0
        )

        XCTAssertNotNil(presentation.importProgress)
        XCTAssertEqual(presentation.importProgress?.cancelActionID, importActivity.id)
        XCTAssertEqual(presentation.importError, "Import failed: disk full")
        XCTAssertTrue(presentation.isWorking)
    }

    // MARK: - Import receipts

    // The toast is the announcement; the bell is the archive. Completed
    // imports become a receipt family in the Activity Center — and they never
    // badge, because the badge counts problems only.
    func testCompletedImportsBecomeReceipts() {
        let receipts = ImportReceiptRow.rows(
            from: [
                AppWorkActivity(
                    id: "import-1",
                    kind: .ingest,
                    status: .completed,
                    title: "Import photos",
                    detail: "Imported 24 photos from /Cards/A",
                    completedUnitCount: 24,
                    totalUnitCount: 24,
                    failureCount: 0
                ),
                AppWorkActivity(
                    id: "cull-1",
                    kind: .culling,
                    status: .completed,
                    title: "Cull the shoot",
                    detail: "12 picks",
                    completedUnitCount: 12,
                    totalUnitCount: 24,
                    failureCount: 0
                ),
                AppWorkActivity(
                    id: "import-running",
                    kind: .ingest,
                    status: .running,
                    title: "Import photos",
                    detail: "Importing…",
                    completedUnitCount: 3,
                    totalUnitCount: 24,
                    failureCount: 0
                )
            ],
            limit: ImportReceiptRow.retentionLimit
        )

        XCTAssertEqual(receipts.map(\.id), ["import-1"])
        XCTAssertEqual(receipts.first?.title, "Imported 24 photos from /Cards/A")
        XCTAssertTrue(receipts.first?.canStartCulling ?? false)
    }

    func testReceiptsAreCappedByTheRetentionLimit() {
        let activities = (0..<12).map { index in
            AppWorkActivity(
                id: "import-\(index)",
                kind: .ingest,
                status: .completed,
                title: "Import photos",
                detail: "Imported 1 photo from /Cards/\(index)",
                completedUnitCount: 1,
                totalUnitCount: 1,
                failureCount: 0
            )
        }

        XCTAssertEqual(ImportReceiptRow.rows(from: activities, limit: 5).count, 5)
    }

    func testAReceiptCarriesItsIssueCountButNeverBadges() {
        let presentation = ActivityCenterPresentation(
            kindRows: [],
            importActivity: nil,
            importError: nil,
            sources: [],
            xmpConflicts: [],
            receipts: [
                ImportReceiptRow(
                    id: "import-1",
                    sessionID: WorkSessionID(rawValue: "import-1"),
                    title: "Imported 6 photos from /Cards/A",
                    detail: "2 files skipped",
                    issueCount: 2,
                    canStartCulling: true
                )
            ],
            providerFailureCount: 0
        )

        XCTAssertEqual(presentation.receipts.count, 1)
        XCTAssertEqual(presentation.badge, .none, "receipts never badge — the badge counts problems only")
        XCTAssertFalse(presentation.isWorking)
    }
}
