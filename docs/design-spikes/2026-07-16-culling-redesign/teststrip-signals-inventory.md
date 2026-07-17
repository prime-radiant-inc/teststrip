# Teststrip Culling Signals & Machinery Inventory (2026-07-16)

Prepared as raw material for a culling-mode redesign. Read-only investigation — no
source was changed. Every claim below cites a file path (and line numbers as of
this HEAD; re-locate by symbol name if they drift).

**Headline finding for the designer:** `docs/product/narrative-select-reference.md`
(dated 2026-07-06) and `docs/superpowers/plans/2026-07-06-teststrip-culling-workflow-audit.md`
are both **stale**. A large amount of work has landed since (RAW+JPEG bonding,
cull-stack-rail, machine-label-provenance, people-surfacing, the culling-signals
and culling-arc plans) and most of what those docs call "Planned"/"Missing" is now
built: per-frame Keep/Toss verdict pill, recommended-frame badge rendered on
frames, People Filter, Potential Picks filter, a Close-Ups face panel, a stack
sidebar, contenders-only compare with rank badges and comparative rationale, and
an A/B compare mode that didn't exist at all in the audit. Section 5's gap table
below reflects current code, not those docs.

---

## 1. Machine signals available today

### 1.1 Signal kinds, providers, and scale

`EvaluationKind` (`Sources/TeststripCore/Evaluation/EvaluationSignal.swift:3-18`) has 15 cases from three providers:

| Kind | Provider | Value type & range | Confidence | Computed by |
|---|---|---|---|---|
| `focus` | `local-image-metrics` | `.score` 0–1, edge-detail/luminance-delta heuristic on a 16×16 preview sample | 1.0 | `PreviewPixelMetrics.focusScore` via `LocalImageMetricsEvaluationProvider.swift:37-43` |
| `motionBlur` | `local-image-metrics` | `.score` 0–1, `1 − focusScore` | 0.7 | `LocalImageMetricsEvaluationProvider.swift:44-50,103-105` |
| `exposure` | `local-image-metrics` | `.score` 0–1, average luminance (0=black,1=white) | 1.0 | `LocalImageMetricsEvaluationProvider.swift:20-29` |
| `framing` | `local-image-metrics` | `.score` 0–1, rule-of-thirds distance of the luminance-weighted centroid | 0.6 | `LocalImageMetricsEvaluationProvider.swift:122-150` |
| `aesthetics` | `local-image-metrics` | `.score` 0–1, weighted composite: focus 35% + balanced-exposure 25% + color-contrast 20% + framing 20% | 0.55 | `LocalImageMetricsEvaluationProvider.swift:58-69,107-120` |
| `colorPalette` | `local-image-metrics` | `.vector([r,g,b])` average color | 1.0 | `LocalImageMetricsEvaluationProvider.swift:30-36` |
| `faceCount` | `apple-vision` | `.count(Int)` | max per-face capture-quality score | `AppleVisionEvaluationProvider.swift:102-117` (Vision `VNDetectFaceCaptureQualityRequest`) |
| `faceQuality` | `apple-vision` | `.score` 0–1, average face capture quality | max score | `AppleVisionEvaluationProvider.swift:119-134` |
| `ocrText` | `apple-vision` | `.text(String)` (joined lines) | 1.0 | `VNRecognizeTextRequest` (`.fast`, no language correction), `AppleVisionEvaluationProvider.swift:270-273,302-304` |
| `object` | `apple-vision` | `.label`/`.labels([String])`, Apple's ~1,300-label taxonomy filtered to precision 0.9/recall 0.01 | top label confidence | `VNClassifyImageRequest`, `AppleVisionEvaluationProvider.swift:154-174,305-311` |
| `visualSimilarity` | `apple-vision` | `.vector([Double])`, `VNGenerateImageFeaturePrintRequest` revision2 (pinned so vector length/dimension never silently changes with an SDK update) | 1.0 | `AppleVisionEvaluationProvider.swift:176-189,240-253,317-325` |
| `smile` | `core-image-faces` | `.score` 0–1, fraction of detected faces with `CIDetectorSmile` true | 0.7 | `FaceExpressionEvaluationProvider.swift` (CIDetector) |
| `eyesOpen` | `core-image-faces` | `.score` 0–1, fraction of faces with both eyes open (`CIDetectorEyeBlink`) | 0.7 | ditto |
| `eyeSharpness` | `core-image-faces` | `.score` 0–1, **minimum** across faces of the sharpest eye-crop focus score (crop = 0.25× face width, ≥8px, same luminance-delta heuristic as `focus`) | 0.6 | ditto |

`smile`/`eyesOpen`/`eyeSharpness` were the deliverable of
`docs/superpowers/plans/2026-07-06-teststrip-culling-signals.md` and are fully
implemented — confirmed present in the current enum, in
`CatalogRepository`'s calibrated-scale gating, and in the ranking/verdict
scorer below. No eye-region-specific *focus* signal beyond `eyeSharpness`
exists (no separate "in/out of focus" per subject beyond whole-image `focus`).

All providers run over **cached previews only** (never source originals on
hot paths) via `TeststripWorker`'s `runEvaluation` command
(`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`); nothing
auto-writes catalog metadata from a signal — see provenance below.

**A version/scale-migration nuance the redesign should know about:** focus,
motionBlur, and eyeSharpness carry a provenance `version` because their scale
was recalibrated 2026-07-06 (raw ~0.04–0.15 → calibrated 0–1); every read
that depends on absolute thresholds (likely-issue/likely-pick queues, the
verdict pill, stack ranking) filters out stale-version rows via
`CatalogRepository.currentScaleSignalSQL`
(`Sources/TeststripCore/Catalog/CatalogRepository.swift:2904-2919`). A
redesign that adds new threshold-based UI should reuse this gate rather than
reading raw scores.

### 1.2 Storage

Table `evaluation_signals` (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:64-80`):
`asset_id, kind, value_json, confidence, provenance_json, provider, model,
version, settings_hash, created_at, updated_at`, primary-keyed on
`(asset_id, kind, provider, model, version, settings_hash)` — multiple
providers/versions can coexist per asset/kind; indexed by `asset_id` and by
`(kind, asset_id)`.

Two SQL-derived queues read straight off this table:
- `likelyIssue` (`CatalogRepository.swift:3181-3230`) — focus ≤0.4, exposure
  ≤0.12 or ≥0.88, `eyesOpen` = 0.0, or `faceQuality` ≤0.1 (each threshold from
  the 2026-07-06 calibration study; comments in-file document the corpus
  percentile each anchors to).
- `likelyPick` (`CatalogRepository.swift:3231-3260+`) — focus ≥0.8,
  aesthetics ≥0.65, or faceQuality ≥0.45, AND not already flagged, AND not
  also hitting a `likelyIssue` clause. This backs the "Potential Picks"
  review queue (`ReviewQueue.potentialPicks`, `AppModel.swift:596`) — see §5,
  this is a **built** capability, not "Missing" as the July 6 doc claims.

### 1.3 Reach to the UI

- `AppModel.evaluationSignals(for:)` / `selectedEvaluationSignals` surface
  signals to every presentation type.
- Verdict pill: `CullingAssistPresentation` (`Sources/TeststripApp/LibraryGridView.swift:8363-8608`)
  — synthesizes a **"Keep read NN%" / "Toss read NN%" / "Mixed read NN%"**
  verdict from the same weighted scorer as stack ranking (needs ≥2 scored
  kinds; thresholds 0.7/0.5, `LibraryGridView.swift:8377-8434`), plus a
  primary-signal title/detail line and up to 3 rationale phrases
  (`rationaleText`/`expressionPhrase`, `LibraryGridView.swift:8456-8510`) that
  render "Eyes open"/"Eyes shut"/"Some eyes shut", "Eyes sharp"/"Eyes soft",
  "Smiling"/"Some smiling" for the expression kinds.
- Focus-metric lanes per tile in Compare: `CompareFocusMetricPresentation`
  (`LibraryGridView.swift:5663-5784`).
- Inspector "Teststrip Reads" grouped rows: `InspectorView.swift` (grouped by
  kind, e.g. all face-related kinds including `smile`/`eyesOpen`/`eyeSharpness`
  under "Faces").
- Search/filter: `signal:`/`evaluation:`/`kind:` token
  (`Sources/TeststripApp/LibrarySearchIntent.swift:159-161`) and
  `SetQuery.Predicate.evaluationKind` (`Sources/TeststripCore/Search/SetQuery.swift:33`).
- Ranking: `CullingQualityScore` (below, §3) and the autopilot planner (§1.4)
  both consume raw signals directly, not the presentation layer.

### 1.4 Autopilot pick/reject and the provenance model

`AutopilotProposalPlanner` (`Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift`)
is a pure function: for every detected multi-frame stack (`AssetStackBuilder`,
§3) whose members carry ≥1 rankable signal, it proposes `.pick` for the
highest-`CullingQualityScore` frame and `.reject` for the rest, with
`confidence` = the winning margin `(winner − runnerUp)/winner` (0–1) and a
plain-language `rationale` string ("Sharpest frame in its burst of N" /
"Weaker frame in a burst of N"). RAW+JPEG ties break toward keeping the RAW
(`AutopilotProposalPlanner.swift:76-84`). It also proposes `.keyword`
suggestions from caller-supplied candidates (fixed confidence 0.6). It
**never writes metadata** — it returns `AutopilotProposal` values with
`status: .pending` (`Sources/TeststripCore/Autopilot/AutopilotProposal.swift`).

Provenance/lifecycle, all in `Sources/TeststripApp/AppModel.swift`:
- `applyTentativeAutopilotProposals` (`:9141`) writes the proposed
  flag/keyword to the catalog immediately but marks it in
  `AssetMetadata.aiUnconfirmedFields`/`aiUnconfirmedKeywords` — visible,
  reversible, catalog-only; **no sidecar write** at this point.
- `commitAutopilotProposals`/`commitAllAutopilotProposals` (`:9299-9369`)
  is the explicit user gesture: clears the unconfirmed marker (origin →
  user) and, for sidecar-eligible fields, writes the XMP sidecar through the
  existing metadata-sync path; proposals whose asset's metadata has since
  changed are marked `.dismissed` rather than force-applied (`:9310-9357`).
- `dismissAutopilotProposals` (`:9380`) marks `.dismissed` without writing.

The general origin mechanism this rides on:
`AssetMetadata.aiUnconfirmedFields: Set<MetadataField>` (`.flag`, `.caption`,
`.rating`, `.keyword`) and `aiUnconfirmedKeywords: Set<String>`
(`Sources/TeststripCore/Domain/Metadata.swift:35-36`).
`confirmedProjection` (`Metadata.swift:55-65`) strips every unconfirmed label —
this is exactly what's exported to XMP and what
`hasWrittenPortableMetadata` (`Metadata.swift:125-134`) is judged against, so
"never write unconfirmed AI labels to sidecars" is enforced structurally, not
by convention. Removing an AI label (rather than confirming it) records a
`removed_ai_labels` row (`asset_id, field, value`,
`CatalogMigrations.swift:247-255`; written via
`CatalogRepository.recordRemovedAILabel`, called from `AppModel.swift:7023,
7863, 7912`) so a later re-evaluation can't resurrect it. Face-identity
negatives use a parallel table, `rejected_face_people` — see §2.

---

## 2. Face pipeline

Two independent face-detection code paths exist, feeding different features —
worth flagging to the designer since their bounding boxes are not guaranteed
to agree frame-to-frame:

**(a) Vision-based, persisted, identity-capable** — `AppleVisionAnalyzer`
(`Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift:240-315`)
runs `VNDetectFaceCaptureQualityRequest` for detection + per-face quality,
then (when the identity model is present) `FaceRecognitionEmbedder`
(`Sources/TeststripCore/People/FaceRecognitionEmbedder.swift`) produces a
128-d-ish embedding per face via `CoreMLFaceEmbeddingModel.auraFace()`
(**AuraFace-v1**, an ArcFace/glint-r100-architecture model, Apache-2.0
licensed) after alignment (`FaceAligner.swift`). Results persist as
`CatalogFaceObservation` (`assetID, faceIndex, boundingBox: FaceBoundingBox{x,y,width,height}
(normalized 0–1), captureQuality, embedding: [Double], provenance`) —
`Sources/TeststripCore/Catalog/CatalogFaceObservation.swift`. Table
`face_observations` (`CatalogMigrations.swift:149-163`), keyed
`(asset_id, face_index, provider, model, version, settings_hash)`. **The
identity embedder is optional** — `sharedFaceEmbedder` is `nil` if the model
hasn't been downloaded (`AppleVisionEvaluationProvider.swift:64-65,214-219`),
in which case detection/quality signals still land but no identity vector
does.

**(b) CoreImage-based, on-demand, display-only** —
`CoreImageFaceExpressionAnalyzer` (`FaceExpressionEvaluationProvider.swift`,
CIDetector with `CIDetectorSmile`/`CIDetectorEyeBlink`) backs the `smile`/
`eyesOpen`/`eyeSharpness` signals (§1) AND, re-run live over the cached
preview per selection, backs both the **Close-Ups panel** and the
**Z/Shift-Z zoom-to-face** targeting in the loupe — nothing from this pass
persists beyond the evaluation-signal rows.

### 2.1 Naming / identity / clustering

- Clustering & person-matching: `FaceSuggestionBuilder`
  (`Sources/TeststripCore/People/FaceSuggestionBuilder.swift`) — L2-normalizes
  embeddings, computes Euclidean distance to each named person's centroid of
  confirmed faces; a face matches an existing person at distance ≤1.23
  (`defaultMaximumMatchDistance`), else single-link-clusters unmatched faces
  into new-person suggestion groups at the same 1.23 threshold, min 2 faces
  per cluster (`FaceSuggestionBuilder.swift:41-65`). The 1.23 constant is
  calibrated against measured same-/different-person distance gaps on a test
  corpus (comment at `FaceSuggestionBuilder.swift:42-49`).
- Catalog: `people` (id, name), `person_assets`, `person_faces`
  (`asset_id, face_index → person_id`), `dismissed_face_assets`,
  `dismissed_faces` (not-a-face / skip), `rejected_face_people` (negative:
  "confirmed NOT this person" — `Sources/TeststripCore/Catalog/RejectedFacePerson.swift`,
  table at `CatalogMigrations.swift:175-183`). `AppModel.rejectFaceSuggestion`
  (`AppModel.swift:4024`) records the negative so recognition stops
  re-proposing that person for that face.
- Naming UI: `PeopleView.swift` (905 lines) — face-suggestion cards,
  name-suggestion sheet, per-face naming on a face-group review card
  (`FaceGroupReviewView.swift`), named-person cards with photo counts
  (`photoCountDescription`, `PeopleView.swift:839`) that filter the library
  on tap (`showPersonPhotos` → `AppModel.showPersonPhotos(named:)` →
  `SetQuery.Predicate.person(name)`), and a merge-person action. A single
  `PersonAutocompleteField`/`PersonCandidateRanker` (similarity + recency
  ranked) unifies naming across all four entry points (face-box pill, review
  card, group review, autocomplete field) — `Sources/TeststripApp/PersonAutocompleteField.swift`,
  `PersonAutocompletePresentation.swift`, `Sources/TeststripCore/People/PersonCandidateRanker.swift`.
- Contacts seeding: `ContactFaceSeeder.swift`/`ContactFaceEmbedder.swift` seed
  reference embeddings from macOS Contacts photos (`contact_reference_faces`
  table, `CatalogMigrations.swift:257-267`) so a person can be named/matched
  from the address book without manual tagging first.
- **People Filter already exists as a first-class capability**:
  `SetQuery.Predicate.person(String)` (`Sources/TeststripCore/Search/SetQuery.swift:24`),
  wired through `LibrarySearchIntent` (`person:` search token,
  `LibrarySearchIntent.swift:124-125`), `PersonAutocompleteField`, and
  `PeopleView`'s tap-to-filter. This contradicts the July 6 reference doc's
  "Planned" status — it is built.

### 2.2 Face rectangles/crops for a "Close-Ups" panel

**Already built.** `CloseUpFacesPresentation`
(`Sources/TeststripApp/CloseUpFacesPresentation.swift`) computes up to 4
padded square crops (1.6× the larger face-bbox dimension, ≥24px side,
largest-face-first) from the on-demand CIDetector pass described above (not
from the persisted `face_observations`). Wired into the loupe's
`closeUpsPanel` (`LibraryGridView.swift:3982-4008`, populated by
`refreshCloseUps(for:)` at `:4018-4043`, which runs off the main actor and
touches nothing persisted). This is exactly the raw material a "Close-Ups
Panel" redesign would use; today it's a fixed 136pt-wide scrolling rail
beside the loupe stage, not spacebar-triggered (Narrative Select's spacebar
zooms to the most important face; Teststrip's equivalent is `Shift+Z`
zoom-to-nearest-face, a different binding — see §4).

---

## 3. Burst/stack/grouping machinery + RAW+JPEG bonding

### 3.1 Stacks

`AssetStackBuilder` (`Sources/TeststripCore/Search/AssetStackBuilder.swift`)
is a **pure, stateless, in-memory** grouper — not a persisted catalog concept
by itself. Given an ordered `[Asset]` (by capture time in practice) plus an
optional `visualSimilarity`-vector lookup, it walks adjacent pairs and groups
them into one stack when either:
- same folder AND capture-time gap ≤ 2s (`defaultMaximumCaptureGap`), or
- `visualSimilarity` feature-print Euclidean distance ≤ 0.05
  (`defaultMaximumVisualSimilarityDistance`) — this vector comes from the
  persisted `visualSimilarity` `EvaluationSignal` (Apple Vision feature
  print), so **this criterion is inert for any asset that hasn't been
  evaluated by `apple-vision`.**

Each `AssetStack{assetIDs, rationale}` carries a human-readable grouping
rationale string ("Same folder, captured within 2s" / "Visual similarity
distance 0.041 <= 0.050", `AssetStackBuilder.swift:123-129`) — this is
*grouping* provenance, not a "why is this the best frame" rationale (see
ranking below, which is separate).

Confirms the July 6 doc's claim ("time-adjacent + visual-similarity stacks
exist") is accurate for the grouping *rule*; what's genuinely new since that
doc is that the best-frame ranking is now rendered (not just computed) and a
sidebar exists to browse stacks (below).

**Persistence:** stacks aren't stored as their own entity; a stack-culling
session snapshots each detected stack as its own `work-stack-<session>-N`
row in `asset_sets` so the groupings a session started with survive relaunch
(`AppModel.saveCullingStackInputSets`) — everywhere else (Compare's
on-the-fly candidate stack, the assist pill, autopilot) `AssetStackBuilder`
is simply re-run over the current scope.

### 3.2 Best-frame ranking within a stack

`CullingQualityScore` (`Sources/TeststripCore/Evaluation/CullingQualityScore.swift`)
is the **single shared scorer** — used by stack-rail ranking, the verdict
pill, Compare's suggests-pill/contenders ranking, AND
`AutopilotProposalPlanner`'s pick/reject proposals (a code comment there says
explicitly this is "so the banner's read and the proposal ranking can never
disagree" — a redesign should keep reusing this rather than forking a second
ranking). It's a defect-inverted, confidence-weighted sum over best-per-kind
components: `focus` ×100, `eyesOpen` ×90, `faceQuality` ×80, `eyeSharpness`
×70, `motionBlur` ×60 (inverted), `aesthetics` ×50, `framing` ×45; `exposure`
and label/vector/text kinds are excluded from ranking entirely. A frame with
zero rankable signals is excluded from ranking (not scored as zero) — so
ranking silently produces "no recommendation" rather than a false winner.

`CullingStackRecommendation.rankedCandidates`
(`LibraryGridView.swift:6245-6261`) sorts stack members by this score.
`.rationalePhrases`/`.comparativeQualifiers`
(`LibraryGridView.swift:6291-6358`) generate short, **honest** (score-gated,
not just composite-ranking-gated) reasons — "sharpest" only when the
leader's *raw* focus score beats every other member's, "eyes open" only at a
literal 1.0 `eyesOpen` score, comparative deltas like "23% sharper" only when
the runner-up's own score is high enough for a percentage to be meaningful
(`minimumRunnerUpFocusForPercentageDelta = 0.1`, guards against a
near-zero-denominator inflated percentage).

**Rendering (this is new since the July 6 audit, which said "the recommended
frame is computed and never rendered"):** the recommended frame gets a ✦
badge in both the loupe stack-rail chips (`LibraryGridView.swift:4466-4471`)
and the loupe filmstrip (`:4578-4583`); flaw badges and pick/reject decision
overlays render per-chip too (`CullingStackRailPresentation.Item`,
`LibraryGridView.swift:6008-6015`).

### 3.3 RAW+JPEG bonding (distinct from stacking)

Landed most recently (`git log`, merge `a1a79238`, "bond RAW+JPEG into one
logical asset (RAW primary)"). `AssetBondPlanner`
(`Sources/TeststripCore/People/AssetBondPlanner.swift` — lives in the
`People/` directory despite having nothing to do with faces) pairs a RAW
original with same-folder, same-filename-stem JPEG/HEIC working stills; the
RAW is always primary, and the working still's `assets.bonded_to_asset_id`
column (`CatalogMigrations.swift:21`) points at the RAW's `AssetID`. Bonded
secondaries are hidden from grid/timeline/folder/place/source-root/people
counts and listings — one logical asset, two files on disk — but move to
trash/relocation together with the primary
(`Sources/TeststripCore/Relocation/`), and a RAW/RAW+JPEG badge renders on
the tile (`RawBadgeLabel`, `LibraryGridView.swift:6361-6373`). This is
orthogonal to burst stacking: a RAW+JPEG pair of the *same* exposure is one
logical asset; a burst of several distinct exposures is a stack of several
logical assets.

---

## 4. Current culling UI surfaces

### 4.1 Views

Two top-level workspaces (`Workspace` enum, `AppModel.swift:50-52`, ⌘1/⌘2):
**Cull** (default sub-view `.loupe`) and **Library** (default `.grid`).

Cull-workspace sub-views (`LibraryViewMode`): `.loupe`, `.cullGrid`,
`.compare`, `.abCompare`.

- **LoupeView** (`Sources/TeststripApp/LibraryGridView.swift:3758` onward,
  ~1,000 lines) — the main culling stage: large image, header HUD
  ("Frame N of M", progress bar, live pick/reject count pills, last-decision
  feedback pill, scope chip), the `CullingAssistPresentation` verdict pill
  ("Keep read 82% — Aesthetics 74% · sharpest · eyes open", detail on
  hover), the stack rail (when the selection is in a ≥2-frame stack:
  "Stack N of M"/"Frame N of M", grouping rationale, numbered chips with ✦
  recommended badge + flaw badges + decision overlay, and 3 actions — Keep
  selected & cut, Keep recommended/Keep top 2, Keep all), the Close-Ups
  panel (§2.2), a 12-thumbnail filmstrip with flag/rating overlays, an
  on-screen P/X/U + 1–5★ + 6 color-label command rail, a completion banner
  (`CullingCompletionBannerView`, pick/reject tally + "View Picks"), an
  autopilot banner (`AutopilotBannerView`, when tentative pending proposals
  exist for the visible scope), a reject-relocation banner, and a
  3-state EXIF overlay (`i` key: off / one-line exposure / full).
- **CompareView** ("survey confirm", `LibraryGridView.swift:6608` onward) —
  up to 8-frame grid; **contenders-only mode** (toggle, gated on the ranking
  having ≥2 candidates) narrows to the top-`N` ranked contenders with #1/#2/#3
  rank badges and `comparativeQualifiers` rationale instead of raw flaw
  badges; per-tile focus-metric lanes; footer actions "Keep primary/top
  signal · reject N", "Keep all", "Keep #1 & #2" (contenders mode only),
  "Choose manually"; auto-advances to the next stack/group after a decision.
- **ABCompareView** (`LibraryGridView.swift:6373-6608`ish) — a two-up A/B
  comparison sub-view with dedicated `,`/`.` keyboard verdicts. **Did not
  exist at the time of the July 6 audit** — new surface to account for.
- **Grid / `.cullGrid`** — standard thumbnail grid
  (`AssetGridCell`, badges for flag/rating/color-label/keyword-count/RAW),
  with its own `GridKeyCaptureView` monitor; `.cullGrid` is the Cull
  workspace's grid entry point.
- **CullSidebarView** (`Sources/TeststripApp/CullSidebarView.swift`) — the
  Cull workspace's left rail, replacing the Library `SidebarView` while in
  Cull: a "Cull From" section (recent import, autopilot proposals, Top
  Picks/Needs Eyes review queues, diagnostics rows — Rejects/Five
  Stars/Needs Keywords/Faces Found/OCR Found/Provider Failures — and the
  current Library selection) plus a **"Stacks · Auto-Grouped"** section:
  per-stack lead thumbnail, title, frame count, a green checkmark once every
  frame in that stack is decided, and highlight-on-selected. This directly
  answers the July 6 audit's gap #8 ("no stack rail/list") — it now exists.

### 4.2 Keyboard shortcut table

Bare (no-modifier) culling keys are captured locally per-view — never bound
as SwiftUI `.keyboardShortcut` in the menu, because AppKit's menu key
equivalents fire independently of the local monitors and would double-dispatch
a single keypress (documented at `main.swift:558-572`, with a cited live
regression). The `?` overlay and the Culling menu (click-only) are the
discoverability path for these.

**Culling loupe/compare/A-B (`CullingKeyCaptureView.swift` monitor, active
only in the Cull workspace's loupe/compare/A-B sub-views —
`CullingKeyCaptureGate`, `CullingKeyCaptureView.swift:11-15`; decoded by
`CullingShortcut`, `AppModel.swift:191-280`):**

| Key | Action | Source |
|---|---|---|
| ← | Previous stack | `AppModel.swift:194,235` |
| → | Next stack | `:195,237` |
| ↑ | Previous frame within stack | `:200,239` |
| ↓ | Next frame within stack | `:201,241` |
| Space | Next photo (advance) | `:193,252` |
| Return / Enter | Promote selected & reject stack siblings | `:207,243` |
| 0–5 | Rating 0 (clear) – 5 stars | `:253-258` |
| 6 / 7 / 8 / 9 / V | Color label red / yellow / green / blue / purple | `:259-263` |
| `-` | Clear color label | `:264` |
| P | Pick | `:265` |
| X | Reject | `:266` |
| U | Clear flag | `:267` |
| Z | Toggle zoom | `:268` |
| Shift+Z | Zoom to nearest detected face | `:140-144,209` |
| I | Cycle EXIF overlay (off/line/full) | `:269` |
| S | Cycle cull scope (unrated/picks/rejects/all) | `:270` |
| G | Show cull grid | `:271` |
| C | Show Compare | `:272` |
| B | Show A/B Compare | `:273` |
| `,` | A/B Compare: keep A over B | `:225,274` |
| `.` | A/B Compare: keep B over A | `:226,275` |
| `?` (Shift+/) | Show key-map overlay | `:145-148,211` |
| PageUp/PageDown | Page the key-map overlay (only while it's open) | `:227-230` |
| Esc | Exit Compare/A-B back to loupe (modal-trap escape; loupe itself uses a separate Escape path) | `CullingKeyCaptureNSView.swift:86-93` |

**Library/cull grid (`GridKeyCaptureView.swift` monitor,
`GridKeyCommand.init(input:)`, lines 60-92):**

| Key | Action |
|---|---|
| ←/→/↑/↓ | Move selection (↑/↓ by column count) |
| Home/End | Jump to first/last |
| Return / Space | Open loupe |
| Escape | Return to grid (only meaningful from `.loupe`) |
| 0–5 | Rating |
| P / X / U | Pick / reject / clear flag |
| G / C / B (only in `.cullGrid`) | Jump straight to loupe / Compare / A-B Compare |

**Menu-bound (real SwiftUI `.keyboardShortcut`s, all modified — never bare
— so they can't collide with the monitors above), all in `main.swift`:**

| Shortcut | Action | Location |
|---|---|---|
| ⌘1/⌘2 | Switch workspace (Cull/Library) | `:194` |
| ⌘Z / ⇧⌘Z | Undo/redo metadata change | `:275,281` |
| ⌘F | Focus search (Find) | `:318` |
| ⇧⌘[ / ⇧⌘] | Navigate back/forward | `:331,337` |
| ⌥⌘M | Batch Metadata… | `:367` |
| ⇧⌘B | Find Best Shots | `:440` |
| ⇧⌘E | Evaluate Visible | `:460` |
| ⇧⌘0 | Toggle Activity panel | `:607` |
| ⌘I | Toggle Inspector | `:621` |
| ⌥⌘+section key | Scroll Inspector to section | `:629` |
| ⌘+ / ⌘− | Zoom grid thumbnails in/out | `:644,649` |

Other `.keyboardShortcut` usages in the app are all sheet default/cancel
actions (Return/Escape on confirm dialogs — `FaceGroupReviewView.swift`,
`SheetScaffold.swift`, `SourceReconnectSheet.swift`,
`LibraryGridView.swift:1280` &c.) and `PersonAutocompleteField`'s
`.onKeyPress` up/down/return for its popover list — not culling-specific.

### 4.3 Rating/flag/keyword operations on `AppModel`

- Flags: `PickFlag` = `.pick`/`.reject` (`Metadata.swift:11-14`);
  `setFlagForSelectedAsset`, `applyCullingCommandAndAdvance` (auto-advances
  after a decision), `applyCompareFlags` (whole-group), all routed through
  an undoable `metadataUndoStack`.
  `keepSelectedStackFrameAndRejectAlternates`/`applyCullingStackDecision`
  handle whole-stack decisions.
- Rating: 0–5 int (`AssetMetadata.rating`, validated range).
- Color label: 5-value `ColorLabel` enum + clear.
- Keywords/caption/creator/copyright: same undoable metadata path;
  AI-sourced ones carry the `aiUnconfirmedFields`/`aiUnconfirmedKeywords`
  provenance from §1.4.
- **Picks set**: `refreshCullingSessionOutputSet` snapshots a `"<session>
  Picks"` `asset_sets` row containing exactly the picked input frames on
  every flag change inside a culling session; deletes it if picks drop to
  zero. Browsable via the sidebar, the Picks review queue
  (`ReviewQueue.picks`), or reopening the session from Recent Work.
- **Move-rejects flows**: `requestMoveRejects`/`moveRejectsToFolder`
  (`AppModel.swift:2493,11712`) relocates rejected originals (+ bonded
  JPEGs, + sidecars) to a folder; `requestMoveRejectsToTrash`/
  `moveRejectsToTrash` (`:2507,11819`) does the Trash equivalent — both go
  through `Sources/TeststripCore/Relocation/` with a manifest for undo.
- **Filtering/search scopes**: `SetQuery.Predicate` has 22 cases
  (`Sources/TeststripCore/Search/SetQuery.swift:19-39`) including `flag`,
  `colorLabel`, `ratingAtLeast`, `person`, `keyword`, `camera`, `lens`,
  `isoAtLeast`, date ranges, geo bounds, `evaluationKind`, `unevaluated`,
  `likelyIssue`, `likelyPick`, `evaluationFailure`,
  `metadataSyncPending/Conflict`, `importBatch`, `workSession`. All are
  reachable through `LibraryQueryTokenField`'s typed tokens
  (`camera:`, `lens:`, `keyword:`/`tag:`, `person:`, `folder:`/`path:`,
  `color:`, `iso:`, `rating:`, `from:`/`before:`, `source:`,
  `signal:`/`evaluation:`/`kind:`, `xmp:`, `session:`, `import:` —
  `LibrarySearchIntent.swift:118-168`) as well as the dedicated
  `CullScope` unrated/picks/rejects/all cycle (`S` key, §4.2) and the
  `ReviewQueue` 10-case enum (`picks, potentialPicks, rejects, fiveStars,
  needsKeywords, needsEvaluation, facesFound, ocrFound, likelyIssues,
  providerFailures` — `AppModel.swift:594-604`).

---

## 5. Gaps vs. Narrative-Select-style capabilities

| Capability | Status | Evidence |
|---|---|---|
| **Scene grouping + ranking** | **Exists** | `AssetStackBuilder` groups by time/visual-similarity (§3.1); `CullingQualityScore` ranks within a group and is rendered as a ✦ badge + "Keep recommended"/"Keep top 2" actions in both stack rail and Compare (§3.2). Gap: ranking silently degrades to "no recommendation" for any asset lacking evaluation signals — there's still no forced/automatic evaluation-on-import default that guarantees signals exist by the time a user starts culling (see below). |
| **Eyes-open detection** | **Exists** | `eyesOpen` signal (CIDetector, §1.1), surfaced in the verdict pill ("Eyes open"/"Eyes shut"/"Some eyes shut") and factored into ranking (weight 90) and rationale phrases. No blink/looking-down beyond open/closed — matches the July 6 doc's own caveat ("do not overclaim") and that remains true. |
| **Face-region focus** | **Exists** | `eyeSharpness` signal — per-eye crop sharpness, min-across-faces (§1.1); no other face-region (e.g. mouth, whole-head) focus metric. |
| **Close-Ups panel** | **Exists** | `CloseUpFacesPresentation` + loupe `closeUpsPanel` (§2.2) — auto-populated per selection, up to 4 crops. Difference from Narrative Select: no spacebar-zoom-to-face gesture (Teststrip uses Shift+Z instead; Space advances to the next photo). |
| **Potential Picks filter** | **Exists** | `ReviewQueue.potentialPicks` backed by the `likelyPick` SQL predicate (§1.2); reachable from the Cull sidebar's "Top Picks" row and search. |
| **People filter** | **Exists** | `SetQuery.Predicate.person(String)`, `person:` search token, tap-to-filter from `PeopleView` named-person cards with photo-count badges (§2.1). |
| **Instant full-res paging** | **Partial** | `AppModel.prefetchLoupeNeighborLargePreviews` (`AppModel.swift:8913-8925`) warms exactly ±1 neighbor's `.large` cached preview on loupe-arrival (`docs/architecture/preview-pipeline.md`). This is real prefetch, but bounded to one frame each way and demand-driven for medium/large in general — a fast multi-frame keyboard-only cull (arrow-arrow-arrow through a 20-frame burst) can still outrun the prefetch window. No "never shows a low-res placeholder" guarantee for rapid multi-step navigation. |
| **Per-frame verdict with confidence** | **Exists** | `CullingAssistPresentation`'s "Keep/Toss/Mixed read NN%" verdict line (§1.3) — this was gap #6 in the July 6 audit and is now built. Still title/detail only in a fixed-width pill; no dedicated "flaw" iconography beyond text. |
| **Comparative tie-break rationale** ("Frame 3 edges it — 8% sharper, eyes open") | **Exists (Compare only)** | `CullingStackRecommendation.comparativeQualifiers` (§3.2), surfaced through Compare's contenders-only rank badges. Not surfaced in the loupe stack rail beyond the button help text. |
| **Key Element Detection (saliency fallback)** | **Absent** | No hits for `saliency`/`Saliency`/`VNGenerateAttentionBasedSaliencyImageRequest` anywhere in `Sources/`. Framing score exists (rule-of-thirds luminance heuristic) but is not a subject-saliency detector. |
| **Smile detection** | **Exists** | `smile` signal (§1.1), same CIDetector pass as eyes-open. |
| **A/B Compare mode** | **Exists (new, undocumented in prior specs)** | `ABCompareView`/`ABComparePresentation` with `,`/`.` verdict keys — not mentioned in the narrative-select reference or the July 6 audit at all; a genuinely new surface since. |
| **Scenes View (browsable stack list)** | **Exists** | `CullSidebarView`'s "Stacks · Auto-Grouped" section (§4.1) — this was gap #8 in the July 6 audit ("blind" stack cull) and is now built. |
| **One-click shipping to Lightroom/Capture One** | **Different approach (by design, not a gap)** | Teststrip writes XMP sidecars continuously + resized-JPEG export; no direct LR/C1 integration is planned (per the reference doc's own note). |
| **Auto-evaluation after import (prerequisite for everything above)** | **Exists, opt-out** | `ImportConfirmationDraft.evaluateAfterImport` defaults to `true` (`Sources/TeststripApp/ImportConfirmationDraft.swift:266`, gating the plan step at `:448`) and threads into `AppModel`'s import entry points (`AppModel.swift:12851,12865,12941,12955` set `importAutoEvaluationEnabled`), which queues the standard provider passes as cached previews complete. This was blocking gap #1 in the July 6 audit and is resolved. |

---

## Files most relevant to a redesign, at a glance

- Signals & scoring: `Sources/TeststripCore/Evaluation/{EvaluationSignal,LocalImageMetricsEvaluationProvider,AppleVisionEvaluationProvider,FaceExpressionEvaluationProvider,PreviewPixelMetrics,CullingQualityScore}.swift`
- Face pipeline: `Sources/TeststripCore/People/{FaceRecognitionEmbedder,FaceSuggestionBuilder,FaceAligner,CoreMLFaceEmbeddingModel,ContactFaceSeeder,ContactFaceEmbedder,PersonCandidateRanker,AssetBondPlanner}.swift`, `Sources/TeststripCore/Catalog/{CatalogFaceObservation,RejectedFacePerson}.swift`
- Stacks/autopilot: `Sources/TeststripCore/Search/AssetStackBuilder.swift`, `Sources/TeststripCore/Autopilot/{AutopilotProposal,AutopilotProposalPlanner,AutopilotQueryTranslator}.swift`
- Catalog schema: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (version 22)
- Culling UI: `Sources/TeststripApp/LibraryGridView.swift` (LoupeView, CompareView, ABCompareView, all the `Culling*`/`Compare*` presentation types), `Sources/TeststripApp/CullSidebarView.swift`, `Sources/TeststripApp/CloseUpFacesPresentation.swift`
- Keyboard: `Sources/TeststripApp/{CullingKeyCaptureView,GridKeyCaptureView,main}.swift`, `CullingShortcut`/`CullingShortcutKey` in `Sources/TeststripApp/AppModel.swift:191-490`
