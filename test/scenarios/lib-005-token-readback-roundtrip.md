# lib-005: structured filter state round-trips through query token text

**What this covers**: `LibraryQueryToken.tokens(from:)`
(`Sources/TeststripApp/LibraryQueryTokenField.swift:117-183`) reads
`AppModel`'s **14** structured library-filter properties (rating, flag,
keyword, folder, camera, lens, iso, dateFrom, dateBefore, color, source,
signal, xmpPending, xmpConflict — enumerated exactly by
`LibraryQueryToken.Field`, `:10-33`; `needsKeywords`/`needsEvaluation`/
`likelyIssues`/`providerFailures` are also structured `AppModel` properties
and produce tokens but aren't in the round-trip tests below since they carry
no `Value` payload to restore beyond a bool flip) back into chip display text
and a `LibrarySearchIntent`-compatible `field:value` string
(`token.searchText`, `:55-99`), and `LibraryQueryToken.apply(_:to:)` /
`.remove(_:from:)` write/clear exactly the one matching `AppModel` property.
**This is a unit-test-verifiable round trip** — the primary verification
method for this card is
`Tests/TeststripAppTests/LibraryQueryTokenTests.swift`, not a live AX drive;
see the note in `docs/dogfooding.md`-adjacent testing guidance and
CLAUDE.md's "every user-facing feature gets an automated scenario" bar, which
this card satisfies via the pre-existing, comprehensive unit suite plus one
thin AX spot-check below.

## Why `person:`, `session:`, `import:` don't read back

`LibraryQueryToken.tokens(from: model)` has **no case** for `.person`,
`.workSession`, or `.importBatch` — there is no `AppModel` property backing
them (no `personFilterText`, no `sessionFilterText`, etc.). Confirmed by
reading `LibraryQueryTokenField.swift`:
- Doc comment on `tokens(from:)` (`:115-116`): "Free text / `person:` etc.
  already round-trip through `librarySearchText` and are not represented
  here — they remain visible via the plain text field."
- `Field.passthrough` case doc (`:29-32`): "Recognized by
  `LibrarySearchIntent` but with no structured `AppModel` property backing it
  (e.g. `person:`). Round-trips through `librarySearchText` verbatim."
- `searchTextFragment(for:)` (`:374-388`) is the mechanism: on parse, any
  predicate `structuredToken(for:)` doesn't recognize (its `default: return
  nil`, `:369-371`, covers exactly `.person`, `.workSession`, `.importBatch`,
  `.text`, `.withinGeoBounds`, `.likelyPick`) gets reconstructed as raw
  `field:value` text and appended to `model.librarySearchText` instead of
  becoming a `LibraryQueryToken`. It then round-trips as plain text through
  the search field itself, not through the chip-token mechanism this card
  covers.

I could not find a comment stating *why* these three specifically were never
given dedicated `AppModel` properties (as opposed to some other design where
they would be) — only the mechanical fact that they aren't, and the
passthrough fallback that makes their absence harmless. Read
`LibraryQueryTokenField.swift:293-296` and `:307-310` for the full mechanical
rationale if extending this list.

## Round-trip quoting rules

`LibraryQueryToken.searchText`'s `quoted(_:)` helper (`:101-103`): a value is
wrapped in `"..."` **only if it contains a space**; single-word values are
emitted bare. Applies to `keyword:`, `folder:`, `camera:`, `lens:`. Confirmed
by `LibraryQueryTokenTests.testCameraRoundTrips` (`"Canon EOS R5"` — un-quoted
in the assertion because the test checks the restored `AppModel` property,
not the raw string, but `searchText` for that token would render as
`camera:"Canon EOS R5"` per the quoting rule) and directly by reading
`LibrarySearchIntent.searchTokens(from:)` (`:404-433`), the tokenizer that
must be able to consume that quoted form back — it treats `"` and `'` as
matching quote delimiters that suppress internal whitespace splitting.
Numeric/enum/date fields (`iso:`, `rating:`, `color:`, `source:`, `signal:`,
dates) never need quoting since their values never contain spaces.

## Primary verification: unit tests (already passing, cited not re-run)

`Tests/TeststripAppTests/LibraryQueryTokenTests.swift` is the authoritative
round-trip proof:
- `testRatingRoundTrips` / `testFlagRoundTrips` / `testKeywordRoundTrips` /
  `testFolderRoundTrips` / `testCameraRoundTrips` / `testLensRoundTrips` /
  `testISORoundTrips` / `testDateRangeRoundTrips` / `testColorRoundTrips` /
  `testSourceRoundTrips` / `testSignalRoundTrips` /
  `testXMPPendingRoundTrips` / `testXMPConflictRoundTrips` — one test per
  structured field, each sets the `AppModel` property, reads the token back,
  asserts `token.display`, then applies the token to a **fresh** model and
  asserts the property matches the original — proving `tokens(from:)` and
  `apply(_:to:)` are true inverses for that field.
- `testRemovingEachTokenClearsOnlyItsOwnFilter` — fully filters a model on
  all 14 fields, removes each token in turn, and asserts *exactly* that
  field cleared while all 13 others survived; also asserts the canonical
  field ordering `[.rating, .flag, .keyword, .folder, .camera, .lens, .iso,
  .dateFrom, .dateBefore, .color, .source, .signal, .xmpPending,
  .xmpConflict]` matches `tokens(from:)`'s emission order exactly.
- `testEvaluationKindFilterRendersExactlyOneChip` /
  `testLegacyRowsNotBackedByTokensSurvive` — dedupe against the legacy
  `activeLibraryFilterRows` sidebar chips, specifically the `.faceCount`/
  `.ocrText` review-queue-title collision case.
- `testMixedFreeTextParsesToTwoTokensAndResidual` — proves `person:` stays in
  `librarySearchText` (`model.librarySearchText.contains("person:Maya")`)
  while `rating:3` becomes a structured token, in a single mixed parse.

Run status of this suite: not re-executed as part of authoring this card
(the task was scoped to writing cards, not running `swift test`); the last
known-passing state is whatever CI/the working tree currently reflects. A
runner executing this card should confirm with
`swift test --filter LibraryQueryTokenTests` before relying on it as a green
gate.

## Thin AX spot-check (the only part of this card that needs a live app)

Rather than re-driving all 14 fields live (redundant with the unit suite and
with lib-003's 6 already-driven fields), this spot-check drives **one**
token end-to-end through the real chip UI to prove the token-field chip
rendering itself (not just the `LibraryQueryToken` struct in isolation)
agrees with `apply(_:to:)`.

### Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")   # 24
ISO=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE (json_valid(technical_metadata_json) AND CAST(json_extract(technical_metadata_json,'\$.isoSpeed') AS INTEGER) >= 700);")
# -> 9 of 24. Recount: --smoke's isoSpeed = 100 + (index % 5) * 200 cycles
# 100/300/500/700/900; over 24 assets residues 0-3 occur 5x and residue 4
# occurs 4x, so iso >= 700 = residue 3 (700, 5 assets) + residue 4 (900,
# 4 assets) = 9. Confirmed live in the VM run (run-lib-iter1: header 9).
```

### Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Type `iso:700`, press Return. Assert a chip reading `ISO >= 700` appears
   and the header count == `$ISO` (9).
3. Click the chip's "x" (or equivalent remove control). Assert the chip
   disappears and the header restores to `$TOTAL` (24) — proving
   `LibraryQueryToken.remove(_:from:)`'s `minimumISOFilter = nil` actually
   reaches the live `AppModel` bound to the rendered grid, not just a copy.

### Expected
- Step 2: chip text and count match `$ISO` exactly.
- Step 3: chip removal clears `minimumISOFilter` and the count restores.
  **Fails if** the chip's remove control doesn't call `LibraryQueryToken.remove`,
  or if removing the chip leaves the filter applied (stale-filter bug class
  already covered generically in lib-003/004, spot-checked here for the
  read-back direction specifically).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Don't re-derive all 14 fields' AX assertions here — that's what
  `LibraryQueryTokenTests.swift` already proves at the unit level, and
  lib-003 already drives 6 of them live through the *parse* direction
  (`LibraryQueryToken.parse`, typed text -> tokens). This card's job is the
  *read-back* direction (`tokens(from:)`, structured state -> chip) and the
  removal wiring, which the unit tests can't reach because they don't render
  the live SwiftUI chip view.
- `LibraryQueryToken.tokens(from:)`'s emission order is significant and
  tested (`testRemovingEachTokenClearsOnlyItsOwnFilter`'s `allFields`
  array) — if a card asserts chip *order* on screen, use that exact ordering,
  not alphabetical or insertion order.

## Run status
PARTIALLY VERIFIED — round-trip and removal-isolation logic confirmed via
existing unit tests (cited above, not re-run in this pass; re-run
`swift test --filter LibraryQueryTokenTests` to confirm current green state).
The AX spot-check (Steps 1-3) PASSED in the VM (run-lib-iter1): chip
"ISO >= 700", header 9, removal restored 24. The one
piece of SQL in this card (`iso:700` -> 9 of 24) was dry-run headlessly
against a freshly seeded `--smoke` catalog on 2026-07-10 via
`script/build_and_run.sh --smoke` (`TeststripBench` seeding only), then the
seeded process was quit and its throwaway `$TMPDIR/teststrip-app-support.*`
directory discarded. Schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` (`version = 19`).
