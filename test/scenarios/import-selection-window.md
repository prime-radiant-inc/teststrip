# import-selection-window: Scan → Review → Select → Ingest with thumbnail promotion

**What this covers**: the full import selection window feature (Tasks 1-9) —
the end-to-end flow from folder scan through the Review & Select thumbnail grid
to final ingest. The selection window (`ImportSelectionView`) shows pre-ingest
thumbnails rendered by `PreIngestThumbnailRenderer` into a
`PreIngestThumbnailCache` temp directory. The user filters (All/New/Duplicates),
deselects individual photos, and confirms a subset. The selected files are
threaded back to the confirmation draft via
`ImportSheetState.confirmingSelection` (`LibraryGridView.swift:21-30`), then
through `LibraryImportService.addFolderInPlace` where the `selectedFiles`
filter limits ingest (`LibraryImportService.swift:226-228`) and
`preIngestThumbnailCache.promote(from:to:)` copies temp micro thumbnails to the
permanent `PreviewCache` (`LibraryImportService.swift:388-406`) — skipping
preview generation for those assets.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

Record the baseline asset count (smoke seeder creates 24 assets,
`Sources/TeststripBench/SmokeCatalogSeeder.swift:91-99`):
```bash
BASELINE=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
# Expect 24
```

Create a fixture folder with 24 new JPEGs — re-encoded from the smoke originals
at 70% quality so the content hashes differ (no duplicates). The smoke
originals at `$ISOLATED/Teststrip/SmokeOriginals/smoke-N.jpg` are already
cataloged, so importing that directory directly would show all 24 as
already-in-catalog:
```bash
FIXTURE=$(mktemp -d)/selection
mkdir -p "$FIXTURE"
for n in $(seq 0 23); do
  sips -s format jpeg -s formatOptions 70 \
    "$ISOLATED/Teststrip/SmokeOriginals/smoke-$n.jpg" \
    --out "$FIXTURE/photo-$((n+1)).jpg" >/dev/null 2>&1
done
ls "$FIXTURE" | wc -l   # expect 24
```

## Steps

### 1. Open import folder picker
Drive the typed-path import route (no native NSOpenPanel needed; the isolated
launch exposes it per `LibraryGridChromePolicy.shouldExposeImportPathControl`,
`LibraryGridView.swift:8684`):
```bash
script/ax_drive.sh wait-vended Teststrip
script/ax_drive.sh press --role AXButton --label "Import Path"
script/ax_drive.sh type --contains "Folder path" --text "$FIXTURE"
script/ax_drive.sh press --role AXButton --label "Review Import"
```
The primary button label "Review Import" comes from
`ImportFolderPathDraft.primaryActionTitle`
(`ImportFolderPathDraft.swift:130-131`). Clicking it scans the folder and opens
the confirmation sheet.

Wait for the confirmation sheet:
```bash
script/ax_drive.sh wait --role AXButton --contains "Review & Select"
```
The confirmation sheet appears with a "Review & Select…" button
(`LibraryGridView.swift:1820`) and a primary "Import 24 Photos" button
(`ImportConfirmationDraft.primaryActionTitle`,
`ImportConfirmationDraft.swift:493-513`).

### 2. Open Review & Select
```bash
script/ax_drive.sh press --role AXButton --contains "Review & Select"
```
This calls `startImportSelection` (`LibraryGridView.swift:1920`) which creates a
`PreIngestThumbnailCache`, builds `ImportSelectionData` from the scan results,
sets `importSheet = .selection(data)`, and kicks off background thumbnail
rendering (`PreIngestThumbnailRenderer.renderBatch`) and dedup scanning.

Wait for the selection window to populate:
```bash
script/ax_drive.sh wait --role AXButton --contains "Import"  # primary button in footer
```

Verify the selection window:
- Filter bar shows segmented picker: "All" | "New" | "Duplicates"
  (`ImportSelectionView.swift:115-118`, `Picker` with `.segmentedControl` style)
- Grid shows 24 thumbnail cells (`LazyVGrid` with `ThumbnailCell`,
  `ImportSelectionView.swift:120-140`)
- Footer shows "24 of 24 selected" (`ImportSelectionView.swift:127`:
  `"\(model.selectedCount) of \(model.entries.count) selected"`)

```bash
script/ax_drive.sh find --role AXButton --contains "Import"
# Should find the "Import 24 Photos" primary button
script/ax_drive.sh find --role AXStaticText --contains "of 24 selected"
# Should find the "24 of 24 selected" footer text
```

### 3. Filter to New only
```bash
script/ax_drive.sh press --role AXRadioButton --label "New"
```
Grid shows only non-duplicate photos. In this fixture all 24 are new (re-encoded
with different content hashes), so the "New" filter shows 24. The "New" filter
excludes entries whose URLs are in `duplicateURLs`
(`ImportSelectionModel.filteredEntries`, `ImportSelectionView.swift`).

```bash
script/ax_drive.sh press --role AXRadioButton --label "All"
```
Returns to full view (24 cells).

### 4. Deselect a photo
Click a thumbnail cell to toggle its selection. `ThumbnailCell`
(`ImportSelectionView.swift:161-210`) is a `Button` with
`.buttonStyle(.plain)` — see Sharp edges for AX matching:
```bash
# Discover thumbnail cell labels at runtime:
script/ax_drive.sh find --role AXButton
# Press the first thumbnail cell (match by discovered label or coordinate)
```

After deselecting one:
- Footer updates: "23 of 24 selected"
  (`model.selectedCount` decrements via `toggleSelection`)
- Primary button updates: "Import 23 Photos"
  (`ImportSelectionView.swift:149`: `Button("Import \(model.selectedCount) Photos")`)

```bash
script/ax_drive.sh find --role AXStaticText --contains "23 of 24 selected"
script/ax_drive.sh find --role AXButton --contains "Import 23 Photos"
```

### 5. Confirm import with selection
Click "Import 23 Photos" in the selection window:
```bash
script/ax_drive.sh press --role AXButton --contains "Import 23 Photos"
```
This calls `ImportSheetState.confirmingSelection` (`LibraryGridView.swift:21-30`)
which transitions back to `.confirmation` with `draft.selectedFiles` set to the
23 selected URLs and `draft.preIngestThumbnailCache` set to the temp cache.

Verify the confirmation sheet's primary button now reads "Import 23 Photos"
(reflecting the selected count via `primaryActionTitle` when `selectedFiles`
is set, `ImportConfirmationDraft.swift:493-513`):
```bash
script/ax_drive.sh wait --role AXButton --contains "Import 23 Photos"
```

Click "Import 23 Photos" to start the import:
```bash
script/ax_drive.sh press --role AXButton --contains "Import 23 Photos"
```
This calls `confirmImport` (`LibraryGridView.swift:2859`) → `importFolders`
(`LibraryGridView.swift:2920`) → `model.beginImportFolders` with
`selectedFiles` and `preIngestThumbnailCache` parameters.

Wait for the import to complete (poll until the Import button re-enables):
```bash
script/ax_drive.sh wait --role AXButton --label "Import"
```

### 6. Verify catalog ground truth
```bash
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
NEW=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE original_path LIKE '$FIXTURE/%';")
echo "Total: $TOTAL (expect $((BASELINE + 23)))"
echo "New:   $NEW   (expect 23)"
```

**Fails if** `NEW != 23` — one file was deselected, so only 23 should be
cataloged. If `NEW == 24`, the `selectedFiles` filter was not applied
(`LibraryImportService.swift:226-228`). If `NEW == 0`, the import didn't
process the fixture.

Verify no micro preview generation is pending for the imported assets
(thumbnails were promoted from the temp cache, so the worker should not need
to regenerate them):
```bash
PENDING_NEW=$(sqlite3 "$DB" "
  SELECT count(*) FROM preview_generation_queue q
  WHERE q.level = 'micro'
  AND q.asset_id IN (
    SELECT id FROM assets WHERE original_path LIKE '$FIXTURE/%'
  );")
echo "Pending micro (new): $PENDING_NEW  (expect 0)"
```

**Fails if** `PENDING_NEW > 0` — micro thumbnails were not promoted from the
`PreIngestThumbnailCache` temp directory to the permanent `PreviewCache`
(`LibraryImportService.swift:388-406`). The `preview_generation_queue` schema
is at `CatalogMigrations.swift:41-49` (PK `asset_id, level`).

### 7. Verify thumbnail promotion
Check that micro.jpg files exist in the permanent PreviewCache for the
imported assets (`PreviewCache.url(for:)` returns
`root/<encoded-asset-id>/micro.jpg`, `PreviewCache.swift`):
```bash
find "$ISOLATED/Teststrip/Previews" -name "micro.jpg" -type f | wc -l
# Should be at least BASELINE + 23 = 47 (smoke-seeded + promoted)
```

**Fails if** no micro.jpg files are found for the fixture assets — thumbnails
were not promoted from the temp cache.

Verify the temp cache directory was cleaned up:
```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "teststrip-pre-ingest-*" -type d 2>/dev/null
# Should return nothing — PreIngestThumbnailCache.cleanup() should have removed it
```

## Expected
- Step 6: `TOTAL == BASELINE + 23` and `NEW == 23`. **Fails if** `NEW == 24`
  (selectedFiles filter not applied) or `NEW == 0` (import didn't process
  fixture).
- Step 6 (preview queue): `PENDING_NEW == 0`. **Fails if** micro previews are
  queued for the 23 new assets — thumbnails were not promoted from the temp
  cache (`LibraryImportService.swift:388-406`).
- Step 7: micro.jpg files exist in `Previews/` for the 23 new assets.
  **Fails if** no micro.jpg files are found for the fixture assets.
- Step 7 (temp cleanup): no `teststrip-pre-ingest-*` directories remain.
  **Fails if** the temp directory persists — `PreIngestThumbnailCache.cleanup()`
  (`PreIngestThumbnailCache.swift:58`) was not called after import.

## Cleanup
```bash
rm -rf "$FIXTURE"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

Verify no temp thumbnail directories remain:
```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "teststrip-pre-ingest-*" -type d 2>/dev/null
```

## Sharp edges
- **Re-encoded fixture JPEGs.** The fixture uses `sips -s formatOptions 70` to
  re-encode smoke originals at 70% quality, producing different bytes and
  content hashes. Do not use `cp`/`copyItem` — the copies would be
  byte-identical and show as duplicates in the selection window's "Duplicates"
  filter.
- **Filter bar is a segmented Picker.** The All/New/Duplicates filter is a
  SwiftUI `Picker` with `.segmentedControl` style. In AX, segments appear as
  `AXRadioButton` elements. Use
  `ax_drive.sh press --role AXRadioButton --label "New"`.
- **primaryActionTitle reflects selection.** After confirming the selection,
  the confirmation sheet's primary button reads "Import 23 Photos" (not the
  original "Import 24 Photos") because `ImportConfirmationDraft.primaryActionTitle`
  uses `selectedCount` when `selectedFiles` is set
  (`ImportConfirmationDraft.swift:493-513`).
- **Cannot use submit_import_path.sh.** `script/submit_import_path.sh` drives
  Import Path → Review Import → primary "Import N Photos" button. It does not
  stop at the confirmation sheet to click "Review & Select…". Drive the flow
  manually with `ax_drive.sh` commands as described in Steps 1-5.

## Run status
Needs a fresh VM run. Source-confirmed the wiring: `startImportSelection`
creates a `PreIngestThumbnailCache` and renders thumbnails in the background
(`LibraryGridView.swift:1920-1950`); `confirmingSelection` threads
`selectedFiles` and the thumbnail cache back to the confirmation draft
(`LibraryGridView.swift:21-30`); `LibraryImportService.addFolderInPlace` filters
to `selectedFiles` (`LibraryImportService.swift:226-228`) and promotes temp
micro thumbnails to the permanent `PreviewCache`
(`LibraryImportService.swift:388-406`). The catalog SQL queries and
`preview_generation_queue` schema were verified against
`CatalogMigrations.swift:41-49`. `PreIngestThumbnailCache.cleanup()` is wired
into all import completion paths: non-worker folder import (`defer` in
`beginImportFolder`'s Task, guarded by `pendingImportFolders.isEmpty`), non-worker
card import (`defer` in `beginImportCard`'s Task), and worker imports (stored in
`WorkerImportContext`, cleaned up in `handleWorkerImportCompleted` and
`releaseInactiveWorkerImportContexts` when no pending folders or active worker
contexts remain). `ThumbnailCell` carries
`.accessibilityLabel(entry.url.lastPathComponent)` for per-cell AX driving.
