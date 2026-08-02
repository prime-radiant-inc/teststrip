# cull-028-face-report-cards: per-face report cards and burst-rail roll-up dots

**What this covers**: As a photographer culling a burst I want to see, per
face, whether the eyes are open, the face is sharp, the head is facing me, and
the light is right — and I want one traffic-light dot per rail thumb so I can
tell which frame has no ruined face *without visiting every frame*. SP-B of
`docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md`;
design in `docs/superpowers/specs/2026-07-31-per-face-report-cards-design.md`.

**Source**: `FaceReportAnalyzer` (`Sources/TeststripCore/Evaluation/FaceReportAnalyzer.swift`)
produces one `FaceReport` per CIDetector detection; `FaceReportStore`
(`Sources/TeststripApp/FaceReportStore.swift`) caches them per asset keyed on
`previewCacheGeneration` **and** the preview level they were measured at, and
sweeps the current stack's frames (current frame first, then rail order);
`closeUpsRail`/`closeUpCropCell`/`closeUpChips` and `cullStackRailCell` in
`Sources/TeststripApp/LibraryGridView.swift` render the header roll-up, the
per-tile corner dot and chip row, and the rail dots. Grading constants were
measured over this same corpus — see the frozen-constants table in
`docs/superpowers/plans/2026-08-01-per-face-report-cards-final.md`.

**No worker involvement.** Unlike `cull-012-closeups-panel.md`, this card needs
**no** Evaluate Matches pass, no `face_observations`, and no AuraFace CoreML
model: every number on screen comes from the app's own live CIDetector +
Vision pass over the cached preview. Do not wait on the worker.

**AX reality this card is built around.** Each face tile is an
`.accessibilityElement(children: .combine)`, which collapses the chips' own
labels — `ax find --contains "Sharpness 82%"` will NEVER match, exactly as
`cull-012-closeups-panel.md`'s 2026-07-29 run found live for the same
construction (see that card's lines 349-360: the composed string lands on
`AXValueDescription`, `AXValue` is absent entirely, and `ax_drive.sh`'s
`--contains` does not search `AXValueDescription`). Every chip assertion here
therefore reads the **tile's combined value** out of a raw attribute dump.
`FaceReportRollUpPresentation.tileAccessibilityValue` exists in exactly that
shape for exactly this reason: it repeats all four chip strings.

## Pre-state
```bash
script/vm_scenario_run.sh sync facestack
script/vm_scenario_run.sh launch facestack
script/vm_scenario_run.sh ax wait-vended Teststrip
```

The `facestack` seed is `sample-data/photos/faces` re-stamped with EXIF
capture times: four frames 1s apart form one burst stack —
`stack-1-face.jpg` and `stack-2-face.jpg` (real portraits, faces guaranteed
present, asserted at seed time), `stack-3-two-faces.jpg` (a composite with one
subject face above the prominence floor and one background face below it, both
asserted at seed time), and `stack-4-noface.jpg` (a synthetic flat frame with
**no** faces, the falsification leg) — and every other photo is an hour away,
so it stays a standalone stop.

## Steps

1. Confirm the fixture really is one four-frame stack before asserting
   anything about it:
   ```bash
   script/vm_scenario_run.sh sql facestack \
     "SELECT original_path, json_extract(technical_metadata_json,'\$.capturedAt') FROM assets ORDER BY 2 LIMIT 5;"
   ```
   Expect `stack-1-face.jpg`, `stack-2-face.jpg`, `stack-3-two-faces.jpg`,
   `stack-4-noface.jpg` in that order, 1s apart, then a fifth asset at least
   an hour later.

2. Switch to the Cull workspace (⌘1) and select `stack-1-face.jpg`. Wait for
   the close-ups panel, then read the rail:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "CLOSE-UPS"
   script/vm_scenario_run.sh ax find --contains "Face close-ups"
   script/vm_scenario_run.sh ax find --contains "No faces"       # expect exit nonzero
   script/vm_scenario_run.sh ax find --contains "Not read yet"   # expect exit nonzero
   ```
   If `Not read yet` matches and does not clear within ~10s, the frame has no
   cached preview at or above `FaceReportPreviewFloor` yet — poll
   `ax find --contains "Not read yet"` until it stops matching (re-asserting
   frontmost with `ax wait-vended` on every poll) before continuing.

3. **Chips, read off the tile's combined value.** Locate the tile, then dump
   its raw AX attributes — do **not** try to `--contains` an individual chip
   string:
   ```bash
   script/vm_scenario_run.sh ax find --label "Face"
   # then dump the matched element's attributes (AXValueDescription carries
   # the composed value; AXValue is absent for this construction)
   ```
   The composed value must match the shape
   `"<Clean|Check|Ruined>, Eyes <open|closed>[, Smiling], Eyes <NN>%, Sharpness <NN>%, Facing <NN|no read>, Light <NN>%"`
   — grade first, then eyes state and smile, then all four chip readings in
   the fixed order eyes, sharpness, facing, light. Assert every one of the
   four signal words is present in that single string, and that the four
   readings are either `<NN>%` or the literal `no read`.

4. **Panel header roll-up.** The `Face close-ups` element's accessibility
   value must be `"N faces, <Clean|Check|Ruined>"` for this frame — never
   `"Faces not read yet"` once tiles have rendered, and never `"No faces"`
   while a tile is on screen.

5. **Rail dots without visiting.** Without ever selecting frames 2, 3 or 4,
   read the stack rail cells' accessibility values:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Stack frame 2"
   script/vm_scenario_run.sh ax find --contains "Stack frame 3"
   script/vm_scenario_run.sh ax find --contains "Stack frame 4"
   ```
   Frames 2 and 3 must each carry a `Faces clean|check|ruined` segment (the
   sweep reached them without a visit). Frame 4 must carry **no** `Faces`
   segment at all, and no dot may be drawn on its thumb — capture a
   screenshot and confirm the absence visually:
   ```bash
   script/vm_scenario_run.sh shell 'cd ~/teststrip-vm && ./script/capture_app_window.sh Teststrip'
   ```

6. **The prominence cap, live.** Select `stack-3-two-faces.jpg`. Its panel
   header must report **2 faces**, and its rail dot and header grade must be
   `Clean` or `Check` — **never** `Ruined` — even if the composited
   background face's own tile shows a ruined signal. Dump both tiles' combined
   values and record the background tile's own grade word alongside the
   frame's roll-up.

7. **Panel and rail agree.** Back on frame 1, compare the grade word in the
   panel header value (step 4) with the grade word in frame 1's own rail-cell
   value. They must be the same word for the same frame. Repeat for frame 3.

8. **Nothing is written.** Capture catalog counts before step 2 and again
   after step 7:
   ```bash
   script/vm_scenario_run.sh sql facestack "SELECT count(*) FROM evaluation_signals;"
   script/vm_scenario_run.sh sql facestack "SELECT count(*) FROM face_observations;"
   script/vm_scenario_run.sh sql facestack "SELECT count(*) FROM person_assets;"
   ```
   and confirm no `.xmp` sidecar appeared next to any stack original:
   ```bash
   script/vm_scenario_run.sh shell 'ls ~/teststrip-vm/run/facestack-*/FaceStackOriginals/*.xmp 2>/dev/null | wc -l'
   ```

## Expected

- Step 2: the close-ups rail renders at least one tile for
  `stack-1-face.jpg`. **Fails if** `"No faces"` is present while a portrait is
  selected, or if `"Not read yet"` never clears.
- Step 3: the tile's combined value carries the grade word, the eyes state,
  and all four signal readings in the fixed order. **Fails if** any of the
  four words is missing from that string (a missing chip would read as a clean
  signal), if an unmeasured signal shows `0%` instead of `no read`, or if the
  string mentions a smile glyph in the chip positions (smile is a separate
  segment, never a chip).
- Step 4: the header value is `"N faces, <word>"` with N matching the frame's
  detected face count.
- Step 5: frames 2 and 3 carry a `Faces …` segment; frame 4 carries none and
  shows no dot. **Fails if** frames 2/3 have no `Faces …` segment (the sweep
  never reached an unvisited frame — the feature's headline claim), **and
  equally fails if** frame 4 *does* get a dot (absence turned into "known
  good").
- Step 6: the composite frame reports 2 faces and rolls up to at worst
  `Check`. **Fails if** it rolls up `Ruined` — that would mean a background
  face below the prominence floor graded the frame red, breaking the
  prominence-weighted roll-up the whole design rests on.
- Step 7: the two grade words are identical for each frame tested. **Fails
  if** the panel and the rail disagree — they must come from one computation
  through one staleness-checked accessor.
- Step 8: all three counts are unchanged and zero `.xmp` files exist. **Fails
  if** anything was written — per-face report cards are display-only and
  nothing here is a confirming gesture.

## Cleanup
```bash
script/vm_scenario_run.sh shell 'rm -rf ~/teststrip-vm/run/facestack-*'
```

## Sharp edges

- **Do not cross-check face counts against `face_observations`.** This card's
  numbers come from the app's own live CIDetector pass, which is a different
  detector from the worker's face pipeline and can legitimately disagree. The
  card deliberately never runs Evaluate Matches.
- **Never assert an individual chip with `ax find --contains`.** The tile
  combines its children, so per-chip labels do not survive into the AX tree.
  Steps 3, 6 and 7 read the tile's composed value from a raw attribute dump
  (`AXValueDescription`), the same technique `cull-012-closeups-panel.md` and
  `cull-024-honest-states.md` both had to fall back to.
- Frame 4's dot ABSENCE is the falsification leg. Do not weaken it to "the dot
  is grey" or "the dot is missing sometimes" — absence must be total and
  stable across the whole run.
- Report cards are only measured off a preview at or above
  `FaceReportPreviewFloor`. A frame showing `"Not read yet"` is not a bug
  unless it persists after its preview lands; grades that *changed* as
  previews upgraded would be the bug, and that is what the floor exists to
  prevent.
- The chip row is 4 × 17pt inside a 112pt tile. If it wraps or truncates in
  the screenshot, that is a real layout bug, not a card problem.
