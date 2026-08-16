# activity-001-icon-states: toolbar Activity icon states (idle/working/problem) and conflict-row navigation

**What this covers**: the toolbar Activity item is quiet at idle, shows its
working treatment while a published work snapshot is active, and shows a
counted problem badge only for attention-worthy state. It also proves that a
conflict row deep-links to the conflicted asset in the Grid lens.

The toolbar reads `ActivityCenterPresentation`, not the worker supervisor's
live queue. Background queue changes are published on the app's coalesced
cadence, so each exact toolbar control below is a positive publication barrier.
Catalog state may lead the view; never replace those barriers with a fixed
delay.

Source: `Sources/TeststripApp/LibraryGridView.swift` (`activityToolbarIcon`
and `activityToolbarHelp`),
`Sources/TeststripApp/ActivityCenterPresentation.swift` (working/problem
projection), `Sources/TeststripApp/ActivityCenterView.swift` (conflict-row
action), and `Sources/TeststripApp/AppModel.swift`
(`activityCenterPresentation`, `revealConflicts(_:)`, and coalesced background
work publication).

## Pre-state

Run every launch, UI action, filesystem operation, and catalog query through
the Tart wrapper. Import the 130 public `smokebig` originals into a fresh
`empty` catalog; do not launch the already-populated `smokebig` catalog.

```bash
script/vm_scenario_run.sh sync empty smokebig
script/vm_scenario_run.sh launch empty
script/vm_scenario_run.sh ax wait-vended Teststrip
test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets;")" -eq 0

script/vm_scenario_run.sh shell '
set -eu
fixture="$HOME/teststrip-vm/fixtures/activity-001-smokebig"
rm -rf "$fixture"
mkdir -p "$fixture"
set -- "$HOME"/teststrip-vm/isolated/smokebig/Teststrip/SmokeOriginals/*.jpg
test "$#" -eq 130
for source in "$@"; do
    cp "$source" "$fixture/$(basename "$source")"
done
test "$(find "$fixture" -type f -name "*.jpg" | wc -l | tr -d " ")" -eq 130
test "$(find "$fixture" -type f -name "*.xmp" | wc -l | tr -d " ")" -eq 0
'
```

The copied folder is card-owned, fits in the VM, contains real decodable JPEGs,
and makes import/preview/evaluation work originate from an empty catalog. It
replaces both the old pre-rendered-smoke launch window and the old host-only
fixture paths.

## Steps

### 1. Idle is exact and unbadged

1. Before importing, prove the exact idle toolbar help and open that control:

   ```bash
   script/vm_scenario_run.sh ax find --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "No active work"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Activity"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh key 'key code 53'
   ```

   Exact AXHelp matching makes this mutually exclusive with `Activity -
   working` and `Activity - N problem(s)`. No count-zero badge is permitted.

### 2. A real import reaches the published working state, then returns idle

2. Submit the copied originals through the real typed-path import route and
   wait for the positive working control. This is condition-driven; do not race
   the app immediately after launch or invoke host `ax_drive.sh` directly.

   ```bash
   script/vm_scenario_run.sh shell '$HOME/teststrip-vm/script/submit_import_path.sh Teststrip $HOME/teststrip-vm/fixtures/activity-001-smokebig'
   script/vm_scenario_run.sh ax wait --role AXButton --help "Activity - working"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - working"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Activity"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Import photos" \
     || script/vm_scenario_run.sh ax find --role AXStaticText --label "Generate previews" \
     || script/vm_scenario_run.sh ax find --role AXStaticText --label "Evaluate photos"
   script/vm_scenario_run.sh key 'key code 53'
   ```

   The row assertion accepts whichever real phase owns the published snapshot;
   it does not infer working state from a catalog counter.

3. Wait for the exact idle control to replace the working control, then open
   it and assert the worker's post-publication idle row:

   ```bash
   attempt=0
   while [ "$attempt" -lt 12 ]; do
       script/vm_scenario_run.sh ax find --role AXButton --help "Activity" && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$attempt" -lt 12
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets;")" -eq 130
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax wait --role AXStaticText --label "Worker idle"
   script/vm_scenario_run.sh ax find --role AXButton --help "Stop idle worker"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Activity"
   script/vm_scenario_run.sh key 'key code 53'
   ```

   `Activity` and `Worker idle` are the positive barriers before the negative
   active-row assertion. A SQL count or a fixed sleep alone is not evidence that
   the coalesced view has published its terminal snapshot.

### 3. One problem badges once and its row deep-links to Grid

4. Bind one imported asset and insert one card-owned presentation conflict.
   Real sidecar divergence/detection belongs to
   `activity-006-xmp-lifecycle.md`; this leg isolates badge arithmetic and the
   row action without claiming to re-test the detector.

   ```bash
   TARGET_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM assets WHERE original_path LIKE '%/smoke-0.jpg' LIMIT 1;")
   test -n "$TARGET_ID"
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM metadata_sync_state WHERE asset_id='$TARGET_ID';")" -eq 0
   script/vm_scenario_run.sh sql empty "INSERT INTO metadata_sync_state (asset_id, sidecar_path, catalog_generation, last_synced_fingerprint, status, updated_at) SELECT id, '/Users/admin/teststrip-vm/fixtures/activity-001-conflict-target.xmp', catalog_generation, 'activity-001-presentation-only', 'conflict', CAST(strftime('%s','now') AS REAL) FROM assets WHERE id='$TARGET_ID';"
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM metadata_sync_state WHERE asset_id='$TARGET_ID' AND status='conflict';")" -eq 1
   ```

5. Relaunch the same `empty` run so the out-of-band presentation row is loaded.
   Calling `launch empty` here would discard the mutation.

   ```bash
   script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
   script/vm_scenario_run.sh shell '
   set -eu
   attempt=0
   while pgrep -x Teststrip >/dev/null 2>&1 && [ "$attempt" -lt 20 ]; do
       attempt=$((attempt + 1))
       sleep 1
   done
   ! pgrep -x Teststrip >/dev/null 2>&1
   run=$(ls -dt "$HOME"/teststrip-vm/run/empty-* | head -1)
   test -n "$run"
   open -n "$HOME/teststrip-vm/dist/Teststrip.app" --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$run"
   '
   script/vm_scenario_run.sh ax wait-vended Teststrip
   script/vm_scenario_run.sh ax wait --role AXButton --help "Activity - 1 problem"
   ```

6. Switch to People first so the deep-link's lens transition is falsifiable,
   then open the positive one-problem control and press the uniquely named
   conflict row:

   ```bash
   script/vm_scenario_run.sh key 'keystroke "6" using {command down}'
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - 1 problem"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh ax press --role AXButton --label "activity-001-conflict-target"
   script/vm_scenario_run.sh ax wait --role AXWindow --contains "Teststrip – Grid"
   script/vm_scenario_run.sh ax find --role AXButton --help "Remove XMP Conflicts filter"
   script/vm_scenario_run.sh ax find --role AXButton --label "smoke-0.jpg" --contains "Selected"
   ```

   The unique presentation label avoids colliding with the grid cell's
   `smoke-0.jpg` label. The resulting Grid window, active conflict-filter
   control, and selected cell jointly prove the row action, rather than merely
   proving that a button accepted a press.

## Expected

- Idle fails unless the exact `Activity` control is present with `No active
  work` and no active/problem section.
- Working fails unless the 130-original import produces `Activity - working`
  and at least one real published kind row. A launch-window glimpse is not a
  pass.
- Return-to-idle fails unless the exact idle control replaces working, all 130
  assets exist, and `Worker idle` plus Stop render after publication.
- Problem fails unless exactly one owned conflict yields exactly
  `Activity - 1 problem`.
- Navigation fails unless the row lands in Grid with only the XMP Conflicts
  scope active and `smoke-0.jpg` selected.

## Cleanup

The catalog is a disposable fresh `empty` run. Remove only the fixture and
presentation row this card owns:

```bash
script/vm_scenario_run.sh sql empty "DELETE FROM metadata_sync_state WHERE sidecar_path='/Users/admin/teststrip-vm/fixtures/activity-001-conflict-target.xmp';"
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
script/vm_scenario_run.sh shell 'rm -rf "$HOME/teststrip-vm/fixtures/activity-001-smokebig"'
```

## Sharp edges

- The `smokebig` seed catalog itself is pre-rendered. This card copies only its
  originals and imports them into `empty`; launching `smokebig` would make the
  working assertion a timing accident.
- The toolbar is a coalesced publication surface. Use its positive exact
  controls as barriers before negative assertions; SQL may update first.
- The inserted `metadata_sync_state` row is presentation-only. It does not
  claim that a missing `.xmp` is a naturally detected conflict.
- Receipts may coexist with `No active work`, and an idle worker may coexist
  with the idle toolbar. Neither is active work or a problem.

## Run status

**Spec'd — NOT RUN (2026-08-10).** The current procedure has not been run in
the Tart VM. This repair replaces direct host commands, the pre-rendered-smoke
launch race, fixed-delay publication assumptions, and the obsolete claim that
no UI rescan exists. It makes every external operation VM-contained and uses
positive published controls as state barriers.

Historical evidence is preserved but is not current execution evidence:

- 2026-07-10: the smoke schema/queue SQL was checked headlessly; no Activity UI
  leg ran.
- The former card was marked `BLOCKED-CONSOLE`; its source reading established
  the three toolbar strings but did not drive them.
- Later sidecar-rescan and conflict-deep-link work removed the original fixture
  gap, but no fresh run of this rewritten 130-original procedure occurred.
