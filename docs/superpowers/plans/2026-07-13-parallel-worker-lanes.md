# Concurrent Per-Lane Worker Execution + Per-Kind Activity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run each background task type (preview, evaluation, import, …) as its own concurrent lane on a single worker process, and show one aggregate progress bar per active work kind in the Activity Center.

**Architecture:** One `TeststripWorker` process executes one command per lane concurrently, serializing catalog access through its single connection (each command wrapped in a transaction). The `WorkerSupervisor`/transport already demux events by `itemID`; concurrency is unlocked by raising the dispatch caps and making the worker's command loop concurrent. The Activity Center groups work items by `WorkSessionKind` into one bar per kind.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, SQLite (C API via `SQLite3`), the JSON-lines worker protocol in `TeststripCore`.

## Global Constraints

- **Confirm-before-write:** machine labels stay provisional until an explicit user gesture. Tests assert the negative — nothing in `people`/`person_assets`/asset metadata before the confirming gesture.
- **Non-destructive:** original image bytes are never modified; edits go to catalog + `.xmp` sidecars only.
- **TDD:** every task writes the failing test first. Test output must be pristine to pass.
- **macOS 14+ / Apple silicon; Swift 6 toolchain.**
- **Build/test locally:** `make build`, `make test`. Interactive scenario driving runs in the Tart VM via `script/vm_scenario_run.sh` (never the host console).
- **Every user-facing surface gets an automated end-to-end scenario** (Phase D).
- **Kind → display title map (single source of truth), used verbatim:** `.ingest`→"Import photos", `.previewGeneration`→"Generate previews", `.recognition`→"Evaluate photos", `.xmpSync`→"Sync sidecars", `.sourceScan`→"Check sources", `.geocoding`→"Find places", `.locationBackfill`→"Backfill locations", `.culling`→"Culling", `.collecting`→"Collecting", `.searchSort`→"Sorting", `.keywording`→"Keywording", `.export`→"Export", `.relocation`→"Relocating".

---

## Phasing

- **Phase A — Per-kind Activity UI.** Independently shippable; correct even while execution is still serial (one lane advances at a time until Phase B lands).
- **Phase B — Concurrent per-lane execution engine.** The real concurrency: serialized catalog, concurrent worker loop, raised dispatch caps.
- **Phase C — Per-item cancel.** Cancel one lane without killing its siblings.
- **Phase D — End-to-end verification.**

Work top-to-bottom; each task ends at a green commit.

---

## Phase A — Per-kind Activity UI

### Task A1: `ActivityKindRow` type + pure grouping function

**Files:**
- Modify: `Sources/TeststripApp/ActivityCenterPresentation.swift`
- Test: `Tests/TeststripAppTests/ActivityKindRowTests.swift` (create)

**Interfaces:**
- Consumes: `AppWorkActivity` (fields: `id`, `kind: WorkSessionKind`, `status: WorkSessionStatus`, `title`, `detail`, `completedUnitCount: Int`, `totalUnitCount: Int?`, `failureCount`, `starred`), `WorkSessionKind`, `WorkSessionStatus`.
- Produces:
  - `ActivityKindRow` with `id: String` (= `kind.rawValue`), `kind: WorkSessionKind`, `title: String`, `detail: String`, `completedUnitCount: Int`, `totalUnitCount: Int?`, `status: WorkSessionStatus`, `activeItemCount: Int`, `canPause: Bool`, `canResume: Bool`, `canCancel: Bool`.
  - `static func ActivityKindRow.rows(from activities: [AppWorkActivity], canPause: Bool, canResume: Bool) -> [ActivityKindRow]`
  - `static func ActivityKindRow.title(for kind: WorkSessionKind) -> String` (the Global-Constraints map).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TeststripApp
import TeststripCore

final class ActivityKindRowTests: XCTestCase {
    private func activity(_ kind: WorkSessionKind, _ status: WorkSessionStatus, done: Int, total: Int?) -> AppWorkActivity {
        AppWorkActivity(kind: kind, status: status, title: "x", detail: "d", completedUnitCount: done, totalUnitCount: total)
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
                AppWorkActivity(kind: .recognition, status: .running, title: "Evaluate photo", detail: "Running apple-vision", completedUnitCount: 0, totalUnitCount: 1),
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
}
```

- [ ] **Step 2: Make `WorkSessionKind` iterable for the map test**

In `Sources/TeststripCore/Work/WorkSession.swift`, change `public enum WorkSessionKind: String, Codable, Hashable, Sendable` to also conform to `CaseIterable`:
`public enum WorkSessionKind: String, Codable, Hashable, Sendable, CaseIterable {`

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ActivityKindRowTests`
Expected: FAIL — `ActivityKindRow` is undefined.

- [ ] **Step 4: Implement `ActivityKindRow` in `ActivityCenterPresentation.swift`**

```swift
/// One aggregate progress row per active work kind in the Activity Center,
/// rolling every in-flight item of that kind into a single bar.
public struct ActivityKindRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var title: String
    public var detail: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var status: WorkSessionStatus
    public var activeItemCount: Int
    public var canPause: Bool
    public var canResume: Bool
    public var canCancel: Bool

    public static func title(for kind: WorkSessionKind) -> String {
        switch kind {
        case .ingest: "Import photos"
        case .previewGeneration: "Generate previews"
        case .recognition: "Evaluate photos"
        case .xmpSync: "Sync sidecars"
        case .sourceScan: "Check sources"
        case .geocoding: "Find places"
        case .locationBackfill: "Backfill locations"
        case .culling: "Culling"
        case .collecting: "Collecting"
        case .searchSort: "Sorting"
        case .keywording: "Keywording"
        case .export: "Export"
        case .relocation: "Relocating"
        }
    }

    // Running outranks paused outranks queued outranks completed/failed.
    private static let statusRank: [WorkSessionStatus: Int] = [
        .running: 5, .paused: 4, .queued: 3, .completed: 2, .failed: 1, .cancelled: 0,
    ]

    public static func rows(
        from activities: [AppWorkActivity],
        canPause: Bool,
        canResume: Bool
    ) -> [ActivityKindRow] {
        var order: [WorkSessionKind] = []
        var byKind: [WorkSessionKind: [AppWorkActivity]] = [:]
        for activity in activities {
            if byKind[activity.kind] == nil { order.append(activity.kind) }
            byKind[activity.kind, default: []].append(activity)
        }
        return order.map { kind in
            let items = byKind[kind]!
            let dominant = items.max { (statusRank[$0.status] ?? 0) < (statusRank[$1.status] ?? 0) }!
            let totals = items.compactMap(\.totalUnitCount)
            let total = totals.count == items.count ? totals.reduce(0, +) : nil
            let running = items.first { $0.status == .running }
            return ActivityKindRow(
                id: kind.rawValue,
                kind: kind,
                title: title(for: kind),
                detail: (running ?? dominant).detail,
                completedUnitCount: items.map(\.completedUnitCount).reduce(0, +),
                totalUnitCount: total,
                status: dominant.status,
                activeItemCount: items.count,
                canPause: canPause,
                canResume: canResume,
                canCancel: items.contains { [.queued, .running, .paused].contains($0.status) }
            )
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ActivityKindRowTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/ActivityCenterPresentation.swift Sources/TeststripCore/Work/WorkSession.swift Tests/TeststripAppTests/ActivityKindRowTests.swift
git commit -m "feat: ActivityKindRow aggregates work items by kind"
```

---

### Task A2: Surface `kindRows` on `ActivityCenterPresentation` and feed all active work

**Files:**
- Modify: `Sources/TeststripApp/ActivityCenterPresentation.swift` (add `kindRows` field to the struct + init)
- Modify: `Sources/TeststripApp/AppModel.swift:2785-2833` (`activityCenterPresentation`) and the active-items projection near `2703-2715`
- Test: `Tests/TeststripAppTests/ActivityCenterPresentationKindRowsTests.swift` (create)

**Interfaces:**
- Consumes: `ActivityKindRow.rows(from:canPause:canResume:)` (Task A1); `AppModel.visibleActiveBackgroundWorkItems` (existing), `AppModel.canPauseBackgroundWork`, `AppModel.canResumeBackgroundWork`.
- Produces: `ActivityCenterPresentation.kindRows: [ActivityKindRow]`; `AppModel.activeWorkKindRows: [ActivityKindRow]` (new computed var, the projection tested here).

- [ ] **Step 1: Write the failing test** — drive it through a seeded model.

```swift
import XCTest
@testable import TeststripApp
import TeststripCore

final class ActivityCenterPresentationKindRowsTests: XCTestCase {
    func testConcurrentPreviewAndEvalProduceTwoKindRows() throws {
        let model = try AppModelTestFixture.seededSmoke() // existing helper; see below
        try model.enqueueTestWorkItem(kind: .previewGeneration, id: "prev-1", title: "Generate preview", done: 0, total: 1)
        try model.enqueueTestWorkItem(kind: .recognition, id: "eval-1", title: "Evaluate photo", done: 0, total: 1)

        let rows = model.activityCenterPresentation.kindRows
        XCTAssertEqual(Set(rows.map(\.kind)), [.previewGeneration, .recognition])
        XCTAssertEqual(rows.first { $0.kind == .previewGeneration }?.title, "Generate previews")
    }
}
```

> **Note for implementer:** search `Tests/TeststripAppTests` for the existing model-construction helper (e.g. an in-memory `AppModel` fixture used by other Activity tests) and reuse it; add the two thin test seams (`enqueueTestWorkItem`) next to existing test-only helpers if none fit. Do not invent a new fixture pattern.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ActivityCenterPresentationKindRowsTests`
Expected: FAIL — `kindRows` is undefined.

- [ ] **Step 3: Add `activeWorkKindRows` to `AppModel`** (near `activityCenterPresentation`)

```swift
public var activeWorkKindRows: [ActivityKindRow] {
    ActivityKindRow.rows(
        from: visibleActiveBackgroundWorkItems.map(AppWorkActivity.init),
        canPause: canPauseBackgroundWork,
        canResume: canResumeBackgroundWork
    )
}
```

- [ ] **Step 4: Add `kindRows` to `ActivityCenterPresentation`** (new stored property, init param, and pass it in `activityCenterPresentation`)

In `ActivityCenterPresentation`: add `public var kindRows: [ActivityKindRow]` and an `init` parameter `kindRows: [ActivityKindRow]`. In `AppModel.activityCenterPresentation`, pass `kindRows: activeWorkKindRows`. Keep the existing `jobs` field for now (removed in Task A3).

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ActivityCenterPresentationKindRowsTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/ActivityCenterPresentation.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/ActivityCenterPresentationKindRowsTests.swift
git commit -m "feat: project active work into per-kind Activity rows"
```

---

### Task A3: Render per-kind bars in `ActivityCenterView`; retire per-item job rows + `ImportProgressRow`

**Files:**
- Modify: `Sources/TeststripApp/ActivityCenterView.swift`
- Modify: `Sources/TeststripApp/ActivityCenterPresentation.swift` (remove `jobs`, `ActivityJobRow`, `importProgress`/`ImportProgressRow`, `importActivity` param)
- Modify: `Sources/TeststripApp/AppModel.swift` (drop the now-unused `jobs`/`visibleImportActivity` wiring from `activityCenterPresentation`)

**Interfaces:**
- Consumes: `ActivityCenterPresentation.kindRows` (Task A2), the per-kind action IDs (Task A4).

> **This is UI; verify it in Phase D's scenario card, not a unit test.** Keep the change mechanical.

- [ ] **Step 1: Replace the job-row `ForEach` with a per-kind `ForEach`**

Render one row per `presentation.kindRows`: title (`row.title`), a `ProgressView(value:)` from `row.completedUnitCount`/`row.totalUnitCount` (indeterminate when `totalUnitCount == nil`), the running `row.detail`, a status label, and per-kind pause/resume/cancel buttons gated by `row.canPause`/`row.canResume`/`row.canCancel` calling the Task A4 actions with `row.kind`. Import now appears here as the `.ingest` row.

- [ ] **Step 2: Delete `ActivityJobRow`, `ImportProgressRow`, and the `jobs`/`importActivity`/`importProgress` fields** from `ActivityCenterPresentation` and their construction in `AppModel`. Update the `init` and every call site the compiler flags.

- [ ] **Step 3: Build**

Run: `make build`
Expected: Build complete. Fix every compile error the removals surface (call sites referencing `jobs`, `importProgress`, `ActivityJobRow`).

- [ ] **Step 4: Run the full unit suite** (catch broken Activity tests)

Run: `make test`
Expected: PASS. Update any test still referencing the removed types to `kindRows`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/ActivityCenterView.swift Sources/TeststripApp/ActivityCenterPresentation.swift Sources/TeststripApp/AppModel.swift Tests/
git commit -m "feat: Activity Center shows one bar per work kind; retire per-item rows"
```

---

### Task A4: Per-kind pause/cancel actions (fan-out over a kind's items)

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/PerKindWorkControlTests.swift` (create)

**Interfaces:**
- Consumes: `WorkerSupervisor.cancel(id:)` (existing), `backgroundWorkQueue.items`.
- Produces: `AppModel.cancelWork(kind: WorkSessionKind) throws`, `AppModel.pauseWork(kind: WorkSessionKind) throws`, `AppModel.resumeWork(kind: WorkSessionKind) throws`.

- [ ] **Step 1: Write the failing test**

```swift
func testCancelKindCancelsEveryActiveItemOfThatKindOnly() throws {
    let model = try AppModelTestFixture.seededSmoke()
    try model.enqueueTestWorkItem(kind: .previewGeneration, id: "prev-1", title: "Generate preview", done: 0, total: 1)
    try model.enqueueTestWorkItem(kind: .recognition, id: "eval-1", title: "Evaluate photo", done: 0, total: 1)
    try model.enqueueTestWorkItem(kind: .recognition, id: "eval-2", title: "Evaluate photo", done: 0, total: 1)

    try model.cancelWork(kind: .recognition)

    let statuses = Dictionary(uniqueKeysWithValues: model.backgroundWorkQueue.items.map { ($0.id.rawValue, $0.status) })
    XCTAssertEqual(statuses["eval-1"], .cancelled)
    XCTAssertEqual(statuses["eval-2"], .cancelled)
    XCTAssertNotEqual(statuses["prev-1"], .cancelled)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PerKindWorkControlTests`
Expected: FAIL — `cancelWork(kind:)` undefined.

- [ ] **Step 3: Implement the fan-out**

```swift
public func cancelWork(kind: WorkSessionKind) throws {
    guard let supervisor = workerSupervisor else { return }
    let ids = backgroundWorkQueue.items
        .filter { $0.kind == kind && Self.isActiveBackgroundWorkStatus($0.status) }
        .map(\.id)
    for id in ids { try supervisor.cancel(id: id) }
    syncBackgroundWorkQueueFromSupervisor()
}
```

Pause/resume delegate to the existing queue-wide `pauseBackgroundWork`/`resumeBackgroundWork` for now (the queue's pause is global; per-kind pause is deferred — see the spec's open item). Wire `pauseWork(kind:)`/`resumeWork(kind:)` to those existing methods so the UI buttons have targets; a genuinely per-kind pause is out of scope for this plan.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PerKindWorkControlTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/PerKindWorkControlTests.swift
git commit -m "feat: per-kind cancel fans out over that kind's active items"
```

---

## Phase B — Concurrent per-lane execution engine

### Task B1: Serialize `CatalogDatabase` handle access (thread-safe)

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogDatabase.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseConcurrencyTests.swift` (create)

**Interfaces:**
- Produces: all public `CatalogDatabase` methods (`execute`, `rows`, `transaction`, …) become safe to call from multiple threads; behavior unchanged single-threaded.

- [ ] **Step 1: Write the failing test** (concurrent writers must not corrupt or crash)

```swift
import XCTest
@testable import TeststripCore

final class CatalogDatabaseConcurrencyTests: XCTestCase {
    func testConcurrentTransactionsSerializeWithoutCorruption() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url)
        try db.execute("CREATE TABLE t (v INTEGER)")
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            try? db.transaction { try db.execute("INSERT INTO t (v) VALUES (1)") }
        }
        let rows = try db.rows("SELECT COUNT(*) AS c FROM t")
        XCTAssertEqual(rows.first?["c"], "200")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CatalogDatabaseConcurrencyTests`
Expected: FAIL/crash — concurrent use of one `sqlite3` handle is unserialized (misuse / lost inserts).

- [ ] **Step 3: Serialize every handle access behind one lock**

Add `private let handleLock = NSRecursiveLock` (recursive so `transaction` can call `execute` while holding it). Wrap the body of each method that touches `handle` — `execute`, `rows`, `transaction`, and any other handle user — in `handleLock.lock()` / `defer { handleLock.unlock() }`. Recursive lock keeps `transaction { execute(...) }` correct.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CatalogDatabaseConcurrencyTests`
Expected: PASS. Then `make test` — no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogDatabase.swift Tests/TeststripCoreTests/CatalogDatabaseConcurrencyTests.swift
git commit -m "feat: serialize CatalogDatabase handle for concurrent worker lanes"
```

---

### Task B2: Concurrent worker command loop (per-lane, serialized writes + output)

**Files:**
- Modify: `Sources/TeststripWorker/main.swift`
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` (wrap each command's writes in `database.transaction`)
- Test: `Tests/TeststripWorkerTests/ConcurrentCommandLoopTests.swift` (create)

**Interfaces:**
- Consumes: `WorkerCommandExecutor.execute(_:progress:)` (existing), `CatalogDatabase.transaction` (thread-safe after B1).
- Produces: worker executes commands received on stdin **concurrently, one per lane (`WorkSessionKind`)**, serializing stdout writes; a slow command in one lane does not block a command in another.

> **Discovery step inside this task:** confirm each evaluation provider and `PreviewRenderer` is safe to run off `@MainActor`. Where a provider is not, guard *that provider* with its own lock (accepted fallback) — it still overlaps other lanes. Record what you found in the commit message.

- [ ] **Step 1: Write the failing test** — a fast lane must finish while a slow lane is mid-flight.

Drive the executor through a test double that makes one command block on a signal and asserts a second command (different lane) completes first. Concretely: build a `WorkerCommandLoop` seam (extracted from `main.swift`) that takes an `execute` closure and a `writeLine` sink, feed it two decoded requests on different lanes where lane A's `execute` waits on an `XCTestExpectation` that lane B fulfils, and assert B's completed event is written before A's.

```swift
func testSecondLaneCompletesWhileFirstLaneBlocks() throws {
    let laneAStarted = expectation(description: "A started")
    let laneBDone = expectation(description: "B done")
    var written: [String] = []
    let writeLock = NSLock()
    let loop = WorkerCommandLoop(
        laneKey: { $0.itemID?.rawValue.hasPrefix("A") == true ? "A" : "B" },
        execute: { request in
            if request.itemID?.rawValue.hasPrefix("A") == true {
                laneAStarted.fulfill()
                wait(for: [laneBDone], timeout: 2) // A blocks until B finishes
            }
            return .completed("done")
        },
        writeLine: { line in writeLock.lock(); written.append(line); writeLock.unlock() }
    )
    loop.submit(decoded("A-1", .generatePreview))
    wait(for: [laneAStarted], timeout: 2)
    loop.submit(decoded("B-1", .runEvaluation))
    // B completes and is written even though A is still blocked:
    // poll `written` for a B completion line, then fulfil laneBDone.
    ...
    laneBDone.fulfill()
}
```

> Implementer: `laneKey` maps a request to its lane (derive from the command's `WorkSessionKind`, not the id prefix, in production; the id-prefix is only the test's stand-in). Keep at most one in-flight execution per lane key; queue a second same-lane request behind the first.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConcurrentCommandLoopTests`
Expected: FAIL — `WorkerCommandLoop` undefined / loop is serial.

- [ ] **Step 3: Extract `WorkerCommandLoop` and make it concurrent**

Create `Sources/TeststripCore/Worker/WorkerCommandLoop.swift`: a reader-fed dispatcher that, per lane key, runs at most one command at a time on a background `DispatchQueue` (concurrent across lanes), serializes `writeLine` behind a lock, and serializes catalog access via B1. Rewrite `main.swift` to: read lines on the main thread, decode, and `loop.submit(request)`; the loop owns execution and output. Control commands (`pause`/`resume`/`cancelAll`) are handled inline as today.

- [ ] **Step 4: Wrap each command's catalog writes in a transaction**

In `WorkerCommandExecutor.execute`, wrap the per-command write sequence (e.g. `syncMetadata`'s multiple `repository.*` calls, evaluation's `recordEvaluationSignals` + `replaceFaceObservations`) in `database.transaction { … }` so a concurrent lane can never observe a half-applied command. Preview's `markPreviewGenerated` and single-statement commands are already atomic but wrap them uniformly for consistency.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ConcurrentCommandLoopTests` then `make test`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripWorker/main.swift Sources/TeststripCore/Worker/WorkerCommandLoop.swift Sources/TeststripCore/Worker/WorkerCommandExecutor.swift Tests/TeststripWorkerTests/ConcurrentCommandLoopTests.swift
git commit -m "feat: worker runs one command per lane concurrently, writes serialized+transactional"
```

---

### Task B3: Raise dispatch caps so lanes actually run concurrently

**Files:**
- Modify: `Sources/TeststripApp/AppCatalog.swift:35-39` (`managedWorkerKindRunningLimits`) and `:122` (queue construction + `maxDispatchedCommandCount`)
- Modify: `Sources/TeststripCore/Worker/WorkerSupervisor.swift:56` (default `maxDispatchedCommandCount`, if changing the default)
- Test: `Tests/TeststripCoreTests/SupervisorConcurrentDispatchTests.swift` (create)

**Interfaces:**
- Consumes: `WorkerSupervisor(queue:transport:commandTimeout:maxDispatchedCommandCount:)`, `BackgroundWorkQueue(maxRunningCount:kindRunningLimits:)`, a test `WorkerTransport` double.
- Produces: supervisor dispatches multiple lanes' commands concurrently (`isCommandDispatched` true for two different-kind items at once).

- [ ] **Step 1: Write the failing test** with a recording transport double.

```swift
func testDispatchesTwoLanesConcurrently() throws {
    let transport = RecordingTransport() // records writeLine calls; never terminal until told
    let limits: [WorkSessionKind: Int] = [.previewGeneration: 1, .recognition: 1]
    let supervisor = WorkerSupervisor(
        queue: BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: limits),
        transport: transport,
        commandTimeout: nil,
        maxDispatchedCommandCount: 8
    )
    try supervisor.enqueue(item(.previewGeneration, "prev-1"), command: .generatePreview(assetID: .init(rawValue: "a"), level: .micro))
    try supervisor.enqueue(item(.recognition, "eval-1"), command: .runEvaluation(assetID: .init(rawValue: "a"), provider: "local-image-metrics"))
    XCTAssertTrue(supervisor.isCommandDispatched(for: .init(rawValue: "prev-1")))
    XCTAssertTrue(supervisor.isCommandDispatched(for: .init(rawValue: "eval-1")))
}
```

> Implementer: if a `RecordingTransport`/`WorkerTransport` test double already exists in `Tests/TeststripCoreTests`, reuse it. Otherwise add a minimal one conforming to `WorkerTransport`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SupervisorConcurrentDispatchTests`
Expected: FAIL — with `maxDispatchedCommandCount: 1` only the first item dispatches. (If you pass 8 explicitly here the supervisor already supports it — the failing production reality is the caps in `AppCatalog`, asserted next.)

- [ ] **Step 3: Raise the production caps**

In `AppCatalog.swift`: extend `managedWorkerKindRunningLimits` to cap **every worker-dispatched kind** at 1 — `.ingest, .previewGeneration, .recognition, .xmpSync, .sourceScan, .geocoding, .locationBackfill` each `: 1`. Change the queue to `BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: managedWorkerKindRunningLimits)` and construct the `WorkerSupervisor` with `maxDispatchedCommandCount: 8`. (8 = comfortable upper bound ≥ lane count; actual concurrency is workload-driven.)

- [ ] **Step 4: Run tests + build**

Run: `swift test --filter SupervisorConcurrentDispatchTests` then `make build`
Expected: PASS; build clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppCatalog.swift Sources/TeststripCore/Worker/WorkerSupervisor.swift Tests/TeststripCoreTests/SupervisorConcurrentDispatchTests.swift
git commit -m "feat: cap each worker kind at 1 and dispatch lanes concurrently"
```

---

## Phase C — Per-item cancel without killing siblings

### Task C1: Per-item cancel command in the protocol + cooperative worker cancellation

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerCommand.swift` (add `case cancelItem(itemID: WorkSessionID)` or reuse the request `itemID` with a `cancel` control)
- Modify: `Sources/TeststripCore/Worker/WorkerProtocol.swift` (encode/decode the new command)
- Modify: `Sources/TeststripCore/Worker/WorkerCommandLoop.swift` (cancel the in-flight task for that lane/item cooperatively)
- Test: `Tests/TeststripWorkerTests/PerItemCancelTests.swift` (create)

**Interfaces:**
- Produces: `WorkerCommand.cancelItem(itemID:)`; the loop marks the targeted lane's in-flight command cancelled (cooperative check between work chunks) and emits `.failed(itemID:, "cancelled")` or a dedicated cancelled event, leaving other lanes untouched.

- [ ] **Step 1: Write the failing test** — cancelling lane A leaves lane B running and emits a terminal for A only.

```swift
func testCancelItemStopsOnlyThatLane() throws {
    // Feed a long-running A command that polls a cancellation flag between chunks,
    // submit cancelItem(A), assert A emits a terminal event and B is never disturbed.
    ...
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PerItemCancelTests`
Expected: FAIL — `cancelItem` undefined.

- [ ] **Step 3: Implement `cancelItem` end-to-end**

Add the command + protocol encode/decode. In `WorkerCommandLoop`, hold a per-lane cancellation token; `cancelItem` flips the token for that item's lane. Long commands (import, batch geocode, availability batch) check the token between units and stop early, emitting a terminal event for that item. Short commands are effectively uncancellable (they finish first) — acceptable.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PerItemCancelTests` then `make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Worker/WorkerCommand.swift Sources/TeststripCore/Worker/WorkerProtocol.swift Sources/TeststripCore/Worker/WorkerCommandLoop.swift Tests/TeststripWorkerTests/PerItemCancelTests.swift
git commit -m "feat: cooperative per-item worker cancellation"
```

---

### Task C2: Supervisor `cancel(id:)` sends per-item cancel, keeps siblings running

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerSupervisor.swift:191-233` (`cancel(id:)`)
- Test: `Tests/TeststripCoreTests/SupervisorPerItemCancelTests.swift` (create)

**Interfaces:**
- Consumes: `WorkerCommand.cancelItem(itemID:)` (Task C1).
- Produces: `cancel(id:)` no longer terminates the transport or fails siblings when the worker supports per-item cancel; it sends `cancelItem`, marks that item cancelled, and leaves other dispatched lanes dispatched.

- [ ] **Step 1: Write the failing test**

```swift
func testCancelOneDispatchedItemLeavesSiblingDispatched() throws {
    let transport = RecordingTransport()
    let supervisor = WorkerSupervisor(
        queue: BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: [.previewGeneration: 1, .recognition: 1]),
        transport: transport, commandTimeout: nil, maxDispatchedCommandCount: 8
    )
    try supervisor.enqueue(item(.previewGeneration, "prev-1"), command: .generatePreview(assetID: .init(rawValue: "a"), level: .micro))
    try supervisor.enqueue(item(.recognition, "eval-1"), command: .runEvaluation(assetID: .init(rawValue: "a"), provider: "local-image-metrics"))

    try supervisor.cancel(id: .init(rawValue: "prev-1"))

    XCTAssertFalse(supervisor.isCommandDispatched(for: .init(rawValue: "prev-1")))
    XCTAssertTrue(supervisor.isCommandDispatched(for: .init(rawValue: "eval-1"))) // sibling survives
    XCTAssertTrue(transport.wroteCommand(named: "cancelItem"))
    XCTAssertFalse(transport.wasTerminated) // no helper-wide terminate
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SupervisorPerItemCancelTests`
Expected: FAIL — current `cancel(id:)` sends `cancelAll` + terminates + fails siblings.

- [ ] **Step 3: Rewrite `cancel(id:)`**

When the worker is running and the item is dispatched: `send(.cancelItem(itemID: itemID))`, remove `itemID` from `dispatchedItemIDs`, `cancelTimeout(for: itemID)`, clear its command, `queue.cancel(id: itemID)`, and `dispatchRunnableItems()` — **without** touching sibling `dispatchedItemIDs`, without `send(.cancelAll)`, without `transport.terminate()`. Keep terminate-and-relaunch only in the timeout path (`handleCommandTimeout`) as the last-resort recovery.

- [ ] **Step 4: Run tests + full suite**

Run: `swift test --filter SupervisorPerItemCancelTests` then `make test`
Expected: PASS. Update/relax any existing supervisor test that asserted the old cancelAll+terminate behavior, matching the spec's new semantics.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Worker/WorkerSupervisor.swift Tests/TeststripCoreTests/SupervisorPerItemCancelTests.swift
git commit -m "feat: per-item cancel leaves sibling lanes running"
```

---

## Phase D — End-to-end verification

### Task D1: Headless verifier asserts preview/evaluation overlap

**Files:**
- Modify: `Sources/TeststripBench/` (the bench target that drives headless import+preview+eval) or add a focused check invoked by `script/verify_headless_workflows.sh`
- Modify: `script/verify_headless_workflows.sh` (add the new check if separate)

**Interfaces:**
- Consumes: the headless import/preview/eval path already exercised by `verify_import_preview_drain.sh`.
- Produces: a headless assertion that preview and evaluation work items are `running` in the same observation window, and that `previews` + `evaluation_signals` rows land correctly.

- [ ] **Step 1: Write the failing check** — seed a smoke catalog, kick preview + evaluation, sample the queue, assert two different kinds are simultaneously `running` at least once, and assert final catalog rows. Run it; expect FAIL if concurrency regressed.
- [ ] **Step 2: Wire it into `verify_headless_workflows.sh`.**
- [ ] **Step 3: Run** `make verify` (or the single script). Expected: PASS.
- [ ] **Step 4: Commit.**

```bash
git add Sources/TeststripBench/ script/verify_headless_workflows.sh
git commit -m "test: headless gate asserts preview/evaluation lanes overlap"
```

---

### Task D2: E2E scenario card in the Tart VM

**Files:**
- Create: `test/scenarios/activity-<nnn>-per-kind-lanes.md` (follow the existing scenario-card format; see `test/scenarios/README.md`)

**Interfaces:**
- Consumes: `script/vm_scenario_run.sh` (setup/sync/launch/ax/sql), `script/ax_drive.sh`.

- [ ] **Step 1: Write the scenario card.** Import a card in the VM; open the Activity Center; assert (via `ax_drive.sh find`) that a "Generate previews" bar **and** an "Evaluate photos" bar are both present and both advance (sample twice, counts increase); via `vm_scenario_run.sh sql`, assert `previews`/`evaluation_signals` rows exist; re-assert **confirm-before-write** — `SELECT COUNT(*) FROM people` and `person_assets` are `0` with no naming gesture, and no asset metadata/sidecars written without a gesture.
- [ ] **Step 2: Run the card in the VM** per `test/scenarios/README.md` (keep the app warm; drive promptly). Iterate until it passes 5/5.
- [ ] **Step 3: Commit the card + a ledger row** per the repo's scenario-testing convention.

```bash
git add test/scenarios/
git commit -m "test: e2e scenario — per-kind lanes advance concurrently on import"
```

---

## Self-Review

**Spec coverage:**
- Lane model / one-per-lane concurrency → B3 (caps) + B2 (worker). ✅
- Concurrent worker, off-actor compute, serialized+transactional catalog → B1, B2. ✅
- Multiplexed transport/supervisor, per-lane completion & timeout → already present; exercised by B3. ✅
- Per-item cancel (routine) vs terminate-relaunch (last resort) → C1, C2. ✅
- Per-kind aggregate Activity UI, import folded in, per-item rows retired → A1–A4. ✅
- Testing: unit (A1, A4, B1–B3, C1–C2), headless overlap (D1), e2e + confirm-before-write (D2). ✅
- Open items: provider concurrency → B2 discovery step; transaction granularity → B2 Step 4; per-kind pause deferral → noted in A4. ✅

**Placeholder scan:** No "TBD/handle edge cases/similar to". The two test-double reuse notes (A2 fixture, B3 transport) direct the implementer to existing helpers rather than leaving code blank; the B2 and C1 test bodies give the mechanism and the seam names.

**Type consistency:** `ActivityKindRow` fields/`rows(from:canPause:canResume:)`/`title(for:)` are consistent across A1→A2→A3. `WorkerCommand.cancelItem(itemID:)` consistent across C1→C2. `maxDispatchedCommandCount`/`kindRunningLimits` consistent B3↔C2. `WorkSessionKind: CaseIterable` added in A1, used only there.
