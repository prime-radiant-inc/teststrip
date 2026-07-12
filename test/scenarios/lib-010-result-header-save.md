# lib-010-result-header-save: result count, plain-text interpretation, catalog-backed suggested chips (active-field suppressed), and the 3-way Save menu

**What this covers**: `libraryResultHeader`
(`Sources/TeststripApp/LibraryGridView.swift`) built from
`LibraryResultHeaderPresentation` (`Sources/TeststripApp/LibraryResultHeaderPresentation.swift`):
a match-count line ("N photos" / "1 photo"), an optional grey
"No filter matched — searching file names and photo text for “…”"
interpretation line shown only when
`LibrarySearchIntent.parse` leaves residual free text after stripping
structured tokens (`interpretation(for:)`), a horizontally scrolling row of
catalog-backed suggested chips whose *fields already active* are suppressed
(`addIfNeeded`, keyed by `token.field`), and a "Save ▾" menu (`saveMenu`)
with exactly the 3 `SaveAction` cases — "Save Search…", "Save as
Snapshot…", "Save Selection as Set…" — each present only if its gating bool
is true: `canSaveDynamicSet` = `model.canSaveCurrentLibraryQuery` =
`currentLibraryQuery() != nil`, `canSaveSnapshotSet` =
`model.canSaveCurrentAssetScopeSnapshot` = `catalog != nil &&
!assets.isEmpty`, `canSaveManualSet` = `model.canSaveSelectedAssetAsManualSet`
= `catalog != nil && !currentManualSelectionAssetIDs.isEmpty`.

**Task 8 change (spec §2b)**: the whole row is now gated on
`LibraryResultHeaderPresentation.hasContent` (interpretation present, OR
suggested tokens non-empty, OR save actions non-empty) — an empty second
row no longer renders. On the `--smoke` fixture, `canSaveSnapshotSet` is
true whenever the catalog is non-empty, so `saveActions` is never empty and
the row (including the match count) still renders in every step below; the
row would only disappear on a genuinely empty catalog with no query and no
suggestions (not exercised by this card's fixture).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
RATING4PLUS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.rating')>=4;")
PICKS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
REJECTS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject';")
SIGNALS=$(sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;")
```
Confirmed against a seeded `--smoke` catalog 2026-07-10: `TOTAL=24`,
`RATING4PLUS=8`, `PICKS=6`, `REJECTS=5`, `SIGNALS=0` — **`--smoke` seeds no
`evaluation_signals` rows at all**, so the 4 signal-candidate suggested
chips (focus/object/ocrText/faceCount) will never appear against this
fixture regardless of active filters; steps that need them require
`--sample-photos` or a post-import evaluate pass and are noted as such
below.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Assert the header reads "`$TOTAL` photos" with no interpretation line
   (empty query).
3. Type free text only, e.g. `sunset`, and Return. Assert the header shows
   "No filter matched — searching file names and photo text for “sunset”" (fully residual, no structured tokens).
4. Clear and type `rating:4` alone, Return. Assert **no** interpretation
   line (fully structured, no residual per the
   `LibraryResultHeaderTests.swift` unit-test contract already covering
   this case) — only the "N photos" count.
5. With no filters active, assert suggested chips include "Rating >= 4"
   (since `RATING4PLUS=8 > 0` drives `hasResults(.fiveStars)`), "Pick"
   (`PICKS=6>0`), and "Reject" (`REJECTS=5>0`) — and assert none of the 4
   signal chips appear (consistent with `SIGNALS=0`).
6. Apply the "Rating >= 4" suggested chip (click it). Assert it disappears
   from the *suggested* row (its field, `.rating`, is now active — per
   `addIfNeeded`'s suppression) while remaining visible as an *active
   filter* chip (per lib-008). Assert "Pick"/"Reject" suggestions remain
   in the suggested row since their fields are untouched.
7. With no selection and no active query, assert the Save ▾ menu offers
   only "Save as Snapshot…" (catalog non-empty → `canSaveSnapshotSet` true;
   no structured/free-text query → `canSaveDynamicSet` false; no manual
   selection → `canSaveManualSet` false).
8. Apply `rating:4` again (any structured filter). Assert Save ▾ now also
   offers "Save Search…".
9. Select one grid cell (click a thumbnail). Assert Save ▾ now also offers
   "Save Selection as Set…", for 3 total actions.

## Expected
- Step 2-4: interpretation line appears exactly when residual free text
  exists. **Fails if** it appears for a fully-structured query or is
  missing for a plain-text one.
- Step 5-6: suggested chips are catalog-backed and active-field-suppressed.
  **Fails if** a chip for an empty queue appears, a chip for a non-empty
  queue is missing, or an active field's chip isn't suppressed from
  suggestions.
- Step 7-9: Save ▾ shows exactly 1, then 2, then 3 actions as the 3 gating
  conditions independently flip true. **Fails if** any action appears
  before its condition is met or is missing after.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
The `ReviewQueue.fiveStars` case backs the "Rating >= 4" suggestion
(`LibraryResultHeaderPresentation.swift:103-105`) — the enum case name says
"five stars" but the actual threshold used is `rating>=4`, not `rating==5`
or `rating>=5`. This is a real naming/semantics mismatch: anyone reading
`ReviewQueue.fiveStars` without checking this call site would reasonably
assume rating 5 only. Worth flagging for a rename (`fiveStars` →
something like `highRated`) — not fixed here per the task's instructions
to document, not fix.

## Run status
NOT RUN — GUI/AX driving was not attempted this session. Header/suggestion/
save-menu logic confirmed by reading
`Sources/TeststripApp/LibraryResultHeaderPresentation.swift` in full (all
139 lines) and `Sources/TeststripApp/LibraryGridView.swift:744-841`, plus
the three gating booleans at `AppModel.swift:2728-2730, 2847-2853`. The
empty-query/no-interpretation and residual-text cases are also covered by
`Tests/TeststripAppTests/LibraryResultHeaderTests.swift` (already
green per unit tests, per task briefing). SQL dry-run headlessly against a
fresh `--smoke` catalog on 2026-07-10 (`TOTAL=24`, `RATING4PLUS=8`,
`PICKS=6`, `REJECTS=5`, `SIGNALS=0`); schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`.
