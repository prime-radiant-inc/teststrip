# Catalog And XMP Sync

## Decision

Teststrip treats the catalog as the operational source of truth. User metadata edits update the catalog first, then Teststrip mirrors portable metadata to an XMP sidecar when the original's directory is writable.

The default sidecar convention is collision-safe: append `.xmp` to the full original filename, such as `frame.cr2.xmp`. Teststrip also reads and updates an existing Adobe-style sidecar such as `frame.xmp` when no sibling `frame.*` original makes that basename ambiguous. Teststrip never modifies original image bytes as part of this writeback path.

## Current Behavior

- Supported portable fields are ratings, color labels, pick/reject flags, keywords, captions, creator, and copyright.
- Sidecars are RDF/XMP packets using Adobe-compatible properties where they exist: `xmp:Rating`, `xmp:Label`, `dc:subject`, `dc:description`, `dc:creator`, and `dc:rights`. Pick/reject uses Teststrip's namespace because there is no common XMP pick-flag property.
- When a sidecar already exists, writeback replaces only the Teststrip-managed portable fields and preserves unrelated XMP properties.
- When both `frame.cr2.xmp` and `frame.xmp` exist, Teststrip prefers `frame.cr2.xmp`. When an Adobe-style `frame.xmp` shares its basename with a RAW+JPEG or similar sibling pair, Teststrip reads `photoshop:SidecarForExtension`: if it case-insensitively names this original's extension the sidecar is treated as unambiguous and read/updated in place through the normal merge path. If it names a different extension, is absent, or the sidecar cannot be parsed, Teststrip ignores it and writes the collision-safe sidecar instead.
- Successful sidecar writes store the last written XMP fingerprint in the catalog.
- Failed sidecar writes do not roll back or block the catalog metadata edit.
- Failed sidecar writes are recorded as pending sync items with the asset ID, sidecar path, catalog generation, and last synced fingerprint if one exists.
- Worker-backed metadata edits record the pending sync item before enqueueing helper work, so a quit or crash after the catalog edit does not lose the required sidecar write.
- Pending worker-backed writes without a previous sidecar checkpoint stay catalog-first: if an existing sidecar is older than the pending catalog write, the worker writes catalog metadata to the sidecar; if the sidecar is newer than the pending row, the worker records an XMP conflict instead of importing or overwriting silently.
- `TeststripWorker` can execute `syncMetadata` for one asset: write missing/outdated sidecars from catalog metadata, import externally changed sidecars when the catalog generation is unchanged, and record conflicts when both catalog and sidecar changed.
- Selection-triggered XMP checks are coalesced: rapid browsing keeps the latest queued selected-asset check and does not let stale checks accumulate behind the worker. In-flight checks are allowed to finish so normal browsing does not restart the helper process.
- Pending sync items appear in the sidebar under `Sync` as `XMP Pending (n)`. Selecting that row applies a catalog-backed query so offline or read-only sidecar writeback gaps are findable at catalog scope.
- Launch-time pending sync retries are bounded and skip unavailable originals or unwritable sidecar folders. The pending rows remain visible so retryable writeback gaps do not flood the worker when a NAS, archive, or removable volume is offline.
- Recorded conflicts appear in the sidebar under `Sync` as `XMP Conflicts (n)`. Selecting that row applies a catalog-backed conflict query so photographers can find and resolve conflicted assets instead of discovering conflicts only one selected photo at a time.

## Next Work

- Add user-facing conflict resolution for ambiguous Adobe-style sidecars that carry no `photoshop:SidecarForExtension` binding if interoperability testing shows photographers need to bind such a `frame.xmp` to a specific original in RAW+JPEG pairs.
