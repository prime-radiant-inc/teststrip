# app-012-autopilot-evaluate-commands: Run Autopilot and the Evaluate commands gate and report correctly

**What this covers**: Jesse drives evaluation and autopilot from the Culling
menu; the commands must be honest about why they can't run. Inventory items
39-40, 42 (`CullingCommands`, `Sources/TeststripApp/main.swift:408-532`):
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

## Run status
**LIVE RUN 2026-09-14, Tart VM `teststrip-e2e`** (`script/vm_scenario_run.sh`): `smoke` run
dir `smoke-1789375602` (steps 2, 3-positive, 4, 5), `burst` run dir `burst-1789375720` (step 6),
`empty` run dir `empty-1789375779` (step 3-negative). All steps verified live.

- **Step 2 (menu inventory, item 42)** — one-pass System Events read of the `Culling` menu on a
  fresh `smoke` launch. Actual composition, in order:
  `Find Best Shots` (cmd=`B`, mods=1 → ⇧⌘B) · `Run Autopilot` (no key) · **divider** ·
  `Evaluate Photo` (no key) · `Evaluate Visible` (cmd=`E`, mods=1 → ⇧⌘E) · `Evaluate Matches`
  (no key) · `Move Rejects…` · **`Move Rejects to Trash…`** · `Auto-cull After Import` ·
  **divider** · then the culling-shortcut sections (`Previous/Next Frame in Stack (↑ / K, ↓ / J)`,
  `Previous/Next Stack (← / H, → / L)`, `Promote Frame & Reject Siblings (⏎)`, ratings 0-5, labels,
  flags, zoom/EXIF/faces/key-map, filters, `Keep A · Reject B`).
  **Double-fire guard holds**: the only two menu *key equivalents* are ⇧⌘B and ⇧⌘E; every
  culling-shortcut item carries its key **only in its title** (`AXMenuItemCmdChar` = missing,
  `mods=8` = no command), so no bare arrow/Return is menu-bound.
  *Card drift*: the card's list omits `Move Rejects to Trash…` (added with the Trash feature,
  `app-017`); everything the card names is present in the order it names them.
- **Step 3 (evaluate gating)** — the positive control is on `smoke`: the grid auto-selects
  `smoke-0` on launch and the seed ships cached previews, so `Evaluate Photo/Visible/Matches` read
  `enabled=true`. The negative control (the card's "no selection") is not reachable on `smoke`
  (clicking empty grid space does not clear the selection), so it was driven on `empty`
  (`empty-1789375779`, 0 assets): `Evaluate Photo`, `Evaluate Visible`, `Evaluate Matches`,
  `Find Best Shots`, and `Run Autopilot` all read `enabled=false` (no selection/no previews);
  `Auto-cull After Import` stays enabled (a preference toggle, not asset-gated). The
  "preview-not-yet-cached" window is unobserved (the seed ships previews) — noted per the card's
  own Sharp edges.
- **Step 4 (Run Autopilot on an unevaluated scope, item 39)** — on a fresh `smoke` launch
  (`evaluation_signals` = 0), Culling ▸ Run Autopilot set the status
  **"Autopilot: no evaluated photos in view to run on"** (footer `AXStaticText`); the ghost count
  stayed 0 and the pick-bearing rows stayed at their baseline 6. Re-confirmed identically on a
  fresh `burst` launch.
- **Step 5 (Evaluate Visible, item 40)** — ⇧⌘E on `smoke`: the toolbar `Activity` button went to
  `help="Activity - working"` and `evaluation_signals` grew 0 → 191 (63 mid-run, then 173 → 191,
  Activity back to idle). On `burst`: 0 → 143.
- **Step 6 (Run Autopilot on an evaluated scope)** — **driven on `burst`, not `smoke`: the card's
  Pre-state (`smoke`) structurally cannot produce flag ghosts.** On `smoke`, after ⇧⌘E completed
  (191 signals), Run Autopilot reported `Autopilot reviewed 0 frames` /
  `No clear cuts to propose — 33 keyword suggestions ready to review` — 0 keep/cut proposals
  because `smoke` has no stacks to rank (`AutopilotProposalPlanner` ranks within stacks; the same
  flat-library condition that makes `potentialPicks` 0), so `metadata_json.flag` ghosts never
  appear. On `burst` (18 assets, 4 burst stacks), after ⇧⌘E (143 signals), Run Autopilot reported
  **`Autopilot reviewed 14 frames` / `4 keepers · 10 rejects · dupes→stacks`**, and the ghosts are
  live and provisional exactly as the card specifies:
  - `aiUnconfirmedFields` is exactly `["flag"]` on every ghost; 7 assets carry a tentative flag
    (`smoke-2` → `pick`; `smoke-1/4/7/8/11/13` → `reject`) — the other proposals targeted assets
    that already carried a confirmed flag and were correctly skipped.
  - The grid cells render the badge via the cell's `AXValue`: `…, Autopilot proposes keep` /
    `…, Autopilot proposes cut` (the AX tree vends the composed phrase, not the literal `KEEP`/
    `CUT` glyph strings `AutopilotBadgePresentation.badge(for:)` returns).
  - **Zero `.xmp` sidecars exist** for any ghosted asset (`find … -name '*.xmp' | wc -l` = 0) —
    the tentative verdict has not touched the portable projection.

**Stale citations**: `CullingCommands` `main.swift:408-532` → `:438` (`sections` consumed at
`:493-508`); `menuKeyboardShortcut` `:575`; `LensChromePolicy.showsFooter`/`showsBrowseChrome`
`LibraryGridView.swift:8264-8286` → `:8801`/`:8818`.
