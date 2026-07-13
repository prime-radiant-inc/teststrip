# Concurrent per-lane worker execution + per-kind Activity progress

_Date: 2026-07-13_

## Problem

On import, background work runs through a single `BackgroundWorkQueue`
(`maxRunningCount: 2`) dispatched to one worker process that executes commands
**one at a time, synchronously, on `@MainActor`**. Preview generation and AI
evaluation are already distinct `WorkSessionKind`s (`.previewGeneration` and
`.recognition`), but they share that one FIFO lane and pool of running slots, so
they compete: a backlog of evaluations delays the previews a user needs to start
culling. The Activity Center compounds it by rendering **one row per work item**,
producing the "96 more queued" pile-up in the screenshot that started this work.

We want two things:

1. **One lane per task type**, executing **concurrently**, so previews render
   while evaluations run (and neither blocks the other).
2. **One aggregate progress bar per active work type** in the Activity Center,
   replacing the per-item rows.

## Decisions (settled during brainstorming)

- **Single worker process, concurrent lanes.** Keep one `TeststripWorker`
  process. Run at most one command **per lane** concurrently on separate tasks,
  serializing catalog access through the worker's single connection. This gets
  real compute overlap (decode/render ‖ ML inference) with a single catalog
  writer *by construction* — and **no protocol/persistence inversion**. We
  explicitly rejected "app is sole writer" (would invert persistence for all ~8
  worker commands, including the just-hardened ingest path) and "N separate
  worker processes" (cross-process SQLite write contention; the catalog is not
  in WAL mode). Crash isolation between lanes is given up; the supervisor's
  existing timeout-and-relaunch recovery is the backstop.
- **A progress bar per active work kind**, aggregating that kind's items. Import
  is **folded in** as just another kind row (no separate import treatment).
- **Provider-serial fallback is acceptable.** If an evaluation provider
  (Vision / Core Image / Core ML) proves unsafe to run concurrently, that lane
  stays internally serial while still running concurrently with *other* lanes.

## Goals

- Preview and evaluation lanes make progress at the same wall-clock time during
  import.
- The Activity Center shows one bar per active kind with correct aggregate
  progress and per-kind pause/cancel.
- No regression to catalog integrity: concurrent lanes never corrupt or
  half-write catalog state.
- The confirm-before-write and non-destructive invariants are preserved.

## Non-goals

- No multiple worker processes / worker pool.
- No "app is sole writer" persistence inversion.
- No WAL migration of the catalog (single-process writer makes it unnecessary).
- No new task types; we parallelize the lanes that already exist.
- Not a throughput-tuning exercise. Land concurrency, verify overlap, stop
  (per the project's perf-restraint guidance).

## Architecture

### Lane model

A **lane** is a `WorkSessionKind`. The worker-dispatched kinds and their
commands:

| Lane (`WorkSessionKind`) | Worker command(s) | Display title |
| --- | --- | --- |
| `.ingest` | `importFolder`, `importCard` | Import photos |
| `.previewGeneration` | `generatePreview` | Generate previews |
| `.recognition` | `runEvaluation` | Evaluate photos |
| `.xmpSync` | `syncMetadata` | Sync sidecars |
| `.sourceScan` | `refreshAvailability`, `refreshAvailabilityBatch` | Check sources |
| `.geocoding` | `reverseGeocodeBatch` | Find places |
| `.locationBackfill` | `backfillCoordinates` | Backfill locations |

Concurrency policy: **at most one running item per lane; all lanes may run
concurrently.** This is expressible with the queue we already have:

- Set `kindRunningLimits` to `1` for every worker-dispatched kind.
- Raise `maxRunningCount` from `2` to the lane count (so the global cap no longer
  gates lane concurrency).

`BackgroundWorkQueue.activateRunnableItems()` already fills running slots up to
`maxRunningCount` while respecting `canRun()`'s per-kind limit, so it will mark
one item per lane running with no change to the queue's selection logic. The
change lives in the **supervisor**, which must now dispatch those multiple
running items concurrently rather than one at a time.

### Concurrent worker (`TeststripWorker` / `WorkerCommandExecutor`)

Today the worker main loop is:

```
while let line = readLine() {           // blocks
    let event = try execute(command)    // runs to completion on @MainActor
    write(event)
}
```

New shape:

- **Read loop never blocks on execution.** It reads a command line and hands the
  command to a per-lane dispatcher, then immediately reads the next line. Reading
  runs on its own thread so it continues while commands execute.
- **Per-lane execution tasks.** Each command runs on its own task, at most one
  per lane in flight. Heavy compute (image decode/render in `PreviewRenderer`,
  and the evaluation providers) runs off any single serialized actor so lanes
  overlap.
- **Serialized catalog access.** All `CatalogDatabase` calls funnel through one
  serialization point (a serial queue owning the handle, or SQLite
  serialized-mode). Each command's write sequence is wrapped in a **transaction**
  so a concurrent lane cannot interleave between a command's writes. Compute
  happens outside the DB critical section, so serializing DB access does not
  serialize the expensive work.
- **Events already carry `itemID`.** `progress`, `completed`, `completedImport`,
  and `failed` are emitted per command with the originating item ID; no protocol
  change is needed to route them.
- **Per-item cancel.** A new per-item cancel path cancels only the targeted
  lane's in-flight task (cooperative cancellation), leaving other lanes running.
  This replaces relying on process termination for routine cancellation.

Thread-safety of the providers is verified during implementation. Any provider
that is not concurrency-safe runs behind a per-lane serialization guard (the
accepted fallback) — it still overlaps other lanes.

### Multiplexed transport + supervisor

- **`FoundationWorkerTransport`** becomes a multiplexed stream: one stdin writer,
  one stdout reader that demuxes event lines by `itemID` to the registered
  in-flight command handlers, instead of the current one-command-at-a-time
  request/response.
- **`WorkerSupervisor`** dispatches every runnable queue item concurrently (one
  per lane), tracks in-flight commands by `itemID`, and when a lane's command
  reaches a terminal event dispatches that lane's next queued item. Timeouts
  become **per-lane**: a stalled lane fails its in-flight command with
  command-specific context.
- **Cancel semantics.** `cancel(id:)` sends a per-item cancel and marks just that
  item cancelled; sibling lanes are unaffected. The helper-wide terminate +
  relaunch remains the **last-resort** recovery for a wedged lane past its
  timeout (it fails all in-flight commands with context — the same behavior as
  today, now rare instead of routine).

### Per-kind aggregate Activity UI

- A new projection groups the visible work items by `WorkSessionKind` into one
  **`ActivityKindRow`** per active kind, carrying: the display title from the
  table above, aggregate progress (items completed / items total for the kind),
  a representative running detail (e.g. the current provider or "Rendering micro
  preview"), a rolled-up status, and per-kind pause/cancel/star availability.
- This **replaces** `ActivityCenterPresentation.jobs: [ActivityJobRow]` per-item
  rows. The dedicated `ImportProgressRow` is **removed**; `.ingest` renders as an
  ordinary kind row.
- Per-kind pause/cancel act on every active item of that kind (fan-out over the
  kind's item IDs through existing queue/supervisor calls).

## Data flow (import example)

1. Card import enqueues an `.ingest` item; supervisor dispatches `importCard`.
2. As assets are cataloged, `.previewGeneration` and `.recognition` items are
   enqueued. The supervisor dispatches the preview command **and** an evaluation
   command concurrently — different lanes, both running.
3. The worker renders a preview on one task while an evaluation provider runs on
   another; each writes its results inside a transaction through the single
   serialized connection.
4. Progress events stream back tagged by `itemID`; the transport demuxes them;
   the supervisor updates the queue; the Activity projection rolls per-kind items
   into "Generate previews" and "Evaluate photos" bars, both advancing.

## Error handling

- **Per-lane failure**: a failed command marks its item failed and frees that
  lane; other lanes continue. The supervisor dispatches the lane's next item.
- **Per-lane timeout**: the in-flight command is failed with command context; if
  the worker is wedged, terminate + relaunch (last resort) and re-dispatch queued
  work.
- **Transactionality**: each command's catalog writes are atomic, so a
  failure/cancel mid-command leaves no half-written state for a concurrent lane
  to observe.

  > **Implementation note**: blanket per-command transaction wrapping was
  > dropped during implementation — wrapping an entire command in one
  > transaction would starve other lanes (and serialize import) for the
  > command's full duration. Instead, each *repository method* is
  > individually atomic (e.g. `recordEvaluationSignals`,
  > `replaceFaceObservations` each wrap their own writes), and
  > `CatalogDatabase`'s lock prevents corruption from concurrent access. The
  > only non-atomic grouping is *across* repository calls within one command
  > (e.g. `runEvaluation`'s signals-then-faces sequence). That's harmless: the
  > intermediate state is provisional and self-healing on retry, not a
  > correctness hazard for concurrent lanes.

## Testing

TDD throughout; every user-facing surface gets an automated end-to-end scenario.

- **Unit — queue**: with per-kind limit 1 and raised `maxRunningCount`,
  `activateRunnableItems()` marks exactly one item per lane running across
  multiple lanes simultaneously; one lane completing promotes that lane's next
  item without disturbing others.
- **Unit — supervisor**: two in-flight commands on different lanes; events
  demuxed by `itemID`; a lane's completion dispatches its next item; a per-item
  cancel leaves sibling lanes running; per-lane timeout fails only its command.
- **Unit — worker**: two commands on different lanes overlap in execution;
  catalog writes remain transactional and correct under concurrency.
- **Unit — UI projection**: items group into per-kind rows with correct
  aggregate counts, titles, status roll-up, and control availability; import
  appears as a kind row.
- **Headless verifier**: extend the import/preview/eval headless gate to assert
  preview and evaluation work **overlap in wall-clock time** and land the correct
  `previews` / `evaluation_signals` rows.
- **E2E scenario card (VM)**: import a card, open the Activity Center, assert the
  per-kind bars appear (Generate previews + Evaluate photos) and **both advance**;
  verify catalog ground truth (cached previews + `evaluation_signals`); re-assert
  **confirm-before-write** — nothing in `people` / `person_assets` and no asset
  metadata written without an explicit gesture.

## Risks and open items

- **Provider concurrency**: verify Vision / Core Image / Core ML providers run
  safely concurrently; fall back to per-lane serialization where not (accepted).
- **Transaction granularity**: confirm each worker command's writes are wrapped
  so concurrent lanes can't observe a partial command; add wrapping where a
  command currently writes in multiple un-batched steps (e.g. `syncMetadata`).
- **`.recognition` label** (resolved): the `.recognition` kind is constructed in
  exactly one place — the "Evaluate photo" enqueue in `AppModel`. Face
  detection/embedding rides inside `runEvaluation` (provider `core-image-faces`);
  people-clustering is app-side, not a worker lane. So the lane is unambiguously
  evaluation and "Evaluate photos" is correct.
- **Pause/resume across lanes**: per-kind pause must gate future dispatch for
  that kind only, consistent with the existing queue pause semantics.

## Out of scope

- Worker pool / multiple processes; app-sole-writer; WAL migration; new task
  types; throughput tuning beyond demonstrating overlap.
