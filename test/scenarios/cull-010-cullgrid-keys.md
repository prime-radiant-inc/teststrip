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
- `Sources/TeststripApp/AppModel.swift:5290-5303` (`moveGridSelection`) —
  operates over `CullScopeOrdering.filteredAssets(assets, scope: cullScope)`,
  i.e. the **scope-filtered** grid, not the full asset list — Home/End jump
  to the first/last tile *matching the active scope*, not the catalog's
  first/last asset.
- `Sources/TeststripApp/AppModel.swift:5309-5334` (`applyGridKeyCommand`) —
  `.rating`/`.pick`/`.reject`/`.clearFlag` call
  `setRatingForSelectedAssets`/`setFlagForSelectedAssets`
  (`AppModel.swift:5970-5990`), whose doc comment (`:5967-5969`) states:
  **"Batch rating/flag/color across the whole grid multi-selection when one
  is active, otherwise the single focused asset. One undo group covers every
  changed photo."** — confirmed by `updateSelectedAssetsMetadata`
  (`:6443-6467`), which iterates `currentManualSelectionAssetIDs` (the batch
  set when non-empty) and records one `MetadataChange` group for the whole
  batch. `.openLoupe` (Return/Space) opens the loupe on the single focused
  tile (`selectedAssetID`), independent of any batch selection.
- `Sources/TeststripApp/LibraryGridView.swift:6542-6564`
  (`assetActivation`) — the actual multi-select gesture: **shift-click**
  calls `model.selectBatchRange(to:)` (contiguous range from the last
  anchor, `AppModel.swift:3910-3919`); **command-click** calls
  `model.toggleBatchSelection(_:)` (`:3906-3908`, individual add/remove).
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
   workspace opens) to reach the grid subview.
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
   per the doc comment at `AppModel.swift:5967-5969`) — not one revert per
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
