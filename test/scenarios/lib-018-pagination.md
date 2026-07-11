# lib-018-pagination: Load Previous / Load More paging controls

**What this covers**: the Library grid's page-window controls (footer
buttons at `Sources/TeststripApp/LibraryGridView.swift:2495-2516`), gated by
`model.hasPreviousAssets`/`model.hasMoreAssets` and disabled during import,
against the offset/window math in `AppModel.swift`.

## Fixture (gap closed by the `smokebig` variant)

`AppModel.assetPageSize = 120` (`Sources/TeststripApp/AppModel.swift:2174`).
`hasMoreAssets` is `assetPageOffset + assets.count < totalAssetCount`
(`AppModel.swift:2302-2303`) — pagination only becomes reachable once a
catalog holds **more than 120 assets**. Checked every existing seed source:

| Seed | Photo count | Reaches 120? |
| --- | --- | --- |
| `--smoke` (synthetic) | 24 | No |
| `--sample-photos` (`sample-data/photos/wordpress-photo-directory`) | 24 | No |
| `--faces` (`sample-data/photos/faces`) | 12 | No |
| `sample-data/photos/loc-free-to-use` | 13 | No |
| `--real-corpus` | not a static fixture — points at whatever real corpus dir is configured; size unknown/variable, not something this card can rely on being seeded to `>120` on demand |

The `smokebig` VM variant (`vm_scenario_run.sh sync smokebig`) closes this
gap: `TeststripBench seed-app-catalog <dir> 130` — 130 synthetic assets,
10 past the page size (host: `TESTSTRIP_SMOKE_ASSET_COUNT=130
./script/build_and_run.sh --smoke`). Live-verified 130 rows in a fresh
`smokebig` catalog.

## What's verified from source (no live catalog needed)

- Gating: `hasMoreAssets` / `hasPreviousAssets`
  (`AppModel.swift:2302-2307`) — `hasPreviousAssets` is simply
  `assetPageOffset > 0`; `hasMoreAssets` is
  `assetPageOffset + assets.count < totalAssetCount`. Both buttons are
  conditionally rendered (`if model.hasPreviousAssets { ... }` /
  `if model.hasMoreAssets { ... }`) — absent, not just disabled, when there's
  nothing to page to.
- Both buttons are `.disabled(isImporting)` (`LibraryGridView.swift:2503,
  2514`) — while an import is in flight, paging is blocked even if more
  pages exist. `isImporting` reads `model.isImporting`
  (`LibraryGridView.swift:69-70`).
- Page-window math: `loadedAssetWindowSize = assetPageSize * 2` = 240
  (`AppModel.swift:2175`) — the app appears to keep a two-page window loaded
  around the current offset rather than exactly one page, based on this
  constant's name and multiplier; the precise sliding-window behavior (does
  "Load More" append a page or replace the window?) needs confirmation by
  reading `loadMoreAssets()`'s/`loadPreviousAssets()`'s call sites in
  `AppModel.swift` (offset math clustered around lines 8780-8810,
  9200-9230, 11460-11480) rather than being asserted here from the constant
  name alone — do that read before writing the runnable version of this
  card.
- `previousOffset` computation: `max(0, assetPageOffset - assetPageSize)`
  (`AppModel.swift:8804`) — Load Previous steps back by exactly one page,
  clamped at 0, not by the window size.

## Pre-state
```bash
# The `smokebig` variant seeds 130 assets — 10 past the 120-asset
# assetPageSize (live-verified: sql smokebig count(*) -> 130):
script/vm_scenario_run.sh sync smokebig && script/vm_scenario_run.sh launch smokebig
TOTAL=$(script/vm_scenario_run.sh sql smokebig "SELECT count(*) FROM assets;")   # 130
# Host equivalent: TESTSTRIP_SMOKE_ASSET_COUNT=130 ./script/build_and_run.sh --smoke
```

## Steps
1. Launch the `smokebig` variant (130 assets). Confirm "Load More"
   is visible and "Load Previous" is not (offset 0).
2. Click "Load More". Confirm the grid's window advances by one page (offset
   increases by 120, or per whatever windowing `loadMoreAssets()` actually
   implements — confirm against source before asserting a specific number).
   Confirm "Load Previous" now appears.
3. Click "Load Previous". Confirm offset steps back by exactly `assetPageSize`
   (120), clamped at 0 (`AppModel.swift:8804`).
4. Start an import (`presentImportConfirmation`) while sitting on a page with
   both buttons visible; confirm both are disabled (grayed, AX
   `AXEnabled == false`) for the duration of the import, and re-enable once
   `model.isImporting` goes false.

## Expected
- Step 1: button visibility exactly matches the `hasPreviousAssets`/
  `hasMoreAssets` boolean gates — **fails if** a button shows when there's
  nothing more to page to, or hides when there is.
- Steps 2-3: offset math matches `AppModel.swift`'s actual implementation
  (confirm the exact call before writing assertions — do not guess).
- Step 4: both buttons are disabled for the full import duration and only
  the full duration — **fails if** they re-enable early (mid-import) or stay
  disabled after import completes.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Don't
  let a runner "fix" this by seeding a smaller fake page size in test-only
  code; that would test a different constant than what ships.
- `loadedAssetWindowSize` (240) suggests the grid may keep two pages loaded
  and swap/scroll rather than doing a hard offset replace on every click —
  if so, "offset increases by 120" in Step 2 may be the wrong assertion
  entirely. Read `loadMoreAssets()`/`loadPreviousAssets()` bodies fully
  before running this card for real.

## Run status
NOT RUN — the `smokebig` fixture now exists (130 assets, live-verified);
the AX drive itself has not yet been executed. Gating logic and page-size
constant verified by direct source read at
`Sources/TeststripApp/AppModel.swift:2174-2175, 2302-2307, 8804` and
`Sources/TeststripApp/LibraryGridView.swift:2495-2516`. The precise
load-more/load-previous window-replacement semantics were **not** fully
traced in this pass (only the constants and the previous-offset formula were
read) — read the full function bodies before this card is made runnable.
