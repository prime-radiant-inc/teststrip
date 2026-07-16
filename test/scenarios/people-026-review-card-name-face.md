# people-026-review-card-name-face: name individual faces from the face-group review card

**What this covers**: Task 2's per-tile naming on the face-group review card
(`Sources/TeststripApp/FaceGroupReviewView.swift`). Before this task, each tile
in the "Is this X?" / "Who is this?" review sheet only had a ✕ to remove it
from the group; the whole remaining group was confirmed/named as one person.
Now every tile also carries a **Name** pill (`namePill`, bottom-left, mirroring
the existing ✕ at top-right) that opens the shared `PersonAutocompleteField`
popover, ranked by similarity to that specific face
(`model.rankedPersonCandidates(forFace:)`). Picking a row or creating a new
name calls `model.nameFace(_:personID:)` / `model.nameFace(_:newPersonName:)`
directly on that one face — a real catalog write (`origin='user'`), not a
staged local exclusion — which drops the face out of the unassigned pool the
review card's group is built from, so the card recomputes with one fewer
tile, exactly as a ✕ removal does. This card exercises both naming legs (an
existing, *different* person than the card's own match, and a brand-new typed
person) on two of a matched group's tiles, then confirms the remainder
one-tap to the card's own person, asserting catalog ground truth after each
step.

Source read at authoring time (cite these, not anything else):
`Sources/TeststripApp/FaceGroupReviewView.swift` (`tileGrid` `:66`-`:86`,
`name` `:166`-`:177`, `PersonCandidateSelection` `:191`-`:194`,
`FaceReviewTileView` `:199`-`:314`, `namePill` `:268`-`:296`),
`Sources/TeststripApp/FaceGroupReviewPresentation.swift` (`FaceGroupReviewPresentation`
`title`/`confirmActionTitle`/`summary`), `Sources/TeststripApp/AppModel.swift`
(`rankedPersonCandidates(forFace:)`, `nameFace(_:personID:)`,
`nameFace(_:newPersonName:)`, `refreshPeopleFaceSuggestions`,
`confirmPeopleFaceSuggestion`), `Sources/TeststripApp/PeopleView.swift`
(`faceSuggestionCard` `:332`-`:383`), `Sources/TeststripApp/PersonAutocompleteField.swift`,
`script/ax_drive.sh`, `script/vm_scenario_run.sh`.

## Pre-state

A freshly built, isolated app instance seeded with real face photos (VM +
AuraFace), built up to a fixture with **two confirmed centroids** (John Glenn,
Sally Ride) and Glenn's three remaining faces still genuinely unassigned, so
they cluster into one matched ("Is this John Glenn?") review group with three
tiles — enough to exercise both naming legs on two tiles and still confirm a
third. Construction mirrors `people-024-face-autocompleter.md`'s Pre-state
steps 1-2 almost exactly, repeated for a second person (Ride) to populate the
autocompleter's "different existing person" candidate.

```bash
ROOT_DIR="$(git rev-parse --show-toplevel)"
./script/download_face_model.sh   # AuraFace-v1 — see Sharp edges: download may fail (dev-008 gap)
script/vm_scenario_run.sh sync faces
script/vm_scenario_run.sh launch faces   # prints "launched 'faces' fresh at $FRESH" — capture $FRESH
script/vm_scenario_run.sh ax wait-vended Teststrip
```

`--faces` seeds `sample-data/photos/faces` (11 real JPEGs, per
`sample-data/faces.tsv`) via a plain folder import — nothing is
pre-flagged/pre-rated/pre-confirmed. Glenn's four files:
`commons-glenn-official.jpg`, `commons-glenn-1962.jpg`,
`commons-glenn-senator.jpg`, `commons-glenn-senator-portrait.jpg`. Ride's four:
`commons-ride-sts7.jpg`, `commons-ride-sts7-cockpit.jpg`,
`commons-ride-1984-portrait.jpg`, `commons-ride-astronautin.jpg`.

1. **Evaluate everything** so face detection runs before any person exists
   (`promoteFaceMatches` only proposes against **confirmed** centroids, and
   none exist yet, so this pass leaves all 11 assets with zero `person_faces`
   rows):
   ```bash
   # ⌘2 Library — confirm all 11 thumbnails visible
   script/vm_scenario_run.sh ax press --role AXMenuItem --label "Evaluate Visible"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required — if 0, the AuraFace model didn't load; stop and flag, don't force the rest
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces;"        # 0 — no person exists yet
   ```
2. **Resolve asset ids** for the fixture:
   ```bash
   GLENN_OFFICIAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg';")
   GLENN_1962_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-1962.jpg';")
   GLENN_SENATOR_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-senator.jpg';")
   GLENN_PORTRAIT_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-senator-portrait.jpg';")
   RIDE_STS7_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-ride-sts7.jpg';")
   ```
3. **Confirm "John Glenn" via the inspector's popover autocompleter**, naming
   one face directly (a **user** gesture) to establish the centroid the
   review group below needs. Open `commons-glenn-official.jpg` (⌘2 Library →
   select → double-click → ⌘I; its one face is `.unnamed`, showing an "Add
   name" button, `PhotoFacesSectionView.addNameButton`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Add name"
   script/vm_scenario_run.sh ax type --contains "Name" --text "John Glenn"
   script/vm_scenario_run.sh ax press --role AXButton --label 'Create "John Glenn"'
   GLENN_PERSON_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='John Glenn';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"  # user
   ```
4. **Confirm "Sally Ride" the same way**, so the autocompleter has a second
   existing person to offer — the "different existing person" leg below picks
   her, not Glenn. Open `commons-ride-sts7.jpg`:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Add name"
   script/vm_scenario_run.sh ax type --contains "Name" --text "Sally Ride"
   script/vm_scenario_run.sh ax press --role AXButton --label 'Create "Sally Ride"'
   RIDE_PERSON_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='Sally Ride';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$RIDE_STS7_ID';"  # user
   ```
5. **Confirm the fixture's three remaining Glenn faces are still genuinely
   unassigned** (none were touched by steps 3-4):
   ```bash
   for A in "$GLENN_1962_ID" "$GLENN_SENATOR_ID" "$GLENN_PORTRAIT_ID"; do
     script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$A';"  # 0 each
   done
   ```

This leaves `$GLENN_PERSON_ID` and `$RIDE_PERSON_ID` each confirmed with a
centroid, and Glenn's other three faces (`$GLENN_1962_ID`,
`$GLENN_SENATOR_ID`, `$GLENN_PORTRAIT_ID`) genuinely unassigned — close enough
to Glenn's centroid that `refreshPeopleFaceSuggestions` (called automatically
after each `nameFace`/naming-sheet confirm) should group them into one
matched review card, "Is this John Glenn?", with 3 tiles. If clustering
doesn't catch all three, see Sharp edges — proceed with however many tiles
actually appear (at least 2 are needed: one to name away, one to confirm).

## Steps

### 1. Open the "Is this John Glenn?" review card

1. ⌘2 Library → AX-press the Library sub-view toggle segment labeled
   **"People"**. `wait` for the header `AXStaticText` matching **"N people ·
   M photos with face signals"** (N ≥ 2).
2. AX-press the suggestion card whose title is **"Is this John Glenn?"**
   (help text **"Review this group before confirming John Glenn"**,
   `PeopleView.swift:365`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Review this group before confirming John Glenn"
   ```
   A review sheet opens titled "Is this John Glenn?" with a grid of large
   face tiles (`FaceReviewTileView`), each carrying a ✕ (top-right) and now a
   **Name** pill (bottom-left, `Label("Name", systemImage:
   "person.crop.circle.badge.plus")`).
3. Assert nothing was written just by opening the review (confirm-before-write
   invariant):
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$GLENN_PERSON_ID';"  # 1 (still just $GLENN_OFFICIAL_ID)
   ```

### 2. Name one tile to a *different* existing person (Sally Ride) via the autocompleter

1. Click the first tile's Name pill:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Name"
   ```
   This sets that tile's local `isNaming = true`, opening the `.popover` with
   `PersonAutocompleteField` anchored to that tile (per-tile `@State`, no
   shared-flag race — see Task 1's `people-025` card for the popover-race fix
   this deliberately avoids by using per-tile state instead of a shared
   `editingFaceID`).
2. Assert the autocompleter appears, ranked by similarity to this specific
   face — both confirmed people should be listed (Glenn nearer his own face,
   Ride further):
   ```bash
   script/vm_scenario_run.sh ax wait --role AXButton --label "Sally Ride"
   script/vm_scenario_run.sh ax find --role AXButton --label "John Glenn"   # also present — the ranked list, not filtered to "not this card's person"
   ```
3. Pick Ride — a *different* person than the card's own match:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Sally Ride"
   ```
   This calls `model.nameFace(tile.faceID, personID: rideID)` →
   `catalog.repository.assignFaces` (writes `person_faces.origin='user'` for
   Ride) → `refreshPeopleFaceSuggestions()`.
4. Assert the catalog write, and identify which of the three known-unassigned
   Glenn assets it landed on (the AX tree's tile order isn't asserted here,
   only the ground-truth result):
   ```bash
   NAMED_TO_RIDE=""
   for A in "$GLENN_1962_ID" "$GLENN_SENATOR_ID" "$GLENN_PORTRAIT_ID"; do
     ORIGIN=$(script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$A' AND person_id='$RIDE_PERSON_ID';")
     [ "$ORIGIN" = "user" ] && NAMED_TO_RIDE="$A"
   done
   [ -n "$NAMED_TO_RIDE" ]   # exactly one of the three now belongs to Ride, origin=user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$NAMED_TO_RIDE';"  # 1 row total — not double-assigned to Glenn too
   ```
5. Assert the card recomputed — the named-away face is gone from Glenn's
   group, both via the header count and by re-querying Glenn's own count:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "2 faces"
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$GLENN_PERSON_ID';"  # still 1 — unchanged, the face went to Ride, not Glenn
   ```

### 3. Name a second tile to a brand-new typed person

1. Click a remaining tile's Name pill:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Name"
   ```
2. Type a name that matches no existing candidate, and create it:
   ```bash
   script/vm_scenario_run.sh ax type --contains "Name" --text "Gordon Cooper"
   script/vm_scenario_run.sh ax press --role AXButton --label 'Create "Gordon Cooper"'
   ```
   This calls `model.nameFace(tile.faceID, newPersonName: "Gordon Cooper")` →
   `upsertPerson` + `assignFaces` (`origin='user'`) → `refreshPeopleFaceSuggestions()`.
3. Assert the new person and the write, on whichever of the two still-unnamed
   Glenn assets it landed on:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE name='Gordon Cooper';"  # 1
   COOPER_PERSON_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='Gordon Cooper';")
   NAMED_TO_COOPER=""
   for A in "$GLENN_1962_ID" "$GLENN_SENATOR_ID" "$GLENN_PORTRAIT_ID"; do
     [ "$A" = "$NAMED_TO_RIDE" ] && continue
     ORIGIN=$(script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$A' AND person_id='$COOPER_PERSON_ID';")
     [ "$ORIGIN" = "user" ] && NAMED_TO_COOPER="$A"
   done
   [ -n "$NAMED_TO_COOPER" ]
   ```
4. Assert the card recomputed again:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "1 face ·"
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$GLENN_PERSON_ID';"  # still 1
   ```

### 4. Confirm the one remaining tile the ordinary one-tap way

1. Press the confirm bar's button (labeled with the card's own person,
   `review.confirmActionTitle` = "John Glenn"):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "John Glenn"
   ```
   This is the pre-existing `confirm(suggestion)` path (unchanged by this
   task) — `AppModel.confirmPeopleFaceSuggestion`.
2. Assert the last remaining Glenn asset (whichever wasn't named away in
   Steps 2-3) is now linked to Glenn, `origin='user'`:
   ```bash
   LAST_GLENN=""
   for A in "$GLENN_1962_ID" "$GLENN_SENATOR_ID" "$GLENN_PORTRAIT_ID"; do
     [ "$A" = "$NAMED_TO_RIDE" ] && continue
     [ "$A" = "$NAMED_TO_COOPER" ] && continue
     LAST_GLENN="$A"
   done
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$LAST_GLENN' AND person_id='$GLENN_PERSON_ID';"  # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$GLENN_PERSON_ID';"  # 2 (official + this one)
   ```
3. Assert the review sheet now shows its completion state (nothing left in
   this group — `FaceGroupReviewView.completionState`, since the Glenn match
   suggestion no longer resolves once every one of its faces has a
   `person_faces` row):
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Nothing left to review"
   ```

## Expected

- Step 1: the review card opens with 3 tiles, each showing both a ✕ and a
  Name pill; opening it writes nothing (`person_faces` for Glenn stays at 1).
  **Fails if** the Name pill is missing from any tile, or opening the review
  changed the catalog.
- Step 2: the autocompleter lists both confirmed people ranked by similarity;
  picking Sally Ride assigns exactly one of the three unassigned Glenn faces
  to her (`origin='user'`), the header drops to "2 faces", and Glenn's own
  count is unchanged. **Fails if** the pill doesn't open a popover, Ride isn't
  listed, the face is double-assigned (to both Glenn and Ride), or the group
  doesn't shrink.
- Step 3: typing an unmatched name and pressing `Create "Gordon Cooper"`
  creates a new person and assigns one more of the remaining Glenn faces to
  him (`origin='user'`); the header drops to "1 face". **Fails if** the new
  person isn't created, the assignment fails, or the group doesn't shrink
  again.
- Step 4: the ordinary one-tap confirm still works on whatever's left —
  the last face links to Glenn (`origin='user'`), and the sheet then shows
  the "Nothing left to review" completion state. **Fails if** the last face
  isn't linked, or the sheet is left showing a stale/empty grid instead of
  the completion state.

## Cleanup

Quit the launched instance; discard the VM run directory
(`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state), per
`test/scenarios/README.md`'s isolated-launch teardown. Touch no real catalog.

## Sharp edges

- **The Name pill's label ("Name") is shared by every tile.** `ax_drive.sh
  press --role AXButton --label "Name"` presses whichever matching element
  the AX tree walk finds first, not a specific asset's tile — this card
  deliberately does not assume *which* tile gets acted on in Steps 2-3; it
  identifies the affected asset afterward by querying all three
  known-by-filename candidates and finding the one whose `person_faces` row
  changed. Do not "fix" this by guessing an AX tree order.
- **The popover's `TextField` placeholder ("Name") is not unique app-wide**
  (culling-session-name and sidebar rename fields also use it, per
  `people-024-face-autocompleter.md`'s Sharp edges); sanity-check with a plain
  `ax find --contains "Name"` first if `type` ever seems to hit the wrong
  field.
- **A `PersonAutocompleteField` row button's accessible label is its
  `Text(candidate.name)`**, unqualified by the similarity "%" badge next to
  it (verified working in `people-024`'s pill-assign leg); if a press by
  `--label "Sally Ride"` doesn't match live, fall back to `ax find --role
  AXButton --contains "Ride"` to see what the row's actual accessible text is.
- **Clustering isn't guaranteed.** Whether all three of Glenn's remaining
  faces land in one review group depends on `FaceSuggestionBuilder`'s match
  distance (1.23) against the fixture's real embeddings, same caveat
  `people-024`/`people-021` flag. If fewer than 3 tiles appear, run Steps 2-3
  on however many are present (at minimum: one named away, one confirmed in
  Step 4) rather than forcing a 3-tile count; if only 1 tile appears, Step 3's
  "brand-new person" leg cannot run in this same group — note the fixture gap
  and consider re-running the download/evaluate pass rather than inventing a
  workaround.
- **AuraFace gating.** The Pre-state's evaluation pass needs the AuraFace
  embedder present (`download_face_model.sh`); if missing, `face_observations`
  stays empty and the whole card is blocked — stop and flag per
  `dev-008-sample-downloads.md`'s manifest-gap note, don't force it.
- **Idle-wedge / keep-warm.** Every wait above (evaluation, AX polling) needs
  the app kept frontmost — re-assert via `script/vm_scenario_run.sh ax
  wait-vended Teststrip` on every poll, per CLAUDE.md and
  `script/verify_people_clustering.sh`'s reference pattern.

## Run status

NOT RUN — authored 2026-07-15 against `feat/face-naming-polish`, for Task 2 of
the Face Naming Polish sub-project. Every label, AX role/help string, file
path, and method name above was re-verified by reading the actual
current-tree source listed under "Source" before writing this card. Pending
live execution in the Tart VM with the AuraFace model present
(`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a
human-triggered step separate from authoring this card.
