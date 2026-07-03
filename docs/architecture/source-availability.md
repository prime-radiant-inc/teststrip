# Source Availability

## Decision

Teststrip tracks source availability in the catalog separately from user metadata. Availability refreshes must not increment catalog metadata generations because they should not create false XMP conflicts.

Normal browsing reads catalog rows and cached previews. It must not probe original files or network volumes on the grid hot path.

## Current Behavior

- `SourceAvailabilityProbe` checks original file attributes and, for `/Volumes/<name>` paths, whether the source root is mounted.
- Matching size and modification date means `online`.
- Existing files with changed attributes are `stale`.
- Absent files are `missing`.
- Absent files under an unmounted `/Volumes/<name>` root are `offline`, which lets NAS/removable sources read as temporarily unavailable instead of truly missing.
- App code can refresh the selected asset or the loaded library window and keep cached grid/loupe previews usable.
- When the supervised worker is configured, loaded-window refreshes enqueue bounded, source-grouped `sourceScan` batches with progress instead of probing originals on the UI path or filling Activity with one row per visible asset. This keeps a large visible NAS/removable set from becoming one oversized worker command.
- Catalog load builds a Sources sidebar section for unavailable or questionable originals: offline, missing, moved, and stale. Selecting one of those rows applies the existing source availability filter, so offline/missing sets are reachable without scanning originals on the grid hot path.
- Imports record catalog source roots. Add-in-place records the imported folder; card imports record the destination library root.
- Source roots can be reconnected from the library toolbar by entering the old cataloged root and the new mounted root. The reconnect sheet pre-fills the old root from recorded catalog roots that have unavailable assets, falling back to the common folder of visible unavailable assets when root history is unavailable. Reconnect updates only assets whose same relative file exists under the new root and matches the catalog fingerprint. It marks those originals online, keeps metadata generation unchanged, records the new source root, refreshes sidebar/source summaries, moves XMP sync state to the new sidecar path, and resumes bounded pending preview generation for restored originals.

## Next Work

- Add configurable per-kind scheduling policy for large NAS/removable-volume scans.
