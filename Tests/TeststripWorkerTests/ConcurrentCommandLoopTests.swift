import TeststripCore
import XCTest

final class ConcurrentCommandLoopTests: XCTestCase {
    /// Proves the loop runs commands concurrently: lane A blocks mid-flight while
    /// lane B is submitted after it, yet B's terminal event is written first. A
    /// serial loop would deadlock here — A would hold the only worker while
    /// waiting on a signal that only fires after B is written.
    func testSecondLaneCompletesWhileFirstLaneBlocks() {
        let laneAMayFinish = DispatchSemaphore(value: 0)
        let laneBWritten = expectation(description: "lane B terminal event written")
        let written = RecordedLines()

        let loop = WorkerCommandLoop(
            execute: { request in
                if request.itemID?.rawValue == "A" {
                    laneAMayFinish.wait()
                    return "completed A"
                }
                return "completed B"
            },
            writeLine: { line in
                written.append(line)
                if line == "completed B" {
                    laneBWritten.fulfill()
                }
            }
        )

        loop.submit(request(itemID: "A", command: .generatePreview(assetID: AssetID(rawValue: "a"), level: .grid)))
        loop.submit(request(itemID: "B", command: .runEvaluation(assetID: AssetID(rawValue: "b"), provider: "test")))

        wait(for: [laneBWritten], timeout: 5)
        XCTAssertEqual(written.snapshot(), ["completed B"], "lane B must finish while lane A is still blocked")

        laneAMayFinish.signal()
        loop.drain()
        XCTAssertEqual(written.snapshot(), ["completed B", "completed A"])
    }

    private func request(itemID: String, command: WorkerCommand) -> WorkerCommandRequest {
        WorkerCommandRequest(command: command, itemID: WorkSessionID(rawValue: itemID))
    }
}

private final class RecordedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
