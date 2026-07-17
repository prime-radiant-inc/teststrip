# Culling Flow — implementation design

**Status:** approved direction ("go implement it", 2026-07-16). The UX
contract is `docs/design-spikes/2026-07-16-culling-redesign/tutorial.md`
(validated via mockup-e-workstation-v3); this spec covers the engineering
decisions and decomposition. Where this spec and the tutorial disagree, the
tutorial wins on behavior, this spec wins on mechanism.

## What we're building

Rework the Cull workspace's loupe experience into the validated layout and
grammar: current burst on a left rail, photo-only stage, faces+reads panel
right, run strip bottom, one home per fact, uniform keys with or without
bursts, honest AI states, user-origin-only progress, and a real completion
summary. **Evolve the existing views — no rewrites.** Most machinery exists
(stack rail, ✦ ranking via `CullingQualityScore`, verdict presentation,
close-ups, key capture, completion banner); this is a re-plumbing of proven
parts into the settled shell plus targeted new capability.

## Sub-projects (each: spec section → plan → SDD → verify)

- **SP-A — The shell** (this is the bulk): round-3 layout in the Cull
  workspace, key-grammar deltas, honest states, completion summary.
- **SP-B — Per-face report cards**: extend the on-demand CIDetector pass
  with facing/light/prominence, per-face chips + traffic-light roll-ups in
  the faces panel, roll-up dots on burst-rail thumbs.
- **SP-C — Blaze-through correctness**: whole-burst prefetch + next landing
  frame, full Return render-gating.
- **SP-D — Run lifecycle**: start card (⌘R), lenses with loud accounting,
  exact resume, completion-summary one-key jumps into scoped mini-runs.

**Explicitly out of scope for this push** (recorded, not forgotten):
saliency/key-element fallback for faceless frames; kiss/laugh context
models (the eye-state enum carries `shutOK(context)` cases from day one,
but nothing emits them until a context provider exists — never fake it);
per-face signal *persistence* (the live on-demand pass serves the panel;
persist only when a feature needs per-face queryability).

## Resolved open questions (from the spike outcome)

1. **`Return` on a frame you already rejected → force-pick.** Standing on a
   frame and saying "commit the stack, keep this one" is an explicit
   gesture; one predictable rule beats a modal warning. The toast makes the
   flip visible ("Kept 1 (was ✕) · rejected 4").
2. **Commit toast carries the undo affordance** — "⌘Z undoes" in the toast;
   no timed auto-revert, no new mechanism. The stack commit is one undo unit.
3. **Ambient ✨:** run-strip pills carry a small ✨ count chip when a stop
   has tentative flags. One glyph, no more chrome than that.
4. **Red-face-at-a-glance (SP-B):** traffic-light roll-up dots render on the
   burst-rail thumbs (worst face per frame), making "which frame has no
   red" scannable without opening the faces panel.

## SP-A engineering decisions

(Verified against code 2026-07-16; exact line refs live in the SP-A
integration brief and drift fast — re-grep before trusting any citation.)

**Layout.** Rework `LoupeView`'s arrangement (it stays a private struct in
`LibraryGridView.swift`; new pure presentation types get their own
`<Feature>Presentation.swift` files per the established pattern): the
existing stack rail (already left, 148pt) widens into the burst rail
(generous thumbs, rank tint, ✦, ✨, decisions, machine-fact stack label);
the verdict — today a bare line inside the HUD — relocates into a new
right-panel **reads card** beneath the existing close-ups
(`CloseUpFacesPresentation`), forming the faces+reads panel; the stage
keeps only the image, shimmer, decision toast, and the existing
hover-revealed P/X/★ controls (`CullLoupeHoverControlsPresentation` stays
as-is: a transient pointer path, not ambient information — it does not
violate one-home-per-fact); a new bottom **run strip** replaces the
12-thumb filmstrip. Run-strip stops come from the live
`AppModel.allCullingStacks(for:)` path (the same full `AssetStackBuilder`
re-run the filmstrip performs today — NOT `cullingStackListEntries()`,
which is empty outside persisted stack-culling sessions). Its per-render
cost (one SQL query per scoped asset for similarity vectors) is
pre-existing; SP-A names it and accepts it. Status bar gains the triple
counter (`N of total · stack S of Σ · frame F of M`) and a
user-origin-only progress bar. Stack labels are machine facts only
(file-range · count · time) — never curated names.

**Key grammar deltas** (in `CullingShortcut` / `CullingKeyCaptureView`,
same local-monitor pattern — bare keys never become menu equivalents; every
new bare key also gets a row in `CullingCommandMenuPresentation.sections`,
the single source for the `?` overlay and the Culling menu):
- Add `H`/`L` = prev/next stack, `J`/`K` = next/prev frame — pure aliases
  onto the existing shortcut cases. Landing on the stack's ✦ frame already
  ships (`selectCullingStack` → `recommendedStackLandingAssetID`); the new
  work is only the aliases plus a preference for always-land-on-frame-1.
- **Fix the standalone dead keys**: today ↑/↓ silently no-op on a
  non-stacked frame (`selectedCullingStackScope` resolves nil there). Frame
  keys — and their new J/K aliases — fall back to stop-to-stop advance so
  there are no dead keys and one grammar.
- `A` toggles auto-advance (new `cullAutoAdvanceEnabled` state, default
  on). Advance target after P/X: next *undecided* frame in the current
  stack, else the next stack's landing frame.
- `Space` is already decision-free (`selectNextAssetForCulling` writes no
  metadata) — keep it, and record a "skipped" mark for the run summary.
- `Return` already has the right core semantics
  (`promoteCurrentFrameAndRejectSiblings`: force-picks the staged frame
  regardless of prior flag, protects already-picked siblings, rejects the
  rest, writes one `recordMetadataChangeGroup` undo unit, auto-advances;
  standalone = informational no-op toast). SP-A adds: a test for the
  staged-frame-was-rejected force-flip case (untested today), toast wording
  that discloses the flip ("Kept 1 (was ✕) · rejected 4"), and the render
  gate — inert unless `previewURL(for:levels:[.large])` returns non-nil for
  the staged frame (cheap file stat; deep prefetch is SP-C), showing the
  shimmer instead of committing.
- `/` toggles the faces panel. (`F` background-face expansion ships with
  SP-B.)

**Honest states.**
- *Too close to call*: computed from
  `CullingStackRecommendation.normalizedQualityRead` (the 0…1
  confidence-weighted mean, comparable across frames) — NOT the raw
  `qualityScore` ranking sum, which is unnormalized and kind-count-
  dependent. When the top candidates sit within a noise-floor margin
  (initial constant with documented rationale, revisited against corpus
  data later), emit a tied-leader set: no ✦ anywhere, rail banner
  "too close to call — N·N·N", Compare (`C`) preloaded with the tied set.
- *No read yet*: the reads card gates the ENTIRE card on ≥2 rankable
  signals (`normalizedQualityRead.kindCount >= 2`, matching the existing
  verdict-badge gate) — deliberately stricter than today's HUD line, which
  renders content off a single signal. Signals reaching the UI are already
  current-scale-only (SQL-layer gating); no new filtering needed.

**Progress and completion.** "Decided" = user-origin flag, already computed
throughout via `confirmedProjection.flag` (✨ tentative never counts — no
new mechanism needed). Viewed/skipped tracking is wholly new: an in-memory
per-run tracker in SP-A (persisted for exact resume in SP-D — never the
catalog). The completion summary extends `CullCompletionPresentation` (the
ad-hoc, scope-wide mechanism — it fires without a formal session, the
common case); `CullingSessionCompletionSummary` stays nested as-is and the
two unify in SP-D when runs become first-class. New counts: picked /
rejected / undecided / skipped / never-viewed / ✨ awaiting review (a
filter over the in-memory `pendingAutopilotProposals` — no new query).
Ceremony buttons wire to existing flows (Review AI suggestions → autopilot
review; Move rejects → existing relocation, which already excludes
tentative-only rejects; Export picks; Save picks as set). One-key scoped
jumps are SP-D.

**Invariants restated** (tests assert the negative): tentative ✨ flags
never fill progress, never enter the Picks set, never relocate/trash/export;
`Return`-commit writes user-origin flags through the same undoable metadata
path as `P`/`X` today; no sidecar writes beyond existing confirmed-origin
rules; original bytes untouched.

**E2E scenario cards** (authored per feature, VM-bound): grammar walk with
and without bursts (uniform keys, no dead keys); Return commit + toast +
one-unit undo against catalog ground truth; honest states (no-read,
too-close-to-call, land-on-✦); completion summary counts vs catalog;
✨-never-commits negative assertions.

## Sequencing rationale

SP-A first because it's dogfoodable immediately with existing signals (the
bar is "Jesse can cull with it tonight"). SP-B enriches the faces panel
(live CIDetector pass already yields per-face eyes/smile; facing comes free
from Vision yaw/roll/pitch; light/prominence are cheap heuristics — no
schema change). SP-C makes speed honest before big-burst dogfooding. SP-D
completes the run lifecycle. Branches stack on `spike/culling-redesign`;
the lineage merges to `main` together.
