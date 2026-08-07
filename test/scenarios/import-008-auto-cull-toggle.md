# import-008-auto-cull-toggle: Autopilot-after-import proposes over exactly the imported set, provisionally

**What this covers**: inventory item 16 — the import confirmation sheet's
"Autopilot cull after reading" toggle. When armed, once the read (evaluation)
pass finishes for the freshly imported asset IDs, Autopilot proposes
keeps/rejects automatically — scoped to exactly those IDs, not the whole
catalog. Per this project's confirm-before-write invariant
(`CLAUDE.md`), the proposals are provisional: nothing lands in
`assets.metadata_json`'s `flag`/`rating` fields until an explicit commit
gesture. This card's negative assertion — nothing written pre-confirm — is
the load-bearing check; do not weaken it.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Baseline verified 2026-07-10 against a fresh `--smoke` seed (re-verified
2026-08-06: `autopilot_proposals` no longer exists as a table — SP-D0
dropped it forward-only — so the baseline is the ghost count instead):
no asset carries a ghost (`SELECT count(*) FROM assets WHERE EXISTS (SELECT
1 FROM json_each(metadata_json,'$.aiUnconfirmedFields') WHERE value='flag')`
→ 0). 11/24 seeded assets already carry a `flag` (`smoke-N.jpg`'s
`metadata_json` has `"flag":"reject"` or `"pick"` per the README's documented
baseline) — this card's assertions must be scoped to the *newly imported*
asset IDs, not the whole catalog, since the seed itself isn't a clean slate.

A fixture folder of new photos is needed (distinct from the 24 already
seeded), e.g. via the bench seeder used by `duplicate-detection-import-new-only.md`:
```bash
FIXTURES=$(mktemp -d)/autocull
swift run TeststripBench seed-dup-fixtures "$FIXTURES"
IMPORT_DIR="$FIXTURES/card2"   # has M=2 brand-new frames beyond card1's overlap
```
(Any folder of ≥1 new, evaluable photos works; `card2` is reused here only
because the seeder already exists and is proven in the dedup card — no new
fixture needed.)

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Open the card/folder import sheet (typed-path route, per
   `duplicate-detection-import-new-only.md`'s Sharp edges:
   `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`), type `$IMPORT_DIR`.
3. In the confirmation sheet, expand the **"Options"** disclosure (these
   toggles moved there under the SheetScaffold conversion,
   `Sources/TeststripApp/LibraryGridView.swift`). Assert the toggle exists
   with the exact label **"Autopilot cull after reading"**, defaults **off**
   (`autopilotAfterImport ?? false`, and `ImportConfirmationDraft.swift:249`),
   and is `.disabled` whenever "Read imported frames automatically" is off
   (autopilot cannot run without the read pass that feeds it).
   Turn **on** both "Read imported frames automatically" (default on) and
   "Autopilot cull after reading".
4. Start the import; wait for it to complete, then wait for the read
   (evaluation) pass and the armed autopilot run to resolve. The armed run
   fires once every imported asset's evaluations have resolved — no earlier
   (`runImportAutopilotIfArmedAndResolved`,
   `Sources/TeststripApp/AppModel.swift:8011-8020`) — then disarms itself, so
   poll until a `.recognition` work session tied to the import is
   `completed` and the imported set's ghost count has stabilized (no live
   table to poll any more — see Step 6's ghost query):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM work_sessions WHERE kind='recognition' AND status IN ('queued','running');"
   ```
5. **Record the imported asset IDs** (ground truth for scoping):
   ```bash
   sqlite3 "$DB" "SELECT id FROM assets WHERE original_path LIKE '%/card2/%' ORDER BY id;"
   ```
6. **Scope assertion**: every ghost-carrying asset from this run belongs to
   the imported set, and no ghost exists on any of the 24 pre-seeded smoke
   assets:
   ```bash
   sqlite3 "$DB" "SELECT id FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
   ```
7. **Provisional-write negative assertion** (the load-bearing check): before
   any confirming click, none of the imported assets' `metadata_json` has a
   `flag` or non-zero `rating` written by autopilot:
   ```bash
   sqlite3 "$DB" "SELECT id, metadata_json FROM assets WHERE original_path LIKE '%/card2/%';"
   ```
   Assert every row's `metadata_json` still reads `"flag":null` (or absent)
   and `"rating":0` — `commitAutopilotProposals` is the only place that
   writes `updatedMetadata.flag`
   (`Sources/TeststripApp/AppModel.swift:7784-7838`, write at :7809-7812), and
   it only runs from an explicit commit gesture (Autopilot Review → Commit),
   never automatically post-import.
8. Assert every ghost from this run is still unconfirmed
   (`aiUnconfirmedFields` still contains `flag` — there is no separate
   `status` column any more; the ghost's mere presence in `metadata_json`
   **is** "pending", per `AutopilotGhost.kind(in:)`):
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
   ```
9. Open the Cull sidebar's "Autopilot Proposals" source (present whenever
   any ghost exists) and commit the ghosts for the imported set (the normal,
   explicit confirm gesture — see `cull-017-autopilot-review.md` for the
   click sequence). Re-run Step 7's query: now assert the imported assets DO
   carry the committed `flag` values, and none of them carry a ghost any
   more (`aiUnconfirmedFields` no longer contains `flag` for those rows).

## Expected
- Step 3: toggle label, default-off, and read-gated-disabled state must match
  exactly. **Fails if** the toggle is on by default (would silently cull an
  import the user didn't ask to auto-cull) or is enabled while reads are off
  (nothing to propose from).
- Step 6: **fails if** any ghost-carrying asset is one of the 24 pre-seeded
  smoke assets — proves the scope leaked beyond `armedAutopilotImportAssetIDs`
  to the whole visible catalog.
- Step 7 (pre-commit): **fails if** any imported asset's `flag`/`rating`
  changed before the explicit commit — this is the confirm-before-write
  invariant; a failure here is a P0, not a nitpick.
- Step 9 (post-commit): **fails if** committing does NOT write the flags —
  proves the commit gesture itself is wired, so Step 7's negative isn't
  vacuously true because commit is broken.

## Cleanup
```bash
rm -rf "$FIXTURES"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- The armed run guards on **both** "no pending evaluation" and "no in-flight
  evaluation" (`Sources/TeststripApp/AppModel.swift:8013-8018`) before firing
  once, then disarms (`armedAutopilotImportAssetIDs = nil`,
  `autopilotArmedForActiveImport = false`, :8019-8020). If a second import is
  armed while the first is still resolving, the two asset-ID sets union
  (`.formUnion`, :8005) — a card that imports twice in quick succession with
  the toggle on both times would see one combined autopilot run over both
  imports' assets, not two separate runs. This card only exercises a single
  import, so it doesn't hit that path, but a future card should if the union
  behavior needs its own verification.
- The per-import toggle runs regardless of the standing global
  `autopilotEnabled` default (`runArmedImportAutopilot`,
  `Sources/TeststripApp/AppModel.swift`): once the sheet's "Autopilot cull
  after reading" is armed for an import, it fires on that import's assets
  even if `model.autopilotEnabled` is false. `autopilotEnabled` only seeds the
  toggle's *initial* checked state when the sheet opens
  (`LibraryGridView.swift:2531`); it is not a second gate. (Previously the
  armed run additionally guarded on the global flag, so an explicit per-import
  opt-in silently no-op'd whenever the global default was off — fixed;
  see `testAutopilotArmedImportRunsEvenWhenGlobalAutopilotIsDisabled` and
  `testUnarmedImportDoesNotRunAutopilotEvenWhenGlobalAutopilotIsEnabled` in
  `AppModelTests.swift`.)

## Run status
SQL-GROUNDED, AX-UNRUN. Toggle label, default state, disabled-gating, the
armed-scope machinery (`scheduleImportAutoEvaluationIfEnabled`,
`runImportAutopilotIfArmedAndResolved`), the (now-dropped) `autopilot_proposals`
schema, and the commit-only write path (`commitAutopilotProposals`) were all
confirmed by reading source with file:line references above on 2026-07-10. The
ghost-baseline-empty and 11/24-flagged-at-seed facts were confirmed against
a freshly seeded `--smoke` catalog the same day. The full
import → armed-autopilot → provisional-check → commit click-through needs a
human-present or isolated-console re-run; not run live this session due to
concurrent-agent build contention on the shared `dist/Teststrip.app`. Schema
per `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (version 19).

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: `autopilot_proposals`
no longer exists as a table (SP-D0 dropped it forward-only) — the baseline,
Step 4's poll, Step 6's scope assertion, and Step 8's status check all
became ghost queries against `metadata_json`/`aiUnconfirmedFields`; Step 9's
"commit the proposals" now routes through the Cull sidebar's "Autopilot
Proposals" source rather than an unspecified "Autopilot Review UI".
Supersedes prior status: the 2026-07-10 SQL-grounded read cited the
`autopilot_proposals` schema directly — not valid evidence for a table that
no longer exists. Needs a fresh VM run.
