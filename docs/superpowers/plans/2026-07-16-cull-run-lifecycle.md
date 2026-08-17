# Cull Run Lifecycle (SP-D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cull runs first-class: a ⌘R start card, loud accounting in the
scope line, exact resume via a persisted run tracker, one-key scoped mini-runs
from the completion summary, and a unified completion type that merges the ad-hoc
`CullCompletionPresentation` with the formal-session
`CullingSessionCompletionSummary`.

**Architecture:** Evolve existing types — no rewrites. `CullRunTracker` gains
`Codable` + file persistence (never the catalog). `CullCompletionPresentation`
gains session-level fields and absorbs `CullingSessionCompletionSummary`.
`CullingProgressSummary` gains viewed/skipped/never-viewed/✨ counts for loud
accounting. A ⌘R keyboard shortcut starts a cull run from the Cull lens. New
pure logic lands as `<Feature>Presentation.swift` files with unit tests; view
code re-plumbs proven parts.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md` (SP-D section). UX contract: `docs/design-spikes/2026-07-16-culling-redesign/tutorial.md`.

## Global Constraints

- ✨ tentative flags never count as decided: all "decided" math goes through `metadata.confirmedProjection.flag`. Assert the negative in tests wherever a count or done-state is computed.
- CullRunTracker persistence is NEVER to the catalog — a JSON file in the app-support directory, scoped to the run's asset-set ID. The catalog is operational truth for assets; the run tracker is UI state.
- `CullRunTracker` resets on cull source/batch change (`startCullRunTracking`), NOT on `S` scope cycling. Persistence saves on mutation and loads on resume.
- Bare culling keys are handled ONLY by the local key monitor (`CullingKeyCaptureView`), never as SwiftUI `.keyboardShortcut` menu equivalents. ⌘R is modifier-bearing, so it goes through the AppKit menu path (like ⌘1–⌘6), NOT the local monitor.
- New pure presentation types go in their own `Sources/TeststripApp/<Feature>Presentation.swift` file; view structs stay in `LibraryGridView.swift`.
- ALL line numbers in this plan are approximate (they drift daily) — locate by symbol name (`grep -n`) before editing.
- Each task: TDD (failing test first), run the named test file(s) with `swift test --filter <TestClass>`, commit per task. `make verify` runs once at branch end.
- Match surrounding code style exactly; smallest reasonable change; no whitespace churn.

---

### Task 1: CullRunTracker Codable + file persistence

**Files:**
- Modify: `Sources/TeststripApp/CullRunTracker.swift` (add `Codable`, `Persistence` namespace)
- Test: `Tests/TeststripAppTests/CullRunTrackerTests.swift`

**Interfaces:**
- Consumes: existing `CullRunTracker` struct, `AssetID` from `TeststripCore`
- Produces: `CullRunTracker: Codable`; `CullRunTracker.Persistence` with `save(_:to:)` and `load(from:)` static methods that read/write a JSON file

- [ ] **Step 1: Write failing Codable round-trip test** in `CullRunTrackerTests.swift`:

```swift
func testTrackerCodableRoundTrip() throws {
    var tracker = CullRunTracker()
    tracker.recordViewed(AssetID(rawValue: "a1"))
    tracker.recordViewed(AssetID(rawValue: "a2"))
    tracker.recordSkipped(AssetID(rawValue: "a3"))
    let data = try JSONEncoder().encode(tracker)
    let restored = try JSONDecoder().decode(CullRunTracker.self, from: data)
    XCTAssertEqual(restored, tracker)
}
```

- [ ] **Step 2: Write failing file persistence test** — save to a temp URL, load back, assert equality. Include a test for the missing-file case (load returns nil when file doesn't exist).

- [ ] **Step 3: Run to verify failures** — `swift test --filter CullRunTrackerTests 2>&1 | tail -10`. Expected: the new tests FAIL (CullRunTracker is not Codable).

- [ ] **Step 4: Add Codable conformance** to `CullRunTracker` — since `Set<AssetID>` is Codable when `AssetID` is `Codable` (check; if `AssetID` is a `String` rawValue struct it is), just add `Codable` to the conformance list. If `AssetID` is not Codable, add a `Codable` conformance to `AssetID` in `TeststripCore` first.

- [ ] **Step 5: Add `CullRunTracker.Persistence`** — a namespace with `save` and `load`:

```swift
extension CullRunTracker {
    enum Persistence {
        static func save(_ tracker: CullRunTracker, to url: URL) throws {
            let data = try JSONEncoder().encode(tracker)
            try data.write(to: url, options: .atomic)
        }
        static func load(from url: URL) -> CullRunTracker? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CullRunTracker.self, from: data)
        }
    }
}
```

- [ ] **Step 6: Run tests + commit** — `swift test --filter CullRunTrackerTests`

---

### Task 2: Integrate tracker persistence into AppModel lifecycle

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `cullRunTrackerURL`, save on mutation, load on resume)
- Test: `Tests/TeststripAppTests/CullRunTrackerTests.swift` or new `CullRunLifecycleTests.swift`

**Interfaces:**
- Consumes: `CullRunTracker.Persistence` from Task 1, existing `startCullRunTracking()`, `beginCullingSession`
- Produces: `cullRunTrackerURL` computed property, `saveCullRunTracker()`, `resumeCullRunIfNeeded()`

- [ ] **Step 1: Write failing test** — create an AppModel, start a cull run, record some viewed/skipped, save the tracker, create a fresh AppModel over the same catalog, call resume, assert the tracker is restored.

- [ ] **Step 2: Run to verify failure** — `swift test --filter CullRunLifecycleTests 2>&1 | tail -10`

- [ ] **Step 3: Add `cullRunTrackerURL`** to AppModel — a computed property that returns the path to `cull-run-tracker.json` in the app-support directory (or a temp directory in tests).

- [ ] **Step 4: Add `saveCullRunTracker()`** — called after `recordViewed` and `recordSkipped` (or at a single choke point). Keep it cheap (atomic write).

- [ ] **Step 5: Add `resumeCullRunIfNeeded()`** — called during `beginCullingSession` when resuming an existing run (detected by matching asset-set ID). Loads the tracker and merges it.

- [ ] **Step 6: Run tests + commit**

---

### Task 3: Extend CullCompletionPresentation with session-level fields (unification)

**Files:**
- Modify: `Sources/TeststripApp/CullCompletionPresentation.swift` (add optional session fields)
- Modify: `Sources/TeststripApp/AppModel.swift` (populate unified fields, deprecate `CullingSessionCompletionSummary`)
- Test: `Tests/TeststripAppTests/CullCompletionTests.swift`

**Interfaces:**
- Consumes: existing `CullCompletionPresentation`, `CullingSessionCompletionSummary`
- Produces: `CullCompletionPresentation` with optional `sessionID`, `title`, `picksSetID`, `remainingSingleAssetIDs`; `CullingSessionCompletionSummary` content flows through the unified type

- [ ] **Step 1: Write failing test** — assert that `CullCompletionPresentation` can carry session-level fields (sessionID, title, picksSetID, remainingSingleAssetIDs) and that the existing `summary()` factory still works without them (defaults nil/empty).

- [ ] **Step 2: Write failing test** — assert that a formal-session completion (via `updateCullingSessionCompletion`) populates the unified `CullCompletionPresentation` with the same counts that `summary()` would produce, so the two paths never disagree.

- [ ] **Step 3: Run to verify failures**

- [ ] **Step 4: Add session-level fields** to `CullCompletionPresentation`:

```swift
var sessionID: WorkSessionID?
var title: String?
var picksSetID: AssetSetID?
var remainingSingleAssetIDs: [AssetID] = []
```

- [ ] **Step 5: Unify the completion paths** — in `updateCullingSessionCompletion`, instead of setting `cullingSessionCompletion`, set a `cullCompletion` property on AppModel that carries both the ad-hoc counts and the session-level fields. `CullingSessionCompletionSummary` becomes a thin adapter or is removed.

- [ ] **Step 6: Update LibraryGridView** to read from the unified `cullCompletion` instead of `cullingSessionCompletion`. Migrate the "View Picks" and "Cull Remaining Singles" buttons.

- [ ] **Step 7: Run tests + commit**

---

### Task 4: ⌘R start card

**UX contract** (tutorial §2): ⌘R shows a start card with batch stats
(`211 photos · 63 stacks (batch is 34% bursts)`), a lens selector (default
Everything; narrowing to Potential Picks / Likely Issues is **loud** — the
run header permanently reads `Showing 96 of 211 — 115 hidden by lens`), and
Auto-advance + Land-on-recommended toggles (both default on). Press Return
to begin. Traversal is always capture order.

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (add ⌘R menu command, start card view)
- Modify: `Sources/TeststripApp/AppModel.swift` (add `startCullRun()`, batch stats)
- Create: `Sources/TeststripApp/CullStartCardPresentation.swift` (pure presentation type)
- Test: `Tests/TeststripAppTests/CullStartCardTests.swift`, `Tests/TeststripAppTests/CullRunLifecycleTests.swift`

**Interfaces:**
- Consumes: existing `beginCullingSession(named:intent:)`, `showStartCullingPopover()`, `allCullingStacks(for:)`
- Produces: ⌘R menu command; `CullStartCardPresentation` with batch stats (photoCount, stackCount, burstPercentage); `startCullRun()` convenience

- [ ] **Step 1: Write failing test** for `CullStartCardPresentation` — assert that it computes `photoCount`, `stackCount`, and `burstPercentage` from the current asset set, and that lens narrowing produces a `hiddenCount`.

- [ ] **Step 2: Write failing test** — assert that `startCullRun()` calls `beginCullingSession` with the suggested session name and switches to the loupe view.

- [ ] **Step 3: Run to verify failures**

- [ ] **Step 4: Create `CullStartCardPresentation`** — a pure value type with batch stats and lens-narrow accounting:

```swift
struct CullStartCardPresentation: Equatable {
    var photoCount: Int
    var stackCount: Int
    var burstPercentage: Int  // stackCount / photoCount * 100, rounded
    var lensHiddenCount: Int  // 0 for Everything; non-zero when narrowed
    var autoAdvanceEnabled: Bool
    var landOnRecommended: Bool
}
```

- [ ] **Step 5: Add `startCullRun()`** to AppModel — a thin convenience over `beginCullingSession(named: suggestedCullingSessionName)` that handles the common case (no custom name/intent needed).

- [ ] **Step 6: Add ⌘R command** to the Cull menu — a new menu item "Start Culling" with `keyEquivalent: "r"` and `.command` modifier. Follow the existing ⌘1–⌘6 pattern (AppKit menu, not SwiftUI `.keyboardShortcut`).

- [ ] **Step 7: Wire the start card view** in `LibraryGridView` — show batch stats, lens selector, and auto-advance/land-on-recommended toggles. The existing `showStartCullingPopover` path can be extended or replaced.

- [ ] **Step 8: Run tests + commit**

---

### Task 5: Loud accounting — extend CullingProgressSummary with run counts

**UX contract** (tutorial §2): lens narrowing is **loud** — the run header
permanently reads `Showing 96 of 211 — 115 hidden by lens`. The scope line
already shows `✓ picks · ✕ rejects · N left`; SP-D adds `⊘ skipped ·
◌ unviewed · ✨ awaiting · hidden by lens`.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (extend `CullingProgressSummary`)
- Modify: `Sources/TeststripApp/ScopeLinePresentation.swift` (render new counts)
- Test: `Tests/TeststripAppTests/ScopeLinePresentationTests.swift` (or new test file)

**Interfaces:**
- Consumes: existing `CullingProgressSummary`, `CullRunTracker`, `pendingAutopilotProposals`
- Produces: `CullingProgressSummary` with `viewedCount`, `skippedCount`, `neverViewedCount`, `awaitingReviewCount`, `hiddenByLensCount`; `ScopeLinePresentation` renders them

- [ ] **Step 1: Write failing test** — assert that `CullingProgressSummary` carries `viewedCount`, `skippedCount`, `neverViewedCount`, `awaitingReviewCount`, `hiddenByLensCount` and that `ScopeLinePresentation.cullStatusText` includes them in the output.

- [ ] **Step 2: Write failing test** — assert that a tentative (✨) flag does NOT count as reviewed (the provenance invariant).

- [ ] **Step 3: Write failing test** — assert that `hiddenByLensCount` is non-zero when a lens narrows the run (tutorial: "Showing 96 of 211 — 115 hidden by lens").

- [ ] **Step 4: Run to verify failures**

- [ ] **Step 5: Extend `CullingProgressSummary`** with the new fields:

```swift
public var viewedCount: Int
public var skippedCount: Int
public var neverViewedCount: Int
public var awaitingReviewCount: Int
public var hiddenByLensCount: Int
```

- [ ] **Step 6: Populate the new fields** in `cullingProgressSummary` — `viewedCount = cullRunTracker.viewedAssetIDs.count`, `skippedCount = cullRunTracker.skippedAssetIDs ∩ scope ∖ decided`, `neverViewedCount = totalAssetCount - viewedCount`, `awaitingReviewCount = pendingAutopilotProposals count`, `hiddenByLensCount = totalAssetCount - scopeAssetCount` (when a lens narrows).

- [ ] **Step 7: Render in `ScopeLinePresentation`** — extend `cullStatusText` to show the new counts. Format: `"854 photos · 326 stacks · ✓ 15 · ✕ 5 · ⊘ 3 skipped · ◌ 12 unviewed · ✨ 4 · 834 left"`. Omit zero-count segments (keep it loud, not noisy). When a lens narrows, prepend `"Showing 96 of 211 — 115 hidden by lens"` (tutorial §2).

- [ ] **Step 8: Run tests + commit**

---

### Task 6: Completion-summary one-key scoped mini-runs

**UX contract** (tutorial §7): the completion summary shows
`Picked 214 · Rejected 1,682 · Undecided 47 · Skipped 12 · Never viewed 0 · ✨ awaiting review 96 · hidden by lens 0`.
Each line is a **one-key jump (1–6)** back into a scoped mini-run — clear the
undecideds, audit the never-viewed, open Review AI suggestions. Ceremonies
(Export, Move Rejects, Save Picks as Set) are separate from the numbered
mini-run jumps.

**Files:**
- Modify: `Sources/TeststripApp/CullCompletionPresentation.swift` (add mini-run actions, numbered jumps)
- Modify: `Sources/TeststripApp/AppModel.swift` (add mini-run starters)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (wire numbered buttons)
- Test: `Tests/TeststripAppTests/CullCompletionTests.swift`

**Interfaces:**
- Consumes: existing `cullRemainingSinglesFromCullingCompletion`, `applyCullCompletionReviewPicks`
- Produces: numbered one-key jumps (1-6) for: undecided, skipped, never-viewed, ✨ awaiting review; each starts a scoped mini-run

- [ ] **Step 1: Write failing test** — assert that `CullCompletionPresentation` carries `undecidedCount`, `skippedCount`, `neverViewedCount`, `awaitingReviewCount`, `hiddenByLensCount` and that each non-zero count produces a numbered mini-run jump.

- [ ] **Step 2: Write failing test** — assert that `cullUndecidedFromCompletion()` starts a new culling session scoped to undecided frames, `cullSkippedFromCompletion()` scopes to skipped, `cullNeverViewedFromCompletion()` scopes to never-viewed. Each is a fresh `beginCullingSession` over a snapshot asset set.

- [ ] **Step 3: Run to verify failures**

- [ ] **Step 4: Add mini-run jump fields** to `CullCompletionPresentation` — a `miniRuns: [MiniRun]` array where each `MiniRun` has a `number` (1-6), a `label`, a `count`, and an `action`. Only non-zero counts produce entries. The existing `actions` array (Export, Move Rejects, etc.) stays separate — ceremonies, not mini-runs.

- [ ] **Step 5: Add mini-run starters** to AppModel — `cullUndecidedFromCompletion()`, `cullSkippedFromCompletion()`, `cullNeverViewedFromCompletion()`, `reviewAIFromCompletion()` — each modeled on `cullRemainingSinglesFromCullingCompletion`: create an asset set from the relevant IDs, apply it, call `beginCullingSession`.

- [ ] **Step 6: Wire numbered buttons** in `LibraryGridView` — each mini-run renders as a numbered row ("1 · 47 undecided", "2 · 12 skipped", etc.). Number keys 1-6 trigger the corresponding mini-run when the completion summary is showing. Ceremonies (Export, Move Rejects, Save Picks as Set) render below the numbered jumps, matching the tutorial's layout.

- [ ] **Step 7: Run tests + commit**

---

### Task 7: E2E scenario cards

**Files:**
- Create: `test/scenarios/cull-030-start-card.md` — ⌘R start card scenario
- Create: `test/scenarios/cull-031-loud-accounting.md` — loud accounting scenario
- Create: `test/scenarios/cull-032-exact-resume.md` — exact resume scenario
- Create: `test/scenarios/cull-033-completion-mini-runs.md` — one-key mini-runs scenario

- [ ] **Step 1: Author scenario cards** following the established pattern (see `cull-016-completion-stage.md` for the reference format: Pre-state, Steps, Expected, Cleanup, Sharp edges).

- [ ] **Step 2: Run in VM** via `script/vm_scenario_run.sh` — these are interactive AX-driven tests, VM-bound per the project doctrine.

- [ ] **Step 3: Assert against catalog ground truth** — the SQLite catalog is authoritative, not the UI render.

---

## Sequencing

Tasks 1-2 (persistence) and Task 4 (⌘R) are independent and can run in
parallel. Task 3 (unification) is independent of 1-2 and 4. Task 5 (loud
accounting) depends on Task 1 (tracker has viewed/skipped data). Task 6
(mini-runs) depends on Task 3 (unified completion type). Task 7 (scenarios)
depends on all others.

Recommended parallel dispatch:
- Wave 1: Tasks 1+2, 3, 4 (three agents, disjoint files)
- Wave 2: Task 5 (after 1), Task 6 (after 3)
- Wave 3: Task 7 (after all)
