# Blaze-Through Correctness (SP-C, kata #10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warm the frames a blazing cull run is about to land on, and turn a render-gated Return into an armed commit that fires the moment the staged frame's preview lands.

**Architecture:** A pure warm-set planner (`CullPrefetchPlanner`) feeds a driver in `AppModel` that routes every prefetch through the existing gated `requestPreview` path and cancels undispatched leftovers when the window slides. The armed commit is a single piece of `AppModel` state set by the existing render gate, fired from the existing worker-completion path, and disarmed by any other input. Spec: `docs/superpowers/specs/2026-07-30-blaze-through-correctness-design.md`.

**Tech Stack:** Swift 6 / SwiftPM, XCTest, existing `WorkerSupervisor`/`BackgroundWorkQueue` plumbing. No new dependencies.

## Global Constraints

- Toast copy, verbatim: armed = `Rendering full preview… will keep when ready`; refusal/failure = `Preview unavailable — not committed`. (`…` is U+2026, `—` is U+2014, same characters the codebase already uses.)
- Warm window, exactly: every frame of the staged burst radiating outward from the staged frame (following frames first in rail order, then earlier frames nearest-first), then the landing frames of the next **3** stacks in order, then the previous stack's landing frame. All at `.large`.
- Every prefetch request must pass the stored-availability gate (`asset.availability.isAvailableForPreviewGeneration`), the attempt cap (`previewGenerationAttemptsExhausted`), and the on-disk short-circuit, at `placement: .back`. No new request path.
- No changes to `BackgroundWorkQueue`, the worker protocol, `PreviewPriority` (stays unconsumed), or the catalog schema.
- The armed commit reuses `promoteCurrentFrameAndRejectSiblings` unchanged: same force-pick semantics, same single undo group, same disclosure toast, provenance `user`. It fires at most once, and disarms on any other culling shortcut, any selection change, leaving the cull loupe, or a render failure for the armed frame.
- Non-cull loupe keeps the existing deck-order ±1 neighbor prefetch untouched.
- TDD for every task: write the failing test, show it fail, implement, show it pass. Full suite (`swift test`) green before each commit.
- Work on branch `feat/blaze-through` in a worktree under `.worktrees/`.

---

### Task 1: `CullPrefetchPlanner` warm-set function

**Files:**
- Create: `Sources/TeststripApp/CullPrefetchPlanner.swift`
- Test: `Tests/TeststripAppTests/CullPrefetchPlannerTests.swift`

**Interfaces:**
- Consumes: `AssetStack` (TeststripCore; `assetIDs: [AssetID]`, `init(assetIDs:)`), `AssetID`.
- Produces: `CullPrefetchPlanner.warmAssetIDs(stops:stagedAssetID:nextStackCount:landingAssetID:) -> [AssetID]` — Task 2's driver calls exactly this signature.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-C: the warm-set planner is pure priority ordering — the staged burst
// radiating outward (forward first), then the next stacks' landing frames,
// then one landing back. The driver turns this into gated queue requests.
final class CullPrefetchPlannerTests: XCTestCase {
    private func id(_ raw: String) -> AssetID { AssetID(rawValue: raw) }
    private func stack(_ raws: [String]) -> AssetStack { AssetStack(assetIDs: raws.map(id)) }

    // stops: [x] [a b c d e] [f g] [h] [i j] with staged = c
    private var stops: [AssetStack] {
        [stack(["x"]), stack(["a", "b", "c", "d", "e"]), stack(["f", "g"]), stack(["h"]), stack(["i", "j"])]
    }

    func testRadiatesOutwardFromStagedFrameForwardFirst() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("c"),
            landingAssetID: { $0.assetIDs.first }
        )
        // Burst first: staged, then following in rail order, then earlier nearest-first.
        XCTAssertEqual(Array(warm.prefix(5)), [id("c"), id("d"), id("e"), id("b"), id("a")])
    }

    func testAppendsNextThreeLandingsThenPreviousLanding() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("c"),
            landingAssetID: { $0.assetIDs.first }
        )
        XCTAssertEqual(Array(warm.suffix(4)), [id("f"), id("h"), id("i"), id("x")])
    }

    func testFirstStopHasNoPreviousEntry() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("x"),
            landingAssetID: { $0.assetIDs.first }
        )
        XCTAssertEqual(warm, [id("x"), id("a"), id("f"), id("h")])
    }

    func testLastStopHasNoNextEntries() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("j"),
            landingAssetID: { $0.assetIDs.first }
        )
        XCTAssertEqual(warm, [id("j"), id("i"), id("h")])
    }

    func testStagedAssetOutsideEveryStopReturnsEmpty() {
        XCTAssertEqual(
            CullPrefetchPlanner.warmAssetIDs(
                stops: stops,
                stagedAssetID: id("nope"),
                landingAssetID: { $0.assetIDs.first }
            ),
            []
        )
    }

    func testNilLandingsAreSkippedAndDuplicatesDeduped() {
        // Landing resolver that punts on "h" and (artificially) lands "i j"
        // on the staged frame — the planner must skip the nil and dedup the
        // repeat instead of double-queuing.
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("c"),
            landingAssetID: { s in
                if s.assetIDs.contains(self.id("h")) { return nil }
                if s.assetIDs.contains(self.id("i")) { return self.id("c") }
                return s.assetIDs.first
            }
        )
        XCTAssertEqual(warm, [id("c"), id("d"), id("e"), id("b"), id("a"), id("f"), id("x")])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CullPrefetchPlannerTests 2>&1 | tail -20`
Expected: FAIL to compile — `CullPrefetchPlanner` not defined. Capture the transcript (this is the red proof).

- [ ] **Step 3: Write the implementation**

```swift
import TeststripCore

// SP-C: the warm set for blaze-through culling. Pure — AppModel's driver
// turns these into gated queue requests. Order is priority order: the
// staged burst radiating outward (forward first, since culling moves
// forward), then the next stacks' landing frames so → lands warm, then one
// landing back so a single ← does too.
enum CullPrefetchPlanner {
    static func warmAssetIDs(
        stops: [AssetStack],
        stagedAssetID: AssetID,
        nextStackCount: Int = 3,
        landingAssetID: (AssetStack) -> AssetID?
    ) -> [AssetID] {
        guard let stopIndex = stops.firstIndex(where: { $0.assetIDs.contains(stagedAssetID) }) else {
            return []
        }
        var ordered: [AssetID] = [stagedAssetID]
        let frames = stops[stopIndex].assetIDs
        if let frameIndex = frames.firstIndex(of: stagedAssetID) {
            ordered.append(contentsOf: frames[(frameIndex + 1)...])
            ordered.append(contentsOf: frames[..<frameIndex].reversed())
        }
        if nextStackCount > 0 {
            for nextIndex in (stopIndex + 1)...(stopIndex + nextStackCount) where stops.indices.contains(nextIndex) {
                if let landing = landingAssetID(stops[nextIndex]) {
                    ordered.append(landing)
                }
            }
        }
        if stops.indices.contains(stopIndex - 1), let landing = landingAssetID(stops[stopIndex - 1]) {
            ordered.append(landing)
        }
        var seen = Set<AssetID>()
        return ordered.filter { seen.insert($0).inserted }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CullPrefetchPlannerTests 2>&1 | tail -5`
Expected: all 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/CullPrefetchPlanner.swift Tests/TeststripAppTests/CullPrefetchPlannerTests.swift
git commit -m "feat: pure warm-set planner for blaze-through cull prefetch (SP-C)"
```

---

### Task 2: Cull prefetch driver with window-slide cancellation

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (near `prefetchLoupeNeighborLargePreviews`, ~line 9310)
- Modify: `Sources/TeststripApp/LibraryGridView.swift:3894-3899` (the loupe `.task` block)
- Test: `Tests/TeststripAppTests/CullPrefetchDriverTests.swift`

**Interfaces:**
- Consumes: `CullPrefetchPlanner.warmAssetIDs(stops:stagedAssetID:nextStackCount:landingAssetID:)` from Task 1; existing `requestPreview(assetID:level:placement:)`, `previewGenerationAttemptsExhausted(assetID:level:)`, `cullingStopSequence()`, `recommendedStackLandingAssetID(for:)`, `Self.previewWorkItemID(assetID:level:)`, `Self.isActiveBackgroundWorkStatus(_:)`, `workerSupervisor.cancel(id:)` (throws), `syncBackgroundWorkQueueFromSupervisor()`.
- Produces: `public func requestVisibleCullPreview(assetID: AssetID) throws` — Task 3's tests and the view call this.

**Background you need:** `requestPreview` short-circuits if the file exists, dedups against active queue items, and enqueues `.generatePreview(assetID:level:)` with item ID `preview-<assetID>-<level>` (`AppModel.swift:10490`). `requestVisibleLoupeAssetPreview` probes availability with `refreshAvailability(for:)`, which stats the original file — in tests with fabricated original paths the *staged* asset flips to `.missing` and its own visible request is skipped. That is expected; assert prefetch behavior on **siblings and landings**, whose stored availability stays `.online`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripAppTests/CullPrefetchDriverTests.swift`. Copy the private helpers `makeAsset`, `technicalMetadata`, `makeTemporaryDirectory`, and `writePreviewPlaceholder` verbatim from `Tests/TeststripAppTests/StackDecisionTests.swift:580-657`, then add this model helper (a supervisor-and-no-seeded-previews variant of the same pattern):

```swift
private func makeModel(
    named name: String,
    assets: [Asset],
    supervisor: WorkerSupervisor
) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
    let directory = try makeTemporaryDirectory(named: name)
    let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)
    try repository.upsert(assets)
    let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
    let catalog = AppCatalog(
        paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
        repository: repository,
        previewCache: previewCache,
        importService: LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
            previewCache: previewCache
        )
    )
    let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
    return (model, repository, previewCache)
}

private func previewItemID(_ assetID: String) -> WorkSessionID {
    WorkSessionID(rawValue: "preview-\(assetID)-large")
}
```

(If `AppModel.load(catalog:workerSupervisor:)` differs in signature, mirror how `Tests/TeststripAppTests/AppModelTests.swift:3629` builds a supervisor-backed model.)

Fixture for every test: one burst of four (captures 1s apart, like `StackDecisionTests`), then three singletons 30s+ apart (`solo-1`, `solo-2`, `solo-3`), then a final burst of two — so the stop sequence is `[burst-1..4] [solo-1] [solo-2] [solo-3] [burst-5..6]`. Supervisor: `WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: RecordingWorkerTransport())`.

Test cases:

```swift
func testCullPreviewRequestWarmsBurstSiblingsAndNextLandings() throws {
    // select burst frame 2, then:
    try model.requestVisibleCullPreview(assetID: id("burst-2"))
    let previewItems = model.backgroundWorkQueue.items.filter { $0.kind == .previewGeneration }
    let itemIDs = Set(previewItems.map(\.id))
    // Siblings warm...
    XCTAssertTrue(itemIDs.contains(previewItemID("burst-3")))
    XCTAssertTrue(itemIDs.contains(previewItemID("burst-4")))
    XCTAssertTrue(itemIDs.contains(previewItemID("burst-1")))
    // ...and the next three stops' landings, plus no fourth-stop reach.
    XCTAssertTrue(itemIDs.contains(previewItemID("solo-1")))
    XCTAssertTrue(itemIDs.contains(previewItemID("solo-2")))
    XCTAssertTrue(itemIDs.contains(previewItemID("solo-3")))
    XCTAssertFalse(itemIDs.contains(previewItemID("burst-5")))
}

func testWindowSlideCancelsUndispatchedOutOfWindowItems() throws {
    try model.requestVisibleCullPreview(assetID: id("burst-2"))
    // Slide far forward: burst-5 window no longer wants burst-1..4 warming.
    try model.requestVisibleCullPreview(assetID: id("burst-5"))
    let queue = model.backgroundWorkQueue
    // Undispatched stragglers from the old window are cancelled…
    XCTAssertEqual(queue.item(id: previewItemID("burst-3"))?.status, .cancelled)
    XCTAssertEqual(queue.item(id: previewItemID("burst-4"))?.status, .cancelled)
    // …the one already running is left to finish (maxRunningCount 1 ran the first)…
    XCTAssertEqual(queue.runningItems.count, 1)
    // …and the new window is queued.
    XCTAssertNotEqual(queue.item(id: previewItemID("burst-6"))?.status, .cancelled)
    XCTAssertNotNil(queue.item(id: previewItemID("burst-6")))
}

func testOfflineSiblingIsNeverRequested() throws {
    // Build burst-3 with availability: .offline in the fixture for this test.
    try model.requestVisibleCullPreview(assetID: id("burst-2"))
    XCTAssertNil(model.backgroundWorkQueue.item(id: previewItemID("burst-3")))
}

func testAttemptExhaustedSiblingIsNeverRequested() throws {
    for _ in 0..<3 {
        try repository.recordPreviewGenerationFailure(assetID: id("burst-3"), level: .large, errorMessage: "boom")
    }
    try model.requestVisibleCullPreview(assetID: id("burst-2"))
    XCTAssertNil(model.backgroundWorkQueue.item(id: previewItemID("burst-3")))
}

func testAlreadyCachedSiblingIsNeverRequested() throws {
    try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: id("burst-3"), level: .large)))
    try model.requestVisibleCullPreview(assetID: id("burst-2"))
    XCTAssertNil(model.backgroundWorkQueue.item(id: previewItemID("burst-3")))
}
```

(Adapt the sketches into complete tests with the shared fixture builder; keep each assertion set as written. `id(_:)` wraps `AssetID(rawValue:)`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CullPrefetchDriverTests 2>&1 | tail -20`
Expected: FAIL to compile — `requestVisibleCullPreview` not defined. Capture the transcript.

- [ ] **Step 3: Implement the driver in AppModel**

Add below `prefetchLoupeNeighborLargePreviews` (AppModel.swift ~9323), and add the tracking property beside the model's other private state:

```swift
// SP-C: queue items the cull prefetch planner enqueued, so a window slide
// can cancel undispatched stragglers without touching work other paths
// requested. In-flight renders are left to finish.
private var cullPrefetchItemIDs: Set<WorkSessionID> = []

// The cull loupe's per-frame request: the visible frame at .front (same as
// plain loupe), then the blaze-through warm window at .back. Replaces the
// deck-order ±1 neighbor prefetch, which warms the wrong frames in a burst.
public func requestVisibleCullPreview(assetID: AssetID) throws {
    try requestVisibleLoupeAssetPreview(assetID: assetID)
    try refreshCullPrefetchWindow(around: assetID)
}

private func refreshCullPrefetchWindow(around assetID: AssetID) throws {
    guard workerSupervisor != nil else { return }
    let wants = CullPrefetchPlanner.warmAssetIDs(
        stops: cullingStopSequence(),
        stagedAssetID: assetID,
        landingAssetID: { [weak self] stack in self?.recommendedStackLandingAssetID(for: stack) }
    )
    let desiredItemIDs = Set(wants.map { Self.previewWorkItemID(assetID: $0, level: .large) })
    for staleItemID in cullPrefetchItemIDs.subtracting(desiredItemIDs) {
        if currentBackgroundWorkQueue.item(id: staleItemID)?.status == .queued {
            try workerSupervisor?.cancel(id: staleItemID)
        }
        cullPrefetchItemIDs.remove(staleItemID)
    }
    for wantedAssetID in wants {
        guard previewURL(for: wantedAssetID, levels: [.large]) == nil else { continue }
        guard let asset = assets.first(where: { $0.id == wantedAssetID }),
              asset.availability.isAvailableForPreviewGeneration else { continue }
        guard try !previewGenerationAttemptsExhausted(assetID: wantedAssetID, level: .large) else { continue }
        try requestPreview(assetID: wantedAssetID, level: .large, placement: .back)
        let itemID = Self.previewWorkItemID(assetID: wantedAssetID, level: .large)
        if let status = currentBackgroundWorkQueue.item(id: itemID)?.status,
           Self.isActiveBackgroundWorkStatus(status) {
            cullPrefetchItemIDs.insert(itemID)
        }
    }
    syncBackgroundWorkQueueFromSupervisor()
}
```

- [ ] **Step 4: Swap the cull call site in LibraryGridView**

At `LibraryGridView.swift:3894-3899`, route cull chrome through the new entry:

```swift
.task(id: LoupeContentKey(assetID: asset.id.rawValue, showsCullChrome: presentation.showsCullChrome)) {
    do {
        if presentation.showsCullChrome {
            try model.requestVisibleCullPreview(assetID: asset.id)
        } else {
            try model.requestVisibleLoupePreview(assetID: asset.id)
        }
    } catch {
        model.errorMessage = error.localizedDescription
    }
    if presentation.showsCullChrome {
        await refreshCloseUps(for: asset.id)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CullPrefetchDriverTests 2>&1 | tail -5`
Expected: all 5 PASS.

- [ ] **Step 6: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: green (baseline was 2257 passing / 15 skipped; no new failures).

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/CullPrefetchDriverTests.swift
git commit -m "feat: sliding-window burst prefetch for the cull loupe (SP-C)"
```

---

### Task 3: Armed Return commit

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` — the render gate (`promoteCurrentFrameAndRejectSiblings`, ~6357), `applyCullingShortcut` (~6538), `selectAssetID(_:)` (~4836) / `select(_:)` (~4786), `handleWorkerCommandCompleted` (~10283), the `onQueueChanged` failed-preview block (~4468-4474)
- Test: `Tests/TeststripAppTests/StackDecisionTests.swift` (rewrite the gate test, add armed-commit tests, extend its helpers)

**Interfaces:**
- Consumes: `requestPreview(assetID:level:placement:)`, `previewGenerationAttemptsExhausted(assetID:level:)`, `Self.previewWorkItemID(assetID:level:)`, `Self.previewAssetID(from:)`, `CullingMetadataDecisionFeedback` (mirror `renderPendingFeedback`, AppModel.swift:6425).
- Produces: `public private(set) var armedStackCommitAssetID: AssetID?` — Task 4's card and Task 5's live run observe its effects.

- [ ] **Step 1: Extend the StackDecisionTests helpers**

Give the file's `makeModelWithCatalogAssetsAndPreviewCache` two optional parameters, defaulted so every existing call compiles unchanged:

```swift
private func makeModelWithCatalogAssetsAndPreviewCache(
    named name: String,
    assets: [Asset],
    workerSupervisor: WorkerSupervisor? = nil,
    seedsLargePreviews: Bool = true
) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
```

Inside: wrap the placeholder-seeding loop in `if seedsLargePreviews`, and pass the supervisor through to `AppModel.load(catalog:workerSupervisor:)`. Also copy `waitForBackgroundWorkStatus` verbatim from `Tests/TeststripAppTests/AppModelTests.swift:19448-19460`.

- [ ] **Step 2: Write the failing tests**

Rewrite `testPromoteInertWhenLargePreviewMissing` (StackDecisionTests.swift:376) as the arming contract, and add the new cases. All use a two-frame stack (`frame-1`, `frame-2`, captures 1s apart) with `RecordingWorkerTransport` + `WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: transport)` unless noted:

```swift
// SP-C: a gated Return arms the commit instead of dropping the keystroke.
func testGatedReturnArmsCommitAndRequestsFrontRender() throws {
    // seedsLargePreviews: false — the staged .large is missing.
    model.select(frame1.id)
    try model.promoteCurrentFrameAndRejectSiblings()

    XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)   // no write yet
    XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
    XCTAssertEqual(model.armedStackCommitAssetID, frame1.id)
    let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
    XCTAssertEqual(feedback.decisionText, "Rendering full preview… will keep when ready")
    XCTAssertTrue(feedback.isInformational)
    // The render was requested (front placement). Don't assert it is the
    // *running* item: with a supervisor present, select() may enqueue an
    // XMP selection check that occupies the single running slot first.
    let armedItem = model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large"))
    XCTAssertTrue([.queued, .running].contains(armedItem?.status))
}

@MainActor
func testArmedCommitFiresWhenRenderLands() async throws {
    // Arm as above. The armed preview item must be RUNNING before its
    // terminal event means anything: if select() put an XMP selection
    // check in the single running slot, drain it first by emitting a
    // .completed for whatever runningItems.first is and waiting, exactly
    // like Tests/TeststripAppTests/AppModelTests.swift:3173-3199. Then:
    let itemID = WorkSessionID(rawValue: "preview-\(frame1.id.rawValue)-large")
    try await waitForBackgroundWorkStatus(.running, itemID: itemID, in: model)
    try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: frame1.id, level: .large)))
    transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(itemID: itemID, message: "rendered")))
    try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

    XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
    XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
    // Provenance: the deferred commit is still the explicit user gesture —
    // a confirmed (user-origin) flag, not a tentative AI one.
    XCTAssertEqual(try repository.asset(id: frame1.id).metadata.confirmedProjection.flag, .pick)
    XCTAssertNil(model.armedStackCommitAssetID)
    // Same single undo group as a direct Return.
    try model.undoMetadataChange()
    XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
    XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
}

@MainActor
func testOtherShortcutDisarmsBeforeRenderLands() async throws {
    // Arm, then any other input:
    try model.applyCullingShortcut(.toggleAutoAdvance)
    XCTAssertNil(model.armedStackCommitAssetID)
    // Render landing afterwards must NOT commit.
    ...write placeholder, emit .completed, wait...
    XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
    XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
}

@MainActor
func testSelectionChangeDisarmsBeforeRenderLands() async throws {
    // Arm, then model.select(frame2.id); assert disarmed and, after the
    // render lands, no flags on either frame.
}

func testReturnRefusesToArmWhenOriginalUnavailable() throws {
    // frame-1 built with availability: .offline; seedsLargePreviews: false.
    model.select(frame1.id)
    try model.promoteCurrentFrameAndRejectSiblings()
    XCTAssertNil(model.armedStackCommitAssetID)
    XCTAssertEqual(try XCTUnwrap(model.lastCullingMetadataDecision).decisionText, "Preview unavailable — not committed")
    XCTAssertTrue(model.backgroundWorkQueue.items.filter { $0.kind == .previewGeneration }.isEmpty)
}

func testReturnRefusesToArmWhenAttemptsExhausted() throws {
    for _ in 0..<3 {
        try repository.recordPreviewGenerationFailure(assetID: frame1.id, level: .large, errorMessage: "boom")
    }
    model.select(frame1.id)
    try model.promoteCurrentFrameAndRejectSiblings()
    XCTAssertNil(model.armedStackCommitAssetID)
    XCTAssertEqual(try XCTUnwrap(model.lastCullingMetadataDecision).decisionText, "Preview unavailable — not committed")
}

@MainActor
func testRenderFailureDisarmsWithUnavailableToast() async throws {
    // Arm, then: transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(itemID: itemID, message: "render failed")))
    try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)
    XCTAssertNil(model.armedStackCommitAssetID)
    XCTAssertEqual(try XCTUnwrap(model.lastCullingMetadataDecision).decisionText, "Preview unavailable — not committed")
    XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
}

@MainActor
func testArmedCommitFiresAtMostOnce() async throws {
    // Fire normally, note the post-commit selection, then emit a second
    // .completed for the same itemID; assert flags and selection unchanged
    // and armedStackCommitAssetID still nil.
}
```

Flesh out the elided bodies with the same fixture/emit/wait pattern shown in the complete tests above. Every test that emits transport events needs the supervisor-backed helper.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter StackDecisionTests 2>&1 | tail -20`
Expected: FAIL to compile — `armedStackCommitAssetID` not defined. Capture the transcript.

- [ ] **Step 4: Implement the armed commit**

(a) State, beside the model's culling state:

```swift
// SP-C: a Return that hit the render gate arms the commit; the moment the
// staged frame's large preview lands, the decision fires. Deliberately
// fragile — any other input disarms, so an armed commit can never fire
// against a frame the user is no longer staging.
public private(set) var armedStackCommitAssetID: AssetID?
```

(b) Replace the gate's else-branch in `promoteCurrentFrameAndRejectSiblings` (keep the existing gate comment, extend it with the arming semantics):

```swift
guard previewURL(for: context.selectedAssetID, levels: [.large]) != nil else {
    try armStackCommit(stagedAssetID: context.selectedAssetID, asset: originalAsset)
    return
}
```

(c) The arm/disarm/fire trio, next to `promoteCurrentFrameAndRejectSiblings`:

```swift
private func armStackCommit(stagedAssetID: AssetID, asset: Asset?) throws {
    // Stored availability, not a fresh probe: the same gate the prefetch
    // paths use. If the render can never succeed, arming would hang forever.
    let stored = assets.first(where: { $0.id == stagedAssetID })
    let canRender = try stored?.availability.isAvailableForPreviewGeneration == true
        && !previewGenerationAttemptsExhausted(assetID: stagedAssetID, level: .large)
    guard canRender else {
        armedStackCommitAssetID = nil
        if let asset {
            lastCullingMetadataDecision = Self.renderUnavailableFeedback(asset: asset)
        }
        return
    }
    armedStackCommitAssetID = stagedAssetID
    try requestPreview(assetID: stagedAssetID, level: .large, placement: .front)
    if let asset {
        lastCullingMetadataDecision = Self.armedCommitFeedback(asset: asset)
    }
}

private func disarmStackCommit() {
    armedStackCommitAssetID = nil
}

private func fireArmedStackCommitIfReady(previewAssetID: AssetID) {
    guard let armedID = armedStackCommitAssetID, armedID == previewAssetID else { return }
    guard selectedAssetID == armedID, selectedView == .loupe,
          previewURL(for: armedID, levels: [.large]) != nil else {
        disarmStackCommit()
        return
    }
    disarmStackCommit()
    do {
        try promoteCurrentFrameAndRejectSiblings()
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

Feedback builders, beside `renderPendingFeedback` (AppModel.swift:6425). `renderPendingFeedback` itself becomes unused once arming replaces the inert gate — delete it:

```swift
private static func armedCommitFeedback(asset: Asset) -> CullingMetadataDecisionFeedback {
    CullingMetadataDecisionFeedback(
        assetID: asset.id,
        filename: asset.originalURL.lastPathComponent,
        command: .clearFlag,
        decisionText: "Rendering full preview… will keep when ready",
        isInformational: true
    )
}

private static func renderUnavailableFeedback(asset: Asset) -> CullingMetadataDecisionFeedback {
    CullingMetadataDecisionFeedback(
        assetID: asset.id,
        filename: asset.originalURL.lastPathComponent,
        command: .clearFlag,
        decisionText: "Preview unavailable — not committed",
        isInformational: true
    )
}
```

(d) Disarm hooks:
- Top of `applyCullingShortcut(_:)` (before the key-map overlay branch): `if shortcut != .promoteAndRejectSiblings { disarmStackCommit() }` — a repeat Return re-enters the gate and re-arms the same asset, which is the specced no-op.
- Top of `selectAssetID(_:)` (AppModel.swift:4836): `if assetID != armedStackCommitAssetID { disarmStackCommit() }`. Check whether `select(_:)` (AppModel.swift:4786) routes through `selectAssetID(_:)`; if it does not, add the same line there.
- Leaving the cull loupe needs no extra hook: `fireArmedStackCommitIfReady` requires `selectedView == .loupe` and a matching selection, so a stale arm dies at fire time.

(e) Fire hook — inside `handleWorkerCommandCompleted`'s existing block (AppModel.swift:10299-10303):

```swift
if completedPreview,
   let itemID,
   let previewAssetID = Self.previewAssetID(from: itemID) {
    enqueueImportEvaluationsForCachedPreviews(assetIDs: [previewAssetID])
    fireArmedStackCommitIfReady(previewAssetID: previewAssetID)
}
```

(f) Failure disarm — inside the `onQueueChanged` closure's `if !newFailedPreviewItemIDs.isEmpty` block (AppModel.swift:4470-4474):

```swift
if let armedID = self.armedStackCommitAssetID,
   newFailedPreviewItemIDs.contains(Self.previewWorkItemID(assetID: armedID, level: .large)) {
    self.disarmStackCommit()
    if let asset = self.assets.first(where: { $0.id == armedID }) {
        self.lastCullingMetadataDecision = Self.renderUnavailableFeedback(asset: asset)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter StackDecisionTests 2>&1 | tail -5`
Expected: all PASS, including the rewritten gate test.

- [ ] **Step 6: Run the full suite**

Run: `swift test 2>&1 | tail -5`
Expected: green. (`renderPendingFeedback`'s old toast text no longer appears anywhere in Tests/ — verify with `grep -rn "Rendering full preview…\"" Tests/` that only the new copy remains.)

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/StackDecisionTests.swift
git commit -m "feat: gated Return arms the stack commit and fires when the render lands (SP-C)"
```

---

### Task 4: Scenario card + reconciliation

**Files:**
- Create: `test/scenarios/cull-027-blaze-through-prefetch.md`
- Modify (reconcile): `test/scenarios/cull-023-return-commit-undo.md` and any other card whose prose asserts the old re-press gate (`grep -rln "second Return\|press Return again\|re-press" test/scenarios/`)

Write `cull-027` in the house card format (mirror `test/scenarios/cull-023-return-commit-undo.md`'s section structure and sharp-edges style; read `test/scenarios/README.md` first). The card must carry these assertions, each with its falsification condition:

1. **Prefetch proof.** Launch isolated with seeded burst fixtures (`build_and_run.sh --smoke` seeding), enter the cull loupe on a burst frame, then — *without visiting them* — poll the isolated preview cache (`$ISOLATED/Teststrip/previews/...`) until `.large` files exist for the burst's other frames and the next stops' landing frames. Falsification: only the visited frame's `.large` appears within the wait budget.
2. **Armed commit.** Delete the staged frame's `.large` file from the cache, press Return, and assert via `sqlite3` against `$ISOLATED/Teststrip/catalog.sqlite` that **no** pick/reject flags exist for the stack yet (the falsification leg: flags present now = FAIL), and that the toast reads "Rendering full preview… will keep when ready". Then wait for the regenerated file and assert the flags landed with `origin = 'user'`.
3. **Disarm.** Repeat the deletion, press Return, then press a different key (e.g. `→`) before the render lands; assert the flags never land for that stack.

Sharp edges to record in the card: toasts fade after ~2s (probe promptly); the AX value for toasts lives where cull-023 already documents it; keep the app frontmost during waits (idle-wedge).

Reconcile `cull-023` (and any grep hits): its Return narrative must not claim a gated Return needs a manual second press. Update prose and citations; **citation sweeps are the last commit on the branch** (line numbers shift with every code commit — Tasks 1-3 are done by now, so sweeping here is safe, but re-verify all citations you touch by reading the cited lines at current HEAD).

- [ ] Write `cull-027-blaze-through-prefetch.md`
- [ ] Reconcile cull-023 + grep hits; verify every citation you touch by reading the cited line
- [ ] Commit: `git add test/scenarios/ && git commit -m "test: blaze-through prefetch scenario card; reconcile Return-gate cards (SP-C)"`

---

### Task 5: Live VM verification

**Files:**
- Modify: `test/scenarios/cull-027-blaze-through-prefetch.md` (Run-status entry), plus Run-status notes on any reconciled card whose changed assertions you exercised

Run `cull-027` live in the Tart VM per `test/scenarios/README.md` ("Running scenarios in a Tart VM": `script/vm_scenario_run.sh` setup/sync/launch/ax/sql verbs). Drive with `script/ax_drive.sh`; re-assert frontmost on every poll; assert against the catalog and preview-cache files, not renders. Record a dated Run-status entry with each assertion's pass/fail and the concrete observations (file lists, sqlite output). If an assertion fails: it is either an app bug (stop, root-cause, fix on this branch — finish what you touch) or a card bug (fix the card). Do not soften verdicts.

- [ ] VM run of cull-027, all three assertion groups, falsification legs included
- [ ] Record Run-status entries; commit docs-only: `git commit -m "test: cull-027 first live run (SP-C)"`

---

## Execution notes

- Baseline before Task 1: `swift test` green on the branch point (2257/0/15 as of main `74e60a63`).
- Line references in this plan are against main `74e60a63`; re-locate by symbol if they drift.
- The final whole-branch review, merge, and cleanup follow superpowers:subagent-driven-development + finishing-a-development-branch as usual (gate: `make verify`).
