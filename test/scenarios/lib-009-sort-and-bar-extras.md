# lib-009-sort-and-bar-extras: the sort menu's 6 options, and the query bar's conditional sync-retry/refresh-source buttons

**What this covers**: `librarySortPicker`
(`Sources/TeststripApp/LibraryGridView.swift`) is, per spec §2b, a compact
icon `Menu` (`DesignGlyph.sort` = `arrow.up.arrow.down`, AXHelp "Sort") —
not the old wide labeled `Picker`. It always lists all 6 `LibrarySortOption`
cases via `LibrarySortOptionPresentation.options(...)`, each rendered as
`"<title>: <subtitle>"`, with the current sort's row showing a leading
checkmark (`option.isSelected`) instead of occupying a fixed-width control.
Next to it, two icon buttons in `libraryQueryBar` are conditionally
shown/enabled: the sync-retry button (`arrow.triangle.2.circlepath`) renders
only when `LibraryGridChromePolicy.shouldShowPendingMetadataSyncRetryAction(...)`
is true, which is just `isPendingFilterActive` — i.e.
`model.metadataSyncPendingFilter`; the refresh-source button
(`arrow.clockwise`) always renders but is `.disabled` unless
`model.canRefreshVisibleAssetAvailability` (`catalog != nil && !assets.isEmpty`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
Confirmed against a seeded `--smoke` catalog 2026-07-10: `TOTAL=24` (so
`assets` is non-empty and `canRefreshVisibleAssetAvailability` should be
true by default).

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. `ax_drive.sh press --role AXButton --help "Sort"` (the compact
   `arrow.up.arrow.down` icon menu) and assert exactly these 6 entries, in
   `LibrarySortOption.allCases` order:
   - "Import Order: Oldest import first"
   - "Capture Time: Newest first"
   - "Capture Time: Oldest first"
   - "Rating: Highest first"
   - "Rating: Lowest first"
   - "Filename: A to Z"
   Assert "Import Order: Oldest import first" (the default sort) shows a
   leading checkmark and no other row does.
3. Assert the sync-retry icon (`--help "Retry pending metadata sync in
   current results"`) is **absent** initially (no `metadataSyncPendingFilter`
   active on a fresh launch).
4. Enable the "Metadata Sync" > "Pending" filter via "Add a filter". Assert
   the sync-retry icon now **appears**.
5. Assert the refresh-source icon (`--help "Refresh source status"`) is
   present and enabled throughout (catalog is non-empty per `$TOTAL=24`).
6. Select "Rating: Highest first" from the sort menu. Scroll the grid and
   assert the first visible asset has the highest rating in the catalog
   (cross-check against `SELECT max(json_extract(metadata_json,'$.rating'))
   FROM assets;` on `$DB`).

## Expected
- Step 2: exactly 6 options with the exact titles above. **Fails if** count
  or text differs from `LibrarySortOptionPresentation`.
- Step 3/4: sync-retry icon visibility tracks `metadataSyncPendingFilter`
  exactly. **Fails if** it shows before the filter is active, or stays
  hidden after.
- Step 5: refresh-source icon is enabled whenever the catalog has assets.
  **Fails if** it's disabled with a non-empty grid.
- Step 6: sort actually reorders the grid by rating descending. **Fails if**
  the visual order doesn't match the ground-truth max-rating query.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
The sync-retry button's *visibility* is gated only by
`metadataSyncPendingFilter` (`shouldShowPendingMetadataSyncRetryAction`,
line 7313-7315 — a one-line passthrough), but its *enabled* state uses a
different, stricter condition,
`isPendingMetadataSyncRetryActionDisabled(isImporting:canRetry:)`
(line 7317-7319), which checks `model.canRetryPendingMetadataSyncInCurrentScope`
— itself gated on `metadataSyncPendingFilter && catalog != nil &&
workerSupervisor != nil` plus a non-empty retry-candidate scope
(`AppModel.swift:2231-2240`). So the button can be **visible but disabled**
whenever the pending filter is on but there's nothing retriable (e.g. no
worker supervisor running, or zero pending-sync assets in the current
scope) — worth a dedicated disabled-state assertion if this card is
extended, since step 4 above only checks visibility, not enabled-ness.

## Run status
NOT RUN — GUI/AX driving was not attempted this session. Sort options and
conditional-button logic confirmed by reading
`Sources/TeststripApp/LibraryGridView.swift:695-718` and `843-852` and
`7304-7368`, plus `AppModel.swift:2231-2245, 2643-2645` in full. SQL
dry-run headlessly against a fresh `--smoke` catalog on 2026-07-10
(`TOTAL=24`); the max-rating query in step 6 was not dry-run this session.
Schema per `Sources/TeststripCore/Catalog/CatalogMigrations.swift`.
