# Preview Pipeline

Teststrip treats cached previews as catalog-adjacent working data. Originals remain external, and normal browsing should prefer cached previews over source-file reads.

Grid display prefers cached grid previews and falls back to micro previews while grid preview work catches up. Loupe/compare display prefers large, then medium, then grid, then micro previews before reporting that no cached preview is available.

Full original access is explicit. The loupe can reveal an online/stale original in Finder, but normal grid, loupe, compare, and preview recovery paths do not load or cache `PreviewLevel.original`. This keeps large RAW/original reads out of ordinary browsing and culling.

## Durable Pending Work

Imports write catalog asset rows first, then record pending micro and grid preview work in `preview_generation_queue` before rendering. Demand-driven grid, medium, and large preview requests also record pending work before dispatching to the worker. A successful render deletes the matching queue row. A failed, cancelled, or interrupted render leaves the row pending so recovery can retry later.

The queue is keyed by `(asset_id, level)`, which keeps retries idempotent and prevents duplicate pending rows for the same cached preview. Queue rows track attempt count, last error text, and last attempted time so the UI can expose retry state without dropping the pending work.

## Import And Recovery

`LibraryImportService.addFolderInPlace` records `.micro` and `.grid` preview work for imported assets and renders those previews inline for the current import flow. Medium and large previews stay demand-driven until the UI needs them. `resumePendingPreviews(repository:)` drains the same queue for non-UI repair or maintenance paths.

The app does not synchronously render pending previews on launch. When `AppModel.load(catalog:workerSupervisor:)` sees pending previews and a worker supervisor is available, it enqueues bounded `.generatePreview` worker jobs through the same background work controls used by visible preview requests. Automatic recovery skips originals the catalog currently marks offline, missing, or moved, so launch does not pull unavailable NAS/removable sources into worker reads.

Automatic launch-time recovery skips preview rows after three failed render attempts. The queue row remains visible in preview failure state, so corrupt files do not churn the worker on every launch and an explicit user retry can still be added without losing diagnostic context.

`WorkerCommandExecutor.execute(.generatePreview)` clears the queue row only after the preview file has been written successfully.

## Current Limits

The queue does not yet track source volume identity or source-specific backoff. Temporarily offline NAS or removable sources still share the same retry counter as corrupt files; a later scheduler policy should distinguish transient source unavailability from permanently unreadable media.
