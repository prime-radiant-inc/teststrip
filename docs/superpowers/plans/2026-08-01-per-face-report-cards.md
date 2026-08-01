# Per-Face Report Cards (SP-B, kata #11) Implementation Plan — Radical Decomposition

> **For agentic workers:** Execute via superpowers:subagent-driven-development, adapted per this plan's Execution Mechanics: tasks are deliberately tiny, test-writing and implementation are SEPARATE subagents, spikes run first and in parallel, and independent lanes run concurrently in their own worktrees. The controller (main session) owns merges, gates, and the constants freeze.

**Goal:** Per-face quality chips in the close-ups panel and traffic-light roll-up dots on the burst rail, from one in-app analyzer + store (spec: `docs/superpowers/specs/2026-07-31-per-face-report-cards-design.md`).

**Architecture:** `FaceReportAnalyzer` (Core, pure: image + CIDetector detections → scored `FaceReport`s) feeds `FaceReportStore` (app, observable cache + stack sweep). Tiles render four icon-in-donut chips via `FaceSignalChipView`; rail cells read the store's per-frame roll-up. Nothing persisted, no worker/schema changes.

**Tech Stack:** Swift 6/SwiftPM, Vision (`VNDetectFaceRectanglesRequest`), CoreImage (existing CIDetector pass), XCTest, SwiftUI.

## Global Constraints

- No new `EvaluationKind`, no schema/worker/protocol changes, nothing persisted (spec: out of scope).
- Chip row: always all four, fixed order **eyes, sharpness, facing, light**; 17pt donut, monochrome SF Symbol inside; smile lives in tile hover/AX only.
- Roll-up rule: a face grades red only if a red-grade signal AND `prominence >= prominenceFloor`; below-floor faces cap at yellow. Frame roll-up = worst face grade; `nil` when no faces. Absence of a dot means "nothing known", never "known good".
- Failure honesty: Vision failure/no-match → `facing == nil` → empty ring + "no read" hover. Never a fake score or fake green.
- `SignalGlyphView` and the reads card are untouched.
- TDD with adversarial split: **the test author and the implementer are different subagents; implementers may not modify test files.** A test the implementer believes is wrong is a BLOCKED report to the controller, never an edit.
- All gates (`swift test`, `make verify`) run FOREGROUND — background runs get reaped (session lesson).
- Branch: `feat/face-report-cards` in `.worktrees/face-report-cards`; lanes in their own worktrees (below). Baseline at branch point: 2281/0/15.

## Constants (provisional until Gate G0)

All grading constants live in `FaceReportAnalyzer.Constants` with WHY comments. Tests reference them symbolically so G0 refinements don't rewrite tests. Provisional values the spikes must confirm or replace:

| Constant | Provisional | Spike |
|---|---|---|
| `facingScore` formula | `max(0, 1 - (abs(yaw) + abs(pitch)) / (π/2))` | S1 |
| Vision↔CIDetector match | greatest IoU, floor 0.3; below floor → unmatched | S1 |
| `redThreshold` (per-signal score) | `< 0.35` | S1/S2 |
| `yellowThreshold` | `< 0.70` | S1/S2 |
| `prominenceFloor` (area ratio) | `0.015` | S2 |
| eyes score | open `1.0`, closed `0.0` (binary) | — |
| light score | `balancedExposure` over crop luminance | S2 |
| sharpness score | normalized neighbor-delta over crop | S2 |
| Chip SF Symbols (eyes/sharp/facing/light) | `eye`, `triangle`, `person.crop.circle.badge.questionmark`→spike picks, `sun.max` | S3 |

---

## Dependency DAG

```
S1 (Vision pose spike)   ─┐
S2 (crop metrics spike)  ─┼─► G0: controller freezes Constants ─► T0 (types freeze)
S3 (chip layout spike)   ─┘                                        │
        ┌───────────────────┬──────────────────┬───────────────────┤
        ▼                   ▼                  ▼                   ▼
   Lane A (analyzer)   Lane B (chips)     Lane C (store)     Lane D (roll-up)
   A1 tests → A2 impl  B1 tests → B2     C1 tests → C2      D1 tests → D2
        │ RA review         │ RB              │ RC                │ RD
        └───────────────────┴────────┬────────┴───────────────────┘
                                     ▼
                    M: controller merges lanes → feat/face-report-cards
                                     ▼
                 I1 → I2 → I3 (serial integration, LibraryGridView)
                 E1 (scenario card) runs parallel with I1–I3
                                     ▼
                        RI: integration review (sonnet)
                                     ▼
                        E2: live VM run (faces variant)
                                     ▼
                        F: final whole-branch review (opus) → merge
```

Parallelism rules: S1∥S2∥S3; after T0, lanes A∥B∥C∥D (each in its OWN worktree — two agents must never build in the same worktree concurrently); E1 ∥ I1–I3. Everything else serial.

---

## Phase 0 — Derisk spikes (parallel, throwaway, no production code)

Spikes write scratch scripts (scratchpad or `/tmp`-style dirs, never committed) and a findings report to `.superpowers/sdd/2026-08-01-face-report-cards/spike-<n>-report.md`. Model: sonnet. Each ends with concrete recommended constants.

### S1 — Vision pose + matching spike
Question to kill: does `VNFaceObservation` deliver usable yaw/roll/pitch on this OS for our preview sizes, and does IoU matching against CIDetector boxes actually pair faces correctly?
- Inputs: `sample-data/photos/faces/` fixtures (main checkout); existing code to crib: `FaceRecognitionEmbedder.swift:16-56` (Vision request setup), `FaceExpressionEvaluationProvider.swift:151` (CIDetector setup, coordinate convention — CIDetector is bottom-left, `DetectedFaceExpression.normalizedBounds` is top-left: the spike must nail the flip needed for IoU).
- Output: per-fixture table (faces, yaw/pitch values, pitch nil-rate, IoU of matched pairs, mismatches); recommended facing formula, IoU floor, red/yellow thresholds for facing; note whether `pitch` is reliably non-nil (macOS 12+ API — if nil in practice, formula degrades to yaw-only and the report says so).

### S2 — Crop metrics spike
Question to kill: do `balancedExposure` and neighbor-delta sharpness, computed over face CROPS, separate good from bad faces on real fixtures?
- Inputs: same fixtures; `PreviewPixelMetrics.swift:37,61,70`, `LocalImageMetricsEvaluationProvider.swift:20,113` as the formulas; crops via `DetectedFaceExpression.normalizedBounds`.
- Output: score distributions for visibly-good vs visibly-bad faces (the fixtures include closed-eye/soft cases — eyeball and label them in the report); recommended red/yellow thresholds for light + sharpness, normalization for sharpness, and `prominenceFloor` (measure the fixtures' subject vs background face area ratios).

### S3 — Chip layout spike
Question to kill: do four 17pt donuts with inset monochrome SF Symbols fit a 112pt row and read at a glance?
- Build a throwaway SwiftUI preview harness (scratch target or Xcode preview in a scratch worktree — nothing committed) rendering the row with candidate symbols (eyes: `eye`; sharpness: `triangle` vs `camera.metering.spot`; facing: `person.crop.circle` family vs `arrow.turn.right.up` composites; light: `sun.max`), at both appearances.
- Output: chosen four symbol names (must exist on the deployment target), measured row width at 17pt + 7pt gaps, screenshot(s) in the report dir.

### G0 — Constants freeze (controller, not a subagent)
Controller reads the three reports, fixes every value in the Constants table above, and records the frozen block in the ledger. Lanes consume the frozen values; any later change to a constant is a plan change, not an implementer liberty.

---

## Phase 1 — T0: types freeze (one tiny task, unblocks all lanes)

**Files:** Create `Sources/TeststripCore/People/FaceReport.swift`, `Sources/TeststripApp/FaceReportStore.swift`, `Sources/TeststripApp/FaceChipPresentation.swift` — types + signatures ONLY, bodies `fatalError("unimplemented")` or trivially empty; `swift build` must pass. Model: haiku (pure transcription, zero test surface). Commit: `feat: SP-B type skeletons (types freeze)`.

```swift
// FaceReport.swift (TeststripCore)
public struct FaceReport: Equatable, Sendable {
    public enum Grade: String, Equatable, Sendable { case green, yellow, red }
    public var normalizedBounds: CGRect   // top-left origin, matches DetectedFaceExpression
    public var eyesClosed: Bool
    public var isSmiling: Bool
    public var facing: Double?            // nil = Vision unmatched/failed; never faked
    public var light: Double
    public var sharpness: Double
    public var prominence: Double
    public var grade: Grade
    public init(normalizedBounds: CGRect, eyesClosed: Bool, isSmiling: Bool, facing: Double?,
                light: Double, sharpness: Double, prominence: Double, grade: Grade)
}

public struct FrameFaceReport: Equatable, Sendable {
    public var faces: [FaceReport]        // sorted by prominence descending
    public var rollUp: FaceReport.Grade?  // nil when faces.isEmpty
    public var previewCacheGeneration: Int
    public init(faces: [FaceReport], rollUp: FaceReport.Grade?, previewCacheGeneration: Int)
}

public enum FaceReportAnalyzer {
    public enum Constants { /* frozen values from G0, each with a WHY comment */ }
    // Pure: image + detections in, reports out. Vision runs inside; its failure
    // yields facing == nil, never a thrown error.
    public static func analyze(image: CGImage, detections: [DetectedFaceExpression]) -> [FaceReport]
    public static func rollUp(_ faces: [FaceReport]) -> FaceReport.Grade?
}
```

```swift
// FaceReportStore.swift (TeststripApp) — follow AppModel's observation pattern
@MainActor
public final class FaceReportStore {   // + the observation macro/conformance AppModel uses
    public private(set) var reportsByAssetID: [AssetID: FrameFaceReport] = [:]
    public init()
    // nil when absent OR stale (entry.previewCacheGeneration != currentGeneration)
    public func report(for assetID: AssetID, currentGeneration: Int) -> FrameFaceReport?
    public func ingest(_ report: FrameFaceReport, for assetID: AssetID)
    // Cancels any prior sweep; analyzes currentAssetID first, then stackAssetIDs
    // in given order; `analyze` returns nil for frames with no usable preview (skipped).
    public func beginSweep(stackAssetIDs: [AssetID], currentAssetID: AssetID,
                           analyze: @escaping @Sendable (AssetID) async -> FrameFaceReport?)
    public func cancelSweep()
}
```

```swift
// FaceChipPresentation.swift (TeststripApp)
enum FaceChipPresentation {
    enum Signal: String, CaseIterable, Equatable { case eyes, sharpness, facing, light } // fixed order
    struct Chip: Equatable {
        let signal: Signal
        let score: Double?          // nil = no read (facing only)
        let symbolName: String      // from G0/S3
        let accessibilityText: String  // "Eyes 100%" / "Facing — no read"
    }
    static func chips(for report: FaceReport) -> [Chip]   // always 4, fixed order
    static func tileAccessibilityValue(for report: FaceReport) -> String // carries eyes state + smile
}
```

---

## Phase 2 — Parallel red/green lanes

Mechanics: controller creates 4 worktrees off `feat/face-report-cards` post-T0: `.worktrees/spb-{analyzer,chips,store,rollup}`, branches `spb/{analyzer,chips,store,rollup}`. Each lane = test task → impl task → lane review, then the controller merges the lane branch back (disjoint files → clean merges; analyzer=Core file+its tests, chips=presentation+view+tests, store=store+tests, rollup=rollUp func tests+rail-dot presentation helpers). Test authors: sonnet. Implementers: sonnet. Lane reviewers: sonnet. **Implementers may not touch `Tests/` in their lane; test authors may not write implementation.**

Every test task's contract: write the tests, run the filter FOREGROUND, capture the red transcript (each test must fail for the stated reason — a compile failure against T0 skeletons' `fatalError` bodies counts where noted), commit `test: ...`. Every impl task: make them green without touching tests, full filter green, commit `feat: ...`.

### Lane A — analyzer

**A1 (tests):** `Tests/TeststripCoreTests/FaceReportAnalyzerTests.swift`. Behaviors (each a named test, expected red = `fatalError` crash or assertion failure):
- Facing formula: synthetic `VNFaceObservation`s aren't constructible with arbitrary pose — so the formula is factored: A1 tests a small exposed pure helper `Constants.facingScore(yaw:pitch:)` at frontal (→1), the frozen yellow/red boundary angles, and nil-pitch degradation per S1's report.
- IoU matching via exposed pure helper `Constants.matchScore(_:_:)` / the top-left↔bottom-left flip: overlapping boxes match, sub-floor IoU → unmatched (facing nil).
- Light/sharpness: synthetic CGImages (flat gray → balancedExposure 1 at mid-gray, ~0 at black/white; checkerboard vs flat for sharpness ordering — construct via `CGContext`).
- Prominence = bounds area ratio; faces sorted prominence-descending.
- Grading: red requires red signal + prominence ≥ floor (assert the negative: sub-floor face with 0.0 sharpness grades yellow); all-good → green; `rollUp`: worst face wins; empty → nil; frame whose only red faces are sub-floor rolls up yellow, never red.
- Vision-failure honesty: `analyze` on a 1×1 image with a fabricated detection → facing nil, other scores still computed.

**A2 (impl):** `FaceReport.swift` bodies + Constants with WHY comments. Vision request on the provided image, matching, scores, grades, rollUp.

**RA (review):** verify red transcripts genuine, re-derive 3 grading cases by hand, check constants match G0 freeze, no test edits by implementer (`git log --follow` on the test file).

### Lane B — chips

**B1 (tests):** `Tests/TeststripAppTests/FaceChipPresentationTests.swift`: 4 chips always, fixed order; scores map through; facing nil → `score == nil` + accessibilityText "Facing — no read"; percentage rounding in AX strings ("Eyes 100%", "Light 62%"); symbol names = G0's four; `tileAccessibilityValue` carries eyes state + smile wording (exact strings specified in G0 ledger entry by controller — copy verbatim).
**B2 (impl):** `FaceChipPresentation` + `Sources/TeststripApp/FaceSignalChipView.swift` (17pt ring via `Circle().trim`, same construction as `SignalGlyphView` at SignalGlyphView.swift:6 but with the inset SF Symbol instead of the word; `.help` + AX label from chip.accessibilityText; score nil → empty track ring).
**RB:** presentation-test verification plus `swift build`; visual appearance was de-risked by S3, not re-litigated here.

### Lane C — store

**C1 (tests):** `Tests/TeststripAppTests/FaceReportStoreTests.swift`, injected `analyze` closures (no images):
- `report(for:currentGeneration:)` nil on absent AND on stale generation; hit on match.
- Sweep order: records analyze-call order == current-first-then-stack-order (closure appends to an actor/array).
- Skip semantics: closure returns nil → no entry; later `ingest` fills it.
- Cancellation: `beginSweep` twice — first sweep's pending analyzes don't land after the second starts (gate the first closure on an unfulfilled continuation; assert its result is discarded).
- Progressive publish: entries appear one at a time as each analyze resolves.
**C2 (impl):** structured-concurrency sweep task, cancellation, main-actor ingestion.
**RC:** concurrency-focused: race between cancel and in-flight ingest; verify no retain of stale sweep results.

### Lane D — roll-up surfaces (presentation only)

**D1 (tests):** `Tests/TeststripAppTests/FaceRailDotPresentationTests.swift`: a pure helper (new file `Sources/TeststripApp/FaceRailDotPresentation.swift`, added in this lane) mapping `FrameFaceReport?` → optional dot color/AX: nil report → no dot; empty faces → no dot; grade → color name + AX "Worst face: yellow" style strings (exact strings in G0 ledger); header parity helper: header dot == rail dot for same report + "N faces" count string.
**D2 (impl):** the helper.
**RD:** standard.

### M — lane merges (controller)
Merge order A → C → B → D (A first so C/B rebase cleanly if type tweaks leaked; they shouldn't — T0 froze types; any lane needing a type change is BLOCKED → controller decision). After merges: full `swift test` FOREGROUND green on `feat/face-report-cards`; delete lane worktrees/branches.

---

## Phase 3 — Serial integration (single worktree, LibraryGridView + AppModel glue)

**I1 — wire the pass and the sweep.** `AppModel` owns a `FaceReportStore` instance (property near `showsCullFacesPanel`, AppModel.swift:2203 vicinity). `refreshCloseUps` (LibraryGridView.swift:4259) feeds its detections + image through `FaceReportAnalyzer.analyze` and `ingest`s the selected frame's `FrameFaceReport` (generation from `model.previewCacheGeneration(for:)`). Stack landing triggers `beginSweep` with the stack's asset IDs (hook where the cull loupe `.task` already fires per-frame, same site SP-C's prefetch uses — `requestVisibleCullPreview` vicinity); analyze closure loads each frame's best cached preview (`loupePreviewURL` ladder) off-main, runs CIDetector + analyzer, returns nil when no preview. Tests: `Tests/TeststripAppTests/FaceReportIntegrationTests.swift` — sweep populates the store for stack siblings, and stale-generation entries recompute. Fixture note: the text placeholders other tests seed are not decodable images; the fixture helper here writes tiny real JPEGs (4×4 via `CGImageDestination`) into the preview cache so the analyze closure exercises the real decode path. Red/green split applies: I1a tests (sonnet) → I1b impl (sonnet), same worktree, sequential.

**I2 — tile UI swap.** `closeUpCropCell` (LibraryGridView.swift:4138): corner dot (9pt, bottom-trailing on the crop), replace `closeUpMarks` row with `HStack` of four `FaceSignalChipView`s from `FaceChipPresentation.chips(for:)`; tile AX value from `tileAccessibilityValue`; retire `closeUpMarks`/`closeUpMarksAccessibilityValue` (delete, they're unreferenced after this). `CloseUpFacesPresentation.sharpnessTone` single-face limitation retired in favor of per-face sharpness (update its tests accordingly — this is the ONE place an integration task touches existing tests; the I2a test author owns that rewrite, red-proofed).

**I3 — rail dot + header.** `cullStackRailCell` (LibraryGridView.swift:4828) ZStack gains top-leading dot overlay from `FaceRailDotPresentation` (store lookup by item asset ID + current generation); close-ups header (`closeUpsRail`, :4109) gains the selected frame's dot + "N faces". AX per D1's strings.

**RI — integration review (sonnet):** the seams: generation keying end-to-end, no main-thread image decode (detached like the existing pass at :4266), sweep lifecycle vs SP-C's prefetch (they share the landing trigger — verify no interference with `cullPrefetchItemIDs` bookkeeping), retired-symbol cleanup complete.

**E1 — scenario card (parallel with I1–I3, separate worktree, docs-only):** `test/scenarios/cull-028-face-report-cards.md` per spec's Testing section: faces-variant VM run; rail dots appear for unvisited stack frames (sweep proof); a no-faces frame asserts dot ABSENCE (falsification leg); chips + AX on the selected frame; header/rail parity. Cites shipped symbols only after M lands — E1 drafts against the spec, and its citation sweep waits for the final commit ordering rule: **citation sweep is the branch's last docs commit**.

---

## Phase 4 — Verification and close

**E2 — live VM run (after RI + E1):** faces variant sync (exercises kata-18 guard for real). Runbook per test/scenarios/README.md; record Run-status with evidence; app bugs → BLOCKED to controller.

**F — final whole-branch review (opus):** full-diff package, ledger Minor triage, `make verify` FOREGROUND, then controller merges to main / closes kata #11 per session conventions.

---

## Execution Mechanics (controller contract)

- Ledger: `.superpowers/sdd/2026-08-01-face-report-cards/progress.md`; every task gets brief+report files there (`<task>-brief.md` / `<task>-report.md`); G0's frozen constants + exact AX strings recorded in the ledger as the single source lanes copy verbatim.
- One build per worktree at a time; lanes are parallel BECAUSE worktrees are separate. Never run two `swift test` in one worktree concurrently.
- Task sizing: if any subagent's task exceeds ~one focused run (say it's ballooning), it reports BLOCKED-TOO-BIG and the controller splits it further — never "keep going heroically".
- Model floors: test authors/implementers/reviewers sonnet (haiku test-ban stands); T0 haiku; F opus.
- Reviews are per-lane and per-integration-step, small and fast, plus the one opus finale. Reviewer prompts carry: the lane's brief, report, diff package, and the frozen-constants block.
- Red proofs are non-negotiable in every test task; implementer-cannot-edit-tests is enforced by review (`git log` on test files).
