# Reads card glyph line (kata #7) — design

**Decision date:** 2026-07-29. Brainstormed with Jesse; mockups in
`.superpowers/brainstorm/32761-1785347588/content/` (chosen: micro donuts,
word beside each, one line).

## Problem

The reads card showed four per-kind percentage rows plus a Keep/Toss verdict,
while the composite behind the verdict (confidence-weighted mean over up to
seven kinds, kindCount gate, calibrated thresholds) stayed invisible — and
three of the verdict's inputs (face kinds) rendered on a different panel
entirely. Jesse's ruling on the card's job: **fast triage cue** — the fix is
less machinery on screen, with every verdict input visible in one place.

## Decisions (Jesse, 2026-07-29)

1. The card's job is a fast triage cue, not a justification panel.
2. Per-signal detail compresses to **one line of micro donut rings, each with
   its measure's word beside it** (9pt secondary gray; "Looks" stands in for
   aesthetics to keep one line viable).
3. **Face signals join the line** when scored — every verdict input visible on
   the card; the close-ups rail keeps per-face detail.
4. **No-call stays pure silence** — a full read between the thresholds renders
   donuts with no verdict word and no placeholder mark (consistent with the
   kata #14 wontfix).

## Design

### Card anatomy

Two elements, nothing else:

- **Verdict slot** — "Keep" (positive tone) / "Toss" (caution tone), gate
  unchanged: `CullingAssistPresentation.verdict` (composed read ≥ 0.7 /
  ≤ 0.5, kindCount ≥ 2). Between thresholds: slot renders nothing.
- **Glyph line** — one donut+word pair per *scored rankable* kind, canonical
  order: Focus · Motion · Framing · Looks · Eyes · Face · Eye sharp. Donut
  11pt (gray track, quiet teal fill, arc sweep = display score), word 9pt
  secondary. The line wraps to a second row when face kinds push past the
  panel width. Absent kinds render nothing — no gaps, no fake zeros.

### States

| Signals scored | Render |
| --- | --- |
| none | `emptyState: "No read yet"` (unchanged copy) |
| exactly 1 kind (any kind, face included) | that one pair + caveat `early read — 1 signal`, no verdict |
| ≥ 2 kinds | full glyph line + verdict word, or silence between thresholds |

The 2026-07-28 face-specific fallback (single face-only kind → "No read yet")
is **retired**: face kinds are first-class in the line, so a face-only single
signal is an ordinary partial read. Its test is replaced (not deleted) by the
new contract test.

### Kind → word table (presentation layer)

| kind | word |
| --- | --- |
| focus | Focus |
| motionBlur | Motion |
| framing | Framing |
| aesthetics | Looks |
| eyesOpen | Eyes |
| faceQuality | Face |
| eyeSharpness | Eye sharp |

Display score = the `bestComponentByKind` component score **as-is**. Components
are already defect-inverted at the core layer (`CullingQualityScore.
qualityComponent` returns `1 − score` for motionBlur) — the presentation must
NOT invert again.

Face entries are the photo-level read: best component per kind across faces —
exactly what the composite consumes (`bestComponentByKind`), so the line and
the verdict can never disagree.

### Component

One small reusable view: donut ring + word ("signal glyph"). SP-B's per-face
report cards reuse it for their chips. The close-ups rail is untouched by this
project.

### Presentation layer / data flow

- `CullReadsCardPresentation` (pure) consumes the same `[EvaluationSignal]`,
  reuses `CullingStackRecommendation.bestComponentByKind`, and emits an
  ordered `[(kind, word, score)]` glyph-entry list plus the existing
  `verdictText` / `earlyReadCaveat` / `emptyState`.
- `canonicalSignalOrder` grows 4 → 7 (whole-photo four, then eyesOpen,
  faceQuality, eyeSharpness).
- The per-kind percentage `SignalRow`s are deleted.
- `CullingAssistPresentation.verdict`, `normalizedQualityRead`, weights,
  thresholds, and the 0.03 tie margin are all **untouched** — presentation
  only, by construction. No catalog/worker/scorer changes.

### Hover and accessibility

- Each pair: help + AX label `"<Word> <NN>%"` (e.g. "Focus 82%").
- Verdict word: help/AX value `"Composed read <0.NN> from <N> signals"` — the
  one place the composition is stated, off-screen.
- Card AX container value chain stays `emptyState ?? verdictText ??
  earlyReadCaveat` (silence for no-call, per kata #14).

## Out of scope

- Any change to the composite math, thresholds, weights, or tie margin.
- The close-ups rail and SP-B's per-face report cards (SP-B consumes the glyph
  component; it is specced separately).
- HUD and compare-survey surfaces.

## Testing

- **Unit (rewrite `CullReadsCardPresentationTests`):** glyph ordering; absent
  kinds omitted; motion inversion; word table; the three states; face-only
  single signal is a partial read (replaces the 2026-07-28 fallback test);
  verdict silence between thresholds; caveat only at kindCount == 1.
- **Scenario cards:** cull-024 reconciled to the new renderings (third
  reconciliation); cull-012's reads-panel probes updated for the new AX
  labels. Both re-run live in the Tart VM after implementation.
