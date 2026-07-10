# activity-001-icon-states: toolbar Activity icon states (idle/working/problem) and popover-row-click navigation

**What this covers**: Task 5 debt called out in the Task 23 brief — the
toolbar Activity item is silent at idle, spins while background work runs,
and shows a red count badge only when something needs attention (XMP
conflict, offline source, provider failure). The icon's three states must be
visually and structurally distinct in the AX tree: idle (bell, no badge),
working (spinner, no badge), and problem (badge with a count). This card
also covers the popover row → navigate-to-asset path: clicking a conflict
row in the popover must land in Library with that asset selected. (Merged
from the former `activity-icon-states.md`, the narrow three-state sweep, and
`quiet-activity-badge.md`, which drove the conflict-badge → popover →
navigation path in detail — kept as one card since they're the same surface
at two grains.)

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps

### Three-state sweep
1. `script/ax_drive.sh wait-vended Teststrip`. Immediately after `--smoke`
   launch, import/preview work is likely still draining — assert **working**
   state first: `ax_drive.sh find --role AXButton --help "Activity - working"`.
2. Wait for the queues to drain — there is no `background_work` table; poll
   the real queues (stay warm every poll):
   ```bash
   sqlite3 "$DB" "SELECT (SELECT count(*) FROM preview_generation_queue)
                       + (SELECT count(*) FROM work_sessions WHERE status IN ('queued','running','paused'));"
   ```
   until it reads 0 (query verified against a seeded `--smoke` catalog
   2026-07-10). Then assert **idle** state:
   `ax_drive.sh find --role AXButton --help "Activity"` (exact match — not
   "- working" or "- N problem(s)").
3. Seed an offline source: pick an asset whose `original_path` is under a
   fake `/Volumes/<name>/...` mount point that doesn't exist, or simulate by
   unmounting a seeded volume if `--smoke` supports one; otherwise seed via
   `UPDATE assets SET original_path = '/Volumes/NoSuchVolume/x.jpg' WHERE id = '<id>';`
   (asset ids are TEXT, e.g. `'smoke-0'`; UPDATE syntax verified in a
   rolled-back transaction against a seeded catalog 2026-07-10)
   and trigger a source-availability rescan.
4. Assert **problem** state: `ax_drive.sh find --role AXButton --help "Activity - 1 problem"`
   (or "N problems" if more than one source/conflict already present).

### Popover row click navigates to the conflicted asset
5. **Idle assertion, restated for this sub-flow**: with the queue drained
   (step 2 already established this) and no problem yet seeded, the
   toolbar Activity button's AXHelp is exactly `"Activity"` — no badge
   element renders at all.
6. **Seed an XMP conflict out-of-band** (per the sync tests' technique):
   pick an asset with a rating already set (or set one via the inspector
   first so a sidecar exists), then edit that sidecar's `xmp:Rating`
   directly with a text edit (not through the app) to a different value
   while the app is running, so the next metadata-sync scan sees catalog !=
   sidecar:
   ```bash
   SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
   # (rate 5 via inspector first if $SRC.xmp doesn't exist yet)
   sed -i '' 's/Rating="5"/Rating="3"/' "$SRC.xmp"
   ```
7. Trigger (or wait for) the next sync scan; assert the toolbar badge
   appears — `ax_drive.sh find --role AXButton --help "Activity - 1 problem"`.
8. Click the Activity button to open the popover; assert a conflict row is
   listed (`ax_drive.sh find --contains` the sidecar's basename).
9. Click the conflict row. Assert the app lands in the Library workspace
   with `$SRC` selected (its grid cell shows selection AX state, or the
   inspector binds to it). See `activity-005-conflict-deep-link.md` for the
   full model-level breakdown of what this click does
   (`AppModel.revealConflicts`) — this card only asserts the observable
   render-level outcome.

## Expected
- Steps 1-4: each state's AXHelp text is exact and mutually exclusive —
  never two states' text simultaneously, never a badge with count 0.
  **Fails if** the working spinner persists after the queue drains (stuck
  state), or the problem badge doesn't clear once the offline source is
  restored.
- Step 5: no badge, exact help text `"Activity"`.
- Step 7: badge shows count 1. **Fails if** the badge never appears — the
  sync scan isn't picking up the out-of-band edit, or the badge logic
  (`ActivityCenterPresentation.badge`) isn't wired to `xmpConflicts`.
- Step 9: **Fails if** the click doesn't switch workspace/select the asset —
  the popover row action isn't wired end to end.

## Cleanup
```bash
rm -f "$SRC.xmp"
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **No UI-reachable trigger exists for the metadata-sync-conflict or
  source-availability rescans** — both fire only off worker-queue events.
  Quoted precisely from `docs/product/focused-workspaces-followups.md`
  ("Known test-fixture gaps"): *"No UI-reachable trigger exists for the
  metadata-sync-conflict or source-availability rescans — both fire only
  off worker-queue events. This makes the Activity item's badge states
  impossible to scenario-test (`quiet-activity-badge` and
  `activity-icon-states` are PARTIAL for this reason) and may also be a
  real product gap: a user who fixes a sidecar or remounts a drive has no
  way to ask for a re-check."* Steps 3, 6-7 above inherit this gap; a
  relaunch against the mutated catalog is the most likely workaround but
  wasn't independently reverified in this merge pass.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. State text confirmed
at `Sources/TeststripApp/LibraryGridView.swift:369-395`
(`activityToolbarIcon`/`activityToolbarHelp`: `isWorking` → spinner + "Activity
- working"; `.problems(count)` → badge + "Activity - N problem(s)"; else
"Activity"). Conflict-badge/popover wiring confirmed at
`Sources/TeststripApp/LibraryGridView.swift:390-395` (`activityToolbarHelp`),
`Sources/TeststripApp/AppModel.swift:2481-2492` (`xmpConflicts` built from
`metadataSyncConflictItems`), `Sources/TeststripApp/ActivityCenterView.swift:39-40`
(conflicts section). Needs a human-present re-run. All SQL in this card was
run headlessly against a seeded --smoke catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift). This file merges the
former `activity-icon-states.md` and `quiet-activity-badge.md`; both were
independently BLOCKED-CONSOLE before the merge and the merge does not change
that status.
