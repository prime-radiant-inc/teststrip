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

## Run status

**2026-08-01 LIVE RUN, app `feat/face-report-cards` @ `87b76824`, VM
`teststrip-e2e`, seed `facestack`. Verdict: BLOCKED — a real, cleanly
reproduced app bug in the preview-generation-completion plumbing prevents
`FaceReportStore` from ever being fed, so Steps 2-7 could not be
meaningfully exercised. Step 1 and Step 8 pass on their own merits.**

- **Step 1 — PASS.** `sql facestack "SELECT original_path,
  json_extract(technical_metadata_json,'\$.capturedAt') FROM assets ORDER BY
  2 LIMIT 5;"` returned `stack-1-face.jpg` (1767268800), `stack-2-face.jpg`
  (1767268801), `stack-3-two-faces.jpg` (1767268802), `stack-4-noface.jpg`
  (1767268803), then `commons-aldrin-portrait.jpg` (1767272400) — exactly
  1s apart for the four stack frames, then ~3597s (~1hr) to the next asset.

- **Steps 2, 4, 5, 6, 7 — BLOCKED (app bug).** After selecting
  `stack-1-face.jpg` (via Library grid `ax press --role AXButton --label
  "stack-1-face.jpg"` then ⌘1 to Cull — the same selection technique
  `cull-012-closeups-panel.md`'s live runs use), the close-ups panel showed
  `"Not read yet"` and **never cleared**, even though:
  - `.medium`/`.large` previews for `stack-1-face.jpg`
    (`0F738826-31B5-403F-97F0-F140F76FDF12`) existed on disk within **9
    seconds** of selection (confirmed via `ls` timestamps against a `date
    +%s` baseline taken at selection time).
  - A lock-step poll (AX state + `ls` of the preview directory, every ~1-2s)
    over the following **99 seconds** (55 polls total) showed the files
    present from poll 1 onward, while `ax find --contains "Not read yet"`
    matched on every single poll with zero recovery.
  - Reselecting away (Stack frame 2) and back (Stack frame 1) — which forces
    a brand-new `.task(id: CloseUpsRefreshKey(...))` instance regardless of
    generation — did not clear it either.
  - A raw `AXUIElementCopyAttributeNames` dump of the `Face close-ups`
    `AXGroup` confirmed the app's own accessibility layer reports
    `AXValueDescription = "Faces not read yet"` at the end of that window —
    not a card-driving artifact.
  - The **rail dots are equally affected, including on frames that never
    needed a live-generated preview**: `stack-2-face.jpg`
    (`BBD642DD-420C-40C6-8916-1894C2E6C0F6`) already had a qualifying
    `large.jpg` cached (from `prefetchLoupeNeighborLargePreviews`'s warm of
    the selected frame's neighbor), yet a raw AX dump of its "Stack frame 2"
    button showed `AXValue = "Not selected"` — no `Faces …` segment at all.
    Neither `ax find --contains "Faces clean"` /`"Faces check"`/`"Faces
    ruined"` matched anywhere in the whole AX tree for the entire session.
  - **Control test, isolating the mechanism**: killing the app and
    relaunching it (`open -n`) against the **same, already-populated** run
    directory (previews already on disk from the very first frame, no
    mid-session generation needed) rendered the report correctly on the
    **very first poll** (`"Not read yet"` cleared immediately). This
    isolates the defect to *previews that complete while the asset is
    already selected/rendered*, not to the analyzer, the store, or the
    presentation layer — those all work correctly the instant they're given
    a chance to run.
  - **Most likely locus** (from reading, not instrumented/proven): both
    consumers — `closeUpsRail`'s `.task(id: CloseUpsRefreshKey(...))`
    (`LibraryGridView.swift:3922-3926`) and `cullingStackRail`'s `.task(id:
    faceReportSweepKey(for:))` (`:4903`, key built at `:4924-4932`) — are
    re-keyed on `model.previewCacheGeneration(for:)`
    (`AppModel.swift:9386-9388`, reading `previewCacheGenerationsByAssetID`)
    and `model.faceReportPreviewSource(for:)` (`:14146-14159`, itself
    memoized in `faceReportPreviewSourceCacheByAssetID`). Both of those
    reads are only refreshed by `flushBackgroundWorkPublication`
    (`:10309-10321`, which calls `clearPreviewLookupCaches()` at `:10323-10327`
    and copies `currentPreviewCacheGenerationsByAssetID` into the published
    map), which itself only runs off worker-completion-driven
    `publishBackgroundWorkState()` calls. Since a from-disk cold read (the
    control test) works immediately, the analyzer/store/presentation code
    Tasks 0-7 own is not implicated — the gap is in this shared
    completion-tracking plumbing that predates this feature (`AppModel.swift`
    is pre-existing infrastructure), and this card is simply the first
    consumer whose correctness depends entirely on that one generation
    number changing with no other fallback re-render trigger.
  - Because neither the panel nor any rail dot ever populated for any
    frame, Steps 4 ("N faces, `<word>`" header), 5 (frame 2/3 dots vs. frame
    4 absence), 6 (composite prominence cap), and 7 (panel/rail agreement)
    could not be meaningfully exercised — there was nothing to read. Frame
    4's dot absence in this state is real but vacuous (every frame lacked a
    dot, not just frame 4), so it does **not** count as a passing
    falsification leg.

- **Step 3 — not reached** (no tile ever rendered to dump).

- **Step 8 — PASS**, independent of the block above:
  `evaluation_signals`/`face_observations`/`person_assets` all read `0`,
  and `ls .../FaceStackOriginals/*.xmp` matched nothing. Nothing was
  written regardless of the stuck report state.

**No production code was changed** (per instructions: app bug → BLOCKED
with evidence, no fix attempted here). Sharp edge encountered mid-run, noted
for future drivers: this VM has live internet access and its Sparkle
auto-updater found a real published release (0.2.0 > the running 0.1.0),
popping a modal "A new version of Teststrip is available!" dialog
unprompted at least once during this session — dismiss with `ax press
--role AXButton --label "Remind Me Later"` before driving further, and
treat its possible reappearance as a standing hazard for any future VM
scenario run, not specific to this card.

---

**2026-08-02 LIVE RUN (Round 2), app `feat/face-report-cards` @ `5b44634d`,
VM `teststrip-e2e`, seed `facestack`. Verdict: PASS — all 8 steps pass.**

The 2026-08-01 BLOCKED verdict above named a specific next step: add live
instrumentation and redrive to see directly whether the two symptomatic
`.task(id:)` closures actually re-fire. That was done (temporary
`NSLog`-based instrumentation, since removed) and it **refuted** the
hypothesis it was written to test: `CloseUpsRefreshKey`'s computed value did
change after the generation bump, and its `.task(id:)` closure did re-fire,
calling `refreshCloseUps` with a valid, non-nil `.large` preview source. The
close-ups pass and the stack-rail sweep were both correctly triggered every
time. The actual defect was one layer deeper: `refreshCloseUps`'s and
`FaceReportStore.sweep`'s `Task.detached` blocks both call
`CoreImageFaceExpressionAnalyzer().detectFaces(previewURL:)` — CIDetector
created with `context: nil`, not documented safe for concurrent access from
multiple threads — with no synchronization between them, and can be
mid-analysis for the same frame at the same time. A standalone reproduction
independent of all Teststrip code (a bare Swift binary calling `CIDetector`
concurrently via `Task.detached`) confirmed this **deadlocks outright** (0%
CPU, no progress, ever) at concurrency 4+ on this VM, while a single
sequential call completes in well under a second — this explains why the
live symptom over 55 polls/99 seconds showed zero recovery (a true hang, not
slowness) and why the earlier 2026-08-01 run's "control test" (relaunching
against an already-populated run directory, so no concurrent
worker-completion-triggered sweep restarts piled up) worked on the first
poll. Fix: `FaceDetectionGate`, a new actor in `FaceReportStore.swift`,
serializes every `CoreImageFaceExpressionAnalyzer` call this feature makes —
`FaceReportStore.analyzeCachedPreview` and `LoupeView.refreshCloseUps` both
now route through `FaceDetectionGate.shared`, making "at most one call in
flight" structural rather than incidental. (Production's
import/evaluation pipeline was never at risk — it already serializes the
same analyzer, but only incidentally, via `AppCatalog
.managedWorkerKindRunningLimits[.recognition] == 1`, an unrelated policy
this feature's direct app-process calls bypassed entirely.) See
`.superpowers/sdd/2026-08-01-face-report-cards/blocker-fix-report.md`,
"Round 2 (live instrumentation)" for the full evidence trail.

- **Step 1 — PASS.** Fixture ordering confirmed identical to the 2026-08-01
  run: `stack-1-face.jpg` (1767268800), `stack-2-face.jpg` (1767268801),
  `stack-3-two-faces.jpg` (1767268802), `stack-4-noface.jpg` (1767268803),
  then `commons-aldrin-portrait.jpg` (1767272400) ~1hr later.
- **Step 2 — PASS.** Selected `stack-1-face.jpg` (Library grid → ⌘1 to
  Cull). `ax find --contains "Face close-ups"` matched; `ax find --contains
  "No faces"` and `ax find --contains "Not read yet"` both matched nothing
  (exit 1) within seconds of selection — no stuck "not read yet" state.
- **Step 3 — PASS.** Raw AX dump of the `Face` tile's `AXValueDescription`:
  `"Clean, Eyes open, Smiling, Eyes 100%, Sharpness 63%, Facing 84%, Light
  93%"` — grade first, eyes state and smile, then all four chip readings
  (eyes, sharpness, facing, light) in fixed order, all `<NN>%`.
- **Step 4 — PASS.** `Face close-ups`'s `AXValueDescription`: `"1 face,
  Clean"` — count matches the frame's one detected face, never `"Faces not
  read yet"` or `"No faces"` once the tile rendered.
- **Step 5 — PASS.** Without ever selecting frames 2/3/4: raw dumps show
  `Stack frame 2` → `"Not selected, Faces clean"`, `Stack frame 3` →
  `"Not selected, Faces clean"` (the sweep reached both without a visit —
  the feature's headline claim), `Stack frame 4` → `"Not selected"` with
  **no** `Faces …` segment at all. Screenshot
  (`cull028-redrive-step5.png`, not committed) visually confirms a green
  dot on rail thumbnails 1-3 and none on thumbnail 4 — the falsification
  leg holds, stable, not "sometimes."
- **Step 6 — PASS.** Selected `stack-3-two-faces.jpg`: header rolled up to
  `"2 faces, Clean"`. Both individual face tiles graded `Clean` in this
  run (the composited background face did not independently grade
  `Ruined` this time), so the prominence cap itself wasn't adversarially
  exercised, but the stated assertion — 2 faces, never rolls up `Ruined`
  — holds.
- **Step 7 — PASS.** Frame 1: panel `"1 face, Clean"` vs. rail `"Selected,
  Faces clean"` — same grade word. Frame 3: panel `"2 faces, Clean"` vs.
  rail `"Selected, Faces clean"` — same grade word. Panel and rail agree
  in both cases.
- **Step 8 — PASS.** `evaluation_signals`/`face_observations`/
  `person_assets` all read `0` before and after steps 2-7; zero `.xmp`
  files found next to any stack original. Nothing was written.

Redrove independently 3 times from a fresh `launch facestack` (no shared
state) before this pass to confirm the fix isn't itself a lucky race: all 3
resolved the close-ups panel within 1 second of selection, 0 hangs.

Full foreground suite: `swift test` — 2366 executed, 5 skipped, 0 failures
(2365 baseline + 1 new `FaceDetectionGate` concurrency test). No
`AppCatalogTests` flake observed.

Cleaned up `~/teststrip-vm/run/facestack-*` and the ad-hoc diagnostic
binaries this round's investigation used (`/tmp/citest`, not committed —
lived only in the scratchpad and the VM's `/tmp`). Left the VM running.
