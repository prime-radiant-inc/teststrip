# Preview Pipeline

Teststrip treats cached previews as catalog-adjacent working data. Originals remain external, and normal browsing should prefer cached previews over source-file reads.

## Durable Pending Work

Imports write catalog asset rows first, then record pending grid preview work in `preview_generation_queue` before rendering. A successful render deletes the matching queue row. A failed, cancelled, or interrupted render leaves the row pending so recovery can retry later.

The queue is keyed by `(asset_id, level)`, which keeps retries idempotent and prevents duplicate pending rows for the same cached preview.

## Import And Recovery

`LibraryImportService.addFolderInPlace` records `.grid` preview work for imported assets and renders those previews inline for the current import flow. `resumePendingPreviews(repository:)` drains the same queue for non-UI repair or maintenance paths.

The app does not synchronously render pending previews on launch. When `AppModel.load(catalog:workerSupervisor:)` sees pending previews and a worker supervisor is available, it enqueues bounded `.generatePreview` worker jobs through the same background work controls used by visible preview requests. This avoids UI-thread disk reads and avoids pulling originals from NAS or removable media during launch.

`WorkerCommandExecutor.execute(.generatePreview)` clears the queue row only after the preview file has been written successfully.

## Current Limits

The queue does not yet track attempt count, last error, source volume identity, or retry policy. Corrupt images may remain pending until a later failure policy is added. This is intentional for the first durable recovery slice; it preserves retryability for temporarily offline sources without adding scheduler policy too early.
