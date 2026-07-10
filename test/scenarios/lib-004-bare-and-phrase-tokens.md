# lib-004: bare flag/rating words and multi-word phrase predicates narrow the grid

**What this covers**: `LibrarySearchIntent.parse` recognizes unprefixed
"natural language" tokens alongside the `field:value` grammar covered in
lib-003 — bare flag words (`pick`/`reject` and their synonyms), bare rating
forms (`3+`, `3stars`, `rating >= 3`-with-a-space, word forms like `three`),
and fixed two-word phrase predicates (`needs keywords`, `faces found`, etc.).
These are parsed by `flagPredicate(for:)` (`LibrarySearchIntent.swift:272-281`),
`ratingPredicate(in:at:)` (`:283-311`), and `phrasePredicate(in:at:)`
(`:313-352`) — all three run *after* `fieldPredicates(from:)` fails to match
a token, so a bare word never shadows a `field:value` token typed elsewhere
in the same query. Unit coverage:
`LibrarySearchIntentTests.testParsesPhotographerFilterTermsAndKeepsResidualSearchText`,
`.testParsesReviewQueueTerms`, `.testParsesRatingFieldFilter`. This card is
the AX-level companion.

## Pre-state
Same seed as lib-003 — reuses its `$DB`/`$TOTAL`/`$RATING` if run in the same
session, otherwise reseed:
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")   # 24
```

Ground truth dry-run against a seeded `--smoke` catalog, 2026-07-10 (SQL
mirrors `CatalogRepository.compileClauses(_:)`):
```bash
PICK=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
# -> 6
REJECT=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject';")
# -> 5
RATING3=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE CAST(json_extract(metadata_json,'\$.rating') AS INTEGER) >= 3;")
# -> 12
MISSING_KEYWORDS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE NOT EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.keywords'));")
# -> 0 (every --smoke asset is seeded with keywords ["smoke","batch-N"])
UNEVALUATED=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE NOT EXISTS (SELECT 1 FROM evaluation_signals WHERE evaluation_signals.asset_id = assets.id);")
# -> 24 (--smoke seeds zero evaluation_signals rows, so *every* asset is unevaluated)
```

## Steps

### Bare flag words (single-select: typing a second flag word replaces, not ANDs, the first)
`flagPredicate(for:)` recognizes `pick`/`picks`/`picked`/`keeper`/`keepers`/
`select`/`selects`/`selected` -> `.flag(.pick)`, and `reject`/`rejects`/
`rejected`/`rejecting` -> `.flag(.reject)`. `LibrarySearchIntent.parse` calls
`removeFlagPredicates(from:&predicates)` before appending the new one
(`:63`), so **at most one flag predicate survives regardless of how many
flag words appear in the query** — this is the single-select semantics,
confirmed by reading `LibrarySearchIntent.swift:62-69` (there is no unit test
asserting this specific replace-not-AND behavior for two *different* flag
words in one query — `LibrarySearchIntentTests` only exercises one flag word
per parse call, e.g. `testParsesPhotographerFilterTermsAndKeepsResidualSearchText`'s
lone `PICKS`).

1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library. Confirm
   header reads `$TOTAL`.
2. Type `keeper` (a pick synonym), Return. Assert header == `$PICK` (6), chip
   `Pick`.
3. Without clearing, type ` reject` appended to the existing text (so the
   field now reads `keeper reject`) and Return. Assert header == `$REJECT`
   (5) and only **one** chip is shown, reading `Reject` — proving the second
   flag word replaced rather than ANDed with the first (an AND would produce
   0, since no asset is both pick and reject). **Fails if** two flag chips
   appear or the count is 0.
4. Clear the field; assert restore to `$TOTAL`.

### Bare rating forms
`ratingPredicate(in:at:)` recognizes three shapes ahead of the `rating:`
field form from lib-003: a single compact token (`3+`, `3stars`, `3star`, or
`>=3` fused, via `compactRatingValue`, `:354-369`); a bare number/word
immediately followed by a separate `star`/`stars` token (`3 stars`, two
tokens); and `rating >= 3` / `rating`+word (three or two tokens, `:295-310`).
`ratingValue(from:)` (`:371-390`) also accepts the English words `one`
through `five`. All forms produce the identical `.ratingAtLeast(N)` predicate
and `"Rating >= N"` chip as `rating:N` — same `>=` semantics, not exact-match.

5. Type `3+`, Return. Assert header == `$RATING3` (12), chip `Rating >= 3`.
   Clear; assert restore.
6. Type `3stars`, Return. Assert header == `$RATING3` (12), same chip. Clear;
   assert restore.
7. Type `three stars` (word form + explicit `stars` token), Return. Assert
   header == `$RATING3` (12), same chip. Clear; assert restore.

### Phrase predicates (fixed two-word forms)
`phrasePredicate(in:at:)` recognizes `unevaluated`/`unanalyzed` as a single
bare word, and these two-token phrases (first/second token pairs, `:330-351`):
`needs|need|missing|without|no keywords|keyword` -> `.missingKeywords`;
`needs|need evaluation|analysis|ai`, `not evaluated` -> `.unevaluated`;
`faces|people found` -> `.evaluationKind(.faceCount)`; `ocr|text found` ->
`.evaluationKind(.ocrText)`; `likely issues|issue` -> `.likelyIssue`;
`provider failures|failure` -> `.evaluationFailure`; `xmp pending` ->
`.metadataSyncPending`; `xmp conflicts|conflict` -> `.metadataSyncConflict`.

8. Type `unevaluated`, Return. Assert header == `$UNEVALUATED` (24 — every
   `--smoke` asset, since none has been evaluated), chip `Not analyzed yet`.
   This is the one phrase predicate `--smoke` can actually demonstrate
   narrowing-to-nonzero for (all the evaluation-signal-backed phrases below
   return 0 against this fixture — a fixture gap, not a bug). Clear; assert
   restore.
9. Type `needs keywords`, Return. Assert header == `$MISSING_KEYWORDS` (0 —
   every `--smoke` asset already has keywords), chip `Needs Keywords`, and
   the grid shows zero cells. Clear; assert restore.
10. Type `faces found`, Return. Assert header == 0 (no `evaluation_signals`
    rows seeded), chip `Faces Found`. This asserts the predicate *compiles
    and runs cleanly* against an evaluation-signal-backed query even with
    zero matching rows — not narrowing per se (fixture gap, documented, not
    hidden). Clear; assert restore.

## Expected
- Each step's header count and chip exactly match the `$VAR` ground truth (or
  the documented 0-of-24 fixture-gap case). **Fails if** any count is off, a
  chip is missing, or a second flag chip survives the single-select case in
  step 3.
- Step 3 is the crux assertion of this card: **Fails if** the flag filter
  becomes cumulative (AND) instead of single-select (replace) — that would be
  a silent behavior change from what `removeFlagPredicates` implements today.
- All three bare-rating forms (`3+`, `3stars`, `three stars`) must produce
  the *identical* chip/count as `rating:3` from lib-003 — **fails if** any
  form parses to a different rating or fails to parse at all.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Bare rating and phrase-predicate matching happens token-by-token *after*
  field-token and flag-word matching fail for that token — a query like
  `rating:3 3stars` runs both matchers independently (two separate
  `.ratingAtLeast` predicate attempts, deduped by `append(_:to:)`'s
  `contains` check, `LibrarySearchIntent.swift:453-456`), not a conflict.
  Not driven here; documented for anyone extending this card.
- `needs keywords` == 0 of 24 against `--smoke` is the *expected* result, not
  a broken query — don't "fix" the card by picking a different fixture that
  happens to have unkeyworded assets unless the fixture change is made
  honestly and documented, per `test/scenarios/README.md`'s fixture-status
  policy.
- Typing into the field mid-session (step 3's "append without clearing")
  requires the field's cursor to be at the end; `ax_drive.sh type` sets the
  whole field value, so drive it by setting the full string `keeper reject`
  rather than trying to append keystrokes.

## Run status
NOT RUN (AX driving) — needs a live, human-present session; no host GUI
launch was permitted for this authoring pass. All SQL in this card (pick,
reject, rating>=3, missingKeywords, unevaluated) was dry-run headlessly
against a freshly seeded `--smoke` catalog on 2026-07-10 via
`script/build_and_run.sh --smoke` (`TeststripBench` seeding only, no
interactive window driving), then the seeded process was quit and its
throwaway `$TMPDIR/teststrip-app-support.*` directory discarded. Schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` (`version = 19`).
