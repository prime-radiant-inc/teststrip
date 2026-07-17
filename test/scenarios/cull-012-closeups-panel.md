# cull-012-closeups-panel: Close-Ups face-crop rail is Cull-chrome-only and writes nothing

**What this covers**: As a photographer culling a group shot I want to check
everyone's eyes/expression at a glance via face close-ups next to the loupe,
without it being confused for the People view's face-confirmation flow (no
catalog writes come from looking at it). Covered inventory items 34
(Cull-chrome-only 112px crop rail) and 35 (display-only — nothing
persisted).

**Reconciled 2026-07-17 (dogfood-r1 panel pass)**: Close-Ups moved from a
grid stacked *above* the Reads card to a vertical **rail on the right edge**
of the same faces+reads panel, with the Reads card now to its left
(`cullFacesReadsPanel` became an `HStack`, not a `VStack`) — dogfood
feedback that the old top-to-bottom stack pushed the reads content too far
down. Each crop also now carries compact on-face read marks immediately
below it: an eye glyph (`eye` open / `eye.slash` closed, orange when
closed), a smiling-face glyph only when the detector actually saw a smile,
and a small green/orange sharpness dot — never bars, never text, and never
a mark for a read the photo doesn't have (see the "on-face marks" step
below). The 112px crop size, the Cull-chrome-only gate, and the
display-only/nothing-persisted behavior are unchanged.

**Source (re-verified 2026-07-17)**: `cullFacesReadsPanel` at
`Sources/TeststripApp/LibraryGridView.swift:4027-4041` (now an `HStack` of
`readsCard` + `closeUpsRail`), gated into the loupe body only `if
presentation.showsCullChrome && model.showsCullFacesPanel` at `:3832`;
`closeUpsRail` at `:4043-4069`; per-crop rendering (`closeUpCropCell`,
`closeUpMarks`) at `:4071-4104`; `refreshCloseUps(for:)` at `:4172-4204`;
the marks themselves come from `CloseUpFacesPresentation.Crop` (`eyesState`,
`isSmiling`, `sharpnessTone`) in `Sources/TeststripApp/CloseUpFacesPresentation.swift`.

**Correction to the assumed source of truth**: `refreshCloseUps` does **not**
read the catalog's `face_observations` table. It runs a fresh, synchronous,
display-only detection pass — `CoreImageFaceExpressionAnalyzer().detectFaces(previewURL:)`
— over the cached preview image every time the loupe selection changes, then
crops in memory via `CloseUpFacesPresentation`. Nothing is written back, and
the crop count is **not guaranteed to equal** `face_observations` row count
for that asset, because `face_observations` is populated by a separate
detector (the worker's face-embedding pipeline) that may find a different
face count, run at a different time, or use a different confidence threshold
than the live Core Image analyzer. Treat "crops render for a photo with
visible faces" as the assertion, not "crop count == face_observations count".
The same applies to the on-face eyes/smile marks — they come from the same
live per-crop `DetectedFaceExpression`, so they're always internally
consistent with the crop they're attached to, but not necessarily with
`face_observations`. The sharpness dot is different again: it's the
asset-level `faceQuality`/`eyeSharpness` evaluation signal (no per-face
location), so `CloseUpFacesPresentation` only attaches it when there's
**exactly one** face crop for the asset — with 2+ faces, no crop shows a
sharpness dot (ambiguous attribution, so no mark beats a misleading one).

## Pre-state
```bash
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
```

## Steps
1. Face detection is NOT passive on a pre-seeded catalog — the worker only
   produces `face_observations` for assets that get an evaluation request.
   Trigger one first (menu item, not a toolbar button):
   ```bash
   script/ax_drive.sh press Teststrip --role AXMenuItem --label "Evaluate Matches"
   ```
   In the VM this also requires the faces originals on disk —
   `vm_scenario_run.sh sync faces` ships `sample-data/photos/faces` and
   `launch` rewrites `original_path`. A catalog whose loupe reads "Original
   missing; cached previews only" will never produce observations (that
   combination is what stalled run-cull-iter2 at 0 rows for 95s).
   Then find a `--faces`-seeded asset with 2+ detected faces (verified live
   2026-07-10: 11 observations landed within ~10s of Evaluate Matches):
   ```bash
   for i in $(seq 1 60); do
     n=$(sqlite3 "$DB" "SELECT asset_id FROM face_observations GROUP BY asset_id HAVING count(*) >= 2 LIMIT 1;")
     [ -n "$n" ] && break; sleep 2
   done
   echo "$n"   # target asset id
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # PA0, expect 0 (nothing confirmed yet)
   sqlite3 "$DB" "SELECT count(*) FROM person_faces;"    # PF0, expect 0
   sqlite3 "$DB" "SELECT count(*) FROM dismissed_faces;" # DF0, expect 0
   ```
2. Switch to Cull workspace (⌘1) and select that asset in the loupe. Wait for
   the panel to populate:
   ```bash
   script/ax_drive.sh wait --role AXStaticText --contains "CLOSE-UPS"
   ```
   Assert the panel renders at least one crop image. Since the culling-flow
   shell (Task 5) the Close-Ups section always renders inside the faces+reads
   right panel, holding its space with an honest "No faces" empty state as
   its accessibility VALUE — so mere presence no longer proves crops > 0.
   Assert the element exists AND the empty-state value is absent:
   ```bash
   script/ax_drive.sh find --contains "Face close-ups"
   script/ax_drive.sh find --contains "No faces"   # expect exit nonzero (crops rendered)
   ```
   (The whole panel is toggled by the bare `/` culling key,
   `AppModel.showsCullFacesPanel`, default shown — don't press `/` mid-run.)
3. Switch to Library workspace (⌘2) with the same asset selected/open in its
   loupe. Assert the Close-Ups panel is **absent** (cull-chrome-only claim):
   ```bash
   script/ax_drive.sh find --contains "Face close-ups"   # expect exit nonzero (not found)
   ```
4. Back in Cull (⌘1), re-select the asset, wait for the panel again, then
   click/interact with one of the crop images. Read the source first to know
   whether it's even hit-testable — `closeUpCropCell`'s `Image(decorative:...)`
   rows carry no `Button`/tap gesture in the current source, so this step may
   be a no-op click. Capture catalog row counts before and after the
   interaction regardless:
   ```bash
   PA1=$(sqlite3 "$DB" "SELECT count(*) FROM person_assets;")
   PF1=$(sqlite3 "$DB" "SELECT count(*) FROM person_faces;")
   DF1=$(sqlite3 "$DB" "SELECT count(*) FROM dismissed_faces;")
   ```
5. **On-face marks.** With the same asset still selected, inspect each face
   cell's accessibility value (`closeUpCropCell`'s
   `.accessibilityLabel("Face")`/`.accessibilityValue(...)`):
   ```bash
   script/ax_drive.sh find --role AXImage --label "Face"   # or whichever role SwiftUI exposes for .accessibilityElement(children: .combine) here — inspect the AX tree first
   ```
   Cross-check against ground truth: for a face crop, "Eyes closed" in the
   value must correspond to a live `DetectedFaceExpression` with **both**
   `leftEyeClosed`/`rightEyeClosed` true (not independently queryable from
   the catalog — this is in-memory-only detection, so cross-check by eye
   from the crop image itself, not sqlite). If the fixture asset has exactly
   one face crop, also confirm whether "Sharp"/"Soft" appears — it should
   only if `evaluation_signals` has a `faceQuality` or `eyeSharpness` row for
   this asset (from step 1's Evaluate Matches pass); if the fixture has 2+
   face crops, confirm **no** cell shows "Sharp"/"Soft" (ambiguous
   attribution — the source deliberately omits the mark rather than
   guessing which face an asset-level signal describes).

## Expected
- Step 2: the Close-Ups rail renders with at least one 112x112 crop while in
  the Cull workspace on an asset with detected faces. **Fails if** the rail
  never appears despite a `--faces` asset with confirmed multi-face
  `face_observations`, or if it still shows the "No faces" empty-state value
  (zero crops).
- Step 3: the rail is completely absent from the Library workspace's loupe
  for the identical asset. **Fails if** it renders in Library — that would
  contradict the "Cull-chrome-only" claim in the gate at `:3832`.
- Step 4: `person_assets`/`person_faces`/`dismissed_faces` counts are
  identical before and after interacting with a crop (`PA1==PA0`,
  `PF1==PF0`, `DF1==DF0`). **Fails if** any count changed — that would be a
  confirm-before-write violation per CLAUDE.md (machine-derived face data
  written without an explicit confirming gesture). This assertion holds
  regardless of whether the click was a no-op; a no-op click passing this
  step trivially is fine and expected given the source reading in this card.
- Step 5: the eyes/smile marks match the crop's own detection, and the
  sharpness dot appears on exactly one crop when the asset has exactly one
  face crop and a scored faceQuality/eyeSharpness signal, or on **no** crop
  when the asset has 2+ face crops. **Fails if** a mark contradicts the crop
  it's attached to, or if a sharpness dot appears on more than one crop for
  the same asset (that would mean one asset-level signal got attributed to
  multiple faces, an honesty-invariant violation).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Do not cross-check the crop count against `face_observations`.** They are
  independent detectors (live Core Image analyzer vs. the worker's face
  pipeline) and can legitimately disagree on face count, or even on whether a
  face was found at all. The only faithful ground truth for "should the panel
  show crops" is `face_observations` count > 0 as a *precondition* to pick a
  fixture asset, not as an exact-match assertion on the rendered crop count.
- Step 4's "click a crop" gesture was read from source as very likely a
  no-op (`Image(decorative:)` with no button/tap modifier at
  `LibraryGridView.swift:4073-4078`) — if `ax_drive.sh find --role AXImage`
  can't even locate a pressable target, that's expected; don't fabricate an
  interaction that doesn't exist in the source. The negative-write assertion
  still stands and is still worth capturing.
- Worker face-detection timing on `--faces` seed was not independently timed
  in this pass — the 60x2s poll budget in step 1 is a guess mirrored from
  other cards' worker-wait patterns; adjust if it proves too short in a real
  run.
- Step 5's exact AX role/query for the per-crop `.accessibilityElement(children:
  .combine)` block was not independently confirmed against a live AX dump in
  this pass (line numbers and behavior were verified by reading source, not
  by driving) — inspect the AX tree first before locking the `find` query.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md.
Reconciled 2026-07-16: the card carried two "Source" paragraphs from
successive revisions (a stale one citing `closeUpsPanel` at
`LibraryGridView.swift:3705-3730` gated only on `showsCullChrome`, and an
accurate one citing `cullFacesReadsPanel`/`closeUpsPanel`/
`refreshCloseUps(for:)` gated on `showsCullChrome && showsCullFacesPanel`)
— verified both against the current working tree, kept the accurate one,
deleted the stale one, and refreshed its line numbers (drifted ~26 lines
since that paragraph was last written) plus two other citations of the same
gate/panel that had gone stale alongside it (Expected step 3, Sharp edges).
No other content changed.
