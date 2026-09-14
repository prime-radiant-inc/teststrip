# worker-002-evaluation-verdicts: Evaluation runs after preview caches, and re-scans don't double-enqueue

**What this covers**: once an asset's thumbnail preview is cached, the worker
runs an evaluation pass (`WorkerCommand.runEvaluation`) and the verdict
surfaces as the grid cell's KEEP/CUT badge — **there is no literal per-cell
"✦" glyph in this UI**; the keep/cut surface is the autopilot badge
(`AutopilotBadgePresentation`), driven by the asset's own ghost value
(`AutopilotGhost.kind(in: asset.metadata)`, a `PickFlag?` — `.pick`/
`.reject`), not a raw evaluation score glyph. The badge disappears the
moment the flag is confirmed (by any direct decision or an explicit
Commit) — it is not gated on being "committed" the way an earlier draft of
this card assumed; a *tentative* (AI-unconfirmed) flag is exactly what
renders the badge. This card also proves
import's auto-evaluation trigger is deduped: an asset that already has an
in-flight or completed evaluation does not get re-enqueued redundantly when a
second scan/import trigger fires for it.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended`, then confirm the smoke seed's baseline
   evaluation state (per `test/scenarios/README.md`, `--smoke` pre-seeds
   metadata but ground-truth it here rather than assume):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"
   sqlite3 "$DB" "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"
   ```
2. **Pick an asset with no evaluation yet.**
   ```bash
   ASSET_ID=$(sqlite3 "$DB" "SELECT id FROM assets WHERE id NOT IN
     (SELECT asset_id FROM evaluation_signals) LIMIT 1;")
   ```
   If every smoke asset already has signals, import a small fresh fixture
   folder (as in `worker-001-preview-lifecycle.md`) to get an unevaluated one.
3. **Trigger evaluation and watch dedup.** Import auto-triggers evaluation
   once the preview is cached (`scheduleImportAutoEvaluationIfEnabled`,
   `Sources/TeststripApp/AppModel.swift:10486-10500`); for an asset already in
   the grid, force it via the Evaluate action (`ax_drive.sh press --role
   AXButton --help "Evaluate"` on the loupe/inspector, or the equivalent grid
   command) — confirm the actual control's AXHelp against the running UI
   before matching.
4. **Fire a second scan/import trigger for the same asset immediately**
   (re-select and re-issue Evaluate, or re-run the import path if the asset
   came from Step 2's fixture folder) while the first evaluation is still
   in-flight (`work_sessions` row with `status IN ('queued','running')` for
   that asset). This exercises the dedup path directly: `requestEvaluation`
   (`Sources/TeststripApp/AppModel.swift:9942-9973`) builds a
   `WorkSessionID(rawValue: "evaluation-\(assetID)-\(provider)")` and returns
   immediately without enqueuing a second work item if that ID already has
   an active-status entry in `currentBackgroundWorkQueue`.
5. **Assert no duplicate work item.**
   ```bash
   sqlite3 "$DB" "SELECT id, status FROM work_sessions WHERE id = 'evaluation-$ASSET_ID-apple-vision' ORDER BY created_at;"
   ```
6. Wait for the evaluation to complete
   (`sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals WHERE asset_id = '$ASSET_ID';"`
   polling until > 0, staying frontmost via `wait-vended` each poll).
7. **Surface the verdict.** Run (or wait for) Autopilot over this asset's
   scope so a ghost is applied, then assert the grid cell's badge:
   `ax_drive.sh find --role AXStaticText --label "KEEP"` or `"CUT"` on the
   cell (`AutopilotBadgePresentation.badge(for:)`,
   `Sources/TeststripApp/LibraryGridView.swift:3518-3531` — `.pick` →
   `"KEEP"`, `.reject` → `"CUT"`, no ghost (confirmed flag, or a keyword,
   which was never part of the ghost type) → no badge). Cross-check against
   the catalog:
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag'), json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id = '$ASSET_ID';"
   ```

## Expected
- Step 5: exactly one `work_sessions` row for that ID — **fails if** a second
  row (a different `id`) or a second dispatch for the same asset+provider
  appears; that means the dedup guard in `requestEvaluation` was bypassed.
- Step 6: `evaluation_signals` gains a row for `$ASSET_ID`. **Fails if** it
  never appears — the worker never actually ran the evaluation command.
- Step 7: the grid cell's badge text matches the asset's own ghost flag
  value (`pick`→`"KEEP"`, `reject`→`"CUT"`). **Fails if** the render
  disagrees with `metadata_json`, or a confirmed flag (no ghost) wrongly
  renders a KEEP/CUT badge.
- Per the confirm-before-write invariant: the ghost's mere presence is what
  "pending" means now — `aiUnconfirmedFields` must still contain `flag` (no
  separate `status` field exists any more; `AutopilotProposalStatus` was
  deleted along with the `autopilot_proposals` table it gated) until an
  explicit Review/Commit gesture clears it. This card does not commit;
  assert the badge renders from the *tentative ghost*, not from a confirmed
  verdict on the asset itself.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- The inventory's "✦ glyph" framing does not match this codebase — grep
  confirms no such literal glyph string exists in `Sources/TeststripApp`.
  This card is written against the real KEEP/CUT badge; if a future UI adds
  a distinct per-cell verdict glyph separate from the autopilot badge, this
  card's Step 7 needs updating.
- `requestEvaluation`'s dedup key includes the provider name
  (`"evaluation-<assetID>-<provider>"`), so triggering two *different*
  providers for the same asset is not deduped against each other — that is
  by design, not a bug; don't conflate it with the same-provider double-fire
  this card targets.

## Run status
SQL and source citations were ground-truthed headlessly against a seeded
`--smoke` catalog on 2026-07-10 (schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`; dedup logic read
directly from `AppModel.swift`). The AX/live-driving steps (2-4, 7) need a
human-present or console-unlocked re-run — not executed in this session (no
host GUI available).

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: `autopilot_proposals`
no longer exists as a table (SP-D0 dropped it forward-only) — Step 7's
cross-check became a `metadata_json`/`aiUnconfirmedFields` query, and the
intro's stale "driven by a *committed* `AutopilotProposalKind`" framing
(which contradicted this card's own later "pending, not committed" Expected
bullet even before this branch) was corrected to "driven by the ghost's own
value, gone the moment the flag is confirmed." Supersedes prior status: the
2026-07-10 SQL-grounded citations quote the dropped table's schema — not
valid evidence for this revision. Needs a fresh VM run.

## Run status
**LIVE RUN 2026-09-14, Tart VM `teststrip-e2e`** (`script/vm_scenario_run.sh`): `smoke` run dir
`smoke-1789375828` (steps 1-6), `burst` run dir `burst-1789375720` (step 7). Steps 1/2/3/4/6 PASS,
**step 7 PASS (on `burst`)**, **step 5 BLOCKED — no observable ground truth** (recorded
`Tested-Fail` / Testability).

- **Step 1 (baseline)**: fresh `smoke` → `evaluation_signals` = `0 | 0` (`count(*)` /
  `count(DISTINCT asset_id)`), `work_sessions` = 0.
- **Step 2 (pick an unevaluated asset)**: `SELECT id FROM assets WHERE id NOT IN (SELECT asset_id
  FROM evaluation_signals) LIMIT 1` → `smoke-0` (no import needed).
- **Step 3 (trigger evaluation)**: the card's per-asset "Evaluate" AXButton does **not** exist —
  there is no `--help "Evaluate"` control in the Grid/Loupe/Inspector; the only Evaluate commands are
  the `Culling` menu items (`Evaluate Photo` = selection, `Evaluate Visible` ⇧⌘E, `Evaluate
  Matches`). Driven via **⇧⌘E** (Evaluate Visible), which evaluates `smoke-0`. Post-run,
  `smoke-0` carries 7 `evaluation_signals` and every one of the 24 assets has ≥1 signal.
- **Step 4 (second trigger while in-flight)**: `⇧⌘E` issued twice back-to-back, ~0.2 s apart, so the
  second dispatch lands while the first pass is still running (Activity `working` throughout).
- **Step 5 (assert no duplicate work item) — BLOCKED.** The card's SQL
  (`work_sessions WHERE id = 'evaluation-<id>-apple-vision'`) returns **zero rows** — not one, not
  two. Evaluation work items are **not persisted to `work_sessions` at all**: the dedup guard lives
  in `requestEvaluation`'s in-memory `currentBackgroundWorkQueue`
  (`AppModel.swift:10697-10722` — `itemID = "evaluation-\(assetID)-\(provider)"`, early-return when
  an active item with that id exists), and `work_sessions` only ever receives `import-…`/ingest rows
  (confirmed: the `empty`-import run has exactly one row, `import-<uuid> | ingest | completed`).
  So the card's step-5 observation method has no backing table and its Expected/`fails if` cannot be
  evaluated as written. Supporting (non-discriminating) evidence that the double trigger did not
  double-run: `evaluation_signals` has **0** duplicate `(asset_id, kind)` groups and totals 191
  (a single 24-asset pass). Suggested card fix: assert the dedup through the in-memory queue's
  observable proxy (or add the recognition items to `work_sessions`), not a `work_sessions` query.
- **Step 6 (evaluation completes)**: polled `SELECT count(*) FROM evaluation_signals WHERE
  asset_id='smoke-0'` → **7** (> 0), Activity back to idle.
- **Step 7 (surface the verdict) — PASS on `burst`, not `smoke`.** On `smoke` autopilot proposes no
  keep/cut (no stacks to rank), so no badge is producible (see app-012). On `burst`, after ⇧⌘E
  (143 signals) Run Autopilot produced `4 keepers · 10 rejects`; the ghosted cells render their
  badge in the cell's `AXValue` — `smoke-2`: `Not selected, Flagged Pick, Rating 2, Label Green,
  4 keywords, Autopilot proposes keep`, and the catalog cross-check agrees:
  `SELECT json_extract(metadata_json,'$.flag'), json_extract(metadata_json,'$.aiUnconfirmedFields')
  FROM assets WHERE id='smoke-2'` → `pick | ["flag"]`. The badge text is vended as the composed
  phrase `Autopilot proposes keep`/`cut`, not the literal `KEEP`/`CUT` strings
  (`AutopilotBadgePresentation.badge(for:)`, `LibraryGridView.swift:3866`), and the flag is still
  AI-unconfirmed — the card does not commit, so this is correct.

**Stale citations**: `requestEvaluation` `AppModel.swift:9942-9973` → `:10697-10722`;
`scheduleImportAutoEvaluationIfEnabled` `:10486-10500` → `:11242`;
`runImportAutopilotIfArmedAndResolved` `:10505-10513` → `:11261`;
`AutopilotBadgePresentation` `LibraryGridView.swift:3518-3531` → `:3866`.
