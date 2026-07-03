# Worker Management

## Decision

Teststrip models background work through a bounded queue and dispatches runnable work to a supervised helper process. The queue is the source of truth for what may run, what is paused, and what can be cancelled.

The UI must not start unbounded detached work silently. Any long-running preview, XMP, source-scan, import, or recognition task should have a visible `BackgroundWorkItem` or import activity record.

## Current Behavior

- `BackgroundWorkQueue` enforces a maximum number of running items.
- Queued work stays queued until a running slot opens.
- Running work can be paused, resumed, or cancelled through app-model methods.
- The activity panel uses the app model's visible work projection so background queue state can be shown even when no import is active.
- Worker commands and JSON-lines protocol live in `TeststripCore` so the app and `TeststripWorker` share one process contract.
- `WorkerSupervisor` dispatches only runnable queue items to a `WorkerTransport`, launches the worker transport on demand, maps completed worker output back to dispatched queue items, sends explicit pause/resume/cancel commands, and terminates the transport on cancel.
- The current helper executes commands synchronously, so `WorkerSupervisor` writes one work command to the helper at a time even when the visible queue allows more than one running item.
- `FoundationWorkerTransport` is the concrete local process adapter for launching a worker executable, writing commands to its standard input, and streaming standard-output and standard-error response lines back to the supervisor.
- The packaged macOS app stages `TeststripWorker` as a signed helper at `Contents/Helpers/TeststripWorker`; app startup injects that helper URL into `AppCatalog.loadModel`.
- Explicit preview requests dispatch missing preview work through `WorkerSupervisor` and surface it through the app model's background queue projection.
- Worker stderr marks the oldest dispatched work item failed and keeps the queue moving.
- Dispatched worker commands have a supervisor-level timeout. If a worker command stops responding, the supervisor terminates the helper process, fails the in-flight dispatched work with command-specific context, and relaunches the helper for queued work. Pausing background work gates queue dispatch, but it does not disable timeouts for commands already sent to the synchronous helper.
- `TeststripWorker` opens the app catalog from `--catalog`, writes cached previews under `--preview-cache`, executes `generatePreview` with `PreviewRenderer`, and executes `syncMetadata` through the catalog/XMP sync planner.
- Visible source refreshes dispatch one `refreshAvailabilityBatch` worker command so slow volume checks remain a single visible, cancellable `sourceScan` item with progress.

## Next Work

- Persist queue state across app relaunches.
- Emit structured worker events for progress and cancellation.
- Add per-kind throttles for NAS/source scans, XMP sync, and recognition.
