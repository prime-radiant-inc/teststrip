# autopilot-review-commit-undo: Autopilot proposes, you review, commit, and undo

**What this covers**: the design-1b autopilot loop merged at migration 17 —
`runAutopilot` → provisional `autopilot_proposals` rows → the AutopilotBanner
Review/Undo-all controls → the review toolbar's Commit path
(`commitAutopilotProposals`, the ONLY metadata-write path) → `undoAutopilotRun`.
The load-bearing assertion is the confirm-before-write invariant: proposals
must leave zero keep/cut/rating writes in the catalog until an explicit
Commit, and Undo all must return the catalog to its pre-run state.

## Pre-state
- **Autopilot only runs after an import** — `runAutopilot` has no on-demand UI
  trigger (it is invoked once, over the imported set, when an import with
  Autopilot armed finishes evaluating). The "Autopilot on" checkbox is only the
  persisted *setting* that arms post-import runs; toggling it on a static
  catalog does nothing. So this card imports a folder to trigger a run.
- An import fixture folder of a few frames:
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
   proposals appear (autopilot runs once the imported frames' evaluations
   resolve):
   ```bash
   for i in $(seq 1 60); do p=$(sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"); [ "$p" -gt 0 ] && break; sleep 2; done
   ```
   Also expect the AutopilotBanner: `script/ax_drive.sh wait --role AXStaticText
   --contains "Autopilot"`.
4. **Assert proposals exist but nothing is written yet** (the invariant):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                        # > PROP0
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # still == GEN0
   ```
5. **Open review.** `script/ax_drive.sh press --contains "Review"`; then
   `script/ax_drive.sh wait --role AXStaticText --contains "Reviewing"`.
6. **Commit all.** `script/ax_drive.sh press --role AXButton --contains "Commit all"`.
7. **Assert the commit wrote through**:
   ```bash
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # GEN1 > GEN0
   ```
8. **Undo all.** `script/ax_drive.sh press --role AXButton --contains "Undo all"`.
9. **Assert undo reverted the committed writes**:
   ```bash
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # generations settle back
   ```

## Expected
- Step 3: `autopilot_proposals` becomes > 0 and the banner appears within ~120s.
  **Fails if** proposals stay 0 (autopilot never ran — check the import
  finished and evaluations drained) or an error alert shows.
- Step 4: proposals > `PROP0`, but `SUM(catalog_generation)` still equals `GEN0`.
  **Fails if** the generation sum rose before Commit — a confirm-before-write
  violation; report it, do not soften it.
- Step 5: "Reviewing N proposals" appears with N ≥ 1.
- Step 7: `GEN1 > GEN0` — Commit reached `commitAutopilotProposals`.
- Step 9: the generation sum settles back toward `GEN0` (Undo reverted the
  committed writes). Quote `GEN0`, `GEN1`, and the final sum side by side.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the app instance you launched. Leave any pre-existing Teststrip untouched.

## Sharp edges
- **There is no on-demand "run autopilot" gesture.** `runAutopilot` is called
  from exactly one place (AppModel, over the imported set post-import). Do not
  try to trigger a run by toggling "Autopilot on" on a static catalog — it will
  never produce proposals. Import is the trigger. (The source comment claiming
  on-demand availability is stale; the affordance does not exist in the UI.)
- Ground truth uses `SUM(catalog_generation)` as the write signal because the
  `--smoke` seed already populates ratings/flags on every asset, which makes a
  "rating IS NOT NULL" check vacuous. A generation bump means *some* metadata
  was written; that is what Commit must cause and the pre-commit run must not.
- Autopilot proposes only over frames that have evaluations. The imported set
  auto-evaluates because "Read imported frames" defaults on; if proposals stay
  0, confirm the import finished (`SELECT count(*) FROM assets` grew) and give
  evaluation time to drain before concluding failure.
