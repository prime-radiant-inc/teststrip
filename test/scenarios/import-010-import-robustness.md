# import-010-import-robustness: large card imports survive slow copies, refuse a full disk, and show real counts

**What this covers**: three fixes to the copy-import path that a large, real
card import exercises (commits on branch fix/import-watchdog-and-count):
1. **Watchdog heartbeat** — `IngestProgressCoalescer`/`ScanProgressCoalescer`
   (`Sources/TeststripCore/Ingest/LibraryImportService.swift`) now emit progress
   on a 15s time heartbeat, not only every 500/100 files, so the
   `WorkerSupervisor` 120s per-command watchdog never kills a healthy but slow
   copy (an 864-photo card copying slower than ~4 files/s used to time out at
   file ~500). Covered by `ProgressCoalescerTests` +
   `WorkerSupervisorTests.testProgressWorkerEventReschedulesCommandTimeout`.
2. **Free-space preflight** — `IngestService.validateAvailableSpace`
   (`Sources/TeststripCore/Ingest/IngestService.swift`) sums the source bytes and
   checks the destination volume's `volumeAvailableCapacityForImportantUsage`
   before copying; an import that wouldn't fit fails fast with a clear "Not
   enough space … on <volume>" error and copies nothing, instead of filling the
   disk until the SQLite catalog can no longer open. Covered by
   `IngestPreflightTests` (injected capacity).
3. **Real preview count** — `ImportSourceSummary.scan`
   (`Sources/TeststripApp/ImportConfirmationDraft.swift`) is time-bounded (2s
   budget, high numeric backstops) so the confirmation sheet shows the true
   photo count instead of a misleading "300+". Covered by
   `ImportConfirmationDraftTests`.

## Pre-state
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke   # note run dir $RUN
script/vm_scenario_run.sh ax wait-vended Teststrip
```
Live legs need a folder of > 300 recognized photos and a small/full destination
volume — see Sharp edges for why legs 1–2 are unit-verified rather than driven.

## Steps
1. **Real count (live).** Seed a source folder with > 300 tiny valid image files
   in the VM (e.g. `for i in $(seq 1 400); do cp <one.jpg> "$SRC/img$i.jpg"; done`).
   Open the card/folder import via the typed-path route
   (`TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`), type `$SRC`. In the confirmation
   sheet assert the count reads the real number (e.g. "400 recognized photo
   files"), **no "+"**.
2. **Free-space preflight (unit-verified — see Sharp edges).** `IngestPreflightTests`
   proves a copy import whose source exceeds injected destination capacity throws
   a space error and copies zero files; ample capacity proceeds; add-in-place is
   never blocked.
3. **Watchdog heartbeat (unit-verified — see Sharp edges).** `ProgressCoalescerTests`
   proves progress emits on the 15s heartbeat between the 500-file marks;
   `WorkerSupervisorTests` proves periodic progress under 120s never trips the
   watchdog and true silence past it does.

## Expected
- Step 1: sheet shows the real count with no "+" suffix. **Fails if** it shows
  "300+" for a 400-file folder (the old cap regressed).
- Steps 2–3: the named tests pass. **Fails if** either regresses.

## Cleanup
```bash
script/vm_scenario_run.sh shell   # rm -rf "$SRC" "$RUN"
```

## Sharp edges
- **The watchdog misfire is not practically drivable live**: reproducing it
  needs a genuinely slow copy of > ~500 files taking > 120s (a slow card / large
  RAWs). The fix is proven at the unit level (coalescer heartbeat + supervisor
  timeout reset); a live large-corpus run would confirm end-to-end but isn't
  hermetic. Marked accordingly in the ledger.
- **The preflight needs a nearly-full destination volume** to trigger live;
  the injectable `availableCapacityForImportantUsage` closure covers it
  deterministically without a real full disk.
- Real photographer context that surfaced all three: an 864-file card import to
  a full boot volume timed out at 120s, then bricked the catalog with "unable to
  open database file" when the disk filled — this card guards against a repeat.
