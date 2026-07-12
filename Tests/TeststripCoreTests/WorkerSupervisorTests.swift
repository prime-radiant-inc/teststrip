import Darwin
import Foundation
import XCTest
@testable import TeststripCore

final class WorkerSupervisorTests: XCTestCase {
    func testEnqueueLaunchesWorkerAndDispatchesOnlyRunnableWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)

        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        XCTAssertEqual(transport.launchCount, 1)
        XCTAssertEqual(try transport.commands(), [firstCommand])
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .running)
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .queued)
    }

    func testBatchEnqueueNotifiesQueueChangedOnceAndDispatchesRunnableWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        var queueSnapshots: [BackgroundWorkQueue] = []
        supervisor.onQueueChanged = { queueSnapshots.append($0) }
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)

        try supervisor.enqueue([
            (item: first, command: firstCommand, placement: .back),
            (item: second, command: secondCommand, placement: .back)
        ])

        XCTAssertEqual(queueSnapshots.count, 1)
        XCTAssertEqual(transport.launchCount, 1)
        XCTAssertEqual(try transport.commands(), [firstCommand])
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .running)
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .queued)
    }

    func testCompletingRunningWorkDispatchesNextQueuedCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.syncMetadata(assetID: AssetID(rawValue: "asset-1"))
        let secondCommand = WorkerCommand.runEvaluation(assetID: AssetID(rawValue: "asset-2"), provider: "local")
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        try supervisor.markCompleted(id: first.id)

        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .completed)
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .running)
    }

    func testPromotingQueuedWorkDispatchesItBeforeOlderQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let olderQueued = BackgroundWorkItem.testItem(id: "older")
        let visible = BackgroundWorkItem.testItem(id: "visible")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let olderCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .grid)
        let visibleCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-3"), level: .grid)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(olderQueued, command: olderCommand)
        try supervisor.enqueue(visible, command: visibleCommand)

        XCTAssertTrue(try supervisor.promoteQueuedItem(id: visible.id))
        try supervisor.markCompleted(id: first.id)

        XCTAssertEqual(try transport.commands(), [firstCommand, visibleCommand])
        XCTAssertEqual(supervisor.queue.item(id: visible.id)?.status, .running)
        XCTAssertEqual(supervisor.queue.item(id: olderQueued.id)?.status, .queued)
    }

    func testCompletedWorkerEventCompletesDispatchedItemAndStartsNextQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: first.id,
            message: "generated medium preview for asset-1"
        )))

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .completed &&
                supervisor.queue.item(id: first.id)?.detail == "generated medium preview for asset-1" &&
                supervisor.queue.item(id: second.id)?.status == .running
        })
        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
    }

    func testCompletedWorkerEventReportsStructuredEventForDispatchedItem() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        var completedEvents: [WorkerEvent] = []
        supervisor.onCommandCompleted = { completedEvents.append($0) }
        let item = BackgroundWorkItem.testItem(id: "import")
        let command = WorkerCommand.importFolder(root: URL(fileURLWithPath: "/Photos", isDirectory: true), duplicateHandling: .importAll)
        let event = WorkerEvent.completedImport(
            itemID: item.id,
            message: "imported 1 photo from Photos",
            importedAssetIDs: [AssetID(rawValue: "asset-1")],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )
        try supervisor.enqueue(item, command: command)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(event))

        XCTAssertTrue(waitUntil {
            completedEvents == [event] &&
                supervisor.queue.item(id: item.id)?.status == .completed
        })
    }

    func testProgressWorkerEventUpdatesDispatchedItem() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let item = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "import"),
            kind: .ingest,
            title: "Import photos",
            detail: "Importing from photos",
            completedUnitCount: 0,
            totalUnitCount: nil
        )
        try supervisor.enqueue(item, command: .importFolder(root: URL(fileURLWithPath: "/Photos", isDirectory: true), duplicateHandling: .importAll))

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: item.id,
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: []
        )))

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: item.id)?.status == .running &&
                supervisor.queue.item(id: item.id)?.detail == "Cataloged 3 photos" &&
                supervisor.queue.item(id: item.id)?.completedUnitCount == 3 &&
            supervisor.queue.item(id: item.id)?.totalUnitCount == 8
        })
    }

    // This is the integration-level watchdog coverage that
    // IngestProgressCoalescer/ScanProgressCoalescer's time-based heartbeat
    // (see ProgressCoalescerTests) relies on: a command that keeps emitting
    // progress under `commandTimeout` never trips the watchdog, while one
    // that goes silent for a full `commandTimeout` does.
    func testProgressWorkerEventReschedulesCommandTimeout() throws {
        let transport = RecordingWorkerTransport()
        let timeoutScheduler = ManualWorkerTimeoutScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: 30,
            timeoutScheduler: timeoutScheduler
        )
        let item = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "import"),
            kind: .ingest,
            title: "Import photos",
            detail: "Importing from photos",
            completedUnitCount: 0,
            totalUnitCount: nil
        )
        try supervisor.enqueue(item, command: .importFolder(root: URL(fileURLWithPath: "/Photos", isDirectory: true), duplicateHandling: .importAll))

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: item.id,
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: []
        )))
        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: item.id)?.detail == "Cataloged 3 photos"
        })

        timeoutScheduler.fireNext()
        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .running)

        timeoutScheduler.fireNext()
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .failed)
    }

    func testDispatchedWorkerCommandCarriesWorkItemID() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let item = BackgroundWorkItem.testItem(id: "preview-work")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)

        try supervisor.enqueue(item, command: command)

        let request = try XCTUnwrap(try transport.requests().first)
        XCTAssertEqual(request.command, command)
        XCTAssertEqual(request.itemID, item.id)
    }

    func testCompletedWorkerEventIgnoresUndispatchedItem() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        XCTAssertTrue(supervisor.isCommandDispatched(for: first.id))
        XCTAssertFalse(supervisor.isCommandDispatched(for: second.id))
        transport.emitOutputLine(#"{"event":"completed","itemID":"second","message":"generated large preview"}"#)

        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .running)
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(try transport.commands(), [firstCommand])
    }

    func testFailedWorkerEventIgnoresUndispatchedItem() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: second.id,
            message: "could not render preview"
        )))

        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .running)
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(try transport.commands(), [firstCommand])
    }

    func testSerialWorkerDispatchDoesNotFailBufferedWorkWhenFirstCommandTimesOut() throws {
        let transport = RecordingWorkerTransport()
        let timeoutScheduler = ManualWorkerTimeoutScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport,
            commandTimeout: 30,
            timeoutScheduler: timeoutScheduler
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        XCTAssertEqual(try transport.commands(), [firstCommand])

        timeoutScheduler.fireNext()

        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(transport.launchCount, 2)
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .failed)
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.detail, "Worker command timed out after 30 seconds: generate medium preview for asset-1")
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
    }

    func testWorkerErrorOutputFailsOldestDispatchedItemAndStartsNextQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        transport.emitErrorLine("error could not render preview")

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .failed &&
                supervisor.queue.item(id: first.id)?.detail == "error could not render preview" &&
                supervisor.queue.item(id: second.id)?.status == .running
        })
        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
    }

    func testTimedOutWorkerCommandTerminatesWorkerFailsDispatchedWorkAndStartsNextQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let timeoutScheduler = ManualWorkerTimeoutScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: 30,
            timeoutScheduler: timeoutScheduler
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        timeoutScheduler.fireNext()

        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(transport.launchCount, 2)
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.status, .failed)
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.detail, "Worker command timed out after 30 seconds: generate medium preview for asset-1")
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
    }

    func testTimedOutWorkerCommandReportsCommandContext() throws {
        let transport = RecordingWorkerTransport()
        let timeoutScheduler = ManualWorkerTimeoutScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: 30,
            timeoutScheduler: timeoutScheduler
        )
        let item = BackgroundWorkItem.testItem(id: "preview")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        try supervisor.enqueue(item, command: command)

        timeoutScheduler.fireNext()

        XCTAssertEqual(
            supervisor.queue.item(id: item.id)?.detail,
            "Worker command timed out after 30 seconds: generate medium preview for asset-1"
        )
    }

    func testCompletingWorkerCommandCancelsTimeout() throws {
        let transport = RecordingWorkerTransport()
        let timeoutScheduler = ManualWorkerTimeoutScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: 30,
            timeoutScheduler: timeoutScheduler
        )
        let item = BackgroundWorkItem.testItem(id: "preview")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        try supervisor.enqueue(item, command: command)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: item.id,
            message: "generated medium preview"
        )))
        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: item.id)?.status == .completed
        })
        timeoutScheduler.fireNext()

        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .completed)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.detail, "generated medium preview")
    }

    func testPausingWorkerCommandDoesNotDisableTimeoutForDispatchedWork() throws {
        let transport = RecordingWorkerTransport()
        let timeoutScheduler = ManualWorkerTimeoutScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: 30,
            timeoutScheduler: timeoutScheduler
        )
        let item = BackgroundWorkItem.testItem(id: "preview")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        try supervisor.enqueue(item, command: command)

        try supervisor.pause()
        XCTAssertTrue(supervisor.queue.isPaused)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .running)
        timeoutScheduler.fireNext()

        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .failed)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.detail, "Worker command timed out after 30 seconds: generate medium preview for asset-1")
    }

    func testPauseResumeAndCancelSendExplicitControlCommands() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let item = BackgroundWorkItem.testItem(id: "first")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        try supervisor.enqueue(item, command: command)

        try supervisor.pause()
        XCTAssertTrue(supervisor.queue.isPaused)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .running)

        try supervisor.resume()
        XCTAssertFalse(supervisor.queue.isPaused)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .running)

        try supervisor.cancelAll()
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .cancelled)
        XCTAssertFalse(transport.isRunning)
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(try transport.commands(), [command, .pause, .resume, .cancelAll])
    }

    func testStoppingIdleWorkerProcessTerminatesTransportWithoutChangingQueue() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let item = BackgroundWorkItem.testItem(id: "preview")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        try supervisor.enqueue(item, command: command)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: item.id,
            message: "generated medium preview"
        )))
        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: item.id)?.status == .completed
        })
        let queueBeforeStop = supervisor.queue

        XCTAssertTrue(supervisor.isWorkerProcessRunning)
        XCTAssertTrue(supervisor.canStopIdleWorkerProcess)
        XCTAssertTrue(supervisor.stopIdleWorkerProcess())

        XCTAssertFalse(transport.isRunning)
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(supervisor.queue, queueBeforeStop)
    }

    func testStoppingIdleWorkerProcessDoesNotTerminateActiveWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let item = BackgroundWorkItem.testItem(id: "preview")
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .medium)
        try supervisor.enqueue(item, command: command)

        XCTAssertTrue(supervisor.isWorkerProcessRunning)
        XCTAssertFalse(supervisor.canStopIdleWorkerProcess)
        XCTAssertFalse(supervisor.stopIdleWorkerProcess())

        XCTAssertTrue(transport.isRunning)
        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .running)
    }

    func testCancellingDispatchedItemPreservesQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let importItem = BackgroundWorkItem.testItem(id: "import")
        let previewItem = BackgroundWorkItem.testItem(id: "preview")
        let importCommand = WorkerCommand.importFolder(root: URL(fileURLWithPath: "/Photos", isDirectory: true), duplicateHandling: .importAll)
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        try supervisor.enqueue(importItem, command: importCommand)
        try supervisor.enqueue(previewItem, command: previewCommand)

        try supervisor.cancel(id: importItem.id)

        XCTAssertEqual(supervisor.queue.item(id: importItem.id)?.status, .cancelled)
        XCTAssertEqual(supervisor.queue.item(id: previewItem.id)?.status, .running)
        XCTAssertEqual(transport.launchCount, 2)
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(try transport.commands(), [importCommand, .cancelAll, previewCommand])
    }

    func testCancellingOneOfMultipleDispatchedItemsFailsOtherStoppedDispatchedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 3),
            transport: transport,
            maxDispatchedCommandCount: 2
        )
        let importItem = BackgroundWorkItem.testItem(id: "import")
        let previewItem = BackgroundWorkItem.testItem(id: "preview")
        let queuedItem = BackgroundWorkItem.testItem(id: "queued")
        let importCommand = WorkerCommand.importFolder(root: URL(fileURLWithPath: "/Photos", isDirectory: true), duplicateHandling: .importAll)
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let queuedCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .grid)
        try supervisor.enqueue(importItem, command: importCommand)
        try supervisor.enqueue(previewItem, command: previewCommand)
        try supervisor.enqueue(queuedItem, command: queuedCommand)

        try supervisor.cancel(id: importItem.id)

        XCTAssertEqual(supervisor.queue.item(id: importItem.id)?.status, .cancelled)
        XCTAssertEqual(supervisor.queue.item(id: previewItem.id)?.status, .failed)
        XCTAssertEqual(
            supervisor.queue.item(id: previewItem.id)?.detail,
            "Worker stopped because another command was cancelled: generate grid preview for asset-1"
        )
        XCTAssertEqual(supervisor.queue.item(id: queuedItem.id)?.status, .running)
        XCTAssertFalse(supervisor.isCommandDispatched(for: importItem.id))
        XCTAssertFalse(supervisor.isCommandDispatched(for: previewItem.id))
        XCTAssertTrue(supervisor.isCommandDispatched(for: queuedItem.id))
        XCTAssertEqual(transport.launchCount, 2)
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(try transport.commands(), [importCommand, previewCommand, .cancelAll, queuedCommand])
    }

    func testUnexpectedWorkerTerminationRetriesInFlightItemOnce() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        transport.simulateUnexpectedTermination()

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .running &&
                supervisor.queue.item(id: second.id)?.status == .queued &&
                transport.launchCount == 2
        })
        XCTAssertEqual(try transport.commands(), [firstCommand, firstCommand])
        XCTAssertTrue(supervisor.isCommandDispatched(for: first.id))
    }

    func testSecondUnexpectedWorkerTerminationFailsItemAndStartsNextQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(first, command: firstCommand)
        try supervisor.enqueue(second, command: secondCommand)

        transport.simulateUnexpectedTermination()
        XCTAssertTrue(waitUntil { supervisor.queue.item(id: first.id)?.status == .running && transport.launchCount == 2 })

        transport.simulateUnexpectedTermination()

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .failed &&
                supervisor.queue.item(id: second.id)?.status == .running
        })
        XCTAssertEqual(
            supervisor.queue.item(id: first.id)?.detail,
            "Worker exited unexpectedly: generate grid preview for asset-1"
        )
        XCTAssertEqual(try transport.commands(), [firstCommand, firstCommand, secondCommand])
    }

    func testWorkerTerminationRetryBudgetResetsAfterItemCompletes() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let firstCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)
        try supervisor.enqueue(first, command: firstCommand)

        transport.simulateUnexpectedTermination()
        XCTAssertTrue(waitUntil { supervisor.queue.item(id: first.id)?.status == .running && transport.launchCount == 2 })
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: first.id, message: "done")))
        XCTAssertTrue(waitUntil { supervisor.queue.item(id: first.id)?.status == .completed })

        let second = BackgroundWorkItem.testItem(id: "second")
        let secondCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-2"), level: .large)
        try supervisor.enqueue(second, command: secondCommand)

        // A fresh item that dies once must still get its own retry, not inherit
        // the first item's spent budget.
        transport.simulateUnexpectedTermination()
        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: second.id)?.status == .running
        })
        XCTAssertTrue(supervisor.isCommandDispatched(for: second.id))
    }

    func testFoundationTransportReportsUnexpectedWorkerTermination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-transport-death")
        let scriptURL = root.appendingPathComponent("dying-worker.sh")
        let script = """
        #!/bin/sh
        IFS= read -r line
        exit 1
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        let transport = FoundationWorkerTransport(executableURL: scriptURL)
        var terminationCount = 0
        transport.terminationHandler = { terminationCount += 1 }

        try transport.launch()
        try transport.writeLine("do something\n")

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { terminationCount == 1 },
            "worker process exit did not fire the transport termination handler"
        )
        XCTAssertFalse(transport.isRunning)
    }

    func testFoundationTransportDoesNotReportIntentionalTermination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-transport-intentional")
        let scriptURL = root.appendingPathComponent("idle-worker.sh")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          :
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        let transport = FoundationWorkerTransport(executableURL: scriptURL)
        var terminationCount = 0
        transport.terminationHandler = { terminationCount += 1 }

        try transport.launch()
        XCTAssertTrue(transport.isRunning)
        transport.terminate()

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { !transport.isRunning },
            "worker process did not stop after intentional termination"
        )
        // Give any stray termination callback a chance to (wrongly) fire.
        _ = waitUntil(timeout: 0.5) { terminationCount > 0 }
        XCTAssertEqual(terminationCount, 0, "intentional termination must not be reported as an unexpected exit")
    }

    func testFoundationTransportLaunchesWritesAndTerminatesProcess() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-transport")
        let scriptURL = root.appendingPathComponent("record-worker.sh")
        let outputURL = root.appendingPathComponent("worker-output.txt")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> "$1"
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        let transport = FoundationWorkerTransport(executableURL: scriptURL, arguments: [outputURL.path])

        try transport.launch()
        try transport.writeLine("hello worker\n")

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { file(outputURL, contains: "hello worker") },
            "worker subprocess did not record the line sent through stdin"
        )
        XCTAssertTrue(transport.isRunning)

        transport.terminate()

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { !transport.isRunning },
            "worker subprocess did not terminate after transport termination"
        )
    }

    func testFoundationTransportFramesBareWriteLineInput() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-transport-bare-line")
        let scriptURL = root.appendingPathComponent("record-worker.sh")
        let outputURL = root.appendingPathComponent("worker-output.txt")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> "$1"
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        let transport = FoundationWorkerTransport(executableURL: scriptURL, arguments: [outputURL.path])

        try transport.launch()
        try transport.writeLine("hello worker")

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { file(outputURL, contains: "hello worker") },
            "writeLine should frame input as one newline-delimited worker message"
        )
        transport.terminate()
    }

    func testFoundationTransportReportsWorkerOutputLines() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-transport-output")
        let scriptURL = root.appendingPathComponent("echo-worker.sh")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf 'completed %s\\n' "$line"
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        let transport = FoundationWorkerTransport(executableURL: scriptURL)
        var outputLines: [String] = []
        transport.outputHandler = { outputLines.append($0) }

        try transport.launch()
        try transport.writeLine("hello worker\n")

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { outputLines == ["completed hello worker"] },
            "worker stdout line was not delivered to the transport output handler"
        )
        transport.terminate()
    }

    func testFoundationTransportReportsWorkerErrorLines() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-transport-error")
        let scriptURL = root.appendingPathComponent("error-worker.sh")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf 'error %s\\n' "$line" >&2
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        chmod(scriptURL.path, 0o755)
        let transport = FoundationWorkerTransport(executableURL: scriptURL)
        var errorLines: [String] = []
        transport.errorHandler = { errorLines.append($0) }

        try transport.launch()
        try transport.writeLine("bad preview\n")

        XCTAssertTrue(
            waitUntil(timeout: workerTransportTimeout) { errorLines == ["error bad preview"] },
            "worker stderr line was not delivered to the transport error handler"
        )
        transport.terminate()
    }
}

private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    var terminationHandler: (() -> Void)?

    private(set) var launchCount = 0
    private(set) var terminateCount = 0
    private(set) var lines: [String] = []
    private(set) var isRunning = false

    func launch() throws {
        launchCount += 1
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        lines.append(line)
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func simulateUnexpectedTermination() {
        isRunning = false
        terminationHandler?()
    }

    func commands() throws -> [WorkerCommand] {
        try lines.map { try WorkerProtocolEncoder.decode($0) }
    }

    func requests() throws -> [WorkerCommandRequest] {
        try lines.map { try WorkerProtocolEncoder.decodeRequest($0) }
    }

    func emitOutputLine(_ line: String) {
        outputHandler?(line)
    }

    func emitErrorLine(_ line: String) {
        errorHandler?(line)
    }
}

private final class ManualWorkerTimeoutScheduler: WorkerTimeoutScheduling, @unchecked Sendable {
    private var scheduled: [ManualWorkerTimeoutCancellation] = []

    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any WorkerTimeoutCancellation {
        let cancellation = ManualWorkerTimeoutCancellation(action: action)
        scheduled.append(cancellation)
        return cancellation
    }

    func fireNext() {
        guard !scheduled.isEmpty else { return }
        scheduled.removeFirst().fire()
    }
}

private final class ManualWorkerTimeoutCancellation: WorkerTimeoutCancellation, @unchecked Sendable {
    private var isCancelled = false
    private let action: @Sendable () -> Void

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func fire() {
        guard !isCancelled else { return }
        action()
    }
}

private extension BackgroundWorkItem {
    static func testItem(id: String) -> BackgroundWorkItem {
        BackgroundWorkItem(
            id: WorkSessionID(rawValue: id),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Rendering cached previews",
            completedUnitCount: 0,
            totalUnitCount: 10
        )
    }
}

private let workerTransportTimeout: TimeInterval = 30

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

private func file(_ url: URL, contains expectedText: String) -> Bool {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        return false
    }
    return text.contains(expectedText)
}
