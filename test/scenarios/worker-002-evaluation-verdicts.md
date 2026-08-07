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
   `Sources/TeststripApp/AppModel.swift:10112-10125`); for an asset already in
   the grid, force it via the Evaluate action (`ax_drive.sh press --role
   AXButton --help "Evaluate"` on the loupe/inspector, or the equivalent grid
   command) — confirm the actual control's AXHelp against the running UI
   before matching.
4. **Fire a second scan/import trigger for the same asset immediately**
   (re-select and re-issue Evaluate, or re-run the import path if the asset
   came from Step 2's fixture folder) while the first evaluation is still
   in-flight (`work_sessions` row with `status IN ('queued','running')` for
   that asset). This exercises the dedup path directly: `requestEvaluation`
   (`Sources/TeststripApp/AppModel.swift:9568-9599`) builds a
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
   `Sources/TeststripApp/LibraryGridView.swift:3605-3618` — `.pick` →
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
