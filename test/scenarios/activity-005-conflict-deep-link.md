# activity-005-conflict-deep-link: clicking a conflict row deep-links into the Grid lens; ⌘⇧0 only toggles the popover

**What this covers**: `AppModel.revealConflicts(_:)` (`AppModel.swift:3344-3365`),
invoked when a conflict row in the Activity popover is clicked
(`ActivityCenterView.selectConflict`, `ActivityCenterView.swift:262-268`) — the
exact sequence of state mutations it performs to land the user on the
conflicted asset. Also `⌘⇧0`, which is **not** wired to `revealConflicts` —
confirmed by source, it only toggles the Activity popover's presentation
(`ActivityCommands`, `main.swift:604-613`).

## Pre-state

This is VM-only. Run every launch, AX action, filesystem operation, and SQL
query through `script/vm_scenario_run.sh`:

```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended Teststrip
```

The `smoke` fixture's baked `original_path` can point at a prior session's host
`$TMPDIR` that `cmd_launch`'s prefix rewrite does not match, leaving the
originals unresolvable in the VM. Repair them VM-side before driving (this card
does not write sidecars, so it is a hygiene step, not a premise):

```bash
script/vm_scenario_run.sh shell '
run=$(ls -dt "$HOME"/teststrip-vm/run/smoke-* | head -1)
db="$run/Teststrip/catalog.sqlite"; dir="$run/Teststrip/SmokeOriginals"
sqlite3 "$db" "SELECT id || char(124) || original_path FROM assets;" | while IFS="|" read id p; do
  b=$(basename "$p"); new="$dir/$b"
  [ -f "$new" ] && sqlite3 "$db" "UPDATE assets SET original_path=\"$new\" WHERE id=\"$id\";"
done'
```

## Steps

1. `script/vm_scenario_run.sh ax wait-vended Teststrip`. Switch to the People
   lens first (`⌘6`) so step 3's lens-switch assertion is meaningful — if you
   start in the Grid lens, the "switches to Grid" claim is unfalsifiable.

   ```bash
   script/vm_scenario_run.sh key 'keystroke "6" using {command down}'
   script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – People"
   ```

2. Seed one conflict row for `smoke-3`. **Disclosed substitution**: the card
   originally asked for a genuinely detected sidecar divergence, but the
   metadata-sync-conflict rescan has no UI trigger on this build (it is owned by
   `activity-006-xmp-lifecycle.md`). Use the same presentation-only
   `metadata_sync_state` row technique as `activity-001`/`activity-004`, which
   exercises the full deep-link path without claiming to re-test detection. Note
   the conflicted asset id (`smoke-3`) as `$SRC`.

   ```bash
   script/vm_scenario_run.sh sql smoke "INSERT INTO metadata_sync_state (asset_id, sidecar_path, catalog_generation, last_synced_fingerprint, status, updated_at) SELECT 'smoke-3', '/Users/admin/teststrip-vm/fixtures/activity-005-smoke-3.jpg.xmp', catalog_generation, 'activity-005-presentation-only', 'conflict', CAST(strftime('%s','now') AS REAL) FROM assets WHERE id='smoke-3';"
   test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM metadata_sync_state WHERE asset_id='smoke-3' AND status='conflict';")" -eq 1
   ```

   Relaunch the same run so the model loads the out-of-band row; `launch smoke`
   would discard it.

   ```bash
   script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
   script/vm_scenario_run.sh shell '
   sleep 2
   run=$(ls -dt "$HOME"/teststrip-vm/run/smoke-* | head -1)
   open -n "$HOME/teststrip-vm/dist/Teststrip.app" --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$run"'
   script/vm_scenario_run.sh ax wait-vended Teststrip
   script/vm_scenario_run.sh key 'keystroke "6" using {command down}'
   script/vm_scenario_run.sh ax wait --role AXButton --help "Activity - 1 problem"
   ```

3. Open the Activity popover, click the conflict row. Per `revealConflicts`
   (`AppModel.swift:3344-3365`), assert the rendered consequences of every state
   mutation. **AX cannot read `selectedView`/`selectedSource`/
   `metadataSyncConflictFilter`/batch selection directly**, so each is asserted
   by a rendered proxy that only this mutation produces:

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - 1 problem"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh ax press --role AXButton --label "activity-005-smoke-3.jpg"
   ```

   - `selectedView == .grid` → the window title becomes `Teststrip – Grid`,
     regardless of the People lens it started in:
     `script/vm_scenario_run.sh ax wait --role AXWindow --contains "Teststrip – Grid"`.
   - `selectedSource.kind == .metadataSyncConflicts` and
     `metadataSyncConflictFilter == true` → the Scope chip reads
     `XMP Conflicts, 1 photo · XMP Conflicts` and the filter-removal control
     `AXButton` help `Remove filter XMP Conflicts` is present.
   - `clearLibraryQueryFilters()` → the `Search Catalog` field's value is empty.
   - batch selection contains exactly `$SRC` → the `smoke-3.jpg` cell's value
     contains `Selected, batch selected` (`setBatchSelection(assetID,
     isSelected: true)`; one id reads as an ordinary single selection, so do not
     assert a multi-select "batch mode" affordance).
   - `isInspectorVisible == true` and the Info section shows the conflict
     (`scrollInspector(to: .info)`, `AppModel.swift:5357`) → the inspector
     renders `Info` plus the `XMP conflict` detail and the sidecar path.

4. Cross-check the grid's rendered selection against the ground truth: the
   selected cell's AX label matches `$SRC`'s filename (`smoke-3.jpg`).

### ⌘⇧0 — popover toggle only, not a deep-link shortcut

5. With the Activity popover closed and the conflict still selected, press
   `⌘⇧0`. Confirmed by source (`main.swift:604-613`, `ActivityCommands`): the
   shortcut is bound to `model.isActivityCenterPresented.toggle()` only — it does
   **not** call `revealConflicts`, does not switch lens/source, and does not
   clear or set any Library filter state. Assert:

   ```bash
   script/vm_scenario_run.sh key 'keystroke "0" using {command down, shift down}'
   script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – Grid"
   script/vm_scenario_run.sh key 'keystroke "0" using {command down, shift down}'
   script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – Grid"
   script/vm_scenario_run.sh ax find --role AXButton --label "smoke-3.jpg" --contains "Selected"
   script/vm_scenario_run.sh ax find --role AXButton --help "Remove filter XMP Conflicts"
   ```

   The popover opens (or closes, if it was open) while the window title, the
   selected cell, and the conflict filter are all unchanged from their
   pre-shortcut values.

## Expected

- Step 3 fails if the lens does not switch to Grid, if the conflict filter is
  not the only active filter afterward (stale filters leaking through), if the
  selected cell is not `$SRC`, or if the inspector does not land on Info.
- Step 5 fails if `⌘⇧0` does anything beyond toggling popover visibility — in
  particular, if it invokes `revealConflicts` or mutates filter/selection state,
  the original task assumption ("likely jumps to Activity or clears deep-link
  state") would be correct instead of the current source reading; re-confirm
  against `main.swift` before trusting either.

## Cleanup

```bash
script/vm_scenario_run.sh sql smoke "DELETE FROM metadata_sync_state WHERE asset_id='smoke-3' AND sidecar_path='/Users/admin/teststrip-vm/fixtures/activity-005-smoke-3.jpg.xmp';"
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
```

The `smoke` run is a disposable fresh launch; only the owned conflict row is
removed.

## Sharp edges

- **No UI-reachable trigger exists for the metadata-sync-conflict rescan**
  (`docs/product/focused-workspaces-followups.md`, "Known test-fixture gaps") —
  hence the presentation-only seed in step 2. This is the same gap
  `quiet-activity-badge.md` and `activity-004-sources-conflicts-quiet.md` are
  PARTIAL for.
- The step-3 model predicates have no direct AX surface; each is asserted
  through a rendered proxy that only `revealConflicts` produces. Do not treat a
  bare "the button accepted a press" as evidence.
- `revealConflicts` takes `[AssetID]`, plural, but `selectConflict` in
  `ActivityCenterView` only ever calls it with a single-element array (one row =
  one asset) — there is currently no UI path that exercises the multi-id
  batch-selection branch with more than one id. If a future UI adds
  multi-select-conflict-rows, step 3's batch-selection assertion should be
  extended to cover N > 1.
- The function name is `revealConflicts`, confirmed exact
  (`AppModel.swift:3344`) — the task brief's "or equivalent" hedge wasn't needed.

## Run status

**Verified — 2026-09-14, Tart VM `teststrip-e2e` (`script/vm_scenario_run.sh`,
run dir `smoke-1789385083`, `launch smoke`, 24 assets).** Steps 1-5 all PASS as
driven.

- Step 1: `⌘6` landed the window on `Teststrip – People`.
- Step 2: one owned presentation-only `conflict` row for `smoke-3`
  (`metadata_sync_state`), same-run relaunch surfaced `Activity - 1 problem`.
- Step 3: pressing the conflict row (`AXButton` desc `activity-005-smoke-3.jpg`)
  landed the window on `Teststrip – Grid`; Scope chip
  `XMP Conflicts, 1 photo · XMP Conflicts`; `AXButton` help
  `Remove filter XMP Conflicts`; the `Search Catalog` field value was empty
  (filters cleared); the cell read `Selected, batch selected, Flagged Pick,
  Rating 3, Label Blue, 2 keywords`; the inspector rendered `Info` plus the
  `XMP conflict` detail and the sidecar path. PASS.
- Step 4: the selected cell's label is `smoke-3.jpg`, matching `$SRC`. PASS.
- Step 5: `⌘⇧0` opened the popover (`XMP Conflicts` text appeared) and a second
  `⌘⇧0` closed it; the window title stayed `Teststrip – Grid`, the `smoke-3.jpg`
  cell stayed `Selected`, and `Remove filter XMP Conflicts` stayed present —
  the shortcut toggles presentation only. PASS.

Corrections applied: the card's host-only pre-state (`build_and_run.sh
--smoke`, `ps eww`) was replaced with the Tart wrapper; step 2's undetectable
"real sidecar divergence" was replaced with the disclosed presentation-only
seed; step 3's model predicates were bound to rendered proxies; stale citations
fixed (`revealConflicts` `:3037-3058`→`:3344-3365`, `ActivityCommands`/⌘⇧0
`:572-584`→`:604-613`, `clearLibraryQueryFilters()` `:12227-12250`→`:13081`,
`scrollInspector(to:)` `:3056-3057`→`:5357`). No `sync` was run (VM pre-synced;
parent forbade it) — the already-synced `isolated/smoke` seed was launched.
