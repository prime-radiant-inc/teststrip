# Worker Management

## Decision

Teststrip models background work through a bounded queue before attaching real process execution. The queue is the source of truth for what may run, what is paused, and what can be cancelled.

The UI must not start unbounded detached work silently. Any long-running preview, XMP, source-scan, import, or recognition task should have a visible `BackgroundWorkItem` or import activity record.

## Current Behavior

- `BackgroundWorkQueue` enforces a maximum number of running items.
- Queued work stays queued until a running slot opens.
- Running work can be paused, resumed, or cancelled through app-model methods.
- The activity panel uses the app model's visible work projection so background queue state can be shown even when no import is active.
- Worker commands and JSON-lines protocol live in `TeststripCore` so the app and `TeststripWorker` share one process contract.
- `WorkerSupervisor` dispatches only runnable queue items to a `WorkerTransport`, launches the worker transport on demand, sends explicit pause/resume/cancel commands, and terminates the transport on cancel.
- `FoundationWorkerTransport` is the concrete local process adapter for launching a worker executable and writing commands to its standard input.

## Next Work

- Wire app-level preview/XMP/recognition requests through `WorkerSupervisor`.
- Persist queue state across app relaunches.
- Emit structured worker events for progress, completion, failure, and cancellation.
- Add per-kind throttles for NAS/source scans, preview rendering, XMP sync, and recognition.
