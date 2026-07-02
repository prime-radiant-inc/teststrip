# Teststrip Real Import Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS app open a real local catalog, add an existing image folder in place, generate cached grid previews, and show real imported assets in the library grid.

**Architecture:** Keep the existing catalog, ingest, and preview pieces. Add one small core orchestration service for "add folder and render grid previews", then add a small app catalog runtime object that owns the repository/cache/import service. The SwiftUI shell stays simple: import folder button, catalog-backed asset list, preview thumbnails, and honest status/errors.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/Observation, SQLite catalog, ImageIO preview rendering.

---

## Scope

This plan intentionally does not add map/geodata, watched folders, worker supervision, agent review UI, face recognition, smart collections, or polished culling. The first useful loop is import/library/previews.

## File Structure

- Modify: `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`
  - Expose a public static supported extension set so app composition and ingest defaults do not duplicate format lists.
- Modify: `Tests/TeststripCoreTests/DecodeRegistryTests.swift`
  - Prove the public supported set contains common formats and drives `canDecode`.
- Modify: `Tests/TeststripCoreTests/TestSupport.swift`
  - Add a reusable real JPEG writer for ImageIO tests.
- Modify: `Tests/TeststripCoreTests/PreviewRendererTests.swift`
  - Reuse the shared JPEG helper.
- Create: `Sources/TeststripCore/Ingest/LibraryImportService.swift`
  - Add folder in place, catalog assets, render grid previews, and report per-asset preview failures without rolling back catalog writes.
- Create: `Tests/TeststripCoreTests/LibraryImportServiceTests.swift`
  - Test cataloging, preview generation, preview failure handling, and reimport identity preservation.
- Create: `Sources/TeststripApp/AppCatalog.swift`
  - Own app catalog paths, repository, preview cache, and import service composition.
- Modify: `Sources/TeststripApp/AppModel.swift`
  - Store optional catalog runtime, reload assets, import folders, expose cached preview URL lookup, and keep demo/test constructors.
- Create: `Tests/TeststripAppTests/AppCatalogTests.swift`
  - Test default path construction and loading an empty/new catalog without touching the user's real Application Support directory.
- Modify: `Tests/TeststripAppTests/AppModelTests.swift`
  - Add an import/reload test using a temp catalog and generated JPEG.
- Modify: `Sources/TeststripApp/LibraryGridView.swift`
  - Add import folder file picker, status/error text, cached thumbnail rendering, and existing rating/flag overlays.
- Modify: `Sources/TeststripApp/main.swift`
  - Initialize from the default catalog runtime instead of demo data.

## Task 1: Expose ImageIO Supported Extensions

**Files:**
- Modify: `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`
- Modify: `Tests/TeststripCoreTests/DecodeRegistryTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `DecodeRegistryTests`:

```swift
func testImageIOSupportedExtensionsArePublicForIngestComposition() {
    XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("jpg"))
    XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("dng"))
    XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("raf"))
}

func testImageIOCanDecodeUsesSharedSupportedExtensions() {
    let provider = ImageIODecodeProvider()

    for fileExtension in ImageIODecodeProvider.supportedExtensions {
        XCTAssertTrue(provider.canDecode(url: URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")))
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter DecodeRegistryTests --scratch-path /tmp/teststrip-real-import-task1
```

Expected: fail because `supportedExtensions` is not public.

- [ ] **Step 3: Implement the minimal API**

In `ImageIODecodeProvider`:

```swift
public static let supportedExtensions: Set<String> = [
    "jpg", "jpeg", "heic", "tif", "tiff", "png",
    "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf"
]

private let extensions = Self.supportedExtensions
```

- [ ] **Step 4: Run the focused tests and commit**

Run:

```bash
swift test --filter DecodeRegistryTests --scratch-path /tmp/teststrip-real-import-task1
```

Expected: pass.

Commit:

```bash
git add Sources/TeststripCore/Decode/ImageIODecodeProvider.swift Tests/TeststripCoreTests/DecodeRegistryTests.swift
git commit -m "feat: expose ImageIO ingest extensions"
```

## Task 2: Add Core Library Import Service

**Files:**
- Modify: `Tests/TeststripCoreTests/TestSupport.swift`
- Modify: `Tests/TeststripCoreTests/PreviewRendererTests.swift`
- Create: `Sources/TeststripCore/Ingest/LibraryImportService.swift`
- Create: `Tests/TeststripCoreTests/LibraryImportServiceTests.swift`

- [ ] **Step 1: Move the JPEG test helper**

Add this helper to `TestSupport.swift`:

```swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension TestDirectories {
    static func writeTestJPEG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create test bitmap context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create test jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write test jpeg")
        }
    }
}
```

Update `PreviewRendererTests` to call `TestDirectories.writeTestJPEG(...)` and remove the private duplicate helper.

- [ ] **Step 2: Write failing service tests**

Create `LibraryImportServiceTests.swift` with tests for:

```swift
func testAddFolderCatalogsSupportedImagesAndGeneratesGridPreview() throws
func testAddFolderKeepsCatalogedAssetWhenPreviewRenderFails() throws
func testReimportPreservesAssetIdentityMetadataAndRefreshesPreview() throws
```

Use real temporary directories, real SQLite, and real ImageIO JPEGs.

- [ ] **Step 3: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter LibraryImportServiceTests --scratch-path /tmp/teststrip-real-import-task2
```

Expected: fail because `LibraryImportService` does not exist.

- [ ] **Step 4: Implement the service**

Create `LibraryImportService.swift`:

```swift
public struct LibraryPreviewFailure: Equatable, Sendable {
    public var assetID: AssetID
    public var sourceURL: URL
    public var message: String
}

public struct LibraryImportResult: Sendable {
    public var importedAssets: [Asset]
    public var previewFailures: [LibraryPreviewFailure]
}

public struct LibraryImportService: Sendable {
    public var ingestService: IngestService
    public var previewCache: PreviewCache
    public var renderer: PreviewRenderer

    public func addFolderInPlace(_ root: URL, repository: CatalogRepository) throws -> LibraryImportResult {
        let assets = try ingestService.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        var failures: [LibraryPreviewFailure] = []
        for asset in assets {
            do {
                try renderer.render(
                    sourceURL: asset.originalURL,
                    level: .grid,
                    destinationURL: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
                )
            } catch {
                failures.append(LibraryPreviewFailure(assetID: asset.id, sourceURL: asset.originalURL, message: error.localizedDescription))
            }
        }
        return LibraryImportResult(importedAssets: assets, previewFailures: failures)
    }
}
```

Add an initializer with defaults for all three stored values.

- [ ] **Step 5: Run focused tests and commit**

Run:

```bash
swift test --filter LibraryImportServiceTests --scratch-path /tmp/teststrip-real-import-task2
swift test --filter PreviewRendererTests --scratch-path /tmp/teststrip-real-import-task2-preview
```

Expected: pass.

Commit:

```bash
git add Sources/TeststripCore/Ingest/LibraryImportService.swift Tests/TeststripCoreTests/LibraryImportServiceTests.swift Tests/TeststripCoreTests/TestSupport.swift Tests/TeststripCoreTests/PreviewRendererTests.swift
git commit -m "feat: add catalog import preview service"
```

## Task 3: Add App Catalog Runtime And Model Import

**Files:**
- Create: `Sources/TeststripApp/AppCatalog.swift`
- Modify: `Sources/TeststripApp/AppModel.swift`
- Create: `Tests/TeststripAppTests/AppCatalogTests.swift`
- Modify: `Tests/TeststripAppTests/AppModelTests.swift`

- [ ] **Step 1: Write app runtime tests**

Add tests that:

```swift
func testDefaultPathsLiveUnderApplicationSupportTeststrip() throws
func testLoadModelCreatesEmptyCatalogAndPreviewCache() throws
func testImportFolderReloadsAssetsAndExposesGridPreviewURL() throws
```

Use injected temporary application-support roots. Do not touch `~/Library/Application Support`.

- [ ] **Step 2: Run app tests and verify they fail**

Run:

```bash
swift test --filter TeststripAppTests --scratch-path /tmp/teststrip-real-import-task3
```

Expected: fail because `AppCatalog` and import model APIs do not exist.

- [ ] **Step 3: Implement `AppCatalog`**

Create a small app composition object:

```swift
public struct AppCatalogPaths: Equatable {
    public var root: URL
    public var catalogURL: URL
    public var previewCacheRoot: URL
}

public struct AppCatalog {
    public var paths: AppCatalogPaths
    public var repository: CatalogRepository
    public var previewCache: PreviewCache
    public var importService: LibraryImportService

    public static func defaultPaths(applicationSupportDirectory: URL) -> AppCatalogPaths
    public static func open(paths: AppCatalogPaths) throws -> AppCatalog
    public static func loadModel(paths: AppCatalogPaths) throws -> AppModel
}
```

Use `ImageIODecodeProvider.supportedExtensions` for the default `FolderScanner`.

- [ ] **Step 4: Extend `AppModel`**

Add:

```swift
private var catalog: AppCatalog?
public var statusMessage: String?
public var errorMessage: String?

public static func load(catalog: AppCatalog) throws -> AppModel
public func reload() throws
@discardableResult public func importFolder(_ folderURL: URL) throws -> LibraryImportResult
public func gridPreviewURL(for assetID: AssetID) -> URL?
```

Keep `demo()` and existing `load(repository:)` working for current tests.

- [ ] **Step 5: Run app tests and commit**

Run:

```bash
swift test --filter TeststripAppTests --scratch-path /tmp/teststrip-real-import-task3
```

Expected: pass.

Commit:

```bash
git add Sources/TeststripApp/AppCatalog.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppCatalogTests.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: open app catalog and import folders"
```

## Task 4: Wire The SwiftUI Import Loop

**Files:**
- Modify: `Sources/TeststripApp/main.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift`
- Modify: `Sources/TeststripApp/SidebarView.swift` only if needed for counts/status.

- [ ] **Step 1: Write or update lightweight app model tests**

If needed, add assertions for status/error strings around import success and preview failure. Do not snapshot SwiftUI output.

- [ ] **Step 2: Initialize from real catalog**

Change `main.swift` to load:

```swift
@State private var model: AppModel

init() {
    do {
        let paths = try AppCatalog.defaultPaths()
        _model = State(initialValue: try AppCatalog.loadModel(paths: paths))
    } catch {
        fatalError("Unable to open Teststrip catalog: \(error)")
    }
}
```

- [ ] **Step 3: Add import folder UI**

In `LibraryGridView`, add a toolbar button and folder picker:

```swift
@State private var isImportingFolder = false

.toolbar {
    Button {
        isImportingFolder = true
    } label: {
        Label("Import", systemImage: "square.and.arrow.down")
    }
}
.fileImporter(isPresented: $isImportingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
    // start security-scoped access, call model.importFolder, show model status/error.
}
```

- [ ] **Step 4: Render cached grid previews**

In each grid cell, if `model.gridPreviewURL(for:)` returns an existing URL and `NSImage(contentsOf:)` succeeds, render `Image(nsImage:)`; otherwise render the existing placeholder.

- [ ] **Step 5: Build and commit**

Run:

```bash
swift build --scratch-path /tmp/teststrip-real-import-task4-build
swift test --scratch-path /tmp/teststrip-real-import-task4-test
```

Expected: both pass.

Commit:

```bash
git add Sources/TeststripApp/main.swift Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/SidebarView.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: wire app folder import loop"
```

## Task 5: Manual Smoke

**Files:** none unless a small bug is found.

- [ ] **Step 1: Create a disposable image folder**

Use a temporary folder with at least one JPEG/PNG.

- [ ] **Step 2: Run the app**

Run:

```bash
swift run --scratch-path /tmp/teststrip-real-import-run TeststripApp
```

Expected: app opens with an empty or existing catalog.

- [ ] **Step 3: Import the folder**

Use the Import button, select the disposable folder, and confirm imported assets appear with previews.

- [ ] **Step 4: Report usability honestly**

Report what works, what is still rough, and the exact command to run the app.
