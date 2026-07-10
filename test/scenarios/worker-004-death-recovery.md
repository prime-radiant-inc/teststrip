# worker-004-death-recovery: The queue recovers when the worker process dies mid-item

**What this covers**: commit `4962f0d` ("fix: recover the work queue when the
worker process dies") — before the fix, an out-of-process `TeststripWorker`
that exited on its own (crash, OOM, OS reap) went undetected:
`FoundationWorkerTransport` set no `terminationHandler`, so the in-flight
item stayed stuck in the supervisor's dispatched set and, with a single
dispatch slot, wedged every queued item at "queued" forever with no worker
running. The fix (`WorkerSupervisor.handleWorkerTermination`,
`Sources/TeststripCore/Worker/WorkerSupervisor.swift:311-333`) detects
unexpected exit via a new `WorkerTransport.terminationHandler`
(`Sources/TeststripCore/Worker/WorkerTransport.swift`), retries each in-flight
item once on a fresh worker, and — if that item's worker dies a second time —
fails the item and moves on so one poison item can't re-wedge the queue.

**This card runs a real `kill -9` against a live subprocess of a running app
instance. Read the Run status section before running it — throwaway isolated
instance only, never Jesse's real catalog/session.**

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--smoke`'s previews are pre-rendered (see `worker-001-preview-lifecycle.md`),
so import fresh content to get real, currently-dispatchable queue depth:
```bash
FIXTURES=$(mktemp -d)/fresh
swift run TeststripBench seed-dup-fixtures "$FIXTURES"
IMPORT_DIR="$FIXTURES/card2"   # 6 JPEGs — enough queue depth to observe resumption
```
A genuinely poisoned item, for the second-strike assertion:
```bash
POISON_DIR=$(mktemp -d)/poison
mkdir -p "$POISON_DIR"
head -c 2048 /dev/urandom > "$POISON_DIR/corrupt.jpg"   # not a valid JPEG; deterministic decode failure
```

## Steps
1. `script/ax_drive.sh wait-vended`. Import `$IMPORT_DIR` (typed-path route,
   `script/submit_import_path.sh Teststrip "$IMPORT_DIR"`) — this queues
   several `preview_generation_queue` rows. Confirm depth before killing
   anything:
   ```bash
   sqlite3 "$DB" "SELECT asset_id, level FROM preview_generation_queue;"
   ```
2. **Identify the live worker PID precisely.** The worker binary is
   `TeststripWorker` (`Package.swift:12`, executable target), launched at
   `<App>.app/Contents/Helpers/TeststripWorker` per
   `script/import_verifier_metrics.sh:53` and `Sources/TeststripApp/AppCatalog.swift:107`.
   Match by exact process name, scoped to this isolated instance's args (the
   catalog path is a command-line argument, per
   `script/test_import_verifier_metrics.sh:18`):
   ```bash
   WORKER_PID=$(/bin/ps -axo pid,command | awk -v db="$DB" '$0 ~ /TeststripWorker/ && $0 ~ db {print $1; exit}')
   ```
   **Fails the card outright if `$WORKER_PID` is empty** — either nothing is
   currently dispatched (poll again after import) or the match pattern is
   wrong; do not proceed to kill an unconfirmed PID.
3. **Kill it mid-queue.**
   ```bash
   kill -9 "$WORKER_PID"
   ```
4. **Assert relaunch.** `dispatchRunnableItems` auto-launches the transport
   if not running (`WorkerSupervisor.swift:248-249`), invoked from
   `handleWorkerTermination`'s recovery path — so a fresh `TeststripWorker`
   process should appear within a few seconds:
   ```bash
   sleep 3
   /bin/ps -axo pid,command | grep -v grep | awk -v db="$DB" '$0 ~ /TeststripWorker/ && $0 ~ db {print}'
   ```
   **Fails if** no `TeststripWorker` process matching this catalog reappears
   — the queue is wedged, exactly the pre-fix bug.
5. **Assert the queue resumes, not wedges.** Poll (staying frontmost via
   `ax_drive.sh wait-vended` each poll):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue;"
   ```
   Must drain to 0 (all remaining items complete on the fresh worker), not
   stall at the depth observed right after the kill.
6. **Assert the in-flight item was retried, not silently dropped.** The item
   that was actually dispatched at kill time should still produce a real
   preview (it wasn't a poisoned file) — check its thumbnail exists:
   ```bash
   sqlite3 "$DB" "SELECT id, original_path FROM assets WHERE original_path LIKE '%$IMPORT_DIR%';"
   ```
   For the specific asset that was in-flight (cross-reference Step 1's queue
   snapshot against the process's last progress line, if visible in
   `script/build_and_run.sh --logs`), confirm its `preview_generation_queue`
   row is gone (completed) and a preview file exists under
   `$ISOLATED/Teststrip/Previews`.
7. **Poison-item second strike.** Import `$POISON_DIR` (same typed-path
   route). Its `corrupt.jpg` will fail to decode deterministically — but a
   decode failure alone goes through the *normal* failure path
   (`WorkerCommandExecutor.execute`'s `catch` at
   `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:209-227`, which
   calls `repository.recordPreviewGenerationFailure` and rethrows — this
   does **not** crash the worker process). To exercise the *process-death*
   second-strike path in `handleWorkerTermination`
   (`WorkerSupervisor.swift:311-333`, `terminationRetriedItemIDs`), the
   poisoned item's worker must die twice in a row while it is the dispatched
   item:
   ```bash
   # Wait until corrupt.jpg's generatePreview command is the dispatched item, then:
   WORKER_PID=$(/bin/ps -axo pid,command | awk -v db="$DB" '$0 ~ /TeststripWorker/ && $0 ~ db {print $1; exit}')
   kill -9 "$WORKER_PID"    # first strike: retried once (terminationRetriedItemIDs gets the item)
   sleep 3
   WORKER_PID=$(/bin/ps -axo pid,command | awk -v db="$DB" '$0 ~ /TeststripWorker/ && $0 ~ db {print $1; exit}')
   kill -9 "$WORKER_PID"    # second strike on the SAME item: must fail it, not retry again
   ```
8. **Assert terminal failure, not infinite retry or a wedge.**
   ```bash
   sqlite3 "$DB" "SELECT id, status, detail FROM work_sessions WHERE detail LIKE '%corrupt%' OR title LIKE '%preview%' ORDER BY updated_at DESC LIMIT 5;"
   ```
   The corrupt asset's preview-generation work session must land at
   `status = 'failed'` (`WorkSessionStatus.failed`,
   `Sources/TeststripCore/Work/WorkSession.swift:27-33`) with a detail
   matching `workerExitedUnexpectedlyDetail`'s format — `"Worker exited
   unexpectedly: <operation>"` (`WorkerSupervisor.swift:420-424`) — and the
   queue must keep processing: confirm any *other* still-queued item (if
   present) continues to drain rather than the whole queue stalling behind
   the poisoned one.

## Expected
- Step 4: **Fails if** no fresh `TeststripWorker` process appears — the
  pre-fix wedge (undetected death → no relaunch → every subsequent item
  parked at "queued" forever).
- Step 5: **Fails if** `preview_generation_queue` never drains after the
  kill — items dispatched before the fresh worker's first item stayed
  wedged behind the dead one.
- Step 6: **Fails if** the in-flight item at kill time is missing entirely
  (dropped, not retried) rather than either completing on the fresh worker
  or (if genuinely poisoned) landing in `failed`.
- Step 8: **Fails if** the corrupt item's work session never reaches
  `failed` (infinite retry loop — the exact "single poison item can't
  re-wedge the queue" regression the commit fixes) OR if a healthy sibling
  item queued behind it never processes (queue-level wedge, not just an
  item-level one).

## Cleanup
```bash
rm -rf "$FIXTURES" "$POISON_DIR"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance. Confirm no stray `TeststripWorker` process
survives: `pgrep -x TeststripWorker` should return nothing once the app quits
(if it does, `pkill -x TeststripWorker` as a last resort — but only after
confirming via `ps` that it's this isolated instance's, not a real session's).

## Sharp edges
- `terminationRetriedItemIDs` is per-item and clears on
  `markCompleted`/`stop`/timeout (`WorkerSupervisor.swift:142,184,212,391-393`)
  — a *different* item dying twice does not share the poisoned item's strike
  count; only the same `WorkSessionID` dying twice in a row triggers the
  terminal-failure path. Step 7's timing (killing while the corrupt item is
  specifically the dispatched one, twice) is the whole point — killing at the
  wrong moment retries a healthy item instead and proves nothing about the
  poison path.
- `WorkerCommandExecutor`'s in-process catch for a normal decode failure
  (Step 7's first sentence) does **not** exercise
  `handleWorkerTermination` at all — that's the pre-existing single-retry-then-fail
  path for command-level errors, a different (and already-covered) mechanism
  from the process-death path this card targets. Don't conflate the two;
  this card must kill the actual process, not merely feed it a bad file.
- No `swift run TeststripBench` scenario in this repo currently drives a real
  `kill -9` end-to-end (the existing `WorkerRecoverySmoke` bench tool
  simulates recovery in-process against a `RecordingWorkerTransport`, per
  `Sources/TeststripBench/WorkerRecoverySmoke.swift` — useful for grounding
  the queue-seeding shape, but it does not touch a real OS process). This
  card is the first to actually kill the live subprocess.

## Run status
**CAUTION — real `kill -9` against a live subprocess.** This card must only
ever be run against a throwaway `--smoke` isolated instance
(`$ISOLATED` under `$TMPDIR`), confirmed by grepping the killed PID's full
command line for `$DB`'s path before every `kill -9` (Steps 2 and 7) — never
run this against Jesse's real session or any instance whose catalog path you
have not explicitly verified. If a human is not present to visually confirm
which app window/process is being targeted, do not run this card
unattended; a mis-scoped `kill -9` against the wrong `TeststripWorker`
process (e.g. a real dogfooding session) would kill live background work
with no undo. SQL/source citations (status vocabulary, recovery code paths,
process/executable naming) were ground-truthed by reading
`Sources/TeststripCore/Worker/WorkerSupervisor.swift`,
`Sources/TeststripCore/Worker/WorkerTransport.swift`, and
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` directly on
2026-07-10, plus commit `4962f0d`'s diff and
`Tests/TeststripCoreTests/WorkerSupervisorTests.swift`
(`testUnexpectedWorkerTerminationRetriesInFlightItemOnce`,
`testSecondUnexpectedWorkerTerminationFailsItemAndStartsNextQueuedWork`) for
the unit-level guarantee this card proves end-to-end. No live kill was
executed in this session (no host GUI, and killing a real subprocess
requires a human present per the caution above) — needs a human-present
re-run with visual confirmation of the target instance before each kill.
