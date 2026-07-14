# Machine-label provenance & auto-apply

_Date: 2026-07-14 · Sub-project 1 of the People/agentic-tags redesign_

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
sidecar flow, folding autopilot into the model, and the invariant rewrite. The
*prominent* people-review experience and the ✨ tag chrome are specified only as
requirements here; their full UI lands in later sub-projects (People-as-a-view
and the face-group review redesign).

## Settled decisions (from brainstorming)

- **Unified model, two UI treatments.** Every machine label auto-applies with an
  AI/unconfirmed flag. For people the flag is *prominent* (review-first); for
  everything else it is a subtle ✨ on the tag.
- **Sidecar policy: confirm-gated.** Unconfirmed AI labels live in the
  **catalog only** — visible and filterable in-app, ✨-marked. The XMP sidecar is
  written only when a label is **confirmed**. This preserves the non-destructive
  invariant (sidecar = human-confirmed portable truth) and keeps originals
  untouched, while still surfacing AI tags immediately in-app.
- **Autopilot folds in now.** Autopilot pick/reject flags auto-apply as
  unconfirmed (✨) flags into asset metadata when a run happens, replacing the
  separate `autopilot_proposals` review-then-commit flow. The proposal table is
  retained only for run tracking / rationale / undo.
- **Promotion reuses existing logic.** The auto-apply step reuses the current
  `FaceSuggestionBuilder` matching and object-label keyword derivation — it
  persists flagged labels instead of returning in-memory suggestions.

## Goals

- Machine labels (scene keywords, captions, face/person identity, autopilot
  flags) are written to the catalog at detection/run time, tagged `origin = ai`.
- A **confirm** gesture promotes a label to `origin = user` and *then* writes the
  XMP sidecar. A **remove** gesture deletes it; "Not <name>" also records a
  rejection.
- Unconfirmed AI labels are never written to XMP sidecars. Originals are never
  modified. The catalog remains the operational truth.
- The confirm-before-write invariant in `CLAUDE.md` is rewritten to the
  auto-apply-with-provenance model.

## Non-goals

- The prominent unconfirmed-**people** review surface and People-as-a-library-view
  (sub-project 2).
- Global filter persistence across views/modes (sub-project 4).
- The "Text found: Signal: Face count" filter-chip fix (sub-project: filter chip).
- No change to how AI *reads* are produced (evaluation signals, face
  observations) — only to whether/how select reads are **promoted** into applied
  labels.
- No new AI models or detectors.

## Architecture

### The provenance flag

Each applied, user-facing label gains an origin: `user` (human-confirmed, the
current default) or `ai` (auto-applied, unconfirmed). Confirming an `ai` label
flips it to `user`; removing it deletes it. Existing catalogs migrate with all
current labels defaulted to `user` (they were only ever created by a confirm
gesture, so they are human-authored by construction).

### Data model (schema migration, next version)

Add columns via the existing idempotent `addColumnIfMissing` ALTER pattern in
`CatalogDatabase.migrate()`; bump the schema version in `CatalogMigrations`.

- **`person_faces`** — add `origin TEXT NOT NULL DEFAULT 'user'`. AI face matches
  insert rows with `origin = 'ai'`. (This also resolves the pre-existing
  provenance ambiguity flagged at `CatalogRepository.swift:1306-1312`.)
- **`person_assets`** — add `origin TEXT NOT NULL DEFAULT 'user'`. A whole-asset
  person link is `ai` when it was created from an unconfirmed face and no user
  gesture; it becomes `user` when any face for that (person, asset) is confirmed
  or the asset is directly assigned by the user.
- **`AssetMetadata`** (stored in `assets.metadata_json`, `Metadata.swift:16`) —
  add two provenance fields:
  - `aiUnconfirmedKeywords: Set<String>` — the subset of `keywords` that is
    AI-applied. `keywords: [String]` stays the full applied set, so in-app search
    and filters need no change; only display marks the subset ✨ and sidecar
    export excludes it.
  - `aiUnconfirmedFields: Set<MetadataField>` where `MetadataField ∈ {flag,
    caption}` — the single-valued AI-settable fields. (Rating, colorLabel,
    creator, copyright are never AI-set, so they are not in this set.)
  - Both default to empty (Codable with default), so existing decoded metadata
    is treated as fully confirmed.
- **`autopilot_proposals`** — unchanged schema; its `status` lifecycle is
  retained for run tracking, rationale, and undo, but the proposed flag now lands
  in `metadata_json` as an `ai`-unconfirmed flag at run time rather than waiting
  for commit.

### Auto-apply (promotion)

After the background worker records evaluation signals and face observations
(unchanged), a **promotion step** turns select reads into flagged applied labels:

- **Scene keywords** — for each `.object` signal label above a confidence floor
  (default **0.5**, tunable), if the asset does not already carry that keyword,
  append it to `keywords` and add it to `aiUnconfirmedKeywords`. Reuses the
  existing object-label extraction (`AppModel.objectLabels(from:)`).
- **Face/person identity** — run the existing `FaceSuggestionBuilder` match logic
  (`defaultMaximumMatchDistance = 1.23`) against confirmed people; for each face
  within match distance of a person, insert an `origin = 'ai'` `person_faces`
  row (and the derived `person_assets` link, `origin = 'ai'`). Faces that match
  no confirmed person remain *unassigned* (they are handled by the clustering /
  "who is this" review in sub-project 2, not auto-named).
- **Captions** — if an AI caption signal exists and the asset has no user
  caption, set `caption` and add `caption` to `aiUnconfirmedFields`.
- **Autopilot flags** — an autopilot run writes each proposed `.pick`/`.reject`
  into `metadata.flag` and adds `flag` to `aiUnconfirmedFields`, using the
  planner's existing confidence. The run/rationale is still recorded in
  `autopilot_proposals` for the "why" and for run-level undo.

Promotion is **idempotent and non-clobbering**: it never overwrites a `user`
label or a field the user has set, and never re-adds a keyword the user removed
(rejections/removals are respected — see below).

### Confirm / remove gestures

- **Confirm** (per label): clear the `ai` flag → `user`. For a keyword: remove it
  from `aiUnconfirmedKeywords`. For a field: remove from `aiUnconfirmedFields`.
  For a face: set `person_faces.origin = 'user'` (and the `person_assets` link).
  Confirming a **sidecar-eligible** field (keyword, caption, flag) writes the
  sidecar (see below). Confirming a **face/identity** does not write a sidecar —
  person identity is not among the fields `XMPPacket` exports
  (rating/label/pick/keywords/caption/creator/copyright); it only flips `origin`
  in the catalog.
- **Remove** (per label): delete it. Keyword → drop from `keywords` and
  `aiUnconfirmedKeywords`. Field → clear the value and the flag. Face → delete the
  `person_faces` row (and the `person_assets` link if no faces remain for that
  person in the asset, per the existing `unassignFaces` reconciliation).
- **"Not <name>"** (identity reject): delete the face's `person_faces` row *and*
  record a `rejected_face_people` row so promotion never re-suggests that
  (person, face) pair.
- Bulk confirm/remove over a selection is allowed (it is still an explicit user
  gesture over an explicit set), and each writes sidecars for the confirmed
  subset only.

### Sidecar policy (confirm-gated)

`applyMetadataSnapshot` (`AppModel.swift:7375`) currently writes `metadata_json`
**and** calls `syncMetadataSidecar`. Split the two:

- Writing/updating a label that is (or remains) `ai`-unconfirmed updates
  `metadata_json` only — **no** sidecar write.
- Confirming a label (clearing its flag) writes `metadata_json` **and** triggers
  `syncMetadataSidecar`.
- The XMP packet (`XMPPacket`, `XMPSidecarStore`) exports **confirmed labels
  only**: `keywords` minus `aiUnconfirmedKeywords`, and confirmed `flag`/`caption`
  (i.e. those not in `aiUnconfirmedFields`).
- `AssetMetadata.hasWrittenPortableMetadata` (`Metadata.swift:36-44`) becomes
  flag-aware: only confirmed labels count as portable/user-authored.

Net effect: an asset can carry AI keywords/flags/people in the catalog with no
sidecar on disk; the sidecar appears/gains a field only when the user confirms.

### What this replaces

- `FaceSuggestionBuilder` in-memory suggestions + `PhotoFacesPresentation.suggested`
  (in-RAM) → derived from persisted `origin = 'ai'` `person_faces`.
- `batchKeywordSuggestions` derivation + accept paths + the inline
  "Suggestions" pills (`currentBatchKeywordSuggestionBar`,
  `LibraryGridView.swift:1118`) → auto-applied ✨ keywords with per-keyword
  confirm/remove. **The inline pills are removed.**
- Autopilot proposal review/commit (`commitAutopilotProposals`,
  `AppModel.swift:8579`) → flags auto-applied as unconfirmed; the review action
  becomes confirm/remove over the flagged set.

### UI language (specified here, applied later)

- Non-identity unconfirmed labels (keywords, caption, AI flag) render with a
  subtle **✨** marker and offer inline confirm/remove. This chrome is applied in
  the tag/inspector surfaces (sub-project 3); this spec only requires that the
  model expose per-label `origin` so the UI can mark them.
- Unconfirmed **people** get the *prominent*, review-first treatment — full UI in
  sub-project 2. This spec requires only that unconfirmed identity be queryable
  (`origin = 'ai'` on `person_faces`).

### Invariant rewrite (`CLAUDE.md`)

Replace the "Confirm-before-write" invariant with **"Auto-apply with
provenance"**:

> Machine labels (scene keywords, captions, face/person identity, autopilot
> flags) auto-apply to the catalog immediately, tagged `origin = ai`
> (unconfirmed, shown ✨). They are **never** written to `.xmp` sidecars until an
> explicit user gesture confirms them; confirmation flips `origin → user` and
> writes the sidecar. Removing an AI label deletes it; identity rejection also
> records a negative. Original image bytes are never modified. Unconfirmed people
> are surfaced prominently, not silently.

Keep the negative assertions, re-pointed: tests assert an AI label is present in
the catalog with `origin = ai` and **no** sidecar file; after confirm, `origin =
user` **and** the sidecar exists and contains the label; XMP export excludes
unconfirmed labels.

## Data flow

worker eval/detection (unchanged) → **promotion** writes flagged labels to
catalog (`person_faces.origin='ai'`, `aiUnconfirmedKeywords`, `aiUnconfirmedFields`)
→ UI shows them (✨ / prominent for people) → user **confirms** (flag→user +
sidecar write) or **removes** (delete [+ reject]) → confirmed labels export to XMP.

## Testing

- **Migration:** the new schema version adds `origin` to `person_faces` /
  `person_assets` defaulting existing rows to `user`; existing `AssetMetadata`
  decodes with empty `aiUnconfirmedKeywords` / `aiUnconfirmedFields`.
- **Auto-apply:** after evaluation, an above-floor object label is present in
  `keywords` and `aiUnconfirmedKeywords`, with **no** sidecar written; a
  within-distance face match creates an `origin='ai'` `person_faces` row with no
  sidecar.
- **Promotion guards:** promotion does not add a keyword the user removed, does
  not re-suggest a `rejected_face_people` pair, and does not overwrite a `user`
  caption/flag.
- **Confirm:** confirming a keyword clears it from `aiUnconfirmedKeywords`, writes
  the sidecar, and the XMP contains the keyword; confirming a face sets
  `origin='user'`.
- **Remove:** removing an AI keyword drops it from both sets and writes no
  sidecar; "Not <name>" deletes the face row and records a rejection.
- **XMP export:** a mixed asset (some confirmed, some ✨ keywords) exports only
  the confirmed keywords; `hasWrittenPortableMetadata` is false when only AI
  labels exist.
- **Autopilot:** a run applies unconfirmed flags to metadata with no sidecar;
  confirming writes the sidecar; run-level undo still works via
  `autopilot_proposals`.
- **E2E scenario (VM):** run evaluation on seeded photos, assert ✨ AI keywords
  appear and catalog has `origin='ai'` with no `.xmp`; confirm one; assert
  `origin='user'` and the `.xmp` now carries it; assert originals unchanged.

## Risks and open items

- **`metadata_json` shape change.** Adding `aiUnconfirmedKeywords` /
  `aiUnconfirmedFields` to `AssetMetadata` is a Codable change; ensure decode of
  old blobs defaults both to empty and every write round-trips them. This is the
  highest-churn touch point.
- **Promotion cost at scale.** Promotion runs per asset after evaluation; it must
  reuse the existing signal/observation reads and not add a new full-catalog
  scan. Bound it to the just-evaluated asset(s).
- **Autopilot fold-in blast radius.** Moving the flag from `autopilot_proposals`
  into `metadata_json` touches the run, review, commit, and undo paths; the
  proposal table's remaining role (rationale/undo) must stay coherent.
- **Confidence floors are guesses.** 0.5 for object keywords and 1.23 match
  distance are starting points; expose them as constants and revisit against real
  dogfood, not synthetic tuning.
- **Backfill of existing AI-derivable labels is out of scope.** Existing catalogs
  keep their current (all-`user`) labels; promotion applies going forward as
  assets are (re-)evaluated. If a one-time backfill is wanted, it is a separate
  follow-on.

## Out of scope (later sub-projects)

- Prominent unconfirmed-people review surface + People-as-a-library-view.
- The ✨ tag/inspector chrome details and confirm/remove affordance layout.
- Global filter persistence across views and modes.
- The "Text found: Signal: Face count" filter-chip fix.
