import XCTest
@testable import TeststripCore

// These coalescers gate how often import/scan progress is reported to the
// WorkerSupervisor, which resets its 120s-silence watchdog on every progress
// event (see WorkerSupervisorTests.testProgressWorkerEventReschedulesCommandTimeout).
// Count-based coalescing alone can go far longer than 120s between reports on
// a slow phase (e.g. copying files 11-500 off a card), which trips the
// watchdog on a healthy import. The heartbeat guarantees a report at least
// every `heartbeat` seconds whenever the count has actually advanced.
final class ProgressCoalescerTests: XCTestCase {
    func testIngestProgressCoalescerSuppressesReportsWithinHeartbeatWindow() {
        let clock = MutableClock()
        let coalescer = IngestProgressCoalescer(interval: 500, eagerLimit: 10, heartbeat: 15, now: clock.now)
        let totalCount = 864

        XCTAssertFalse(coalescer.shouldReport(completedCount: 11, totalCount: totalCount))
        clock.advance(by: 5)
        XCTAssertFalse(coalescer.shouldReport(completedCount: 12, totalCount: totalCount))
        clock.advance(by: 9)
        XCTAssertFalse(coalescer.shouldReport(completedCount: 13, totalCount: totalCount))
    }

    func testIngestProgressCoalescerEmitsHeartbeatOnceElapsedAndCountAdvanced() {
        let clock = MutableClock()
        let coalescer = IngestProgressCoalescer(interval: 500, eagerLimit: 10, heartbeat: 15, now: clock.now)
        let totalCount = 864

        XCTAssertFalse(coalescer.shouldReport(completedCount: 11, totalCount: totalCount))
        clock.advance(by: 15)
        XCTAssertTrue(coalescer.shouldReport(completedCount: 12, totalCount: totalCount))

        // The heartbeat window restarts from the report it just emitted.
        XCTAssertFalse(coalescer.shouldReport(completedCount: 13, totalCount: totalCount))
    }

    func testIngestProgressCoalescerAlwaysReportsIntervalMultiplesRegardlessOfClock() {
        let clock = MutableClock()
        let coalescer = IngestProgressCoalescer(interval: 500, eagerLimit: 10, heartbeat: 15, now: clock.now)

        XCTAssertTrue(coalescer.shouldReport(completedCount: 500, totalCount: 864))
    }

    func testIngestProgressCoalescerAlwaysReportsFinalCountRegardlessOfClock() {
        let clock = MutableClock()
        let coalescer = IngestProgressCoalescer(interval: 500, eagerLimit: 10, heartbeat: 15, now: clock.now)

        XCTAssertTrue(coalescer.shouldReport(completedCount: 864, totalCount: 864))
    }

    func testIngestProgressCoalescerNeverReportsRepeatedCountEvenPastHeartbeat() {
        let clock = MutableClock()
        let coalescer = IngestProgressCoalescer(interval: 500, eagerLimit: 10, heartbeat: 15, now: clock.now)
        let totalCount = 864
        XCTAssertTrue(coalescer.shouldReport(completedCount: 500, totalCount: totalCount))

        clock.advance(by: 20)

        XCTAssertFalse(coalescer.shouldReport(completedCount: 500, totalCount: totalCount))
    }

    func testScanProgressCoalescerSuppressesReportsWithinHeartbeatWindow() {
        let clock = MutableClock()
        let coalescer = ScanProgressCoalescer(interval: 100, heartbeat: 15, now: clock.now)

        XCTAssertFalse(coalescer.shouldReportScanCount(2))
        clock.advance(by: 5)
        XCTAssertFalse(coalescer.shouldReportScanCount(3))
        clock.advance(by: 9)
        XCTAssertFalse(coalescer.shouldReportScanCount(4))
    }

    func testScanProgressCoalescerEmitsHeartbeatOnceElapsedAndCountAdvanced() {
        let clock = MutableClock()
        let coalescer = ScanProgressCoalescer(interval: 100, heartbeat: 15, now: clock.now)

        XCTAssertFalse(coalescer.shouldReportScanCount(2))
        clock.advance(by: 15)
        XCTAssertTrue(coalescer.shouldReportScanCount(3))

        XCTAssertFalse(coalescer.shouldReportScanCount(4))
    }

    func testScanProgressCoalescerAlwaysReportsIntervalMultiplesRegardlessOfClock() {
        let clock = MutableClock()
        let coalescer = ScanProgressCoalescer(interval: 100, heartbeat: 15, now: clock.now)

        XCTAssertTrue(coalescer.shouldReportScanCount(100))
    }

    func testScanProgressCoalescerNeverReportsRepeatedCountEvenPastHeartbeat() {
        let clock = MutableClock()
        let coalescer = ScanProgressCoalescer(interval: 100, heartbeat: 15, now: clock.now)
        XCTAssertTrue(coalescer.shouldReportScanCount(100))

        clock.advance(by: 20)

        XCTAssertFalse(coalescer.shouldReportScanCount(100))
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 0)) {
        self.current = start
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock {
            current.addTimeInterval(seconds)
        }
    }

    func now() -> Date {
        lock.withLock {
            current
        }
    }
}
