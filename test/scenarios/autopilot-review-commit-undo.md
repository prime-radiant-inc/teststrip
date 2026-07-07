# autopilot-review-commit-undo: Autopilot proposes, you review, commit, and undo

**What this covers**: the design-1b autopilot loop merged at migration 17 —
`runAutopilot` → provisional `autopilot_proposals` rows → the AutopilotBanner
Review/Undo-all controls → the review toolbar's Commit path
(`commitAutopilotProposals`, the ONLY metadata-write path) → `undoAutopilotRun`.
The load-bearing assertion is the confirm-before-write invariant: proposals
must leave zero keep/cut/rating writes in the catalog until an explicit
Commit, and Undo all must return the catalog to its pre-run state.

## Pre-state
- Fresh build, isolated catalog seeded with synthetic photos:
  ```bash
  ./script/build_and_run.sh --smoke
  ```
  `--smoke` seeds the synthetic app catalog into a throwaway
  application-support dir under `$TMPDIR` and opens the app against it. Capture
  that dir — every ground-truth query runs against `$ISOLATED/Teststrip/catalog.sqlite`:
  ```bash
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
- The grid shows the seeded photos. No autopilot banner is visible yet.

## Steps
1. **Record the pre-run baseline** (ground truth, before any UI action):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"          # committed/pending proposal rows
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE rating IS NOT NULL OR keep_state IS NOT NULL;"
   ```
   Note both numbers; call them `PROP0` and `WRITES0`.
2. **Run autopilot.** `script/activate_app.sh Teststrip`, then AX-press the
   toolbar toggle whose accessible label is **"Autopilot on"**.
3. **Wait for the proposal banner.** `waitFor` a `AXStaticText` whose value
   begins with **"Autopilot: "** (the AutopilotBanner `bannerText`).
4. **Assert nothing is written yet** (the invariant):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE rating IS NOT NULL OR keep_state IS NOT NULL;"
   ```
   This must still equal `WRITES0`.
5. **Open review.** AX-press the banner's **"Review"** button. `waitFor` an
   `AXStaticText` matching **"Reviewing N proposals"** (N ≥ 1).
6. **Commit all.** AX-press **"Commit all N"** (the review toolbar button).
   `waitFor` the "Reviewing" toolbar to disappear.
7. **Assert the commit wrote through**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE rating IS NOT NULL OR keep_state IS NOT NULL;"
   ```
   Call it `WRITES1`.
8. **Re-run and Undo all.** AX-press **"Autopilot on"** again, wait for the
   banner, then AX-press the banner's **"Undo all"** button; `waitFor` the
   banner to clear.
9. **Assert undo restored state**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE rating IS NOT NULL OR keep_state IS NOT NULL;"
   ```

## Expected
- Step 3: banner appears with `Autopilot: …` text within 20s. **Fails if** no
  banner appears (autopilot never produced a summary) or an error alert shows.
- Step 4: `WRITES0` unchanged. **Fails if** the count rose — that is a
  confirm-before-write violation; report it, do not soften it.
- Step 5: "Reviewing N proposals" with N ≥ 1. **Fails if** N = 0 or the review
  toolbar never appears.
- Step 7: `WRITES1 > WRITES0`. **Fails if** the count is unchanged — Commit
  did not reach `commitAutopilotProposals`.
- Step 9: count returns to `WRITES1`'s pre-second-run baseline (i.e. Undo all
  reverted the second run's writes). **Fails if** writes from the undone run
  persist. Quote `WRITES0`, `WRITES1`, and the final count side by side.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the app instance you launched. Leave any pre-existing Teststrip untouched.

## Sharp edges
- The **"Autopilot on"** control is a toggle: pressing it a second time in
  step 8 must re-trigger a run, not toggle autopilot off. Re-dump and confirm a
  fresh banner appeared before pressing Undo all; if the label reads
  "Autopilot off", you toggled the mode instead of running — press again.
- `keep_state`/`rating` column names above are the assumed catalog columns for
  autopilot's keep/cut/rating writes — verify against the live schema
  (`sqlite3 "$DB" .schema assets`) before trusting a zero count; a query
  against a wrong column silently reads 0 and would make the invariant check
  vacuous.
- Autopilot needs cached previews/evaluations to propose. `--smoke` seeds
  evaluable synthetic photos; if the banner reports 0 proposals, evaluation
  hasn't drained — wait on the Activity panel before running.
