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
- `FoundationWorkerTransport` is the concrete local process adapter for launching a worker executable, writing commands to its standard input, and streaming standard-output response lines back to the supervisor.
- The packaged macOS app stages `TeststripWorker` as a signed helper at `Contents/Helpers/TeststripWorker`; app startup injects that helper URL into `AppCatalog.loadModel`.
- Explicit preview requests dispatch missing preview work through `WorkerSupervisor` and surface it through the app model's background queue projection.
- `TeststripWorker` opens the app catalog from `--catalog`, writes cached previews under `--preview-cache`, and executes `generatePreview` with `PreviewRenderer`.

## Next Work

- Move XMP sync and recognition requests through `WorkerSupervisor`.
- Persist queue state across app relaunches.
- Emit structured worker events for progress, failure, and cancellation.
- Add per-kind throttles for NAS/source scans, XMP sync, and recognition.
