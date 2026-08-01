# Per-face report cards (SP-B, kata #11) — design

**Decision date:** 2026-07-31. Brainstormed with Jesse (visual companion
mockups in `.superpowers/brainstorm/75295-1785534970/content/`; chosen:
icon-in-donut chips, always all four). Parent spec:
`docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md`
("SP-B — Per-face report cards: extend the on-demand CIDetector pass with
facing/light/prominence, per-face chips + traffic-light roll-ups in the
faces panel, roll-up dots on burst-rail thumbs").

## Problem

The close-ups rail shows per-face crops with eye/smile symbol marks, but
"which frame has no ruined face" is not scannable: sharpness only
attributes when a frame has exactly one face, facing/light/prominence
don't exist, and the burst rail carries no face information at all.

## Decisions (Jesse, 2026-07-31)

1. **Prominence-weighted roll-up.** Only a face above the prominence floor
   can grade a frame red; background faces cap at yellow. The rail dot
   answers "is anyone I care about ruined", not "is any face imperfect".
2. **Tile = crop + corner traffic dot + one always-on row of four
   icon-in-donut chips** (eyes, sharpness, facing, light): 17pt ring whose
   sweep is the score, stylized monochrome icon inside naming the signal.
   Chosen over warn-only chips and over symbol marks.
3. **Smile moves to hover/AX** (a non-smiling face is not a defect; the
   chip row is quality signals only).
4. **Approach A** — one Core analyzer + a central in-app report store both
   surfaces read. No worker involvement, no schema change, nothing
   persisted (per parent spec's explicit out-of-scope).

## Design

### FaceReportAnalyzer (TeststripCore)

New Core type. Entry point takes the preview `CGImage` and the CIDetector
detections the close-ups pass already produces
(`CoreImageFaceExpressionAnalyzer.detectFaces`,
FaceExpressionEvaluationProvider.swift), and returns one `FaceReport` per
face:

- Existing fields carried through: normalized bounds, eyes open/closed,
  smile. (Eye centers stay on `DetectedFaceExpression` for zoom-to-face,
  which is unchanged.)
- **facing** (0…1): one `VNDetectFaceRectanglesRequest` on the same image;
  Vision observations matched to CIDetector faces by bounding-box overlap
  (greatest-IoU wins, unmatched → facing unscored). Score decays from 1
  (full frontal) with |yaw| and |pitch| magnitude; constants documented in
  code with rationale.
- **light** (0…1): the existing `balancedExposure` formula
  (LocalImageMetricsEvaluationProvider) computed over the face crop's
  luminance (PreviewPixelMetrics.luminance).
- **sharpness** (0…1): the existing neighbor-delta metric
  (PreviewPixelMetrics) over the crop region — per-face, which retires the
  single-face-only `sharpnessTone` attribution limit in
  `CloseUpFacesPresentation`.
- **prominence** (0…1): face area / frame area (normalized bounds), used
  for grading and sort order; not a chip.
- **grade**: `.green / .yellow / .red` from documented threshold constants.
  Rule: red requires BOTH a red-grade signal AND prominence ≥ the
  prominence floor; a below-floor face grades at worst yellow. Constants
  live in one place with a WHY comment (same discipline as
  `tooCloseToCallMargin`).

Pure with respect to app state: image + detections in, reports out.
Failure honesty: a failed Vision request leaves `facing == nil` (chip
renders an empty ring, hover "no read"); never a fake score, never a fake
green.

### FaceReportStore (app layer)

`@MainActor` observable cache: `[AssetID: FrameFaceReport]`, where
`FrameFaceReport` holds the per-face reports, the frame's rolled-up worst
prominent grade, and the `previewCacheGeneration` it was computed from.
Stale generation → recompute on next read/sweep (the same invalidation
signal views already key on).

- **Sweep:** landing on a stack starts one background task — current frame
  first, then remaining frames in rail order — each frame analyzed off the
  main actor from its best cached preview (`loupePreviewURL` ladder; SP-C
  keeps these warm). Frames with no cached preview are skipped and picked
  up when their preview generation bumps. Per-frame results publish as
  they complete (dots appear progressively).
- **Cancellation:** stack change cancels and restarts the sweep. No queue,
  no worker items — plain structured concurrency in-app.
- **Single computation source:** `refreshCloseUps` keeps owning crop
  images; it feeds its detections through the analyzer and into the store,
  so the selected frame's chips, its panel dot, and its rail dot come from
  one computation.

### Surfaces

- **Face tile** (`closeUpCropCell`, LibraryGridView): corner traffic dot on
  the crop (bottom-trailing, 9pt, grade color); symbol-marks row replaced
  by four chips in fixed order — eyes, sharpness, facing, light — rendered
  by a new small `FaceSignalChipView` (17pt donut ring, sweep = score,
  monochrome SF Symbol inside). Always all four. Hover/AX per chip:
  `"<Signal> <NN>%"`; tile AX value carries eyes state and smile.
  `SignalGlyphView` (reads card) is untouched; the chip view is a sibling
  component.
- **Burst-rail thumb** (`cullStackRailCell`): one overlay dot,
  top-leading (clear of the ✦ top-trailing and the decision bar), colored
  by the frame's rolled-up grade from the store. No dot while uncomputed
  or when the frame has no faces — absence means "nothing known", never
  "known good".
- **Panel roll-up:** the close-ups header line adds the selected frame's
  dot + face count, so panel and rail always agree.

### Out of scope

- Persisting per-face signals, new `EvaluationKind`s, worker/protocol/
  schema changes (parent spec's explicit exclusions).
- `shutOK(context)` eye-state cases (no context provider exists — never
  fake it).
- Run-strip (per-stack) dots; the reads card; compare surfaces.
- Any change to the composite quality read or verdict math.

## Testing

**Unit (TDD):**

- Analyzer: facing score from known yaw/pitch fixtures; Vision↔CIDetector
  box matching (incl. unmatched → nil facing); light/sharpness over
  synthetic crops; prominence ratio; grade thresholds — including the
  negative: a face with a red-grade signal below the prominence floor
  grades yellow, and a frame whose only problems are background faces
  never rolls up red.
- Store: generation-bump invalidation; sweep order (current frame first,
  then rail order); cancellation on stack change; skipped no-preview frames
  picked up after generation bump.
- Presentation: chip entries (order, scores, nil-facing empty ring, AX
  strings); rail-dot roll-up worst-prominent-face selection; header
  roll-up equals rail dot for the same frame.

**End-to-end (scenario card, VM, faces variant):** new card using seeded
face fixtures (exercises the kata-18 model packaging live): rail dots
appear for stack frames without visiting them (store sweep proof, with a
no-faces frame asserting dot ABSENCE as the falsification leg); selected
frame's chips render with the four signals and AX values; panel header
dot matches that frame's rail dot.
