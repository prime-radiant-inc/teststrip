import Observation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// cull-028 live VM run blocker (.superpowers/sdd/2026-08-01-face-report-cards/
// task-9-report.md): a fresh isolated launch never populated the close-ups
// panel or the burst-rail dots even after a qualifying .medium/.large preview
// landed on disk, while a control run (kill + relaunch against a directory
// where the preview already existed at process start) rendered correctly on
// the first poll. That isolates the defect to previews completing AFTER the
// frame is already selected/rendered.
//
// Both consumers (`CloseUpsRefreshKey` in `closeUpsRail` and
// `FaceReportSweepKey` in `cullingStackRail`, LibraryGridView.swift) build
// their `.task(id:)` keys from exactly two `AppModel` accessors:
// `previewCacheGeneration(for:)` and `faceReportPreviewSource(for:)`. This
// reproduces the view-call order in-process against those two accessors
// directly: read `faceReportPreviewSource` once before any preview exists
// (as every render of `currentFaceReport`/`faceReportSweepKey` does), then
// land the worker's completion event exactly as the real preview pipeline
// does, and assert both accessors observe the new state afterward.
final class FaceReportPreviewCompletionTests: XCTestCase {
    // Immediate-flush configuration (no publication coalescing): isolates the
    // caching/generation-bump mechanism itself from the 0.25s async
    // coalescing timer the real app uses. maxDispatchedCommandCount is raised
    // so select()'s own collateral XMP-check request (enqueueMetadataSyncCheck)
    // can dispatch alongside the preview request instead of contending for a
    // single lane -- matching production (AppCatalog.swift's real
    // maxDispatchedCommandCount: 8), and keeping this test about the
    // preview-completion path, not queue-lane contention (already covered by
    // WorkerSupervisorTests/CullPrefetchDriverTests).
    @MainActor
    func testFaceReportPreviewSourceObservesCompletionAfterPriorNilReadWithImmediateFlush() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport,
            maxDispatchedCommandCount: 4
        )
        let asset = try makeOnlineAsset(id: "face-report-completion-immediate")
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "face-report-completion-immediate",
            assets: [asset],
            workerSupervisor: supervisor,
            seedsLargePreviews: false
        )
        model.select(asset.id)

        // The view reads faceReportPreviewSource on every render, including
        // before any preview exists -- exactly what `currentFaceReport(for:)`
        // (LibraryGridView.swift:4192-4198) and `faceReportSweepKey(for:)`
        // (:4810-4818) do. This is the read that must not permanently poison
        // the memoized lookup.
        XCTAssertNil(model.faceReportPreviewSource(for: asset.id))
        let initialGeneration = model.previewCacheGeneration(for: asset.id)
        XCTAssertEqual(initialGeneration, 0)

        // The floor-level request the close-ups pass needs (requestVisibleCullPreview
        // additionally requests .large, an orthogonal upgrade already covered
        // elsewhere -- see CullPrefetchDriverTests/StackDecisionTests).
        try model.requestPreview(assetID: asset.id, level: .medium, placement: .front)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium")
        try await waitForBackgroundWorkStatus(.running, itemID: itemID, in: model)

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertEqual(
            model.previewCacheGeneration(for: asset.id),
            initialGeneration + 1,
            "worker completion must bump the published generation the view's task is keyed on"
        )
        let source = model.faceReportPreviewSource(for: asset.id)
        XCTAssertNotNil(source, "the memoized nil must not survive the completion that made a preview available")
        XCTAssertEqual(source?.level, .medium)
    }

    // Matches production exactly: AppCatalog.loadModel wires
    // backgroundWorkPublicationInterval to the 0.25s coalescing constant, so
    // the generation bump and the cache clear land asynchronously via a timer
    // rather than inline in the worker-completion call stack.
    @MainActor
    func testFaceReportPreviewSourceObservesCompletionAfterPriorNilReadWithCoalescedFlush() async throws {
        let scheduler = ManualBackgroundWorkPublicationScheduler()
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport,
            maxDispatchedCommandCount: 4
        )
        let asset = try makeOnlineAsset(id: "face-report-completion-coalesced")
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "face-report-completion-coalesced",
            assets: [asset],
            workerSupervisor: supervisor,
            seedsLargePreviews: false,
            backgroundWorkPublicationInterval: 0.25,
            backgroundWorkPublicationScheduler: scheduler
        )
        model.select(asset.id)

        XCTAssertNil(model.faceReportPreviewSource(for: asset.id))
        let initialGeneration = model.previewCacheGeneration(for: asset.id)

        try model.requestPreview(assetID: asset.id, level: .medium, placement: .front)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium")
        // requestPreview's own syncBackgroundWorkQueueFromSupervisor() call
        // schedules its own (unrelated) coalesced publish -- flush it now to
        // reach a clean, quiescent baseline before the completion under test,
        // exactly as the real 0.25s timer would have done well before a
        // multi-second-later worker completion.
        XCTAssertEqual(scheduler.scheduledActions.count, 1)
        scheduler.fireScheduledActions()
        XCTAssertEqual(model.previewCacheGeneration(for: asset.id), initialGeneration)

        // Poison the memoized lookup again now that the baseline flush wiped
        // it clean -- the preview still doesn't exist yet, so this is the
        // same nil-before-existence read every render performs.
        XCTAssertNil(model.faceReportPreviewSource(for: asset.id))

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitUntil { scheduler.scheduledActions.count == 1 }

        // Re-render BETWEEN the completion landing (generation bumped
        // internally) and the coalesced flush actually running: exactly what
        // a SwiftUI re-render for any unrelated reason would do while the
        // 0.25s timer is still pending. Both accessors must still read the
        // OLD (pre-completion) state consistently until the flush.
        XCTAssertEqual(model.previewCacheGeneration(for: asset.id), initialGeneration)
        XCTAssertNil(model.faceReportPreviewSource(for: asset.id))

        scheduler.fireScheduledActions()

        XCTAssertEqual(
            model.previewCacheGeneration(for: asset.id),
            initialGeneration + 1,
            "the coalesced flush must bump the published generation the view's task is keyed on"
        )
        let source = model.faceReportPreviewSource(for: asset.id)
        XCTAssertNotNil(source, "the memoized nil must not survive the flush that made a preview available")
        XCTAssertEqual(source?.level, .medium)
    }

    // SwiftUI's `.task(id:)` only re-evaluates its id expression (and thus
    // notices previewCacheGeneration/faceReportPreviewSource changed) because
    // Observation's `withObservationTracking` fires `onChange` after a render
    // read those two accessors. This exercises that exact mechanism directly
    // -- the same primitive SwiftUI's renderer uses under the hood -- rather
    // than assuming a changed return value implies a fired notification.
    @MainActor
    func testObservationFiresAfterTrackingBothSweepKeyAccessorsThenCompletionFlushes() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport,
            maxDispatchedCommandCount: 4
        )
        let asset = try makeOnlineAsset(id: "face-report-completion-observation")
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "face-report-completion-observation",
            assets: [asset],
            workerSupervisor: supervisor,
            seedsLargePreviews: false
        )
        model.select(asset.id)

        let notified = ObservationChangeFlag()
        withObservationTracking {
            // Exactly the two reads faceReportSweepKey(for:)/CloseUpsRefreshKey's
            // construction perform, in the same order.
            _ = model.previewCacheGeneration(for: asset.id)
            _ = model.faceReportPreviewSource(for: asset.id)
        } onChange: {
            notified.value = true
        }

        try model.requestPreview(assetID: asset.id, level: .medium, placement: .front)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium")
        try await waitForBackgroundWorkStatus(.running, itemID: itemID, in: model)

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertTrue(
            notified.value,
            "a tracking scope that read the sweep key's two accessors must be notified once the completion's flush bumps the generation -- otherwise SwiftUI's .task(id:) never re-evaluates its key and the view is stuck forever"
        )
    }

    // Full fidelity to the real call chain AND the real supervisor
    // configuration: requestVisibleCullPreview (not the lower-level
    // requestPreview) is exactly what LoupeContentKey's task calls, and it
    // requests BOTH .medium and .large (requestVisibleLoupeAssetPreview,
    // AppModel.swift:9389-9408). Critically, AppCatalog.managedWorkerKindRunningLimits
    // caps .previewGeneration at 1 concurrent item -- so unlike the generous-
    // concurrency tests above, .large stays QUEUED (not running) behind
    // .medium in the real app, and only starts once .medium's completion
    // frees the lane. This reproduces that exact serialization.
    @MainActor
    func testFaceReportPreviewSourceObservesBothMediumAndLargeCompletionsWithProductionKindLimits() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: AppCatalog.managedWorkerKindRunningLimits),
            transport: transport,
            maxDispatchedCommandCount: 8
        )
        let asset = try makeOnlineAsset(id: "face-report-completion-kind-limited")
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "face-report-completion-kind-limited",
            assets: [asset],
            workerSupervisor: supervisor,
            seedsLargePreviews: false
        )
        model.select(asset.id)

        XCTAssertNil(model.faceReportPreviewSource(for: asset.id))
        let initialGeneration = model.previewCacheGeneration(for: asset.id)

        // The exact method LoupeContentKey's .task calls.
        try model.requestVisibleCullPreview(assetID: asset.id)
        let mediumItemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium")
        let largeItemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-large")
        try await waitForBackgroundWorkStatus(.running, itemID: mediumItemID, in: model)
        // .large is enqueued but the previewGeneration kind limit (1) keeps it
        // queued behind the running .medium item.
        XCTAssertEqual(model.backgroundWorkQueue.item(id: largeItemID)?.status, .queued)

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: mediumItemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: mediumItemID, in: model)

        XCTAssertEqual(model.previewCacheGeneration(for: asset.id), initialGeneration + 1)
        XCTAssertEqual(model.faceReportPreviewSource(for: asset.id)?.level, .medium)

        // Freed by .medium's completion -- now running.
        try await waitForBackgroundWorkStatus(.running, itemID: largeItemID, in: model)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: largeItemID, message: "rendered")))
        try await waitForBackgroundWorkStatus(.completed, itemID: largeItemID, in: model)

        XCTAssertEqual(
            model.previewCacheGeneration(for: asset.id),
            initialGeneration + 2,
            "the large completion must ALSO bump the generation so the panel re-analyzes at the better level"
        )
        XCTAssertEqual(model.faceReportPreviewSource(for: asset.id)?.level, .large)
    }

    // MARK: - Fixtures

    // `requestVisibleCullPreview`'s own staged-asset request path (unlike the
    // prefetch-window siblings) re-probes availability against the real
    // original file (AppModel.refreshAvailability ->
    // SourceAvailabilityProbe), so a fixture with a nonexistent path gets
    // silently marked `.missing` and never requests a preview. The original
    // must actually exist on disk with a fingerprint that matches.
    private func makeOnlineAsset(id: String) throws -> Asset {
        let originalURL = try makeTemporaryDirectory(named: "originals-\(id)")
            .appendingPathComponent("\(id).jpg")
        try Data("original".utf8).write(to: originalURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: originalURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: size, modificationDate: modificationDate),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    @MainActor
    private func waitForBackgroundWorkStatus(
        _ status: WorkSessionStatus,
        itemID: WorkSessionID,
        in model: AppModel
    ) async throws {
        try await waitUntil { model.backgroundWorkQueue.item(id: itemID)?.status == status }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for condition")
    }

}

/// Records the JSON-lines commands `WorkerSupervisor` would send to the
/// out-of-process worker without ever completing them on its own, so tests
/// can drive terminal events (`.completed`/`.failed`) at exactly the moment
/// they want. Mirrors StackDecisionTests'/AppModelTests' private type of the
/// same name (kept local per file per Swift's file-private access).
private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    var terminationHandler: (() -> Void)?

    private(set) var lines: [String] = []
    private(set) var terminateCount = 0
    private(set) var isRunning = false

    func launch() throws {
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

/// Mirrors AppModelTests' private scheduler test double of the same name
/// (kept local per file per Swift's file-private access): records scheduled
/// flush actions instead of running them on a real timer, so a test can fire
/// the coalesced publication at exactly the moment it wants.
private final class ManualBackgroundWorkPublicationScheduler: WorkerTimeoutScheduling, @unchecked Sendable {
    private(set) var scheduledActions: [@Sendable () -> Void] = []

    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any WorkerTimeoutCancellation {
        scheduledActions.append(action)
        return ManualBackgroundWorkPublicationCancellation()
    }

    func fireScheduledActions() {
        let actions = scheduledActions
        scheduledActions = []
        for action in actions {
            action()
        }
    }
}

private final class ManualBackgroundWorkPublicationCancellation: WorkerTimeoutCancellation, @unchecked Sendable {
    func cancel() {}
}

/// Mirrors AppModelTests' private helper of the same name (kept local per
/// file per Swift's file-private access): a `withObservationTracking` onChange
/// sink a test can poll/assert on the main actor after triggering a mutation.
private final class ObservationChangeFlag: @unchecked Sendable {
    var value = false
}
