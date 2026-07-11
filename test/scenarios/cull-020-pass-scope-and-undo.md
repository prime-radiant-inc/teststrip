# cull-020-pass-scope-and-undo: P/X/S/Return in the Cull workspace, and ⌘Z reverts one gesture at a time

**What this covers**: the Cull workspace's keyboard loop — pick (`P`) and
reject (`X`) a few frames, cycle scope with `S` to Picks and confirm the
sidebar/HUD reflect it, then Return on a stack writes pick+sibling-rejects as
one gesture. Undo is scoped per gesture, not per pass: a single ⌘Z reverts
the *stack promote* gesture's flags (pick + all sibling rejects) as one unit,
while each standalone `P`/`X` keystroke is its own separate undo step (per
spec/plan Task 16: "single undo group: one ⌘Z reverts the whole gesture" —
the gesture is the Return promote action, not the whole multi-keystroke
pass).

## Pre-state
```bash
# The `burst` variant makes the stack leg (step 5) drivable: it seeds 4
# auto-groupable stacks (capture times 1s apart). The pass/scope/undo legs
# work identically on it.
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
# ground truth via: script/vm_scenario_run.sh sql burst "..."
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
5. Advance to a frame that belongs to a multi-frame stack; press Return.
   With the `burst` seed, Return fires on the in-memory auto stack —
   `promoteCurrentFrameAndRejectSiblings` accepts membership in
   `cullingStacks()` (AssetStackBuilder auto-grouping), not only a
   persisted work stack — so assert the promote wrote pick + sibling
   rejects across that auto stack's 3-4 members (ground truth: the
   burst group's assets share capture times <=2s apart in
   `technical_metadata_json.capturedAt`). The persisted-set variant below
   applies when a `work-stack-%` set exists (requires a live import):
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
6. Note the flagged count after step 5 (`AFTER_STACK`). Press ⌘Z once.
   Assert **only** the stack promote gesture from step 5 is reverted: the
   flagged count returns to `AFTER_STACK` minus that stack's members (i.e.
   back to its pre-step-5 value), the Return target and every sibling from
   step 5 read NULL again, but the standalone `P`/`X` flags from step 3 are
   still set (not yet touched by this ⌘Z).
7. Press ⌘Z twice more (once per step-3 keystroke). Assert the flagged count
   now returns to `BASELINE` and the step-3 ids read NULL — each standalone
   `P`/`X` keystroke was its own separate undo step, not grouped with the
   others or with the stack gesture.

## Expected
- Step 3: exactly the picked/rejected frames show the matching flag.
- Step 4: scope indicator and visible set both read Picks-only.
- Step 5: stack Return is one atomic gesture — pick the Return target,
  reject every sibling, in the same transaction. **Fails if** siblings need a
  separate action, or if some siblings are left undecided.
- Step 6: a single ⌘Z reverts exactly the step-5 stack gesture's flags (pick +
  all siblings) as one unit, and nothing else. **Fails if** it reverts only
  one sibling at a time (gesture isn't grouped), or if it also reverts the
  unrelated step-3 flags (undo grouping is too coarse, spanning gestures).
- Step 7: the two step-3 keystrokes each undo separately (two more ⌘Z to
  clear both). **Fails if** they were already grouped together, or if they
  got grouped with the step-5 gesture.
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
