# people-024-face-autocompleter: face-box name pill autocompleter and inspector people autocompleter

**What this covers**: the face autocompleter sub-project — on the loupe with
the inspector visible, hovering an unnamed face box reveals a "Name…" pill that
opens a popover autocompleter listing candidate people **ordered by similarity
%**, and the inspector's People section autocompleter for both picking existing
people and creating new ones. Exercises face-box pill-driven assignment, removal
via the ✕ button (confirmed → unassign, suggested → sticky reject), and
inspector-driven new-person creation.

## Pre-state

A freshly built, isolated app instance seeded with real face photos (VM +
AuraFace), built up to a concrete fixture: one person confirmed with a
face-level assignment (so a centroid exists for ranking) and two additional
unassigned same-person faces waiting for autocompleter assignment.
Construction mirrors `people-020-ai-label-provenance.md`'s §3 and §7-9 almost
exactly.

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
`commons-glenn-senator.jpg`, `commons-glenn-senator-portrait.jpg`.

1. **Evaluate everything** so face detection runs before anything else (mirrors
   `people-022-proposed-and-key-photo.md`'s Pre-state step 1):
   ```bash
   ax wait-vended Teststrip
   # (⌘2 Library — confirm all 11 thumbnails visible)
   ax press --role AXMenuItem --label "Evaluate Visible"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required — if 0, the AuraFace model didn't load; stop and flag, don't force the rest
   ```
2. **Confirm one face to establish a centroid** — the basis for
   autocompleter ranking (mirrors `people-020` step 7 verbatim). Open
   `commons-glenn-official.jpg` (⌘2 → Library → select → double-click → ⌘I;
   scroll to People section):
   ```bash
   GLENN_OFFICIAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg';")
   GLENN_1962_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-1962.jpg';")
   GLENN_SENATOR_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-senator.jpg';")
   RIDE_STS7_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-ride-sts7.jpg';")
   ```
   Assign Glenn to the first photo:
   ```bash
   ax press --role AXButton --label "Add name"
   ax press --role AXMenuItem --label "New person…"
   ax type --contains "Person name" --text "John Glenn"
   ax press --role AXButton --label "Create Person"
   ```
   ```bash
   JOHN_GLENN_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='John Glenn';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"    # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_OFFICIAL_ID';"  # 1
   ```
3. **Re-evaluate to build AI proposals** against the new centroid (mirrors
   `people-020` step 8 — promotion fires only on evaluation completion).
   Select `$GLENN_1962_ID`, then:
   ```bash
   ax press --role AXMenuItem --label "Evaluate Photo"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE asset_id='$GLENN_1962_ID';"); [ "$n" -gt 0 ] && break; sleep 2; done
   ```
   Check:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_1962_ID' AND origin='ai' AND person_id='$JOHN_GLENN_ID';"  # >0 — or retry with $GLENN_SENATOR_ID or a Ride pair if this didn't cluster
   ```
   Repeat for `$GLENN_SENATOR_ID`:
   ```bash
   ax wait-vended Teststrip
   # (⌘2 Library → select $GLENN_SENATOR_ID's thumbnail)
   ax press --role AXMenuItem --label "Evaluate Photo"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE asset_id='$GLENN_SENATOR_ID';"); [ "$n" -gt 0 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_SENATOR_ID' AND origin='ai' AND person_id='$JOHN_GLENN_ID';"  # >0 — or retry with another asset
   ```

This leaves `$JOHN_GLENN_ID` confirmed with a centroid, and `$GLENN_1962_ID` +
`$GLENN_SENATOR_ID` each with an unassigned face (`person_faces` exists with
`origin='ai'`, but UI doesn't show them until clicked/assigned via
autocompleter in the Steps below). A third unassigned face on `$RIDE_STS7_ID`
will be used in Step 4 for inspector-driven new-person creation.

## Steps

### 1. Face-box pill: assign an AI-proposed face via autocompleter

1. Open `commons-glenn-1962.jpg` on the loupe with inspector visible (⌘2
   Library → select → double-click → ⌘I). Assert that the face is currently
   unconfirmed:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_1962_ID';"  # ai
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE asset_id='$GLENN_1962_ID';"  # 0
   ```
2. On the loupe, identify the unassigned face box and hover it. The inspector
   uses `focusedFaceID` to track hover state (per `Sources/TeststripApp/Views/PhotoLoupe.swift` overlay logic) — on hover, a "Name…" pill button appears
   over the face box.
   - **AX note**: Face-box identification by AX is delicate (each box is a
     custom overlay rect with no independent AXElement); the exact `--xpath`
     or label to find the pill may require a real-run pass to pin precisely.
     As written, this assumes the pill has an accessibility label or can be
     found by role + nearby box position; adjust per actual AX hierarchy when
     running live.
3. Click the "Name…" pill button:
   ```bash
   ax press --role AXButton --label "Name…"
   ```
   A popover autocompleter appears, listing candidate people **ordered by
   similarity %** (per `FaceSuggestionBuilder.sortedSuggestions(_:)` ranking).
   John Glenn should appear at/near the top.
4. Click "John Glenn" in the autocompleter popover:
   ```bash
   ax press --role AXButton --label "John Glenn"
   ```
5. Assert the assignment:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_1962_ID' AND person_id='$JOHN_GLENN_ID';"  # user (flipped from ai)
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_1962_ID';"  # 1 (created)
   ```

### 2. Face-box pill: remove a confirmed assignment via ✕

1. Still viewing `commons-glenn-1962.jpg` on the loupe, hover the now-named
   face box. The pill should now show the person name ("John Glenn") with a
   trailing ✕ button instead of "Name…".
2. Click the ✕ button:
   ```bash
   ax press --role AXButton --label "Clear…"  # or match the ✕ icon label — adjust per actual AX label
   ```
3. Assert the unassignment:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_1962_ID' AND person_id='$JOHN_GLENN_ID';"  # 0 (removed)
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_1962_ID';"  # 0 (unlinked)
   ```

### 3. Face-box pill: re-assign and then step 4 will use inspector instead

1. Click the "Name…" pill again to re-open the autocompleter:
   ```bash
   ax press --role AXButton --label "Name…"
   ```
2. Click "John Glenn" to re-assign:
   ```bash
   ax press --role AXButton --label "John Glenn"
   ```
3. Confirm:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_1962_ID' AND person_id='$JOHN_GLENN_ID';"  # user again
   ```

### 4. Inspector autocompleter: create a new person on an unnamed face

1. Open `commons-ride-sts7.jpg` (`$RIDE_STS7_ID`) on the loupe with inspector
   visible (same ⌘2/double-click/⌘I flow). This asset has no prior face
   assignments (none of the Ride photos were in the Pre-state face confirmation
   or evaluation path). Assert:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$RIDE_STS7_ID';"  # 0
   ```
2. In the inspector's People section, find the face row (a `.suggested` or
   `.unassigned` row, depending on whether AI promotion happened to propose
   something; for simplicity, assume it's unassigned and shows a "Name…" or
   similar placeholder):
   - **AX note**: the People section is a `VStack` in `InspectorView.swift`
     (`PhotoFacesSectionView`); find the face's row and the autocompleter
     trigger within it.
3. Click the face's autocompleter trigger (e.g., a "Name…" button or similar in
   the People row):
   ```bash
   ax press --role AXButton --label "Name…"  # or the actual label for the People section's face assignment trigger
   ```
   The autocompleter popover appears, listing existing people (John Glenn,
   etc.) and showing a "Create 'Gus Grissom'" row if a new name has been
   typed.
4. Type a new name, "Gus Grissom", in a text field (if the autocompleter
   includes a free-text input) or trigger a new-person flow (the exact UI
   depends on the inspector's autocompleter design — flag if the flow differs
   from this outline):
   ```bash
   ax type --contains "Person name" --text "Gus Grissom"
   ```
5. Activate the "Create 'Gus Grissom'" row or button:
   ```bash
   ax press --role AXMenuItem --label "Create 'Gus Grissom'"  # or equivalent
   ```
6. Assert the new person and the assignment:
   ```bash
   GUS_GRISSOM_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='Gus Grissom';")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE name='Gus Grissom';"  # 1 (created)
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$RIDE_STS7_ID' AND person_id='$GUS_GRISSOM_ID';"  # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$GUS_GRISSOM_ID' AND asset_id='$RIDE_STS7_ID';"  # 1
   ```

## Expected

- Step 1.2–1.4 (face-box pill assign): the popover autocompleter appears with
  John Glenn ranked at or near the top (similarity % ordering visible or
  verifiable via the presence of other candidates lower in the list). **Fails
  if** the autocompleter does not appear, John Glenn is not listed, or the
  popover shows no ordering distinction.
- Step 1.5 (assignment): `person_faces.origin` for `$GLENN_1962_ID`/John Glenn
  flips from `ai` to `user`, and a `person_assets` row is created. **Fails if**
  the row stays `ai`, no `person_assets` row appears, or the face remains
  unassigned in the UI.
- Step 2.2–2.3 (face-box remove): clicking the ✕ button removes both the
  `person_faces` row (confirmed → unassign, not stub with `origin='ai'`) and
  the `person_assets` row. **Fails if** either row persists, the UI still shows
  the face assigned, or the pill reappears with "John Glenn" still active.
- Step 3 (re-assign): the pill can be clicked again to re-open the autocompleter
  and re-assign the same person. **Fails if** the pill does not reappear after
  removal, or the re-assignment is rejected or silently fails.
- Step 4.6 (inspector autocompleter, new person): a new `people` row is created
  with `name='Gus Grissom'`, a `person_faces` row links the face to the new
  person with `origin='user'`, and a `person_assets` row exists. **Fails if**
  the new person row is not created, the face assignment fails, or the row has
  the wrong `origin`.

## Cleanup

Quit the launched instance; discard the VM run directory (`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state) created for this run, per `test/scenarios/README.md`'s isolated-launch teardown. Touch no real catalog.

## Sharp edges

- **Face-box pill AX targeting is delicate.** The face box is a custom overlay
  rect (per `PhotoLoupe.swift`'s `focusedFaceID` hover logic), and the pill
  appears on hover via `ZStack` overlay logic — not a persistent, always-present
  AXButton. Finding the pill via AX may require matching by `--xpath`, nearby
  element context, or the text label `"Name…"` / person name string. On a real
  run, inspect the AX hierarchy (e.g., via Xcode's Accessibility Inspector or
  `script/ax_drive.sh find --role ...` exploratory queries) to nail down the
  exact selector and label; this card's `ax press --role AXButton --label
  "Name…"` is a best-guess outline that may need adjustment. Similarly, the
  ✕ button's accessibility label (e.g., `"Clear…"`, `"Remove"`, an icon label)
  must be verified live.
- **Inspector autocompleter design unconfirmed.** This card assumes the
  inspector's People section has a face-level autocompleter trigger (a button
  or text input) that behaves like the face-box pill (showing a popover, listing
  people, supporting new-person creation via a "Create '…'" row). If the actual
  UI differs (e.g., a different layout, a different trigger mechanism, or a
  different new-person flow), adjust Steps 4.2–4.5 to match the real
  implementation.
- **AI proposal presence optional.** If Pre-state step 3's evaluation doesn't
  fire an AI proposal for `$RIDE_STS7_ID` (Step 4.1 `person_faces` check returns
  0), that's expected — the face is simply unassigned, and Step 4 proceeds
  normally. The card doesn't require a proposed face; it exercises both
  unassigned and (if present) proposed faces.
- **Idle-wedge / keep-warm**: Step 1 waits on face rendering in the loupe after
  opening a photo. If the loupe lags or the face box doesn't appear, re-assert
  frontmost via `ax wait-vended Teststrip` and retry navigation. Keep the app
  warm during any waits, per CLAUDE.md and `script/verify_people_clustering.sh`'s
  reference pattern.

## Run status

NOT RUN — authored 2026-07-14 against `feat/person-autocompleter`, not yet run
live. Pending execution in the Tart VM with the AuraFace model present
(`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a
human-triggered step separate from authoring this card.
