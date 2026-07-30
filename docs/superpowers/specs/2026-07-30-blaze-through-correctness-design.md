# Blaze-through correctness (SP-C, kata #10) — design

**Decision date:** 2026-07-30. Brainstormed with Jesse. Parent spec:
`docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md`
("SP-C — Blaze-through correctness: whole-burst prefetch + next landing
frame, full Return render-gating").

## Problem

Blazing through a cull run outpaces preview generation. Two symptoms:

1. **Cold frames.** The only prefetch today
   (`AppModel.prefetchLoupeNeighborLargePreviews`, AppModel.swift:9310) warms
   `index±1` in *deck* order — wrong for bursts: the tail of a 20-frame stack
   and the next stack's landing frame are always cold.
2. **Lost Return keystrokes.** The SP-A render gate (AppModel.swift:6372)
   correctly refuses to commit a stack decision while the staged frame's
   `.large` preview is missing, but the recovery is a toast plus a manual
   re-press.

## Decisions (Jesse, 2026-07-30)

1. **Return gate → armed commit.** A gated Return arms the decision: the
   frame's render jumps the queue and the commit fires automatically the
   moment the render lands. Any other input disarms.
2. **Prefetch reach = sliding window of stacks.** The whole current burst,
   plus the landing frames of the next 3 stacks (and the previous stack's
   landing frame, so a single ← lands warm).
3. **Approach A** — model-level planner + armed-commit state in `AppModel`,
   reusing the existing gated request path. No queue, worker-protocol, or
   schema changes.

## Design

### Prefetch planner

**Pure warm-set function** (unit-testable, no side effects). Input: the cull
stop sequence (`cullingStopSequence()`, AppModel.swift:6945), the current
stack, and the staged frame. Output: an ordered `[(assetID, PreviewLevel)]`
want list, all at `.large`:

1. The current burst's frames, starting at the staged frame and radiating
   outward through rail order — following frames first, then earlier ones
   (forward motion dominates).
2. The landing frame of each of the next 3 stacks, in order, computed with
   the existing `recommendedStackLandingAssetID(for:)` (AppModel.swift:7202)
   so the warmed frame is the frame the app will actually land on.
3. The previous stack's landing frame (one entry).

Frames whose `.large` already exists on disk may appear in the want list;
the request path's short-circuit drops them.

**Driver.** Runs on every cull selection change, hooked where
`requestVisibleLoupePreview` (AppModel.swift:9283) already fires per-frame.
In cull mode (cull chrome shown) it **replaces** the deck-order ±1 neighbor
prefetch; non-cull loupe keeps the existing behavior unchanged. Every want
goes through the existing `requestPreview(assetID:level:placement:)`
(AppModel.swift:8926) at `placement: .back`, so the availability gate
(`isAvailableForPreviewGeneration`), the 3-attempt cap
(`previewGenerationAttemptsExhausted`, AppModel.swift:9333), dedup against
queued items, and the on-disk short-circuit all apply by construction —
the retry-storm invariants hold with no new request path.

**Window slide.** The planner records the queue item IDs it enqueued. When
the desired set changes, items that (a) it enqueued, (b) are no longer
wanted, and (c) are still undispatched are cancelled via the supervisor's
existing `cancel(id:)` (WorkerSupervisor.swift:195). In-flight renders
finish naturally. Bound: the queue holds at most ~one burst + 4 landing
frames of planner work regardless of skip speed, and stale warming never
delays the current burst.

### Armed commit

New `AppModel` state: the asset ID of an armed stack decision (at most one).

- **Arming.** When Return on a multi-frame stack hits the render gate
  (`promoteCurrentFrameAndRejectSiblings`, AppModel.swift:6357), instead of
  toast-and-drop: record the staged asset ID, request its `.large` at
  `placement: .front` (the request path already promotes an existing queued
  item via `promoteQueuedItem`), and toast
  **"Rendering full preview… will keep when ready"**.
- **Refusing to arm.** If the frame can never render — availability blocks
  generation or the attempt cap is exhausted — do not arm; toast
  **"Preview unavailable — not committed"**.
- **Firing.** The preview-completion path
  (`invalidatePreviewCacheIfNeeded`, AppModel.swift:10416) checks the armed
  asset; when its `.large` now resolves on disk, disarm and run
  `promoteCurrentFrameAndRejectSiblings` — same force-pick semantics, same
  single `recordMetadataChangeGroup` undo unit, same disclosure toast as an
  ungated Return. Fires at most once.
- **Disarming.** Any intervening input kills the arm: any other culling
  shortcut, any selection or stack change, exiting cull mode. The armed
  commit can therefore never fire against a frame the user is no longer
  staging. A render *failure* for the armed frame also disarms, with the
  "Preview unavailable — not committed" toast. Re-pressing Return while
  armed is a no-op.
- **Provenance unchanged.** The deferred commit is the same explicit user
  gesture; picks/rejects land `origin = user` exactly as today.

### Out of scope

- Queue priorities (`PreviewPriority` stays unconsumed), worker-protocol or
  schema changes.
- Non-cull loupe prefetch behavior.
- Warming levels other than `.large`, or whole-next-burst warming.
- Persisted-stack-session traversal differences beyond what
  `recommendedStackLandingAssetID` already unifies.

## Testing

**Unit (TDD):**

- Warm-set function: radiating order within the burst; next-3 landing
  frames in order; previous landing included; correct behavior at sequence
  edges (first/last stacks, single-frame neighbors).
- Slide cancellation: only planner-enqueued, only out-of-window, only
  undispatched items are cancelled.
- Gate filtering: blocked availability and exhausted attempts produce no
  request (assert the negative).
- Armed commit: arms on gated Return; fires exactly once on completion;
  disarms on each input kind, on selection change, on cull exit, on render
  failure; refuses to arm when rendering cannot succeed; provenance of the
  deferred commit is `user`.

**End-to-end (scenario card, VM):** new `cull-` card:

1. Seed a burst; land on its stack; **without visiting** the burst's later
   frames or the next stack, assert their `.large` preview files appear on
   disk (filesystem ground truth — prefetch proof).
2. Delete the staged frame's `.large` file; press Return; assert the toast
   and that **no** pick/reject flags are in SQLite yet (falsification leg);
   after the re-render lands, assert the flags committed with
   `origin = user`.
3. Arm, then press a different key; assert the decision never lands.

Reconcile any existing card that documents the re-press behavior of the
SP-A gate.
