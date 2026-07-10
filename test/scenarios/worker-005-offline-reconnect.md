# worker-005-offline-reconnect: The worker short-circuits offline sources and resumes after reconnect

**What this covers**: worker queue behavior around an unreachable source
volume — a `.generatePreview` command for an asset whose original is
`.offline`/`.missing`/`.stale` (`SourceAvailability`,
`Sources/TeststripCore/Domain/SourceAvailability.swift`) is short-circuited
rather than retried indefinitely
(`WorkerCommandExecutor.markPreviewBlockingAvailabilityIfNeeded`,
`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:274-283`, checked
both before *and* after a render attempt), and work for those assets
resumes once the source is available again. This card is narrowly scoped to
**worker queue behavior**: whether a queued/blocked item gets skipped vs.
error-looped, and whether it re-enqueues after availability flips back to
online. It does not cover the reconnect UI mechanics (the folder-picker
sheet, the "Reconnect" button, `reconnectSourceRoot`'s path-remapping) — that
belongs to the import-side reconnect card (cross-reference it once it
exists; as of this writing no `import-*` card in this directory owns that
surface yet, so there is currently no companion card to point to).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Needs a source that can be made unreachable on demand. Simplest reliable
technique: import from a folder on an external/removable volume mounted at a
throwaway path, or — since `--smoke`'s originals are ordinary files under
`$ISOLATED` — simulate offline by revoking read access or moving the file
out from under the catalog without updating it:
```bash
ASSET_ID=$(sqlite3 "$DB" "SELECT id FROM assets ORDER BY id LIMIT 1;")
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets WHERE id = '$ASSET_ID';")
mv "$SRC" "$SRC.hidden"   # original vanishes; catalog still points at $SRC
```

## Steps
1. `script/ax_drive.sh wait-vended`. Confirm `$ASSET_ID`'s availability is
   still `online` in the catalog before the move (it's a cached column, only
   refreshed on demand — this establishes the pre-condition ground truth):
   ```bash
   sqlite3 "$DB" "SELECT availability FROM assets WHERE id = '$ASSET_ID';"
   ```
2. **Force a fresh preview request for the now-missing original** — clear
   any cached preview so a real `.generatePreview` command is dispatched
   (e.g. select the asset in the loupe at a level not yet cached, or delete
   its cache entry if a dev affordance exists; confirm the actual trigger
   against the running UI before relying on it).
3. **Assert short-circuit, not an error loop.**
   ```bash
   sqlite3 "$DB" "SELECT asset_id, attempt_count, last_error FROM preview_generation_queue WHERE asset_id = '$ASSET_ID';"
   ```
   Poll a few times over ~10s. **Fails if** `attempt_count` climbs
   repeatedly (a retry-storm against an unreachable source) rather than the
   item being marked/skipped once availability resolves to `.offline`/
   `.missing`. Cross-check the assets table:
   ```bash
   sqlite3 "$DB" "SELECT availability FROM assets WHERE id = '$ASSET_ID';"
   ```
   Expect `offline` or `missing` (per `SourceAvailabilityProbe`, checked
   both before the render attempt and again in the catch block if the
   attempt itself fails — `WorkerCommandExecutor.swift:209-227`, `274-283`).
4. **Assert the rest of the queue is not blocked by this one offline item.**
   If other assets have pending preview/evaluation work, confirm they
   continue to drain normally while `$ASSET_ID` sits blocked — offline
   short-circuit must not consume the worker's single dispatch slot in a
   loop.
5. **Reconnect the source.**
   ```bash
   mv "$SRC.hidden" "$SRC"
   ```
6. **Trigger an availability re-check.** The app must have some path that
   re-probes availability (a periodic scan, or an explicit user action) —
   confirm which one is live in the running UI (grep suggests
   `refreshAvailability`/`refreshAvailabilityBatch` worker commands,
   `WorkerCommandExecutor.swift:284-301`); drive whichever is real rather
   than assuming.
7. **Assert resumed work.**
   ```bash
   sqlite3 "$DB" "SELECT availability FROM assets WHERE id = '$ASSET_ID';"   # expect online
   ```
   Then confirm a preview request for `$ASSET_ID` now succeeds (a real
   thumbnail lands, not another skip).

## Expected
- Step 3: `attempt_count` does not climb unboundedly and no busy-retry loop
  is observed — the offline short-circuit is a single mark-and-stop, not a
  retry storm. **Fails if** the queue instead re-attempts the same item
  repeatedly with growing `attempt_count` and no terminal state.
- Step 4: **Fails if** other queued assets stop draining while `$ASSET_ID`
  is offline — offline handling must not wedge the shared single-slot queue
  (the same class of bug `worker-004-death-recovery.md` covers for process
  death, applied here to a blocked-not-dead item).
- Step 7: **Fails if** availability never flips back to `online` after
  reconnect, or a subsequent preview request still short-circuits as if
  still offline (stale cached availability never re-probed).

## Cleanup
```bash
mv "$SRC.hidden" "$SRC" 2>/dev/null || true   # in case Step 5 didn't run
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- `SourceAvailability` is a cached column on `assets`
  (`Sources/TeststripCore/Domain/SourceAvailability.swift`), not computed
  live on every read — a stale `online` value can mask an offline source
  until something explicitly re-probes it. This card's Step 6 is the
  load-bearing step; if no live re-probe trigger exists in the current UI,
  say so explicitly rather than assuming one.
- `markPreviewBlockingAvailabilityIfNeeded` is checked twice: once before
  attempting the render (fast path, avoids even trying) and once in the
  `catch` if the render itself throws (slow path, catches a source that
  went offline mid-attempt). Distinguish which path fired when reporting a
  result — the pre-check path never touches `preview_generation_queue`'s
  `attempt_count`/`last_error` at all, since it throws before the render is
  attempted.
- This card was authored without being able to observe the live UI's actual
  reconnect/re-probe trigger — Step 6 names the worker commands that exist
  in source (`refreshAvailability`) but not which UI gesture fires them for
  a genuinely offline (not moved-root) asset. Flagged as an open question.

## Run status
Source citations (`SourceAvailability` handling, dual-check short-circuit,
`refreshAvailability` commands) were grep-confirmed against
`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` and
`Sources/TeststripCore/Domain/SourceAvailability.swift` on 2026-07-10. No
SQL was run live against a seeded catalog for this card's specific
file-move-then-reconnect sequence in this session. AX/live-driving steps
need a human-present or console-unlocked re-run, and Step 6's actual trigger
needs confirming against the live UI before the card can be trusted as
written.
