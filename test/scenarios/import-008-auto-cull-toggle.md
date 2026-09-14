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
   (`autopilotAfterImport ?? false`, and `ImportConfirmationDraft.swift:269`),
   and is `.disabled` whenever "Read imported frames automatically" is off
   (autopilot cannot run without the read pass that feeds it).
   Turn **on** both "Read imported frames automatically" (default on) and
   "Autopilot cull after reading".
4. Start the import; wait for it to complete, then wait for the read
   (evaluation) pass and the armed autopilot run to resolve. The armed run
   fires once every imported asset's evaluations have resolved — no earlier
   (`runImportAutopilotIfArmedAndResolved`,
   `Sources/TeststripApp/AppModel.swift:10505-10513`) — then disarms itself, so
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
   (`Sources/TeststripApp/AppModel.swift:10252-10284`, write at :10268-10271), and
   it only runs from an explicit commit gesture (Autopilot Review → Commit),
   never automatically post-import.
8. Assert every ghost from this run is still unconfirmed
   (`aiUnconfirmedFields` still contains `flag` — there is no separate
   `status` column any more; the ghost's mere presence in `metadata_json`
   **is** "pending", per `AutopilotGhost.kind(in:)`):
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
   ```
9. Open the sidebar's "AI Suggestions" source (present whenever
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
  evaluation" (`Sources/TeststripApp/AppModel.swift:10506-10509`) before firing
  once, then disarms (`armedAutopilotImportAssetIDs = nil`,
  `autopilotArmedForActiveImport = false`, :10510-10511). If a second import is
  armed while the first is still resolving, the two asset-ID sets union
  (`.union`, :10496) — a card that imports twice in quick succession with
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
  (`LibraryGridView.swift:2696`); it is not a second gate. (Previously the
  armed run additionally guarded on the global flag, so an explicit per-import
  opt-in silently no-op'd whenever the global default was off — fixed;
  see `testAutopilotArmedImportRunsEvenWhenGlobalAutopilotIsDisabled` and
  `testUnarmedImportDoesNotRunAutopilotEvenWhenGlobalAutopilotIsEnabled` in
  `AppModelTests.swift`.)
- **Step 7's pre-commit "still reads `\"flag\":null`" expectation appears to
  contradict this card's own Steps 6/8/9 and the project's auto-apply-with-
  provenance invariant — flagged, not fixed.** Step 7 asserts that before
  any confirming click, none of the imported assets' `metadata_json` has a
  `flag` written, and calls a failure there a P0. But Steps 6, 8, and 9 all
  assume the opposite: that a ghost (a tentative, AI-unconfirmed `flag`
  value already sitting in `metadata_json`) exists on the imported assets
  *before* the commit gesture — Step 6 queries for ghost-carrying assets,
  Step 8 asserts those ghosts' `aiUnconfirmedFields` still contains `flag`,
  and Step 9 commits "the ghosts for the imported set". Reading the source
  directly confirms the ghost side: `runArmedImportAutopilot`
  (`Sources/TeststripApp/AppModel.swift:10515-10526`) calls `runAutopilot`
  (`:10025-10073`), which calls `applyTentativeAutopilotProposals`
  (`:10086-10133`) — that function writes `updatedMetadata.flag` and inserts
  `.flag` into `aiUnconfirmedFields` (`:10107-10108`) via
  `catalog.repository.updateMetadata` (`:10122`) **immediately**, for any
  qualifying proposal, matching `CLAUDE.md`'s auto-apply-with-provenance
  invariant (machine labels land at once, tagged `origin`/unconfirmed, and
  only an explicit gesture confirms them — auto-apply is not the same as
  "unwritten until confirmed"). This is a **pre-existing** issue — it
  predates SP-D0 and is not something this branch introduced or should
  guess-fix. What's established: the source read above says a ghost's
  `flag` is written to `metadata_json` pre-commit. What's NOT established:
  whether that's what a live run actually shows for *this exact* armed-
  import path (Step 7 has never been driven live — see Run status), or
  whether Step 7's author had something else in mind (e.g. a `rating` field,
  or a build predating this write path) that a live run would clarify.
  **The next live run of this card must resolve this empirically before
  trusting either Step 7 or Steps 6/8/9 at face value** — do not report a
  Step 7 `"flag":null` failure as a P0 without first checking whether it's
  actually this contradiction surfacing.

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

**Flagged 2026-08-06 (Task 9 review)**: Step 7's pre-commit "flag stays
null" expectation looks like it contradicts Steps 6/8/9 and the auto-apply-
with-provenance invariant — see the new Sharp edges bullet above. Pre-
existing, not caused by SP-D0; unresolved by any live run so far. The next
live run must settle which side is right before either is trusted.

## Run status
**LIVE RUN 2026-09-14, Tart VM `teststrip-e2e`** (`script/vm_scenario_run.sh`, run dir
`smoke-1789375947`, `launch smoke`, typed-path import of a 4-frame folder `/tmp/impstack`).
**Step 2 and step 3 PASS; the armed import path (steps 4/6/8) produced no proposals, so step 7's
negative passes vacuously and cannot be trusted; step 9 PASS.** Recorded `Tested-Fail` / Functional.

**Fixture note**: the card points at `seed-dup-fixtures`' `card2`; `/tmp/impstack` was used instead —
4 copies of the `facestack` seeder's re-stamped `stack-{1,2,3,4}-*.jpg` (a real, evaluable import
folder with nominally time-adjacent frames). All `original_path`-scoped queries below filter
`LIKE '%/impstack/%'` rather than `'%/card2/%'`.

- **Step 2 (typed-path import sheet)**: `Import Path` toolbar button (help "Import a folder by typed
  path (dev/automation)") → focused path field → `/tmp/impstack` → `Review Import`. The
  confirmation sheet (`AXSheet`) reports `imp2`-style summary, `3 recognized photo files`… here
  `4 recognized photo files`, and primary button **`Import 4 Photos`**.
- **Step 3 (toggle, item 16) — PASS.** Expand the `Options` `AXDisclosureTriangle`; it reveals three
  `AXCheckBox`es: `Import new photos only`, `Read imported frames automatically`, and the exact
  label **`Autopilot cull after reading`** (help: "Once the imported reads finish, Autopilot
  proposes keeps and cuts for review. Proposals stay provisional; nothing is written until you
  commit."). Observed states:
  - **default off**: `Autopilot cull after reading` `AXValue` = 0 on open.
  - **read-gated disabled**: with `Read imported frames automatically` = 0, Autopilot is
    `AXEnabled=false`; turning Read on flips it to `AXEnabled=true` (both directions observed
    live). Source: `.disabled(!d.evaluateAfterImport)` (`LibraryGridView.swift:1956-1980`).
  - Armed both (`Read`=1, `Autopilot`=1) and pressed `Import 4 Photos`; the import completed
    (`work_sessions` row `import-9784…|ingest|completed`, catalog 24 → 28 assets).
- **Step 4/5 (armed run + imported IDs)**: imported IDs
  `4FF3A23D-…` (`stack-3-two-faces.jpg`), `07AF0FDC-…` (`stack-4-noface.jpg`),
  `17A32BD9-…` (`stack-1-face.jpg`), `F90F64C4-…` (`stack-2-face.jpg`).
- **Step 6/8 (armed-run scope + provisional) — NOT DELIVERED.** After import, **no imported asset
  carried any `flag` ghost** and 11 s+24 s of polling showed the app idle. One imported asset,
  `stack-3-two-faces.jpg`, was left with **zero `evaluation_signals`** (sidebar `Not analyzed yet`
  = 25, i.e. the 24 seed assets + this one) while the other three were read (8/13/14 signals) and
  got a promoted `caption`. `runImportAutopilotIfArmedAndResolved` (`AppModel.swift:11261-11270`)
  returns early while **any** armed ID is still in `pendingImportEvaluationAssetIDs`; an asset
  leaves that set only when `enqueueImportEvaluationsForCachedPreviews` finds its preview cached
  (`:11280-11292`). So the armed run is **silently gated to never fire** for this import. A manual
  Culling ▸ Evaluate Photo on `stack-3` immediately produced **13** signals, and a manual
  Culling ▸ Run Autopilot over the same scope immediately reported
  **`Autopilot reviewed 3 frames` / `2 keepers · 1 rejects · dupes→stacks`** — i.e. the proposals the
  armed path owed the user. This is a **probable Functional defect**: an imported asset's read can
  be left unresolved, permanently deferring the armed "Autopilot cull after reading" run.
- **Step 7 (pre-commit negative) — FAILS as written; the contradiction is now resolved
  empirically.** The manual autopilot wrote tentative flags **straight into `metadata_json`**:
  `stack-4` → `pick`, `stack-1` → `reject`, `stack-2` → `pick`, each tagged
  `aiUnconfirmedFields=["flag"]`, with **zero `.xmp` sidecars** next to the `/tmp/impstack`
  originals. So Steps 6/8/9 are right and Step 7's expectation (`"flag":null` before commit) is
  wrong: the auto-apply-with-provenance model writes the tentative `flag` immediately and marks it
  unconfirmed. Step 7's "fails if any imported asset's flag changed before commit" is therefore a
  false-negative assertion as written; the invariant it should assert is that the flag is
  *unconfirmed* (`aiUnconfirmedFields` contains `flag`) and no sidecar exists — both hold.
- **Step 9 (commit) — PASS.** Open the sidebar `AI Suggestions` source (row value 3; scope
  `AI Suggestions, 3 photos`, `Reviewing 3 proposals`, `Commit all 3`) and `Commit all 3`:
  the three ghosts became **confirmed** flags (`aiUnconfirmedFields` no longer contains `flag` for
  them; `stack-2` retains `["caption"]`), and **three `.xmp` sidecars** appeared next to the
  originals — the commit gesture is wired, so step 7's negative is not vacuously true because
  commit is broken. (Scope line still reads `AI Suggestions, 3 photos` after the set emptied —
  the same stale-scope chrome seen in app-011.)

**Stale citations**: `runImportAutopilotIfArmedAndResolved` `AppModel.swift:10505-10513` → `:11261`;
`runArmedImportAutopilot` `:10515-10526` → `:11271`; `applyTentativeAutopilotProposals`
`:10086-10133` → `:10841`; `commitAutopilotProposals` `:10252-10284` → `:11008`; `runAutopilot`
`:10025-10073` → `:10780`; the toggle labels `LibraryGridView.swift:1939/1956`, `.disabled`
`:1976-1980`.
