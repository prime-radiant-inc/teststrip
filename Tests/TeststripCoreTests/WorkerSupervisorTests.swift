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

    func testCompletedWorkerOutputCompletesOldestDispatchedItemAndStartsNextQueuedWork() throws {
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

        transport.emitOutputLine("completed generated medium preview for asset-1")

        XCTAssertTrue(waitUntil {
            supervisor.queue.item(id: first.id)?.status == .completed &&
                supervisor.queue.item(id: second.id)?.status == .running
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

    func emitOutputLine(_ line: String) {
        outputHandler?(line)
    }

    func emitErrorLine(_ line: String) {
        errorHandler?(line)
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
