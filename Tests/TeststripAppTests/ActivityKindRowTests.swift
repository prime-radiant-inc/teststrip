import XCTest
import TeststripCore
@testable import TeststripApp

final class ActivityKindRowTests: XCTestCase {
    private func activity(_ kind: WorkSessionKind, _ status: WorkSessionStatus, done: Int, total: Int?) -> AppWorkActivity {
        AppWorkActivity(kind: kind, status: status, title: "x", detail: "d", completedUnitCount: done, totalUnitCount: total, failureCount: 0)
    }

    func testGroupsByKindWithSummedCounts() {
        let rows = ActivityKindRow.rows(
            from: [
                activity(.previewGeneration, .running, done: 3, total: 10),
                activity(.recognition, .running, done: 1, total: 30),
                activity(.recognition, .queued, done: 0, total: 30),
            ],
            canPause: true, canResume: false
        )
        XCTAssertEqual(rows.map(\.kind), [.previewGeneration, .recognition]) // stable kind order
        let eval = rows.first { $0.kind == .recognition }!
        XCTAssertEqual(eval.title, "Evaluate photos")
        XCTAssertEqual(eval.completedUnitCount, 1)
        XCTAssertEqual(eval.totalUnitCount, 60)
        XCTAssertEqual(eval.activeItemCount, 2)
        XCTAssertEqual(eval.status, .running) // running wins over queued
    }

    func testRunningDetailComesFromARunningItem() {
        let rows = ActivityKindRow.rows(
            from: [
                activity(.recognition, .queued, done: 0, total: 1),
                AppWorkActivity(kind: .recognition, status: .running, title: "Evaluate photo", detail: "Running apple-vision", completedUnitCount: 0, totalUnitCount: 1, failureCount: 0),
            ],
            canPause: true, canResume: false
        )
        XCTAssertEqual(rows.first?.detail, "Running apple-vision")
    }

    func testTitleMapCoversEveryKind() {
        for kind in WorkSessionKind.allCases {
            XCTAssertFalse(ActivityKindRow.title(for: kind).isEmpty)
        }
    }

    func testTotalUnitCountIsNilWhenAnyItemHasNoTotal() {
        let rows = ActivityKindRow.rows(
            from: [
                activity(.previewGeneration, .running, done: 3, total: 10),
                activity(.previewGeneration, .queued, done: 0, total: nil),
            ],
            canPause: true, canResume: false
        )
        XCTAssertEqual(rows.first?.totalUnitCount, nil)
    }

    func testCanCancelIsFalseWhenEveryItemIsTerminal() {
        let rows = ActivityKindRow.rows(
            from: [
                activity(.previewGeneration, .completed, done: 10, total: 10),
                activity(.previewGeneration, .failed, done: 3, total: 10),
                activity(.previewGeneration, .cancelled, done: 0, total: 10),
            ],
            canPause: true, canResume: false
        )
        XCTAssertEqual(rows.first?.canCancel, false)
    }
}
