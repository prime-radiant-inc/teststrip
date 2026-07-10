# lib-006-query-field-and-tips: the query field's icons drive parse+submit, and the tips popover lists the token groups

**What this covers**: the Library token query field (`queryTokenField`,
`Sources/TeststripApp/LibraryGridView.swift:554-599`) has a leading sparkles
glyph (decorative), a text field whose Return/submit action runs
`submitQueryTokenField()` (parses `LibraryQueryToken` tokens out of the typed
text and applies them to `AppModel`, then re-runs `applyLibraryFilters()`),
an info-circle button that opens the "Search tips" popover
(`searchTipsPopover`, lines 606-633), and a magnifying-glass button that is a
second trigger for the same submit action. The tips popover must list exactly
the 8 token groups baked into `Self.searchTokenTips` (lines 635-644) — the
task brief guessed 8 without confirming; source-reading confirms it is
in fact 8, not by assumption.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
PICKS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
```
No seeding needed beyond `--smoke`. Confirmed against a seeded catalog
2026-07-10: `TOTAL=24`, `PICKS=6`.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. `ax_drive.sh find --role AXTextField --contains "Search photos, people, places, or rating:3 camera:… "`
   confirms the field exists (placeholder text per line 559).
3. `ax_drive.sh type --role AXTextField --contains "Search photos" --text "flag:pick"`,
   then press Return. Assert the result-count header reads `$PICKS`
   (ground truth from Pre-state) and a "Pick" filter chip appears.
4. Clear the field, retype `flag:pick`, and instead of Return, use
   `ax_drive.sh press --role AXButton --help "Search"` (the magnifying-glass
   icon) to confirm the icon button is an equivalent submit trigger — same
   `$PICKS` result.
5. `ax_drive.sh press --role AXButton --help "Search tips and filter tokens"`
   (the info-circle icon). Assert the popover opens (`ax_drive.sh wait --role
   AXStaticText --contains "Search tips"`).
6. Within the popover, assert all 8 token-group rows are present by their
   exact `token` label text (`ax_drive.sh find --role AXStaticText --contains
   "<token>"` for each): `person:"Name"`, `keyword:`, `folder:`, `camera: /
   lens:`, `iso:`, `rating: / color:`, `from: / before: / date:`, `source: /
   signal: / xmp:`. Also assert the trailing repeat-person hint text
   ("Repeat person: to require every name…") is present.

## Expected
- Step 3 and 4: header count equals `$PICKS` both times — Return and the
  magnifying-glass icon must be equivalent submit paths, since both call
  `submitQueryTokenField()` (line 565, 582). **Fails if** the icon button
  is a no-op, or if it behaves differently from Return.
- Step 6: exactly 8 token-group rows, matching `Self.searchTokenTips`
  verbatim (line 635-644). **Fails if** the popover shows a different count,
  or if any row's text drifts from source (e.g. a stale tip for a token
  the parser no longer recognizes — cross-check against
  `LibraryQueryToken.swift`'s documented fields: rating, flag, keyword,
  folder, camera, lens, iso, dateFrom, dateBefore, color, source, signal,
  xmpPending, xmpConflict, needsKeywords, needsEvaluation, likelyIssues,
  providerFailures — all covered by the 8 grouped rows).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
The popover documents `xmp:` as one token under the "source: / signal: /
xmp:" row, but `LibraryQueryToken`'s structured fields are `xmpPending` and
`xmpConflict` (two distinct AppModel booleans) — the tips text doesn't
distinguish them or show their exact spelling (e.g. `xmp:pending` vs
`xmp:conflict`), so a user typing `xmp:` alone has to guess the suffix. Not
a bug per se (the row is a category label, not a literal grammar), but worth
noting since every other row shows a literal token prefix.

## Run status
NOT RUN — GUI/AX driving was not attempted this session (constraints
forbade live GUI launches). Field/button/popover structure confirmed by
reading `Sources/TeststripApp/LibraryGridView.swift:554-644` directly
(`queryTokenField`, `submitQueryTokenField()` at 601-604, `searchTipsPopover`
at 606-633, `Self.searchTokenTips` at 635-644 — read in full, count is 8).
SQL in Pre-state was dry-run headlessly against a fresh `--smoke` catalog on
2026-07-10 via `script/build_and_run.sh --smoke`, reading
`TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` off the running process
(`TOTAL=24`, `PICKS=6`); schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`.
