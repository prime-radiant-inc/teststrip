# Machine-label provenance & auto-apply

_Date: 2026-07-14 · Sub-project 1 of the People/agentic-tags redesign_
_Rev 2 — revised after adversarial review (see “Review corrections” below)._

## Problem

Today Teststrip follows **confirm-before-write**: machine-derived labels (AI
face/person matches, AI scene keywords, AI captions, autopilot pick/reject
proposals) stay *provisional and unwritten* until an explicit per-item user
gesture creates them. The face and keyword suggestions live only in memory
(`FaceSuggestionBuilder`, `batchKeywordSuggestions`); autopilot keeps a
separate persisted proposal table reviewed and then committed.

This makes the AI's work invisible until a human grinds through confirmations,
and it produced UX that a user-persona panel found actively unsafe or
confusing: an "Apply People 759 photos at 90%" pill that one-click mass-writes
keywords with no review, face cards that ask you to name people blind, etc.

We are inverting the model. **Machine labels auto-apply immediately, each
tagged with a provenance flag (`origin = ai`, unconfirmed). A user gesture then
confirms the label (clears the flag) or removes it.** The AI's guesses become
visible, filterable, and reviewable in place, while a clear provenance flag
keeps human-confirmed truth distinct from machine guesses.

This spec covers the **foundation**: the data model, the auto-apply → confirm →
sidecar flow, folding autopilot in as *tentative* flags, and the invariant
rewrite. The *prominent* people-review experience and the ✨ tag chrome are
specified here only as requirements; their full UI lands in later sub-projects
(People-as-a-library-view and the face-group review redesign).

## Settled decisions (from brainstorming)

- **Unified model, two UI treatments.** Every machine label auto-applies with an
  AI/unconfirmed flag. For people the flag is *prominent* (review-first); for
  everything else it is a subtle ✨ on the tag.
- **Sidecar policy: confirm-gated.** Unconfirmed AI labels live in the
  **catalog only** — visible and filterable in-app, ✨-marked. The XMP sidecar is
  written only when a label is **confirmed**. Preserves the non-destructive
  invariant (sidecar = human-confirmed portable truth); originals untouched.
- **Autopilot folds in as tentative proposals.** Autopilot pick/reject/score
  labels auto-apply as unconfirmed (✨) *tentative* flags/ratings — proposals,
  not decisions. **They never drive committing or destructive operations
  (move/trash-rejects, culling commits); those act on confirmed labels only**
  (see “Tentative flags”). `autopilot_proposals` is retained for run
  tracking/rationale; run-level undo is restructured because flags now apply at
  run time.
- **Promotion reuses existing logic — carefully.** The auto-apply step reuses
  `FaceSuggestionBuilder` matching and object-label keyword derivation, but must
  add the guards those in-memory paths relied on downstream (rejection filtering,
  confirmed-only centroids, non-clobbering inserts) — see Promotion.

## Goals

- Machine labels (scene keywords, captions, face/person identity, autopilot
  flags/ratings) are written to the catalog at detection/run time, tagged
  `origin = ai`.
- A **confirm** gesture promotes a label to `origin = user` and *then* writes the
  XMP sidecar (for sidecar-eligible fields). A **remove** gesture deletes it and
  remembers the removal so promotion never resurrects it; "Not <name>" also
  records a face rejection.
- Unconfirmed AI labels are never written to XMP sidecars and never drive
  destructive/committing operations. Originals are never modified.
- The confirm-before-write invariant in `CLAUDE.md` is rewritten to the
  auto-apply-with-provenance model.

## Non-goals

- The prominent unconfirmed-**people** review surface and People-as-a-library-view
  (sub-project 2).
- Global filter persistence across views/modes (sub-project 4).
- The "Text found: Signal: Face count" filter-chip fix (its own sub-project).
- No change to how AI *reads* are produced (evaluation signals, face
  observations) — only to whether/how select reads are **promoted** into labels.
- Fixing the separate whole-asset-vs-face-derived `person_assets` ambiguity at
  `CatalogRepository.swift:1306-1312` (orthogonal to this `origin` flag).
- One-time backfill of AI labels onto already-imported assets (promotion applies
  going forward as assets are re-evaluated).

## Architecture

### The provenance flag

Each applied, user-facing label carries an origin: `user` (human-confirmed, the
current default) or `ai` (auto-applied, unconfirmed). Confirming an `ai` label
flips it to `user`; removing it deletes it. Existing catalogs migrate with all
current labels defaulted to `user` (they were only ever created by a confirm
gesture, so they are human-authored by construction).

### Data model (schema migration, next version)

Add columns via the existing idempotent `addColumnIfMissing` ALTER pattern in
`CatalogDatabase.migrate()`; bump the schema version in `CatalogMigrations`.

- **`person_faces`** — add `origin TEXT NOT NULL DEFAULT 'user'`. AI face matches
  insert **face-level** rows with `origin = 'ai'`. (This `user`/`ai` origin is
  orthogonal to the whole-asset-vs-face-derived ambiguity at
  `CatalogRepository.swift:1306-1312`, which this spec does not claim to fix.)
- **`person_assets`** — add `origin TEXT NOT NULL DEFAULT 'user'`. **AI matches do
  NOT create a `person_assets` row** — only a face-level `person_faces` row (see
  Promotion, and why below). The whole-asset link is created `origin = 'user'`
  only on user confirm or direct assign, via an upsert that sets the origin
  (`ON CONFLICT(person_id, asset_id) DO UPDATE SET origin = 'user'`) — never the
  current `INSERT OR IGNORE` (`CatalogRepository.swift:1229`), which would leave a
  stale row unpromoted.
- **`AssetMetadata`** (stored in `assets.metadata_json`, `Metadata.swift:16`) —
  add two provenance fields:
  - `aiUnconfirmedKeywords: Set<String>` — the subset of `keywords` that is AI.
    `keywords: [String]` stays the full applied set (in-app search/filters need no
    change); only display marks the subset ✨ and sidecar export excludes it.
  - `aiUnconfirmedFields: Set<MetadataField>` where `MetadataField ∈ {flag,
    caption, rating}` — the single-valued AI-settable fields (autopilot sets
    flag/rating; AI captioning sets caption; colorLabel/creator/copyright are
    never AI-set).
  - `AssetMetadata` has a **custom** `init(from:)` (`Metadata.swift:66-84`); both
    fields must be decoded with `decodeIfPresent(...) ?? []` (Swift throws on a
    missing key and does not apply property defaults). Old blobs then decode as
    fully confirmed.
- **`removed_ai_labels`** (new table) — keyed by `(asset_id, field, value)`
  (`value` empty for single-valued fields). Records that the user removed an
  AI-applied keyword/caption/flag/rating, so promotion never re-adds it. (Face
  rejections already have `rejected_face_people`; this is the analogue for
  metadata labels. Preferred over an in-`metadata_json` set so all label types
  share one mechanism.)
- **`autopilot_proposals`** — schema unchanged; retained for run
  tracking/rationale. Its `pending → committed` lifecycle is superseded by
  auto-apply (the flag lands in `metadata_json` as tentative at run time).

### Auto-apply (promotion)

After the background worker records evaluation signals and face observations
(unchanged), a **promotion step**, bounded to the just-evaluated asset(s), turns
select reads into flagged labels. It is idempotent and never clobbers a `user`
label, a field the user set, or anything in `removed_ai_labels` /
`rejected_face_people`.

- **Scene keywords** — an object read is one `.object` signal carrying a *list*
  of labels and a **single** `confidence` for the whole signal (per-label scores
  are not available; `EvaluationSignal.confidence` is one value —
  `EvaluationSignal.swift:33`). So the floor is applied **per signal** (default
  **0.5**, tunable): if the signal clears the floor, each of its labels the asset
  does not already carry and that is not in `removed_ai_labels` is appended to
  `keywords` and `aiUnconfirmedKeywords`. Reuses `AppModel.objectLabels(from:)`.
- **Face/person identity** — build person centroids from **confirmed faces
  only**: the centroid query (`CatalogRepository.swift:1168-1191`) must add
  `person_faces.origin = 'user'`, else AI guesses feed back as ground truth and
  matching self-reinforces. Run `FaceSuggestionBuilder` matching
  (`defaultMaximumMatchDistance = 1.23`) against those centroids. For each face
  within distance of a person — **excluding** `(person, face)` pairs in
  `rejected_face_people` and any face that already carries a `user` assignment —
  insert an `origin = 'ai'`, **face-level** `person_faces` row via a *guarded*
  insert (never `ON CONFLICT(asset_id, face_index) DO UPDATE SET person_id`,
  which would overwrite a user assignment — `CatalogRepository.swift:1219`). **No
  `person_assets` row is written for an AI match.** Faces matching no confirmed
  person stay unassigned for the clustering / “who is this” review (sub-project
  2). Because AI matches are face-level and don't touch `person_assets`,
  co-occurring unmatched faces in the same photo remain reviewable — but the
  review pool query `unassignedFaceObservations` (`CatalogRepository.swift:1136-1166`)
  must exclude assigned *faces*, not whole *assets* (today it excludes any asset
  with a `person_assets` row).
- **Captions** — if an AI caption signal exists, the asset has no user caption,
  and the caption is not in `removed_ai_labels`, set `caption` and add `caption`
  to `aiUnconfirmedFields`.
- **Autopilot flags/ratings** — an autopilot run writes each proposed
  `.pick`/`.reject` into `metadata.flag` and each proposed score into
  `metadata.rating` as **tentative**, adding `flag`/`rating` to
  `aiUnconfirmedFields`, using the planner's confidence, skipping fields the user
  set or removed. Autopilot `.keyword` proposals flow through the scene-keyword
  path above (so no proposal kind is stranded). The run records a metadata
  undo group **at run time** (the assets/fields it touched) so “undo autopilot
  run” reverts the tentative writes; `undoAutopilotRun` is repointed to that
  group instead of the old commit-time group.

### Confirm / remove gestures

- **Confirm** (per label): clear the `ai` flag → `user`. Keyword → remove from
  `aiUnconfirmedKeywords`. Field → remove from `aiUnconfirmedFields`. Face → set
  `person_faces.origin = 'user'` **and** upsert the whole-asset `person_assets`
  link with `origin = 'user'` (the `ON CONFLICT … DO UPDATE` above). Confirming a
  **sidecar-eligible** field (keyword/caption/flag/rating) writes the sidecar (see
  below). Confirming a **face** writes no sidecar — identity is not a field
  `XMPPacket` exports; it only flips `origin` in the catalog.
- **Remove** (per label): delete it **and** record it in `removed_ai_labels`
  (keyword/caption/flag/rating) so promotion won't resurrect it. Face → delete the
  `person_faces` row (and the `person_assets` link if no faces remain for that
  person in the asset, per the existing `unassignFaces` reconciliation).
- **"Not <name>"** (identity reject): delete the face's `person_faces` row and
  record a `rejected_face_people` row.
- Bulk confirm/remove over a selection is one explicit user gesture over an
  explicit set; each writes sidecars for the confirmed subset only.

### Sidecar policy (confirm-gated, at the write layer)

The sidecar is **not** written by `applyMetadataSnapshot` in the normal path; the
actual `.xmp` bytes are written by the **worker** from the full `asset.metadata`
(`WorkerCommandExecutor.swift:492`) and by the inline/conflict paths
(`AppModel.swift:7418`, `:7448`). Filtering must therefore live at the write
layer, and three things interlock:

1. **Confirmed-only at the packet layer.** `XMPPacket` / `XMPSidecarStore`
   (`XMPPacket.swift:68-93`, `XMPSidecarStore.swift:50`) always emit the
   *confirmed projection*: `keywords` minus `aiUnconfirmedKeywords`, and
   `flag`/`caption`/`rating` only when not in `aiUnconfirmedFields`. Because it's
   at the packet layer, no caller can leak an unconfirmed label regardless of
   which write path fires.
2. **AI-only changes queue no sidecar write.** Promotion mutates `metadata_json`,
   which bumps `catalog_generation` (`CatalogRepository.swift:61-64`) and would
   make `MetadataSyncPlanner` return `.writeCatalog` (`MetadataSyncPlanner.swift:43`),
   re-writing an already-sidecar’d asset with no user gesture. The sync decision
   must key on whether the **confirmed projection** changed, not raw
   `catalog_generation`: promotion does not advance the sidecar-sync watermark,
   and `AssetMetadata.hasWrittenPortableMetadata` (`Metadata.swift:36-44`) becomes
   confirmed-aware (an AI-only asset reports “nothing portable to sync”).
3. **Import merges, never replaces.** `.importSidecar`
   (`WorkerCommandExecutor.swift:519`, `IngestService.swift:168`) currently does
   `catalogMetadata = sidecarMetadata`, wiping catalog-only AI labels on any
   external-sidecar freshen. Import must **merge** the parsed (confirmed) sidecar
   into existing catalog metadata, preserving `aiUnconfirmedKeywords` /
   `aiUnconfirmedFields` and their values.

Confirming a label advances the watermark and writes the sidecar with the
now-confirmed value. Net: an asset can carry AI labels in the catalog with no
sidecar on disk; the sidecar gains a field only on confirm; an external sidecar
edit never destroys catalog AI state.

### Tentative flags: never committing or destructive

An unconfirmed AI flag/rating is a *proposal*. `metadata.flag` / `metadata.rating`
are read raw by many consumers; each must choose confirmed-only vs. all values:

- **Destructive / committing — confirmed-only (safety-critical, tested).** The
  reject-relocation scope that moves/trashes originals (`rejectRelocationScope`,
  `AppModel.swift:10664` → `moveRejectsToFolder`, `:10702`) must match **confirmed
  rejects only**. A tentative AI reject must never move or trash a file — asserted
  with a negative test.
- **Culling counts / “undecided” triage — tentative = undecided.** An asset whose
  only flag is tentative is still awaiting the user, matching the prior
  autopilot-proposal semantics; decision counts (`AppModel.swift:2574-2575`) and
  the undecided predicate (`:6496`) treat tentative flags as not-yet-decided.
- **Display / scope views — may show, cannot commit.** The picks/rejects scope
  filters (`AppModel.swift:315-316`) may *show* tentative flags (✨) as proposals.

Implementation: flag/rating predicates and in-memory culling counts gain
confirmed-awareness via `aiUnconfirmedFields`. Every `metadata.flag` consumer is
enumerated and audited during implementation; the reject-relocation exclusion is
the one that must not be missed.

### What this replaces

- `FaceSuggestionBuilder` in-memory suggestions + `PhotoFacesPresentation.suggested`
  (in-RAM) → derived from persisted `origin = 'ai'` `person_faces`.
- `batchKeywordSuggestions` + accept paths + the inline "Suggestions" pills
  (`currentBatchKeywordSuggestionBar`, `LibraryGridView.swift:1118`) →
  auto-applied ✨ keywords with per-keyword confirm/remove. **The pills are removed.**
- Autopilot proposal review/commit (`commitAutopilotProposals`,
  `AppModel.swift:8579`) → tentative flags auto-applied at run time; the review
  action becomes confirm/remove over the flagged set; undo repointed to the
  run-time group.

### UI language (specified here, applied later)

- Non-identity unconfirmed labels render with a subtle **✨** and inline
  confirm/remove (chrome in sub-project 3). This spec only requires the model
  expose per-label `origin` so the UI can mark them.
- Unconfirmed **people** get the *prominent*, review-first treatment (sub-project
  2). This spec requires only that unconfirmed identity be queryable
  (`person_faces.origin = 'ai'`).

### Invariant rewrite (`CLAUDE.md`)

Replace "Confirm-before-write" with **"Auto-apply with provenance"**:

> Machine labels (scene keywords, captions, face/person identity, autopilot
> flags/ratings) auto-apply to the catalog immediately, tagged `origin = ai`
> (unconfirmed, shown ✨). Unconfirmed labels are **never** written to `.xmp`
> sidecars and **never** drive committing or destructive operations
> (move/trash-rejects) until an explicit user gesture confirms them; confirmation
> flips `origin → user` and (for sidecar-eligible fields) writes the sidecar.
> Removing an AI label deletes it and records the removal so it is not
> resurrected; identity rejection records a negative. Original image bytes are
> never modified. Unconfirmed people are surfaced prominently, not silently.

## Data flow

worker eval/detection (unchanged) → **promotion** writes flagged labels to
catalog (`person_faces.origin='ai'`, `aiUnconfirmedKeywords`, `aiUnconfirmedFields`),
respecting removed/rejected memory, from confirmed-only centroids, without
sidecar writes → UI shows them (✨ / prominent for people) → user **confirms**
(flag→user, watermark advances, sidecar written) or **removes** (delete + record
removal) → confirmed labels export to XMP; tentative flags never move/trash.

## Testing

- **Migration:** the new version adds `origin` to `person_faces`/`person_assets`
  (existing rows → `user`) and the `removed_ai_labels` table; existing
  `metadata_json` decodes with empty provenance sets and does **not** throw.
- **Auto-apply:** an above-floor object signal adds its labels to `keywords` +
  `aiUnconfirmedKeywords` with **no** sidecar written; a within-distance face
  match creates an `origin='ai'` face-level `person_faces` row (and **no**
  `person_assets` row) with no sidecar.
- **Confirmed-only centroids:** an `origin='ai'` face does not alter the centroids
  used for the next promotion pass (no self-reinforcement).
- **Promotion guards:** promotion skips a keyword in `removed_ai_labels`, skips a
  `rejected_face_people` pair, does not overwrite a `user` face assignment, and
  does not overwrite a `user` caption/flag/rating.
- **Confirm:** confirming a keyword clears it from `aiUnconfirmedKeywords`, writes
  the sidecar, and the XMP contains it; confirming a face sets `person_faces` and
  `person_assets` origin to `user` and writes no sidecar.
- **Remove:** removing an AI keyword drops it and records `removed_ai_labels`, no
  sidecar; a subsequent promotion does not re-add it; "Not <name>" deletes the
  face row and records a rejection.
- **Sidecar layer:** every write path (worker, inline, conflict) emits confirmed
  labels only; a mixed asset exports only confirmed keywords;
  `hasWrittenPortableMetadata` is false when only AI labels exist.
- **No AI-only sidecar churn:** promoting a keyword onto an already-sidecar’d
  asset does not queue or write a sidecar.
- **Import merge:** importing/freshening a sidecar preserves catalog-only AI
  keywords/caption/flag (does not wipe them).
- **Tentative flags never destructive:** an asset with only a tentative AI
  `.reject` is **not** in the reject-relocation scope and is not moved/trashed; it
  counts as undecided.
- **Autopilot:** a run applies tentative flags/ratings (no sidecar); `.keyword`
  proposals land in `aiUnconfirmedKeywords`; run-level undo reverts the run's
  tentative writes; confirming a flag then writes the sidecar.
- **E2E scenario (VM):** evaluate seeded photos; assert ✨ AI keywords appear,
  catalog has `origin='ai'` with no `.xmp`, and no photo was relocated; confirm
  one keyword; assert `origin='user'` and the `.xmp` now carries it; run autopilot
  and assert a tentative AI reject does not move the file until confirmed; assert
  originals unchanged throughout.

## Review corrections (rev 2)

Adversarial review found the rev-1 design under-modeled how deeply auto-apply
touches the sidecar/sync/culling machinery. Corrections folded in:

- Sidecar confirmed-only filtering moved from `applyMetadataSnapshot` to the
  `XMPPacket`/`XMPSidecarStore` write layer (the worker writes the real bytes);
  `catalog_generation`/sync-watermark interplay handled; `.importSidecar` merges
  instead of replacing.
- AI flags/ratings are tentative and excluded from destructive/committing paths
  (reject-relocation, counts, triage), per Jesse.
- Face promotion: confirmed-only centroids; respect `rejected_face_people`;
  guarded non-clobbering insert; face-level only (no auto `person_assets`);
  review pool excludes assigned faces not assets; confirm upserts `person_assets`
  origin.
- Removed-AI-label memory (`removed_ai_labels`) so promotion never resurrects a
  removed keyword/caption/flag/rating.
- Per-signal (not per-label) object-keyword confidence floor.
- Autopilot `.keyword` proposals routed through keyword promotion; undo repointed
  to a run-time group.
- Dropped the false claim that `origin` fixes the 1306-1312 ambiguity; corrected
  the Codable-default mechanism to `decodeIfPresent ?? []`.

## Risks and open items

- **`metadata_json` shape change** (new Codable fields, custom decoder) is the
  highest-churn touch point; every read/write must round-trip the provenance sets.
- **Sidecar write-layer refactor** (confirmed projection at `XMPPacket`/store,
  watermark keyed on confirmed change, merge-on-import) is the subtlest correctness
  area — a miss leaks AI labels to disk or wipes them on import.
- **Autopilot fold-in blast radius** across run/apply/undo and every
  `metadata.flag` consumer; the reject-relocation exclusion is safety-critical.
- **Face-promotion query changes** (`confirmedFaceEmbeddingsByPerson`,
  `unassignedFaceObservations`, the assign upserts) must be made together or the
  model self-reinforces or hides faces.
- **Confidence floors are guesses** (0.5 signal floor, 1.23 match distance);
  expose as constants and tune against real dogfood, not synthetic budgets.

## Out of scope (later sub-projects)

- Prominent unconfirmed-people review surface + People-as-a-library-view.
- The ✨ tag/inspector chrome details and confirm/remove affordance layout.
- Global filter persistence across views and modes.
- The "Text found: Signal: Face count" filter-chip fix.
- The whole-asset-vs-face-derived `person_assets` provenance ambiguity (1306-1312).
