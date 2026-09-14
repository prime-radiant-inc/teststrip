
**LIVE RUN 2026-09-13, Tart VM `teststrip-e2e` (`script/vm_scenario_run.sh`,
run dir `smoke-1789360059`, `launch smoke`, 24 assets): Steps 1-8 all PASS.**
Grid order is numeric (`smoke-0`…`smoke-23`), which matches the on-screen
sequence measured by arrowing; scope was already `.all` (no `Cull filter` chip
rendered), so no `S` press was needed.
- Step 2: 3×Right, then Return → `Frame 4 of 24` on `smoke-3.jpg` — focus
  advances exactly one tile per press. PASS.
- Step 3: End, Return → `Frame 24 of 24` on `smoke-23.jpg`. PASS.
- Step 4: Home, Return → `Frame 1 of 24` on `smoke-0.jpg`. PASS.
- Step 5: batch-select driven with a one-off warped modifier-click helper (see
  the harness finding below) — plain-click `smoke-0` then shift-click
  `smoke-2` → AX values show `smoke-0` `Selected, batch selected` and
  `smoke-1`/`smoke-2` `Not selected, batch selected` (contiguous range). PASS.
- Step 6: press `3` → SQL `smoke-0/1/2` ratings `3/3/3` (baseline `0/1/2`) in
  one keystroke — the load-bearing batch-write assertion. PASS.
- Step 7: a single ⌘Z → SQL back to `0/1/2` — one undo group for all three.
  PASS.
- Step 8: plain-click `smoke-5` (batch cleared), Return → `Frame 6 of 24` on
  `smoke-5.jpg`. PASS.

**Harness finding (not an app defect): `ax_drive.sh press --modifiers` cannot
drive this card's step 5 as shipped.** Two defects, both reproduced live:
1. It posts the synthetic `leftMouseDown`/`Up` at the element's AX center but —
   unlike the `--button right` path — never warps the cursor first
   (`CGWarpMouseCursorPosition`) or posts a `mouseMoved`. SwiftUI's grid tile
   hit-test then misses the click entirely (element present, no selection
   change). A warp+move makes the identical click land.
2. It sets `flags` on the mouse events but never posts a flags-cleared
   (`flagsChanged`) event, so the modifier is left **stuck** in the global
   `NSEvent.modifierFlags` state. After one `--modifiers shift` attempt, a
   following plain click was misread as a shift-click and range-selected. Any
   card using this verb corrupts the next click.
   The card's Sharp edge (a)/(b) was therefore correct: step 5 needed a
   purpose-built driver. The one used here warps the cursor, posts a
   `mouseMoved`, then flagged down/up, then a `flagsChanged` clear.

**Environment geometry**: the VM display is **1024×768**, but the app window is
1520×772 placed at `x=-248`, so grid columns past tile index ~5 (screen x >
1024) are clipped off-screen and un-clickable even though their AX elements
(with positions) are vended. On-screen tiles must be chosen for point clicks.

**Fixture gap (honest, not a card weakening)**: a fully *unflagged+unrated*
contiguous triple does not exist on `--smoke` — any 3 consecutive indices
include a multiple of 3 (always `.pick`), and every `rating == 0` index is also
a multiple of 3/6 (hence decided). The batch assertion this card exists to
prove is "one keystroke writes all three; one ⌘Z reverts all three", which does
not need an unflagged triple, so the run used contiguous `smoke-0/1/2`
(ratings `0/1/2`, flags reject/null/null) and asserted the rating delta.

Stale citation: `assetActivation` is at `LibraryGridView.swift:8021-8065`, not
`:7521-7566` (that range is now the compare-survey body). Symbols
(`selectBatchRange`/`toggleBatchSelection`) are alive and behave as the card
describes. Supersedes prior status: fresh full VM re-run on the current build;
all 8 steps green.
# cull-010-cullgrid-keys: cull grid arrow/Home/End navigation and batch rating in one keystroke

**What this covers**: as a photographer doing rapid grid-level triage, I
want arrow keys and Home/End to move focus through the grid, I want to
shift/cmd-click a handful of near-duplicate tiles and rate them all with a
single keystroke instead of one-by-one, and I want Return to drop straight
into the loupe on a focused tile. Covers items 27-29.

Source:
- `Sources/TeststripApp/GridKeyCaptureView.swift:116-143`
  (`GridSelectionMovement.nextIndex`) — pure arrow/Home/End arithmetic:
  left/right ±1 clamped to `[0, count-1]`; up/down ±`columns` clamped so an
  out-of-range move is a no-op (`target >= 0`/`target < count`, else stays
  put — not clamped to the nearest row, just refuses to move); Home → index
  0; End → index `count - 1`.
- `Sources/TeststripApp/AppModel.swift:6674-6687` (`moveGridSelection`) —
  operates over `CullScopeOrdering.filteredAssets(assets, scope: cullScope)`,
  i.e. the **scope-filtered** grid, not the full asset list — Home/End jump
  to the first/last tile *matching the active scope*, not the catalog's
  first/last asset.
- `Sources/TeststripApp/AppModel.swift:6693-6737` (`applyGridKeyCommand`) —
  `.rating`/`.pick`/`.reject`/`.clearFlag` call
  `setRatingForSelectedAssets`/`setFlagForSelectedAssets`
  (`AppModel.swift:7779-7815`), whose doc comment (`:7779-7781`) states:
  **"Batch rating/flag/color across the whole grid multi-selection when one
  is active, otherwise the single focused asset. One undo group covers every
  changed photo."** — confirmed by `updateSelectedAssetsMetadata`
  (`:8489-8518`), which iterates `currentManualSelectionAssetIDs` (the batch
  set when non-empty) and records one `MetadataChange` group for the whole
  batch. `.openLoupe` (Return/Space) opens the loupe on the single focused
  tile (`selectedAssetID`), independent of any batch selection.
- `Sources/TeststripApp/LibraryGridView.swift:7521-7566`
  (`assetActivation`) — the actual multi-select gesture: **shift-click**
  calls `model.selectBatchRange(to:)` (contiguous range from the last
  anchor, `AppModel.swift:4774-4783`); **command-click** calls
  `model.toggleBatchSelection(_:)` (`:4770-4772`, individual add/remove).
  There is no keyboard-only multi-select gesture in `GridKeyCaptureView`
  itself — batch selection is mouse-driven (with a modifier key), navigated
  focus (arrows/Home/End) is keyboard-driven, and they're independent state
  (`selectedAssetID` vs `selectedBatchAssetIDs`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Switch to the `.all` cull scope first (press `s` until the scope indicator
reads "All") so Home/End land on the catalog's actual first/last tile rather
than a scope-filtered subset — simpler to reason about ground truth.

## Steps
1. ⌘1 Cull, press `G` from the loupe (or land in `.cullGrid` however the
   lens opens) to reach the grid subview.
2. Press the right arrow several times; assert focus advances one tile per
   press. AX signal: `selectedAssetID` isn't itself exposed as text, so
   cross-check via the loupe — press Return after a few right-arrows,
   confirm (via `sqlite3` on the asset's filename shown in the loupe
   header, or `AssetSourceStatusPresentation`/filename label) that the
   opened asset is the Nth tile in catalog order, then press `G`/Esc back to
   the grid rather than guessing focus from the grid alone.
3. Press End. Scroll the grid into view if needed (**lazily virtualized —
   off-screen tiles are not in the AX tree**, per `test/scenarios/README.md`).
   Press Return; assert the opened asset is the catalog's last asset:
   ```bash
   sqlite3 "$DB" "SELECT id FROM assets ORDER BY id DESC LIMIT 1;"
   ```
   compare against whatever id/filename the source data actually orders
   last (confirm the grid's sort order matches `id` ordering before relying
   on this — if the grid sorts by capture date or import order instead,
   adjust the comparison query to match).
4. Press Home; Return; assert the opened asset is the catalog's first tile
   by the same ordering.
5. Back in the grid, record 3 unflagged/unrated tile ids up front:
   ```bash
   BASELINE3=$(sqlite3 "$DB" "SELECT id FROM assets WHERE json_extract(metadata_json,'\$.rating') IS NULL OR json_extract(metadata_json,'\$.rating')=0 LIMIT 3;")
   ```
   Click the first, shift-click the third (contiguous 3-tile range via
   `selectBatchRange`) — **this requires a real mouse click with the Shift
   key held**, which `ax_drive.sh press` (a plain `AXPress`) does not carry;
   see Sharp edges for how to actually drive this.
6. Press `3` (rate 3). Assert **all three** tiles' `metadata_json` rating
   became 3 in one keystroke, not just the last-clicked one:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.rating') FROM assets WHERE id IN (<id1>,<id2>,<id3>);"
   ```
7. Press ⌘Z once. Assert all three ratings revert together (one undo group
   per the doc comment at `AppModel.swift:7779-7781`) — not one revert per
   ⌘Z.
8. Click a single (non-batch-selected) tile, press Return. Assert the loupe
   opens on exactly that tile.

## Expected
- Step 2: focus advances exactly one tile per right-arrow press. **Fails
  if** it skips or repeats a tile.
- Step 3/4: End/Home land on the catalog's actual last/first tile per the
  confirmed sort order. **Fails if** they land on a scope-filtered subset
  while scope is `.all` (would indicate `CullScopeOrdering.filteredAssets`
  isn't respecting `.all`), or don't move at all.
- Step 6: all 3 recorded ids show `rating = 3`. **Fails if** only the
  focused/last-clicked tile changed — the "batch write" claim is the
  load-bearing assertion this card exists to prove.
- Step 7: a single ⌘Z reverts all 3 ratings together. **Fails if** it takes
  3 separate ⌘Z presses (undo grouping too fine) or reverts an unrelated
  change (grouping too coarse).
- Step 8: Return opens the loupe on the single clicked tile, unaffected by
  any leftover batch-selection state from steps 5-7.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Batch selection is not drivable through `ax_drive.sh`'s current
  primitives.** `press` issues a plain `AXPress` action with no modifier
  flags; shift-click/cmd-click requires an actual mouse-down event with
  `NSEvent.modifierFlags` set, which the AX action model doesn't carry. A
  live run of step 5 needs either: (a) a new `ax_drive.sh` verb that clicks
  through System Events with a modifier held (`click ... using {shift
  down}` in AppleScript, which needs pixel coordinates derived from the
  tile's AX frame, not just its accessibility identity), or (b) a
  one-off `osascript` snippet written for this card. **This card is UNRUN
  and step 5 specifically needs that driving primitive built or improvised
  before it can execute — flag this to Jesse as a possible `ax_drive.sh`
  gap** rather than silently downgrading the assertion to single-tile rating
  (which would defeat the point of the card).
- Home/End semantics are scope-relative (`CullScopeOrdering.filteredAssets`),
  which is why Pre-state pins the scope to `.all` first — running this card
  under `.unrated` (the default scope) would make Home/End land on a
  different, scope-dependent tile and complicate the ground-truth query.
- `--smoke`'s 11/24 pre-flagged, 4/24 rated-3 seed data means step 5's
  "3 unflagged/unrated tiles" query must actually filter for that — don't
  assume the first 3 catalog rows qualify.
- Step 3/4's assumption that the grid's on-screen order matches `SELECT ...
  ORDER BY id` is unverified against the live sort — confirm the grid's
  actual sort key (likely capture date or import sequence, not row id) by
  reading `LibraryGridView`'s asset ordering, or by reading off the first/
  last on-screen filename and matching it in SQL, before trusting this
  assertion.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md. Step 5's
batch-select driving mechanism is an open gap in `ax_drive.sh`, not just an
unrun step — see Sharp edges.

**Reconciled 2026-08-09 (Task 13, unified-shell preamble sweep)**: Step 1's
⌘1 preamble is unchanged in effect (⌘1 selects the Cull lens under
`LibraryLens`, same as it selected Cull under the old `Workspace` enum).
Preamble only; no other stale symbol found in this card. Supersedes prior
status: no prior run evidence exists to invalidate (still UNRUN).
