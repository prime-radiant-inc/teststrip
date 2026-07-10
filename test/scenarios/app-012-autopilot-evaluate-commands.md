# app-012-autopilot-evaluate-commands: Run Autopilot and the Evaluate commands gate and report correctly

**What this covers**: Jesse drives evaluation and autopilot from the Culling
menu; the commands must be honest about why they can't run. Inventory items
39-40, 42 (`CullingCommands`, `Sources/TeststripApp/main.swift:360-470`):
**Run Autopilot** (no key equivalent) needs evaluated photos in view, else it
sets the status "Autopilot: no evaluated photos in view to run on"
(`AppModel.runAutopilotOnCurrentScope`); **Evaluate Photo / Evaluate Visible
(⇧⌘E) / Evaluate Scope** are gated by worker liveness + cached previews
(`canRequestSelectedAssetEvaluation` etc.); and the Culling menu mirrors
`CullingCommandMenuPresentation.sections` with arrow/Return keys deliberately
NOT menu-bound (the double-fire guard, `menuKeyboardShortcut`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **Menu inventory (item 42).** Open the Culling menu via System Events.
   Assert it contains, in order: Find Best Shots (⇧⌘B), Run Autopilot (no
   key), divider, Evaluate Photo, Evaluate Visible (⇧⌘E), Evaluate Scope,
   Move Rejects…, the Auto-cull After Import toggle, divider, then the
   culling-shortcut sections. Assert no menu item shows a bare arrow/Return
   key equivalent (double-fire guard).
3. **Evaluate gating before previews.** Immediately after first launch
   (previews still generating), read the enabled state of Evaluate Photo
   with nothing selected: DISABLED (no selection). Select a thumbnail whose
   preview hasn't been generated yet if catchable: still disabled. Once
   previews exist, the same items enable.
4. **Run Autopilot on an unevaluated scope (item 39).** Before any
   evaluation (`sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"`
   returns 0), click Culling ▸ Run Autopilot. Assert the status area shows
   "Autopilot: no evaluated photos in view to run on" and:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"   # still 0
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE metadata_json LIKE '%pick%';"  # baseline-unchanged
   ```
5. **Evaluate Visible (item 40).** Press ⇧⌘E. Assert the Activity item goes
   to a working state and evaluation rows appear:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"    # grows
   ```
   Keep the app warm while polling.
6. **Run Autopilot on an evaluated scope.** After step 5 completes, click
   Run Autopilot again. Assert proposals appear as *provisional* state only:
   `autopilot_proposals` rows exist / KEEP-CUT badges render, but no asset's
   `metadata_json` verdict changed (confirm-before-write: nothing commits
   without the Review flow, which is cull-017's card).

## Expected
- Step 2: exact menu composition; zero arrow/Return equivalents. **Fails
  if** an item is missing/renamed or a bare arrow key is bound (double-step
  regression risk).
- Step 3: Evaluate items track worker+preview+selection state. **Fails if**
  an item is enabled with no worker or presses into a silent no-op.
- Step 4: the exact status string, zero proposals written. **Fails if**
  autopilot runs on nothing or writes anything.
- Step 5: ⇧⌘E produces evaluation signals. **Fails if** the shortcut is
  inert while the menu item works (shortcut plumbing bug).
- Step 6: proposals are provisional only. **Fails if** any `metadata_json`
  verdict changed without a confirming gesture — invariant violation,
  report immediately.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The gating booleans depend on the worker process being alive; if
  everything is disabled, check the worker first (Support ▸ Copy
  Diagnostics shows `Worker process: running/stopped`) before calling it a
  gating bug.
- Step 3's "preview not yet cached" window is racy on a fast machine —
  it's fine to observe only the no-selection→selection transition and note
  the preview-window race as unobserved.
- Status messages surface in the footer/status chrome, Library-only per
  `WorkspaceChromePolicy.showsFooter` — run step 4 from a workspace where
  the status is actually visible, or read `statusMessage` indirectly via a
  screenshot of the footer in Library.
