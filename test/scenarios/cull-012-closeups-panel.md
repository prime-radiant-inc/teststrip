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

**Source (re-verified 2026-08-01, SP-B per-face report cards citation
sweep; gate citation re-verified 2026-08-09, unified-shell sweep — see Run
status)**: `cullFacesReadsPanel` at
`Sources/TeststripApp/LibraryGridView.swift:4002-4021` (an `HStack` of
`readsCard` + `closeUpsRail`), gated into the loupe body only `if
presentation.showsCullChrome && model.showsCullFacesPanel` at `:3796`;
`closeUpsRail` at `:4023-4075`; per-tile rendering (`closeUpCropCell`,
`closeUpChips`) at `:4200-4231`; `refreshCloseUps(for:)` at `:4321-4366`.
Each tile's composed accessibility value now comes from
`FaceReportRollUpPresentation.tileAccessibilityValue`
(`Sources/TeststripApp/FaceReportPresentation.swift`), not from
`CloseUpFacesPresentation` — that type dropped `eyesState`/`isSmiling`/
`sharpnessTone` and now owns only crop geometry (`Crop.faceIndex`/
`.pixelRect`) in `Sources/TeststripApp/CloseUpFacesPresentation.swift`. See
the 2026-08-01 Run-status reconciliation for the full before/after.

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
The same applies to the eyes/smile segments of each tile's accessibility
value — they come from the same live per-crop `DetectedFaceExpression`, so
they're always internally consistent with the crop they're attached to, but
not necessarily with `face_observations`. Sharpness is now measured
per-face over that face's own crop (`FaceReportAnalyzer`), not as a single
asset-level signal — see the 2026-08-01 Run-status reconciliation for the
retired exactly-one-face limit this paragraph used to describe.

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
   2026-07-10: 11 observations landed within ~10s of Evaluate Matches).
   **Fixture-gap correction (verified live 2026-07-28, app 878f1939): the
   current `sample-data/photos/faces` corpus has no such asset** — all 11
   assets are single-subject portraits and each yields exactly 1
   `face_observations` row (confirmed both by SQL `GROUP BY asset_id` and by
   viewing four of the source JPEGs directly). If the loop below finds
   nothing after the full budget, fall back to any single-face asset (e.g.
   `commons-glenn-senator-portrait.jpg`) for steps 2–4, and skip step 5's
   2+-crop/no-sharpness-dot sub-case as untestable against this fixture:
   ```bash
   for i in $(seq 1 60); do
     n=$(sqlite3 "$DB" "SELECT asset_id FROM face_observations GROUP BY asset_id HAVING count(*) >= 2 LIMIT 1;")
     [ -n "$n" ] && break; sleep 2
   done
   echo "$n"   # target asset id (empty if the fixture-gap above applies)
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # PA0, expect 0 (nothing confirmed yet)
   sqlite3 "$DB" "SELECT count(*) FROM person_faces;"    # PF0, expect 0
   sqlite3 "$DB" "SELECT count(*) FROM dismissed_faces;" # DF0, expect 0
   ```
2. Switch to the Cull lens (⌘1) and select that asset in the loupe. Wait for
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
3. **Switch to the Loupe lens (⌘3) — not the Grid lens (⌘2).** Under the old
   two-workspace shell, ⌘2 (Library) opened the Library's own loupe on the
   same asset: a genuine single-image view, just without cull chrome — so
   this step proved the panel is gated on cull chrome specifically, not
   merely on "is some per-asset detail view showing." The unified shell's
   ⌘2 now opens the **Grid lens** (thumbnails, no loupe at all); swapping in
   ⌘2 here would make the assertion trivially true for the wrong reason (no
   detail view of any kind is showing, so of course no face-crop rail
   renders). ⌘3 is the actual like-for-like successor: it opens the Loupe
   lens's `.libraryLoupe` view (`lib-013-library-loupe.md`) — the same
   plain-navigation, no-pick/reject-pills loupe the old Library workspace
   used — on the identical asset. `LoupePresentation.showsCullChrome = (mode
   == .loupe)` (`AppModel.swift:33`) is `false` for `.libraryLoupe`, exactly
   as it was for the old Library loupe, so this preserves the original
   test's meaning. With the same asset selected/open in the Loupe lens,
   assert the Close-Ups panel is **absent** (cull-chrome-only claim, gated at
   `LibraryGridView.swift:3796`):
   ```bash
   script/ax_drive.sh find --contains "Face close-ups"   # expect exit nonzero (not found)
   ```
4. Back in the Cull lens (⌘1), re-select the asset, wait for the panel again, then
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
5. **Per-face report card.** With the same asset still selected, inspect each
   face tile's accessibility value (`closeUpCropCell`'s
   `.accessibilityLabel("Face")`/`.accessibilityValue(...)`, composed by
   `FaceReportRollUpPresentation.tileAccessibilityValue`):
   ```bash
   script/ax_drive.sh find --role AXImage --label "Face"   # or whichever role SwiftUI exposes for .accessibilityElement(children: .combine) here — inspect the AX tree first
   ```
   Cross-check against ground truth: for a face tile, "Eyes closed" in the
   value must correspond to a live `DetectedFaceExpression` with **both**
   `leftEyeClosed`/`rightEyeClosed` true (not independently queryable from
   the catalog — this is in-memory-only detection, so cross-check by eye
   from the crop image itself, not sqlite). Every tile carries all four chip
   readings (eyes, sharpness, facing, light) regardless of face count — the
   old single-face-only sharpness limit this step used to assert is retired
   (see the 2026-08-01 reconciliation below); do not re-assert "no crop shows
   Sharp/Soft with 2+ faces".

## Expected
- Step 2: the Close-Ups rail renders with at least one 112x112 crop while in
  the Cull lens on an asset with detected faces. **Fails if** the rail
  never appears despite a `--faces` asset with confirmed multi-face
  `face_observations`, or if it still shows the "No faces" empty-state value
  (zero crops).
- Step 3: the rail is completely absent from the Loupe lens's loupe for the
  identical asset — a genuine per-asset detail view, just not the Cull
  lens's. **Fails if** it renders there — that would contradict the
  "Cull-chrome-only" claim in the gate at `LibraryGridView.swift:3796`
  (`showsCullChrome = (mode == .loupe)`, `AppModel.swift:33`, `false` for
  `.libraryLoupe`).
- Step 4: `person_assets`/`person_faces`/`dismissed_faces` counts are
  identical before and after interacting with a crop (`PA1==PA0`,
  `PF1==PF0`, `DF1==DF0`). **Fails if** any count changed — that would be a
  confirm-before-write violation per CLAUDE.md (machine-derived face data
  written without an explicit confirming gesture). This assertion holds
  regardless of whether the click was a no-op; a no-op click passing this
  step trivially is fine and expected given the source reading in this card.
- Step 5: the eyes/smile segments of each tile's composed accessibility value
  match the tile's own crop detection. **Fails if** a segment contradicts the
  crop it's attached to. The old "sharpness dot on exactly one crop, none
  with 2+ faces" assertion is retired (see the 2026-08-01 reconciliation
  below) — sharpness is now a per-face chip on every tile, asserted by
  `cull-028-face-report-cards.md` instead.

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
  `LibraryGridView.swift:4200-4223`, `closeUpCropCell`) — if `ax_drive.sh find --role AXImage`
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
**2026-07-28 re-run, app `fix/cull012-bugs` @ `af4d104c`, VM `teststrip-e2e`
(fresh `launch faces`), seed `faces`. Verdict: PARTIAL PASS — 2 of 3 prior
bugs fully fixed, the CPU-storm fix is incomplete (narrower real gap found).**
All 5 steps pass on their literal assertions (same fixture-gap substitution
as before: no asset in this corpus has 2+ `face_observations`; additionally
this run found `face_observations` empty for *all* assets because the
AuraFace CoreML identity-embedding model wasn't present in this VM sync —
an environment/packaging gap, not a regression, and irrelevant to the
close-ups rail since it runs its own live `core-image-faces` detection pass
independent of `face_observations`, confirmed still populated normally).

**Kata #17 (sticky "No faces") — FIXED.** Drove the exact repro precisely:
Cull loupe (crop renders) → ⌘2 explicitly through Library **Grid** (confirmed
via screenshot, not skipped) → Library **Loupe** on the same asset (rail
absent, confirmed) → ⌘1 back to Cull. The rail correctly repopulated the
crop + marks immediately — no "No faces" stuck state. Matches the
`LoupeContentKey(assetID:showsCullChrome:)` fix at `LibraryGridView.swift:3894`.

**Kata #16 (ghost crop) — FIXED.** Screenshot of the run strip's 2-frame
stack stop shows the count badge now rendering as a small dark circle
directly on the bottom-right corner of the stack's own thumbnail — no
floating ghost image outside the strip, no ballooned stop, normal row
height. Matches the `.overlay`-based badge fix.

**Kata #15 (CPU peg) — PARTIALLY FIXED; a real, narrower gap remains.** The
dominant failure mode from the original run (95-99% CPU, continuous,
non-recovering for 40+ minutes across *all* stale assets simultaneously) is
gone: with the same live precondition reproduced (5/11 assets stale,
`preview_generation_queue` populated), CPU repeatedly returned to a clean
**0.0%** on both app and worker after each burst of activity, confirmed
across three independent idle windows (a 2-min pure-SSH-only window with zero
AX interaction, a 2-min window with periodic `ax wait-vended` polling, and a
single isolated `wait-vended` check) — it never failed to settle. `attempt_count`
also now advances instead of pinning at 0 (the headline fix), confirmed live.

However: `attempt_count` for the currently-selected asset and its immediate
run-strip neighbors climbed **0 → 7 → 9 with no ceiling** across four
ordinary navigation events (select, ⌘2/⌘1 round-trip, arrow-key next/prev) —
well past the stated 3-attempt cap, and CPU visibly spiked to 12-20% during
each such burst before settling back to idle. Root cause (read from the exact
deployed source, `.worktrees/cull012-bugs` @ `af4d104c`):
`AppModel.requestVisibleLoupeAssetPreview`/`prefetchLoupeNeighborLargePreviews`
(`AppModel.swift:9283-9315`) are a separate dispatch path from the one the
kata #15 fix covers (`CatalogRepository.pendingPreviewGenerationItems`/
`enqueuePendingPreviewGeneration`). They gate only on `.offline`/`.missing`
(`refreshAvailability`, `:9291`) and `requiresCachedPreviewOnly`
(`:14423-14430`, deliberately still `false` for `.stale` per the fix's own
diagnosis, to preserve a manual retry affordance) — neither excludes
`.stale`, and neither path checks `attempt_count` before calling
`requestPreview` (`:8940-8982`, which only dedupes against an *active*
in-flight item, not exhausted-retry history). The result: simply
selecting/paging to/near a stale asset — ordinary use, not an explicit
"retry" gesture — re-dispatches a guaranteed-to-fail worker request every
time, unbounded. This does **not** reproduce the original symptom (it
settles to idle between events, never pegs continuously) but it does violate
the retry-cap invariant the fix's own unit tests assert, and it wastes a
worker round-trip plus a reload-class UI refresh on every revisit. Evidence:
`preview_generation_queue` attempt_count readings and `ps` CPU samples in
`.superpowers/card-runs/cull-012-rerun.md`.

No app code was changed (verification only, per instructions). Full report:
`.superpowers/card-runs/cull-012-rerun.md`.

---

**2026-07-28, live run, app 878f1939, VM `teststrip-e2e`, seed `faces`.
Verdict: PARTIAL PASS.** Steps 1 (with a fixture-gap substitution), 2, 3,
and 5 pass on their literal assertions; step 4's negative-write assertion
(`person_assets`/`person_faces`/`dismissed_faces` stay `0/0/0`) passes
cleanly, but its "re-select the asset, wait for the panel again" sub-step
hit a real, precisely-reproduced app bug: after Cull→Library→Cull on the
*same* asset, the rail got stuck at the "No faces" empty state for 3+
minutes (never self-resolving), even though the identical asset had just
rendered correctly, and plain next/prev navigation within Cull continued to
repopulate the rail correctly for other assets throughout. Two further app
bugs were found and documented with screenshot/`sample`/SQL evidence: (a)
sustained ~95-99% single-core CPU pegging in a SwiftUI `SystemSegmentedControl`
relayout thrash that persists across workspace/view switches and degrades
every `ax find`/`ax press` call to 5-20+ minutes; (b) a persistent orphaned
face-crop image (a different, never-selected asset's content) rendered
floating outside the rail's frame for the entire ~40-minute session. No app
code was changed. Full report:
`.superpowers/card-runs/cull-012-run.md`.

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

**Reconciled 2026-07-29 (reads-card glyph-line, docs-only, not a live
run)**: grepped this card for "No read yet", "early read", "Reads", and
per-kind percentage probes — this card makes **no** assertions about the
Reads card's own state; it only cites `readsCard` as a layout fact (the
faces+reads panel is an `HStack` of `readsCard` + `closeUpsRail`, Source
above) and never probes what the Reads card renders. That state-gating
contract is fully owned by `cull-024-honest-states.md`. Flagging the one
load-bearing interaction for whoever next drives this card live: the
`faces` fixture's assets are single-subject portraits that yield **exactly
one** `face_observations` row each (Source above), and once Step 1's
Evaluate Matches pass runs, the same asset typically yields exactly one
`faceQuality`/`eyeSharpness` `evaluation_signals` row too (the signal Step
5 reads for the sharpness dot) — i.e. `kindCount == 1`, face-specific. As
of the 2026-07-29 reads-card glyph-line change
(`CullReadsCardPresentation.swift:86-98`), a lone signal of *any* rankable
kind — face-specific included — is a genuine PARTIAL read (one glyph, e.g.
`Face NN%`/`Eye sharp NN%` per `word(for:)`,
`CullReadsCardPresentation.swift:37-48`, plus the `"early read — 1 signal"`
caveat). The pre-2026-07-29 fallback to `"No read yet"` for a lone
face-specific signal is retired. So the Reads card immediately to this
rail's left will show that partial read for these assets during a live
run, not `"No read yet"` — expected, not a regression, and still out of
scope for this card's own assertions.

**LIVE RUN 2026-07-29, app `4b2c6db6` (reads-card glyph-line build),
`teststrip-e2e` VM, fresh `launch faces`. Verdict: PASS on all 5 card
steps; corrects a wrong prediction in the 2026-07-29 doc-only reconciliation
just above; plus one Step 5 AX-methodology finding (a card-driving gap, not
an app bug).** Same fixture gap as every prior run: no `faces` asset has 2+
`face_observations` — substituted `commons-glenn-senator-portrait.jpg`
(`3A228732-1A55-41E6-868E-F6676A956D9E`) for Steps 2-5, per the card's own
fallback.
- Step 1: `person_assets`/`person_faces`/`dismissed_faces` = 0/0/0
  confirmed before any interaction (PA0/PF0/DF0 baseline).
- Step 2: `ax wait --contains "CLOSE-UPS"` succeeded; `ax find --contains
  "Face close-ups"` found; `ax find --contains "No faces"` did not match —
  crop rendered. **PASS.**
- Step 3: ⌘2 to Library, confirmed same asset in Library's plain Loupe
  (`ax find --contains "Loupe"`/`"Library Loupe"`/`"senator-portrait"` all
  matched); `ax find --contains "Face close-ups"` did not match — rail
  absent. **PASS.**
- Step 4 (+ kata #17 regression re-check): ⌘1 back to Cull — rail
  immediately repopulated with the crop (`Face close-ups` found, `No faces`
  not found) — no sticky-empty-state regression. Attempted the crop-click
  gesture (`ax press --contains "Face close-ups"` succeeded, landing on the
  rail section rather than a specific crop button — matches the card's own
  prediction that `Image(decorative:)` carries no button/tap target).
  `person_assets`/`person_faces`/`dismissed_faces` stayed 0/0/0 both before
  and after. **PASS**, negative-write assertion holds.
- Step 5: on-face marks for the one rendered crop (eye-open glyph, smile
  glyph, green sharpness dot — visible in screenshot) matched ground truth:
  `eyesOpen` = 1.0 (open, not closed); the source photo shows the subject
  smiling; `faceQuality` = 0.6071 >= `faceQualityStrongThreshold` (0.45,
  `LibraryGridView.swift:6151`) → Sharp (green dot). **PASS on
  substance** — but see the AX-methodology finding below: the exact
  accessibility value needed a raw attribute dump, not `ax_drive.sh find
  --contains`.
  - **AX-methodology finding (a card-driving gap, not an app bug):** the
    crop cell's `.accessibilityElement(children: .combine)`
    (`LibraryGridView.swift:4147-4149`) sets `.accessibilityLabel("Face")`
    and `.accessibilityValue("Eyes open, Smiling, Sharp")` — `--label
    "Face"` matches (Title carries the label), but `ax find --contains
    "Eyes open"`/`"Smiling"`/`"Sharp"` all failed to match, exactly as this
    card's own (previously unconfirmed) Sharp-edges caution anticipated. A
    raw `AXUIElementCopyAttributeNames` dump of the matched element
    confirmed why: the composed value lands on `AXValueDescription` (`=
    "Eyes open, Smiling, Sharp"`, matching ground truth exactly), with
    `AXValue` absent from the attribute list entirely and `AXRole =
    AXUnknown` — the same SwiftUI-AX bridging quirk
    `cull-024-honest-states.md`'s Sharp edges documented for the Reads
    panel container's `.accessibilityElement(children: .contain)`, now
    confirmed live on this card's `.combine`-children construction too.
    `ax_drive.sh`'s `--contains` search never inspects `AXValueDescription`
    (same root cause as cull-024). A future run of this card's Step 5 needs
    a raw AX-attribute dump (or an `ax_drive.sh` enhancement to also hay
    over `AXValueDescription`) to verify the marks' value text; `--label
    "Face"` alone confirms the element exists but proves nothing about
    which marks it carries.

**Reads-leg finding (corrects the 2026-07-29 doc-only reconciliation just
above — this is the task-4 brief's "load-bearing check"):** that
reconciliation predicted Step 1's **Evaluate Matches** pass alone would
leave this fixture's asset at `kindCount == 1` (face-specific only).
**Live-verified false**: triggering Evaluate Matches on a fresh `launch
faces` produced **all seven** rankable kinds simultaneously for every one
of the 11 assets (confirmed via `GROUP BY asset_id`, `kindCount = 7`
uniformly, catalog-wide) — tight SQL (0.5s) and AX (~1s) polling from the
moment the menu item was pressed never caught an intermediate face-only
state; whole-photo and face-specific signals land together under this
trigger.

The real, live-confirmed trigger for the face-only window is a
**different** menu item: **People ▸ Scan for Faces**
(`requestPeopleFaceScan()`, `main.swift:389-393`/`402-408` — apple-vision
only, distinct from `evaluateCurrentScope()`/Evaluate Matches). On a fresh
`launch faces`, selecting `commons-glenn-senator-portrait.jpg` and running
Scan for Faces produced exactly one rankable signal (`faceQuality =
0.60713`) and zero whole-photo or other face-specific signals (confirmed
via SQL: only `faceCount`/`faceQuality`/`object`/`visualSimilarity` rows,
`kindCount = 1`). Live AX matched the load-bearing prediction exactly:
`"No read yet"` no longer matched, `"early read — 1 signal"` matched,
exactly one glyph (`"Face 61%"`) matched, `"Keep"`/`"Toss"` did not match,
and **none** of the other six kind-words (`Focus `/`Motion `/`Framing
`/`Looks `/`Eyes `/`Eye sharp `) matched — confirming the retired-fallback
change holds for a lone face-specific signal exactly as
`cull-024-honest-states.md` describes. Screenshot evidence captured.
Subsequently ran Evaluate Matches on the same asset (now `kindCount = 7`)
and confirmed the face glyph joins the whole-photo glyphs as a second line:
`Focus 60%`/`Motion 60%`/`Framing 60%`/`Looks 49%` on line one, `Eyes
100%`/`Face 61%`/`Eye sharp 43%` on line two; independently computed
`normalizedQualityRead ≈ 0.6464` (between the 0.5 Toss and 0.7 Keep
thresholds) → predicted Mixed (no verdict text) → live confirmed neither
`"Keep"` nor `"Toss"` matched. Screenshot evidence captured. The
whole-photo line was truncated on screen the same way
`cull-024-honest-states.md`'s Step-4 screenshot was (`Foc…`/`Mot…`/`Fra…`
/`Loo…`) — same width-truncation finding, not re-litigated here. **This
fully exercises the `kindCount == 1` face-specific PARTIAL-read branch that
`cull-024-honest-states.md`'s own `burst` fixture cannot reach (see that
card's LIVE RUN 2026-07-29 entry) — together the two runs are a live proof
of the entire glyph-line change's three-state contract across both
fixtures.**

**Reconciled 2026-07-30 (2+2 width-truncation fix superseded the layout
description above, docs-only, not a live run)**: the "Reads-leg finding"
entry above (the `kindCount = 7` paragraph) predates the 2+2 width-
truncation fix and describes the whole-photo glyphs as rendering "as a
second line" together on one line ("`Focus 60%`/`Motion 60%`/`Framing
60%`/`Looks 49%` on line one, `Eyes 100%`/`Face 61%`/`Eye sharp 43%` on
line two") — that historical entry is left as written, since it's an
accurate record of what that run observed at that commit, but its layout
claim no longer matches current behavior: `readsCard` now splits
`wholePhotoGlyphEntries` across two lines itself (`.prefix(2)`/
`.dropFirst(2)`, `LibraryGridView.swift:4218-4219`), so this same
`kindCount = 7` frame would render three lines today (two whole-photo +
one face), not two, and the truncation that entry found is the same issue
`cull-024-honest-states.md`'s matching "Reconciled 2026-07-29 (2+2
width-truncation fix...)" entry addressed for that card — see that entry
for the fix's mechanism. Not re-verified live against this exact commit on
this card's `faces` fixture.

**Reconciled 2026-07-30 (final glyph-line branch review — citation
re-sweep, docs-only, not a live run)**: this card's Source section (whole
`cullFacesReadsPanel`/`closeUpsRail`/`closeUpCropCell`/`refreshCloseUps`
citation block) had drifted from several intervening `LibraryGridView.swift`
changes since its 2026-07-17 re-verification, unrelated to this branch's
own edits — every citation was re-verified by directly reading the cited
lines at this branch's final HEAD (see the updated Source section above;
the `faceQualityStrongThreshold` citation in the LIVE RUN 2026-07-29 entry
was similarly fixed to `:6151`, previously `:6137`, in the prior commit).
Historical Run-status entries were otherwise left untouched.

---

**Reconciled 2026-08-01 (SP-B per-face report cards, docs-only, not a live
run)**: the compact on-face marks this card described — an `eye`/`eye.slash`
glyph, a conditional `face.smiling` glyph, and a green/orange sharpness dot
attached only when the asset had exactly one face crop — are **retired**. Each
tile now carries a corner traffic-light dot plus an always-on row of four
icon-in-donut chips (eyes, sharpness, facing, light), all four rendered every
time; because the tile still combines its children for accessibility, the
per-chip readings are repeated inside the tile's own composed value
(`"<Grade>, Eyes <open|closed>[, Smiling], Eyes NN%, Sharpness NN%, Facing
NN%, Light NN%"`), which is the only string a live driver can read. Smile is
a segment of that value, never a chip. The single-face-only sharpness
attribution limit is gone with it: sharpness is now measured per face over
that face's own crop (`FaceReportAnalyzer`), so a 2+-face frame shows a
sharpness chip on **every** tile — the old "no crop shows Sharp/Soft with 2+
faces" assertion in Step 5 and Expected step 5 is superseded and must not be
re-asserted. `CloseUpFacesPresentation` no longer has `eyesState`,
`isSmiling`, `sharpnessTone`, or a `wholePhotoSignals:` parameter; it owns
crop geometry plus a `faceIndex` pairing only. Two further behavior changes
this card's future runs will see: the panel's body text is now driven by the
report store rather than by the crop list (so a frame whose faces are all too
small to crop reads "Faces too small to crop", not "No faces"), and report
cards are only measured off a preview at or above `FaceReportPreviewFloor`, so
a freshly-selected frame can briefly read "Not read yet". Everything else this
card covers is unchanged: the 112px crop size, the Cull-chrome-only gate, the
`"No faces"` empty state for a genuinely faceless frame, and the
display-only/nothing-persisted behavior. The replacement assertions live in
`cull-028-face-report-cards.md`.

---

**Reconciled 2026-08-09 (Task 13, unified-shell push — load-bearing, not a
mechanical preamble swap)**: Steps 2-4 are this card's actual test, not a
preamble to it — the ⌘1/⌘2 round trip proves the Close-Ups rail is gated on
cull chrome specifically, by showing the identical asset in two different
single-image views and asserting the rail only renders in one of them. A
mechanical "⌘2 → Grid lens" swap would have broken that: the unified shell's
⌘2 now opens the **Grid lens** (`.grid`, a thumbnail grid, no per-asset loupe
at all), so Step 3 would trivially pass for the wrong reason — no detail
view of any kind is showing, not "cull chrome absent from a detail view."
Rewrote Step 3 to press **⌘3 (the Loupe lens)** instead: it opens
`.libraryLoupe`, the direct successor to the old Library workspace's loupe
(`lib-013-library-loupe.md`) — same plain-navigation, no-pick/reject-pills
single-image view, same asset, just reached via a different key. Verified
`LoupePresentation.showsCullChrome = (mode == .loupe)` (`AppModel.swift:33`)
is `false` for `.libraryLoupe`, exactly as it was `false` for the old
Library loupe's equivalent state — so the round trip's *meaning* is
unchanged: two different loupes on the same asset, one with cull chrome, one
without, and only one renders the rail. Also corrected the gate's own line
citation, drifted from `:3903` to its real location at
`LibraryGridView.swift:3796` (`if presentation.showsCullChrome &&
model.showsCullFacesPanel`), verified by direct read rather than trusting
the prior number. Steps 1 and 5 are unaffected (no lens keys). Historical
Run-status entries above (the 2026-07-28/07-29 live runs) describe what
those runs actually drove under the pre-unified-shell build and are left
as-is per this file's own precedent for historical entries. Supersedes
prior status: every live run recorded above drove the old ⌘2-into-Library-
loupe round trip, which no longer exists — none of that evidence covers
Steps 2-4 as now written. Needs a fresh VM run.
