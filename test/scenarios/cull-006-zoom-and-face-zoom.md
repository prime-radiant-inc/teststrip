# cull-006-zoom-and-face-zoom: 1:1 zoom toggle and face-zoom cycling in the loupe

**What this covers**: as a photographer culling a shoot I want to snap to 1:1
so I can check focus/sharpness without leaving the loupe, and — on a
multi-person frame — cycle the zoom target across each detected face, so
that I can check every subject's eyes in a group shot without hunting for
them by hand. Covers item 21 (`z` toggles 1:1 zoom), item 22 (`Z` zooms to
the nearest face / cycles faces), and item 23 (face-zoom targets are the same
detections the Close-Ups panel shows, so the two features never disagree
about "what counts as a face").

Source:
- `Sources/TeststripApp/AppModel.swift:5494-5497` — `toggleLoupeZoom()`, the
  `z` shortcut (`CullingShortcut.toggleZoom`, keyed at `:255`).
- `Sources/TeststripApp/AppModel.swift:5519-5540` — `zoomToNearestFaceOrCycleFace()`,
  the `Z` (shift-z, exact-case) shortcut (`CullingShortcut.zoomToNearestFace`,
  keyed at `:233-234`): first press zooms to the face nearest the current
  focus (or center); a repeated press while still face-zoomed cycles to the
  next face, wrapping (`LoupeFaceZoomTargeting.wrappedIndex`, `:394-397`);
  falls back to a plain centered 1:1 zoom if no faces were detected (`:5524-5527`).
- `Sources/TeststripApp/LibraryGridView.swift:3736-3769` (`refreshCloseUps`) —
  **verified same-detections claim**: this is the single call site that both
  populates the Close-Ups panel crops (`closeUpCrops`) and calls
  `model.setLoupeFaceFocuses(result.faceFocuses)` (the Z-cycle targets). Both
  come from one `CoreImageFaceExpressionAnalyzer().detectFaces(...)` call per
  selection change — there is no second, independent face-detection path for
  the loupe. Comment at `:3736-3740` states this explicitly. Detection here
  is **display-only and in-memory** (nothing persisted to `face_observations`
  — that table backs the separate People-workspace clustering pipeline, not
  this loupe feature).

## Pre-state
```bash
./script/build_and_run.sh --faces
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--faces` seeds `sample-data/photos/faces` per `sample-data/faces.tsv`
(confirmed real: `script/build_and_run.sh` lines 209-217 map `--faces` to
`SAMPLE_PHOTOS_DIR=sample-data/photos/faces`). Use
`commons-armstrong-gemini8.jpg` (Armstrong and Scott, two people) as the
multi-face frame, and any single-portrait frame (e.g.
`commons-glenn-official.jpg`) for the plain 1:1 toggle.

## Steps
1. Open the loupe on `commons-glenn-official.jpg` (⌘1 Cull, navigate/select,
   Return to open loupe).
2. Press `z`. There is **no AX signal in the plain loupe** that reflects
   `model.loupeZoomFocus` (see Sharp edges) — the on-screen legend text
   `"Z 1:1"` (`LibraryGridView.swift:5313`) is static and does not change
   with zoom state. Fall back to a screenshot comparison:
   `script/capture_app_window.sh` before and after the press, and visually
   confirm the frame now renders cropped/magnified rather than fit-to-pane.
3. Press `z` again; capture another screenshot and confirm the frame returns
   to fit-to-pane.
4. Navigate to `commons-armstrong-gemini8.jpg`. Wait briefly for
   `refreshCloseUps` to populate (poll `script/ax_drive.sh find
   --accessibilityLabel "Face close-ups"` — the Close-Ups panel only renders
   when `closeUpCrops` is non-empty, `LibraryGridView.swift:3707`). If the
   panel never appears, the frame has fewer detections than Wikipedia's
   subject count would suggest — note this and pick a different multi-face
   fixture from the manifest rather than asserting on nothing.
5. Press shift-`Z`. Capture a screenshot; the crop should now be centered on
   whichever face `LoupeFaceZoomTargeting.nearestFaceIndex` picked (nearest
   to image center on first press).
6. Press shift-`Z` again. Capture another screenshot; the crop should visibly
   move to a **different** region of the frame (the next face, wrapping via
   `wrappedIndex`).
7. Press shift-`Z` a third time on a two-face frame; the crop should wrap
   back to the first face's region (same as step 5's screenshot).

## Expected
- Step 2/3: the loupe image visibly changes scale between the two
  screenshots (magnified vs fit). **Fails if** the two screenshots are
  pixel-identical (toggle did nothing) — screenshot diff is the only
  falsification available here (see Sharp edges).
- Step 4: the Close-Ups panel (`accessibilityLabel "Face close-ups"`) appears
  for a frame with 2+ people. **Fails if** it never appears within a few
  seconds on `commons-armstrong-gemini8.jpg` — face detection may need a
  different fixture, or the analyzer found <1 face; do not force an
  assertion past a real "no faces detected" result.
- Step 5/6: three shift-`Z` presses on a two-face frame produce a
  first-face crop, a visibly different second-face crop, then back to the
  first-face crop again. **Fails if** the crop never moves between presses
  (cycling isn't wired) or drifts to a third, non-existent target on a
  two-face frame (index math wrong).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **No AX-assertable zoom-state signal in the plain loupe.** `model.loupeZoomFocus`
  drives only pixel-level rendering in the standard loupe view; there is no
  accessibility label/value that mirrors it there. The only place the app
  exposes this state as text is the **A/B compare pane's header button**
  (`LibraryGridView.swift:5859-5865`), whose label reads `"Zoom 1:1"` when
  unzoomed and `"Fit"` when zoomed — and it reads the *same* shared
  `model.loupeZoomFocus`. A more rigorous re-run of this card could press `z`
  in the loupe, then press `B` to switch to A/B compare, and assert that
  button's label reflects the state `z` just set — that is a real,
  AX-driven cross-check this draft didn't attempt live. Absent a live run,
  this card falls back to screenshot diffing, which is honest but weaker
  than a text assertion.
- **Face-zoom targets are not persisted** — this feature and `face_observations`/
  `person_assets` are unrelated pipelines; don't cross-check this card
  against People-workspace tables.
- Face detection quality depends on `CoreImageFaceExpressionAnalyzer` finding
  faces in real (non-synthetic) JPEGs — this is why the card requires
  `--faces`, not `--smoke` (synthetic smoke frames are flat generated images
  with no faces to detect).

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md.
