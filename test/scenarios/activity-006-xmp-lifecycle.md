# activity-006-xmp-lifecycle: XMP conflicts arise from divergence or unreadable sidecars, and never auto-resolve

**What this covers**: `MetadataSyncPlanner.decision` (both-diverged
conflicts, `MetadataSyncPlanner.swift:35-47`) and
`WorkerCommandExecutor.recordConflictForUnreadableSidecar` (corrupt/torn
sidecars, `WorkerCommandExecutor.swift:550-576`) — the two distinct code
paths that produce an XMP conflict — plus the durability invariant: once
`metadata_sync_state.status = 'conflict'`, repeated sync scans never
re-evaluate or clear it (`CatalogRepository.pendingMetadataSyncItems` only
selects `status = 'pending'` rows, `CatalogRepository.swift:1767-1777`, so a
conflicted row is structurally excluded from the scan's input set).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps

### Sub-case A: both catalog and sidecar diverged since last sync
1. `script/ax_drive.sh wait-vended Teststrip`. Rate an asset via the
   inspector (e.g. 5 stars) so a `.xmp` sidecar is written and
   `metadata_sync_state` gets a row with `status = 'synced'`/`'pending'` for
   it (confirm actual post-write status value against a live catalog before
   asserting an exact string — not independently re-derived this pass).
   ```bash
   SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets WHERE id = 'smoke-0';")
   sqlite3 "$DB" "SELECT asset_id, status, catalog_generation FROM metadata_sync_state WHERE asset_id = 'smoke-0';"
   ```
2. **Diverge the catalog** (`localChanged` — the in-app path): rate the same
   asset differently again via the inspector (e.g. 3 stars) *without*
   letting a sync scan run in between, so `assets.catalog_generation`
   advances past what `metadata_sync_state.catalog_generation` recorded.
3. **Diverge the sidecar independently, out-of-band**: edit the `.xmp` file
   directly (not through the app) to a third rating value:
   ```bash
   sed -i '' 's/Rating="[0-9]"/Rating="1"/' "$SRC.xmp"
   ```
   Now both `localChanged` and `sidecarContentChanged` are true relative to
   the last-synced fingerprint — the exact condition
   `MetadataSyncPlanner.decision`'s `case (true, true, _)` matches
   (`MetadataSyncPlanner.swift:42-47`).
4. Trigger the next sync scan — use Metadata ▸ **Check Sidecars for
   Changes** (or relaunch; both run the rescan — see Sharp edges). Assert a
   conflict was recorded:
   ```bash
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id = 'smoke-0';"   # expect 'conflict'
   sqlite3 "$DB" "SELECT count(*) FROM metadata_sync_state WHERE status = 'conflict';"
   ```
   and that the Activity popover's XMP Conflicts section lists it
   (`ax_drive.sh find --contains` the sidecar's basename, per
   `quiet-activity-badge.md` step 5).

### Sub-case B: sidecar becomes unreadable/corrupt
5. Clean up sub-case A's state (`./script/reset_isolated_test_data.sh --delete`
   and relaunch) or pick a second, untouched asset for a clean run.
6. Rate the asset via the inspector so a valid `.xmp` sidecar exists and
   syncs cleanly (`status` reads clean/synced — confirm exact value live).
7. **Corrupt the sidecar out-of-band**, twice, to satisfy
   `recordConflictForUnreadableSidecar`'s double-read-same-garbage guard
   (`WorkerCommandExecutor.swift:560-568` — a single torn read is treated as
   an in-progress write by another tool and does *not* record a conflict;
   only a read that stays unparsable on a second fetch does):
   ```bash
   printf 'not xml at all' > "$SRC2.xmp"
   ```
   (a static corrupt file trivially satisfies "same bytes on re-read" since
   nothing is actively rewriting it).
8. Trigger the next sync scan. Assert the conflict was recorded via this
   *different* code path (no catalog-generation divergence was needed —
   only the corrupt sidecar):
   ```bash
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id = '<second-asset-id>';"   # expect 'conflict'
   ```
9. Cross-check against the comment at `WorkerCommandExecutor.swift:545-549`:
   *"A sync step that fails because the existing sidecar cannot be parsed
   would otherwise retry forever as a silently pending item. Recording the
   existing conflict state instead routes the asset into XMP Conflicts
   review, where the inspector surfaces the unreadable sidecar and offers
   Use Catalog to recreate it."* — confirm the inspector does show an
   "unreadable sidecar" affordance for this asset (the "Use Catalog"
   resolution action itself is out of scope per this card's brief).

### Never-auto-resolve invariant
10. Using sub-case A's conflicted asset (`smoke-0`, still in `conflict`
    status), trigger **two more** sync scans in a row (repeat whatever
    step-4 trigger worked, twice) without any user resolution action in
    between. After each, assert `status` is still `'conflict'` and the
    fingerprint/generation columns are unchanged:
    ```bash
    sqlite3 "$DB" "SELECT status, catalog_generation, last_synced_fingerprint FROM metadata_sync_state WHERE asset_id = 'smoke-0';"
    ```
    **This is the load-bearing assertion of this card**: a conflicted row's
    `metadata_sync_state` values must be byte-identical across repeated
    scans. Structurally, this is guaranteed by
    `pendingMetadataSyncItems` only querying `status = 'pending'`
    (`CatalogRepository.swift:1767-1777`) — a `'conflict'` row is invisible
    to the scan's own input query, so there is no code path by which a scan
    could silently flip it back. Confirm this holds by direct observation,
    not just by citing the query.

## Expected
- Step 4: **Fails if** no conflict is recorded despite both catalog and
  sidecar diverging, or if only one divergence (not both) suffices —
  the card's fixture must confirm both are necessary, not just sufficient
  (e.g. repeat with *only* step 2 or *only* step 3 done, and confirm no
  conflict is recorded — a plain `writeCatalog` or `importSidecar` decision
  instead, per `MetadataSyncPlanner.swift:38-41`).
- Step 8: **Fails if** the corrupt-sidecar path does not independently
  produce a conflict without any catalog-side change.
- Step 10: **Fails if** `status` ever reverts to `pending`/`synced` or the
  fingerprint/generation values change across a scan with no user
  resolution action — this is the auto-resolve regression this card exists
  to catch.

## Cleanup
```bash
rm -f "$SRC.xmp" "$SRC2.xmp" 2>/dev/null
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **The no-rescan product gap is closed (Jesse's ruling 2026-07-11).** Two
  UI-reachable triggers now exist for "trigger the next sync scan" (steps
  4, 8, 10):
  1. **Relaunch the app** — catalog open runs a whole-catalog sidecar
     rescan (`AppModel.performLaunchSidecarRescan`, wired via `.task` in
     `Sources/TeststripApp/main.swift`), batched off the main actor.
  2. **Metadata ▸ Check Sidecars for Changes** — the same rescan on demand
     over the **whole catalog**, regardless of any active library filters
     (`checkSidecarsForChangesInCurrentScope`). persona-6 regression guard:
     with a Pick chip (or any filter) active that excludes the edited asset,
     the menu command must STILL flag the edit — it previously scoped to the
     filter and missed real out-of-band edits silently. Assert this leg with
     a filter active.
  Both walk `metadata_sync_state` rows with `status='synced'`, cheap-gate on
  sidecar mtime vs the recorded sync instant, fingerprint-compare changed
  files, and re-enter the existing planner semantics: sidecar-only change →
  `pending` (worker re-syncs); sidecar + catalog both changed → `conflict`.
  No schema change was needed — `last_synced_fingerprint` (content hash) and
  `updated_at` already record what the check needs. Core logic:
  `Sources/TeststripCore/Metadata/SidecarRescanService.swift`; unit coverage:
  `SidecarRescanServiceTests` (pending/conflict/cheap-gate/missing/scope) +
  `SidecarRescanAppTests` (model plumbing, status line, filter-independence).
  The menu command **always** reports completion in the status line —
  "Checked N sidecars — M changed on disk, queued to re-sync" when it found
  edits, "Checked N sidecars — no changes" when it did not; silence after
  the menu click is a failure. The launch rescan reports only when it found
  changes. PENDING-VM: the live-driven legs (menu click, relaunch trigger, AX
  assertions) have not been re-run — VM unavailable this pass.
- Sub-case A requires *not* letting a sync scan run between steps 1-2 and
  step 3 (or the catalog-only divergence would resolve to `writeCatalog`
  before the sidecar is touched) — sequencing still matters: forcing a scan
  is now easy (menu command), but the worker's own automatic sync of the
  step-1 rating can still land between steps; do steps 2 and 3 promptly and
  only then fire the menu command.
- Step 1 and step 6's exact `metadata_sync_state.status` value immediately
  after a clean rate-and-sync was not independently re-derived this pass —
  confirm the literal string (`'synced'`, `'clean'`, or similar) against a
  live catalog before asserting it exactly.
- `MetadataSyncPlanner.decision` is a pure function with a small, fully
  enumerated case table (`MetadataSyncPlanner.swift:35-47`) — worth unit-test
  coverage independent of this end-to-end card if it doesn't already exist;
  not verified whether `MetadataSyncPlannerTests` covers the `(true, true,
  _)` conflict case specifically.

## Run status
NOT RUN — no host GUI available in this session. The two-code-path
distinction (`MetadataSyncPlanner.decision`'s `(true, true, _)` case vs.
`recordConflictForUnreadableSidecar`'s double-read guard) and the
never-auto-resolve structural guarantee (`pendingMetadataSyncItems` querying
only `status = 'pending'`) are confirmed by direct source citation
(`Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift`,
`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`,
`Sources/TeststripCore/Catalog/CatalogRepository.swift`). Schema (`metadata_sync_state`
columns) confirmed against `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
and an empty seeded `--smoke` catalog (`metadata_sync_state` has 0 rows at
launch, confirmed via `sqlite3` 2026-07-10) — no live conflict-producing SQL
was actually executed against a running instance this pass; the sync-scan
trigger gap above blocks it. Needs a human-present or console-unlocked
re-run to determine a working trigger and complete both sub-cases live.
