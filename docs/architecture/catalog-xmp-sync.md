# Catalog And XMP Sync

## Decision

Teststrip treats the catalog as the operational source of truth. User metadata edits update the catalog first, then Teststrip mirrors portable metadata to an XMP sidecar when the original's directory is writable.

The first implemented sidecar convention is collision-safe: append `.xmp` to the full original filename, such as `frame.cr2.xmp`. Teststrip never modifies original image bytes as part of this writeback path.

## Current Behavior

- Supported portable fields are ratings, color labels, pick/reject flags, keywords, captions, creator, and copyright.
- Successful sidecar writes store the last written XMP fingerprint in the catalog.
- Failed sidecar writes do not roll back or block the catalog metadata edit.
- Failed sidecar writes are recorded as pending sync items with the asset ID, sidecar path, catalog generation, and last synced fingerprint if one exists.

## Next Work

- Read newer external sidecars into the catalog when there are no unsynced local edits.
- Detect conflicts using stored fingerprints and catalog generations, not mtime alone.
- Surface pending/conflicted XMP sync state in the UI and worker queue.
- Revisit sidecar filename compatibility before shipping import/export interoperability guarantees.
