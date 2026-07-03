# Catalog And XMP Sync

## Decision

Teststrip treats the catalog as the operational source of truth. User metadata edits update the catalog first, then Teststrip mirrors portable metadata to an XMP sidecar when the original's directory is writable.

The default sidecar convention is collision-safe: append `.xmp` to the full original filename, such as `frame.cr2.xmp`. Teststrip also reads and updates an existing Adobe-style sidecar such as `frame.xmp` when no sibling `frame.*` original makes that basename ambiguous. Teststrip never modifies original image bytes as part of this writeback path.

## Current Behavior

- Supported portable fields are ratings, color labels, pick/reject flags, keywords, captions, creator, and copyright.
- Sidecars are RDF/XMP packets using Adobe-compatible properties where they exist: `xmp:Rating`, `xmp:Label`, `dc:subject`, `dc:description`, `dc:creator`, and `dc:rights`. Pick/reject uses Teststrip's namespace because there is no common XMP pick-flag property.
- When a sidecar already exists, writeback replaces only the Teststrip-managed portable fields and preserves unrelated XMP properties.
- When both `frame.cr2.xmp` and `frame.xmp` exist, Teststrip prefers `frame.cr2.xmp`. When an Adobe-style `frame.xmp` would be ambiguous because of a RAW+JPEG or similar sibling pair, Teststrip ignores it and writes the collision-safe sidecar instead.
- Successful sidecar writes store the last written XMP fingerprint in the catalog.
- Failed sidecar writes do not roll back or block the catalog metadata edit.
- Failed sidecar writes are recorded as pending sync items with the asset ID, sidecar path, catalog generation, and last synced fingerprint if one exists.
- Worker-backed metadata edits record the pending sync item before enqueueing helper work, so a quit or crash after the catalog edit does not lose the required sidecar write.
- `TeststripWorker` can execute `syncMetadata` for one asset: write missing/outdated sidecars from catalog metadata, import externally changed sidecars when the catalog generation is unchanged, and record conflicts when both catalog and sidecar changed.

## Next Work

- Add user-facing conflict resolution for ambiguous Adobe-style sidecars if import/export interoperability testing shows photographers need to bind `frame.xmp` to a specific original in RAW+JPEG pairs.
