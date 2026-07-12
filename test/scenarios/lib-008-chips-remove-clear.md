# lib-008-chips-remove-clear: filter chips dedupe by identity, removal is per-property, and "clear all" only shows when a filter is active

**What this covers**: `activeFilterChips`
(`Sources/TeststripApp/LibraryGridView.swift:954-979`) renders two chip
sources back to back — structured `LibraryQueryToken` chips (from
`LibraryQueryToken.tokens(from: model)`) and legacy
`ActiveLibraryFilterRow` chips (from `model.activeLibraryFilterRows`),
deduplicated against the structured tokens by
`LibraryQueryToken.legacyRows(_:notCoveredBy:)` (identity = title AND
`SidebarRowTarget`, per `LibraryQueryTokenField.swift`). One legacy chip kind
carries a "Not a filter — matching file names and photo text" subtitle
(`filterChip(isPlainSearchFallback:)`, lines 981-1016): it is set `true`
exactly once, in `AppModel.swift:2758`, for the row titled
`"Search: \(residualSearch)"` — i.e. whatever free text is left over after
`LibrarySearchIntent.parse` strips out every structured token it recognizes.
Removing a structured chip calls `LibraryQueryToken.remove(token, from:
model)`, which (per `LibraryQueryTokenField.swift`) clears exactly that
token's one backing property and leaves siblings untouched. The "Clear
filters" (xmark-circle) button only renders when `hasActiveFilters` is true
(`LibraryGridView.swift:720`, backed by `model.hasActiveLibraryFilters` at
`AppModel.swift:2732-2734`, itself `selectedAssetSetID != nil ||
currentLibraryQuery() != nil`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
RATING3PLUS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.rating')>=3;")
PICKS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
```
Confirmed against a seeded `--smoke` catalog 2026-07-10: `TOTAL=24`,
`RATING3PLUS=12`, `PICKS=6`.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Confirm no chips render initially and no "Clear filters" button exists
   (`ax_drive.sh find --role AXButton --help "Clear filters"` should fail —
   `hasActiveFilters` is false on a fresh launch with no saved set or
   library query active).
3. Type `rating:3` and Return; then use the "Add a filter" > Flag > Pick
   menu item as well, so two independent structured filters are active at
   once.
4. Assert exactly two chips render, titled "Rating >= 3" and "Pick" (both
   from `LibraryQueryToken`, not legacy rows — neither has a "Plain search
   fallback" subtitle). Assert "Clear filters" now appears.
5. Assert the result count reflects the intersection of both filters (AND
   semantics — record the exact expected count by running the equivalent SQL:
   `SELECT count(*) FROM assets WHERE json_extract(metadata_json,'$.rating')>=3
   AND json_extract(metadata_json,'$.flag')='pick';` against `$DB` and using
   that as ground truth, since `$RATING3PLUS` and `$PICKS` are independent
   marginals).
6. Click the "x" on the "Rating >= 3" chip. Assert only that chip is
   removed — the "Pick" chip and its filtering remain, and the count
   changes to `$PICKS` (confirms `LibraryQueryToken.remove` clears exactly
   the rating property, leaving `flagFilter` untouched).
7. Type a query mixing structured and free text, e.g. `rating:4 sunset`,
   and Return. Assert a chip titled "Search: sunset" appears with the
   "Not a filter — matching file names and photo text" subtitle beneath it, alongside a separate
   "Rating >= 4" chip with no subtitle.
8. Click "Clear filters". Assert all chips disappear, the count restores to
   `$TOTAL`, and the button itself disappears (since `hasActiveFilters` is
   now false again).

## Expected
- Step 2: no chips, no Clear button pre-filter. **Fails if** either
  renders on a clean launch.
- Step 4: exactly 2 chips, correct titles, Clear button present. **Fails
  if** count/titles differ or Clear is absent.
- Step 6: removing one chip leaves the sibling filter and its narrowing
  intact. **Fails if** removing one chip clears both filters (would mean
  `LibraryQueryToken.remove`'s per-property scoping regressed), or if the
  removed chip's filter effect persists (stale filter application).
- Step 7: exactly one chip carries the "Not a filter — matching file names and photo text" subtitle, and it's the
  free-text residual, not the structured `rating:4` token. **Fails if** the
  subtitle appears on the wrong chip or on none/both.
- Step 8: all chips and the Clear button vanish, count restores. **Fails
  if** the button is still visible with no active filters (would falsify
  the `hasActiveFilters`-gated Sharp-edges note below), or a filter
  survives the clear.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
`hasActiveLibraryFilters` (`AppModel.swift:2732-2734`) is defined as
`selectedAssetSetID != nil || currentLibraryQuery() != nil` — it does
**not** directly reference any of the 13 structured filter properties
(`minimumRatingFilter`, `flagFilter`, etc.) or `librarySearchText`. Whether
"Clear filters" appears is therefore contingent on `currentLibraryQuery()`
returning non-nil whenever any structured filter or search text is set — a
separate function (`AppModel.swift:9573`) not read in full for this card.
If that function's notion of "active" ever drifts from what
`activeFilterChips` actually renders (e.g. a filter chip shows but
`currentLibraryQuery()` returns nil for it), the Clear button could
disappear while chips are still visible with no way to bulk-clear them —
worth a dedicated assertion (step 4's "Clear filters now appears" check)
since this card's Pre-state SQL can't verify that function's logic
directly.

## Run status
NOT RUN — GUI/AX driving was not attempted this session. Chip/dedup/removal
logic confirmed by reading `Sources/TeststripApp/LibraryGridView.swift:947-1016`
and `AppModel.swift:2732-2845` (`hasActiveLibraryFilters`,
`activeLibraryFilterRows`, the `isPlainSearchFallback: true` site at line
2758) in full, plus the `LibraryQueryTokenField.swift` summary of
`legacyRows(_:notCoveredBy:)` and `remove(_:from:)`. SQL dry-run headlessly
against a fresh `--smoke` catalog on 2026-07-10 (`TOTAL=24`,
`RATING3PLUS=12`, `PICKS=6`); the AND-intersection count in step 5 was not
dry-run this session and should be computed fresh at run time. Schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`.
