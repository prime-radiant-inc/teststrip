# People Surfacing — Design Spec

**Date:** 2026-07-14
**Sub-project:** A (of the People/identity follow-ups; sub-project B = Contacts
seeding, designed separately).

## Goal

Two small, additive surfacings of already-captured person data in the
just-shipped People-as-a-Library-view work:

1. **Proposed photos in a person's view.** When the library is filtered to a
   single person (`person:"Name"`), show — below the confirmed photos — a
   separate **Proposed** section of AI-suggested-but-unconfirmed photos, each
   with inline confirm (✓) / reject (✗) actions.
2. **Key photo on person cards.** The confirmed-people list draws a synthetic
   gradient circle per person; replace it with a crop of the person's best
   confirmed face.

Both read data that already exists (`person_faces.origin`, `face_observations`)
— no new capture, no worker changes.

## Background (current state, grounded)

- The `person:"Name"` filter compiles to an `EXISTS` over **`person_assets`**
  (the confirmed join table), matched by `people.name COLLATE NOCASE`, with no
  `origin` filter — `CatalogRepository.compileClauses` `.person` case,
  `Sources/TeststripCore/Catalog/CatalogRepository.swift:2671-2685`.
- AI face proposals are written **only** as `person_faces` rows with
  `origin='ai'` and **no** `person_assets` link — `insertAIFace`,
  `CatalogRepository.swift:1276-1288`. So proposed matches are structurally
  excluded from the `person:` filter today.
- Confirming a suggested face promotes `origin='ai'→'user'` and writes the
  `person_assets` link — `confirmFace`, `CatalogRepository.swift:1293-1310`.
- Rejecting a suggested face records the sticky negative signal
  `rejected_face_people` so promotion never resurrects it (the mechanism the
  merged face-group review reuses).
- The person-filtered grid is the flat `.grid` mode — `assetGrid`, a single
  `LazyVGrid` over `model.assets` inside a `VStack`/`ScrollView`,
  `Sources/TeststripApp/LibraryGridView.swift:2347-2428`. There is **no**
  "single-person view" flag; the only signal is that the parsed query is
  exactly one `.person(name)` predicate.
- Person cards draw `Circle().fill(avatarGradient(seed: person.id, …))` — no
  face — `namedPersonCard`, `Sources/TeststripApp/PeopleView.swift:421-464`
  (gradient at `:423-424`). `NamedPersonPresentation`
  (`PeopleView.swift:819-833`) carries only `id`/`name`/`assetCount`.
- `FaceCropAvatar(previewURL:boundingBox:diameter:)`
  (`Sources/TeststripApp/FaceCropAvatar.swift:55`) already renders a face crop
  and is used by the suggestion card (`PeopleView.swift:317-319`).
- Face embeddings/quality/box live in `face_observations.face_json` as
  `FaceObservationPayload{boundingBox, captureQuality: Double?, embedding}`
  (`CatalogRepository.swift:3306-3310`). `captureQuality` is **optional**.
- The active face provenance is `provider:"face-recognition",
  model:"auraface-v1", version:"1", settingsHash:"default"`
  (`Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift:195-200`);
  face reads that touch `face_observations` are provenance-scoped exactly as
  `confirmedFaceEmbeddingsByPerson` (`CatalogRepository.swift:1234-1258`) and
  `unassignedFaceObservations` (`:1198-1232`) are.

## Feature 1 — Proposed section in a person's photos

### Trigger

A proposed set is computed **only** when the active query, as parsed by
`currentLibraryQuery()` (`AppModel.swift:10837`), is exactly one predicate and
it is `.person(name)`. Any other query (extra predicates, no predicates) clears
the proposed set. This is re-evaluated on every `reload()`.

### New repository read

Add a read that returns, for a person **name**, each proposed asset and the
person's proposed face index(es) on it — i.e. faces the person has with
`origin='ai'` where the asset is not already in that person's confirmed
`person_assets` (modeled on the `unassignedFaceObservations` anti-join,
`CatalogRepository.swift:1198-1232`):

```sql
SELECT pf.person_id, pf.asset_id, pf.face_index
FROM person_faces pf
JOIN people ON people.id = pf.person_id AND people.name = ? COLLATE NOCASE
WHERE pf.origin = 'ai'
  AND NOT EXISTS (
      SELECT 1 FROM person_assets pa
      WHERE pa.person_id = pf.person_id AND pa.asset_id = pf.asset_id
  )
ORDER BY pf.asset_id, pf.face_index
```

`person_id` is selected (not just filtered by name) because the **reject**
action records `rejected_face_people`, which is keyed by person — and two
people can share a name, in which case the name filter surfaces both. The
return value groups by asset, carrying each cell's `(personID, [faceIndex])`
(e.g. `[(assetID, personID, [faceIndex])]`), in a stable order, so the UI
renders one cell per asset and each ✓/✗ acts on exactly the right person's
faces. The confirmed-asset loader already exists (`AppModel` uses `assets(ids:)`
in `reload()`), so proposed asset ids feed the same loader.

### AppModel state + reload wiring

- Add `proposedAssets: [Asset]` (published) and enough context to drive the
  actions (the per-asset face indices and the person name/id). Keep it a
  **separate** array — never merged into `model.assets`.
- In `reload()` (`AppModel.swift:10080-10121`), after building the query:
  when the lone-`.person` trigger holds, run the new read, load the assets,
  and set `proposedAssets`; otherwise clear it.

### UI — the Proposed section and its actionable cells

- In `assetGrid`'s existing `VStack` (`LibraryGridView.swift:2348`), after the
  confirmed `LazyVGrid`, render — only when `proposedAssets` is non-empty — a
  titled section following the Timeline `daySection` pattern
  (`LibraryGridView.swift:7460-7506`): a header (**"✨ Proposed"** + count)
  and a second `LazyVGrid` of cells over `proposedAssets`. Because `assetGrid`
  is already inside one `ScrollView`, the section scrolls with the confirmed
  grid for free.
- Each proposed cell is an `AssetGridCell` with **two corner overlay buttons in
  opposite corners** (so they can't be misclicked):
  - **✗ (reject)** — top-leading.
  - **✓ (confirm)** — bottom-trailing.
  - (Corner arrangement is a stated default, trivially flippable.)

### Confirm / reject semantics + provenance

- **✓ confirm** promotes **all** of the person's `origin='ai'` faces on that
  asset to `origin='user'` and writes the `person_assets` link — reusing the
  sub-project-1 confirm path (`confirmFace`, `CatalogRepository.swift:1293`;
  AppModel wrapper `confirmAIFace`). Result: `origin='user'`, a
  sidecar-eligible confirmation, and the photo moves to the confirmed grid.
- **✗ reject** records the sticky `rejected_face_people` negative for the
  person's suggested face(s) on that asset — reusing the sub-project-1 sticky
  reject path (`rejectFaceSuggestion`) — so re-running recognition never
  resurrects it. The photo leaves Proposed permanently.
- After either action, `reload()` refreshes both sections (confirm removes the
  asset from Proposed and adds it to the confirmed grid; reject removes it from
  Proposed).

### Invariant compliance (auto-apply with provenance)

- Proposed assets live in their **own array**, never in `model.assets`, so
  Picks, export, and destructive operations — which read `model.assets` / the
  confirmed `person_assets` set — never see tentative matches. No new gating is
  required; separation is by construction.
- ✓/✗ are explicit user gestures. ✓ produces `origin='user'` (confirmed,
  sidecar-eligible per the identity rules — identity itself has no XMP field,
  but the confirmation flips provenance). ✗ records the sticky removal. Neither
  is auto-applied.

## Feature 2 — Key photo on person cards

### New repository read

Add a per-person read that returns the person's **highest-`captureQuality`
confirmed face** as `(personID, assetID, faceIndex, boundingBox)`. It is a
near-clone of `confirmedFaceEmbeddingsByPerson`
(`CatalogRepository.swift:1234-1258`) — same `person_faces.origin='user' ⨝
face_observations` join, same provenance scoping — but the SELECT also carries
`person_faces.asset_id`/`face_index`, decodes the full `FaceObservationPayload`
(not just `embedding`), and picks the max `captureQuality` per person. Because
`captureQuality` is `Double?`, treat `NULL` as lowest when ranking (a person
whose only confirmed faces have `NULL` quality still gets a key face —
deterministically the first by the existing order).

### AppModel surface + presentation

- Surface the key faces on `AppModel`, keyed by person id, loaded alongside
  `catalogPeople`.
- Extend `NamedPersonPresentation` (`PeopleView.swift:819-833`) with
  `keyFaceAssetID: AssetID?` and `keyFaceBoundingBox: FaceBoundingBox?`.

### UI — face crop with gradient fallback

- In `namedPersonCard` (`PeopleView.swift:421-464`), replace the gradient
  `Circle` (`:423-424`) with `FaceCropAvatar(previewURL: model.previewURL(for:
  keyFaceAssetID, levels: [.grid, .medium, .micro]), boundingBox:
  keyFaceBoundingBox)` when a key face exists.
- **Fallback:** people confirmed via whole-asset assignment (`assignAssets`,
  no `person_faces` row) have no derivable key face — they keep the existing
  gradient circle. So: face crop when a confirmed face row exists, gradient
  otherwise. (`FaceCropAvatar` also needs a graceful no-preview state — an
  uncached preview should not blank the card; fall back to the gradient there
  too.)

## Non-goals (YAGNI)

- No user-pickable key photo (best confirmed face is derived; a manual override
  is a later enhancement).
- No key-photo persistence column on `people` — the key face is derived at read
  time. (Add a column only if the derivation later proves too slow, which it
  is not at current catalog sizes.)
- No heuristic key face for whole-asset-confirmed people (which face is theirs
  is unknown without a `person_faces` link) — gradient fallback instead.
- No changes to the worker, the embedding model, or capture.
- No per-cell ✨ badge in the Proposed section — the section header is the
  proposed signal.

## Testing

- **Repository tests.** The proposed anti-join: returns an `origin='ai'` face's
  asset for the person; excludes an asset once it has a `person_assets` link;
  excludes a `rejected_face_people` face; matches by name case-insensitively.
  The key-face read: picks the max-`captureQuality` confirmed face; handles a
  person with only `NULL`-quality faces; returns nothing for a person with only
  whole-asset (no `person_faces`) confirmations.
- **Presentation tests.** A lone `.person` query populates `proposedAssets`; a
  multi-predicate or empty query clears it. `NamedPersonPresentation` carries
  the key face when present and nil (→ gradient) when absent.
- **End-to-end scenario card.** Seed a person with one confirmed face and one
  AI-proposed face on a different asset. Open the person (`person:` filter):
  assert the confirmed grid shows the confirmed asset and the **Proposed**
  section shows the proposed asset. Click ✓ on the proposed cell → assert (via
  catalog ground truth) a `person_assets` row and `person_faces.origin='user'`
  for that asset, and that the photo moved to the confirmed grid. In a second
  case, click ✗ → assert a `rejected_face_people` row and that the photo is
  gone from Proposed and does not reappear after a recognition re-run. Assert
  the named person renders a face crop, and a whole-asset-only person renders
  the gradient.

## Open decisions (resolved)

- Proposed presentation: **separate section**, not per-cell ✨ badge.
- Proposed cells: **actionable** — ✓ confirm (bottom-trailing) / ✗ reject
  (top-leading), opposite corners.
- Key photo: **best confirmed face, face-cropped**; gradient fallback for
  whole-asset-confirmed people.
