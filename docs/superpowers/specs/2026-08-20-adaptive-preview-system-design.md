# Adaptive Preview System Redesign

## Problem

Before this redesign, the preview system generated 5 separate JPEG files per
asset — micro (160px), grid (512px), medium (1600px), large (3200px), and
original (full-res) — each produced by a separate read of the original from
SMB. For a 130k-photo library that's mostly RAW, that meant up to 5 SMB reads
per asset, JPEG files that were 3–5x larger than necessary, and no quality
control on the JPEG encoder (ImageIO's default ~0.8 quality).

## Solution

Replace 5 physical JPEG files with 3 physical HEIC files, deriving 2
additional logical levels in memory. Generate all physical files from a single
local copy of the original, eliminating redundant SMB reads. Delete all
existing JPEG previews — no coexistence, no fallback.

## Codec: HEIC

Empirically validated against 5 diverse RAW samples (10MP–102MP, Canon/Fuji/
DNG, 2007–2025). HEIC at q=0.25 full-res is visually indistinguishable from
JPEG at q=0.40, at roughly 1/5 the file size. Both JPEG and HEIC carry
embedded ICC profiles; the color space depends on ImageIO's RAW decoder, not
the output codec. The full-res HEIC is an evaluation preview, not an archival
copy — the original RAW remains the source of truth.

Quality settings (from visual comparison):

| Physical file | Pixel dim | HEIC quality |
|---------------|-----------|-------------|
| grid.heic     | 512px     | 0.82        |
| large.heic    | 3200px    | 0.40        |
| full.heic     | original  | 0.25        |

`full.heic` is the display target for 1:1 zoom. The original RAW may never be
loaded directly for display — it remains the source of truth for export, but
the preview system is the display surface.

## Architecture

### Physical files → logical levels

```
grid.heic  (512px, q=0.82)   →  .micro  (160px, derived in memory)
                              →  .grid   (512px, as-is)

large.heic (3200px, q=0.40)  →  .medium (1600px, derived in memory)
                              →  .large  (3200px, as-is)

full.heic  (original, q=0.25) →  .original (as-is)
```

`PreviewLevel` enum stays unchanged (micro, grid, medium, large, original) —
it remains the API the UI and scheduler use. The mapping from logical level
to physical file is internal to `PreviewCache` and `PreviewRenderer`.

### Write path: copy-once, batch generation

Previously: each level called `renderer.render(sourceURL: asset.originalURL,
...)` separately — N levels = N reads of the original from SMB.

New: copy the original to a local temp file once, generate all needed levels
from that temp, delete the temp. One SMB read regardless of how many levels.

```
Import:  copy original → temp → render grid.heic → delete temp
Worker:  copy original → temp → render large.heic + full.heic → delete temp
```

The worker generates large.heic and full.heic as a batch — one copy, two
renders, one cleanup. This requires a new batch command
(`generatePreviews(assetID, levels: [PreviewLevel])`) so the worker copies
the original once and renders all queued levels from the same temp file before
deleting it. The current single-level `generatePreview(assetID, level)` command
is replaced by this batch command.

Import generates only grid.heic (micro is derived). The pre-ingest thumbnail
cache (used for import-time display before previews exist) is not promoted to
the permanent cache — the worker generates grid.heic fresh from the original.

### Queue consistency: mark derived levels together

When a physical file is generated, all logical levels it serves are marked
generated:

- `grid.heic` generated → mark `.grid` AND `.micro` as generated
- `large.heic` generated → mark `.large` AND `.medium` as generated
- `full.heic` generated → mark `.original` as generated

This prevents the queue from re-requesting derived levels that have no
physical file of their own.

### Read path: local disk, no change

All previews are already served from local disk
(`~/Library/Application Support/Teststrip/Previews/`). HEIC decode is
hardware-accelerated on Apple Silicon and universally supported on macOS 14+.

For derived levels (micro from grid, medium from large), the loader uses
`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`
to downsample in memory. This is a minor optimization — the source files are
already small — but it reduces memory bandwidth when scrolling thousands of
thumbnails.

## Components changed

### PreviewCache (`Sources/TeststripCore/Preview/PreviewCache.swift`)

New method: `physicalFile(for: PreviewLevel) -> String` maps a logical level to
its physical file name (`url(for:)` combines it with the per-asset directory):

```swift
private static func physicalFile(for level: PreviewLevel) -> String {
    switch level {
    case .micro, .grid:    return "grid.heic"
    case .medium, .large:  return "large.heic"
    case .original:        return "full.heic"
    }
}
```

`url(for:)` returns the physical file URL (always `.heic`). No `.jpg` fallback.
Callers that need the logical level's pixel dimensions get them from
`PreviewLevel.maxPixelDimension`.

### PreviewRenderer (`Sources/TeststripCore/Preview/PreviewRenderer.swift`)

Two changes:

1. **HEIC output + quality control.** `render()` creates the
   `CGImageDestination` with `UTType("public.heic")` instead of `.jpeg`, and
   passes `kCGImageDestinationLossyCompressionQuality` in the properties
   dictionary. The quality value comes from a new per-level mapping:

   ```swift
   private static func compressionQuality(for level: PreviewLevel) -> Double {
       switch level {
       case .micro, .grid:   return 0.82
       case .medium, .large: return 0.40
       case .original:       return 0.25
       }
   }
   ```

2. **Batch render from local source.** New method that generates multiple
   physical files from a single local source URL (the temp copy):

   ```swift
   func renderLevels(
       fromLocalSource sourceURL: URL,
       levels: [PreviewLevel],
       destinationProvider: (PreviewLevel) -> URL
   ) throws
   ```

   Each level is still decoded via `CGImageSourceCreateThumbnailAtIndex` from
   the local file (which is fast — no network), but all levels share one SMB
   read. The caller is responsible for copying the original to temp and
   cleaning up. `renderLevels` deduplicates levels that map to the same
   physical file (e.g. passing `[.micro, .grid]` generates `grid.heic` once).

### PreviewImageDataLoader (`Sources/TeststripApp/CachedPreviewImage.swift`)

New `loadImage(from:maxPixelDimension:rotation:)` variant that uses
`CGImageSourceCreateThumbnailAtIndex` with a max pixel size when the requested
logical level is smaller than the physical file. For example, loading `.micro`
(160px) from `grid.heic` (512px) downsamples to 160px in memory.

When the requested level matches the physical file's native resolution (e.g.
`.grid` from `grid.heic`), the existing `Data(contentsOf:)` path is used as-is.

### AppModel.previewURL(for:levels:) (`Sources/TeststripApp/AppModel.swift`)

Maps each logical level to its physical file via `PreviewCache`. Since all
files are `.heic`, there is no fallback logic. De-duplicates physical file
checks (micro + grid → same file, only stat once).

### WorkerCommand: batch generatePreviews (`Sources/TeststripCore/Worker/WorkerCommand.swift` + `WorkerCommandExecutor.swift`)

Replace the single-level `generatePreview(assetID, level)` command with a
batch `generatePreviews(assetID, levels: [PreviewLevel])` command. The executor:

1. Copies the original to a local temp file (one SMB read).
2. Calls `renderer.renderLevels(fromLocalSource:levels:)` for all requested
   levels.
3. Marks all logical levels served by the generated physical files as
   generated (e.g. generating grid.heic marks both `.grid` and `.micro`).
4. Deletes the temp file.

### LibraryImportService (`Sources/TeststripCore/Ingest/LibraryImportService.swift`)

`importPreviewLevels` changes from `[.micro, .grid]` to `[.grid]` (micro is
derived). The pre-ingest thumbnail cache promotion path (which promoted a
JPEG temp to the `.micro` preview slot) is removed — the worker generates
grid.heic fresh from the original. The import preview generation uses the
copy-once path. After generating grid.heic, mark both `.grid` and `.micro` as
generated.

### PreviewScheduler (`Sources/TeststripCore/Preview/PreviewScheduler.swift`)

No change. The scheduler still maps UI context to logical `PreviewLevel` and
priority. The physical file mapping is transparent.

### CatalogMigrations (`Sources/TeststripCore/Catalog/CatalogMigrations.swift`)

No schema change. `preview_generation_queue` tracks `(asset_id, level)` where
`level` is the logical level — this stays the same. When a physical file is
generated, all logical levels it serves are marked generated in the queue.

## Migration

Delete all existing JPEG preview files. No coexistence, no fallback. The
first launch after deploy regenerates all previews as HEIC from the originals.
The `preview_generation_queue` is reset so all levels are re-queued for
generation.

This is a one-time cost: the worker re-generates all 3 physical files per
asset. For a 130k-photo library, this runs in the background over time as the
worker processes the queue.

## Testing

- Unit tests for `PreviewCache.physicalFile(for:)` mapping.
- Unit tests for `PreviewRenderer` outputting HEIC at the correct quality.
- Unit test verifying batch `renderLevels` generates all physical files from
  a single source read (use a test file, count source accesses).
- Unit test verifying that generating `grid.heic` marks both `.grid` and
  `.micro` as generated in the queue.
- Unit test verifying `generatePreviews` batch command copies the original
  once and renders all levels.
- Verify HEIC files are readable by `PreviewImageDataLoader`.
- All existing tests pass with the new file mapping.
