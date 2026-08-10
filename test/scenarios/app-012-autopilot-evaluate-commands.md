# app-012-autopilot-evaluate-commands: Run Autopilot and the Evaluate commands gate and report correctly

**What this covers**: Jesse drives evaluation and autopilot from the Culling
menu; the commands must be honest about why they can't run. Inventory items
39-40, 42 (`CullingCommands`, `Sources/TeststripApp/main.swift:406-530`):
**Run Autopilot** (no key equivalent) needs evaluated photos in view, else it
sets the status "Autopilot: no evaluated photos in view to run on"
(`AppModel.runAutopilotOnCurrentScope`); **Evaluate Photo / Evaluate Visible
(⇧⌘E) / Evaluate Matches** are gated by worker liveness + cached previews
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
   key), divider, Evaluate Photo, Evaluate Visible (⇧⌘E), Evaluate Matches,
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
   "Autopilot: no evaluated photos in view to run on" and (`autopilot_proposals`
   no longer exists as a table — SP-D0 dropped it forward-only — so the
   ghost count is the ground truth instead):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # still at its baseline (0 on a fresh --smoke seed)
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE metadata_json LIKE '%pick%';"  # baseline-unchanged
   ```
5. **Evaluate Visible (item 40).** Press ⇧⌘E. Assert the Activity item goes
   to a working state and evaluation rows appear:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"    # grows
   ```
   Keep the app warm while polling.
6. **Run Autopilot on an evaluated scope.** After step 5 completes, click
   Run Autopilot again. Assert ghosts appear as *provisional* state:
   KEEP/CUT badges render, and (per the auto-apply-with-provenance model —
   `applyTentativeAutopilotProposals`) the run has already written each
   proposed asset's tentative pick/reject straight into `metadata_json.flag`,
   tagged `origin=ai` (`aiUnconfirmedFields` contains `flag`) — this AI-origin,
   unconfirmed flag **is** the ghost (`AutopilotGhost.kind(in:)`); not yet a
   *confirmed* verdict, and not yet synced to any `.xmp` sidecar. Only the
   Review → Commit flow (cull-017's card) confirms it (flips to `origin=user`,
   writes the sidecar):
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets
     WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
   ```

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
- Step 6: proposals are provisional — each proposed asset's tentative
  `flag` lands in `metadata_json` immediately, but tagged `aiUnconfirmedFields`
  contains `flag` and with no `.xmp` sidecar yet. **Fails if** a proposed
  asset's `flag` is set without `aiUnconfirmedFields` containing `flag` (a
  tentative verdict silently landed as confirmed), or if a sidecar exists for
  it before Commit — either is an invariant violation, report immediately.

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
- Status messages surface in the footer/status chrome, shown only in the
  "browse" lenses — Grid, Loupe, Timeline, Map, not Cull or People — per
  `LensChromePolicy.showsFooter`/`showsBrowseChrome`
  (`LibraryGridView.swift:8264-8286`). A fresh launch already lands in the
  Grid lens (`AppModel.load`, `selectedView: .grid`), so step 4 is fine as
  written; if a prior step switched to Cull or People, switch back to a
  browse lens before reading the status, or read `statusMessage` indirectly
  via a screenshot of the footer.

## Run status
**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: `autopilot_proposals`
no longer exists as a table (SP-D0 dropped it forward-only) — Step 4's and
Step 6's queries became ghost queries against
`metadata_json`/`aiUnconfirmedFields`, and Step 6's `JOIN` against the
dropped table became a plain `WHERE EXISTS (...)` clause. Supersedes prior
status: LEDGER records this card `Tested-Pass`/PASS, but that result was
obtained against a build where `autopilot_proposals` still existed and Step
6's query still worked — not valid evidence for this revision. Needs a
fresh VM run.

**Reconciled 2026-08-09 (Task 13, unified-shell sweep)**: the Sharp edges
note cited `WorkspaceChromePolicy.showsFooter`, gating the footer to the
deleted "Library" workspace — renamed to `LensChromePolicy.showsFooter`
(`LibraryGridView.swift:8284-8286`), which delegates to
`showsBrowseChrome(_:)` (`:8264-8271`): footer chrome now shows across four
lenses (Grid/Loupe/Timeline/Map), not one workspace, and is absent in Cull
and People. Corrected the guidance accordingly (a fresh launch's default
Grid lens already satisfies it). No step or assertion in this card
referenced a workspace directly, so only this one citation changed.
Supersedes prior status: the 2026-08-06 ghost-derivation reconciliation
above is unaffected by this correction — it never depended on footer
visibility — but still needs a fresh VM run per its own text.
