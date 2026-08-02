import CoreGraphics
import Foundation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class FaceReportStoreTests: XCTestCase {
    private static func report(sharpness: Double, prominence: Double = 0.2) -> FaceReport {
        FaceReport(
            normalizedBounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            eyesOpen: true,
            hasSmile: false,
            sharpness: sharpness,
            light: 0.9,
            facing: 0.9,
            prominence: prominence
        )
    }

    /// A clean face and a ruined one, expressed against the measured bands so
    /// these fixtures cannot drift out from under Task 0's constants.
    private static var cleanReport: FaceReport {
        report(sharpness: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0))
    }

    private static var ruinedReport: FaceReport {
        report(sharpness: FaceReportGrading.redSignalCeiling / 2)
    }

    private static func frame(
        _ id: String,
        generation: Int = 1,
        level: PreviewLevel? = .medium
    ) -> FaceReportSweepFrame {
        FaceReportSweepFrame(
            assetID: AssetID(rawValue: id),
            source: level.map {
                FaceReportPreviewSource(previewURL: URL(fileURLWithPath: "/previews/\(id).jpg"), level: $0)
            },
            previewCacheGeneration: generation
        )
    }

    /// Records every preview URL it is handed, and can be held open on a
    /// chosen URL so a test can act while one analysis is in flight.
    private actor AnalysisRecorder {
        private(set) var calls: [String] = []
        private var gateURL: String?
        private var hasReachedGate = false
        private var gateOpened: CheckedContinuation<Void, Never>?
        private var gateReachedWaiter: CheckedContinuation<Void, Never>?

        func gate(on lastPathComponent: String) {
            gateURL = lastPathComponent
        }

        func analyze(_ url: URL) async -> [FaceReport] {
            calls.append(url.lastPathComponent)
            if url.lastPathComponent == gateURL {
                // Record arrival BEFORE suspending, and resume any waiter that
                // already installed itself. `waitUntilGateReached` checks the
                // flag first, so a gate reached before the waiter arrives can
                // never deadlock the suite.
                hasReachedGate = true
                gateReachedWaiter?.resume()
                gateReachedWaiter = nil
                await withCheckedContinuation { continuation in
                    gateOpened = continuation
                }
            }
            return [FaceReportStoreTests.cleanReport]
        }

        func waitUntilGateReached() async {
            if hasReachedGate { return }
            await withCheckedContinuation { continuation in
                gateReachedWaiter = continuation
            }
        }

        func openGate() {
            gateOpened?.resume()
            gateOpened = nil
        }
    }

    // MARK: - Sweep order

    func testSweepOrderPutsTheCurrentFrameFirstThenRailOrder() {
        let frames = [Self.frame("a"), Self.frame("b"), Self.frame("c")]

        let ordered = FaceReportStore.sweepOrder(frames: frames, currentFrameID: AssetID(rawValue: "c"))

        XCTAssertEqual(ordered.map(\.assetID.rawValue), ["c", "a", "b"])
    }

    func testSweepOrderKeepsRailOrderWhenTheCurrentFrameIsNotInTheRail() {
        let frames = [Self.frame("a"), Self.frame("b")]

        let ordered = FaceReportStore.sweepOrder(frames: frames, currentFrameID: AssetID(rawValue: "z"))

        XCTAssertEqual(ordered.map(\.assetID.rawValue), ["a", "b"])
    }

    @MainActor
    func testSweepAnalyzesTheCurrentFrameBeforeTheRest() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(
            frames: [Self.frame("a"), Self.frame("b"), Self.frame("c")],
            currentFrameID: AssetID(rawValue: "b")
        )

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["b.jpg", "a.jpg", "c.jpg"])
        for id in ["a", "b", "c"] {
            XCTAssertNotNil(
                store.report(for: AssetID(rawValue: id), currentGeneration: 1, bestAvailableLevel: .medium)
            )
        }
    }

    // MARK: - Preview floor, generation, and level

    @MainActor
    func testFramesWithoutAPreviewAtOrAboveTheFloorAreSkipped() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(
            frames: [Self.frame("a"), Self.frame("b", level: nil)],
            currentFrameID: nil
        )

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg"])
        XCTAssertNil(
            store.report(for: AssetID(rawValue: "b"), currentGeneration: 1, bestAvailableLevel: nil)
        )
    }

    func testThePreviewFloorRejectsThumbnailLevelsAndAcceptsEverythingAbove() {
        XCTAssertFalse(FaceReportPreviewFloor.accepts(.micro))
        XCTAssertFalse(FaceReportPreviewFloor.accepts(.grid))
        XCTAssertTrue(FaceReportPreviewFloor.accepts(FaceReportPreviewFloor.lowestAcceptedLevel))
        XCTAssertTrue(FaceReportPreviewFloor.accepts(.original))
    }

    @MainActor
    func testASkippedFrameIsPickedUpOnceAFloorQualityPreviewLands() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("b", level: nil)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("b", generation: 2, level: .medium)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["b.jpg"])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "b"), currentGeneration: 2, bestAvailableLevel: .medium)?
                .previewCacheGeneration,
            2
        )
    }

    @MainActor
    func testAFrameAlreadyComputedAtTheSameGenerationAndLevelIsNotReanalyzed() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("a", generation: 3)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("a", generation: 3)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg"])
    }

    @MainActor
    func testAGenerationBumpInvalidatesTheCachedReport() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("a", generation: 1)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("a", generation: 2)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg", "a.jpg"])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "a"), currentGeneration: 2, bestAvailableLevel: .medium)?
                .previewCacheGeneration,
            2
        )
    }

    // Grades must not flap as previews upgrade: a report measured off a
    // 1600px preview is superseded the moment a 3200px one is cached.
    @MainActor
    func testABetterPreviewLevelInvalidatesTheCachedReport() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        await store.sweep(frames: [Self.frame("a", level: .medium)], currentFrameID: nil)
        await store.sweep(frames: [Self.frame("a", level: .large)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, ["a.jpg", "a.jpg"])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .large)?
                .analyzedLevel,
            .large
        )
    }

    // MARK: - Staleness is enforced on READ, not only on sweep

    @MainActor
    func testAStaleGenerationReadsAsNoReportRatherThanTheCachedEntry() {
        let store = FaceReportStore()

        store.record(
            [Self.cleanReport],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertNotNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .medium))
        XCTAssertNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 2, bestAvailableLevel: .medium))
    }

    @MainActor
    func testAStaleLevelReadsAsNoReportRatherThanTheCachedEntry() {
        let store = FaceReportStore()

        store.record(
            [Self.cleanReport],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .large))
    }

    // MARK: - Cancellation

    @MainActor
    func testCancellationStopsTheSweepAndDiscardsTheInFlightResult() async {
        let recorder = AnalysisRecorder()
        await recorder.gate(on: "a.jpg")
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        let sweep = Task { @MainActor in
            await store.sweep(
                frames: [Self.frame("a"), Self.frame("b"), Self.frame("c")],
                currentFrameID: nil
            )
        }
        await recorder.waitUntilGateReached()
        sweep.cancel()
        await recorder.openGate()
        await sweep.value

        let calls = await recorder.calls
        // The in-flight frame's result is dropped rather than published from
        // a sweep the user already navigated away from...
        XCTAssertNil(store.report(for: AssetID(rawValue: "a"), currentGeneration: 1, bestAvailableLevel: .medium))
        // ...and the frames behind it are never analyzed at all.
        XCTAssertEqual(calls, ["a.jpg"])
        XCTAssertNil(store.report(for: AssetID(rawValue: "b"), currentGeneration: 1, bestAvailableLevel: .medium))
        XCTAssertNil(store.report(for: AssetID(rawValue: "c"), currentGeneration: 1, bestAvailableLevel: .medium))
    }

    // MARK: - Roll-up and the close-ups hand-off

    @MainActor
    func testRecordStoresTheCloseUpsPassResultWithoutAnalyzingAgain() async {
        let recorder = AnalysisRecorder()
        let store = FaceReportStore(analyze: { await recorder.analyze($0) })

        store.record(
            [Self.cleanReport],
            for: AssetID(rawValue: "a"),
            previewCacheGeneration: 4,
            analyzedLevel: .medium
        )
        await store.sweep(frames: [Self.frame("a", generation: 4, level: .medium)], currentFrameID: nil)

        let calls = await recorder.calls
        XCTAssertEqual(calls, [])
        XCTAssertEqual(
            store.report(for: AssetID(rawValue: "a"), currentGeneration: 4, bestAvailableLevel: .medium)?
                .reports.count,
            1
        )
    }

    @MainActor
    func testRolledUpGradeIsTheWorstFaceGrade() {
        let frame = FrameFaceReport(
            reports: [
                Self.cleanReport,
                Self.report(sharpness: (FaceReportGrading.redSignalCeiling + FaceReportGrading.greenSignalFloor) / 2)
            ],
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertEqual(frame.rolledUpGrade, .yellow)
    }

    @MainActor
    func testABackgroundFacesRuinedSignalNeverRollsTheFrameUpToRed() {
        let frame = FrameFaceReport(
            reports: [
                Self.report(sharpness: min(FaceReportGrading.greenSignalFloor + 0.15, 1.0), prominence: 0.3),
                // Ruined, but below the prominence floor.
                Self.report(sharpness: FaceReportGrading.redSignalCeiling / 2, prominence: FaceReportGrading.prominenceFloor / 10)
            ],
            previewCacheGeneration: 1,
            analyzedLevel: .medium
        )

        XCTAssertEqual(frame.rolledUpGrade, .yellow)
    }

    @MainActor
    func testAFrameWithNoFacesHasNoRolledUpGrade() {
        let frame = FrameFaceReport(reports: [], previewCacheGeneration: 1, analyzedLevel: .medium)

        // Absence means "nothing known", never "known good".
        XCTAssertNil(frame.rolledUpGrade)
    }

    @MainActor
    func testAnUncomputedFrameHasNoReportAtAll() {
        let store = FaceReportStore()

        XCTAssertNil(
            store.report(for: AssetID(rawValue: "never-swept"), currentGeneration: 1, bestAvailableLevel: .medium)
        )
    }

    // MARK: - Face detection concurrency gate (cull-028 blocker, Round 2)

    // Thread-safe by a plain lock, not an actor: the tracked closure below
    // runs synchronously (matching CoreImageFaceExpressionAnalyzer's real,
    // non-async signature), so it cannot `await` its way into an actor.
    private final class ConcurrencyTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var maxObserved = 0

        func enter() {
            lock.lock(); defer { lock.unlock() }
            current += 1
            maxObserved = Swift.max(maxObserved, current)
        }

        func exit() {
            lock.lock(); defer { lock.unlock() }
            current -= 1
        }
    }

    // CIDetector's default (`context: nil`) internal CIContext is not
    // documented safe for concurrent access from multiple threads at once.
    // The live VM redrive for cull-028 (blocker-fix-report.md Round 2)
    // proved this is not theoretical: 4 concurrent
    // CoreImageFaceExpressionAnalyzer.detectFaces calls deadlocked outright
    // (0% CPU, no progress, ever) in a standalone reproduction with no
    // Teststrip code involved, where a single call completed in well under a
    // second. FaceDetectionGate must make "at most one call in flight"
    // structural, not incidental -- this test proves that holds even when
    // several callers race it at once.
    func testFaceDetectionGateSerializesConcurrentCalls() async {
        let tracker = ConcurrencyTracker()
        let gate = FaceDetectionGate(detect: { _ in
            tracker.enter()
            // Long enough that six nearly-simultaneous callers would almost
            // certainly overlap if the gate did not serialize them.
            Thread.sleep(forTimeInterval: 0.05)
            tracker.exit()
            return []
        })

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<6 {
                group.addTask {
                    _ = try? await gate.detectFaces(previewURL: URL(fileURLWithPath: "/previews/frame-\(i).jpg"))
                }
            }
        }

        XCTAssertEqual(tracker.maxObserved, 1, "concurrent calls through the gate must never overlap")
    }
}
