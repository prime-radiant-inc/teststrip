import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class CopilotPresentationTests: XCTestCase {
    func testPresentationSummarizesExistingAgenticState() {
        let runningWork = AppWorkActivity(
            id: "eval-running",
            kind: .recognition,
            status: .running,
            title: "Evaluate photos",
            detail: "Running local signals",
            completedUnitCount: 3,
            totalUnitCount: 10,
            failureCount: 0
        )
        let presentation = CopilotPresentation(
            totalAssetCount: 1204,
            activeFilterChips: ["Pick", "Needs Evaluation"],
            visibleWorkActivities: [runningWork],
            reviewQueueCounts: [
                .needsKeywords: 9,
                .needsEvaluation: 81,
                .facesFound: 14,
                .ocrFound: 11,
                .likelyIssues: 5,
                .providerFailures: 2
            ],
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .object, assetCount: 77),
                CatalogEvaluationKindSummary(kind: .focus, assetCount: 52),
                CatalogEvaluationKindSummary(kind: .ocrText, assetCount: 11)
            ],
            pendingMetadataSyncCount: 3,
            metadataSyncConflictCount: 1,
            canRequestVisibleAssetEvaluations: true
        )

        XCTAssertEqual(presentation.metricRows.map(\.title), ["Scope", "Filters", "Work", "XMP"])
        XCTAssertEqual(presentation.metricRows.map(\.value), ["1204", "2", "1", "4"])
        XCTAssertEqual(presentation.reviewRows.map(\.title), ["Needs Keywords", "Needs Evaluation", "Faces Found", "OCR Found", "Likely Issues", "Provider Failures"])
        XCTAssertEqual(presentation.reviewRows.map(\.countText), ["9", "81", "14", "11", "5", "2"])
        XCTAssertEqual(presentation.reviewRows.map(\.target), [
            .reviewQueue(.needsKeywords),
            .reviewQueue(.needsEvaluation),
            .reviewQueue(.facesFound),
            .reviewQueue(.ocrFound),
            .reviewQueue(.likelyIssues),
            .reviewQueue(.providerFailures)
        ])
        XCTAssertTrue(presentation.reviewRows.allSatisfy(\.isActionEnabled))
        XCTAssertEqual(presentation.signalRows.map(\.title), ["Objects", "Focus", "Text"])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["77", "52", "11"])
        XCTAssertEqual(presentation.signalRows.map(\.target), [
            .evaluationKind(.object),
            .evaluationKind(.focus),
            .evaluationKind(.ocrText)
        ])
        XCTAssertEqual(presentation.readChips, ["Pick", "Needs Evaluation"])
        XCTAssertEqual(presentation.primaryAction?.title, "Review XMP Conflicts")
        XCTAssertEqual(presentation.primaryAction?.action, .open(.metadataSyncConflicts))
    }

    func testPresentationStaysHonestWhenNoSignalsExist() {
        let presentation = CopilotPresentation(
            totalAssetCount: 42,
            activeFilterChips: [],
            visibleWorkActivities: [],
            reviewQueueCounts: [:],
            evaluationSummaries: [],
            pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0,
            canRequestVisibleAssetEvaluations: false
        )

        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP COPILOT")
        XCTAssertEqual(presentation.statusDetail, "Local evaluation, review queues, and background work are idle.")
        XCTAssertEqual(presentation.metricRows.map(\.value), ["42", "0", "0", "0"])
        XCTAssertEqual(presentation.reviewRows.map(\.isActionEnabled), [false, false, false, false, false, false])
        XCTAssertEqual(presentation.reviewRows.map(\.statusText), [
            "No photos missing keywords",
            "All catalog photos have local signals",
            "No face signals recorded",
            "No OCR text signals recorded",
            "No likely issues found",
            "No provider failures recorded"
        ])
        XCTAssertEqual(presentation.signalRows, [])
        XCTAssertEqual(presentation.readChips, ["All photographs"])
        XCTAssertNil(presentation.primaryAction)
    }

    func testPresentationPrioritizesReviewWorkBeforeRunningMoreSignals() {
        let presentation = CopilotPresentation(
            totalAssetCount: 90,
            activeFilterChips: [],
            visibleWorkActivities: [],
            reviewQueueCounts: [
                .needsEvaluation: 12,
                .likelyIssues: 4,
                .providerFailures: 3
            ],
            evaluationSummaries: [],
            pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0,
            canRequestVisibleAssetEvaluations: true
        )

        XCTAssertEqual(presentation.primaryAction?.title, "Review Provider Failures")
        XCTAssertEqual(presentation.primaryAction?.detail, "3 evaluation failures need attention")
        XCTAssertEqual(presentation.primaryAction?.action, .open(.reviewQueue(.providerFailures)))
    }

    func testPresentationOffersLoadedSignalRunWhenNoReviewWorkExists() {
        let presentation = CopilotPresentation(
            totalAssetCount: 90,
            activeFilterChips: ["Needs Evaluation"],
            visibleWorkActivities: [],
            reviewQueueCounts: [:],
            evaluationSummaries: [],
            pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0,
            canRequestVisibleAssetEvaluations: true
        )

        XCTAssertEqual(presentation.primaryAction?.title, "Run Local Signals")
        XCTAssertEqual(presentation.primaryAction?.detail, "Evaluate loaded photos with local providers")
        XCTAssertEqual(presentation.primaryAction?.action, .evaluateVisibleAssets)
    }

    func testPresentationOffersScopeSetActionsWhenCurrentReadCanBeSaved() {
        let presentation = CopilotPresentation(
            totalAssetCount: 42,
            activeFilterChips: ["Pick", "Camera: Canon"],
            visibleWorkActivities: [],
            reviewQueueCounts: [:],
            evaluationSummaries: [],
            pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0,
            canRequestVisibleAssetEvaluations: false,
            suggestedName: "Canon Picks",
            canSaveDynamicSet: true,
            canSaveSnapshotSet: true
        )

        XCTAssertEqual(presentation.scopeActions, [
            CopilotScopeActionPresentation(
                action: .saveDynamicSet,
                title: "Save Dynamic Set",
                detail: "Canon Picks updates as the catalog changes",
                systemImage: "bookmark"
            ),
            CopilotScopeActionPresentation(
                action: .saveSnapshotSet,
                title: "Freeze 42 Results",
                detail: "Capture this exact result set",
                systemImage: "camera.viewfinder"
            )
        ])
    }
}
