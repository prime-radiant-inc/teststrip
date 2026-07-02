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

    func testCompletedWorkerEventCompletesMatchingDispatchedItemOutOfOrder() throws {
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

        transport.emitOutputLine(#"{"event":"completed","itemID":"second","message":"generated large preview"}"#)

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .running &&
                supervisor.queue.item(id: second.id)?.status == .completed
        })
        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
    }

    func testFailedWorkerEventFailsMatchingDispatchedItemOutOfOrder() throws {
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

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .running &&
                supervisor.queue.item(id: second.id)?.status == .failed &&
                supervisor.queue.item(id: second.id)?.detail == "could not render preview"
        })
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
        XCTAssertEqual(supervisor.queue.item(id: first.id)?.detail, "Worker command timed out after 30 seconds")
        XCTAssertEqual(supervisor.queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(try transport.commands(), [firstCommand, secondCommand])
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
        timeoutScheduler.fireNext()

        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .failed)
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.detail, "Worker command timed out after 30 seconds")
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
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .paused)

        try supervisor.resume()
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .running)

        try supervisor.cancelAll()
        XCTAssertEqual(supervisor.queue.item(id: item.id)?.status, .cancelled)
        XCTAssertFalse(transport.isRunning)
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(try transport.commands(), [command, .pause, .resume, .cancelAll])
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

        XCTAssertTrue(waitUntil { file(outputURL, contains: "hello worker") })
        XCTAssertTrue(transport.isRunning)

        transport.terminate()

        XCTAssertTrue(waitUntil { !transport.isRunning })
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

        XCTAssertTrue(waitUntil { outputLines == ["completed hello worker"] })
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

        XCTAssertTrue(waitUntil { errorLines == ["error bad preview"] })
        transport.terminate()
    }
}

private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?

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
