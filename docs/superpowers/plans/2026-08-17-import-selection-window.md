# Import Selection Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Jesse review thumbnails and pick which photos to import (with duplicate filtering), queue multiple imports concurrently, and promote pre-rendered thumbnails into the permanent cache so nothing is rendered twice.

**Architecture:** A new `PreIngestThumbnailCache` + `PreIngestThumbnailRenderer` (TeststripCore) render tiny JPEGs into a temp directory before any ingest. `ImportSourceSummary.scan` and `ImportDedupPreview.scan` expose their per-file results so a new `ImportSelectionView` (TeststripApp) can show a lazy grid with duplicate badges. `LibraryImportService` gains `selectedFiles: Set<URL>?` (filters before calling `IngestService.ingest`, which already accepts a `files:` parameter — no `IngestService` change) and `preIngestThumbnailCache: PreIngestThumbnailCache?` (promotes temp thumbnails during preview generation instead of re-rendering). `WorkerCommand` carries `selectedFiles` and the temp cache directory through the protocol so the worker path also filters and promotes. `AppModel` lifts `isImporting` from the folder/card pickers (keep it on the confirm button) and threads the new parameters through factory closures.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, ImageIO (CGImageSource/CGImageDestination), SQLite (CatalogRepository), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-17-import-selection-window-design.md`

---

## Global Constraints

- **Non-destructive.** Original image bytes are never modified. Thumbnails are JPEGs rendered by ImageIO into a temp directory; promotion copies the JPEG to the PreviewCache location — originals stay in place.
- **Auto-apply with provenance.** No metadata changes in this plan. Import remains non-destructive and in-place.
- **TDD throughout.** Write the failing test, watch it fail for the right reason, then implement.
- **Smallest reasonable change.** Match the style and formatting of surrounding code.
- **Tests assert against catalog/sidecar ground truth**, not just view state.
- **Never `git add -A`.** Run `git status` first; stage only the files the task names.
- **Green-after-every-commit.** Every commit leaves `swift build` clean and `swift test` at 0 failures.
- **Factory test updates are mechanical.** When the factory typealiases gain parameters, every test factory closure gets `_, _, ` added for the two new params. Do not skip any — the build will fail on any missed closure.
- **No `IngestService` changes.** The existing `files: [URL]` parameter on `IngestService.ingest` is the subset-ingest seam. `LibraryImportService` filters before calling it.
- **Headless gate is `make verify`.** Run it before the final commit of the branch.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift` | Temp-directory thumbnail cache keyed by source file path; promote-to-PreviewCache method |
| `Sources/TeststripCore/Preview/PreIngestThumbnailRenderer.swift` | Concurrent thumbnail rendering using `PreviewRenderer`, writing into `PreIngestThumbnailCache` |
| `Sources/TeststripApp/ImportSelectionView.swift` | SwiftUI selection window: lazy thumbnail grid, filter bar, select all/none, duplicate badges |
| `Tests/TeststripCoreTests/PreIngestThumbnailCacheTests.swift` | Unit tests for temp cache: store, exists, promote, cleanup |
| `Tests/TeststripCoreTests/PreIngestThumbnailRendererTests.swift` | Unit tests for concurrent rendering: renders to cache, skips existing, handles errors |
| `Tests/TeststripAppTests/ImportSelectionViewTests.swift` | Unit tests for selection model: filter logic, select all/none, duplicate status |
| `test/scenarios/import-selection-window.md` | End-to-end scenario card |

### Modified files

| File | Changes |
|---|---|
| `Sources/TeststripCore/Preview/PreviewRenderer.swift` | Add `kCGImageSourceShouldCache: false` to thumbnail options (memory optimization) |
| `Sources/TeststripCore/Ingest/LibraryImportService.swift` | `addFolderInPlace`/`copyFromCard`/`importAssets` gain `selectedFiles: Set<URL>?` and `preIngestThumbnailCache: PreIngestThumbnailCache?`; filter source files before `ingest`; promote temp thumbnails in `generatePreviews` |
| `Sources/TeststripCore/Worker/WorkerCommand.swift` | `.importFolder` and `.importCard` gain `selectedFiles: Set<URL>?` and `preIngestThumbnails: URL?`; update `operationDescription` and `silenceTimeout` pattern matches |
| `Sources/TeststripCore/Worker/WorkerProtocol.swift` | `WorkerCommandEnvelope` gains `selectedFiles: [String]?` and `preIngestThumbnails: String?`; update `encode`/`decodeRequest` |
| `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` | Pass `selectedFiles` and `PreIngestThumbnailCache` to `importService.addFolderInPlace`/`copyFromCard` |
| `Sources/TeststripApp/ImportConfirmationDraft.swift` | `ImportSourceSummary.scan` gains `fileURLs: [URL]`; `ImportDedupPreview.scan` gains `duplicateURLs: Set<URL>`; `ImportConfirmationDraft` gains `selectedFiles: Set<URL>?` |
| `Sources/TeststripApp/AppModel.swift` | `beginImportFolder`/`beginImportCard`/`beginImportFolders` gain `selectedFiles`/`preIngestThumbnailCache`; factory typealiases gain 2 params; `defaultImportTask`/`defaultCardImportTask` pass through; `enqueueWorkerImport` passes to worker command; add `scanDedupPreview` async helper |
| `Sources/TeststripApp/LibraryGridView.swift` | "Review & Select" button on confirmation sheet; present selection sheet; wire `selectedFiles` back to draft; lift `isImporting` from import buttons; add pending-queue count to import progress |
| `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift` | New test cases for `fileURLs`, `duplicateURLs`, `selectedFiles` |
| `Tests/TeststripCoreTests/FolderImportTests.swift` | New test cases for `selectedFiles` filter and thumbnail promotion |
| `Tests/TeststripWorkerTests/WorkerProtocolTests.swift` | New test cases for `selectedFiles`/`preIngestThumbnails` serialization round-trip |
| `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift` | New test cases for `selectedFiles` passthrough |
| `Tests/TeststripAppTests/AppModelTests.swift` | New test cases for `selectedFiles` passthrough; update all 21 factory closures |

---

## Frozen facts (verified at plan time)

### FF1 — IngestService.ingest already accepts a `files:` parameter

`IngestService.ingest(files:plan:repository:...)` at `IngestService.swift:88` receives `files sourceFiles: [URL]`. The caller (`LibraryImportService.importAssets` at `:269`) passes the scanned file list. Filtering this list before the call is the subset-ingest seam — no `IngestService` change needed.

### FF2 — LibraryImportService.generatePreviews is the promotion point

`generatePreviews` at `LibraryImportService.swift:357` iterates `previewItems`, renders each via `renderer.render(sourceURL:level:destinationURL:)`, then calls `repository.markPreviewGenerated(assetID:level:)`. Promotion inserts a check before the render: if the temp cache has a thumbnail for the asset's `originalURL` and the level is `.micro`, copy it to the PreviewCache location and call `markPreviewGenerated` instead of rendering.

### FF3 — WorkerCommand has 6 pattern-match sites for import cases

| File | Line | Pattern |
|---|---|---|
| `WorkerCommand.swift` | ~54 | `case .importFolder(let root, _):` (silenceTimeout) |
| `WorkerCommand.swift` | ~56 | `case .importCard(let source, let destinationRoot, _, _, _):` (silenceTimeout) |
| `WorkerProtocol.swift` | ~59 | `case .importFolder(let root, let duplicateHandling):` (encode) |
| `WorkerProtocol.swift` | ~71 | `case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination, let duplicateHandling):` (encode) |
| `WorkerCommandExecutor.swift` | ~174 | `case .importFolder(let root, let duplicateHandling):` (execute) |
| `WorkerCommandExecutor.swift` | ~190 | `case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination, let duplicateHandling):` (execute) |

Each needs `let selectedFiles, let preIngestThumbnails` (or `_` for silenceTimeout) added.

### FF4 — Factory typealiases and test factory closures

| Typealias | Current params | New params |
|---|---|---|
| `AppImportTaskFactory` | `paths, folderURL, duplicateHandling, progress` (4) | `paths, folderURL, duplicateHandling, selectedFiles, preIngestThumbnailCache, progress` (6) |
| `AppCardImportTaskFactory` | `paths, source, destinationRoot, destinationPolicy, secondCopyDestination, duplicateHandling, progress` (7) | `+ selectedFiles, preIngestThumbnailCache` (9) |

21 test factory closures need `_, _, ` added (2 new params each). The closures that use real `defaultImportTask` need to pass the new params through.

### FF5 — ImportSourceSummary.scan enumerates with limits

`ImportSourceSummary.scan` at `ImportConfirmationDraft.swift:55` enumerates files with `defaultScanLimit = 100_000`, `defaultScanBudget = 2.0s`. To collect `fileURLs`, add a `var fileURLs: [URL] = []` accumulator inside the loop. The selection window calls `scan` with `limit: Int.max, budget: .greatestFiniteMagnitude` to get all files.

### FF6 — ImportDedupPreview.scan checks path + hash

`ImportDedupPreview.scan` at `ImportConfirmationDraft.swift:202` checks path matches (`repository.asset(originalURL:)`) then content hashes. To expose `duplicateURLs: Set<URL>`, collect the URLs of path-matched files and hash-matched files into a set. The selection window uses this set for the duplicate filter.

### FF7 — SheetScaffold has fixed width, no secondary button

`SheetScaffold` at `SheetScaffold.swift:31` has Cancel + Primary in the footer, no secondary button. The "Review & Select" button goes in the content VStack (above the Options disclosure). The selection view is presented as a separate `.sheet` via a state enum that replaces the confirmation sheet while the selection is active.

---

## Task 1: PreIngestThumbnailCache

**Files:**
- Create: `Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift`
- Test: `Tests/TeststripCoreTests/PreIngestThumbnailCacheTests.swift`

**Interfaces:**
- Produces: `PreIngestThumbnailCache` struct (Sendable) with `init(directoryURL: URL? = nil)`, `thumbnailExists(for sourceURL: URL) -> Bool`, `storeThumbnail(_ data: Data, for sourceURL: URL) throws`, `promote(from sourceURL: URL, to destinationURL: URL) throws`, `cleanup()`, `directoryURL: URL`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/TeststripCoreTests/PreIngestThumbnailCacheTests.swift
import XCTest
@testable import TeststripCore

final class PreIngestThumbnailCacheTests: XCTestCase {
    func testStoreAndCheckExistence() throws {
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let sourceURL = URL(fileURLWithPath: "/tmp/test/photo.jpg")
        let thumbnailData = Data([0xFF, 0xD8, 0xFF]) // JPEG magic bytes
        
        XCTAssertFalse(cache.thumbnailExists(for: sourceURL))
        try cache.storeThumbnail(thumbnailData, for: sourceURL)
        XCTAssertTrue(cache.thumbnailExists(for: sourceURL))
        cache.cleanup()
    }
    
    func testPromoteCopiesToDestination() throws {
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let sourceURL = URL(fileURLWithPath: "/tmp/test/photo.jpg")
        let thumbnailData = Data([0xFF, 0xD8, 0xFF])
        try cache.storeThumbnail(thumbnailData, for: sourceURL)
        
        let destDir = makeTempDir()
        let destURL = destDir.appendingPathComponent("micro.jpg")
        try cache.promote(from: sourceURL, to: destURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        let promoted = try Data(contentsOf: destURL)
        XCTAssertEqual(promoted, thumbnailData)
        cache.cleanup()
    }
    
    func testPromoteNoopWhenThumbnailMissing() throws {
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let destURL = makeTempDir().appendingPathComponent("micro.jpg")
        try cache.promote(from: URL(fileURLWithPath: "/nonexistent.jpg"), to: destURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destURL.path))
        cache.cleanup()
    }
    
    func testCleanupRemovesDirectory() throws {
        let dir = makeTempDir()
        let cache = PreIngestThumbnailCache(directoryURL: dir)
        try cache.storeThumbnail(Data([0xFF]), for: URL(fileURLWithPath: "/tmp/x.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        cache.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
    
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PreIngestThumbnailCacheTests`
Expected: FAIL — "cannot find 'PreIngestThumbnailCache' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift
import Foundation

/// Temporary thumbnail cache for pre-ingest selection review.
/// Keyed by source file path; stores JPEGs in a temp directory.
/// After import, thumbnails can be promoted to the permanent
/// PreviewCache, avoiding re-rendering.
public struct PreIngestThumbnailCache: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("teststrip-pre-ingest-\(UUID().uuidString)")
        }
        try? FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    private func thumbnailURL(for sourceURL: URL) -> URL {
        let safeName = sourceURL.path.replacingOccurrences(of: "/", with: "_")
        return directoryURL.appendingPathComponent(safeName + ".jpg")
    }

    public func thumbnailExists(for sourceURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: thumbnailURL(for: sourceURL).path)
    }

    public func storeThumbnail(_ data: Data, for sourceURL: URL) throws {
        try data.write(to: thumbnailURL(for: sourceURL))
    }

    /// Copy a temp thumbnail to a permanent PreviewCache location.
    /// No-op when no temp thumbnail exists for the source URL.
    public func promote(from sourceURL: URL, to destinationURL: URL) throws {
        let src = thumbnailURL(for: sourceURL)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        try? FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: src, to: destinationURL)
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PreIngestThumbnailCacheTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift Tests/TeststripCoreTests/PreIngestThumbnailCacheTests.swift
git commit -m "feat: add PreIngestThumbnailCache for pre-ingest thumbnail storage"
```

---

## Task 2: PreIngestThumbnailRenderer + ImageIO optimization

**Files:**
- Create: `Sources/TeststripCore/Preview/PreIngestThumbnailRenderer.swift`
- Modify: `Sources/TeststripCore/Preview/PreviewRenderer.swift:24-30` (add `kCGImageSourceShouldCache: false`)
- Test: `Tests/TeststripCoreTests/PreIngestThumbnailRendererTests.swift`

**Interfaces:**
- Consumes: `PreIngestThumbnailCache` (from Task 1), `PreviewRenderer` (existing), `PreviewLevel` (existing)
- Produces: `PreIngestThumbnailRenderer` struct (Sendable) with `init(renderer: PreviewRenderer = PreviewRenderer())`, `render(sourceURL: URL, cache: PreIngestThumbnailCache) throws`, `renderBatch(_ sourceURLs: [URL], cache: PreIngestThumbnailCache, concurrency: Int = 4)`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/TeststripCoreTests/PreIngestThumbnailRendererTests.swift
import XCTest
@testable import TeststripCore

final class PreIngestThumbnailRendererTests: XCTestCase {
    func testRenderCreatesThumbnailInCache() throws {
        let sourceURL = try writeTestJPEG()
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        XCTAssertFalse(cache.thumbnailExists(for: sourceURL))
        try renderer.render(sourceURL: sourceURL, cache: cache)
        XCTAssertTrue(cache.thumbnailExists(for: sourceURL))
        cache.cleanup()
    }

    func testRenderSkipsWhenThumbnailExists() throws {
        let sourceURL = try writeTestJPEG()
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        try renderer.render(sourceURL: sourceURL, cache: cache)
        let firstSize = try FileManager.default.attributesOfItem(
            at: cache.thumbnailURL(for: sourceURL)
        )[.size] as? Int ?? 0

        // Render again — should skip (thumbnail already exists)
        try renderer.render(sourceURL: sourceURL, cache: cache)
        let secondSize = try FileManager.default.attributesOfItem(
            at: cache.thumbnailURL(for: sourceURL)
        )[.size] as? Int ?? 0

        XCTAssertEqual(firstSize, secondSize)
        cache.cleanup()
    }

    func testRenderBatchConcurrent() throws {
        let urls = try (0..<8).map { _ in writeTestJPEG() }
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        try renderer.renderBatch(urls, cache: cache, concurrency: 4)

        for url in urls {
            XCTAssertTrue(cache.thumbnailExists(for: url), "missing thumbnail for \(url.path)")
        }
        cache.cleanup()
    }

    private func writeTestJPEG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jpg")
        // 4x4 red JPEG
        let cgImage = createTestCGImage(width: 4, height: 4)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    private func createTestCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("renderer-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PreIngestThumbnailRendererTests`
Expected: FAIL — "cannot find 'PreIngestThumbnailRenderer' in scope"

- [ ] **Step 3: Add kCGImageSourceShouldCache to PreviewRenderer**

In `Sources/TeststripCore/Preview/PreviewRenderer.swift`, add `kCGImageSourceShouldCache: false` to the thumbnail options dictionary. This prevents ImageIO from caching the full decoded image in memory — we only need the thumbnail JPEG on disk.

```swift
// Modify the options dictionary in render(sourceURL:level:destinationURL:)
var options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCache: false
]
```

- [ ] **Step 4: Write PreIngestThumbnailRenderer implementation**

```swift
// Sources/TeststripCore/Preview/PreIngestThumbnailRenderer.swift
import Foundation

/// Renders micro-level thumbnails into a PreIngestThumbnailCache for
/// the import selection window. Skips files that already have a cached
/// thumbnail. Uses concurrent rendering for batch operations.
public struct PreIngestThumbnailRenderer: Sendable {
    private let renderer: PreviewRenderer

    public init(renderer: PreviewRenderer = PreviewRenderer()) {
        self.renderer = renderer
    }

    /// Render a single thumbnail into the cache. Skips if already cached.
    public func render(sourceURL: URL, cache: PreIngestThumbnailCache) throws {
        guard !cache.thumbnailExists(for: sourceURL) else { return }
        let tempURL = cache.directoryURL
            .appendingPathComponent("rendering-\(UUID().uuidString).jpg")
        try renderer.render(sourceURL: sourceURL, level: .micro, destinationURL: tempURL)
        let finalURL = cache.thumbnailURL(for: sourceURL)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
    }

    /// Render thumbnails for multiple source files concurrently.
    /// Skips files that already have a cached thumbnail.
    public func renderBatch(
        _ sourceURLs: [URL],
        cache: PreIngestThumbnailCache,
        concurrency: Int = 4
    ) throws {
        let toRender = sourceURLs.filter { !cache.thumbnailExists(for: $0) }
        guard !toRender.isEmpty else { return }

        var renderErrors: [Error] = []
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: toRender.count) { index in
            let url = toRender[index]
            do {
                try render(sourceURL: url, cache: cache)
            } catch {
                lock.lock()
                renderErrors.append(error)
                lock.unlock()
            }
        }

        if let firstError = renderErrors.first {
            throw firstError
        }
    }
}
```

Note: `thumbnailURL(for:)` is currently `private` on `PreIngestThumbnailCache`. Change it to `public` (or `internal`) so `PreIngestThumbnailRenderer` can call it. Add `public` to the method in `PreIngestThumbnailCache.swift`:
```swift
public func thumbnailURL(for sourceURL: URL) -> URL {
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter PreIngestThumbnailRendererTests`
Expected: PASS (3 tests)

- [ ] **Step 6: Run full test suite to verify no regressions**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Preview/PreIngestThumbnailRenderer.swift \
  Sources/TeststripCore/Preview/PreviewRenderer.swift \
  Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift \
  Tests/TeststripCoreTests/PreIngestThumbnailRendererTests.swift
git commit -m "feat: add PreIngestThumbnailRenderer with concurrent rendering + ImageIO cache optimization"
```

---

## Task 3: Expose file list and per-file duplicate status

**Files:**
- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift` (ImportSourceSummary.scan, ImportDedupPreview.scan)
- Test: `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`

**Interfaces:**
- Produces: `ImportSourceSummary.fileURLs: [URL]` — all scanned photo file URLs (within scan limits)
- Produces: `ImportDedupPreview.duplicateURLs: Set<URL>` — URLs of files already in the catalog (path match or content hash match)

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`:

```swift
func testSourceSummaryFileURLsCollected() throws {
    let dir = makeTemporaryDirectory()
    let photo1 = dir.appendingPathComponent("a.jpg")
    let photo2 = dir.appendingPathComponent("b.jpg")
    try writeTestPNG(at: photo1)
    try writeTestPNG(at: photo2)
    // Non-photo file should not appear
    try "text".write(to: dir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

    let summary = ImportSourceSummary.scan(sourceURL: dir, supportedExtensions: ["jpg", "png"])
    XCTAssertEqual(summary.photoCount, 2)
    XCTAssertEqual(summary.fileURLs.count, 2)
    let paths = Set(summary.fileURLs.map(\.path))
    XCTAssertTrue(paths.contains(photo1.path))
    XCTAssertTrue(paths.contains(photo2.path))
}

func testDedupPreviewDuplicateURLsExposed() throws {
    let dir = makeTemporaryDirectory()
    let photo = dir.appendingPathComponent("dup.jpg")
    try writeTestPNG(at: photo)

    let repo = makeRepository(in: makeTemporaryDirectory())
    // Import the photo so it's in the catalog
    let asset = Asset(
        id: .new(), originalURL: photo,
        importedAt: Date(), catalogedAt: Date(),
        fileKind: .image
    )
    try repo.upsert(asset)

    let dedup = ImportDedupPreview.scan(
        sourceURL: dir,
        supportedExtensions: ["jpg", "png"],
        repository: repo
    )
    XCTAssertNotNil(dedup)
    XCTAssertTrue(dedup?.duplicateURLs.contains(photo) ?? false)
    XCTAssertEqual(dedup?.existingContentCount, 1)
}
```

Use the existing `makeTemporaryDirectory` and `writeTestPNG` helpers from the test file. Add `makeRepository` if not already present (follow the pattern from `FolderImportTests.swift`):
```swift
private func makeRepository(in dir: URL) -> CatalogRepository {
    let db = try! CatalogDatabase.open(at: dir.appendingPathComponent("catalog.sqlite"))
    try! db.migrate()
    return CatalogRepository(database: db)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImportConfirmationDraftTests`
Expected: FAIL — "value of type 'ImportSourceSummary' has no member 'fileURLs'" / "value of type 'ImportDedupPreview' has no member 'duplicateURLs'"

- [ ] **Step 3: Add fileURLs to ImportSourceSummary**

In `Sources/TeststripApp/ImportConfirmationDraft.swift`:

1. Add `var fileURLs: [URL]` to the `ImportSourceSummary` struct (after `blocksImport: Bool`):
```swift
var fileURLs: [URL]
```

2. In `scan(sourceURL:...)`, add a `var fileURLs: [URL] = []` accumulator before the loop. Inside the loop, after `byteCount += Int64(values?.fileSize ?? 0)`, add:
```swift
fileURLs.append(fileURL)
```

3. In the return statement, add `fileURLs: fileURLs`:
```swift
return ImportSourceSummary(
    sourceURL: sourceURL,
    photoCount: photoCount,
    byteCount: byteCount,
    reachedLimit: reachedLimit,
    reachedEntryLimit: reachedEntryLimit,
    scannedEntryCount: scannedEntryCount,
    unavailableReason: nil,
    blocksImport: false,
    fileURLs: fileURLs
)
```

4. In `unavailableSummary`, add `fileURLs: []`:
```swift
private static func unavailableSummary(sourceURL: URL, reason: String, blocksImport: Bool) -> ImportSourceSummary {
    ImportSourceSummary(
        sourceURL: sourceURL,
        photoCount: 0,
        byteCount: 0,
        reachedLimit: false,
        reachedEntryLimit: false,
        scannedEntryCount: 0,
        unavailableReason: reason,
        blocksImport: blocksImport,
        fileURLs: []
    )
}
```

5. In `merging(_:)`, add `fileURLs: fileURLs + other.fileURLs`:
```swift
func merging(_ other: ImportSourceSummary) -> ImportSourceSummary {
    ImportSourceSummary(
        sourceURL: sourceURL,
        photoCount: photoCount + other.photoCount,
        byteCount: byteCount + other.byteCount,
        reachedLimit: reachedLimit || other.reachedLimit,
        reachedEntryLimit: reachedEntryLimit || other.reachedEntryLimit,
        scannedEntryCount: scannedEntryCount + other.scannedEntryCount,
        unavailableReason: unavailableReason ?? other.unavailableReason,
        blocksImport: blocksImport || other.blocksImport,
        fileURLs: fileURLs + other.fileURLs
    )
}
```

- [ ] **Step 4: Add duplicateURLs to ImportDedupPreview**

In `Sources/TeststripApp/ImportConfirmationDraft.swift`:

1. Add `var duplicateURLs: Set<URL>` to the `ImportDedupPreview` struct (after `reachedLimit: Bool`):
```swift
var duplicateURLs: Set<URL>
```

2. In `scan(sourceURL:...)`, add `var duplicateURLs: Set<URL> = []` before the loop.

3. At the path-match check (where `repository.asset(originalURL:)` is checked), collect the URL into `duplicateURLs`:
```swift
if (try? repository.asset(originalURL: fileURL)) != nil
    || (try? repository.asset(originalURL: fileURL.resolvingSymlinksInPath())) != nil {
    duplicateURLs.insert(fileURL)
    continue
}
```

4. After the hash check, add hash-matched files to `duplicateURLs`. The current code collects `contentHashes` and then checks against the catalog. We need to track which files have hashes that are in the catalog. Refactor: collect `(URL, String)` pairs, then after the `containedContentHashes` check, add files whose hash is in `existingHashes`:
```swift
var hashedFiles: [(url: URL, hash: String)] = []
// In the loop, replace `contentHashes.append(hash)` with:
if let hash = try? ContentHash.compute(forFileAt: fileURL) {
    hashedFiles.append((fileURL, hash))
}

// After the loop, replace the hash counting block:
let uniqueHashes = Set(hashedFiles.map(\.hash))
let existingHashes = Set((try? repository.containedContentHashes(uniqueHashes)) ?? [])
for entry in hashedFiles where existingHashes.contains(entry.hash) {
    duplicateURLs.insert(entry.url)
}
let newContentCount = uniqueHashes.subtracting(existingHashes).count
```

5. Update the return statement:
```swift
return ImportDedupPreview(
    newContentCount: newContentCount,
    existingContentCount: max(scannedPhotoCount - newContentCount, 0),
    reachedLimit: reachedLimit,
    duplicateURLs: duplicateURLs
)
```

6. Update `merging(_:_:)`:
```swift
return ImportDedupPreview(
    newContentCount: a.newContentCount + b.newContentCount,
    existingContentCount: a.existingContentCount + b.existingContentCount,
    reachedLimit: a.reachedLimit || b.reachedLimit,
    duplicateURLs: a.duplicateURLs.union(b.duplicateURLs)
)
```

- [ ] **Step 5: Fix existing tests that construct ImportSourceSummary/ImportDedupPreview**

Search for any existing tests that construct these types with the old member list and add the new fields. Run `swift build` to find them.

Run: `swift build 2>&1 | grep "error:" | head -20`

Fix each by adding `fileURLs: []` or `duplicateURLs: []` to the constructor call.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ImportConfirmationDraftTests`
Expected: PASS (all existing + 2 new tests)

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/ImportConfirmationDraft.swift Tests/TeststripAppTests/ImportConfirmationDraftTests.swift
git commit -m "feat: expose fileURLs from ImportSourceSummary and duplicateURLs from ImportDedupPreview"
```

---

## Task 4: ImportConfirmationDraft gains selectedFiles

**Files:**
- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift` (ImportConfirmationDraft struct)
- Test: `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`

**Interfaces:**
- Produces: `ImportConfirmationDraft.selectedFiles: Set<URL>?` — nil means "import all"; non-nil means "import only these files"
- Produces: `ImportConfirmationDraft.selectedCount: Int?` — nil when selectedFiles is nil, count when set
- Produces: `ImportConfirmationDraft.hasSelectionFilter: Bool` — true when selectedFiles is non-nil

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/ImportConfirmationDraftTests.swift`:

```swift
func testSelectedFilesDefaultNil() {
    let draft = ImportConfirmationDraft.folder(
        sourceURL: URL(fileURLWithPath: "/tmp/photos"),
        supportedExtensions: ["jpg"]
    )
    XCTAssertNil(draft.selectedFiles)
    XCTAssertFalse(draft.hasSelectionFilter)
    XCTAssertNil(draft.selectedCount)
}

func testSelectedFilesSet() {
    var draft = ImportConfirmationDraft.folder(
        sourceURL: URL(fileURLWithPath: "/tmp/photos"),
        supportedExtensions: ["jpg"]
    )
    let urls = Set([
        URL(fileURLWithPath: "/tmp/photos/a.jpg"),
        URL(fileURLWithPath: "/tmp/photos/b.jpg")
    ])
    draft.selectedFiles = urls
    XCTAssertTrue(draft.hasSelectionFilter)
    XCTAssertEqual(draft.selectedCount, 2)
}

func testPrimaryActionTitleWithSelection() {
    var draft = ImportConfirmationDraft.folder(
        sourceURL: URL(fileURLWithPath: "/tmp/photos"),
        supportedExtensions: ["jpg"]
    )
    draft.sourceSummary = ImportSourceSummary(
        sourceURL: URL(fileURLWithPath: "/tmp/photos"),
        photoCount: 100,
        byteCount: 500_000_000,
        reachedLimit: false,
        reachedEntryLimit: false,
        scannedEntryCount: 100,
        unavailableReason: nil,
        blocksImport: false,
        fileURLs: []
    )
    draft.selectedFiles = Set([
        URL(fileURLWithPath: "/tmp/photos/a.jpg"),
        URL(fileURLWithPath: "/tmp/photos/b.jpg")
    ])
    XCTAssertTrue(draft.primaryActionTitle.contains("2"), "title should reflect selected count, got: \(draft.primaryActionTitle)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImportConfirmationDraftTests`
Expected: FAIL — "value of type 'ImportConfirmationDraft' has no member 'selectedFiles'"

- [ ] **Step 3: Add selectedFiles to ImportConfirmationDraft**

In `Sources/TeststripApp/ImportConfirmationDraft.swift`, find the `ImportConfirmationDraft` struct (line ~285) and add:

```swift
var selectedFiles: Set<URL>?
```

Add after `autopilotAfterImport: Bool?` (or wherever the last stored property is).

Add computed properties:
```swift
var hasSelectionFilter: Bool {
    selectedFiles != nil
}

var selectedCount: Int? {
    selectedFiles?.count
}
```

Update `primaryActionTitle` (line ~466) to use `selectedCount` when available:
```swift
var primaryActionTitle: String {
    let count: Int
    if let selectedCount, selectedCount > 0 {
        count = selectedCount
    } else if importNewOnly, let dedup = dedupPreview {
        count = dedup.newContentCount
    } else {
        count = sourceSummary.photoCount
    }
    return count == 1 ? "Import 1 Photo" : "Import \(count) Photos"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ImportConfirmationDraftTests`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/ImportConfirmationDraft.swift Tests/TeststripAppTests/ImportConfirmationDraftTests.swift
git commit -m "feat: add selectedFiles to ImportConfirmationDraft"
```

---

## Task 5: LibraryImportService gains selectedFiles + thumbnail promotion

**Files:**
- Modify: `Sources/TeststripCore/Ingest/LibraryImportService.swift`
- Test: `Tests/TeststripCoreTests/FolderImportTests.swift`

**Interfaces:**
- Consumes: `PreIngestThumbnailCache` (from Task 1)
- Produces: `addFolderInPlace`/`copyFromCard` now accept `selectedFiles: Set<URL>? = nil` and `preIngestThumbnailCache: PreIngestThumbnailCache? = nil`
- Produces: `importAssets` filters source files by `selectedFiles` before calling `ingestService.ingest`
- Produces: `generatePreviews` promotes temp thumbnails for `.micro` level when cache is available

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/FolderImportTests.swift`:

```swift
func testSelectedFilesFiltersIngest() throws {
    let dir = makeTemporaryDirectory()
    let photo1 = dir.appendingPathComponent("keep.jpg")
    let photo2 = dir.appendingPathComponent("skip.jpg")
    let photo3 = dir.appendingPathComponent("keep2.jpg")
    try writeTestPNG(at: photo1)
    try writeTestPNG(at: photo2)
    try writeTestPNG(at: photo3)

    let repo = makeRepository(in: makeTemporaryDirectory())
    let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg", "png"]))
    let importService = LibraryImportService(
        ingestService: service,
        previewCache: PreviewCache(root: makeTemporaryDirectory())
    )

    let selectedFiles: Set<URL> = [photo1, photo3]
    let result = try importService.addFolderInPlace(
        dir,
        repository: repo,
        previewPolicy: .defer,
        selectedFiles: selectedFiles
    )

    XCTAssertEqual(result.importedAssets.count, 2)
    let importedURLs = Set(result.importedAssets.map(\.originalURL))
    XCTAssertTrue(importedURLs.contains(photo1))
    XCTAssertTrue(importedURLs.contains(photo3))
    XCTAssertFalse(importedURLs.contains(photo2))
}

func testThumbnailPromotionSkipsMicroRender() throws {
    let dir = makeTemporaryDirectory()
    let photo = dir.appendingPathComponent("photo.jpg")
    try writeTestPNG(at: photo)

    // Create a pre-ingest thumbnail cache with a thumbnail for this photo
    let preIngestCache = PreIngestThumbnailCache(directoryURL: makeTempDir())
    let thumbnailData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // minimal JPEG header
    try preIngestCache.storeThumbnail(thumbnailData, for: photo)

    let previewRoot = makeTempDir()
    let repo = makeRepository(in: makeTemporaryDirectory())
    let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg", "png"]))
    let importService = LibraryImportService(
        ingestService: service,
        previewCache: PreviewCache(root: previewRoot)
    )

    let result = try importService.addFolderInPlace(
        dir,
        repository: repo,
        previewPolicy: .generateImmediately,
        preIngestThumbnailCache: preIngestCache
    )

    XCTAssertEqual(result.importedAssets.count, 1)
    let asset = result.importedAssets[0]

    // The micro preview should be the promoted thumbnail, not a fresh render
    let microURL = PreviewCache(root: previewRoot).url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
    XCTAssertTrue(FileManager.default.fileExists(atPath: microURL.path), "micro preview should exist from promotion")

    // The micro preview should NOT be in the pending generation queue
    let pendingItems = try repo.pendingPreviewGenerationItems()
    let microPending = pendingItems.filter { $0.assetID == asset.id && $0.level == .micro }
    XCTAssertTrue(microPending.isEmpty, "micro preview should be marked as generated")

    preIngestCache.cleanup()
}

private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("import-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FolderImportTests`
Expected: FAIL — "extra argument 'selectedFiles' in call"

- [ ] **Step 3: Add selectedFiles and preIngestThumbnailCache to LibraryImportService**

In `Sources/TeststripCore/Ingest/LibraryImportService.swift`:

1. Add parameters to `addFolderInPlace` (line ~132):
```swift
public func addFolderInPlace(
    _ root: URL,
    repository: CatalogRepository,
    previewPolicy: LibraryImportPreviewPolicy,
    duplicateHandling: DuplicateHandling = .importAll,
    selectedFiles: Set<URL>? = nil,
    preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
    progress: LibraryImportProgressHandler? = nil
) throws -> LibraryImportResult {
    try importAssets(
        plan: IngestPlanner.addFolder(root, duplicateHandling: duplicateHandling),
        scanRootName: root.lastPathComponent,
        catalogingDetail: { "Cataloging \(Self.photoCountDescription($0))" },
        perFileDetail: { completed, total in "Cataloging \(completed) of \(total) photos" },
        catalogedDetail: { "Cataloged \(Self.photoCountDescription($0))" },
        repository: repository,
        previewPolicy: previewPolicy,
        selectedFiles: selectedFiles,
        preIngestThumbnailCache: preIngestThumbnailCache,
        progress: progress
    )
}
```

2. Add parameters to `copyFromCard` (line ~151):
```swift
public func copyFromCard(
    source: URL,
    destinationRoot: URL,
    destinationPolicy: ImportDestinationPolicy = .flat,
    secondCopyDestination: URL? = nil,
    repository: CatalogRepository,
    previewPolicy: LibraryImportPreviewPolicy,
    duplicateHandling: DuplicateHandling = .importAll,
    selectedFiles: Set<URL>? = nil,
    preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
    progress: LibraryImportProgressHandler? = nil
) throws -> LibraryImportResult {
    try importAssets(
        plan: IngestPlanner.copyFromCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: destinationPolicy,
            secondCopyDestination: secondCopyDestination,
            duplicateHandling: duplicateHandling
        ),
        scanRootName: source.lastPathComponent,
        catalogingDetail: { "Copying \(Self.photoCountDescription($0)) to \(destinationRoot.lastPathComponent)" },
        perFileDetail: { completed, total in "Copying \(completed) of \(total) photos to \(destinationRoot.lastPathComponent)" },
        catalogedDetail: { "Copied \(Self.photoCountDescription($0)) to \(destinationRoot.lastPathComponent)" },
        repository: repository,
        previewPolicy: previewPolicy,
        selectedFiles: selectedFiles,
        preIngestThumbnailCache: preIngestThumbnailCache,
        progress: progress
    )
}
```

3. Add parameters to `importAssets` (line ~179) and filter source files:
```swift
private func importAssets(
    plan: IngestPlan,
    scanRootName: String,
    catalogingDetail: (Int) -> String,
    perFileDetail: @escaping @Sendable (Int, Int) -> String,
    catalogedDetail: (Int) -> String,
    repository: CatalogRepository,
    previewPolicy: LibraryImportPreviewPolicy,
    selectedFiles: Set<URL>? = nil,
    preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
    progress: LibraryImportProgressHandler?
) throws -> LibraryImportResult {
```

After the line `let sourceFiles = scannedSourceFiles.filter { !isPreviewCacheFile($0) }` (line ~215), add:
```swift
let filteredFiles = selectedFiles.map { selected in
    sourceFiles.filter { selected.contains($0) }
} ?? sourceFiles
```

Then change the `ingestService.ingest(files: sourceFiles, ...)` call to use `filteredFiles`:
```swift
let assets = try ingestService.ingest(
    files: filteredFiles,
    plan: plan,
    // ... rest unchanged
)
```

Also update the progress total count to use `filteredFiles.count` instead of `sourceFiles.count`:
```swift
totalUnitCount: filteredFiles.count,
```

And the `catalogingDetail` call:
```swift
detail: catalogingDetail(filteredFiles.count)
```

4. Pass `preIngestThumbnailCache` to `generatePreviews`:

Change the `generatePreviews` call (line ~330) to:
```swift
let previewResult = try generatePreviews(
    for: previewItems,
    repository: repository,
    preIngestThumbnailCache: preIngestThumbnailCache,
    progress: progress
)
```

5. Add `preIngestThumbnailCache` parameter to `generatePreviews` (line ~357):
```swift
private func generatePreviews(
    for items: [PreviewGenerationItem],
    repository: CatalogRepository,
    preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
    progress: LibraryImportProgressHandler?
) throws -> LibraryPreviewGenerationResult {
```

Inside the loop (before `try renderer.render(...)`), add the promotion check:
```swift
let asset = try repository.asset(id: item.assetID)
if let cache = preIngestThumbnailCache,
   item.level == .micro,
   cache.thumbnailExists(for: asset.originalURL) {
    let destURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
    try cache.promote(from: asset.originalURL, to: destURL)
    try repository.markPreviewGenerated(assetID: asset.id, level: .micro)
    generatedCount += 1
    // Report progress and continue
    let completedCount = index + 1
    progress?(LibraryImportProgress(
        completedUnitCount: completedCount,
        totalUnitCount: items.count,
        detail: "Generated \(completedCount) of \(items.count) previews"
    ))
    continue
}
```

- [ ] **Step 4: Fix any compile errors from the signature changes**

Run: `swift build 2>&1 | grep "error:" | head -20`

Fix any calls to `generatePreviews` that don't pass `preIngestThumbnailCache` — the default `nil` should handle most, but `resumePendingPreviews` (line ~344) calls `generatePreviews` without the new param. That's fine since it has a default value.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FolderImportTests`
Expected: PASS (all existing + 2 new tests)

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Ingest/LibraryImportService.swift Tests/TeststripCoreTests/FolderImportTests.swift
git commit -m "feat: add selectedFiles filter and thumbnail promotion to LibraryImportService"
```

---

## Task 6: WorkerCommand selectedFiles + temp cache passthrough

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerCommand.swift`
- Modify: `Sources/TeststripCore/Worker/WorkerProtocol.swift`
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`
- Test: `Tests/TeststripWorkerTests/WorkerProtocolTests.swift`
- Test: `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`

**Interfaces:**
- Consumes: `LibraryImportService` changes (from Task 5)
- Produces: `WorkerCommand.importFolder(root:duplicateHandling:selectedFiles:preIngestThumbnails:)` and `WorkerCommand.importCard(source:destinationRoot:destinationPolicy:secondCopyDestination:duplicateHandling:selectedFiles:preIngestThumbnails:)`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripWorkerTests/WorkerProtocolTests.swift`:

```swift
func testImportFolderWithSelectedFilesRoundTrips() throws {
    let selected: Set<URL> = [
        URL(fileURLWithPath: "/tmp/photos/a.jpg"),
        URL(fileURLWithPath: "/tmp/photos/b.jpg")
    ]
    let thumbDir = URL(fileURLWithPath: "/tmp/thumbnails")
    let command = WorkerCommand.importFolder(
        root: URL(fileURLWithPath: "/tmp/photos"),
        duplicateHandling: .importAll,
        selectedFiles: selected,
        preIngestThumbnails: thumbDir
    )
    let envelope = try WorkerProtocolEncoder.encode(command)
    let decoded = try WorkerProtocolEncoder.decodeRequest(envelope)
    XCTAssertEqual(decoded, command)
}

func testImportCardWithSelectedFilesRoundTrips() throws {
    let selected: Set<URL> = [URL(fileURLWithPath: "/tmp/card/IMG_0001.jpg")]
    let thumbDir = URL(fileURLWithPath: "/tmp/thumbnails")
    let command = WorkerCommand.importCard(
        source: URL(fileURLWithPath: "/Volumes/SD"),
        destinationRoot: URL(fileURLWithPath: "/tmp/dest"),
        destinationPolicy: .flat,
        secondCopyDestination: nil,
        duplicateHandling: .importAll,
        selectedFiles: selected,
        preIngestThumbnails: thumbDir
    )
    let envelope = try WorkerProtocolEncoder.encode(command)
    let decoded = try WorkerProtocolEncoder.decodeRequest(envelope)
    XCTAssertEqual(decoded, command)
}
```

Add to `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`:

```swift
func testImportFolderPassesSelectedFilesToImportService() throws {
    let dir = makeTemporaryDirectory()
    let photo1 = dir.appendingPathComponent("keep.jpg")
    let photo2 = dir.appendingPathComponent("skip.jpg")
    try writeTestPNG(at: photo1)
    try writeTestPNG(at: photo2)

    let repo = makeRepository(in: makeTemporaryDirectory())
    let importService = LibraryImportService(
        ingestService: IngestService(scanner: FolderScanner(supportedExtensions: ["jpg", "png"])),
        previewCache: PreviewCache(root: makeTemporaryDirectory())
    )
    let executor = WorkerCommandExecutor(
        importService: importService,
        repository: repo,
        // ... other params as existing tests construct it
    )

    let result = try executor.execute(
        .importFolder(
            root: dir,
            duplicateHandling: .importAll,
            selectedFiles: [photo1],
            preIngestThumbnails: nil
        )
    )

    guard case .completedImport(_, let importedAssetIDs, _, _, _, _) = result else {
        XCTFail("expected completedImport, got \(result)")
        return
    }
    XCTAssertEqual(importedAssetIDs.count, 1)
}
```

Note: Match the existing `WorkerCommandExecutorTests` setup pattern — check how existing tests construct the executor and use the same helpers.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkerProtocolTests`
Expected: FAIL — "cannot find 'selectedFiles' in call" / "extra arguments"

- [ ] **Step 3: Update WorkerCommand enum cases**

In `Sources/TeststripCore/Worker/WorkerCommand.swift`:

Change the import cases:
```swift
case importFolder(
    root: URL,
    duplicateHandling: DuplicateHandling,
    selectedFiles: Set<URL>?,
    preIngestThumbnails: URL?
)
case importCard(
    source: URL,
    destinationRoot: URL,
    destinationPolicy: ImportDestinationPolicy,
    secondCopyDestination: URL?,
    duplicateHandling: DuplicateHandling,
    selectedFiles: Set<URL>?,
    preIngestThumbnails: URL?
)
```

Update `operationDescription` to include the new params (add `let selectedFiles, let preIngestThumbnails` or `_` for unused values):
```swift
case .importFolder(_, _, _, _):
    return "Importing folder"
case .importCard(_, _, _, _, _, _, _):
    return "Importing from card"
```

Update `silenceTimeout` pattern matches:
```swift
case .importFolder(_, _, _, _):
    return 600
case .importCard(_, _, _, _, _, _, _):
    return 600
```

- [ ] **Step 4: Update WorkerProtocol encode/decode**

In `Sources/TeststripCore/Worker/WorkerProtocol.swift`:

1. Add fields to `WorkerCommandEnvelope`:
```swift
var selectedFiles: [String]?
var preIngestThumbnails: String?
```

2. Update the encode switch (the `encode` function that creates envelopes). Find `case .importFolder(let root, let duplicateHandling):` and change to:
```swift
case .importFolder(let root, let duplicateHandling, let selectedFiles, let preIngestThumbnails):
    return WorkerCommandEnvelope(
        kind: "importFolder",
        rootURL: root.path,
        duplicateHandling: duplicateHandling,
        selectedFiles: selectedFiles?.map(\.path).sorted(),
        preIngestThumbnails: preIngestThumbnails?.path,
        // ... other fields nil
    )
```

Find `case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination, let duplicateHandling):` and change to:
```swift
case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination, let duplicateHandling, let selectedFiles, let preIngestThumbnails):
    return WorkerCommandEnvelope(
        kind: "importCard",
        sourceURL: source.path,
        destinationRootURL: destinationRoot.path,
        destinationPolicy: destinationPolicy,
        secondCopyDestinationURL: secondCopyDestination?.path,
        duplicateHandling: duplicateHandling,
        selectedFiles: selectedFiles?.map(\.path).sorted(),
        preIngestThumbnails: preIngestThumbnails?.path,
        // ... other fields nil
    )
```

3. Update `decodeRequest` to decode the new fields. Find the `case "importFolder":` and `case "importCard":` in the decode switch:
```swift
case "importFolder":
    return .importFolder(
        root: URL(fileURLWithPath: envelope.rootURL ?? ""),
        duplicateHandling: envelope.duplicateHandling ?? .importAll,
        selectedFiles: envelope.selectedFiles.map { Set($0.map { URL(fileURLWithPath: $0) }) },
        preIngestThumbnails: envelope.preIngestThumbnails.map { URL(fileURLWithPath: $0) }
    )
case "importCard":
    return .importCard(
        source: URL(fileURLWithPath: envelope.sourceURL ?? ""),
        destinationRoot: URL(fileURLWithPath: envelope.destinationRootURL ?? ""),
        destinationPolicy: envelope.destinationPolicy ?? .flat,
        secondCopyDestination: envelope.secondCopyDestinationURL.map { URL(fileURLWithPath: $0) },
        duplicateHandling: envelope.duplicateHandling ?? .importAll,
        selectedFiles: envelope.selectedFiles.map { Set($0.map { URL(fileURLWithPath: $0) }) },
        preIngestThumbnails: envelope.preIngestThumbnails.map { URL(fileURLWithPath: $0) }
    )
```

- [ ] **Step 5: Update WorkerCommandExecutor**

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`:

Find the `.importFolder` case (line ~174) and change to:
```swift
case .importFolder(let root, let duplicateHandling, let selectedFiles, let preIngestThumbnails):
    let cache = preIngestThumbnails.map { PreIngestThumbnailCache(directoryURL: $0) }
    let result = try importService.addFolderInPlace(
        root,
        repository: repository,
        previewPolicy: .generateImmediately,
        duplicateHandling: duplicateHandling,
        selectedFiles: selectedFiles,
        preIngestThumbnailCache: cache,
        progress: progressHandler
    )
    return .completedImport(
        message: "Imported \(result.importedAssets.count) photos",
        importedAssetIDs: result.importedAssets.map(\.id),
        newAssetCount: result.newAssetCount,
        existingAssetCount: result.existingAssetCount,
        skippedSourceFileCount: result.skippedSourceFiles.count,
        skippedSourceFiles: result.skippedSourceFiles
    )
```

Find the `.importCard` case (line ~190) and make the same changes, adding `selectedFiles` and `cache`:
```swift
case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination, let duplicateHandling, let selectedFiles, let preIngestThumbnails):
    let cache = preIngestThumbnails.map { PreIngestThumbnailCache(directoryURL: $0) }
    let result = try importService.copyFromCard(
        source: source,
        destinationRoot: destinationRoot,
        destinationPolicy: destinationPolicy,
        secondCopyDestination: secondCopyDestination,
        repository: repository,
        previewPolicy: .generateImmediately,
        duplicateHandling: duplicateHandling,
        selectedFiles: selectedFiles,
        preIngestThumbnailCache: cache,
        progress: progressHandler
    )
    return .completedImport(
        message: "Imported \(result.importedAssets.count) photos",
        importedAssetIDs: result.importedAssets.map(\.id),
        newAssetCount: result.newAssetCount,
        existingAssetCount: result.existingAssetCount,
        skippedSourceFileCount: result.skippedSourceFiles.count,
        skippedSourceFiles: result.skippedSourceFiles
    )
```

- [ ] **Step 6: Fix all pattern-match compile errors**

Run: `swift build 2>&1 | grep "error:" | head -30`

Fix every file that pattern-matches `.importFolder` or `.importCard` with the old arity. Search:
```bash
grep -rn "\.importFolder(" Sources/ Tests/ | grep -v "//\|test" | head -30
```

Each match needs the two new associated values added. For `WorkerSupervisor.swift:258` (which matches `.completedImport` not `.importFolder`), no change needed.

- [ ] **Step 7: Fix all existing test calls to importFolder/importCard**

Search for existing tests that construct `WorkerCommand.importFolder` or `.importCard`:
```bash
grep -rn "\.importFolder(" Tests/ | head -20
grep -rn "\.importCard(" Tests/ | head -20
```

Add `selectedFiles: nil, preIngestThumbnails: nil` to each call.

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter WorkerProtocolTests && swift test --filter WorkerCommandExecutorTests`
Expected: PASS

- [ ] **Step 9: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 10: Commit**

```bash
git add Sources/TeststripCore/Worker/WorkerCommand.swift \
  Sources/TeststripCore/Worker/WorkerProtocol.swift \
  Sources/TeststripCore/Worker/WorkerCommandExecutor.swift \
  Tests/TeststripWorkerTests/WorkerProtocolTests.swift \
  Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift
git commit -m "feat: pass selectedFiles and preIngestThumbnails through worker protocol"
```

---

## Task 7: AppModel selectedFiles + factory typealiases + dedup scan

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `LibraryImportService` changes (Task 5), `WorkerCommand` changes (Task 6)
- Produces: `beginImportFolder(selectedFiles:preIngestThumbnailCache:)`, `beginImportCard(selectedFiles:preIngestThumbnailCache:)`, `beginImportFolders(selectedFiles:preIngestThumbnailCache:)`
- Produces: Updated `AppImportTaskFactory` and `AppCardImportTaskFactory` typealiases (2 new params each)
- Produces: `scanDedupPreview(sourceURL:supportedExtensions:) async -> ImportDedupPreview?` helper

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
func testBeginImportFolderPassesSelectedFiles() throws {
    let dir = makeTemporaryDirectory()
    let photo1 = dir.appendingPathComponent("keep.jpg")
    let photo2 = dir.appendingPathComponent("skip.jpg")
    try writeTestPNG(at: photo1)
    try writeTestPNG(at: photo2)

    var receivedSelectedFiles: Set<URL>?
    let model = AppModel(
        catalog: AppCatalog(
            paths: .defaultPaths(in: makeTemporaryDirectory()),
            importTaskFactory: { paths, folderURL, duplicateHandling, selectedFiles, preIngestThumbnailCache, progress in
                receivedSelectedFiles = selectedFiles
                return Self.defaultImportTask(
                    paths: paths,
                    folderURL: folderURL,
                    previewPolicy: .defer,
                    duplicateHandling: duplicateHandling,
                    selectedFiles: selectedFiles,
                    preIngestThumbnailCache: preIngestThumbnailCache,
                    progress: progress
                )
            },
            // ... other params as existing tests
        )
    )
    try model.load()

    model.beginImportFolder(dir, selectedFiles: [photo1])
    waitForActivityStatus(.completed, in: model)

    XCTAssertEqual(receivedSelectedFiles, [photo1])
}
```

Note: Match the existing `AppModelTests` setup pattern. Check how existing tests construct `AppModel` with factory injection. The test should follow that pattern exactly, just adding the two new `_, ` params to the factory closure.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelTests.testBeginImportFolderPassesSelectedFiles`
Expected: FAIL — compile error from factory arity mismatch

- [ ] **Step 3: Update factory typealiases**

In `Sources/TeststripApp/AppModel.swift`, find the typealiases (around line 1690):

```swift
public typealias AppImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    DuplicateHandling,
    Set<URL>?,
    PreIngestThumbnailCache?,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>

public typealias AppCardImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    URL,
    ImportDestinationPolicy,
    URL?,
    DuplicateHandling,
    Set<URL>?,
    PreIngestThumbnailCache?,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>
```

- [ ] **Step 4: Update defaultImportTask and defaultCardImportTask**

In `Sources/TeststripApp/AppModel.swift` (around line 14888), add `selectedFiles` and `preIngestThumbnailCache` parameters:

```swift
private static func defaultImportTask(
    paths: AppCatalogPaths,
    folderURL: URL,
    previewPolicy: LibraryImportPreviewPolicy,
    duplicateHandling: DuplicateHandling,
    selectedFiles: Set<URL>?,
    preIngestThumbnailCache: PreIngestThumbnailCache?,
    progress: @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error> {
    Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let backgroundCatalog = try AppCatalog.open(paths: paths)
        let result = try backgroundCatalog.importService.addFolderInPlace(
            folderURL,
            repository: backgroundCatalog.repository,
            previewPolicy: previewPolicy,
            duplicateHandling: duplicateHandling,
            selectedFiles: selectedFiles,
            preIngestThumbnailCache: preIngestThumbnailCache,
            progress: progress
        )
        try Task.checkCancellation()
        let contents = try Self.catalogContents(
            repository: backgroundCatalog.repository,
            query: nil
        )
        return AppImportOutput(
            result: result,
            assets: contents.assets,
            totalAssetCount: contents.totalAssetCount
        )
    }
}
```

Do the same for `defaultCardImportTask` (line ~14918), adding the two new params and passing them to `copyFromCard`.

- [ ] **Step 5: Update default factory closures**

Find where the default factory closures are created in `AppModel.init` (search for `importTaskFactory:` in the init). Update the closure to pass through the new params:

```swift
self.importTaskFactory = importTaskFactory ?? { paths, folderURL, duplicateHandling, selectedFiles, preIngestThumbnailCache, progress in
    Self.defaultImportTask(
        paths: paths,
        folderURL: folderURL,
        previewPolicy: importPreviewPolicy,
        duplicateHandling: duplicateHandling,
        selectedFiles: selectedFiles,
        preIngestThumbnailCache: preIngestThumbnailCache,
        progress: progress
    )
}
```

Same for `cardImportTaskFactory`.

- [ ] **Step 6: Update beginImportFolder, beginImportCard, beginImportFolders**

Find `beginImportFolder` (line ~14289) and add `selectedFiles: Set<URL>? = nil` and `preIngestThumbnailCache: PreIngestThumbnailCache? = nil` parameters. Pass them to the factory call:

```swift
public func beginImportFolder(
    _ url: URL,
    evaluateAfterImport: Bool = true,
    importNewOnly: Bool = true,
    autopilotAfterImport: Bool? = nil,
    selectedFiles: Set<URL>? = nil,
    preIngestThumbnailCache: PreIngestThumbnailCache? = nil
) {
    guard !isImporting else {
        errorMessage = "Another import is already running"
        return
    }
    // ... existing setup ...
    let task = importTaskFactory(
        catalog.paths,
        url,
        duplicateHandling,
        selectedFiles,
        preIngestThumbnailCache,
        progressHandler
    )
    // ... rest unchanged
}
```

Do the same for `beginImportCard` (line ~14375) and `beginImportFolders` (line ~14264).

For `PendingImportFolder` (struct at line ~1979), add `selectedFiles: Set<URL>?` and `preIngestThumbnailCache: PreIngestThumbnailCache?` fields. Update `drainPendingImportFolder` (line ~14592) to pass them through to `beginImportFolder`.

- [ ] **Step 7: Update enqueueWorkerImport to pass selectedFiles and preIngestThumbnails**

Find `enqueueWorkerImport` (line ~10970). Update the `.importFolder` and `.importCard` command construction:

```swift
let command = WorkerCommand.importFolder(
    root: url,
    duplicateHandling: duplicateHandling,
    selectedFiles: selectedFiles,
    preIngestThumbnails: preIngestThumbnailCache?.directoryURL
)
```

```swift
let command = WorkerCommand.importCard(
    source: sourceURL,
    destinationRoot: destinationRoot,
    destinationPolicy: destinationPolicy,
    secondCopyDestination: secondCopyDestination,
    duplicateHandling: duplicateHandling,
    selectedFiles: selectedFiles,
    preIngestThumbnails: preIngestThumbnailCache?.directoryURL
)
```

- [ ] **Step 8: Add scanDedupPreview helper**

Add to `AppModel`:

```swift
public func scanDedupPreview(
    sourceURL: URL,
    supportedExtensions: Set<String>
) async -> ImportDedupPreview? {
    guard let repo = catalog?.repository else { return nil }
    return ImportDedupPreview.scan(
        sourceURL: sourceURL,
        supportedExtensions: supportedExtensions,
        repository: repo
    )
}
```

- [ ] **Step 9: Update all 21 test factory closures**

Run: `swift build 2>&1 | grep "error:" | head -40`

Each error will be a factory closure with the wrong number of parameters. For each:
- Folder factories: `{ _, _, _, _ in` → `{ _, _, _, _, _, _ in` (6 underscores)
- Card factories: `{ _, _, _, _, _, _, _ in` → `{ _, _, _, _, _, _, _, _, _ in` (9 underscores)
- Closures that use specific param names (e.g., `{ paths, _, _, progress in`): add `_, _` for the new params: `{ paths, _, _, _, _, progress in`

Files to update (from FF4):
- `Tests/TeststripAppTests/AppModelTests.swift` — ~19 closures
- `Tests/TeststripAppTests/ImportCompletionScopingTests.swift` — 1 closure
- `Tests/TeststripAppTests/ImportCompletionSurfaceTests.swift` — 1 closure

- [ ] **Step 10: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 11: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift \
  Tests/TeststripAppTests/ImportCompletionScopingTests.swift \
  Tests/TeststripAppTests/ImportCompletionSurfaceTests.swift
git commit -m "feat: thread selectedFiles and preIngestThumbnailCache through AppModel + factory typealiases"
```

---

## Task 8: ImportSelectionView

**Files:**
- Create: `Sources/TeststripApp/ImportSelectionView.swift`
- Test: `Tests/TeststripAppTests/ImportSelectionViewTests.swift`

**Interfaces:**
- Consumes: `ImportSourceSummary.fileURLs` (Task 3), `ImportDedupPreview.duplicateURLs` (Task 3), `PreIngestThumbnailCache` (Task 1), `PreIngestThumbnailRenderer` (Task 2), `ImportConfirmationDraft.selectedFiles` (Task 4)
- Produces: `ImportSelectionView` SwiftUI view, `ImportSelectionModel` observable model, `ImportSelectionFilter` enum

- [ ] **Step 1: Write the failing test for the selection model**

```swift
// Tests/TeststripAppTests/ImportSelectionViewTests.swift
import XCTest
@testable import TeststripApp

final class ImportSelectionViewTests: XCTestCase {
    func testFilterAllShowsAllEntries() {
        let entries = makeEntries(count: 5, duplicateIndices: [2])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [entries[2].url])
        model.filter = .all
        XCTAssertEqual(model.filteredEntries.count, 5)
    }

    func testFilterNewOnlyExcludesDuplicates() {
        let entries = makeEntries(count: 5, duplicateIndices: [1, 3])
        let dupes = Set([entries[1].url, entries[3].url])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: dupes)
        model.filter = .newOnly
        XCTAssertEqual(model.filteredEntries.count, 3)
        XCTAssertFalse(model.filteredEntries.contains { $0.url == entries[1].url })
        XCTAssertFalse(model.filteredEntries.contains { $0.url == entries[3].url })
    }

    func testFilterDuplicatesOnlyShowsDuplicates() {
        let entries = makeEntries(count: 5, duplicateIndices: [0, 4])
        let dupes = Set([entries[0].url, entries[4].url])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: dupes)
        model.filter = .duplicates
        XCTAssertEqual(model.filteredEntries.count, 2)
    }

    func testSelectAll() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.selectAll()
        XCTAssertEqual(model.selectedURLs.count, 5)
    }

    func testSelectNone() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.selectAll()
        model.selectNone()
        XCTAssertTrue(model.selectedURLs.isEmpty)
    }

    func testDefaultAllSelected() {
        let entries = makeEntries(count: 3, duplicateIndices: [1])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [entries[1].url])
        XCTAssertEqual(model.selectedURLs.count, 3, "all should be selected by default")
    }

    func testSelectedCountAfterDeselect() {
        let entries = makeEntries(count: 5, duplicateIndices: [])
        let model = ImportSelectionModel(entries: entries, duplicateURLs: [])
        model.toggle(entries[0].url)
        XCTAssertEqual(model.selectedURLs.count, 4)
    }

    private func makeEntries(count: Int, duplicateIndices: Set<Int>) -> [ImportSelectionEntry] {
        (0..<count).map { i in
            ImportSelectionEntry(
                url: URL(fileURLWithPath: "/tmp/photo\(i).jpg"),
                byteSize: 1_000_000,
                isDuplicate: duplicateIndices.contains(i)
            )
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImportSelectionViewTests`
Expected: FAIL — "cannot find 'ImportSelectionModel' in scope"

- [ ] **Step 3: Write the model and view**

```swift
// Sources/TeststripApp/ImportSelectionView.swift
import SwiftUI
import TeststripCore

enum ImportSelectionFilter: Hashable {
    case all
    case newOnly
    case duplicates
}

struct ImportSelectionEntry: Identifiable, Hashable {
    let url: URL
    let byteSize: Int64
    let isDuplicate: Bool

    var id: URL { url }
}

@MainActor
final class ImportSelectionModel: ObservableObject {
    let entries: [ImportSelectionEntry]
    let duplicateURLs: Set<URL>
    let thumbnailCache: PreIngestThumbnailCache
    let thumbnailRenderer: PreIngestThumbnailRenderer

    @Published var selectedURLs: Set<URL>
    @Published var filter: ImportSelectionFilter = .all
    @Published var thumbnails: [URL: NSImage] = [:]
    @Published var isRendering = false

    init(
        entries: [ImportSelectionEntry],
        duplicateURLs: Set<URL>,
        thumbnailCache: PreIngestThumbnailCache,
        thumbnailRenderer: PreIngestThumbnailRenderer = PreIngestThumbnailRenderer()
    ) {
        self.entries = entries
        self.duplicateURLs = duplicateURLs
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
        self.selectedURLs = Set(entries.map(\.url))
    }

    var filteredEntries: [ImportSelectionEntry] {
        switch filter {
        case .all:
            entries
        case .newOnly:
            entries.filter { !duplicateURLs.contains($0.url) }
        case .duplicates:
            entries.filter { duplicateURLs.contains($0.url) }
        }
    }

    var selectedCount: Int { selectedURLs.count }

    func selectAll() {
        selectedURLs = Set(entries.map(\.url))
    }

    func selectNone() {
        selectedURLs.removeAll()
    }

    func toggle(_ url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    func loadThumbnail(for url: URL) {
        if thumbnails[url] != nil { return }
        if let image = thumbnailCache.thumbnailImage(for: url) {
            thumbnails[url] = image
            return
        }
        isRendering = true
        let cache = thumbnailCache
        let renderer = thumbnailRenderer
        Task.detached {
            try? renderer.render(sourceURL: url, cache: cache)
            let image = cache.thumbnailImage(for: url)
            await MainActor.run {
                if let image { self.thumbnails[url] = image }
                self.isRendering = false
            }
        }
    }
}

struct ImportSelectionView: View {
    @StateObject var model: ImportSelectionModel
    let onConfirm: (Set<URL>) -> Void
    let onCancel: () -> Void

    private let columns = Array(
        repeating: GridItem(.adaptive(minimum: 100), spacing: 8),
        count: 1
    )

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("Filter", selection: $model.filter) {
                    Text("All").tag(ImportSelectionFilter.all)
                    Text("New").tag(ImportSelectionFilter.newOnly)
                    Text("Duplicates").tag(ImportSelectionFilter.duplicates)
                }
                .pickerStyle(.segmented)
                Spacer()
                Text("\(model.selectedCount) of \(model.entries.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            // Thumbnail grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.filteredEntries) { entry in
                        ThumbnailCell(
                            entry: entry,
                            isSelected: model.selectedURLs.contains(entry.url),
                            thumbnail: model.thumbnails[entry.url],
                            isDuplicate: model.duplicateURLs.contains(entry.url),
                            onToggle: { model.toggle(entry.url) },
                            onAppear: { model.loadThumbnail(for: entry.url) }
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            // Footer
            HStack {
                Button("Select All") { model.selectAll() }
                Button("Select None") { model.selectNone() }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                Button("Import \(model.selectedCount) Photos") {
                    onConfirm(model.selectedURLs)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedURLs.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 800, height: 600)
    }
}

private struct ThumbnailCell: View {
    let entry: ImportSelectionEntry
    let isSelected: Bool
    let thumbnail: NSImage?
    let isDuplicate: Bool
    let onToggle: () -> Void
    let onAppear: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )

                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .padding(4)

                // Duplicate badge
                if isDuplicate {
                    Text("Dup")
                        .font(.caption2)
                        .padding(2)
                        .background(.orange.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { onAppear() }
    }
}
```

- [ ] **Step 4: Add thumbnailImage to PreIngestThumbnailCache**

`PreIngestThumbnailCache` is in TeststripCore and can't import AppKit. Add a `thumbnailData(for:)` method that returns `Data?`, and have the view load it as `NSImage(data:)`:

In `Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift`:
```swift
public func thumbnailData(for sourceURL: URL) -> Data? {
    let url = thumbnailURL(for: sourceURL)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? Data(contentsOf: url)
}
```

Update `ImportSelectionModel.loadThumbnail`:
```swift
func loadThumbnail(for url: URL) {
    if thumbnails[url] != nil { return }
    if let data = thumbnailCache.thumbnailData(for: url), let image = NSImage(data: data) {
        thumbnails[url] = image
        return
    }
    // Background render...
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ImportSelectionViewTests`
Expected: PASS (7 tests)

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/ImportSelectionView.swift \
  Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift \
  Tests/TeststripAppTests/ImportSelectionViewTests.swift
git commit -m "feat: add ImportSelectionView with lazy thumbnail grid and filter bar"
```

---

## Task 9: Wire Review & Select + lift isImporting + queue visibility

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift`
- Test: `Tests/TeststripAppTests/LensChromePolicyTests.swift` (if import button policy assertions exist)

**Interfaces:**
- Consumes: `ImportSelectionView` (Task 8), `AppModel.scanDedupPreview` (Task 7), `ImportConfirmationDraft.selectedFiles` (Task 4), `PreIngestThumbnailCache`/`PreIngestThumbnailRenderer` (Tasks 1-2)

- [ ] **Step 1: Add import sheet state enum**

In `Sources/TeststripApp/LibraryGridView.swift`, add a state enum for managing sheet transitions:

```swift
private enum ImportSheetState: Identifiable {
    case confirmation(ImportConfirmationDraft)
    case selection(ImportSelectionData)

    var id: String {
        switch self {
        case .confirmation: return "confirmation"
        case .selection: return "selection"
        }
    }
}

private struct ImportSelectionData: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let supportedExtensions: Set<String>
    let fileURLs: [URL]
    var duplicateURLs: Set<URL>
    let thumbnailCache: PreIngestThumbnailCache
}
```

Replace the existing `@State private var importConfirmationDraft: ImportConfirmationDraft?` with:
```swift
@State private var importSheet: ImportSheetState?
```

And update the `.sheet(item: $importConfirmationDraft)` modifier to `.sheet(item: $importSheet)` with a switch:
```swift
.sheet(item: $importSheet) { state in
    switch state {
    case .confirmation(let draft):
        importConfirmationSheet(draft)
    case .selection(let data):
        importSelectionSheet(data)
    }
}
```

- [ ] **Step 2: Add "Review & Select" button to confirmation sheet**

In `importConfirmationSheet` (line ~1721), add a button in the content VStack after the plan steps:

```swift
importPlanView(steps: draft.planSteps, width: 440)

Button("Review & Select…") {
    startImportSelection(for: draft)
}
.buttonStyle(.bordered)
.padding(.top, 6)
```

- [ ] **Step 3: Implement startImportSelection**

Add a method that transitions from confirmation to selection:

```swift
private func startImportSelection(for draft: ImportConfirmationDraft) {
    let cache = PreIngestThumbnailCache()
    let data = ImportSelectionData(
        sourceURL: draft.sourceURL,
        supportedExtensions: model.supportedExtensions,
        fileURLs: draft.sourceSummary.fileURLs,
        duplicateURLs: draft.dedupPreview?.duplicateURLs ?? [],
        thumbnailCache: cache
    )
    importSheet = .selection(data)

    // Background: render thumbnails + scan for duplicates
    Task {
        let renderer = PreIngestThumbnailRenderer()
        try? renderer.renderBatch(data.fileURLs, cache: cache)

        let dedup = await model.scanDedupPreview(
            sourceURL: data.sourceURL,
            supportedExtensions: data.supportedExtensions
        )
        if let dedup {
            await MainActor.run {
                if case .selection(var d) = importSheet {
                    d.duplicateURLs = dedup.duplicateURLs
                    importSheet = .selection(d)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Implement importSelectionSheet**

```swift
private func importSelectionSheet(_ data: ImportSelectionData) -> some View {
    let entries = data.fileURLs.map { url in
        ImportSelectionEntry(
            url: url,
            byteSize: 0,
            isDuplicate: data.duplicateURLs.contains(url)
        )
    }
    let model = ImportSelectionModel(
        entries: entries,
        duplicateURLs: data.duplicateURLs,
        thumbnailCache: data.thumbnailCache
    )

    return ImportSelectionView(
        model: model,
        onConfirm: { selectedURLs in
            // Return to confirmation sheet with selectedFiles set
            if case .confirmation(var draft) = importSheet {
                draft.selectedFiles = selectedURLs
                importSheet = .confirmation(draft)
            } else {
                importSheet = nil
            }
        },
        onCancel: {
            if case .confirmation(let draft) = importSheet {
                importSheet = .confirmation(draft)
            } else {
                importSheet = nil
            }
        }
    )
}
```

- [ ] **Step 5: Update confirmImport to pass selectedFiles**

Find `confirmImport` (line ~2711) and pass `draft.selectedFiles` through to `beginImportFolder`/`beginImportCard`:

```swift
private func confirmImport(_ draft: ImportConfirmationDraft) {
    importSheet = nil
    // ... existing setup ...
    if draft.mode == .folder {
        model.beginImportFolder(
            draft.sourceURL,
            evaluateAfterImport: draft.evaluateAfterImport,
            importNewOnly: draft.importNewOnly,
            autopilotAfterImport: draft.autopilotAfterImport,
            selectedFiles: draft.selectedFiles
        )
    } else {
        model.beginImportCard(
            // ... existing params ...
            selectedFiles: draft.selectedFiles
        )
    }
}
```

- [ ] **Step 6: Lift isImporting from import buttons**

Find the import buttons that use `!isImporting` to disable themselves (search for `isImporting` in the import button area). Change them to be always enabled. The `isImporting` guard stays only on:
- The confirm button in `importConfirmationSheet` (line ~1729): `isPrimaryEnabled: !isImporting && draft.canStartImport`
- The `beginImportFolder`/`beginImportCard` guard in `AppModel` (keeps the commit guard)

Find `isImporting` usages in LibraryGridView (line ~74, ~92). The `.onChange(of: model.isImporting)` for draining pending imports stays. The `isImporting` variable used to disable import buttons should be removed.

Search for the toolbar import buttons (menu items) and remove any `!isImporting` / `.disabled(isImporting)` modifiers on them.

- [ ] **Step 7: Add pending-queue count to import progress**

Find the import progress display (search for import progress card / activity status). Add pending count:

```swift
if !model.pendingImportFolders.isEmpty {
    Text("Next: \(model.pendingImportFolders.count) folder\(model.pendingImportFolders.count == 1 ? "" : "s") queued")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Add near the import progress indicator.

- [ ] **Step 8: Update presentImportConfirmation**

Find `presentImportConfirmation` (line ~2613) and update to set `importSheet` instead of `importConfirmationDraft`:

```swift
private func presentImportConfirmation(_ draft: ImportConfirmationDraft) {
    var draft = draft
    draft.autopilotAfterImport = model.autopilotEnabled
    importSheet = .confirmation(draft)
}
```

- [ ] **Step 9: Update all references to importConfirmationDraft**

Search for all references to `importConfirmationDraft` in LibraryGridView.swift and update them to use `importSheet`:
```bash
grep -n "importConfirmationDraft" Sources/TeststripApp/LibraryGridView.swift | head -20
```

For places that read the draft (e.g., in `chooseImportDestinationOverride`, `chooseImportSecondCopyDestination`), extract from the enum:
```swift
guard case .confirmation(var draft) = importSheet else { return }
draft.destinationOverride = ...
importSheet = .confirmation(draft)
```

- [ ] **Step 10: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 0 failures

- [ ] **Step 11: Build release and smoke test**

Run: `swift build -c release --product TeststripApp 2>&1 | tail -3`
Expected: Build succeeds

- [ ] **Step 12: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: wire Review & Select button, lift isImporting from pickers, add queue visibility"
```

---

## Task 10: End-to-end scenario

**Files:**
- Create: `test/scenarios/import-selection-window.md`

**Interfaces:**
- Consumes: All prior tasks

- [ ] **Step 1: Write the scenario card**

```markdown
# Import Selection Window

## Setup
- Fresh isolated launch with `--smoke` (24 synthetic photos)
- Catalog at `$ISOLATED/Teststrip/catalog.sqlite`

## Steps

### 1. Open import folder picker
- Click Import ▸ Folder…
- Select the smoke-seeded directory
- Confirmation sheet appears with "Import N Photos" button

### 2. Open Review & Select
- Click "Review & Select…" button in the confirmation sheet
- Selection window appears with thumbnail grid
- All thumbnails render (24 cells visible)
- Filter bar shows: All | New | Duplicates
- Footer shows "24 of 24 selected"

### 3. Filter to New only
- Click "New" in the filter bar
- Grid shows only non-duplicate photos
- Click "All" to return to full view

### 4. Deselect photos
- Click a thumbnail to deselect it
- Footer updates: "23 of 24 selected"
- Primary button updates: "Import 23 Photos"

### 5. Confirm import with selection
- Click "Import 23 Photos"
- Selection sheet dismisses, returns to confirmation sheet
- Primary button reads "Import 23 Photos"
- Click "Import 23 Photos" to confirm
- Import runs, progress card shows

### 6. Verify catalog ground truth
- Query catalog: SELECT COUNT(*) FROM assets
- Expect 23 (not 24 — one was deselectedd)
- Verify no micro preview generation pending:
  SELECT COUNT(*) FROM preview_generation_queue WHERE level = 'micro'
  -- Should be 0 if thumbnails were promoted

### 7. Verify thumbnail promotion
- Check PreviewCache directory for micro.jpg files
- At least some micro previews should exist
- Verify temp cache directory was cleaned up

## Cleanup
- Close the app
- Verify no temp thumbnail directories remain in the system temp directory
```

- [ ] **Step 2: Run the scenario in the VM**

Run: `script/vm_scenario_run.sh setup && script/vm_scenario_run.sh sync && script/vm_scenario_run.sh launch && script/vm_scenario_run.sh ax -- --scenario test/scenarios/import-selection-window.md`

Follow the scenario testing harness in `test/scenarios/README.md`.

- [ ] **Step 3: Commit**

```bash
git add test/scenarios/import-selection-window.md
git commit -m "test: add import selection window end-to-end scenario"
```

---

## Self-Review

### Spec coverage

| Spec section | Task(s) |
|---|---|
| §1 Pre-Ingest Thumbnail Pipeline (temp cache, ImageIO opts, concurrent rendering, promotion) | Tasks 1, 2, 5 |
| §2 Selection Window UI (lazy grid, filter bar, select all/none, Review & Select button) | Tasks 3, 4, 8, 9 |
| §3 Import Queue (serial ingest, concurrent review, lift isImporting, queue visibility) | Tasks 7, 9 |
| §4 Data Flow (scan → review → selected files → ingest with filter → promote → cleanup) | Tasks 3, 5, 6, 7 |
| §5 Code Modifications | Tasks 1-9 |
| §6 Testing | Task 10 |

### Placeholder scan

No placeholders found. All steps contain actual code.

### Type consistency

- `PreIngestThumbnailCache.directoryURL: URL` — used in Task 6 (`preIngestThumbnails?.path`) and Task 7 (`preIngestThumbnailCache?.directoryURL`)
- `PreIngestThumbnailCache.thumbnailURL(for:)` — changed from `private` to `public` in Task 2, used in Task 2 and Task 8
- `selectedFiles: Set<URL>?` — consistent across ImportConfirmationDraft (Task 4), LibraryImportService (Task 5), WorkerCommand (Task 6), AppModel (Task 7)
- `preIngestThumbnailCache: PreIngestThumbnailCache?` — consistent across LibraryImportService (Task 5), factory typealiases (Task 7)
- `preIngestThumbnails: URL?` — consistent across WorkerCommand (Task 6), AppModel (Task 7)
- `ImportSourceSummary.fileURLs: [URL]` — produced in Task 3, consumed in Task 8 and Task 9
- `ImportDedupPreview.duplicateURLs: Set<URL>` — produced in Task 3, consumed in Task 8 and Task 9
- `ImportSelectionEntry` — defined in Task 8, used in Task 9
- `ImportSelectionModel` — defined in Task 8, used in Task 9
- `ImportSelectionFilter` — defined in Task 8, used in Task 9
