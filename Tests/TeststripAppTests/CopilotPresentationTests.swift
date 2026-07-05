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
                .needsEvaluation: 81,
                .likelyIssues: 5,
                .providerFailures: 2
            ],
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .object, assetCount: 77),
                CatalogEvaluationKindSummary(kind: .focus, assetCount: 52),
                CatalogEvaluationKindSummary(kind: .ocrText, assetCount: 11)
            ],
            pendingMetadataSyncCount: 3,
            metadataSyncConflictCount: 1
        )

        XCTAssertEqual(presentation.metricRows.map(\.title), ["Scope", "Filters", "Work", "XMP"])
        XCTAssertEqual(presentation.metricRows.map(\.value), ["1204", "2", "1", "4"])
        XCTAssertEqual(presentation.reviewRows.map(\.title), ["Needs Evaluation", "Likely Issues", "Provider Failures"])
        XCTAssertEqual(presentation.reviewRows.map(\.countText), ["81", "5", "2"])
        XCTAssertTrue(presentation.reviewRows.allSatisfy(\.isActionEnabled))
        XCTAssertEqual(presentation.signalRows.map(\.title), ["Objects", "Focus", "Text"])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["77", "52", "11"])
    }

    func testPresentationStaysHonestWhenNoSignalsExist() {
        let presentation = CopilotPresentation(
            totalAssetCount: 42,
            activeFilterChips: [],
            visibleWorkActivities: [],
            reviewQueueCounts: [:],
            evaluationSummaries: [],
            pendingMetadataSyncCount: 0,
            metadataSyncConflictCount: 0
        )

        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP COPILOT")
        XCTAssertEqual(presentation.statusDetail, "Local evaluation, review queues, and background work are idle.")
        XCTAssertEqual(presentation.metricRows.map(\.value), ["42", "0", "0", "0"])
        XCTAssertEqual(presentation.reviewRows.map(\.isActionEnabled), [false, false, false])
        XCTAssertEqual(presentation.signalRows, [])
    }
}
