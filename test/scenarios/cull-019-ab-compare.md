# cull-019-ab-compare: A/B head-to-head — panes, contender resolution, synced zoom, keep-decision write

**What this covers**: as a photographer culling a shoot I want to put two
nearly identical frames head-to-head with synced zoom so that I can compare
focus precisely and commit one keep/reject decision for the pair. Covers
inventory items 63-68:

- Item 63 — `ABComparePresentation` (`LibraryGridView.swift:5392-5454`:
  `primaryAsset`/`contenderAsset`, `canCompare`, `positionText` = "Comparing
  X vs Y" / "Need two frames to compare") and `ABCompareView`
  (`LibraryGridView.swift:5807-6037`: header → two panes → keep bar →
  filmstrip).
- Item 64 — contender resolution order override → recommended → neighbor:
  `ABComparePresentation.resolveContender`, `LibraryGridView.swift:5420-5442`
  (NOT in AppModel as an older digest claimed). Neighbor = next asset after
  the anchor, else the previous one; each tier is skipped if it would equal
  the primary's id.
- Item 65 — filmstrip tile click sets pane B, anchor tile click clears the
  override: `abFilmstripTile`, `LibraryGridView.swift:5983-6012`
  (`model.selectABContender(asset.id)` / `selectABContender(nil)`).
- Item 66 — `AppModel.keepABFrame(keeping:over:)`,
  `AppModel.swift:5010-5021`, delegating to `applyCompareFlags`
  (`AppModel.swift:5099-5137`): kept frame → `flag = .pick`, rejected frame →
  `flag = .reject`, both under one `recordMetadataChangeGroup` undo entry.
- Item 67 — the <2-frames notice: `singleFrameNotice`,
  `LibraryGridView.swift:5944-5953` ("Load at least two frames to compare
  A/B"), shown whenever `presentation.canCompare` is false.
- Item 68 — synced zoom: both panes render `LoupeZoomStageView` reading the
  single shared `model.loupeZoomFocus` (`AppModel.swift:1830`,
  `toggleLoupeZoom` at `:5494-5495`) — sync is structural (one source of
  truth), not mirrored state.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
```
Baseline — `--smoke` pre-seeds flags (11/24 flagged), so record before
asserting anything write-related:
```bash
BASELINE=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NOT NULL;")
```

## Steps
1. **Enter the Cull grid and select a frame.** Press ⌘1 for Cull, click an
   *unflagged* grid tile (pick its id from
   `sqlite3 "$DB" "SELECT id, original_path FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL LIMIT 4;"` —
   scroll it into view first per the README's virtualized-grid gotcha). Note
   its filename as `A_NAME` and its two SQL-order neighbors' filenames.
2. **Switch to A/B view.** Press bare `b` (decoded at
   `GridKeyCaptureView.swift:52` in the grid and `AppModel.swift:260`
   globally; the toolbar "A/B" mode button at `LibraryGridView.swift:4477`
   and the View menu item "A/B Compare" are equivalent). NOT ⇧⌘B — that is
   "Find Best Shots".
3. **Assert the two-pane layout and pane A's identity.**
   `script/ax_drive.sh wait --role AXStaticText --contains "Comparing"`;
   `script/ax_drive.sh find --contains "$A_NAME"` — pane A is the
   currently-selected asset (`ABComparePresentation.init` at `:5398-5410`
   uses `model.selectedAssetID`, falling back to `assets.first`). Pane B is
   whatever `resolveContender` yields — with no override and (in `--smoke`,
   which has no persisted stacks/recommendations for the survey) likely the
   *neighbor*: the asset after the anchor in grid order. Read the
   "Comparing X vs Y" header text and record Y as the resolved contender.
4. **Filmstrip click sets pane B (item 65).** Press a non-anchor filmstrip
   tile: `script/ax_drive.sh press --role AXButton --help "Set as contender (B)"`
   (icon-only tiles carry meaning in AXHelp; if several match, `press`
   takes the first — fine for this assertion). Assert the header now reads
   "Comparing $A_NAME vs <that tile's filename>".
5. **Anchor click clears the override.** Press the anchor tile:
   `script/ax_drive.sh press --role AXButton --help "Anchor (A)"`. Assert
   the header's "vs" side reverts to the step-3 contender (override cleared
   → resolution falls back to recommended/neighbor).
6. **Synced zoom (item 68).** Press the header zoom toggle:
   `script/ax_drive.sh press --role AXButton --help "Zoom both frames to the same region (synced)"`.
   Assert the toggle's label flipped from "Zoom 1:1" to "Fit"
   (`ax_drive.sh find --role AXButton --contains "Fit"`) and that TWO
   "Loupe zoom" HUD overlays are present (one per pane):
   `ax_drive.sh find --label "Loupe zoom"` — see Sharp edges for what this
   does and does not prove. Capture a screenshot via
   `script/capture_app_window.sh` as the same-region evidence. Toggle back
   ("Fit" → "Zoom 1:1") before the keep step.
7. **Commit the keep decision (item 66).**
   `script/ax_drive.sh press --role AXButton --contains "Keep A"` (full
   label "Keep A · Reject B"). Assert ground truth — pane A's asset is
   picked, pane B's is rejected:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN ('<A-id>','<B-id>');"
   ```
   Expect exactly `pick` for A and `reject` for B, and the total flagged
   count = the step-6 value + 2 (both chosen frames were unflagged). Also
   assert one status message appeared: `ax_drive.sh find --contains "Kept"`
   ("Kept <name>; rejected the alternate", `AppModel.swift:5020`).
8. **One-gesture undo check.** Press ⌘Z once and assert BOTH flags return to
   NULL (the pick and the reject were grouped into a single
   `recordMetadataChangeGroup` entry). Re-run the step-7 query. Then redo
   (⇧⌘Z) or re-commit to leave a deterministic state, and note which you did.
9. **<2 comparable frames (item 67).** Narrow the scope to a single asset —
   e.g. type a filename-unique query token into the filter field (per
   `token-query-filter.md`) so `model.assets` for the surface contains one
   asset — then re-enter A/B (`b`). Assert
   `ax_drive.sh find --contains "Load at least two frames to compare A/B"`
   and `ax_drive.sh find --contains "Need two frames to compare"` (the
   header's `positionText` for the nil case), and that no keep bar renders
   (`ax_drive.sh find --contains "Keep A"` fails).

## Expected
- Step 3: two panes render with A/B capsule labels; pane A = the selected
  asset. **Fails if** pane A is not the selection, or `canCompare` is false
  with 24 assets present.
- Step 4: header contender changes to the clicked tile. **Fails if** the
  click selects/navigates instead of setting the override, or the header
  doesn't update.
- Step 5: anchor click reverts pane B to the non-override resolution.
  **Fails if** the override sticks or pane B goes empty.
- Step 6: zoom-toggle label flips and both panes show the zoom HUD
  simultaneously. **Fails if** only one pane zooms (would mean the panes no
  longer share `loupeZoomFocus`), or the label doesn't flip.
- Step 7: exactly `pick`/`reject` land on A/B respectively; no other asset's
  flag changed (flagged count moved by exactly 2). **Fails if** only one
  side is written, the flags are swapped, or an unrelated asset changed.
- Step 8: a single ⌘Z clears both flags. **Fails if** it clears only one
  (the pair isn't one undo group).
- Step 9: the notice text renders and the keep bar is absent. **Fails if**
  a broken two-pane layout renders (e.g. one pane + a keep bar) or the app
  errors.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the app instance you launched.

## Sharp edges
- **Zoom sync is only partially AX-assertable.** The HUD's zoom label is a
  hardcoded `"100%"` (`LoupeZoomView.swift:~157`), not a live readout, and
  no pan/zoom-region coordinate is exposed to accessibility. What IS
  assertable: the header toggle's "Zoom 1:1"/"Fit" label state and the
  presence of a "Loupe zoom" HUD (accessibilityLabel,
  `LoupeZoomView.swift:320`) over each pane. Proving both panes focus the
  *same region* requires a screenshot; the structural claim (one shared
  `model.loupeZoomFocus`) was verified by source read, not by AX.
- **`--smoke` has no persisted stacks and no compare recommendation**, so
  step 3's "no-override" contender is expected to come from the *neighbor*
  tier. The recommended tier (`recommendedAssetID`) is untested by this
  card; exercising it needs an evaluated set with a best-shot
  recommendation — fixture gap, noted per README Fixture status.
- Filmstrip tiles are icon-only; match by `--help` ("Anchor (A)" / "Set as
  contender (B)"), never by title. `press` takes the *first* non-anchor
  match, which may be the same asset the neighbor tier already resolved —
  if so the step-4 header won't visibly change; pick a later tile by
  scoping/scrolling if that happens.
- `keepABFrame` wraps both writes in one undo group and one logical
  operation, but they are two `updateMetadata` repository calls, not
  literally one SQL transaction. The card asserts the user-visible contract
  (both flags land, one ⌘Z reverts both), not transaction internals.
- Step 9's single-asset scoping depends on the query-token filter narrowing
  `model.assets` for the A/B surface; if the filter and the compare surface
  read different asset lists, find another way to a 1-asset scope (e.g. an
  `--isolated` launch plus a 1-photo import) and update this card.
- Bare `b` vs ⇧⌘B confusion is a real trap (`main.swift:373` binds ⇧⌘B to
  Find Best Shots).

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md. All
source claims (line numbers, labels, help strings, resolution order, write
semantics) verified by source read on 2026-07-09; no SQL dry-run yet.
