# quiet-activity-badge: the toolbar Activity icon is silent at idle and surfaces problems

**What this covers**: the Task 5/22 "quiet Activity" toolbar item — a bell
that shows no badge at idle, a spinner while background work runs, and a red
count badge only when something needs attention (XMP conflict, offline
source, provider failure). Clicking a problem row in the popover must land in
Library with that asset selected.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`, then wait for import/preview
   work to drain (poll `SELECT count(*) FROM background_work WHERE state NOT IN ('done','failed');`
   until 0, staying warm every poll).
2. **Idle assertion**: assert no badge element renders — the toolbar Activity
   button's AXHelp is exactly `"Activity"` (not `"Activity - working"` or
   `"Activity - N problem(s)"`); `ax_drive.sh find --role AXButton --help "Activity"`.
3. **Seed an XMP conflict out-of-band** (per the sync tests' technique): pick
   an asset with a rating already set (or set one via the inspector first so
   a sidecar exists), then edit that sidecar's `xmp:Rating` directly with a
   text edit (not through the app) to a different value while the app is
   running, so the next metadata-sync scan sees catalog != sidecar:
   ```bash
   SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
   # (rate 5 via inspector first if $SRC.xmp doesn't exist yet)
   sed -i '' 's/Rating="5"/Rating="3"/' "$SRC.xmp"
   ```
4. Trigger (or wait for) the next sync scan; assert the toolbar badge appears
   — `ax_drive.sh find --role AXButton --help "Activity - 1 problem"`.
5. Click the Activity button to open the popover; assert a conflict row is
   listed (`ax_drive.sh find --contains` the sidecar's basename).
6. Click the conflict row. Assert the app lands in the Library workspace with
   `$SRC` selected (its grid cell shows selection AX state, or the inspector
   binds to it).

## Expected
- Step 2: no badge, exact help text `"Activity"`.
- Step 4: badge shows count 1. **Fails if** the badge never appears — the
  sync scan isn't picking up the out-of-band edit, or the badge logic
  (`ActivityCenterPresentation.badge`) isn't wired to `xmpConflicts`.
- Step 6: **Fails if** the click doesn't switch workspace/select the asset —
  the popover row action isn't wired end to end.

## Cleanup
```bash
rm -f "$SRC.xmp"
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Source-confirmed the
wiring exists: `Sources/TeststripApp/LibraryGridView.swift:390-395`
(`activityToolbarHelp`), `Sources/TeststripApp/AppModel.swift:2481-2492`
(`xmpConflicts` built from `metadataSyncConflictItems`),
`Sources/TeststripApp/ActivityCenterView.swift:39-40` (conflicts section).
Needs a human-present re-run.
