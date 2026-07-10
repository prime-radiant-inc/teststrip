# app-011-find-best-shots: Find Best Shots routes to Potential Picks, Picks, or a plain-language status

**What this covers**: Jesse's one-button "show me the keepers". Inventory
item 38: `Culling ▸ Find Best Shots` (⇧⌘B) is read-only and routes via
`FindBestShotsRouter.plan` (`Sources/TeststripApp/AppModel.swift:641-684,
7708-7737`): (a) potential picks exist → Potential Picks queue; (b) none but
committed picks exist → Picks queue; (c) nothing ranks and nothing left to
evaluate → status message "These look too distinct to auto-rank — rate a few
to rank" — never a bare zero. When unevaluated frames remain it also triggers
a scope evaluation and lands on Potential Picks to fill in. Gated by
`canFindBestShots` (catalog non-nil, assets non-empty).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Keep the app warm during the evaluation wait (re-assert frontmost each poll).

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 (Library).
2. **Read-only baseline.** Snapshot the catalog's user-visible metadata:
   ```bash
   sqlite3 "$DB" ".dump assets" | shasum > /tmp/before.sha
   ```
3. **Outcome A/its evaluate-first variant.** Press ⇧⌘B on the fresh smoke
   seed (frames likely unevaluated). Expect a route to **Potential Picks**
   (breadcrumb/queue header) with an evaluation pass visibly running via the
   Activity item, the queue filling as the worker reports. Wait (warm!) for
   the evaluation to finish; record the final queue count and cross-check:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"   # grew from 0
   ```
4. **Outcome B (Picks).** Commit at least one pick (press P on a frame in
   Cull — a user gesture, allowed to write), then empty the potential-picks
   queue if needed (decide the proposals). Press ⇧⌘B again: with no
   potential picks but ≥1 pick, it must land on the **Picks** queue.
5. **Outcome C (nothing ranked).** Hard to force on a ranked seed; run this
   branch on an `--isolated` + import of 2-3 deliberately dissimilar photos
   (or a smoke state where all proposals were rejected and no picks exist).
   Press ⇧⌘B with the scope fully evaluated and nothing ranking: assert the
   status line "These look too distinct to auto-rank — rate a few to rank"
   appears and the view does NOT navigate to an empty queue.
6. **Read-only invariant.** Re-hash as in step 2 after step 3's route (before
   step 4's deliberate pick): apart from evaluation-signal/queue tables, no
   user metadata changed — `metadata_json` diffs are a failure. (Compare
   with `sqlite3 "$DB" "SELECT id, metadata_json FROM assets"` before/after
   rather than the whole-dump hash if evaluation rows pollute it.)

## Expected
- Step 3: routes to Potential Picks and triggers evaluation exactly when
  unevaluated frames + a live worker exist. **Fails if** it lands on an
  empty view with no activity, or shows a bare "0".
- Step 4: routes to Picks when only picks exist. **Fails if** it re-routes
  to an empty Potential Picks.
- Step 5: the exact plain-language string renders as a status, no
  navigation. **Fails if** any zero-count dead end appears.
- Step 6: no `metadata_json` changed by any ⇧⌘B press. **Fails if** the
  "reads only; writes nothing" contract broke.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Which of the three outcomes fires depends on live queue counts — assert
  the *mapping* (state → route), not a fixed sequence. Before each press,
  capture the app's own counts (review-queue badge numbers or the catalog's
  proposal/pick state) so the expected route is derivable, then check it.
- Outcome C needs a scope that genuinely evaluates to nothing ranked;
  document the fixture you used. If you cannot produce it, mark the branch
  NOT-RUN explicitly — do not substitute a weaker assertion.
- Evaluation needs the worker and cached previews (`canRequestCurrentScope…`);
  on a cold catalog wait for preview generation first or the evaluate-first
  branch silently degrades to outcome C.
