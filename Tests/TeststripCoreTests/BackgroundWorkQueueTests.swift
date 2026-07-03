import XCTest
@testable import TeststripCore

final class BackgroundWorkQueueTests: XCTestCase {
    func testQueueStartsOnlyUpToRunningLimit() {
        var queue = BackgroundWorkQueue(maxRunningCount: 2)
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let third = BackgroundWorkItem.testItem(id: "third")

        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(third)
        queue.activateRunnableItems()

        XCTAssertEqual(queue.item(id: first.id)?.status, .running)
        XCTAssertEqual(queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(queue.item(id: third.id)?.status, .queued)
        XCTAssertEqual(queue.runningItems.map(\.id), [first.id, second.id])
    }

    func testCompletingRunningItemStartsNextQueuedItem() {
        var queue = BackgroundWorkQueue(maxRunningCount: 1)
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.activateRunnableItems()

        queue.markCompleted(id: first.id)

        XCTAssertEqual(queue.item(id: first.id)?.status, .completed)
        XCTAssertEqual(queue.item(id: second.id)?.status, .running)
    }

    func testFrontQueuedItemStartsBeforeOlderQueuedItems() {
        var queue = BackgroundWorkQueue(maxRunningCount: 1)
        let running = BackgroundWorkItem.testItem(id: "running")
        let olderQueued = BackgroundWorkItem.testItem(id: "older")
        let visible = BackgroundWorkItem.testItem(id: "visible")
        queue.enqueue(running)
        queue.enqueue(olderQueued)
        queue.activateRunnableItems()

        queue.enqueue(visible, placement: .front)
        queue.markCompleted(id: running.id)

        XCTAssertEqual(queue.item(id: visible.id)?.status, .running)
        XCTAssertEqual(queue.item(id: olderQueued.id)?.status, .queued)
    }

    func testCompletingItemMarksProgressComplete() {
        var queue = BackgroundWorkQueue(maxRunningCount: 1)
        let item = BackgroundWorkItem.testItem(id: "first")
        queue.enqueue(item)
        queue.activateRunnableItems()

        queue.markCompleted(id: item.id)

        XCTAssertEqual(queue.item(id: item.id)?.completedUnitCount, item.totalUnitCount)
    }

    func testFailingRunningItemRecordsDetailAndStartsNextQueuedItem() {
        var queue = BackgroundWorkQueue(maxRunningCount: 1)
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.activateRunnableItems()

        queue.markFailed(id: first.id, detail: "Preview render failed")

        XCTAssertEqual(queue.item(id: first.id)?.status, .failed)
        XCTAssertEqual(queue.item(id: first.id)?.detail, "Preview render failed")
        XCTAssertEqual(queue.item(id: second.id)?.status, .running)
    }

    func testPauseAndResumeControlRunningWork() {
        var queue = BackgroundWorkQueue(maxRunningCount: 2)
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.activateRunnableItems()

        queue.pause()

        XCTAssertTrue(queue.isPaused)
        XCTAssertEqual(queue.item(id: first.id)?.status, .paused)
        XCTAssertEqual(queue.item(id: second.id)?.status, .paused)

        queue.resume()

        XCTAssertFalse(queue.isPaused)
        XCTAssertEqual(queue.item(id: first.id)?.status, .running)
        XCTAssertEqual(queue.item(id: second.id)?.status, .running)
    }

    func testCancelAllStopsQueuedAndRunningWork() {
        var queue = BackgroundWorkQueue(maxRunningCount: 1)
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.activateRunnableItems()

        queue.cancelAll()

        XCTAssertEqual(queue.item(id: first.id)?.status, .cancelled)
        XCTAssertEqual(queue.item(id: second.id)?.status, .cancelled)
        XCTAssertEqual(queue.runningItems, [])
        XCTAssertEqual(queue.queuedItems, [])
    }

    func testCancellingOneItemStartsNextQueuedItem() {
        var queue = BackgroundWorkQueue(maxRunningCount: 1)
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.activateRunnableItems()

        queue.cancel(id: first.id)

        XCTAssertEqual(queue.item(id: first.id)?.status, .cancelled)
        XCTAssertEqual(queue.item(id: second.id)?.status, .running)
        XCTAssertEqual(queue.runningItems.map(\.id), [second.id])
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
