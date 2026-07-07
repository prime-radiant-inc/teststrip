# On-Device Face-Identity Recognition — Design

**Date:** 2026-07-07
**Status:** Approved for planning

## Goal

Replace the whole-image feature-print embedding that Teststrip currently uses
for face grouping with a real on-device face-recognition model, so that
automatic grouping clusters the same person's faces together and keeps
different people apart on a real photo library.

## Why

The current pipeline computes `VNGenerateImageFeaturePrint` on a padded face
crop. That is a general image descriptor, not a face-identity model. Measured
on the 11-photo public-domain astronaut corpus, the closest pair of faces in
the whole set is **Aldrin↔Glenn (Euclidean 0.66) — two different people** —
nearer than any true same-person pair (~0.71–0.90). No distance threshold can
separate identities from this embedding: the recalibration in
`c2b2eae` unblocks the *flow* (suggestions appear) but the groups are wrong
(Glenn's cluster absorbs Aldrin). Good grouping requires an identity embedding,
and Apple's Vision exposes no face-identity API — hence a bundled model.

## Scope

In scope: the embedding source (a new face-recognition embedder), face
alignment, model delivery, retuned clustering thresholds, and recomputation of
existing embeddings under a new provenance.

Out of scope (unchanged): the `face_observations`/`people`/`person_faces`
catalog schema, the `FaceSuggestionBuilder` clustering *algorithm*, the People
view and its confirm/dismiss/name flow, and the confirm-before-write invariant.

## Decisions (settled during brainstorming)

- **Model:** InsightFace `w600k_r50` ArcFace (ResNet50, 512-d, L2-normalized) —
  the "best model" option. Converted to Core ML.
- **Delivery:** the `.mlpackage` is fetched by a checksum-verified download
  manifest + script into the app bundle at build time (mirrors the
  `sample-data` photo-manifest pattern). NOT committed to git.
- **Swappability:** the embedder sits behind a `FaceEmbeddingModel` protocol so
  a smaller/permissive model (e.g. MobileFaceNet) can drop in later without
  downstream rework.
- **License:** the InsightFace weights are research/non-commercial. Acceptable
  for the current personal alpha (not distributed). This is a **pre-release
  blocker** to resolve before any public distribution — recorded, not solved
  here.

## Architecture

Swap the embedding source; keep everything downstream. The unit boundaries:

### 1. `FaceEmbeddingModel` (protocol) + `ArcFaceCoreMLModel` (implementation)
- **Does:** takes an aligned 112×112 face image, returns a 512-d L2-normalized
  identity embedding.
- **Interface:** `func embedding(for alignedFace: CGImage) throws -> [Float]`
  plus a `provenance: ProviderProvenance` describing the model
  (`provider: "face-recognition", model: "arcface-w600k-r50", version: "1"`).
- **Depends on:** Core ML (`MLModel`), the bundled `.mlpackage`. First use in
  the codebase — no existing Core ML usage to follow.
- **Failure:** model-load failure and inference failure are typed errors; a
  face that cannot be embedded is skipped (no observation written) and logged,
  never crashes evaluation.

### 2. `FaceAligner`
- **Does:** given the source image + Vision face landmarks, produces the
  canonical 112×112 aligned crop ArcFace expects (5-point similarity transform
  to the standard ArcFace reference landmark positions).
- **Interface:** `func alignedFace(from image: CGImage, landmarks:
  VNFaceLandmarks2D, faceBox: CGRect) -> CGImage?` — nil when required
  landmarks are missing.
- **Depends on:** Core Graphics/Image only. Pure and unit-testable given
  synthetic landmark inputs (assert the transform maps input landmark points to
  the canonical positions within tolerance).

### 3. `FaceRecognitionEmbedder`
- **Does:** orchestrates detect → landmarks → align → embed for one image,
  emitting `AppleVisionFaceObservation`-shaped results carrying the new
  embedding. Replaces the `VNGenerateImageFeaturePrint`-on-face-box block in
  `AppleVisionAnalyzer.analyze`.
- **Interface:** consumed by the existing evaluation entry point that today
  produces face embeddings; output flows unchanged into
  `CatalogRepository` face-observation persistence.
- **Depends on:** `FaceAligner`, `FaceEmbeddingModel`, `VNDetectFaceLandmarks`.

### 4. `FaceSuggestionBuilder` (existing — retune only)
- **Does:** unchanged clustering; only the distance thresholds change to the
  ArcFace scale. Because ArcFace embeddings are L2-normalized, the existing
  Euclidean-on-normalized-vectors distance is monotonic with cosine distance;
  thresholds are re-derived from measured same/different-person distances on
  the astronaut corpus.

### Model delivery unit
- `sample-data/face-recognition-model.tsv` (or equivalent manifest): filename,
  URL, md5, size. `script/download_sample_photos.sh`-style fetch (reuse or
  parameterize the existing downloader) places the `.mlpackage` where
  `build_and_run.sh` copies it into `dist/Teststrip.app/Contents/Resources`.
  Not committed; gitignored like the sample photos.

## Data flow

```
image → VNDetectFaceRectangles (have) → per face:
  VNDetectFaceLandmarks → FaceAligner (112×112) →
  ArcFaceCoreMLModel → 512-d L2-normalized embedding →
  face_observations row (new provenance) →
  FaceSuggestionBuilder (retuned) → PeopleFaceSuggestion → People UI (confirm)
```

Reads filter to the new provenance, so old feature-print observations are inert
and ignored; no schema migration. Populating identity embeddings requires a
re-evaluation pass over existing assets (the standard Evaluate path, now
calling the new embedder).

## Error handling

- **Model missing/unloadable** (e.g. the download didn't run): face embedding
  is disabled with a single clear status/log line; detection, quality, and all
  other evaluation continue. The app never hard-fails because the face model is
  absent.
- **No/insufficient landmarks** for a detected face: skip that face's embedding
  (still record detection if that is today's behavior), log, continue.
- **Inference error** on one face: skip that face, continue the batch.

## Testing

- **Unit — `FaceAligner`:** given synthetic landmark points, the transform maps
  them onto the canonical ArcFace positions within tolerance; missing landmarks
  → nil.
- **Unit — embedding:** the model output is 512-d and L2-normalized (‖v‖ ≈ 1).
- **Unit — clustering:** deterministic same/different-person unit vectors at the
  new ArcFace scale cluster correctly at the retuned thresholds (locks the
  calibration; fails at the old thresholds).
- **Model-conversion verification:** the converted Core ML model reproduces
  reference ArcFace embeddings for known inputs within tolerance (guards a
  broken/mismatched conversion). Corpus/asset-gated; skips when the model isn't
  downloaded.
- **Acceptance (integration):** real Apple Vision detection + the new embedder
  over the downloaded astronaut corpus clusters Glenn×4, Ride×4, Armstrong×2
  each into one group and keeps Aldrin separate, with no two different people in
  one group — the exact failure that exists today. Gated with `XCTSkip` when
  the corpus/model isn't present.

## E2E scenario cards

| Card | Covers | Falsification |
| --- | --- | --- |
| people-cluster-by-identity | Automatic face grouping on a real multi-person corpus clusters same-person faces together and separates different people, using the new identity embedding | Two confirmed-different people appear in one suggested group, OR one person's faces split across multiple un-mergeable groups, OR the astronaut corpus still merges Aldrin into a Glenn group |
| people-confirm-name-persists | Confirming/naming a suggested identity group writes a `people` row + `person_assets` links, and nothing is written before the confirm | A `people` row exists before any confirm gesture (confirm-before-write violation), OR after confirming, `people`/`person_assets` counts are unchanged |

## Open implementation questions (for the plan, not blockers)

- Exact source of a `w600k_r50` ONNX/PyTorch export and the `coremltools`
  conversion recipe (input size, normalization, output layer) — resolved during
  implementation with the conversion-verification test as the gate.
- Whether to prune stale feature-print face observations or leave them inert
  (leaning: leave inert; they cost nothing and reads already filter by
  provenance).
