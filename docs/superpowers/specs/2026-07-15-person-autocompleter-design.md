# Person Autocompleter — Design Spec

**Date:** 2026-07-15
**Sub-project:** Person-assignment UX (a follow-up after the People-surfacing and
Contacts-seeding sub-projects merged).

## Goal

Replace every "select-a-person + New person" naming flow with one reusable
person-name autocompleter whose suggestions are **ordered by face-similarity %**
(embedding distance to the target face) rather than alphabetically, and make the
per-photo **face-box overlay** support assigning a person, removing the current
person, and picking another via that autocompleter.

## Background (grounded)

- **The face-box overlay** (`Sources/TeststripApp/FaceBoxOverlayView.swift`)
  draws one box per `PhotoFaceRow` over the loupe image
  (`LoupeZoomView.swift:276`), showing `row.state.displayLabel` and reacting to
  **hover** (`model.focusedFaceID`). It has no click/assign/remove — the file's
  own header comment flags assign/remove as "a deliberate follow-up." Each
  `PhotoFaceRow` carries `faceID`, `boundingBox`, and `state` (personID + name +
  confirmed/suggested/unnamed) but **not the embedding**.
- **Four naming surfaces** exist, all to be unified:
  1. Inspector per-photo faces — `PhotoFacesSectionView.addNameMenu` (a `Menu`
     of every `catalogPeople` + "New person…") + `newPersonNameSheet`.
  2. People "Name selection" — `PeopleView.nameSelectionSheet` →
     `confirmSelectedAssetsAsPerson(named:)` (whole-asset, no face embedding).
  3. People "Name Face Group" — `PeopleView.nameSuggestionSheet` →
     `confirmPeopleFaceSuggestion(_:personName:)`.
  4. Face-group review — `FaceGroupReviewView.namingSheet` → same confirm.
  Surfaces 2–4 are "type-a-new-name" sheets (`SheetScaffold` + a `TextField` +
  "Create Person"); only surface 1 lets you pick an existing person, via an
  unranked `Menu`.
- **Assign/remove operations** (`AppModel`): `nameFace(_:personID:)` (assign to
  existing → `assignFaces`, `origin='user'`), `nameFace(_:newPersonName:)`
  (create → `upsertPerson` + `assignFaces`), `removeFacePerson(_:)`
  (confirmed → `unassignFaces`), `rejectFaceSuggestion(_:personID:)`
  (AI → `unassignFaces` + `recordRejectedFacePerson`, sticky). A face's origin
  is carried at the UI layer by which `PhotoFaceState` case it is
  (`.confirmed`/`.suggested`/`.unnamed`).
- **Similarity primitives** (`Sources/TeststripCore/People/FaceSuggestionBuilder.swift`)
  exist but are **`private static`**: `centroid(of:)`, `distance(_:_:)`,
  `normalized(_:)`; `defaultMaximumMatchDistance = 1.23` (L2-normalized AuraFace-v1,
  `d = √(2 − 2s)`). The two embedding sources keyed by `person_id` are
  `confirmedFaceEmbeddingsByPerson(provenance:)` and
  `contactReferenceEmbeddingsByPerson()`; `refreshPeopleFaceSuggestions` already
  unions them. A face's embedding is on `CatalogFaceObservation.embedding`
  (from `faceObservations(assetID:)`) but is **dropped** before the UI layer.
  There is **no** distance→percent mapping and **no** "rank all people" method.
- **No typeahead/combobox UI exists.** Reuse `SheetScaffold`, the suggested-chip
  `ForEach` idiom, and the `PeopleKeyCaptureView`/`@FocusState` keyboard pattern.

## Components

### 1. Similarity ranker (Core + AppModel)

- Expose the three `FaceSuggestionBuilder` helpers (`centroid`, `distance`,
  `normalized`) as `public static` (no logic change), so a ranker outside the
  builder can compute a per-person centroid and its distance to a target vector.
- Add a distance→similarity-percent mapping in Core (e.g.
  `FaceSimilarity.percent(distance:) -> Int`): cosine `s = 1 − d²/2`, clamp to
  `0…1`, `Int((s*100).rounded())`.
- Add `AppModel.rankedPersonCandidates(forFace faceID: FaceID?) -> [PersonCandidate]`
  where `PersonCandidate = { id: String, name: String, similarityPercent: Int? }`:
  - Build `[personID: centroid]` from the two unioned embedding sources.
  - When `faceID` is non-nil, fetch its embedding
    (`faceObservations(assetID:).first { $0.faceIndex == faceID.faceIndex }`) and
    rank every person **with a centroid** by ascending distance, carrying the
    `similarityPercent`.
  - Names union `catalogPeople` with `contactReferenceNamesByPerson()`, so
    not-yet-materialized contacts are included.
  - People **without** a centroid — and **all** people when `faceID` is nil (the
    whole-asset "Name selection" case) — are appended ordered
    **most-recently-used first**, then alphabetical (`similarityPercent = nil`).
  - Recency is a small in-memory `recentlyNamedPersonIDs: [String]` on `AppModel`,
    pushed on every successful assign (face or whole-asset). It is session-only
    (not persisted).

### 2. `PersonAutocompleteField` (one reusable SwiftUI view)

A text field + a live results list + a **"Create '\<typed>'"** row + keyboard
navigation. Contract:
- Inputs: the ranked `[PersonCandidate]` (from the ranker), and callbacks
  `onPick(personID: String)` and `onCreate(name: String)`.
- Typing filters candidates by case-insensitive name substring, **preserving the
  ranked order** within the filtered set (empty query → full ranked list).
- Each candidate row shows its name and, when present, a subtle
  `similarityPercent` badge (e.g. "92%").
- The **"Create '\<typed>'"** row appears when the trimmed query is non-empty and
  does not exactly (case-insensitively) match an existing candidate name.
- Keyboard: ↑/↓ move a focus index over the visible rows (candidates + the
  create row), **Return** activates the focused row (`onPick`/`onCreate`), **Esc**
  cancels. Auto-focuses the text field on appear (`@FocusState`).
- Hostable both inline (inside a popover) and inside `SheetScaffold`.

### 3. Face-box overlay — the interactive name pill

- On hover/focus (`focusedFaceID`), a box's name label becomes an interactive
  **pill** (a `Button`). Clicking it opens a **popover** anchored to the box,
  hosting `PersonAutocompleteField` ranked for that face
  (`rankedPersonCandidates(forFace: row.faceID)`).
- A named face's pill carries a **✕** that removes the current person — routed by
  origin: a `.confirmed` face → `removeFacePerson`; a `.suggested` face →
  `rejectFaceSuggestion` (the same split the inspector already uses).
- An **unnamed** face shows a "Name…" pill that opens the same popover.
- Picking a candidate → `nameFace(faceID, personID:)`; creating →
  `nameFace(faceID, newPersonName:)`.
- **Box-interior click still zooms to 100%** — unchanged; only the pill is the
  new control.

### 4. Unify the four naming surfaces

`PersonAutocompleteField` replaces the naming input at each surface; each call
site keeps its own assign operation:
- **Inspector faces** (surface 1): the `addNameMenu` + `newPersonNameSheet` are
  replaced by the autocompleter (ranked for that face) → `nameFace`.
- **Name Face Group** and **Face-group review** (surfaces 3, 4): the naming sheet
  hosts the autocompleter ranked for the suggestion's representative face →
  `confirmPeopleFaceSuggestion(_:personName:)` for create, and
  `confirmPeopleFaceSuggestion(_:)` (existing person) for pick.
- **Name selection** (surface 2, whole-asset, no target face): the autocompleter
  with `faceID = nil` (recency/alpha, no %). Picking an existing person assigns
  the selected assets to that person; creating names them a new person. (Add a
  small `confirmSelectedAssetsAsPerson(existingPersonID:)` path if only the
  by-name creator exists today.)

## Provenance & invariant compliance

- Assigning a face is an explicit **user** gesture → `origin='user'`
  (`assignFaces`) — a confirmed label, never tentative; consistent with the
  auto-apply-with-provenance invariant.
- **Removing** honors the origin split: confirmed → clean `unassignFaces`
  (re-suggestible later); AI → `rejectFaceSuggestion` (records
  `rejected_face_people`, sticky).
- **Picking a not-yet-materialized contact** (`person_id = contact:<id>`, no
  `people` row) must `upsertPerson` first — gated on it being contact-backed —
  then assign, mirroring the guard sub-project B's confirm path uses. The assign
  helpers (`nameFace(_:personID:)`) must handle this (a bare `assignFaces` throws
  `notFound` for a latent id).
- No sidecar/XMP is involved (identity has no XMP field); no originals modified.

## Non-goals (YAGNI)

- No persisted recency (session-only in-memory ordering).
- No fuzzy/typo-tolerant matching — plain case-insensitive substring filter.
- No new merge UI (the person→person merge menu stays as-is).
- No similarity % for the whole-asset "Name selection" (no target face).
- No changes to recognition, embeddings, or the matcher's auto-apply behavior.

## Testing

- **Ranker unit tests:** distance ordering (nearer person ranks first);
  `%`-conversion (`s = 1 − d²/2` → clamped percent); the no-target/no-centroid
  tail ordered most-recently-used then alpha; contact-only people included and
  rankable; a person with no embedding falls to the tail.
- **Autocomplete presentation tests:** substring filter preserves ranked order;
  the "Create '…'" row appears only when the query doesn't exactly match an
  existing candidate; keyboard focus-index moves and activates the right row.
- **Assign/remove tests:** picking → `nameFace` (`origin='user'`); create → new
  person; remove on a confirmed face → `unassignFaces`; remove on an AI face →
  `rejected_face_people`; picking a latent contact materializes then assigns
  (asserted against catalog ground truth).
- **End-to-end scenario card** (VM-bound, authored): on the loupe, hover a face
  box, click its pill, pick a similarity-ranked person, confirm the assignment
  in the catalog; remove it; and drive the inspector autocompleter for the same
  face.

## Open decisions (resolved)

- **Face-box trigger:** the name pill is the interactive control (click → popover,
  ✕ removes); box-interior click still zooms.
- **Fallback order (no similarity score):** most-recently-used first, then alpha.
- Similarity **%** shown per candidate when a target face exists.
- Not-yet-materialized **contacts included** in the ranked list; picking one
  materializes the person.
