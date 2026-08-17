# Import Selection Window & Queue Design

## Problem

Import is single-shot: the confirmation sheet shows counts only (no
thumbnails), you can't see which photos are duplicates before committing, and
you can't start a new import review while a previous import is running. The
user wants a visual selection window with thumbnails, duplicate filtering, and
the ability to queue multiple imports without waiting.

## Design

### Approach: Scan → Review → Ingest

The selection window opens before any catalog insertion. The user sees
thumbnails, filters duplicates, deselects unwanted photos, and commits. Only
selected files are ingested. Pre-rendered micro thumbnails are promoted into
the real preview cache so no work is wasted.

### 1. Pre-Ingest Thumbnail Pipeline

**Goal**: Generate 160px micro thumbnails for every candidate file as fast as
possible, before any catalog insertion.

**Mechanism**: A `PreIngestThumbnailRenderer` that wraps
`PreviewRenderer.render(sourceURL:level:destinationURL:)` targeting a temporary
cache directory. Source URL is the original file path — no asset ID needed.

**Speed**: ImageIO's `CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceCreateThumbnailFromImageAlways` +
`kCGImageSourceThumbnailMaxPixelSize: 160` pulls embedded JPEG previews from
RAWs without decoding full sensor data. For JPEGs, it downsamples efficiently.

**Concurrency**: `DispatchQueue.concurrentPerform` across files, capped at
`ProcessInfo.processInfo.activeProcessorCount`. For slow/removable volumes,
reduce concurrency to 2–4 to avoid seek thrashing.

**Additional ImageIO optimizations**:
- `kCGImageSourceShouldCache: false` — don't hold decoded image in memory
- `kCGImageSourceShouldCacheImmediately: false` — lazy decode

**Cache layout**: `temp/PreIngestThumbnails/<source-path-hash>.jpg` — keyed by
a hash of the source file path. Survives the review session, cleaned up on
import completion or app exit.

**Thumbnail availability**: Grid cells check if the temp thumbnail exists; if
not, show a placeholder. A background task pre-renders all thumbnails. Cells
re-evaluate on a timer (similar to existing `previewCacheGeneration` pattern).

**Thumbnail promotion on import**: When `IngestService.ingest` assigns an
asset ID and the pre-ingest thumbnail exists, move it to
`PreviewCache.url(for: PreviewCacheKey(assetID, .micro))` and call
`markPreviewGenerated(.micro)`. Post-ingest `enqueuePendingPreviewGeneration`
then sees micro is done and only queues grid/medium/large. Zero re-rendering of
micro previews after import. Deselected files' temp thumbnails are left behind
and cleaned up later.

### 2. Selection Window UI

**Layout**: Full-window SwiftUI view replacing the grid content area. Top bar
with source name, file count, and filter controls. Main area is a `LazyVGrid`
of square thumbnail cells.

**Grid cell**: Micro thumbnail (or placeholder while rendering). Checkmark
badge indicates selection state. Selected = visible checkmark; deselected =
dimmed, no checkmark. Click toggles selection.

**Filter bar**:
- "Show duplicates" toggle (default: off — duplicates hidden). When off,
  files already in catalog are hidden. When on, they show with an "Already in
  catalog" badge.
- Count summary: "2,310 photos · 1,890 selected · 418 already in catalog"

**Toolbar actions**:
- "Select All" / "Select None"
- "Import N Photos" (primary, orange, shows selected count)
- "Cancel" (dismisses, no import)

**Selection state**: `Set<URL>` of selected files, defaulting to all. The
"Import N Photos" button passes the selected file list to
`IngestService.ingest`.

**Entry point**: "Review & Select" button on the existing confirmation sheet.
Quick import (import everything) stays one click — the sheet's primary "Import
N Photos" button is unchanged.

### 3. Import Queue — Serial Ingest, Concurrent Review

**Decouple review from ingest**: The `isImporting` guard on import *entry
points* (folder/card pickers) is lifted. The selection window can open while a
previous import is ingesting. The `isImporting` guard stays only on the
*commit* (`beginImportFolder`/`beginImportCard`) — if an ingest is running, the
new import joins `pendingImportFolders` and runs when the current one finishes.

**Queue visibility**: The import progress card shows the current import. A
"Next: N folders queued" line appears when `pendingImportFolders` is non-empty.

**Selection during ingest**: The selection window operates on source files,
doesn't touch the catalog or worker, and is safe during ingest. The only
constraint: committing (hitting "Import N Photos") while another ingest is
running shows "Queued" and adds to `pendingImportFolders`.

**Cancel**: Cancelling the current ingest doesn't cancel queued imports. 
Cancelling a queued import (before it starts) removes it from
`pendingImportFolders`.

**No worker changes**: The worker still caps `.ingest` to 1 concurrent job.
The queue is entirely app-side.

### 4. Data Flow

```
1. User picks folder(s) or card
   → ImportSourceSummary.scan: count, size, photo file list
   → ImportDedupPreview.scan: hash sample, "N new · M in catalog"

2. Confirmation sheet appears (existing)
   → New "Review & Select" button

3. Selection window opens
   → PreIngestThumbnailRenderer starts background rendering of all micro previews
   → LazyVGrid displays thumbnails as they arrive
   → Duplicate filter uses ImportDedupPreview results

4. User adjusts selection (defaults to all)
   → Set<URL> of selected files

5. User hits "Import N Photos"
   → If !isImporting: begin import immediately
   → If isImporting: add to pendingImportFolders, button shows "Queued"
   → Passes selected file list to IngestService.ingest

6. IngestService.ingest (modified)
   → Receives optional selectedFiles: Set<URL>? — filters to only those files
   → For each file: assign AssetID → promote temp micro thumbnail to
     PreviewCache(assetID, .micro) → markPreviewGenerated(.micro)
   → Hash, copy (if card), fingerprint, catalog insert, bond, sidecar
   → Post-ingest: enqueuePendingPreviewGeneration skips micro (already done)

7. Cleanup: temp/PreIngestThumbnails purged for deselected files
```

### 5. Key Code Modifications

- `IngestService.ingest`: add `selectedFiles: Set<URL>?` parameter — if
  non-nil, filter scanner results to only those files. Add
  `preIngestThumbnailCache: PreIngestThumbnailCache?` — if non-nil, promote
  thumbnails during the serial loop after asset ID assignment.
- `ImportSourceSummary.scan`: expose the file list (or `ImportDedupPreview`
  results) to the selection window.
- `beginImportFolder`/`beginImportCard`: accept `selectedFiles: Set<URL>?`
  and pass through to the ingest task.
- `ImportConfirmationDraft`: gains `selectedFiles: Set<URL>?` (nil = import
  all, the default quick-import path).
- Import entry points: lift `isImporting` guard from pickers, keep on commit.

**No changes to**: worker protocol, preview generation queue, catalog schema,
sidecar sync, bonding, dedup logic, or the confirmation sheet's existing
options (destination, second copy, dated folders, import-new-only, evaluate,
autopilot).

### 6. Testing

- Unit tests for `PreIngestThumbnailRenderer` (renders to temp cache,
  promotion to PreviewCache, cleanup).
- Unit tests for `IngestService.ingest` with `selectedFiles` filter (only
  selected files ingested, deselected files skipped).
- Unit tests for thumbnail promotion (micro marked generated, not re-queued).
- Unit tests for queue behavior (can queue while importing, queued import
  runs after current, cancel current doesn't cancel queued).
- End-to-end scenario: pick folder → review & select → deselect some → import
  → verify only selected in catalog, micro previews promoted, deselected not
  present.
