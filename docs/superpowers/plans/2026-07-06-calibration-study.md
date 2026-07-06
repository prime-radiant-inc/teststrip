# Teststrip Culling Threshold Calibration Study

**Date:** 2026-07-06
**Corpus:** `sample-data/photos/jesse-pictures` (gitignored real corpus, read-only) — 194 catalogable files: 79 JPG, 79 RAF, 36 DNG. The 79 JPG/RAF files are RAW+JPEG pairs of the same captures, so the corpus holds 115 unique frames.
**Method:** Throwaway in-process harness (not committed): seeded an isolated catalog under a `/tmp` scratchpad app-support directory using the same ingest path as `RealCorpusCatalogSeeder` (all 194 candidates instead of the 4-file representative selection), rendered `.grid` (512 px) cached previews with `PreviewRenderer`, ran all three evaluation providers (`local-image-metrics`, `apple-vision`, `core-image-faces`) directly over the cached previews, recorded signals through `CatalogRepository.recordEvaluationSignals`, and validated the `likelyPick`/`likelyIssue` SQL predicates against a Swift reimplementation (exact match at 0.65). 0 render failures, 0 provider failures. Verdicts came from the real `CullingAssistPresentation.presentation(for:)` / `CullingStackRecommendation.normalizedQualityRead` code, not a reimplementation. Source corpus verified unmodified (read-only ingest plan; same guarantees `real-corpus-smoke` asserts).

## Headline

**Every score-threshold in today's culling features is on the wrong scale for what the providers actually emit.** On this corpus: 100% of assets read **Toss**, 0% qualify as **Potential Picks** at any swept threshold, and 194/194 assets match `likelyIssue`. The root cause is not the thresholds per se — it is that `focus` (and therefore `motionBlur` and `eyeSharpness`, which derive from the same luminance-delta heuristic) live on a ~0.04–0.15 scale while every threshold assumes a 0–1 "percentage quality" scale.

## Signal distributions (per kind, over grid previews)

Histogram buckets are 0.0–0.1 through 0.9–1.0.

| kind | n | min | median | mean | max | histogram |
|---|---|---|---|---|---|---|
| aesthetics | 194 | 0.276 | 0.385 | 0.381 | 0.453 | [0, 0, 3, 128, 63, 0, 0, 0, 0, 0] |
| exposure | 194 | 0.260 | 0.435 | 0.436 | 0.801 | [0, 0, 10, 47, 98, 37, 0, 1, 1, 0] |
| eyeSharpness | 111 | 0.006 | 0.033 | 0.035 | 0.106 | [110, 1, 0, 0, 0, 0, 0, 0, 0, 0] |
| eyesOpen | 148 | 0.000 | 1.000 | 0.870 | 1.000 | [8, 0, 0, 3, 0, 10, 8, 6, 1, 112] |
| faceQuality | 149 | 0.061 | 0.270 | 0.311 | 0.703 | [6, 48, 26, 25, 17, 20, 6, 1, 0, 0] |
| focus | 194 | 0.044 | 0.095 | 0.096 | 0.148 | [113, 81, 0, 0, 0, 0, 0, 0, 0, 0] |
| framing | 194 | 0.533 | 0.613 | 0.619 | 0.759 | [0, 0, 0, 0, 0, 75, 107, 12, 0, 0] |
| motionBlur | 194 | 0.852 | 0.905 | 0.904 | 0.956 | [0, 0, 0, 0, 0, 0, 0, 0, 81, 113] |
| smile | 148 | 0.000 | 0.667 | 0.619 | 1.000 | [28, 0, 3, 10, 0, 30, 11, 2, 3, 61] |

Key percentiles: focus p5/p50/p95 = 0.066/0.095/0.128; aesthetics = 0.325/0.385/0.426; faceQuality = 0.102/0.270/0.597.

Observations:

- **focus never leaves the bottom two buckets.** It is the mean absolute neighbor-luminance delta over a 16×16 downsample; real photographs — sharp or soft — land in 0.04–0.15. Thresholds like "focus ≥ 0.65" (likelyPick strong read) and "focus ≤ 0.5" (defect) are unreachable and always-true respectively.
- **motionBlur is exactly `1 − focus`** (`LocalImageMetricsEvaluationProvider.motionBlurScore`). It carries zero independent information and, at the current scale, every asset trips the "motionBlur ≥ 0.5" defect.
- **aesthetics is structurally capped near ~0.55** because its 0.35-weighted focus term contributes at most ~0.05 at the real focus scale. Observed max: 0.453. "aesthetics ≥ 0.65" is unreachable.
- **eyeSharpness inherits the focus scale** (same heuristic on eye crops); max 0.106, so the verdict-strip phrase threshold "Eyes sharp ≥ 0.7" can never fire — every face photo says "Eyes soft".
- exposure and framing behave sanely; the exposure defect band (≤ 0.12 or ≥ 0.88) matched 0 assets, which is credible for a curated personal corpus.
- **faceQuality** (Vision `faceCaptureQuality`) spans 0.06–0.70 with median 0.27. Apple documents this metric as comparable within shots of the *same subject*, not as an absolute quality score — treating 0.65 as "strong" absolute quality selects almost nothing (2 of 149 face photos).

## Faces: eyesOpen / smile (CIDetector) vs Vision

- Vision found faces in 149/194 assets (faceCount distribution: 1×68, 2×38, 3×29, 4×8, 6×1, 8×5). CIDetector emitted eyesOpen/smile for 148/194; the two disagree on face presence for only 1 asset.
- eyesOpen values (per-photo fraction of faces with both eyes open): 1.0×112, 0.88×1, 0.75×6, 0.67×8, 0.5×10, 0.33×3, 0.0×8. So 24% of face photos have eyesOpen < 1.0 — and `likelyIssue`/`likelyPick` treat *any* value below 1.0 as a defect (36 assets, 18.6% of corpus).
- smile: 1.0×61, 0.0×28, rest spread across fractions — plausible shape for a family/travel corpus.
- RAW+JPEG pair stability: across 79 pairs of the identical frame, readScore median |diff| = 0.003 (max 0.117), but **4 of 56 pairs disagree on eyesOpen** — the expression detector flips on identical content rendered slightly differently. Any threshold that hard-fails on eyesOpen < 1.0 inherits this noise.

### Plausibility spot check (7 previews eyeballed against scores)

| photo | scores | eyeball verdict |
|---|---|---|
| DSCF9430 (couch portrait) | eyesOpen=1.0, smile=1.0 | **Hit** on eyes; smile plausible (small face, slight smile) |
| DSCF9609 (grandmother + toddler) | eyesOpen=1.0, smile=0.0, 1 face | Smile hit; **eyes unverifiable — subject wears sunglasses**, detector defaults to "open". Toddler in profile missed by both detectors |
| DSCF9602 (person behind glass door) | eyesOpen=0.0, smile=0.0 | **Unverifiable/likely miss** — tiny dark reflected face; "all eyes shut" is noise, though the photo genuinely is low quality |
| DSCF9436 (woman leaning over stroller) | eyesOpen=0.0, smile=1.0 | Mixed — downcast eyes plausibly read as closed; smile unverifiable at preview size |
| DSCF9800 (kids walking, 3 faces) | eyesOpen=0.33 | **Probable miss** — visible eyes look open; likely scored small background faces |
| DSCF9500 (two kids at tiger window) | eyesOpen=0.5, smile=0.5 | **Miss on eyes** (both look open); smile=0.5 plausible (toddler mouth open, boy neutral) |
| DSCF9719 (ride photo, waving woman) | eyesOpen=0.5, smile=1.0 | **Hit on smile** (clear smile); eyes partial — second face hard to judge |

**Verdict on CIDetector:** roughly a coin-flip-to-hit at the photo level. It is directionally right on clear frontal faces (eyesOpen=1.0 on 112 photos looks trustworthy as a *positive* signal), but fractional/zero values are frequently driven by tiny, occluded, downcast, or sunglassed faces, and it flips between renders of the same frame. It is usable as a *soft ranking bonus*; it is **not accurate enough to be a hard disqualifier**, which is exactly how `likelyPick`/`likelyIssue` use it today.

## Verdict simulation (current weights, real presentation code)

Current thresholds (Keep ≥ 0.7, Toss ≤ 0.45, ≥ 2 scored kinds):

| verdict | count | fraction |
|---|---|---|
| Keep | 0 | 0.0% |
| Toss | 194 | 100.0% |
| Mixed | 0 | 0.0% |
| no-read | 0 | 0.0% |

normalizedQualityRead distribution: min 0.136, median 0.342, mean 0.305, max 0.421; histogram [0, 34, 39, 112, 9, 0, 0, 0, 0, 0]. Every asset produced ≥ 4 scored kinds (kindCount 4×45, 5×1, 6×37, 7×111), so the ≥ 2-kind gate never bit.

The read is dragged into the 0.1–0.42 band by the three focus-scale components: focus (weight 100 × score ~0.1), motionBlur (weight 42, inverted score ~0.1), eyeSharpness (weight 42 × score ~0.03). The visible bimodality (0.1–0.3 vs 0.3–0.4) is mostly "has faces with open eyes" (eyesOpen weight 63 at value 1.0), not photo quality.

Threshold sweep on the current read:

| keep ≥ / toss ≤ | Keep | Toss | Mixed |
|---|---|---|---|
| 0.70 / 0.45 (today) | 0.0% | 100.0% | 0.0% |
| 0.40 / 0.30 | 4.6% | 37.6% | 57.7% |
| 0.38 / 0.25 | 17.5% | 30.9% | 51.5% |
| 0.36 / 0.28 | 32.5% | 34.5% | 33.0% |
| 0.35 / 0.25 | 40.2% | 30.9% | 28.9% |

## likelyPick simulation

SQL predicate at 0.65 (validated against `CatalogRepository`): **0 of 194** (Swift replication matches exactly). No corpus asset carries an XMP flag, so flag exclusion contributed nothing.

Strong-read sweep, with today's defect exclusion left as-is:

| threshold | strong read (focus/aesthetics/faceQuality) | after defect exclusion |
|---|---|---|
| 0.50 | 27 (13.9%) | 0 (0.0%) |
| 0.55 | 15 (7.7%) | 0 (0.0%) |
| 0.60 | 7 (3.6%) | 0 (0.0%) |
| 0.65 (today) | 2 (1.0%) | 0 (0.0%) |
| 0.70 | 1 (0.5%) | 0 (0.0%) |
| 0.75 | 0 (0.0%) | 0 (0.0%) |

Two compounding failures:

1. **Strong read barely fires** — at every swept threshold, only faceQuality ever crosses (at 0.50: focus 0, aesthetics 0, faceQuality 27). Moving the threshold alone cannot get near Narrative Select's ~50% review-volume cut; even th=0.50 yields 13.9%.
2. **Defect exclusion swallows everything**: focus ≤ 0.5 matches 100% of assets, motionBlur ≥ 0.5 matches 100%, eyesOpen < 1.0 matches 18.6%. Nothing can survive. The same terms make `likelyIssue` match 194/194, i.e., both queues are currently constant functions.

Recalibrated candidates (simulated on this corpus):

| rule set | qualifies |
|---|---|
| A: strong = focus ≥ 0.12 (p75) OR aesthetics ≥ 0.42 (p90) OR faceQuality ≥ 0.45 (p75); defects = focus ≤ 0.06 (p5), exposure band unchanged, eyesOpen < 1.0 | 51 (26.3%) |
| B: same strong; eyesOpen defect only when 0.0 (all eyes shut) | 61 (31.4%) |
| C: strong at medians (focus 0.095 / aesthetics 0.385 / faceQuality 0.27); eyesOpen defect at 0.0 | 146 (75.3%) |

Narrative Select comparison: their Potential Picks cut review volume by ~half. Rule B (31%) is the closest honest analogue this signal set supports — pushing to ~50% (rule C) requires median-split thresholds so loose they stop meaning "strong".

## Recommendations (evidence only — no code changed)

1. **Verdict strip Keep ≥ 0.7 → keep the threshold only if the focus-family components are rescaled first; otherwise it is dead code.** The right fix is root-cause: normalize `focus`/`motionBlur`/`eyeSharpness` to their empirical range (e.g., map 0.04–0.15 onto 0–1) inside the provider or `qualityComponent`, then re-measure before choosing thresholds. If thresholds must move without rescaling, 0.38/0.25 gives Keep 17.5% / Toss 30.9% on this corpus — but those magic numbers encode this heuristic's scale and will silently break the moment the focus metric changes.
2. **Toss ≤ 0.45 → too high either way** (today it captures 100%). Same rescale-first recommendation; 0.25 is the evidence-backed interim value.
3. **likelyPick strong read ≥ 0.65 → lower per-kind, not uniformly.** 0.65 selects 1% before exclusions. Percentile-anchored per-kind thresholds (focus 0.12 / aesthetics 0.42 / faceQuality 0.45 ≈ each kind's top quartile-to-decile) yield a 26–31% queue — the closest this signal set gets to Narrative's ~50% while still meaning "strong". A single shared threshold cannot work: the three kinds live on incompatible scales (max focus 0.148 vs max faceQuality 0.703).
4. **likelyPick/likelyIssue defect terms — fix before any threshold tuning:** `focus ≤ 0.5` → ≈ 0.06 (p5); `motionBlur ≥ 0.5` → drop entirely (it is 1 − focus, pure redundancy); `exposure` band is fine as-is (0 hits, plausible); `eyesOpen < 1.0` → relax to `= 0.0` or demote from hard defect to ranking penalty — the spot check shows fractional values are unreliable and unstable across renders of the same frame (4/56 RAW+JPEG pairs disagree).
5. **"Eyes sharp ≥ 0.7" phrase (eyeSharpness)** — unreachable (max 0.106); rescale with the focus family or use ≈ 0.05 (p75) in the interim.
6. **CIDetector smile/blink: keep as soft signal only.** eyesOpen = 1.0 is a usable positive; anything below 1.0 must not hard-disqualify a photo.

## Limitations

- **One photographer, one corpus, 115 unique frames** (194 files; 79 are RAW+JPEG duplicates that double-count the same content). Family/travel-heavy; no sports, low-light events, or studio work. Percentile-anchored suggestions are fitted to this corpus and need re-checking on a second corpus before hardening.
- **Preview-level analysis only** (512 px grid previews, matching the dogfood seed path). The app prefers `.large`/`.medium` previews when present; the focus heuristic's absolute values shift with preview size, though its ~0–0.15 scale ceiling is structural.
- **No ground-truth labels.** "Keep-worthiness" wasn't human-rated; the study calibrates signal scales and queue sizes, not precision/recall of the verdicts themselves. The XMP sidecars in the corpus carried no pick flags, so the flag-exclusion path in `likelyPick` went unexercised.
- Spot check was 7 photos eyeballed by one reviewer at preview resolution; the CIDetector accuracy read is an impression, not a measured error rate.
