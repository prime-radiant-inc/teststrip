# Catalog And XMP Sync

## Decision

Teststrip treats the catalog as the operational source of truth. User metadata edits update the catalog first, then Teststrip mirrors portable metadata to an XMP sidecar when the original's directory is writable.

The first implemented sidecar convention is collision-safe: append `.xmp` to the full original filename, such as `frame.cr2.xmp`. Teststrip never modifies original image bytes as part of this writeback path.

## Current Behavior

- Supported portable fields are ratings, color labels, pick/reject flags, keywords, captions, creator, and copyright.
- Sidecars are RDF/XMP packets using Adobe-compatible properties where they exist: `xmp:Rating`, `xmp:Label`, `dc:subject`, `dc:description`, `dc:creator`, and `dc:rights`. Pick/reject uses Teststrip's namespace because there is no common XMP pick-flag property.
- When a sidecar already exists, writeback replaces only the Teststrip-managed portable fields and preserves unrelated XMP properties.
- Successful sidecar writes store the last written XMP fingerprint in the catalog.
- Failed sidecar writes do not roll back or block the catalog metadata edit.
- Failed sidecar writes are recorded as pending sync items with the asset ID, sidecar path, catalog generation, and last synced fingerprint if one exists.
- `TeststripWorker` can execute `syncMetadata` for one asset: write missing/outdated sidecars from catalog metadata, import externally changed sidecars when the catalog generation is unchanged, and record conflicts when both catalog and sidecar changed.

## Next Work

- Surface conflicted XMP sync state in the UI.
- Revisit sidecar filename compatibility before shipping import/export interoperability guarantees.
