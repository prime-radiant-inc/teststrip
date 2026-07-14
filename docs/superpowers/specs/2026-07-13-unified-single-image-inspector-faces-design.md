# Unified single-image view: inspector (stacked sections) + per-photo face naming

_Date: 2026-07-13_

## Problem

Opening a photo from the Library grid drops you into the **Cull** loupe, and
`WorkspaceChromePolicy.showsInspector` is false for Cull — so the inspector /
"AI sidebar" (which exists for Library, with Info/Describe/AI tabs) is never
shown on the single image. You cannot, on one photo, see its AI categorization
and human tags together, and there is no way to **see the detected faces or
edit who they are** — no way to name an unnamed face, remove a name, or tell
the system a face is *not* the person it guessed.

We want: opening a photo lands in a single-image view with the inspector
available; the inspector is a vertical stack of sections (**Info, Describe, AI,
People**); and the **People** section shows the photo's faces — as boxes on the
image tied to a crop list — where you add / remove / confirm / correct names,
with rejections that stick.

## What already exists (this is mostly UI + one new store)

- **The loupe is already one shared view.** `loupeStage(for:)` and the cull
  stage `body` in `LibraryGridView.swift` render both the Library loupe
  (`.libraryLoupe`) and the Cull loupe (`.loupe`), gated by
  `presentation.showsCullChrome`. There is no fork to merge.
- **The inspector exists**: `InspectorView` (1398 lines) with `InspectorTab`
  = `.info` ("Info"), `.describe` ("Describe"), `.ai` ("AI"), presented at the
  app level (`main.swift`) gated by `isInspectorVisible &&
  WorkspaceChromePolicy.showsInspector(selectedWorkspace)` — false for Cull.
- **The face data + repo layer exists**: `face_observations` (per-face
  `FaceBoundingBox {x,y,w,h}` + embedding + quality), face-level `person_faces
  (person_id, asset_id, face_index)`, `people`, `FaceID`,
  `faceObservations(assetID:)`, `assignFaces(faceIDs:toPersonID:)`,
  `dismissFaces(faceIDs:)`, `dismissFaceAssets`, and a suggestion surface:
  `PeopleFaceSuggestion` (`.matchExisting(personID,personName)` / `.newPerson`),
  `refreshPeopleFaceSuggestions()`, `confirmPeopleFaceSuggestion(...)`,
  `dismissPeopleFaceSuggestion(...)`, computed by the static
  `AppModel.peopleFaceSuggestions(...)`.
- The **People workspace** (`PeopleView`) is a separate cross-catalog grouping /
  naming queue — this feature adds a **per-photo** faces surface in the
  inspector, not a change to that workspace.

So: the container is small (loupe already shared), the inspector restructure and
faces UI are the bulk, and the negative-suggestion store is the one new data
piece.

## Decisions (settled during brainstorming)

- **Unified single-image view**: the inspector coexists with cull chrome, so a
  single-image view is `[stack rail | loupe | inspector]`; clicking a photo
  already lands here. Cull gestures keep working.
- **Inspector = stacked sections, not tabs**: Info, Describe, AI, **People**
  render as a vertical scroll of sections (retire the tab switcher).
- **Faces = boxes on the photo + a crop list** in the People section. Boxes tie
  names to positions; the list is the edit surface. Hover/select links the two.
- **Edit gestures per face**: add name (assign to an existing person or a new
  one), remove name (un-assign a confirmed face), confirm a guess, and
  **"not them"** (reject a guess).
- **Reject = clear + remember**: "not them" clears the guess AND records that
  this face is not that person, and the suggestion computation consults that
  record so recognition stops re-suggesting them here. This is the one new data
  store.
- **Confirm-before-write**: guesses stay provisional; only an explicit gesture
  writes `person_faces` or a negative record. Nothing is written by merely
  viewing the photo or opening the inspector.

## Goals

- Opening a photo shows the single-image view with the inspector available
  (Info / Describe / AI / People stacked).
- The People section shows every detected face with its state (confirmed /
  guessed / unnamed) and lets you add, remove, confirm, and reject names.
- Rejecting a guess ("not them") stops that person from being re-suggested for
  that face.
- Confirm-before-write and non-destructive invariants hold: viewing writes
  nothing; only explicit gestures write.

## Non-goals

- No change to the People workspace's cross-catalog grouping/naming queue
  (`PeopleView`), or to how faces are detected / embedded / clustered.
- No change to the stack rail, filmstrip, or cull gestures beyond letting the
  inspector coexist.
- No re-training of the recognition model; the negative store only filters
  suggestions, it doesn't feed embeddings.
- Not a redesign of Info/Describe/AI content — those sections render their
  existing elements, just stacked instead of tabbed.

## Architecture

### 1. Container — inspector on the single-image view

`WorkspaceChromePolicy.showsInspector` gates the app-level inspector. Allow the
inspector in the single-image / cull context (so `showsInspector` is true when a
single photo is up, Library or Cull), and place the inspector column to the
**right** of the loupe stage — the loupe stage HStack becomes
`[stack rail | loupe | inspector]` (the stack rail is left, added by the prior
feature; the inspector is the right column). Cull chrome (rail, filmstrip, HUD)
and the inspector coexist. `⌘I` toggles the inspector as today.

### 2. Inspector — stacked sections

Restructure `InspectorView` from a tab switcher into a **vertical `ScrollView`
of sections**: Info, Describe, AI, People, each rendered inline under a section
header (reuse each tab's existing element set via `InspectorTabPresentation`).
Retire the `InspectorTab` tab-selection chrome and `model.inspectorTab`
switching; keep the per-tab element definitions as the per-section content.
Menu/keyboard that selected a tab now scrolls to / focuses that section.

### 3. People section — boxes + crop list

- **Model**: a new pure presentation, `PhotoFacesPresentation`, computed from
  `faceObservations(assetID:)`, `person_faces` for the asset, and
  `peopleFaceSuggestions` scoped to the asset. It yields, per detected face:
  the `FaceBoundingBox`, a crop source, and a state — `confirmed(personName)`,
  `suggested(personName)`, or `unnamed` — plus the available actions.
- **Overlay**: draw each face's `FaceBoundingBox` over the loupe image
  (normalized coords → image frame), labeled with the name/guess; hovering or
  selecting a box highlights the matching list row and vice versa.
- **List**: in the People inspector section, one row per face — a crop
  thumbnail, its state, and controls: **Add name** (a person picker: existing
  person or create new → `assignFaces`), **Confirm** (a guess → `assignFaces`),
  **Remove** (a confirmed face → new `unassignFaces`), and **Not <name>**
  (reject a guess → clear + negative record).

### 4. Face edit gestures (AppModel)

Add per-photo, per-face methods that wrap the repo, all writing only on the
explicit gesture:
- `nameFace(_ faceID:, personID:)` / `nameFace(_ faceID:, newPersonName:)` →
  `assignFaces([faceID], toPersonID:)` (create the person first for a new name).
- `removeFacePerson(_ faceID:)` → new `CatalogRepository.unassignFaces(_ faceIDs:)`
  (delete the `person_faces` rows).
- `confirmFaceSuggestion(...)` → the existing confirm path scoped to one face.
- `rejectFaceSuggestion(_ faceID:, personID:)` → write a negative record (below)
  and refresh suggestions.

### 5. Negative-suggestion store (new data)

- New table `rejected_face_people (asset_id TEXT, face_index INTEGER, person_id
  TEXT, created_at REAL, PRIMARY KEY (asset_id, face_index, person_id))` via a
  `CatalogMigrations` addition, with repo methods `recordRejectedFacePerson(...)`
  and `rejectedFacePeople(...)`.
- `AppModel.peopleFaceSuggestions(...)` (the suggestion computation) consults it:
  a `(face, person)` pair that has a rejection is never proposed. Confirming a
  face for a person that was previously rejected clears/overrides the rejection
  (an explicit positive beats a prior negative).

## Data flow

Selected asset → `PhotoFacesPresentation` (faces + person_faces + suggestions −
rejections) → the People inspector section + the loupe box overlay. A gesture
(name / remove / confirm / reject) calls the AppModel method → repo write →
suggestions refresh → presentation recomputes → overlay + list update. No
worker/queue involvement; recognition/embedding is unchanged.

## Confirm-before-write / non-destructive

- Opening the photo, showing boxes, and displaying guesses write nothing —
  asserted in tests (nothing in `person_faces` / `rejected_face_people` before a
  gesture).
- Original bytes untouched; face edits are catalog-only (no sidecar changes,
  since faces aren't mirrored to XMP in this feature's scope).

## Testing

- **Unit** — `PhotoFacesPresentation` (correct per-face state from
  observations + person_faces + suggestions − rejections; unnamed/guessed/
  confirmed; box coords). Repo: `unassignFaces` removes only the targeted
  `person_faces` rows; `recordRejectedFacePerson` + suggestion exclusion (a
  rejected pair is never suggested; a later confirm overrides). Inspector
  stacked-section presentation renders all four sections. Confirm-before-write:
  viewing writes nothing.
- **E2E scenario card (VM)** — open a photo → single-image view shows the
  inspector with Info/Describe/AI/People stacked; the People section lists the
  faces with boxes on the image; add a name to an unnamed face (assert
  `person_faces` row appears only after the gesture); reject a guess ("not
  <name>") and assert the guess clears, a `rejected_face_people` row appears,
  and re-running suggestions no longer proposes that person for that face;
  remove a confirmed name and assert the row is gone. Re-assert
  confirm-before-write (no writes before gestures).

## Risks and open items

- **Inspector coexisting with cull chrome width**: `[stack rail | loupe |
  inspector]` plus the filmstrip must fit the window floors
  (`WorkspaceChromePolicy` min widths); confirm the loupe doesn't squeeze below
  its floor, and decide collapse order (sidebar/inspector before content).
- **Box-overlay coordinate mapping**: `FaceBoundingBox` is normalized; map to
  the *displayed* image frame (which is aspect-fit within the loupe), not the
  raw view bounds — get orientation/letterboxing right.
- **Retiring the tab switcher** touches menu/keyboard coverage
  (`MenuCoveragePresentation`, the `1/2/3` tab key-equivalents) and their tests —
  they become scroll-to-section.
- **New-person creation** from the face list needs a name-entry affordance
  consistent with the People workspace's naming (reuse its person-create path).
- **Suggestion scoping**: the existing `peopleFaceSuggestions` is catalog-wide
  (the People queue); scoping/filtering it to one asset for the per-photo
  section must not change the People workspace's behavior.

## Out of scope

- People-workspace grouping redesign; face detection/embedding/clustering
  changes; XMP face regions; model retraining; multi-select batch face ops
  across photos.
