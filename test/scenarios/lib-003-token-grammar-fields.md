# lib-003: the structured `field:value` token grammar narrows the grid per its documented SQL semantics

**What this covers**: the Library workspace's query token field recognizes a
fixed set of `field:value` tokens (`camera:`, `lens:`, `keyword:`/`tag:`,
`person:`, `folder:`/`path:`, `color:`/`colour:`/`label:`, `iso:`, `rating:`
(+3 more aliases), `from:`/`after:`/`since:`, `before:`/`until:`, `date:`,
`source:`, `signal:`, `xmp:pending`/`xmp:conflict`, `session:`/`worksession:`,
`import:`/`importbatch:`/`batch:`). Each recognized field is parsed by
`LibrarySearchIntent.fieldPredicates(from:)`
(`Sources/TeststripApp/LibrarySearchIntent.swift:107-173`), compiled to SQL by
`CatalogRepository.compileClauses(_:)`
(`Sources/TeststripCore/Catalog/CatalogRepository.swift:2261-2555`), and
rendered as a chip via `LibraryQueryToken` (`Sources/TeststripApp/LibraryQueryTokenField.swift`).
Unit coverage already proves the parse step
(`Tests/TeststripAppTests/LibrarySearchIntentTests.swift`); this card is the
AX-level companion proving typed tokens actually narrow the live grid to the
counts the SQL compiler would produce.

This card drives and asserts **6 representative fields in full** (camera,
keyword, rating, iso, color, source) with real dry-run SQL against the
`--smoke` fixture, and documents the compiled SQL + exact enum/alias lists for
every other field so the same drive pattern can be extended without
re-reading source. Fields whose ground truth the `--smoke` fixture cannot
populate (`signal:`, `xmp:pending`/`xmp:conflict`, `date:` narrowing, `person:`,
`session:`, `import:`) are called out explicitly as fixture gaps, not silently
skipped.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")   # 24
```

`--smoke`'s 24 synthetic assets each carry `cameraModel` cycling
`SmokeCam 1/2/3`, `lensModel` cycling `35mm/50mm/65mm/80mm`, `isoSpeed`
cycling `100/300/500/700/900`, `rating` 0-5 (4 assets per value),
`colorLabel` cycling `red/yellow/green/blue/purple` (5/5/5/5/4),
`availability = 'online'` for all 24, and `capturedAt` timestamps all inside
2024-01-01 UTC 15 minutes apart. **No `evaluation_signals`,
`metadata_sync_state`, or `evaluation_failures` rows are seeded** — verified
2026-07-10 by querying a fresh `--smoke` catalog (`count(*)` was 0 for all
three tables). That means `signal:`, `xmp:pending`, `xmp:conflict`, and the
`likelyIssue`/`evaluationFailure`/`faceCount`/`ocrText` phrase predicates from
lib-004 all compile and run but return **0 of 24** against this fixture — a
fixture gap, not a bug; do not weaken the card to hide it.

Ground truth queries (all dry-run against a seeded `--smoke` catalog on
2026-07-10; SQL mirrors `CatalogRepository.compileClauses(_:)` exactly):
```bash
CAMERA=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE (json_valid(technical_metadata_json) AND LOWER(COALESCE(json_extract(technical_metadata_json,'\$.cameraMake'),'') || ' ' || COALESCE(json_extract(technical_metadata_json,'\$.cameraModel'),'')) LIKE LOWER('%SmokeCam 1%') ESCAPE '\\');")
# -> 8
KEYWORD=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.keywords') WHERE LOWER(value)=LOWER('batch-0'));")
# -> 6
RATING=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE CAST(json_extract(metadata_json,'\$.rating') AS INTEGER) >= 3;")
# -> 12
ISO=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE (json_valid(technical_metadata_json) AND CAST(json_extract(technical_metadata_json,'\$.isoSpeed') AS INTEGER) >= 500);")
# -> 14
COLOR=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.colorLabel') = 'green';")
# -> 5
SOURCE_ONLINE=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE availability='online';")
# -> 24 (== TOTAL; --smoke has no offline/missing/moved/stale assets, so source: can only be
#         shown returning everything or, for the untestable states, 0 — a fixture gap)
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library. Note the
   header count reads `$TOTAL` (24).
2. **camera** — type `camera:"SmokeCam 1"` (QUOTED — the value contains a
   space; see Sharp edges) into the query field
   (`--role AXTextField --contains "Search your library"`), press Return.
   Assert header count == `$CAMERA` (8) and a chip reading `Camera: SmokeCam 1`
   is shown. Clear the token; assert header restores to `$TOTAL`. Verified
   live in run-lib-iter1: quoted -> 8; unquoted `camera:SmokeCam 1` -> 24
   (token committed as `camera:SmokeCam`, " 1" dropped).
3. **keyword** (alias `tag:` recognized identically per
   `LibrarySearchIntent.swift:122-123` — not separately driven) — type
   `keyword:batch-0`, Return. Assert header count == `$KEYWORD` (6), chip
   `Keyword: batch-0`. Clear; assert restore to `$TOTAL`.
4. **rating** (aliases `rating:`/`rated:`/`star:`/`stars:`, all `>=N`
   semantics — see `LibrarySearchIntent.swift:136-138`; only `rating:` driven
   here, the others are exercised via bare-token forms in lib-004) — type
   `rating:3`, Return. Assert header count == `$RATING` (12), chip
   `Rating >= 3`. Clear; assert restore.
5. **iso** — type `iso:500`, Return. Assert header count == `$ISO` (14), chip
   `ISO >= 500`. Clear; assert restore. Note: `iso:` also accepts the `>=`
   separator form (`iso>=500`, same predicate — unit-tested in
   `LibrarySearchIntentTests.testParsesGreaterThanOrEqualFieldSeparatorAndLeavesInvalidFieldsAsSearchText`),
   not separately AX-driven.
6. **color** (aliases `color:`/`colour:`/`label:`, only `color:` driven) —
   type `color:green`, Return. Assert header count == `$COLOR` (5), chip
   `Green Label`. Type `color:ultraviolet` (invalid value) and Return; assert
   the token is **silently ignored** — no chip appears, header count stays at
   `$TOTAL` (24), and the literal text `color:ultraviolet` remains in the
   field as unrecognized residual text (per
   `LibrarySearchIntent.colorLabel(from:)` returning `nil` for unknown values,
   which makes `fieldPredicates(from:)` return `nil` and the whole token falls
   through to `residualTokens` — confirmed by
   `LibrarySearchIntentTests.testParsesGreaterThanOrEqualFieldSeparatorAndLeavesInvalidFieldsAsSearchText`,
   which asserts `color:ultraviolet` lands in `residualText` verbatim, not
   dropped). Clear the field; assert restore to `$TOTAL`.
7. **source** — type `source:online`, Return. Assert header count == `$SOURCE_ONLINE`
   (24, i.e. no narrowing against this fixture — expected, not a bug). Clear;
   assert restore.

## Expected
- Each field's header count exactly matches its `$VAR` ground truth and its
  chip text matches `LibrarySearchIntent`'s chip string for that predicate.
  **Fails if** the count is off by even one row, or the chip text disagrees
  with what `fieldPredicates(from:)` builds.
- Step 6's invalid `color:` value must produce **no predicate, no chip, and
  no count change** — the grammar's documented behavior per
  `LibrarySearchIntent.swift:130-132` (`colorLabel(from:)` returns `nil` ->
  `fieldPredicates` returns `nil` -> token falls to residual text, not an
  error toast). **Fails if** the app throws a visible error, silently applies
  some default color, or drops the token text entirely instead of leaving it
  in the field as residual text.
- Clearing each token must restore the header to `$TOTAL` every time. **Fails
  if** any token leaves a stale predicate applied after removal.

## Fields verified by source reading only (not independently AX-driven here)

These compile via the same `compileClauses(_:)` switch (exact SQL cited so a
future card or bug report can dry-run them directly) but are not driven live
in this card, either because the `--smoke` fixture cannot populate their
ground truth or to keep this card's Steps bounded:

- **lens** (`Sources/TeststripApp/LibrarySearchIntent.swift:121`): same
  LIKE-contains shape as camera, single field name, no aliases. SQL:
  `(json_valid(technical_metadata_json) AND LOWER(COALESCE(json_extract(technical_metadata_json,'$.lensModel'),'')) LIKE LOWER(?) ESCAPE '\')`.
  Dry-run confirmed 2026-07-10: `lens:35mm` -> 6 of 24.
- **person** (`:124`) — passthrough token (no structured `AppModel` filter
  property; ANDed when repeated, per `LibrarySearchIntent`'s own
  `searchFieldHelp` text and `LibrarySearchIntentTests.testParsesPersonFilterTokens`).
  SQL: `EXISTS (SELECT 1 FROM person_assets JOIN people ON people.id = person_assets.person_id WHERE person_assets.asset_id = assets.id AND people.name = ? COLLATE NOCASE)`.
  `--smoke` seeds no `people`/`person_assets` rows — untestable against this
  fixture; would need `--faces` or a people-seeded catalog.
- **folder**/**path** (`:126-128`): `original_path LIKE <prefix>% ESCAPE '\'`.
  Chip title is the path's last component only (`URL(fileURLWithPath:).lastPathComponent`).
- **from**/**after**/**since** and **before**/**until** (`:139-144`):
  `YYYY-MM-DD` parsed as a GMT calendar date via
  `LibrarySearchIntent.captureDate(from:)`
  (`Calendar` with `TimeZone(secondsFromGMT: 0)`); invalid calendar dates
  (e.g. `2026-02-31`) fail to construct and the token falls to residual text
  exactly like the invalid-color case (unit-tested in
  `testParsesGreaterThanOrEqualFieldSeparatorAndLeavesInvalidFieldsAsSearchText`).
  SQL: `capturedAt >= ?` / `capturedAt < ?` against
  `date.timeIntervalSince1970`.
- **date**/**day**/**captured** (`:145-154`): a single day expands to
  **two** predicates, `.capturedAtOrAfter(start)` AND `.capturedBefore(start+1day)`,
  but renders as **one** chip (`Date: 2026-02-04`) — confirmed by
  `LibrarySearchIntentTests.testParsesDateFieldAsSingleCaptureDay`. Not
  independently narrowing against `--smoke`: all 24 assets share
  2024-01-01, so `date:2024-01-01` -> 24 of 24 (dry-run confirmed
  2026-07-10) — can't distinguish "narrowed to the day" from "narrowed to
  nothing," a fixture gap. A future fixture with multi-day capture spread
  would let this actually narrow.
- **signal** (`:159-162`, aliases `signal:`/`evaluation:`/`kind:`) — exactly
  **15** `EvaluationKind` values (`Sources/TeststripCore/Evaluation/EvaluationSignal.swift:3-19`,
  confirmed by direct read, not inferred): `focus`, `motionBlur`, `exposure`,
  `aesthetics`, `framing`, `object`, `faceCount`, `faceQuality`, `ocrText`,
  `colorPalette`, `novelty`, `visualSimilarity`, `smile`, `eyesOpen`,
  `eyeSharpness`. `signal:faceCount` and `signal:faceQuality` compile to an
  extra `AND NOT EXISTS (dismissed_face_assets) AND NOT EXISTS (person_assets)`
  clause the other 13 kinds don't get
  (`CatalogRepository.swift:2374-2396`). `--smoke` seeds zero
  `evaluation_signals` rows, so every `signal:` value returns 0 of 24 against
  this fixture — untestable narrowing here; needs a catalog with evaluated
  assets (e.g. after running the evaluator against `--sample-photos`).
- **xmp:pending** / **xmp:conflict** (`:163-165`): SQL checks
  `metadata_sync_state.status = 'pending' | 'conflict'` joined on
  `asset_id`. `--smoke` seeds zero `metadata_sync_state` rows (no rating/flag
  write has happened yet at seed time) -> 0 of 24 for both, untestable
  narrowing here. `rate-writes-xmp-happy-path.md` is the card that actually
  produces sync state to test against.
- **session**/**worksession** and **import**/**importbatch**/**batch**
  (`:166-169`) — passthrough tokens (no structured `AppModel` property; see
  lib-005 for why). SQL membership is via `work_sessions.input_set_ids_json`/
  `output_set_ids_json` (session checks both, import checks output only) —
  too structurally complex for a simple ground-truth `SELECT count`; verified
  by reading `CatalogRepository.compileClauses` case `.workSession`/
  `.importBatch` (`CatalogRepository.swift:2517-2554`) and by
  `LibrarySearchIntentTests.testParsesQuotedFieldValuesAndImportBatch`. Not
  independently dry-run.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Multi-word field values REQUIRE quotes** — the tokenizer
  (`LibrarySearchIntent`'s quote-aware splitter, unit-tested in
  `testParsesQuotedFieldValuesAndImportBatch`) treats an unquoted space as a
  token boundary, so `camera:SmokeCam 1` commits as `camera:SmokeCam`
  (matching every SmokeCam-N) and **silently drops the trailing " 1"** into
  a separate bare token. Confirmed live in run-lib-iter1. Whether that
  silent truncation is acceptable UX (vs. an error, or auto-quoting) is an
  open product question pending Jesse's ruling — until then, cards must use
  the quoted form and must NOT treat the unquoted behavior as a pass/fail
  assertion.
- The grid is lazily virtualized — off-screen rows aren't in the AX tree, so
  don't rely on scanning for a filename; use the result-count header instead.
- Keep the app frontmost/warm while typing multi-character tokens — an
  idle-wedged AX tree drops keystrokes silently rather than erroring.
- `color:`/`colour:`/`label:` and `from:`/`after:`/`since:` and
  `before:`/`until:` and `rating:`/`rated:`/`star:`/`stars:` are true field
  aliases (same predicate, same chip) — driving one alias per family is
  sufficient; the parser doesn't special-case which alias was typed.
- An invalid field value (bad color name, unparseable date) does not error —
  it silently leaves the raw token text in the field as residual/free-text
  search. A card asserting "invalid input rejected" must check for *no chip
  and no count change*, not for an error message, which doesn't exist.

## Run status
NOT RUN (AX driving) — needs a live, human-present session per the "locked
console" trap in `test/scenarios/README.md`; no host GUI launch was permitted
for this authoring pass. All SQL in this card (camera, keyword, rating, iso,
color, source, lens, missingKeywords/unevaluated referenced by lib-004, and
the date/day-expansion count) was dry-run headlessly against a freshly seeded
`--smoke` catalog on 2026-07-10, using
`script/build_and_run.sh --smoke` to seed via `TeststripBench` (no
interactive window driving), reading counts directly with `sqlite3`, then
quitting the seeded process and discarding its throwaway
`$TMPDIR/teststrip-app-support.*` directory. Schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` (`version = 19`).
