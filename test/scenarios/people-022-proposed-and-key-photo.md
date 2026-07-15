# people-022-proposed-and-key-photo: a person's Proposed section + key-photo card

**What this covers**: the People-surfacing sub-project — the per-person
Proposed section (inline ✓ confirm / ✗ reject) and the best-confirmed-face key
photo on People cards. Exercises `proposedPersonFaces`, `keyFacesByPerson`,
`confirmProposedPhoto`, `rejectProposedPhoto`.

## Pre-state

A freshly built, isolated app instance seeded with real face photos (VM +
AuraFace), built up to a concrete fixture: one person confirmed with a
face-level assignment (so a key face exists) and two same-person `origin='ai'`
proposals on two other assets — one to confirm, one to reject-then-rescan.
Construction mirrors `people-020-ai-label-provenance.md`'s §3 ("Face-match
promotion") almost exactly; reproduced here for a lone `person:` filter.

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

1. **Evaluate everything** so face detection runs before anything else:
   ⌘2 Library, confirm all 11 thumbnails are present, then Culling ▸
   **Evaluate Visible** (⇧⌘E): `ax press --role AXMenuItem --label "Evaluate
   Visible"`. Keep the app warm (re-assert frontmost every poll) while it
   drains:
   ```bash
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required — if 0, the AuraFace model didn't load; stop and flag, don't force the rest
   ```
2. **Confirm one face to create the person + key face** — a direct **user**
   gesture (mirrors people-020's step 7 verbatim):
   ```bash
   GLENN_OFFICIAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg';")
   GLENN_1962_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-1962.jpg';")
   GLENN_SENATOR_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-senator.jpg';")
   ```
   Open `commons-glenn-official.jpg` (⌘2 → select → double-click → ⌘I;
   scroll to the People section):
   ```bash
   ax press --role AXButton --label "Add name"
   ax press --role AXMenuItem --label "New person…"
   ax type --contains "Person name" --text "John Glenn"
   ax press --role AXButton --label "Create Person"
   ```
   ```bash
   JOHN_GLENN_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='John Glenn';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"    # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_OFFICIAL_ID';"  # 1 — this is the key face
   ```
3. **Re-evaluate two more same-person assets to fire two AI proposals**
   (promotion only runs on a genuine evaluation-completion event — not on
   navigation or naming — per people-020's step 8 caution). For each of
   `$GLENN_1962_ID` and `$GLENN_SENATOR_ID`: select its thumbnail (⌘2
   Library, click), then `ax press --role AXMenuItem --label "Evaluate
   Photo"` (single-asset), wait for it to drain, then check:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT face_index, origin, person_id FROM person_faces WHERE asset_id='$GLENN_1962_ID';"     # origin='ai', person_id=$JOHN_GLENN_ID
   script/vm_scenario_run.sh sql faces "SELECT face_index, origin, person_id FROM person_faces WHERE asset_id='$GLENN_SENATOR_ID';"  # origin='ai', person_id=$JOHN_GLENN_ID
   ```
   Both need an `origin='ai'` row against `$JOHN_GLENN_ID` — together they're
   the fixture's two proposed cells (Steps §3 confirms one, Steps §4-5
   reject-and-rescan the other; which literal asset plays which role doesn't
   matter — Steps §3 resolves it by querying which one actually got
   confirmed, since both cells' buttons share identical AXHelp text). If
   either didn't cluster within
   `FaceSuggestionBuilder.defaultMaximumMatchDistance` (1.23), retry with the
   fourth Glenn photo (`commons-glenn-senator-portrait.jpg`) or fall back to
   a same-person Ride pair, per people-020's step 9 caution — note the
   fixture gap rather than forcing a result.

This leaves `$JOHN_GLENN_ID` ("John Glenn") confirmed with a key face
(`$GLENN_OFFICIAL_ID`) and two same-person AI proposals
(`$GLENN_1962_ID`, `$GLENN_SENATOR_ID`) — the fixture the Steps below exercise.

## Steps

1. Navigate to People: ⌘2 Library, then AX-press the Library sub-view toggle
   segment labeled **"People"** (the Grid | Loupe | Timeline | Map | People
   toggle, per `people-021-face-group-review.md`'s step 2). Find John
   Glenn's card.
   ```bash
   ax find --role AXStaticText --contains "John Glenn"
   ```
2. Click John Glenn's card to open his `person:"John Glenn"` grid
   (`showPersonPhotos(named:)`).
3. Click ✓ (bottom-trailing, AXHelp "Confirm this person") on either
   proposed cell — both cells' buttons share identical AXHelp text, so which
   literal photo you click doesn't matter; resolve which one it was
   afterward:
   ```bash
   CONFIRM_ID=$(script/vm_scenario_run.sh sql faces "SELECT asset_id FROM person_faces WHERE person_id='$JOHN_GLENN_ID' AND origin='user' AND asset_id != '$GLENN_OFFICIAL_ID';")
   if [ "$CONFIRM_ID" = "$GLENN_1962_ID" ]; then REJECT_ID="$GLENN_SENATOR_ID"; else REJECT_ID="$GLENN_1962_ID"; fi
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$CONFIRM_ID' AND person_id='$JOHN_GLENN_ID';"   # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$CONFIRM_ID';"  # 1
   ```
4. Reopen John Glenn's `person:` grid — only `$REJECT_ID` is left in
   Proposed now that `$CONFIRM_ID` has moved to the confirmed grid, so this
   click is unambiguous. Click ✗ (top-leading, AXHelp "Not this person") on
   it.
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM rejected_face_people WHERE asset_id='$REJECT_ID' AND person_id='$JOHN_GLENN_ID';"        # 1
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$REJECT_ID' AND origin='ai' AND person_id='$JOHN_GLENN_ID';" # 0 — the ai row is deleted, not just hidden
   ```
5. **Re-run recognition on just the rejected asset — not the whole filtered
   scope.** `requestCurrentScopeAssetEvaluations` (what "Evaluate Visible"/
   the People-scan action calls) scopes candidates through
   `currentLibraryQuery()`, and the `.person` predicate matches only
   confirmed `person_assets` rows (`CatalogRepository.swift:2779-2793`) — the
   asset just rejected in step 4 has neither a `person_assets` nor a
   `person_faces` row for John Glenn any more, so if the `person:"John
   Glenn"` filter were still active it would sit outside scope and never get
   re-evaluated, and the sticky-reject guard would never be exercised. Fix:
   clear the filter (⌘2 Library, plain — full library back in view) and
   select `$REJECT_ID`'s thumbnail directly, then re-evaluate just that one
   asset (mirrors people-020's step 8 single-asset pattern):
   ```bash
   ax press --role AXMenuItem --label "Evaluate Photo"
   ```
   Keep the app warm (re-assert frontmost via `wait-vended` on every poll —
   see Sharp edges) while it drains, then reopen John Glenn's `person:` grid
   and check the Proposed section and the catalog:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$REJECT_ID' AND origin='ai' AND person_id='$JOHN_GLENN_ID';"  # must stay 0
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM rejected_face_people WHERE asset_id='$REJECT_ID' AND person_id='$JOHN_GLENN_ID';"           # still 1
   ```

## Expected

- Step 1: John Glenn's card shows a cropped face photo (from the confirmed
  `$GLENN_OFFICIAL_ID` key face), not a colored gradient circle. **Fails if**
  it still shows a gradient circle for a person who has a confirmed face.
- Step 2: `$GLENN_OFFICIAL_ID` appears in the confirmed grid; a "✨ Proposed"
  section below lists `$GLENN_1962_ID` and `$GLENN_SENATOR_ID`. **Fails if**
  no Proposed section renders despite the two `origin='ai'` rows from
  Pre-state step 3, or either proposed photo also appears in the confirmed
  grid.
- Step 3: `person_faces.origin` for `$CONFIRM_ID`/John Glenn flips to `user`
  and a `person_assets` row is created. **Fails if** the row stays `ai`, no
  `person_assets` row appears, or `$CONFIRM_ID` fails to resolve (neither
  proposed cell was actually confirmed).
- Step 4: rejecting `$REJECT_ID` both (a) creates the `rejected_face_people`
  row and (b) deletes the `origin='ai'` `person_faces` row. **Fails if** the
  `rejected_face_people` row is absent (reject didn't record), **or fails
  if** the `origin='ai'` row is still present (reject only hid the cell
  instead of clearing the suggestion, leaving it able to resurface).
- Step 5: after a targeted re-evaluation of exactly the rejected asset, no
  new `origin='ai'` `person_faces` row appears for `$REJECT_ID`/John Glenn
  and the `rejected_face_people` row persists — i.e. the photo does **not**
  reappear in Proposed. **Fails if** an `origin='ai'` row reappears (sticky
  reject leaked) — this is the assertion the whole card exists to make, and
  it is only meaningful because step 5 re-evaluates the rejected asset
  directly instead of through the (still-filtered) person scope.

## Cleanup
Quit the launched instance; discard the VM run directory
(`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state)
created for this run, per `test/scenarios/README.md`'s isolated-launch
teardown. Touch no real catalog.

## Sharp edges
- Proposed cells only render for a lone `person:` filter; adding any other
  token clears the section.
- Key photo requires a face-level confirmation; a whole-asset-confirmed
  person correctly shows the gradient fallback — don't read that as a bug.
- **The `person:` filter scopes re-evaluation, not just the grid.** A
  rejected (or merely proposed, never-confirmed) asset has no `person_assets`
  row, so it is outside `currentLibraryQuery()`'s `.person` predicate and
  will silently not be re-evaluated by any current-scope action (Evaluate
  Visible, People-scan) while that filter is active — re-evaluate a specific
  asset directly (select it, "Evaluate Photo") when the point is to test
  what happens to *that* asset.
- **Idle-wedge / keep-warm**: step 5 waits on an asynchronous recognition
  pass; a backgrounded/idle app parks its accessibility tree and becomes
  undrivable — re-assert frontmost (`script/vm_scenario_run.sh ax
  wait-vended Teststrip`) on every poll while waiting, per CLAUDE.md and
  `script/verify_people_clustering.sh`'s reference pattern.

## Run status
NOT RUN — authored 2026-07-14 against `feat/people-surfacing`, not yet run
live. Pending execution in the Tart VM with the AuraFace model present
(`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a
human-triggered step separate from authoring this card.
