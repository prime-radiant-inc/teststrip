import XCTest
import TeststripCore
@testable import TeststripApp

/// Covers `AppModel.cancelWork(kind:)` / `pauseWork(kind:)` / `resumeWork(kind:)` -
/// the per-kind work-control actions the Activity Center's kind rows call (Task A4).
final class PerKindWorkControlTests: XCTestCase {
    func testCancelKindCancelsEveryActiveItemOfThatKindOnly() {
        let model = AppModel.demo()
        model.backgroundWorkQueue = BackgroundWorkQueue(
            maxRunningCount: 8,
            items: [
                BackgroundWorkItem(
                    id: WorkSessionID(rawValue: "prev-1"),
                    kind: .previewGeneration,
                    title: "Generate preview",
                    detail: "",
                    status: .running,
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
                BackgroundWorkItem(
                    id: WorkSessionID(rawValue: "eval-1"),
                    kind: .recognition,
                    title: "Evaluate photo",
                    detail: "",
                    status: .running,
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
                BackgroundWorkItem(
                    id: WorkSessionID(rawValue: "eval-2"),
                    kind: .recognition,
                    title: "Evaluate photo",
                    detail: "",
                    status: .queued,
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
            ]
        )

        model.cancelWork(kind: .recognition)

        let statuses = Dictionary(uniqueKeysWithValues: model.backgroundWorkQueue.items.map { ($0.id.rawValue, $0.status) })
        XCTAssertEqual(statuses["eval-1"], .cancelled)
        XCTAssertEqual(statuses["eval-2"], .cancelled)
        XCTAssertNotEqual(statuses["prev-1"], .cancelled)
    }
}
