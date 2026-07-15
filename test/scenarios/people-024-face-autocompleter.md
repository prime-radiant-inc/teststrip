# people-024-face-autocompleter: face-box name pill autocompleter and inspector people autocompleter

**What this covers**: the face autocompleter sub-project's two naming surfaces on
`feat/person-autocompleter` — the loupe's face-box pill (`FaceBoxOverlayView`,
hover-only, `.popover`-hosted `PersonAutocompleteField`) and the inspector
People section's "Add name" button (`PhotoFacesSectionView`, same popover).
Exercises: assigning a genuinely unnamed face via the pill's ranked-candidate
list, removing a **confirmed** face via the pill's ✕ (plain unassign), removing
a **suggested** (`origin='ai'`) face via the same ✕ (the sticky-reject path —
`rejected_face_people`), and creating a brand-new person from the inspector's
autocompleter's `Create "..."` row.

Source read at authoring time (cite these, not anything else):
`Sources/TeststripApp/FaceBoxOverlayView.swift`,
`Sources/TeststripApp/PhotoFacesSectionView.swift`,
`Sources/TeststripApp/PhotoFacesPresentation.swift`,
`Sources/TeststripApp/PersonAutocompleteField.swift`,
`Sources/TeststripApp/AppModel.swift` (`rankedPersonCandidates(forFace:)`,
`nameFace`, `removeFacePerson`, `rejectFaceSuggestion`, `promoteFaceMatches`),
`Sources/TeststripCore/Catalog/CatalogRepository.swift` (`assignFaces`,
`unassignFaces`, `insertAIFace`, `recordRejectedFacePerson`),
`Sources/TeststripCore/People/PersonCandidateRanker.swift`,
`script/ax_drive.sh`.

## Pre-state

A freshly built, isolated app instance seeded with real face photos (VM +
AuraFace), built up to a concrete fixture: one person ("John Glenn") confirmed
with a face-level assignment (so a centroid exists for ranking), one other
same-person face left as an `origin='ai'` **suggestion** against that centroid
(for the sticky-reject leg), and two faces left genuinely **unnamed** — no
`person_faces` row at all — for the assign-via-pill and create-new-person
legs. Construction mirrors `people-020-ai-label-provenance.md`'s §3 and
`people-022-proposed-and-key-photo.md`'s Pre-state almost exactly, except the
person-creation gesture below uses the **current** popover autocompleter, not
the deleted `Menu`/"New person…"/"Create Person" sheet those two cards used.

```bash
ROOT_DIR="$(git rev-parse --show-toplevel)"
./script/download_face_model.sh   # AuraFace-v1 — see Sharp edges: download may fail (dev-008 gap)
script/vm_scenario_run.sh sync faces
script/vm_scenario_run.sh launch faces   # prints "launched 'faces' fresh at $FRESH" — capture $FRESH
script/vm_scenario_run.sh ax wait-vended Teststrip
# ground truth via: script/vm_scenario_run.sh sql faces "..."
```

`--faces` seeds `sample-data/photos/faces` (11 real JPEGs of Glenn ×4/Ride
×4/Armstrong ×2/Aldrin ×1, per `sample-data/faces.tsv`) via a plain folder
import — nothing is pre-flagged/pre-rated/pre-confirmed. Glenn's four files:
`commons-glenn-official.jpg`, `commons-glenn-1962.jpg`,
`commons-glenn-senator.jpg`, `commons-glenn-senator-portrait.jpg` (the last is
a spare, unused unless a clustering retry is needed below).

1. **Evaluate everything** so face detection runs before any person exists
   (this matters: `promoteFaceMatches` only proposes AI matches against
   **confirmed** centroids, and no person exists yet, so this pass leaves
   every one of the 11 assets with zero `person_faces` rows):
   ```bash
   script/vm_scenario_run.sh ax wait-vended Teststrip
   # ⌘2 Library — confirm all 11 thumbnails visible
   script/vm_scenario_run.sh ax press --role AXMenuItem --label "Evaluate Visible"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required — if 0, the AuraFace model didn't load; stop and flag, don't force the rest
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces;"        # 0 — no person exists yet, so nothing could have been proposed
   ```
2. **Create "John Glenn" via the current popover autocompleter**, confirming
   one face directly (a **user** gesture) to establish the centroid the
   ranking/promotion below need. Resolve the asset ids used throughout:
   ```bash
   GLENN_OFFICIAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg';")
   GLENN_1962_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-1962.jpg';")
   GLENN_SENATOR_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-senator.jpg';")
   RIDE_STS7_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-ride-sts7.jpg';")
   ```
   Open `commons-glenn-official.jpg` (⌘2 Library → select → double-click →
   ⌘I; the "People" section is a plain `VStack` below Info/Describe/AI, no
   scroll gate). Its one face is `.unnamed`, so the row shows an "Add name"
   button (`PhotoFacesSectionView.addNameButton`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Add name"
   script/vm_scenario_run.sh ax type --contains "Name" --text "John Glenn"
   script/vm_scenario_run.sh ax press --role AXButton --label 'Create "John Glenn"'
   ```
   (The popover's `TextField("Name", ...)` has placeholder "Name", matched by
   `--contains` per CLAUDE.md's empty-field rule; the create row is
   `Label("Create \"\(name)\"", systemImage: "plus")` wrapped in a `Button` —
   see Sharp edges on the "Name" placeholder not being unique app-wide.)
   ```bash
   JOHN_GLENN_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='John Glenn';")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE name='John Glenn';"  # 1
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"    # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_OFFICIAL_ID';"  # 1
   ```
3. **Re-evaluate one more Glenn asset alone** to fire an AI proposal against
   the new centroid — `promoteFaceMatches` only runs on a genuine
   evaluation-*completion* event, not on naming or navigation (per
   `people-020`'s step 8 caution, unchanged in this branch). Select
   `commons-glenn-1962.jpg`'s thumbnail (⌘2 Library, click), then:
   ```bash
   script/vm_scenario_run.sh ax press --role AXMenuItem --label "Evaluate Photo"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE asset_id='$GLENN_1962_ID';"); [ "$n" -gt 0 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT origin, person_id, face_index FROM person_faces WHERE asset_id='$GLENN_1962_ID';"   # origin='ai', person_id=$JOHN_GLENN_ID
   ```
   If this didn't cluster within `FaceSuggestionBuilder.defaultMaximumMatchDistance`
   (1.23), retry with `commons-glenn-senator-portrait.jpg` in place of
   `$GLENN_1962_ID` (the fourth, otherwise-unused Glenn photo) or a same-person
   Ride pair, per `people-020`'s step 9 caution — note the fixture gap rather
   than forcing a result. Capture the face index for later assertions:
   ```bash
   GLENN_1962_FACE_INDEX=$(script/vm_scenario_run.sh sql faces "SELECT face_index FROM person_faces WHERE asset_id='$GLENN_1962_ID' AND origin='ai';")
   ```
4. **Confirm the other two faces are still genuinely unnamed** — neither
   `commons-glenn-senator.jpg` nor `commons-ride-sts7.jpg` was touched by
   steps 2-3, so both should still have zero `person_faces` rows (their pill
   will read "Name…", `PhotoFaceState.unnamed`):
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_SENATOR_ID';"  # 0
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$RIDE_STS7_ID';"      # 0
   ```

This leaves: `$JOHN_GLENN_ID` confirmed with a centroid
(`$GLENN_OFFICIAL_ID`); `$GLENN_1962_ID` with an `origin='ai'` **suggested**
face against John Glenn; `$GLENN_SENATOR_ID` and `$RIDE_STS7_ID` genuinely
**unnamed** — the fixture the Steps below exercise.

## Steps

### 1. Face-box pill: assign a genuinely unnamed face

1. Open `commons-glenn-senator.jpg` on the loupe with inspector visible (⌘2
   Library → select → double-click → ⌘I).
2. Hover the face box. Per `FaceBoxOverlayView.faceBox`, hovering sets
   `model.focusedFaceID` (shared with the inspector's own hover handling),
   which renders the pill; since this face is `.unnamed`, `pillTitle` reads
   `"Name…"` (`FaceBoxOverlayView.swift:159`, `"Name\u{2026}"`).
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Name…"
   ```
   (See Sharp edges — whether a hover state can be reached at all through
   `ax_drive.sh`'s AX-action-only verbs, and whether the box's
   accessibility-collapsing wrapper hides the pill regardless, are both open
   questions pending a live pass.)
3. Clicking the pill sets `model.editingFaceID`, opening the `.popover` with
   `PersonAutocompleteField`. John Glenn is the only confirmed person, so he's
   the only ranked candidate and appears with a similarity "%" badge
   (`AppModel.rankedPersonCandidates(forFace:)` → `PersonCandidateRanker.rank`,
   using `FaceSuggestionBuilder.centroid`/`.distance`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "John Glenn"
   ```
4. Assert the assignment:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_SENATOR_ID' AND person_id='$JOHN_GLENN_ID';"  # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_SENATOR_ID';"  # 1
   ```

### 2. Face-box pill: remove the now-confirmed assignment via ✕

1. Still on `commons-glenn-senator.jpg`'s loupe, hover the same face box.
   It's now `.confirmed`, so `pillTitle` reads `"John Glenn"` (no checkmark —
   the `✓` suffix belongs only to `PhotoFaceState.displayLabel`, used for the
   box's own accessibility label and the inspector row text, not the pill),
   and a trailing ✕ button appears (`row.state.personID != nil`).
2. Click the ✕, an icon-only control targeted by AXHelp per CLAUDE.md's rule
   (`Image(systemName: "xmark.circle.fill")` + `.help("Remove this person")`,
   `FaceBoxOverlayView.swift:142-145`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Remove this person"
   ```
   For a `.confirmed` row, `removePerson` calls `model.removeFacePerson(row.faceID)`
   (`FaceBoxOverlayView.swift:163-166`) → `CatalogRepository.unassignFaces` —
   deletes the `person_faces` row outright; this is a plain unassign, not a
   sticky reject.
3. Assert:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_SENATOR_ID' AND person_id='$JOHN_GLENN_ID';"   # 0
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_SENATOR_ID';"   # 0
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM rejected_face_people WHERE asset_id='$GLENN_SENATOR_ID' AND person_id='$JOHN_GLENN_ID';"  # 0 — a confirmed-face removal is not a sticky reject
   ```

### 3. Face-box pill: remove a suggested (`origin='ai'`) assignment via ✕ — the sticky-reject leg

1. Open `commons-glenn-1962.jpg` on the loupe (inspector visible). Re-confirm
   the Pre-state fixture is still intact:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT origin, person_id FROM person_faces WHERE asset_id='$GLENN_1962_ID';"  # ai, $JOHN_GLENN_ID
   ```
2. Hover its face box. It's `.suggested`, so `pillTitle` reads
   `"guess: John Glenn"` (`FaceBoxOverlayView.swift:158`), and since
   `row.state.personID` is non-nil for `.suggested` too, the ✕ button also
   appears alongside it.
3. Click the ✕ (same target as Step 2):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Remove this person"
   ```
   For a `.suggested` row, `removePerson` calls
   `model.rejectFaceSuggestion(row.faceID, personID:)`
   (`FaceBoxOverlayView.swift:167-168`), which calls `unassignFaces` (deletes
   the `origin='ai'` `person_faces` row) **then**
   `recordRejectedFacePerson` (writes a `rejected_face_people` row) — the
   sticky-reject path, so recognition never re-proposes this pair.
4. Assert:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_1962_ID' AND origin='ai';"  # 0 — the ai row is deleted, not just hidden
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM rejected_face_people WHERE asset_id='$GLENN_1962_ID' AND face_index='$GLENN_1962_FACE_INDEX' AND person_id='$JOHN_GLENN_ID';"  # 1
   ```

### 4. Inspector People-section autocompleter: create a brand-new person

1. Open `commons-ride-sts7.jpg` (⌘2 Library → select → double-click → ⌘I;
   People section). Re-confirm the Pre-state fixture:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$RIDE_STS7_ID';"  # 0
   ```
   Its `.unnamed` face row renders `addNameButton` ("Add name",
   `PhotoFacesSectionView.swift:103-109`) — a plain button with no
   accessibility-collapsing wrapper (unlike the loupe pill; see Sharp edges),
   so it should be reliably AX-findable without any hover.
2. Click it:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Add name"
   ```
3. Type a brand-new name into the popover's field:
   ```bash
   script/vm_scenario_run.sh ax type --contains "Name" --text "Gus Grissom"
   ```
4. Click the create row — `Label("Create \"Gus Grissom\"", systemImage: "plus")`
   (`PersonAutocompleteField.swift:97`), wrapped in a `Button` (`rowButton`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label 'Create "Gus Grissom"'
   ```
   This calls `onCreate` → `model.nameFace(row.faceID, newPersonName: "Gus Grissom")`
   (`PhotoFacesSectionView.swift:117-120`) → `upsertPerson` + `assignFaces`.
5. Assert:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE name='Gus Grissom';"  # 1
   GUS_GRISSOM_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='Gus Grissom';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$RIDE_STS7_ID' AND person_id='$GUS_GRISSOM_ID';"  # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$GUS_GRISSOM_ID' AND asset_id='$RIDE_STS7_ID';"  # 1
   ```

## Expected

- Step 1 (pill assign): the popover lists John Glenn (with a "%" similarity
  badge) and clicking his row flips `person_faces.origin` to `user` for
  `$GLENN_SENATOR_ID` and creates a `person_assets` row. **Fails if** the pill
  never appears/opens the popover, John Glenn isn't listed, the row stays
  unassigned, or no `person_assets` row is created.
- Step 2 (pill remove, confirmed): clicking the ✕ deletes both the
  `person_faces` row and the `person_assets` row for `$GLENN_SENATOR_ID`, and
  writes **no** `rejected_face_people` row. **Fails if** either row survives,
  or a `rejected_face_people` row appears (a confirmed removal must not be
  sticky).
- Step 3 (pill remove, suggested — the sticky-reject leg, required by this
  rewrite): clicking the ✕ on a `.suggested` face deletes the `origin='ai'`
  `person_faces` row **and** writes a `rejected_face_people` row for
  `($GLENN_1962_ID, $GLENN_1962_FACE_INDEX, $JOHN_GLENN_ID)`. **Fails if** the
  `ai` row survives (reject only hid the pill instead of clearing the
  suggestion), or the `rejected_face_people` row is missing (the reject isn't
  sticky, so recognition could re-propose the same wrong match later).
- Step 4 (inspector, new person): a new `people` row is created with
  `name='Gus Grissom'`, a `person_faces` row links `$RIDE_STS7_ID` to it with
  `origin='user'`, and a `person_assets` row exists. **Fails if** the new
  person isn't created, the face assignment fails, or `origin` is wrong.

## Cleanup

Quit the launched instance; discard the VM run directory
(`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state) created
for this run, per `test/scenarios/README.md`'s isolated-launch teardown.
Touch no real catalog.

## Sharp edges

- **The pill only appears on hover, and driving that hover purely through
  `ax_drive.sh` is unproven.** `facePill` only exists in the view tree when
  `isFocused || isEditing` (`FaceBoxOverlayView.swift:82-88`), and
  `isFocused` is set by a real SwiftUI `.onHover` callback
  (`FaceBoxOverlayView.swift:91-97`). Reading `script/ax_drive.sh` end to
  end: its plain `press`/`find`/`wait` verbs act purely through
  `AXUIElementPerformAction`/AX-tree reads and never move the actual mouse
  cursor; only its `--button right` path calls `CGWarpMouseCursorPosition` +
  posts a real `mouseMoved` event (immediately followed by a right-click) —
  there is no bare "move/hover" verb. Whether that right-click path's cursor
  warp is enough to trigger `.onHover` (and whether the resulting context
  menu can be dismissed cleanly first) is untested; treat Steps 1-3's hover
  instruction as the *intent*, not a proven recipe, until a live pass checks
  it. (Both the inspector's People rows and the loupe's face box call
  `model.focusedFaceID = row.faceID` on hover — same shared state — so if
  hover-driving one surface is solved, it solves both.)
- **The face box's own accessibility wrapper may hide the pill/✕ regardless
  of hover.** `FaceBoxOverlayView.faceBox` applies
  `.accessibilityElement(children: .ignore)` +
  `.accessibilityLabel(row.state.displayLabel)` unconditionally to the whole
  box (`FaceBoxOverlayView.swift:98-99`), which per SwiftUI's accessibility
  model collapses the box's entire subtree — including the conditionally
  rendered pill `Button` and ✕ `Button` — into one opaque element exposing
  only that single label. If so, `ax_drive.sh find --role AXButton --label
  "Name…"` (or `--help "Remove this person"`) may never match anything inside
  a face box, hover or not. This is a real, source-grounded risk, not settled
  by reading alone — confirm live (e.g.
  `script/vm_scenario_run.sh ax find --role AXButton` scoped near the loupe)
  before trusting Steps 1-3's AX commands as written; if it's
  confirmed, driving these two steps needs either a product-code change
  (relaxing the `.ignore`) or a coordinate-based click, neither of which this
  card invents.
- **The inspector's "Add name"/create-row buttons carry none of the above
  risk** — `PhotoFacesSectionView` has no accessibility-collapsing wrapper,
  so Step 4 should be materially more reliable to drive than Steps 1-3.
- **The popover's `TextField` placeholder ("Name") is not unique app-wide.**
  `LibraryGridView.swift` (culling-session-name, rename fields) and
  `SidebarView.swift` (rename fields) also use `TextField("Name", ...)`. They
  should not be mounted while this card's popover is open, but if
  `ax type --contains "Name"` ever lands in the wrong field, sanity-check
  with `ax find --contains "Name"` first to see how many fields matched.
- **AuraFace gating.** Steps 1-3 need the AuraFace embedder present
  (`download_face_model.sh`); if it's missing, `face_observations` stays
  empty and the whole card is blocked at Pre-state step 1 — stop and flag
  per `dev-008-sample-downloads.md`'s manifest-gap note, don't force it.
- **Clustering isn't guaranteed.** Pre-state step 3's AI proposal depends on
  `commons-glenn-1962.jpg` actually landing within
  `FaceSuggestionBuilder.defaultMaximumMatchDistance` (1.23) of
  `commons-glenn-official.jpg`'s centroid — retry with the spare Glenn photo
  or a Ride pair per the inline fallback note before concluding promotion is
  broken.
- **Idle-wedge / keep-warm**: every wait above (evaluation, AI-proposal
  polling) needs the app kept frontmost — re-assert via
  `script/vm_scenario_run.sh ax wait-vended Teststrip` on every poll, per
  CLAUDE.md and `script/verify_people_clustering.sh`'s reference pattern.

## Run status

NOT RUN — authored 2026-07-15 against `feat/person-autocompleter`, rewritten
after review rejected the prior version for describing UI this branch deleted
(the old `Menu`/"New person…"/"Create Person" sheet) and for citing source
paths and methods that do not exist in this tree. Every label, AX role/help
string, file path, and method name above was re-verified by reading the
actual current-tree source listed under "Source" before writing this card.
Pending live execution in the Tart VM with the AuraFace model present
(`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a
human-triggered step separate from authoring this card.
