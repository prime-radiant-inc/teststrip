import Foundation
import XCTest
@testable import TeststripCore

final class SupervisorPerItemCancelTests: XCTestCase {
    func testCancellingDispatchedItemLeavesSiblingDispatchedWithoutTerminating() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = makeConcurrentSupervisor(transport: transport)
        let previewItem = BackgroundWorkItem.testCancelItem(id: "preview", kind: .previewGeneration)
        let recognitionItem = BackgroundWorkItem.testCancelItem(id: "recognition", kind: .recognition)
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let recognitionCommand = WorkerCommand.runEvaluation(assetID: AssetID(rawValue: "asset-1"), provider: "local-image-metrics")
        try supervisor.enqueue(previewItem, command: previewCommand)
        try supervisor.enqueue(recognitionItem, command: recognitionCommand)

        XCTAssertTrue(supervisor.isCommandDispatched(for: previewItem.id))
        XCTAssertTrue(supervisor.isCommandDispatched(for: recognitionItem.id))

        try supervisor.cancel(id: recognitionItem.id)

        // The sibling preview lane keeps running, entirely untouched.
        XCTAssertTrue(supervisor.isCommandDispatched(for: previewItem.id))
        XCTAssertEqual(supervisor.queue.item(id: previewItem.id)?.status, .running)
        // Per-item cancel never kills the worker or broadcasts cancelAll.
        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertFalse(try transport.commands().contains(.cancelAll))
        // The cancelling lane stays occupied (still running/dispatched) until its
        // own natural terminal arrives, so no second same-kind command dispatches.
        XCTAssertTrue(supervisor.isCommandDispatched(for: recognitionItem.id))
        XCTAssertEqual(supervisor.queue.item(id: recognitionItem.id)?.status, .running)
    }

    func testCancelledDispatchedItemFinalizesAsCancelledOnCompletedTerminal() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = makeConcurrentSupervisor(transport: transport)
        var completedEvents: [WorkerEvent] = []
        supervisor.onCommandCompleted = { completedEvents.append($0) }
        let previewItem = BackgroundWorkItem.testCancelItem(id: "preview", kind: .previewGeneration)
        let recognitionItem = BackgroundWorkItem.testCancelItem(id: "recognition", kind: .recognition)
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let recognitionCommand = WorkerCommand.runEvaluation(assetID: AssetID(rawValue: "asset-1"), provider: "local-image-metrics")
        try supervisor.enqueue(previewItem, command: previewCommand)
        try supervisor.enqueue(recognitionItem, command: recognitionCommand)

        try supervisor.cancel(id: recognitionItem.id)

        // The worker's natural terminal for the cancelled item happens to be "completed".
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: recognitionItem.id,
            message: "ran local-image-metrics evaluation for asset-1"
        )))

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: recognitionItem.id)?.status == .cancelled
        })
        // A cancelled item ends cancelled, not completed, and frees its lane.
        XCTAssertFalse(supervisor.isCommandDispatched(for: recognitionItem.id))
        // The sibling is never disturbed.
        XCTAssertTrue(supervisor.isCommandDispatched(for: previewItem.id))
        XCTAssertEqual(supervisor.queue.item(id: previewItem.id)?.status, .running)
        XCTAssertEqual(transport.terminateCount, 0)
        // A cancelled item does not report a completion to observers.
        XCTAssertTrue(completedEvents.isEmpty)
    }

    func testCancelledDispatchedItemFinalizesAsCancelledOnFailedTerminal() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = makeConcurrentSupervisor(transport: transport)
        let previewItem = BackgroundWorkItem.testCancelItem(id: "preview", kind: .previewGeneration)
        let recognitionItem = BackgroundWorkItem.testCancelItem(id: "recognition", kind: .recognition)
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let recognitionCommand = WorkerCommand.runEvaluation(assetID: AssetID(rawValue: "asset-1"), provider: "local-image-metrics")
        try supervisor.enqueue(previewItem, command: previewCommand)
        try supervisor.enqueue(recognitionItem, command: recognitionCommand)

        try supervisor.cancel(id: recognitionItem.id)

        // The worker's natural terminal for the cancelled item happens to be "failed".
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: recognitionItem.id,
            message: "evaluation error"
        )))

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: recognitionItem.id)?.status == .cancelled
        })
        // A cancelled item ends cancelled, never failed.
        XCTAssertNotEqual(supervisor.queue.item(id: recognitionItem.id)?.status, .failed)
        XCTAssertFalse(supervisor.isCommandDispatched(for: recognitionItem.id))
        // The sibling is never disturbed.
        XCTAssertTrue(supervisor.isCommandDispatched(for: previewItem.id))
        XCTAssertEqual(supervisor.queue.item(id: previewItem.id)?.status, .running)
        XCTAssertEqual(transport.terminateCount, 0)
    }

    func testCancellingQueuedItemCancelsItDirectly() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: nil
        )
        let running = BackgroundWorkItem.testCancelItem(id: "running", kind: .previewGeneration)
        let queued = BackgroundWorkItem.testCancelItem(id: "queued", kind: .previewGeneration)
        let runningCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let queuedCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .grid)
        try supervisor.enqueue(running, command: runningCommand)
        try supervisor.enqueue(queued, command: queuedCommand)

        XCTAssertTrue(supervisor.isCommandDispatched(for: running.id))
        XCTAssertFalse(supervisor.isCommandDispatched(for: queued.id))
        XCTAssertEqual(supervisor.queue.item(id: queued.id)?.status, .queued)

        try supervisor.cancel(id: queued.id)

        // A never-dispatched item cancels immediately.
        XCTAssertEqual(supervisor.queue.item(id: queued.id)?.status, .cancelled)
        // The running sibling is untouched and the worker is never terminated.
        XCTAssertTrue(supervisor.isCommandDispatched(for: running.id))
        XCTAssertEqual(supervisor.queue.item(id: running.id)?.status, .running)
        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertFalse(try transport.commands().contains(.cancelAll))
    }

    private func makeConcurrentSupervisor(transport: RecordingWorkerTransport) -> WorkerSupervisor {
        WorkerSupervisor(
            queue: BackgroundWorkQueue(
                maxRunningCount: 8,
                kindRunningLimits: [.previewGeneration: 1, .recognition: 1]
            ),
            transport: transport,
            commandTimeout: nil,
            maxDispatchedCommandCount: 8
        )
    }
}

private extension BackgroundWorkItem {
    static func testCancelItem(id: String, kind: WorkSessionKind) -> BackgroundWorkItem {
        BackgroundWorkItem(
            id: WorkSessionID(rawValue: id),
            kind: kind,
            title: "Work \(id)",
            detail: "Working",
            completedUnitCount: 0,
            totalUnitCount: 10
        )
    }
}

private func waitUntil(timeout: TimeInterval = 2, predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return predicate()
}
