import XCTest
@testable import TeststripCore

/// Covers Task B3: with per-kind dispatch caps of 1 and a `maxDispatchedCommandCount`
/// large enough to admit every lane, the supervisor dispatches different-kind
/// commands to the worker concurrently instead of queuing the second behind the first.
final class SupervisorConcurrentDispatchTests: XCTestCase {
    func testDispatchesTwoDifferentKindLanesConcurrently() throws {
        let transport = RecordingWorkerTransport()
        let limits: [WorkSessionKind: Int] = [.previewGeneration: 1, .recognition: 1]
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: limits),
            transport: transport,
            commandTimeout: nil,
            maxDispatchedCommandCount: 8
        )
        let previewItem = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "prev-1"),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Rendering cached previews",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        let evaluationItem = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "eval-1"),
            kind: .recognition,
            title: "Evaluate photos",
            detail: "Scoring photos",
            completedUnitCount: 0,
            totalUnitCount: 1
        )

        try supervisor.enqueue(previewItem, command: .generatePreview(assetID: AssetID(rawValue: "a"), level: .micro))
        try supervisor.enqueue(evaluationItem, command: .runEvaluation(assetID: AssetID(rawValue: "a"), provider: "local-image-metrics"))

        XCTAssertTrue(supervisor.isCommandDispatched(for: previewItem.id))
        XCTAssertTrue(supervisor.isCommandDispatched(for: evaluationItem.id))
        XCTAssertEqual(supervisor.queue.item(id: previewItem.id)?.status, .running)
        XCTAssertEqual(supervisor.queue.item(id: evaluationItem.id)?.status, .running)
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: AssetID(rawValue: "a"), level: .micro),
            .runEvaluation(assetID: AssetID(rawValue: "a"), provider: "local-image-metrics")
        ])
    }
}
