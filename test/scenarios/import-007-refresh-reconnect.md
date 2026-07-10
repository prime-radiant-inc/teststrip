# import-007-refresh-reconnect: Refresh availability vs. Reconnect rewrite root+bookmark+previews

**What this covers**: inventory items 13-15 — the "Refresh source status"
worker-driven batch rescan and its two UI entry points; the Reconnect flow
that rewrites a source root's path, its security-scoped bookmark, and
re-enqueues preview generation for the affected assets; the specific
failure-message copy when reconnect targets a folder that doesn't actually
contain the expected files; and the structural distinction between a plain
availability-count row and a bookmark-repair row in the Activity popover's
Sources section.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
ORIGINALS="$ISOLATED/Teststrip/SmokeOriginals"
```
Baseline verified 2026-07-10 against a fresh `--smoke` seed: 24 assets, all
`availability='online'`, `source_roots` table empty (the smoke seeder writes
assets directly and never calls `recordSourceRoot`, so no bookmark-repair row
exists at seed time — this card must first arm one, see Step 1).

## Steps

### Part A — refresh is a worker batch job, triggered from two places
1. `script/ax_drive.sh wait-vended Teststrip`. Both refresh entry points call
   the same `AppModel.refreshVisibleAssetAvailability()`
   (`Sources/TeststripApp/AppModel.swift:8967-8980`):
   - the grid toolbar's `arrow.clockwise` button, AXHelp `"Refresh source
     status"` (`Sources/TeststripApp/LibraryGridView.swift:711-718`);
   - the Activity popover's per-source-row `arrow.clockwise` button, AXHelp
     `"Refresh source availability"` (`Sources/TeststripApp/ActivityCenterView.swift:244-251`),
     which only renders when a `SourceStatusRow.refreshActionID` is non-nil.
   Neither is automatic — there is no on-launch or filesystem-watch rescan
   (see `import-006-availability-badges.md`'s Sharp edges for the same
   finding). `ax_drive.sh find --role AXButton --help "Refresh source status"`
   to confirm presence.
2. With a `workerSupervisor` configured (always true for a normally launched
   app), the refresh path batches by `volumeIdentifier`
   (`sourceAvailabilityRefreshBatches`, `Sources/TeststripApp/AppModel.swift:9092-9112`)
   and enqueues `.sourceScan` work items running `.refreshAvailabilityBatch`
   (`Sources/TeststripApp/AppModel.swift:9063-9089`) — confirmed as a genuine
   out-of-process worker job, not an inline synchronous probe: the executor
   lives in `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:284-303`
   and runs under the worker process. Assert a `sourceScan` row appears:
   ```bash
   sqlite3 "$DB" "SELECT id, status FROM work_sessions WHERE kind='sourceScan' ORDER BY created_at DESC LIMIT 1;"
   ```

### Part B — reconnect rewrites path + bookmark + re-enqueues previews
3. Arm a bookmark-repair row: pick a source root and mark it needing repair.
   The reconnect sheet is driven from `reconnectActionID`, which is populated
   only for roots in `sourceRootBookmarkRepairPaths`
   (`Sources/TeststripApp/AppModel.swift:2500-2510`). Simulate a broken
   bookmark by moving the originals to a sibling directory (the fixture the
   Reconnect flow is meant to repair):
   ```bash
   NEWROOT="$ISOLATED/Teststrip/SmokeOriginalsRelocated"
   mv "$ORIGINALS" "$NEWROOT"
   ```
4. Open the Activity popover; assert a bookmark-repair row is structurally
   distinct from a plain availability-count row — **same `SourceStatusRow`
   type, but disjoint action fields**: a repair row has `reconnectActionID`
   set and `refreshActionID` nil (`Sources/TeststripApp/AppModel.swift:2503-2509`,
   icon `externaldrive.badge.exclamationmark`, AXHelp `"Reconnect
   <source name>"`), while a plain availability row has `refreshActionID` set
   and `reconnectActionID` nil (`Sources/TeststripApp/AppModel.swift:2492-2498`,
   icon `arrow.clockwise`, AXHelp `"Refresh source availability"`). Assert via
   AXHelp text and icon system-image name, not row position — both render in
   the same `sourcesSection` list (`Sources/TeststripApp/ActivityCenterView.swift:228-265`).
5. Click the reconnect (`externaldrive.badge.exclamationmark`) button; the
   `SourceReconnectSheet` opens with `Old root path` pre-filled
   (`Sources/TeststripApp/SourceReconnectSheet.swift:13-15`,
   `showSourceReconnectSheet` at `ActivityCenterView.swift:275-278`).
6. **Failure case first**: type a `New mounted root path` that doesn't
   contain the expected files (an empty directory):
   ```bash
   mkdir -p "$ISOLATED/Teststrip/EmptyDecoy"
   ```
   Fill `New mounted root path` = `$ISOLATED/Teststrip/EmptyDecoy`, click
   Reconnect. Assert the sheet's red error text is exactly the
   `scannedAssetCount == 0` branch OR (since assets *do* exist under the old
   root) the `missingFileCount == scannedAssetCount` branch of
   `sourceReconnectFailureMessage`
   (`Sources/TeststripApp/AppModel.swift:9008-9028`):
   > "No files were reconnected from EmptyDecoy. 24 catalog photos were found
   > under SmokeOriginals, but the matching files were missing under the new
   > root."
   (names are `url.lastPathComponent`, `Sources/TeststripApp/AppModel.swift:9031-9034`;
   singular/plural branches exist for 1-asset catalogs — this card's 24-asset
   smoke seed exercises the plural wording).
7. **Success case**: change `New mounted root path` to `$NEWROOT` (the real
   relocated directory from Step 3), click Reconnect.
8. Assert on catalog ground truth — root path, `original_path`, availability,
   and bookmark all rewritten together
   (`CatalogRepository.reconnectSourceRoot`, `Sources/TeststripCore/Catalog/CatalogRepository.swift:1635-1686`,
   plus `persistSecurityScopedBookmarkForSourceRoot` at
   `Sources/TeststripApp/AppModel.swift:8996,11217-11225`):
   ```bash
   sqlite3 "$DB" "SELECT original_path, availability FROM assets WHERE id='smoke-0';"
   sqlite3 "$DB" "SELECT path, security_scoped_bookmark_base64 IS NOT NULL FROM source_roots WHERE path LIKE '%SmokeOriginalsRelocated%';"
   ```
   Expect `original_path` to now point under `SmokeOriginalsRelocated`,
   `availability='online'`, and a non-null bookmark row for the new root.
9. Assert preview generation was re-enqueued for the reconnected assets —
   `reconnectSourceRoot` calls `enqueuePendingPreviewGeneration()`
   (`Sources/TeststripApp/AppModel.swift:9002`):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue;"
   ```

## Expected
- Step 2: a `sourceScan` `work_sessions` row appears and resolves to
  `completed`. **Fails if** no row appears — refresh silently no-ops instead
  of dispatching to the worker.
- Step 4: **fails if** a repair row and an availability row are
  indistinguishable in the AX tree (same help text/icon on both), or if a row
  somehow carries both `reconnectActionID` and `refreshActionID` non-nil
  (contradicts the source's two-family model at `AppModel.swift:2485-2488`).
- Step 6: **fails if** the shown message doesn't match the quoted copy
  (word-for-word, modulo the singular/plural branch) — a rewritten,
  paraphrased error string is not this app's actual copy.
- Step 8: **fails if** `original_path` is unchanged, `availability` is not
  `online`, or `source_roots` has no bookmark for the new root — a partial
  reconnect (path rewritten but bookmark stale, or vice versa) breaks the
  next relaunch's access.
- Step 9: **fails if** `preview_generation_queue` is empty post-reconnect for
  assets whose previews should be regenerated against the new path.

## Cleanup
```bash
rm -rf "$ISOLATED/Teststrip/EmptyDecoy"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **A bookmark-repair row never arises organically from `--smoke`.** The
  seeder never calls `recordSourceRoot`, so `sourceRootBookmarkRepairPaths` is
  always empty at seed time; this card's Step 3 fakes the broken-bookmark
  condition by relocating files, which produces a `missing`/`offline`
  availability row (see `import-006-availability-badges.md`), not
  automatically a `reconnectActionID` row — confirm during the live run
  whether `sourceRootBookmarkRepairPaths` actually gets populated by this
  fixture, or whether a real bookmark failure (e.g. revoking Full Disk Access
  mid-session) is the only way to arm it. If the fixture doesn't arm a repair
  row, this is a real fixture gap to report, not a card to quietly rewrite.
- The reconnect failure-message branches
  (`Sources/TeststripApp/AppModel.swift:9015-9028`) have three distinct
  wordings depending on `scannedAssetCount`/`missingFileCount`/`fingerprintMismatchCount`
  — don't assume Step 6's exact branch without checking which one the live
  smoke fixture actually hits (24 assets under the old root, so
  `scannedAssetCount == 24 != 0`, and an empty decoy directory makes every
  file "missing" under the new root — the `missingFileCount ==
  scannedAssetCount` branch should fire, but confirm live).

## Run status
SQL-GROUNDED, AX-UNRUN. Table/column names, the two refresh entry points, the
reconnect rewrite (`reconnectSourceRoot`), and the failure-message text were
all confirmed by reading source with file:line references above on
2026-07-10; the `source_roots` baseline (empty on `--smoke`) was confirmed
against a freshly seeded catalog the same day. The full click-through
(sheet-driven reconnect, popover row distinction, preview re-enqueue count)
needs a human-present or isolated-console re-run — not run live this session
due to concurrent-agent build contention on the shared `dist/Teststrip.app`.
Schema per `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (version 19).
