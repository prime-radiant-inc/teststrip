# lib-006-query-field-and-tips: the query field's icons drive parse+submit, and the tips popover lists the token groups

**What this covers**: the Library token query field (`queryTokenField`,
`Sources/TeststripApp/LibraryGridView.swift:554-...`) has a leading
"Add a filter" menu accessory (`addFilterMenu`, rendered as
`DesignGlyph.filterMenu` = `line.3.horizontal.decrease`, per spec §2b —
`sparkles` no longer doubles as the query icon and the old standalone
plus-circle button is gone; see lib-007 for the menu's own contents), a text
field whose Return/submit action runs `submitQueryTokenField()` (parses
`LibraryQueryToken` tokens out of the typed text and applies them to
`AppModel`, then re-runs `applyLibraryFilters()`), an info-circle button
that opens the "Search tips" popover (`searchTipsPopover`), and a
magnifying-glass button that is a second trigger for the same submit
action. The tips popover must list exactly the 8 token groups baked into
`Self.searchTokenTips` — the task brief guessed 8 without confirming;
source-reading confirms it is in fact 8, not by assumption.

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
   confirms the field exists (placeholder text). Also
   `ax_drive.sh find --role AXButton --help "Add a filter"` confirms the
   filter-menu leading accessory sits inside the same field group (see
   lib-007 for its contents) and no `sparkles`-icon element remains inside
   the query field.
3. `ax_drive.sh type --role AXTextField --contains "Search photos" --text "pick"`,
   then press Return. Assert the result-count header reads `$PICKS`
   (ground truth from Pre-state) and a "Pick" filter chip appears. Note:
   there is NO `flag:` field prefix — `LibrarySearchIntent`'s field list has
   no `flag` entry, so `flag:pick` falls through to plain-text search and
   matches 0; the flag filter is driven by the BARE tokens `pick`/`reject`
   (and synonyms, see lib-004), verified live in run-lib-iter1.
4. Clear the field, retype `pick`, and instead of Return, use
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

7. **⌘F focus (persona-3 item 2).** From the Cull workspace, press ⌘F.
   Assert the app switches to Library (⌘I-style route: `AppModel
   .requestFocusSearch` calls `selectWorkspace(.library)` before bumping
   `focusSearchRequestToken`) and the query text field gains keyboard
   focus (`ax_drive.sh find --role AXTextField --contains "Search photos"`
   reports it as the focused element). Type immediately without clicking;
   assert the typed text lands in the field.
8. **Cycle Filter gating.** In Library, open the Culling menu and confirm
   "Cycle Filter (S)" is disabled/grayed (`CullingKeyCaptureGate.isActive`
   requires workspace `.cull` and a non-grid sub-view — Library is neither,
   so the item is correctly inert there, not a bug). Switch to Cull ▸
   Loupe and confirm the same item is enabled and pressing `s` cycles the
   filter scope.

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

## Fix notes (persona-fixes-5, 2026-07-11)
PENDING-VM: search-field focus now releases on submit
(`submitQueryTokenField()` sets `isQueryFieldFocused = false`), so a stray
post-submit keystroke (e.g. a lone "1") can no longer land in the field and
become a plain-text chip. Esc semantics added: Esc clears the field, Esc
with an empty field clears all filters; documented in the tips popover and
the field's help text. Unit-tested via `LibraryGridChromePolicy
.queryFieldEscapeAction`; live AX keystroke verification pending VM.

## Fix notes (2026-07-11, Esc staging observable)
PENDING-VM: live VM driving showed the two-stage Esc was unobservable — the
field bound `librarySearchText` directly, so typing mutated the committed
filter chips and Esc #1 wiped the committed search (chips collapsed with
the field). The field now edits `AppModel.librarySearchDraft`; committed
filter state stays in `librarySearchText` (re-synced to the draft on
programmatic changes via didSet). Esc #1 clears the draft only — chips
stay visible — and Esc #2 (empty field) clears the active filters.
Unit-tested in `LibraryGridChromeTests`
(`testTypingInQueryFieldDraftLeavesCommittedFilterChipsVisible`,
`testEscapeStageOneClearsDraftOnlyThenStageTwoClearsFilters`).
