import XCTest
import TeststripCore
@testable import TeststripApp

/// Covers `AppModel.activeWorkKindRows` / `ActivityCenterPresentation.kindRows` -
/// the per-kind Activity rows projection introduced for concurrent per-lane
/// worker execution (Task A2).
final class ActivityCenterPresentationKindRowsTests: XCTestCase {
    func testConcurrentPreviewAndEvalProduceTwoKindRows() {
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
                    status: .queued,
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
            ]
        )

        let rows = model.activityCenterPresentation.kindRows
        XCTAssertEqual(Set(rows.map(\.kind)), [.previewGeneration, .recognition])
        XCTAssertEqual(rows.first { $0.kind == .previewGeneration }?.title, "Generate previews")
    }
}
