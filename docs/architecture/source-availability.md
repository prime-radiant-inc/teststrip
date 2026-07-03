# Source Availability

## Decision

Teststrip tracks source availability in the catalog separately from user metadata. Availability refreshes must not increment catalog metadata generations because they should not create false XMP conflicts.

Normal browsing reads catalog rows and cached previews. It must not probe original files or network volumes on the grid hot path.

## Current Behavior

- `SourceAvailabilityProbe` checks file attributes only.
- Matching size and modification date means `online`.
- Existing files with changed attributes are `stale`.
- Absent files are `missing`.
- App code can refresh the selected asset or the loaded library window and keep cached grid/loupe previews usable.
- When the supervised worker is configured, loaded-window refreshes enqueue one managed batch `sourceScan` work item with progress instead of probing originals on the UI path or filling Activity with one row per visible asset.

## Next Work

- Add per-source throttling and cancellation policy for large NAS/removable-volume scans.
- Distinguish temporarily offline volumes from truly missing files where the platform gives enough evidence.
- Surface source-level summaries and reconnect actions without blocking catalog browsing.
