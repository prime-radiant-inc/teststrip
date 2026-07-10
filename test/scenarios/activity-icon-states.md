# activity-icon-states: idle / working / problem-badge states of the toolbar Activity icon

**What this covers**: Task 5 debt called out in the Task 23 brief — the
Activity icon's three states must be visually and structurally distinct in
the AX tree: idle (bell, no badge), working (spinner, no badge), and problem
(badge with a count). Complements `quiet-activity-badge.md`, which drives the
conflict-badge → popover → navigation path in detail; this card is the
narrower three-state sweep.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`. Immediately after `--smoke`
   launch, import/preview work is likely still draining — assert **working**
   state first: `ax_drive.sh find --role AXButton --help "Activity - working"`.
2. Wait for `SELECT count(*) FROM background_work WHERE state NOT IN ('done','failed');`
   to reach 0 (stay warm every poll). Assert **idle** state:
   `ax_drive.sh find --role AXButton --help "Activity"` (exact match — not
   "- working" or "- N problem(s)").
3. Seed an offline source: pick an asset whose `original_path` is under a
   fake `/Volumes/<name>/...` mount point that doesn't exist, or simulate by
   unmounting a seeded volume if `--smoke` supports one; otherwise seed via
   `UPDATE assets SET original_path = '/Volumes/NoSuchVolume/x.jpg' WHERE id = <id>;`
   and trigger a source-availability rescan.
4. Assert **problem** state: `ax_drive.sh find --role AXButton --help "Activity - 1 problem"`
   (or "N problems" if more than one source/conflict already present).

## Expected
- Each state's AXHelp text is exact and mutually exclusive — never two
  states' text simultaneously, never a badge with count 0.
- **Fails if** the working spinner persists after the queue drains (stuck
  state), or the problem badge doesn't clear once the offline source is
  restored.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. State text confirmed
at `Sources/TeststripApp/LibraryGridView.swift:369-395`
(`activityToolbarIcon`/`activityToolbarHelp`: `isWorking` → spinner + "Activity
- working"; `.problems(count)` → badge + "Activity - N problem(s)"; else
"Activity"). Needs a human-present re-run.
