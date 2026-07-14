# inspect-010-photo-faces: the People inspector section lists per-photo faces, names/rejects/removes write only on the gesture, and boxes track the loupe image

**What this covers**: Task 9 of the unified-single-view feature. Opening a
photo now lands in the single-image Cull view, where the on-demand
inspector — reachable from every workspace as of this branch
(`WorkspaceChromePolicy.showsInspector` is unconditionally `true`) — renders
as one continuous scroll of four stacked sections: Info, Describe, AI, and
the new **People** section (`PhotoFacesSectionView`), one row per detected
face with per-face naming controls. Every gesture is confirm-before-write:
nothing lands in `person_faces`/`rejected_face_people` until the user taps
Confirm, names a person (existing or new), rejects a guess (`"Not <name>"`),
or removes a confirmed name. Detected faces are also drawn
as bounding boxes over the loupe's aspect-fitted image
(`FaceBoxOverlayView`), gated to when the inspector is open and the image
isn't 1:1-zoomed. Rejecting a guess records a `rejected_face_people`
negative so recognition stops re-proposing that person for that exact face.

Source:
- `Sources/TeststripApp/main.swift:52-57` — the inspector column, gated on
  `WorkspaceChromePolicy.showsInspector(model.selectedWorkspace)`
  (`Sources/TeststripApp/LibraryGridView.swift:7830-7834`: "all three
  workspaces show the inspector").
- `Sources/TeststripApp/AppModel.swift:4447-4451` — `toggleInspector()` is
  now a bare `isInspectorVisible.toggle()`; there is no more Cull-switches-
  to-Library special case (contrast with the pre-unification behavior
  `inspect-001-toggle-tabs.md` used to test, now reconciled).
- `Sources/TeststripApp/InspectorView.swift:552-602` — `InspectorView.body`:
  a `ScrollViewReader`/`ScrollView` over a plain `VStack` (`:557`, not
  `LazyVStack`) holding four `inspectorSection`s — Info `:558-561`,
  Describe `:563-572`, AI `:574-577`, People `:579-581` — each tagged
  `.id(InspectorTab.x)` (People has no tag/shortcut) and scrolled to via
  `proxy.scrollTo` on `model.inspectorScrollRequestToken` (`:586-590`).
  `inspectorSection` itself (a header `Text` + content + trailing
  `Divider`, not a tab) is `:607-618`; `peopleSectionBody` (`:652-654`)
  renders `PhotoFacesSectionView`.
- `Sources/TeststripApp/PhotoFacesSectionView.swift` (whole file) — one row
  per `PhotoFaceRow` (`FaceCropAvatar` + `row.state.displayLabel` +
  per-state controls): `.unnamed` → "Add name" menu (existing person or
  "New person…", `:100-118`); `.suggested` → "Confirm" (`:80-84`,
  `model.nameFace(_:personID:)`) and "Not \(name)" (`:85-89`,
  `model.rejectFaceSuggestion`); `.confirmed` → "Remove" (`:91-96`,
  `model.removeFacePerson`).
- `Sources/TeststripApp/PhotoFacesPresentation.swift` (whole file) — the
  per-face naming state: `.confirmed` (from `person_faces`) wins over
  `.suggested` (from `peopleFaceSuggestions`) for the same face index,
  falling back to `.unnamed`; `displayLabel` (`"<name> ✓"` / `"guess:
  <name>"` / `"Unnamed"`) is shared verbatim by the loupe box labels.
- `Sources/TeststripApp/AppModel.swift:3706-3751` — `nameFace(_:personID:)`
  (assigns + clears any prior rejection for that pair), `nameFace(_:newPersonName:)`
  (mints a person via `upsertPerson` then `assignFaces`), `removeFacePerson`
  (`unassignFaces`), `rejectFaceSuggestion` (`recordRejectedFacePerson`) —
  every one calls `refreshPeopleFaceSuggestions()` inline, so the People
  rows and the suggestion pipeline agree immediately with no separate
  "re-scan" gesture needed for the reject leg below.
- `Sources/TeststripCore/Catalog/CatalogRepository.swift:1185-1219`
  (`assignFaces` — writes `person_faces` **and** a `person_assets` row for
  the whole asset, `:1208-1217`), `:1238-1254`
  (`recordRejectedFacePerson`/`clearRejectedFacePerson`), `:1269-1279`
  (`unassignFaces` — deletes only `person_faces`, see Sharp edges),
  `:1116-1146` (`unassignedFaceObservations` — excludes any face whose
  **asset** already has a `person_assets` row, `:1136-1139`, not just the
  confirmed face itself: this is the "a confirmed asset drops out of the
  suggestion pipeline entirely" behavior the brief warns not to conflate
  with a same-photo confirmed+suggested test).
- `Sources/TeststripCore/Catalog/CatalogMigrations.swift:164-182` —
  `person_faces`/`rejected_face_people` schema (`PRIMARY KEY (asset_id,
  face_index)` / `(asset_id, face_index, person_id)`).
- `Sources/TeststripApp/FaceBoxOverlayView.swift` (whole file) — geometry
  in `FaceBoxOverlayGeometry.displayRect` (`:16-42`): aspect-fit scale +
  centering origin from `imagePixelSize`/`containerSize`, plus the
  bottom-left-origin → top-left-origin y-flip (`topLeftY = 1.0 - box.y -
  box.height`, `:35-38`, Vision's convention) — exactly what letterboxing
  and a resize should visually confirm.
- `Sources/TeststripApp/LoupeZoomView.swift:266-284` — `faceBoxOverlay` is
  drawn only `if WorkspaceChromePolicy.showsInspector(...), model.isInspectorVisible`,
  and only over `fittedImage` (`:249-264`), never the 1:1-zoomed view.
- `Sources/TeststripApp/main.swift:4-23` — `AppWindowLayoutMetrics`;
  `.cull`'s 800pt floor (`:15`) predates the inspector becoming reachable
  from Cull at all (Task 5), which is exactly what step 25 below checks.

## Pre-state
```bash
./script/download_face_model.sh   # AuraFace-v1 CoreML model — see Sharp edges: fetch may fail (dev-008 fixture gap)
./script/build_and_run.sh --faces
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--faces` seeds `sample-data/photos/faces` per `sample-data/faces.tsv` (same
fixture as `cull-006-zoom-and-face-zoom.md`/`people-005-queue-keyboard.md`).
Per `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift:214-237`,
`face_observations` rows (bounding boxes) are **only produced when the
AuraFace embedder is present** — without the model, `faceObservations(...)`
returns `[]` outright and this entire card (People rows, boxes, naming) has
nothing to exercise. The model download is a hard precondition, not just a
nicety for the matching/reject legs.

`face_observations` isn't populated automatically — trigger it once via
**People ▸ Scan for Faces** (gated per `people-009-scan.md`; wait for
cached previews first) and poll `face_observations`/`work_sessions` until
it settles, mirroring `script/verify_people_clustering.sh`'s warm-poll loop
(re-assert frontmost on every poll so the AX tree doesn't idle-wedge).

Use the astronaut corpus's repeat subjects — verified real by
`Tests/TeststripCoreTests/FaceCorpusGroupingTests.swift`, which asserts
Glenn's and Ride's photos cluster by identity (though it only guarantees
*some* pair within each person clusters, not which specific pair — if the
chosen pair below doesn't produce a guess live, try another same-person
pair from the manifest before concluding matching is broken):
`commons-glenn-official.jpg` and `commons-glenn-1962.jpg` (two different
photos of John Glenn) for the confirm → suggest → reject leg;
`commons-aldrin-portrait.jpg` (the corpus's only Aldrin photo — `sample-data/faces.tsv`
has exactly one `aldrin` row, so it can never pick up a stray suggestion)
for the plain add-a-name leg.

## Steps

### 1. Opening a photo lands in the single-image Cull view with the stacked inspector
1. Press ⌘2 (Library), select `commons-glenn-official.jpg`'s grid cell, and
   double-click it (`.help("Double-click to open in Loupe")`,
   `LibraryGridView.swift:2424`; the double-click gesture itself calls
   `model.openAssetInLoupe(asset.id)` at `:7082-7087`, inside the
   `assetActivation` view modifier `:7076-7113`) to open it. Assert the
   workspace is now Cull (a Cull-only control, e.g. the stack rail, is
   present) — `openAssetInLoupe` (`AppModel.swift:5355-5358`) lands on
   `selectedView == .loupe`, whose `.workspace` is `.cull`.
2. Press ⌘I. Assert the inspector column appears **without leaving Cull**
   — contrast the old special-case behavior `inspect-001-toggle-tabs.md`
   used to test, where ⌘I from Cull switched to Library first; that case
   is gone (`toggleInspector` is now a bare toggle).
3. Assert all four section headers are present simultaneously as
   `AXStaticText`: `ax_drive.sh find --role AXStaticText --label "Info"`,
   `"Describe"`, `"AI"`, `"People"`. This is a genuine simultaneous-presence
   check, not scroll-dependent — the sections live in a plain `VStack`
   (`InspectorView.swift:557`), not a `LazyVStack`, so every section's
   content is already in the AX tree regardless of scroll position (unlike
   the grid's lazy virtualization, per this README's "grid is lazily
   virtualized" sharp edge — this view doesn't have that trap).

### 2. The People section lists faces; boxes appear on the loupe
4. Assert `SELECT count(*) FROM face_observations WHERE asset_id=(SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg');`
   is >= 1 (if 0, the AuraFace model didn't load or the scan hasn't reached
   this asset yet — stop and note the fixture/timing gap rather than
   forcing the rest of the card).
5. In the People section, assert one row per detected face, each reading
   "Unnamed" (`ax_drive.sh find --role AXStaticText --contains "Unnamed"`)
   — nothing is confirmed yet.
6. Assert the loupe shows the same count of bounding boxes over the image
   (`FaceBoxOverlayView`), each also labeled "Unnamed" — the People row and
   the box share `PhotoFaceState.displayLabel` verbatim, so they can never
   silently disagree.
7. **Confirm-before-write, first checkpoint**: on a freshly seeded/reset
   catalog, `SELECT count(*) FROM person_faces;` and
   `SELECT count(*) FROM rejected_face_people;` both read 0.

### 3. Add a name to an unnamed face (new person)
8. Navigate to `commons-aldrin-portrait.jpg` (⌘2 Library → select → open in
   loupe). Confirm its People row reads "Unnamed".
9. Re-assert confirm-before-write:
   `SELECT count(*) FROM person_faces WHERE asset_id=$ALDRIN_ID;` reads 0
   (`ALDRIN_ID` from `SELECT id FROM assets WHERE original_path LIKE '%commons-aldrin-portrait.jpg';`).
10. Click "Add name" (`ax_drive.sh press --role AXButton --label "Add name"`
    — a SwiftUI `Menu` presses like a button to open its item list), then
    "New person…" (`ax_drive.sh press --role AXMenuItem --label "New person…"`).
11. **Before typing/submitting**, re-assert `person_faces` is still 0 for
    this asset — opening the sheet is routing, not writing (same
    confirm-before-write shape as `people-006-sheet-return-routing.md`).
12. Type "Buzz Aldrin" into the sheet's name field
    (`ax_drive.sh type --contains "Person name" --text "Buzz Aldrin"`) and
    press "Create Person"
    (`ax_drive.sh press --role AXButton --label "Create Person"`).
13. Assert: `person_faces` now has exactly 1 row for this asset/face index,
    joined to a `people` row named "Buzz Aldrin"; the People row now reads
    "Buzz Aldrin ✓"; the loupe box's label updates to match.

### 4. Reject a guess (rejected_face_people negative, suggestion stops)
14. Navigate to `commons-glenn-official.jpg`. Repeat steps 10-13 to name
    its face "John Glenn" via **New person…** (this both proves the
    add-a-name gesture on a second, independent face, and seeds a
    confirmed-embedding centroid for John Glenn that `refreshPeopleFaceSuggestions`
    can match other unassigned faces against).
15. Navigate to `commons-glenn-1962.jpg` — a **different photo** of the
    same person; do not reuse the just-confirmed photo (see the Sharp
    edges "do not test confirmed + suggested on the same photo" note).
    `refreshPeopleFaceSuggestions()` already ran synchronously inside the
    step-14 `nameFace` call, so re-select/re-open this photo to force
    `photoFacesPresentation` to read the refreshed state. Assert its
    People row now reads "guess: John Glenn".
16. **Confirm-before-write**: `SELECT count(*) FROM rejected_face_people;`
    reads 0 before the next click.
17. Click "Not John Glenn" (`ax_drive.sh press --role AXButton --label "Not John Glenn"`).
18. Assert: the People row flips to "Unnamed" (not back to "guess:..."); the
    loupe box label matches; `SELECT count(*) FROM rejected_face_people WHERE asset_id=$GLENN1962_ID AND person_id=$JOHN_GLENN_ID;`
    reads exactly 1; `person_faces` for this face is still 0 (a rejection
    is not a confirmation).
19. **Re-running suggestions no longer proposes Glenn for this face**:
    navigate away (⌘2 Library) and back to `commons-glenn-1962.jpg` —
    this forces `photoFacesPresentation` to recompute against the current
    `peopleFaceSuggestions` state. Assert the row still reads "Unnamed",
    not "guess: John Glenn" — `rejectedPairs` filters this exact (asset,
    face, person) tuple out of `FaceMatchSuggestion.faceIDs`
    (`AppModel.swift:3776-3786`).

### 5. Remove a confirmed name
20. Return to `commons-glenn-official.jpg` (its face is still confirmed
    "John Glenn ✓" from step 14). Click "Remove"
    (`ax_drive.sh press --role AXButton --label "Remove"`).
21. Assert: the People row flips to "Unnamed"; the loupe box label matches;
    `SELECT count(*) FROM person_faces WHERE asset_id=$GLENN_OFFICIAL_ID;`
    reads 0.
22. **Open question — do not paper over.** `unassignFaces`
    (`CatalogRepository.swift:1269-1279`) deletes only `person_faces`,
    never `person_assets`. Check
    `SELECT count(*) FROM person_assets WHERE asset_id=$GLENN_OFFICIAL_ID;`
    — expect it to **still read 1** (the row `assignFaces` wrote in step
    14 is never cleaned up by Remove). If so, this asset is permanently
    excluded from `unassignedFaceObservations` (`:1136-1139`) from this
    point on: any future unnamed face on this exact photo can never
    receive a suggested match again, and the People-workspace person
    card's asset count for "John Glenn" still includes this photo even
    though the inspector now shows no confirmed face on it. This is a real
    cross-surface inconsistency, not a scenario-authoring artifact —
    confirm it live and flag it to Jesse rather than silently excusing it.

### 6. Confirm-before-write and non-destructive, restated
23. Across steps 8-22, nothing was written to `person_faces`/
    `rejected_face_people` before its corresponding gesture (already
    asserted inline at each checkpoint) — restate as a summary check: diff
    the full table contents against the step immediately before each
    click, not just aggregate counts, to rule out a wrong-row write that
    happens to preserve the count.
24. **Non-destructive**: for every photo touched above, assert no `.xmp`
    sidecar was created (`test ! -e "$FILE.xmp"`, or diff its bytes
    before/after if one pre-existed from an earlier card) and checksum the
    original JPEG before/after (`shasum`) — bytes must be identical. Face
    naming is catalog-only; it must never create or touch a sidecar or the
    original.

### 7. 800pt Cull width holds with the inspector open
25. With the inspector open (from step 2) and a photo selected, resize the
    window to exactly 800pt wide
    (`script/vm_scenario_run.sh key 'set size of window 1 of process "Teststrip" to {800, 820}'`
    — same technique as `app-002-window-floors.md`). Assert: the stack
    rail, the loupe image, the Close-Ups panel (if visible), and the
    inspector column are all simultaneously present in the AX tree, with
    no element's frame extending past the window's right edge and no two
    elements' frames overlapping. **Fails if** anything is clipped or
    overlapped — `AppWindowLayoutMetrics.minimumWidth(.cull)` (800pt,
    `main.swift:15`) was set before the inspector became reachable from
    Cull (Task 5), so this floor has never actually had to fit all four
    panes — [stack rail | loupe | close-ups | inspector] — at once.

### 8. Box placement on a letterboxed non-square photo, and after resize
26. Pick a photo whose pixel aspect ratio clearly differs from the loupe
    viewport's (any of the astronaut portraits will do — confirm with
    `sips -g pixelWidth -g pixelHeight <file>` that width ≠ height in a
    ratio that won't exactly match the viewport, guaranteeing letterboxing
    on at least one axis). With its face box(es) visible, capture a
    screenshot (`script/capture_app_window.sh`) and visually confirm each
    box sits over the actual face in the letterboxed image — not shifted
    into the letterbox bars, and not flipped top-for-bottom (the Vision
    bottom-left-origin → SwiftUI top-left-origin flip,
    `FaceBoxOverlayGeometry.displayRect:35-38`, is exactly the kind of bug
    that would place a box near the chin/neck instead of the eyes).
27. Resize the window (per step 25's technique) to a different width.
    Capture another screenshot. Assert the box moves with the now
    differently-sized/positioned letterboxed image — same relative
    position on the face, not stuck at its old screen coordinates and not
    left pointing at empty letterbox space.

## Expected
- Step 2: inspector opens, workspace stays Cull. **Fails if** any workspace
  switch happens (the old Library-switch special case resurfacing) or the
  panel doesn't appear.
- Step 3: Info/Describe/AI/People headers all present without scrolling.
  **Fails if** any is missing, duplicated, or only reachable by scrolling
  first (would indicate the sections became lazy).
- Steps 5-6: People rows and loupe boxes agree in count and label. **Fails
  if** they disagree (a data-source split between the section and the
  overlay) or a box is missing/extra relative to `face_observations`.
- Steps 9, 11, 16: all read 0. **Fails if** anything is written before its
  gesture — assert the negative, don't soften it.
- Step 13: exactly 1 new `person_faces` row, row label updates, box label
  updates. **Fails if** the row is created before "Create Person", or the
  wrong face/asset is written.
- Step 15: a guess appears (or, if it genuinely doesn't with this pair,
  the actual measured distance is reported and a different same-person
  pair is tried rather than the step being silently skipped).
- Step 18: `rejected_face_people` gains exactly 1 row; `person_faces` for
  that face stays 0; UI reflects "Unnamed" not "guess:...". **Fails if**
  the reject also confirms, or writes for the wrong (asset, face, person)
  tuple.
- Step 19: the rejected pairing never resurfaces as a guess. **Fails if**
  it does — the negative isn't honored on recompute.
- Step 21: `person_faces` row gone, UI "Unnamed". **Fails if** the row
  survives Remove.
- Step 22: documents whatever `person_assets` actually reads — a finding
  to report, not a pass/fail gate on this card (the card's scope is the
  People-section gesture writes; the cross-table residue is an open
  product question for Jesse).
- Step 24: byte-identical originals, no new/changed `.xmp`. **Fails if**
  either changes — naming a face is catalog-only.
- Step 25: no clipping/overlap of the four panes at 800pt. **Fails if**
  any element is cut off or overlapping — this is the first time this
  floor has had to hold the inspector too.
- Steps 26-27: box tracks the actual face in the letterboxed image, both
  at rest and after a resize. **Fails if** a box sits in the letterbox
  bars, is vertically flipped, or doesn't move when the window is resized.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **This card's entire surface is gated on the AuraFace model being
  present.** `AppleVisionEvaluationProvider.faceObservations` returns `[]`
  outright when `faceEmbedder` is `nil`
  (`Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift:214-219`)
  — without `script/download_face_model.sh` having actually fetched the
  model, `face_observations` stays empty, the People section always reads
  "No faces detected", and there's nothing to name/reject/remove. Per
  `dev-008-sample-downloads.md`, the model manifest
  (`sample-data/face-recognition-model.tsv`) points at a GitHub Releases
  URL still carrying a `TODO(host): upload auraface-v1.mlpackage.zip...`
  comment in the file — confirm the download actually succeeds before
  trusting a "no faces detected" result as a product finding rather than a
  fixture gap.
- **Do not test confirmed + suggested on the same photo.** Confirming any
  face on a photo (`nameFace` → `assignFaces`) inserts a `person_assets`
  row for the **whole asset** (`CatalogRepository.swift:1208-1217`), and
  `unassignedFaceObservations` excludes any face whose asset has a
  `person_assets` row (`:1136-1139`) — not just the confirmed face index.
  So once one face on a photo is confirmed, every other face on that same
  photo is permanently excluded from the suggestion pipeline and can only
  ever show "Unnamed", never "guess: ...". This card deliberately uses
  separate photos (`commons-glenn-official.jpg` confirmed,
  `commons-glenn-1962.jpg` suggested/rejected) to exercise both states.
- **No AX hover verb.** `ax_drive.sh` only has `wait-vended`/`find`/`wait`/
  `press`/`type` (`script/ax_drive.sh:15-33`), so the row↔box
  cross-highlight on hover (`onHover` in both
  `PhotoFacesSectionView.swift:64-70` and `FaceBoxOverlayView.swift:86-92`)
  is not independently AX-drivable here; a screenshot-based mouse-move
  check would be needed to verify it live, and this card doesn't attempt
  one.
- **`refreshPeopleFaceSuggestions()` is synchronous and automatic** — every
  `nameFace`/`removeFacePerson`/`rejectFaceSuggestion` call already
  recomputes suggestions inline (`AppModel.swift:3706-3751`, each ends by
  calling it). There's no separate "re-run suggestions" gesture to drive;
  "re-running suggestions" in step 19 means re-reading the already-
  refreshed state, not triggering a new scan.
- **Face detection here is the `face_observations`/Vision+AuraFace
  pipeline, not the loupe's separate in-memory `z`/`Z` zoom-to-face
  detector** (`CoreImageFaceExpressionAnalyzer`, see
  `cull-006-zoom-and-face-zoom.md`'s Sharp edges) — the two never write to
  or read from the same store; don't cross-check counts between them.
- The 800pt-floor and letterbox/resize legs are visual/geometric and
  mostly fall back to screenshot inspection (`capture_app_window.sh`)
  rather than a clean AX text assertion — the same limitation
  `cull-006-zoom-and-face-zoom.md` documents for the loupe's zoom state.

## Run status: NOT RUN
Authored 2026-07-13 for Task 9 of the unified-single-view feature;
source-cited against the current working tree (`feat/unified-single-view`
branch) but never driven — the controller runs this live in the Tart VM per
`test/scenarios/README.md`. Needs the AuraFace model actually present
(`script/download_face_model.sh`, network-dependent — see Sharp edges)
before any step past Pre-state can produce a face to name.
