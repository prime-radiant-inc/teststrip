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
2. Record the baseline — **`--smoke` pre-seeds flags** (verified against a
   seeded catalog 2026-07-10: 11 of 24 assets launch already flagged), so do
   NOT assert 0 here:
   ```bash
   BASELINE=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NOT NULL;")
   ```
3. Press `P` (pick current frame), advance (Space), press `X` (reject the
   next frame) — choose frames that launch unflagged. Assert the two frames
   now carry the right flag:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN ('<picked-id>','<rejected-id>');"
   ```
4. Press `S` to cycle scope to Picks. Assert the HUD/sidebar scope indicator
   reads "Picks" (`ax_drive.sh find --contains "Picks"` in the scope area)
   and the visible set narrows to picked frames only.
5. Advance to a frame that belongs to a persisted stack; press Return.
   There is no `assets.stack_id` column — persisted stack membership lives in
   `asset_sets.membership_json` (set ids prefixed `work-stack-`, member ids
   at JSON path `$.manual._0[].rawValue`; loaded/derived stacks exist only
   in-memory via `AssetStackBuilder`, so drive a *persisted* stack). Assert
   **one gesture** wrote pick + sibling rejects across the stack's members:
   ```bash
   sqlite3 "$DB" "
     SELECT json_extract(m.value,'\$.rawValue') AS member,
            (SELECT json_extract(a.metadata_json,'\$.flag') FROM assets a
              WHERE a.id = json_extract(m.value,'\$.rawValue')) AS flag
     FROM asset_sets s, json_each(s.membership_json,'\$.manual._0') m
     WHERE s.id = '<work-stack-set-id>';"
   ```
   confirms exactly one `pick` (the Return target) and every other member
   `reject`. (Query shape verified against a seeded `--smoke` catalog
   2026-07-10; if the set was stored as a snapshot, use `$.snapshot._0` —
   the two paths mirror `CatalogRepository.workSessionAssetMembershipSelector`.)
6. Press ⌘Z. Assert every flag set in steps 3 and 5 is cleared in one undo —
   the flagged count returns to `BASELINE` and the specific ids from steps
   3/5 read NULL again — a single ⌘Z reverts the whole pass, not just the
   last stack decision.

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
and `:5418`; scope titles at `:270-303`. All SQL in this card was run
headlessly against a seeded `--smoke` catalog on 2026-07-10 (schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`). Needs a
human-present re-run, including the preload-ahead spot-check above.
