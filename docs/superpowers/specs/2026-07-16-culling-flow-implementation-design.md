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

**Layout.** Rework `LoupeView`'s arrangement, reusing its presentation
types: the existing stack-rail chips become the left burst rail (generous
thumbs, rank tint, ✦, ✨, decisions, machine-fact stack label); the
`CullingAssistPresentation` verdict moves into the right panel's reads card
beneath the existing close-ups (`CloseUpFacesPresentation`); the stage
drops all pills/overlays except shimmer + decision toast; a new bottom run
strip replaces the 12-thumb filmstrip (stops = `AssetStackBuilder` groups
over the current scope: pills for multi-frame stacks, thumbs for
standalones, current highlighted, done ✓, ✨ count chips); status bar gains
the triple counter (`N of total · stack S of Σ · frame F of M`) and a
user-origin-only progress bar. Stack labels are machine facts only
(file-range · count · time) — never curated names.

**Key grammar deltas** (in `CullingShortcut` / `CullingKeyCaptureView`,
same local-monitor pattern — bare keys never become menu equivalents):
- Add `H`/`L` = prev/next stack, `J`/`K` = next/prev frame (synonyms for
  ←→↑↓). On standalone stops, frame keys walk stops — no dead keys.
- `←→`/`HL` land on the stack's ✦ frame (or frame 1 when no
  recommendation); a preference switches to always-frame-1.
- `A` toggles auto-advance (new `AppModel` setting, default on). Advance
  target after P/X: next *undecided* frame in the stack, else next stack's
  landing frame.
- `Space` stays decision-free advance (verify current semantics; if today's
  path writes anything, fix). Track "skipped" per session for the summary.
- `Return` = stack commit: keep staged frame + already-picked siblings,
  reject *undecided* siblings only (adjust
  `keepSelectedStackFrameAndRejectAlternates` if it currently overwrites
  user picks); on standalones, pick + advance. Gate: inert unless the
  staged frame's `.large` preview is in cache (cheap check in SP-A; deep
  prefetch is SP-C) — show the shimmer instead of committing.
- Whole commit = one `metadataUndoStack` unit.
- `/` toggles the faces panel. (`F` background-face expansion ships with
  SP-B.)

**Honest states.**
- *Too close to call*: in `CullingStackRecommendation`, when the top
  candidates' composite scores sit within a noise-floor margin (constant
  calibrated in the plan from the scorer's real distributions, documented
  in-code like the 2026-07-06 threshold work), emit a tied-leader set
  instead of a winner: no ✦, rail banner "too close to call — N·N·N",
  Compare (`C`) preloaded with the tied set.
- *No read yet*: reads card renders the explicit empty state when the
  frame has fewer than 2 rankable current-scale signals (reuse
  `currentScaleSignalSQL` gating); never a fabricated verdict.

**Progress and completion.** "Decided" = user-origin flag on every frame of
the stack (✨ never counts — enforced by reading through
`aiUnconfirmedFields`, which already exists). Track per-session
viewed/skipped sets (in the session snapshot, not the catalog). The
completion banner grows into the summary: picked / rejected / undecided /
skipped / never-viewed / ✨ awaiting review, plus ceremony buttons wired to
existing flows (Review AI suggestions → autopilot review; Move rejects → the
existing relocation flow, which already excludes tentative-only rejects;
Export picks; Save picks as set). One-key scoped jumps are SP-D.

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
