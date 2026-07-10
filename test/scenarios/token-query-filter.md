# token-query-filter: typing a filter token narrows the grid to the matching catalog rows

**What this covers**: the Library workspace's token query field — typing
`rating:3` and pressing Return must narrow the grid to exactly the rows
`SELECT count(*) ... WHERE rating>=3` returns (the app's advertised token
grammar is "at least this rating", confirmed by both the search-tips help
text and the "Rating >= 3" filter chip it renders), and removing the token
restores the full count.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
Ratings live in `metadata_json`, not a `rating` column (per README). No
seeding needed: `--smoke` pre-seeds rated assets (verified against a seeded
catalog 2026-07-10: 4 of 24 at rating 3, 12 of 24 at rating>=3). Record the
expected count using the app's own `>=` semantics:
```bash
EXPECTED=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.rating')>=3;")
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Note the result-header count before filtering (should read `$TOTAL`).
3. `ax_drive.sh type --role AXTextField --contains "Search your library" --text "rating:3"`,
   then press Return (`ax_drive.sh press --role AXButton --help "Search"` or
   simulate Return via the field's submit action).
4. Assert the result-count header now reads `$EXPECTED`, and a "Rating >= 3"
   filter chip is shown, and the grid shows only that many cells (scroll to
   confirm no extra cells past `$EXPECTED`).
5. Clear the token (click its "x" chip or select-all/delete in the field) and
   resubmit an empty query. Assert the count restores to `$TOTAL`.

## Expected
- Step 4: header count equals `$EXPECTED` (the `>=3` ground truth) and the
  chip reads "Rating >= 3". **Fails if** the count is off, or if the app
  silently changes `rating:N` to mean exact-match instead of its advertised
  `>=N` — the token parser (`LibraryQueryToken`) or `LibrarySearchIntent.parse`
  disagrees with the actual filter application.
- Step 5: count restores to `$TOTAL`. **Fails if** removing the token leaves a
  stale filter applied.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Field/help text
confirmed at `Sources/TeststripApp/LibraryGridView.swift:528-562`
(`queryTokenField`, `.help("Search your library, or type filter tokens like
rating:3, camera:, keyword:. ...")`) and `submitQueryTokenField()` at line
575. Needs a human-present re-run. All SQL in this card was run headlessly against a seeded --smoke catalog on 2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift).
