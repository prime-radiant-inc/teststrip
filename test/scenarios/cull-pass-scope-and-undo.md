# cull-pass-scope-and-undo: P/X/S/Return in the Cull workspace, and ⌘Z reverts the whole pass

**What this covers**: the Cull workspace's keyboard loop — pick (`P`) and
reject (`X`) a few frames, cycle scope with `S` to Picks and confirm the
sidebar/HUD reflect it, then Return on a stack writes pick+sibling-rejects as
one gesture, and ⌘Z reverts everything from the pass in one step.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Assert nothing decided yet: `sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NOT NULL;"` reads 0.
3. Press `P` (pick current frame), advance (Space), press `X` (reject next
   frame). Assert `SELECT flag FROM ...` (via metadata_json) shows one pick
   and one reject.
4. Press `S` to cycle scope to Picks. Assert the HUD/sidebar scope indicator
   reads "Picks" (`ax_drive.sh find --contains "Picks"` in the scope area)
   and the visible set narrows to picked frames only.
5. Advance to a frame that belongs to a persisted/loaded stack (seeded
   burst); press Return. Assert **one gesture** wrote: the frame picked AND
   its stack siblings rejected — query `person`-free assertion:
   ```bash
   sqlite3 "$DB" "SELECT asset_id, json_extract(metadata_json,'\$.flag') FROM assets WHERE stack_id = (SELECT stack_id FROM assets WHERE id=<frame>);"
   ```
   confirms exactly one `pick` and the rest `reject` within that stack.
6. Press ⌘Z. Assert every flag set in steps 3 and 5 is cleared in one undo
   (`SELECT count(*) ... flag IS NOT NULL` returns 0 again) — a single ⌘Z
   reverts the whole pass, not just the last stack decision.

## Expected
- Step 3: exactly the picked/rejected frames show the matching flag.
- Step 4: scope indicator and visible set both read Picks-only.
- Step 5: stack Return is one atomic gesture — pick the Return target,
  reject every sibling, in the same transaction. **Fails if** siblings need a
  separate action, or if some siblings are left undecided.
- Step 6: ⌘Z clears all flags from the pass in one keystroke. **Fails if** it
  only reverts the most recent stack decision, requiring repeated ⌘Z.
- Preload-ahead check (spec §3): confirm Space/advance never blocks waiting
  on a preview — if it does, STOP and flag to Jesse per CLAUDE.md's
  perf-restraint rule rather than investigating further.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. `CullScope.cycleScope`
keyboard wiring confirmed at `Sources/TeststripApp/AppModel.swift:210-260`
and `:5418`; scope titles at `:270-303`. Needs a human-present re-run,
including the preload-ahead spot-check above.
