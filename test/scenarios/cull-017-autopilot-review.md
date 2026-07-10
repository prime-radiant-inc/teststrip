# cull-017-autopilot-review: Autopilot proposes, badges the grid, you review (selected/all), commit, dismiss, undo

**What this covers**: as a photographer who just imported a shoot with
Autopilot armed, I want machine-proposed keeps/cuts surfaced as provisional
grid badges I can scan, then either commit them (selected subset or all) or
dismiss/undo without ever having metadata written before I say so. Covers the
design-1b autopilot loop merged at migration 17 — `runAutopilot` →
provisional `autopilot_proposals` rows → the `AutopilotBannerView`
Review/Undo-all/Dismiss controls (item 52 —
`LibraryGridView.swift:3356-3441`, `AppModel.swift:7744`
`dismissAutopilotRunSummary`) → grid-cell KEEP/CUT badges from
`AutopilotBadgePresentation.badge(for:)` (item 53 —
`LibraryGridView.swift:3319-3329`, wired via `autopilotDecision:` on
`AssetGridCell` at `:3311`) → the review toolbar's Commit selected / Commit
all / Dismiss selected controls, `commitAutopilotProposals` being the ONLY
metadata-write path (item 54 — `LibraryGridView.swift:2360-2394`). The
load-bearing assertion is the confirm-before-write invariant: proposals must
leave zero keep/cut/rating writes in the catalog until an explicit Commit,
and Undo all must return the catalog to its pre-run state.

## Pre-state
- **Autopilot only runs after an import** — `runAutopilot` has no on-demand UI
  trigger (it is invoked once, over the imported set, when an import with
  Autopilot armed finishes evaluating). The "Autopilot on" checkbox is only the
  persisted *setting* that arms post-import runs; toggling it on a static
  catalog does nothing. So this card imports a folder to trigger a run.
- An import fixture folder of a few frames (want ≥4 so a partial "Commit
  selected" is distinguishable from "Commit all"):
  ```bash
  FIX=$(mktemp -d); swift run TeststripBench seed-dup-fixtures "$FIX" >/dev/null
  IMP="$FIX/card1"        # 4 distinct JPEGs
  ```
- Fresh build, isolated seeded catalog:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```

## Steps
1. **Arm autopilot and record the baseline.** `script/ax_drive.sh wait-vended`,
   then arm the setting: `script/ax_drive.sh press --role AXCheckBox --contains
   "Autopilot"`. Baseline (ground truth):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                       # PROP0 (expect 0)
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # GEN0 (write signal)
   ```
2. **Import the fixture** (drives the whole Import Path flow — path field →
   Review Import → Start Import; Autopilot-after-import is seeded from the armed
   setting):
   ```bash
   ./script/submit_import_path.sh Teststrip "$IMP"
   ```
3. **Wait for the imported set to evaluate and autopilot to run.** Poll until
   proposals appear:
   ```bash
   for i in $(seq 1 60); do p=$(sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"); [ "$p" -gt 0 ] && break; sleep 2; done
   ```
   Also expect the banner: `script/ax_drive.sh wait --role AXStaticText
   --contains "Autopilot"`.
4. **Assert proposals exist but nothing is written yet, and the grid badges
   are provisional-only (items 52-53).** In Library workspace, for each
   imported asset with a pick/reject proposal, assert the grid cell shows a
   KEEP or CUT badge matching `autopilot_proposals.kind`
   (`ax_drive.sh find --contains "KEEP"` / `"CUT"` scoped near that tile —
   scroll it into view first per the README's virtualized-grid gotcha):
   ```bash
   sqlite3 "$DB" "SELECT asset_id, kind FROM autopilot_proposals WHERE run_id = (SELECT run_id FROM autopilot_proposals ORDER BY created_at DESC LIMIT 1);"
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                        # > PROP0
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # still == GEN0
   ```
   Cross-check: no asset in the run has `metadata_json.flag`/`.rating` set
   from the proposal yet (the badge is a UI-only read of `autopilot_proposals`,
   not of committed metadata).
5. **Banner Dismiss (item 52), not the review path.** Before opening review,
   click the banner's "Dismiss" (`ax_drive.sh press --role AXButton --contains
   "Dismiss"` scoped to the banner, not the review toolbar which doesn't exist
   yet at this point). Assert the banner disappears
   (`ax_drive.sh find --contains "Autopilot"` in the banner region now fails)
   but `autopilot_proposals` rows and `SUM(catalog_generation)` are
   unchanged — dismissing the banner only hides the summary UI
   (`dismissAutopilotRunSummary`), it does not delete proposals or write
   anything:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                        # unchanged from step 4
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # still == GEN0
   ```
   The grid badges (item 53) must still render — they read `autopilot_proposals`
   directly via `autopilotProposalDecision(for:)`, not through the banner.
6. **Re-run is not available from a dismissed banner** — relaunch is overkill
   for a card; instead accept the banner is gone for the rest of this run and
   drive review directly via whatever affordance opens it (grep confirmed
   `beginAutopilotReview()` is only wired from the banner's Review button and
   from `cullCompletionStage`'s folded banner — if the plain banner is gone,
   the review path may only be reachable by not dismissing it. **Reorder the
   card in practice**: run steps 4-6 non-destructively (inspect only, don't
   dismiss), THEN branch: dismiss-and-verify-nothing-changes as one leaf,
   separately open Review as another leaf, on two independent runs of steps
   1-4 if the driving agent finds Dismiss is a dead end once clicked. Note
   this ordering risk explicitly when actually driving the card.
7. **Open review (undismissed banner).** `script/ax_drive.sh press --role
   AXButton --contains "Review"`; then `script/ax_drive.sh wait --role
   AXStaticText --contains "Reviewing"`. Batch-select a subset (not all) of
   the proposed assets in the grid (shift-click or ⌘-click per whatever the
   grid's multi-select gesture is).
8. **Commit selected (item 54, partial commit).**
   `script/ax_drive.sh press --role AXButton --contains "Commit"` matching the
   "Commit N" button (N = selection count, not the full proposal count —
   distinguish from "Commit all N" by exact label). Assert only the selected
   assets' metadata changed (their `catalog_generation` bumped and
   `metadata_json.flag`/keyword now reflects the proposal), while the
   unselected assets in the run are untouched:
   ```bash
   sqlite3 "$DB" "SELECT id, catalog_generation, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN (<all imported ids>);"
   ```
9. **Commit all remaining.** `script/ax_drive.sh press --role AXButton
   --contains "Commit all"`. Assert the remaining (previously unselected)
   assets are now also written:
   ```bash
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # GEN1 > GEN0
   ```
10. **Undo all.** `script/ax_drive.sh press --role AXButton --contains "Undo all"`.
11. **Assert undo reverted the committed writes**:
    ```bash
    sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # generations settle back
    ```

## Expected
- Step 3: `autopilot_proposals` becomes > 0 and the banner appears within ~120s.
  **Fails if** proposals stay 0 or an error alert shows.
- Step 4: proposals > `PROP0`, `SUM(catalog_generation)` still equals `GEN0`,
  and every proposed asset's grid cell shows the matching KEEP/CUT badge.
  **Fails if** the generation sum rose before Commit (report as a
  confirm-before-write violation, do not soften it), or a badge doesn't match
  `autopilot_proposals.kind`, or a `keyword`-kind proposal wrongly shows a
  KEEP/CUT badge (source says keyword proposals carry no badge).
- Step 5: banner Dismiss hides the banner but changes nothing in the
  catalog and the grid badges persist. **Fails if** Dismiss deletes proposal
  rows, writes any metadata, or also clears the grid badges.
- Step 7: "Reviewing N proposals" appears with N ≥ 1.
- Step 8: "Commit N" (N = current selection) writes only the selected
  assets — `catalog_generation` for unselected assets in the same run stays
  at its pre-commit value. **Fails if** the partial commit writes every
  proposal instead of just the selection (Commit selected and Commit all
  behave identically — the confirm-before-write scoping is broken).
- Step 9: `GEN1 > GEN0` after "Commit all N" writes the rest.
- Step 11: the generation sum settles back toward `GEN0` (Undo reverted the
  committed writes). Quote `GEN0`, the post-step-8 sum, `GEN1`, and the final
  sum side by side.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the app instance you launched. Leave any pre-existing Teststrip untouched.

## Sharp edges
- **There is no on-demand "run autopilot" gesture.** `runAutopilot` is called
  from exactly one place (AppModel, over the imported set post-import). Do not
  try to trigger a run by toggling "Autopilot on" on a static catalog — it will
  never produce proposals. Import is the trigger.
- Ground truth uses `SUM(catalog_generation)` as the write signal because the
  `--smoke` seed already populates ratings/flags on every asset, which makes a
  "rating IS NOT NULL" check vacuous. A generation bump means *some* metadata
  was written; that is what Commit must cause and the pre-commit run must not.
- Autopilot proposes only over frames that have evaluations. The imported set
  auto-evaluates because "Read imported frames" defaults on; if proposals stay
  0, confirm the import finished (`SELECT count(*) FROM assets` grew) and give
  evaluation time to drain before concluding failure.
- **Open question (step 6): whether Review is still reachable after the
  banner's Dismiss.** `beginAutopilotReview()` appears wired only from the
  standalone banner's Review button (`LibraryGridView.swift:2296-2301`) and
  the folded banner inside the completion stage
  (`LibraryGridView.swift:3582-3587`) — not from anywhere else. If Dismiss
  genuinely removes the only path to Review for that run, items 52 (Dismiss)
  and 54 (Review→Commit) may be mutually exclusive per run and this card's
  steps 5-11 need two separate import runs rather than one sequential run.
  Flagging for the runner rather than guessing; resolve empirically on first
  execution and fix the step ordering here if so.
- "Commit N" / "Dismiss selected" in the review toolbar are both disabled
  when the batch selection is empty (`.disabled(selectedIDs.isEmpty)`) —
  don't forget to select before asserting those buttons are pressable.

## Run status
UNRUN since the rename/extension in this revision — the original
proposals/Commit-all/Undo-all assertions (steps 1-4, 7-11 minus the
selected-vs-all split) were verified headlessly by source read on
2026-07-10. Steps 4's badge assertions, 5 (banner Dismiss), and 8's
partial "Commit selected" are newly added and have not been dry-run against
a live catalog or AX tree, including the open ordering question in Sharp
edges. Needs a human-present re-run.
