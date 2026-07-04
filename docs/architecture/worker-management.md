# Worker Management

## Decision

Teststrip models background work through a bounded queue and dispatches runnable work to a supervised helper process. The queue is the source of truth for what may run, what is paused, and what can be cancelled.

The UI must not start unbounded detached work silently. Any long-running preview, XMP, source-scan, import, or recognition task should have a visible `BackgroundWorkItem` or import activity record.

## Current Behavior

- `BackgroundWorkQueue` enforces a maximum number of running items.
- Queued work stays queued until a running slot opens.
- Queue dispatch can be paused and resumed through app-model methods. Already-dispatched work remains visibly running because the synchronous helper cannot stop mid-command; it can still be cancelled or timed out.
- The activity panel uses the app model's visible work projection so background queue state can be shown even when no import is active.
- Activity rows can cancel individual queued/running/paused background items. Cancelling queued work does not terminate the helper or cancel unrelated work; cancelling dispatched work uses `WorkerSupervisor.cancel(id:)`, sends the helper-wide cancel command required by the synchronous helper protocol, terminates the helper, and dispatches the next queued item.
- Worker commands and JSON-lines protocol live in `TeststripCore` so the app and `TeststripWorker` share one process contract.
- `WorkerSupervisor` dispatches only runnable queue items to a `WorkerTransport`, launches the worker transport on demand, maps completed worker output back to dispatched queue items, sends explicit pause/resume/cancel commands, and terminates the transport on cancel.
- The current helper executes commands synchronously, so `WorkerSupervisor` writes one work command to the helper at a time even when the visible queue allows more than one running item.
- `FoundationWorkerTransport` is the concrete local process adapter for launching a worker executable, writing commands to its standard input, and streaming standard-output and standard-error response lines back to the supervisor.
- The packaged macOS app stages `TeststripWorker` as a signed helper at `Contents/Helpers/TeststripWorker`; app startup injects that helper URL into `AppCatalog.loadModel`.
- Explicit preview requests dispatch missing preview work through `WorkerSupervisor` and surface it through the app model's background queue projection.
- Worker stderr marks the oldest dispatched work item failed and keeps the queue moving.
- Dispatched worker commands have a supervisor-level timeout. If a worker command stops responding, the supervisor terminates the helper process, fails the in-flight dispatched work with command-specific context, and relaunches the helper for queued work. Pausing background work gates future queue dispatch, but it does not mark already-sent commands as paused and does not disable their timeouts.
- `TeststripWorker` opens the app catalog from `--catalog`, writes cached previews under `--preview-cache`, executes `generatePreview` with `PreviewRenderer`, and executes `syncMetadata` through the catalog/XMP sync planner.
- Worker progress, completion, import-completion, and failure events are structured JSON-lines events with the originating work item ID.
- Visible source refreshes dispatch bounded, source-grouped `refreshAvailabilityBatch` worker commands so slow volume checks stay visible, cancellable, and smaller than one full loaded-window scan.
- Worker import work is persisted to `work_sessions` when it is queued/running. On the next catalog load, stale queued/running/paused ingest sessions are reconciled as failed with an interruption message instead of disappearing from Work history or falsely appearing active.
- Progress updates for already-persisted worker import sessions refresh the running `work_sessions` row, so interruption/reload history reflects the last observed import detail and counts instead of the original queued message.
- The app's managed worker queue caps source scans, XMP sync, and recognition to one running item per kind while still allowing unrelated runnable work to use remaining global queue capacity.

## Next Work

- Persist resumable command state across app relaunches for worker kinds that can be safely replayed.
