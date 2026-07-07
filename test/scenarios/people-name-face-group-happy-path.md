# people-name-face-group-happy-path: Naming a face group writes only on confirm

**What this covers**: the People flow — automatic face grouping surfaces
"needs a name" suggestion cards; confirming/naming one writes a `people` row
and its `person_assets` links; nothing is written until the explicit confirm.
The positive path (a group gets named and persists) plus the invariant (a
merely-suggested group leaves the catalog untouched).

Grouping now uses the bundled ArcFace face-identity model (aligned 112×112
crop → 512-d L2-normalized embedding), not the old whole-image feature print, so
the surfaced suggestions should be **identity-coherent**: a suggested group
should be one person's faces, not a visual-similarity grab-bag.

## Pre-state
- Fresh build against a corpus that actually contains faces. **Synthetic
  `--isolated` seed has no detectable faces, and the `--sample-photos`
  (WordPress) set has 0/12** (it is landscapes, statues, and animals — Vision
  finds no human faces). Use the dedicated face corpus instead, and download
  the face-identity model first so identity embeddings are produced:
  ```bash
  ./script/download_face_model.sh
  ./script/build_and_run.sh --faces
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
  `--faces` downloads `sample-data/faces.tsv` — 11 public-domain Wikimedia
  Commons portraits (Vision-verified this many detected faces per file: John
  Glenn ×4, Sally Ride ×4, Neil Armstrong ×2, Buzz Aldrin ×1). Glenn and Ride
  each appear in four photos, so face grouping has same-person clusters to
  form, not just isolated detections. The binaries are gitignored; the manifest
  is checksum-verified on download.

## Steps
1. **Record the baseline** (ground truth):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # call it P0 (named/confirmed people)
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # call it L0
   ```
2. **Open People and wait for grouping.** `script/activate_app.sh Teststrip`;
   AX-press the top-bar mode item labeled **"People"**. `waitFor` either a
   suggestion card or the header `AXStaticText` matching
   **"N people · M photos with face signals"** with M ≥ 1. Face detection is
   async — give it time to drain (watch Activity).
3. **Assert suggestions are provisional** (invariant, before confirming):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # must still equal P0
   ```
   Surfacing a "needs a name" card must not have written a person.
4. **Confirm/name a group.** AX-press a suggestion card's confirm button
   (accessible via help **"Confirm these faces as …"** or **"Name this face
   group"**). If a name sheet appears (**"Name Face Group"**), type a name and
   press its confirm button.
5. **Assert the confirm wrote through**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # P1
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # L1
   ```
6. **Assert it renders as a named person.** Re-dump People; the named group now
   appears as a confirmed person (no longer in the "needs a name" band).

## Expected
- Step 2: face signals present (M ≥ 1) and at least one suggestion card.
  **Fails if** the corpus yields no face signals — that's the fixture gap, not
  a code failure; report which corpus you used.
- Step 3: `people` count unchanged at `P0`. **Fails if** it rose from a mere
  suggestion — confirm-before-write violation; report it.
- Step 5: `P1 == P0 + 1` and `L1 > L0` (the confirmed group's assets linked).
  **Fails if** the counts are unchanged after confirming. Quote P0/P1, L0/L1.
- Step 6: the group renders as a named person. **Fails if** it's still shown as
  an unnamed suggestion after a successful confirm.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Face detection and clustering are asynchronous and can lag well behind the
  view opening; don't conclude "no suggestions" (step 2) until the face-work
  queue in Activity has drained.
- Two confirm shapes exist: one-tap confirm (writes immediately) and a
  name-sheet path. The `card.isOneTapConfirm` help text distinguishes them —
  handle the sheet if it appears, but don't wait for a sheet that never comes.
- Cross-check the rendered person against the `people` row: the UI must not show
  a named person the table doesn't back (name fabricated in the view).
