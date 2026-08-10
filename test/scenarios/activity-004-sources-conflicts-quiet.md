# activity-004-sources-conflicts-quiet: Sources and XMP problems compose, refresh, and return to quiet

**What this covers**: the Activity popover's quiet state, one source-
availability row, one presentation-level XMP conflict row, their simultaneous
problem count, and the transition back to quiet through the real Refresh
action.

Source: `Sources/TeststripApp/ActivityCenterView.swift` (section gates and
quiet predicate `:14-63`, Sources and Refresh `:173-220`, conflicts
`:241-268`), `Sources/TeststripApp/ActivityCenterPresentation.swift`
(problems-only badge `:142-190`), `Sources/TeststripApp/AppModel.swift`
(`activityCenterPresentation` `:2907-2955`,
`refreshVisibleAssetAvailability()` `:11101-11114`, availability labels
`:14179-14192`), and `Sources/TeststripApp/LibraryGridView.swift`
(`activityToolbarHelp` `:445-492`). The catalog constraints are
`Sources/TeststripCore/Catalog/CatalogMigrations.swift:12-39`: every
`original_path` is unique and `metadata_sync_state.status='conflict'` feeds
the conflict presentation.

## Pre-state

This is a VM-only fresh-smoke card. Every launch, AX action, filesystem
operation, and SQL query goes through `script/vm_scenario_run.sh`:

```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended Teststrip
```

Capture `smoke-0`'s original path as a SQLite literal before changing it, and
persist that literal in the card's owned fixture directory so cleanup remains
recoverable after a failed intermediate step:

```bash
script/vm_scenario_run.sh shell '
set -eu
run=$(ls -dt "$HOME"/teststrip-vm/run/smoke-* | head -1)
fixture="$HOME/teststrip-vm/fixtures/activity-004"
rm -rf "$fixture"
mkdir -p "$fixture"
sqlite3 "$run/Teststrip/catalog.sqlite" "SELECT quote(original_path) FROM assets WHERE id='smoke-0';" > "$fixture/original-path.sql"
test -s "$fixture/original-path.sql"
'
ORIGINAL_PATH_SQL=$(script/vm_scenario_run.sh shell 'cat "$HOME/teststrip-vm/fixtures/activity-004/original-path.sql"')
test -n "$ORIGINAL_PATH_SQL"
MISSING_PATH=/Users/admin/teststrip-vm/fixtures/activity-004/missing/smoke-0.jpg
CONFLICT_PATH=/Users/admin/teststrip-vm/fixtures/activity-004/activity-004-smoke-1.jpg.xmp
```

## Steps

### Part A: establish and render the quiet floor

1. Wait conditionally for the fresh seed's background work to drain. Prove
   the catalog has no active non-culling work, unavailable assets, XMP
   conflicts, or provider failures:

   ```bash
   attempt=0
   while [ "$attempt" -lt 180 ]; do
       ACTIVE_NON_CULL=$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM work_sessions WHERE kind!='culling' AND status IN ('queued','running','paused');")
       UNAVAILABLE=$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM assets WHERE availability!='online';")
       CONFLICTS=$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM metadata_sync_state WHERE status='conflict';")
       PROVIDER_FAILURES=$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(DISTINCT asset_id) FROM evaluation_failures;")
       test "$ACTIVE_NON_CULL" -eq 0 && test "$UNAVAILABLE" -eq 0 && test "$CONFLICTS" -eq 0 && test "$PROVIDER_FAILURES" -eq 0 && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$ACTIVE_NON_CULL" -eq 0
   test "$UNAVAILABLE" -eq 0
   test "$CONFLICTS" -eq 0
   test "$PROVIDER_FAILURES" -eq 0
   ```

2. Open the exact idle toolbar state. Assert `No active work` and the
   absence of active/problem headers and pause notices:

   ```bash
   script/vm_scenario_run.sh ax find --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "No active work"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Activity"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Sources"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused after current task"
   script/vm_scenario_run.sh key 'key code 53'
   ```

   `Recent Imports` and `Worker idle` may coexist with this floor. They are
   durable history and an idle process notice, not active work or problems.

### Part B: one missing source, then a simultaneous conflict

3. Prove the card's missing path is unique and nonexistent. Change only
   `smoke-0` to that path and mark it missing:

   ```bash
   test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM assets WHERE original_path='$MISSING_PATH';")" -eq 0
   script/vm_scenario_run.sh shell 'test ! -e /Users/admin/teststrip-vm/fixtures/activity-004/missing/smoke-0.jpg'
   script/vm_scenario_run.sh sql smoke "UPDATE assets SET original_path='$MISSING_PATH', availability='missing' WHERE id='smoke-0';"
   test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM assets WHERE id='smoke-0' AND original_path='$MISSING_PATH' AND availability='missing';")" -eq 1
   ```

4. Quit and relaunch the same recorded smoke run through the wrapper. Do not
   call `launch smoke`, which would replace the mutated run with a fresh copy:

   ```bash
   script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
   script/vm_scenario_run.sh shell '
   sleep 1
   run=$(ls -dt "$HOME"/teststrip-vm/run/smoke-* | head -1)
   open -n "$HOME/teststrip-vm/dist/Teststrip.app" --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$run"
   '
   script/vm_scenario_run.sh ax wait-vended Teststrip
   ```

5. Assert one problem and the source row's current UI contract:

   ```bash
   script/vm_scenario_run.sh ax find --role AXButton --help "Activity - 1 problem"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - 1 problem"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Sources"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Missing Originals"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Missing"
   script/vm_scenario_run.sh ax find --role AXButton --help "Refresh source availability"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh key 'key code 53'
   ```

6. While Sources remains unresolved, seed one owned presentation-only
   conflict for `smoke-1`. A fresh smoke run must not already own a sync-state
   row for that asset:

   ```bash
   test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM metadata_sync_state WHERE asset_id='smoke-1';")" -eq 0
   script/vm_scenario_run.sh sql smoke "INSERT INTO metadata_sync_state (asset_id, sidecar_path, catalog_generation, last_synced_fingerprint, status, updated_at) SELECT 'smoke-1', '$CONFLICT_PATH', catalog_generation, 'activity-004-presentation-only', 'conflict', CAST(strftime('%s','now') AS REAL) FROM assets WHERE id='smoke-1';"
   test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM metadata_sync_state WHERE asset_id='smoke-1' AND sidecar_path='$CONFLICT_PATH' AND status='conflict';")" -eq 1
   ```

7. Relaunch that same run again, then assert both independent sections and
   the exact two-problem help:

   ```bash
   script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
   script/vm_scenario_run.sh shell '
   sleep 1
   run=$(ls -dt "$HOME"/teststrip-vm/run/smoke-* | head -1)
   open -n "$HOME/teststrip-vm/dist/Teststrip.app" --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$run"
   '
   script/vm_scenario_run.sh ax wait-vended Teststrip
   script/vm_scenario_run.sh ax find --role AXButton --help "Activity - 2 problems"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - 2 problems"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Sources"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Missing Originals"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh ax find --role AXButton --label "activity-004-smoke-1.jpg"
   script/vm_scenario_run.sh key 'key code 53'
   ```

   This row tests Activity presentation and badge composition. Real sidecar
   divergence, detection, and conflict persistence belong to
   `activity-006-xmp-lifecycle.md`.

### Part C: restore, Refresh, and return to quiet

8. Restore `smoke-0`'s captured path while deliberately leaving its
   availability as `missing`. Reopen the two-problem popover and press the
   real Refresh action only after the path is valid again:

   ```bash
   ORIGINAL_PATH_SQL=$(script/vm_scenario_run.sh shell 'cat "$HOME/teststrip-vm/fixtures/activity-004/original-path.sql"')
   script/vm_scenario_run.sh sql smoke "UPDATE assets SET original_path=$ORIGINAL_PATH_SQL WHERE id='smoke-0';"
   test "$(script/vm_scenario_run.sh sql smoke "SELECT availability FROM assets WHERE id='smoke-0';")" = missing
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - 2 problems"
   script/vm_scenario_run.sh ax press --role AXButton --help "Refresh source availability"
   ```

9. Poll the catalog until the refresh work returns `smoke-0` online and all
   non-culling work retires. Assert Sources clears while the owned XMP
   conflict remains and the badge becomes one problem:

   ```bash
   attempt=0
   while [ "$attempt" -lt 120 ]; do
       AVAILABILITY=$(script/vm_scenario_run.sh sql smoke "SELECT availability FROM assets WHERE id='smoke-0';")
       ACTIVE_NON_CULL=$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM work_sessions WHERE kind!='culling' AND status IN ('queued','running','paused');")
       test "$AVAILABILITY" = online && test "$ACTIVE_NON_CULL" -eq 0 && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$AVAILABILITY" = online
   test "$ACTIVE_NON_CULL" -eq 0
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Sources"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
   script/vm_scenario_run.sh ax find --role AXButton --label "activity-004-smoke-1.jpg"
   script/vm_scenario_run.sh ax find --role AXButton --help "Activity - 1 problem"
   script/vm_scenario_run.sh key 'key code 53'
   ```

10. Delete only the owned conflict, relaunch the same run so its cached
    conflict projection reloads, and repeat the quiet proof:

    ```bash
    script/vm_scenario_run.sh sql smoke "DELETE FROM metadata_sync_state WHERE asset_id='smoke-1' AND sidecar_path='$CONFLICT_PATH';"
    test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM metadata_sync_state WHERE status='conflict';")" -eq 0
    script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
    script/vm_scenario_run.sh shell '
    sleep 1
    run=$(ls -dt "$HOME"/teststrip-vm/run/smoke-* | head -1)
    open -n "$HOME/teststrip-vm/dist/Teststrip.app" --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$run"
    '
    script/vm_scenario_run.sh ax wait-vended Teststrip
    test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM assets WHERE availability!='online';")" -eq 0
    test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM work_sessions WHERE kind!='culling' AND status IN ('queued','running','paused');")" -eq 0
    test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(*) FROM metadata_sync_state WHERE status='conflict';")" -eq 0
    test "$(script/vm_scenario_run.sh sql smoke "SELECT COUNT(DISTINCT asset_id) FROM evaluation_failures;")" -eq 0
    script/vm_scenario_run.sh ax find --role AXButton --help "Activity"
    script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
    script/vm_scenario_run.sh ax find --role AXStaticText --label "No active work"
    ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Activity"
    ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Sources"
    ! script/vm_scenario_run.sh ax find --role AXStaticText --label "XMP Conflicts"
    ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused"
    ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused after current task"
    ```

## Expected

- Quiet fails unless SQL proves no active non-culling work, unavailable assets,
  XMP conflicts, or provider failures and AX shows `No active work` without
  Activity, Sources, XMP Conflicts, or pause notices. Durable receipts may
  coexist.
- The missing-source leg fails unless the unique missing path produces
  `Missing Originals`, `Missing`, Refresh, and exactly one problem.
- Composition fails unless Sources and XMP Conflicts render simultaneously
  and toolbar help reads exactly `Activity - 2 problems`.
- Refresh fails unless the captured path is restored first, the UI action
  moves `smoke-0` from missing to online, Sources clears, XMP remains, and the
  help becomes exactly one problem.
- Final quiet fails unless deleting only the owned conflict and relaunching
  removes the last problem and restores the original quiet assertions.

## Cleanup

Cleanup restores path and availability before removing the recovery literal,
and deletes only the conflict and fixture this card owns:

```bash
if ORIGINAL_PATH_SQL=$(script/vm_scenario_run.sh shell 'test -f "$HOME/teststrip-vm/fixtures/activity-004/original-path.sql" && cat "$HOME/teststrip-vm/fixtures/activity-004/original-path.sql"'); then
    script/vm_scenario_run.sh sql smoke "UPDATE assets SET original_path=$ORIGINAL_PATH_SQL, availability='online' WHERE id='smoke-0';"
fi
script/vm_scenario_run.sh sql smoke "DELETE FROM metadata_sync_state WHERE asset_id='smoke-1' AND sidecar_path='/Users/admin/teststrip-vm/fixtures/activity-004/activity-004-smoke-1.jpg.xmp';"
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
script/vm_scenario_run.sh shell 'rm -rf "$HOME/teststrip-vm/fixtures/activity-004"'
```

## Sharp edges

- Bookmark-repair and Reconnect are an explicit fixture gap, not pass
  criteria here. They require a registered source root with a genuinely
  invalid security-scoped bookmark. `import-007-refresh-reconnect.md` owns
  that lifecycle.
- The owned `metadata_sync_state` row is presentation-only. It proves section
  separation and badge arithmetic without pretending to prove sidecar
  detection. `activity-006-xmp-lifecycle.md` owns real conflict generation.
- Relaunching the same run is required after out-of-band SQL because the model
  caches source summaries and conflict items. Calling `launch smoke` would
  silently discard the mutation and make these assertions vacuous.
- Restoring `original_path` from another asset violates the unique index.
  Updating `availability='online'` in SQL would bypass the Refresh action.
  This card does neither.

## Run status

**Spec'd — NOT RUN (2026-08-10).** The executable procedure has been repaired
against current source and schema, but no UI or VM leg has ever run. The old
LEDGER `Tested-Fail` label was not supported by a driven failure and is
corrected to this truthful pre-test state.

Historical evidence is preserved:

- 2026-07-10: `source_roots` emptiness and the smoke catalog schema were
  inspected headlessly. No UI leg ran.
- 2026-08-10: a docs-only contract cleanup re-anchored the quiet semantics.
  It still ran no UI leg. This repair fixes the duplicated-path restore, the
  Refresh ordering, and the mutually exclusive Sources/conflict setup before
  the first live drive.
