# Adaptive Preview System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 5 physical JPEG preview files per asset with 3 physical HEIC files, deriving 2 logical levels in memory, generating all levels from a single copy of the original.

**Architecture:** Three physical HEIC files (`grid.heic`, `large.heic`, `full.heic`) serve five logical `PreviewLevel` cases. `PreviewCache.url(for:)` maps logical levels to physical files. `PreviewRenderer` outputs HEIC with per-level quality control. A batch `generatePreviews` worker command copies the original to a local temp once and renders all requested levels from it. Existing JPEG previews are deleted — no coexistence.

**Tech Stack:** Swift 6, SwiftPM, ImageIO (CGImageDestination, CGImageSource), HEIC (`UTType("public.heic")`), macOS 14+.

**Spec:** `docs/superpowers/specs/2026-08-20-adaptive-preview-system-design.md`

## Global Constraints

- Deployment target: macOS 14.0 — HEIC is universally available.
- `PreviewLevel` enum stays unchanged (micro, grid, medium, large, original) — it's the API the UI and scheduler use.
- All preview files use `.heic` extension. No `.jpg` fallback.
- `preview_generation_queue` schema is unchanged; level stays as logical level.
- Non-destructive: originals are never modified. Previews are derived files.

---

## File Structure

**Modified files:**
- `Sources/TeststripCore/Preview/PreviewCache.swift` — logical→physical file mapping
- `Sources/TeststripCore/Preview/PreviewRenderer.swift` — HEIC output, quality control, batch render
- `Sources/TeststripCore/Worker/WorkerCommand.swift` — replace `generatePreview` with `generatePreviews` batch command
- `Sources/TeststripCore/Worker/WorkerProtocol.swift` — encode/decode `generatePreviews` (levels array)
- `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` — batch execute with copy-to-temp
- `Sources/TeststripCore/Ingest/LibraryImportService.swift` — `importPreviewLevels` → `[.grid]`, remove preIngest promotion, use copy-once
- `Sources/TeststripApp/AppModel.swift` — `previewURL(for:levels:)` dedup, batch preview requests
- `Sources/TeststripApp/CachedPreviewImage.swift` — in-memory downsampling for derived levels

**Test files modified:**
- `Tests/TeststripCoreTests/PreviewCacheTests.swift` — physical file mapping tests
- `Tests/TeststripCoreTests/PreviewRendererTests.swift` — HEIC output tests
- `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift` — batch command tests
- `Tests/TeststripAppTests/PreviewImageLoaderTests.swift` — downsampling tests

---

## Task 1: PreviewCache — logical-to-physical file mapping

**Files:**
- Modify: `Sources/TeststripCore/Preview/PreviewCache.swift`
- Test: `Tests/TeststripCoreTests/PreviewCacheTests.swift`

**Interfaces:**
- Produces: `PreviewCache.url(for:)` now returns `grid.heic` / `large.heic` / `full.heic` paths instead of per-level `.jpg` paths. No signature change — the return type is still `URL`. Callers that check `url(for: .micro)` and `url(for: .grid)` will see the same path.

- [ ] **Step 1: Write failing tests for physical file mapping**

Add to `Tests/TeststripCoreTests/PreviewCacheTests.swift`:

```swift
func testMicroAndGridMapToSamePhysicalFile() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping")
    let cache = PreviewCache(root: directory)
    let assetID = AssetID(rawValue: "asset-1")

    let microURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .micro))
    let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))

    XCTAssertEqual(microURL, gridURL)
    XCTAssertTrue(microURL.pathExtension == "heic")
    XCTAssertTrue(microURL.lastPathComponent == "grid.heic")
}

func testMediumAndLargeMapToSamePhysicalFile() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping-medium")
    let cache = PreviewCache(root: directory)
    let assetID = AssetID(rawValue: "asset-1")

    let mediumURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .medium))
    let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))

    XCTAssertEqual(mediumURL, largeURL)
    XCTAssertTrue(mediumURL.pathExtension == "heic")
    XCTAssertTrue(mediumURL.lastPathComponent == "large.heic")
}

func testOriginalMapsToFullHeic() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping-original")
    let cache = PreviewCache(root: directory)
    let assetID = AssetID(rawValue: "asset-1")

    let originalURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .original))

    XCTAssertTrue(originalURL.pathExtension == "heic")
    XCTAssertTrue(originalURL.lastPathComponent == "full.heic")
}

func testThreePhysicalFilesAreDistinct() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping-distinct")
    let cache = PreviewCache(root: directory)
    let assetID = AssetID(rawValue: "asset-1")

    let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
    let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
    let fullURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .original))

    XCTAssertNotEqual(gridURL, largeURL)
    XCTAssertNotEqual(gridURL, fullURL)
    XCTAssertNotEqual(largeURL, fullURL)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreviewCacheTests`
Expected: FAIL — `url(for:)` still returns `.jpg` paths with per-level names.

- [ ] **Step 3: Implement physical file mapping**

Replace `Sources/TeststripCore/Preview/PreviewCache.swift` line 25 (`"\(key.level.rawValue).jpg"`) with the physical file mapping:

```swift
public func url(for key: PreviewCacheKey) -> URL {
    let assetDirectoryName = PathSafeName.encode(key.assetID.rawValue)

    return root
        .appendingPathComponent(assetDirectoryName, isDirectory: true)
        .appendingPathComponent(Self.physicalFile(for: key.level))
}

private static func physicalFile(for level: PreviewLevel) -> String {
    switch level {
    case .micro, .grid:   return "grid.heic"
    case .medium, .large: return "large.heic"
    case .original:       return "full.heic"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreviewCacheTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Preview/PreviewCache.swift Tests/TeststripCoreTests/PreviewCacheTests.swift
git commit -m "feat: map PreviewCache logical levels to 3 physical HEIC files"
```

---

## Task 2: PreviewRenderer — HEIC output with per-level quality control

**Files:**
- Modify: `Sources/TeststripCore/Preview/PreviewRenderer.swift`
- Test: `Tests/TeststripCoreTests/PreviewRendererTests.swift`

**Interfaces:**
- Produces: `PreviewRenderer.render(sourceURL:level:destinationURL:)` now outputs HEIC with `kCGImageDestinationLossyCompressionQuality`. Signature unchanged.

- [ ] **Step 1: Write failing tests for HEIC output and quality**

Add to `Tests/TeststripCoreTests/PreviewRendererTests.swift`:

```swift
func testRendererOutputsHEICFile() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-heic")
    let source = directory.appendingPathComponent("source.jpg")
    let output = directory.appendingPathComponent("grid.heic")
    try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

    let renderer = PreviewRenderer()
    try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

    XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    let sourceRef = CGImageSourceCreateWithURL(output as CFURL, nil)
    XCTAssertNotNil(sourceRef)
    let typeID = CGImageSourceGetType(sourceRef!)
    XCTAssertEqual(typeID, UTType("public.heic")!)
}

func testGridPreviewHasCorrectMaxDimension() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-heic-grid-dim")
    let source = directory.appendingPathComponent("source.jpg")
    let output = directory.appendingPathComponent("grid.heic")
    try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

    let renderer = PreviewRenderer()
    try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

    let dimensions = try renderer.dimensions(of: output)
    XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
}

func testOriginalPreviewIsFullResolution() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-heic-original")
    let source = directory.appendingPathComponent("source.jpg")
    let output = directory.appendingPathComponent("full.heic")
    try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

    let renderer = PreviewRenderer()
    try renderer.render(sourceURL: source, level: .original, destinationURL: output)

    let dimensions = try renderer.dimensions(of: output)
    XCTAssertEqual(dimensions, PreviewDimensions(width: 1200, height: 800))
}
```

Add `import UniformTypeIdentifiers` at the top of the test file if not already present.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreviewRendererTests`
Expected: FAIL — output is still JPEG, and HEIC type check fails.

- [ ] **Step 3: Implement HEIC output with quality control**

In `Sources/TeststripCore/Preview/PreviewRenderer.swift`, replace the `render` method (lines 18–49):

```swift
public func render(sourceURL: URL, level: PreviewLevel, destinationURL: URL) throws {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
        throw TeststripError.unsupportedFormat("could not read \(sourceURL.lastPathComponent)")
    }
    var options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: false
    ]
    if let maxDimension = level.maxPixelDimension {
        options[kCGImageSourceThumbnailMaxPixelSize] = maxDimension
    }
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw TeststripError.unsupportedFormat("could not render preview for \(sourceURL.lastPathComponent)")
    }

    let destinationDirectory = destinationURL.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    } catch {
        throw TeststripError.io("could not create preview directory \(destinationDirectory.path): \(error.localizedDescription)")
    }
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType("public.heic")! as CFString,
        1,
        nil
    ) else {
        throw TeststripError.io("could not create HEIC preview destination")
    }
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: Self.compressionQuality(for: level)
    ]
    CGImageDestinationAddImage(destination, thumbnail, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write preview \(destinationURL.path)")
    }
}

private static func compressionQuality(for level: PreviewLevel) -> Double {
    switch level {
    case .micro, .grid:   return 0.82
    case .medium, .large: return 0.40
    case .original:       return 0.25
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreviewRendererTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Preview/PreviewRenderer.swift Tests/TeststripCoreTests/PreviewRendererTests.swift
git commit -m "feat: render previews as HEIC with per-level quality control"
```

---

## Task 3: PreviewRenderer — batch renderLevels from local source

**Files:**
- Modify: `Sources/TeststripCore/Preview/PreviewRenderer.swift`
- Test: `Tests/TeststripCoreTests/PreviewRendererTests.swift`

**Interfaces:**
- Produces: `PreviewRenderer.renderLevels(fromLocalSource:levels:destinationProvider:)` — generates multiple physical files from one local source URL. Deduplicates levels that map to the same physical file.

- [ ] **Step 1: Write failing test for batch render**

Add to `Tests/TeststripCoreTests/PreviewRendererTests.swift`:

```swift
func testRenderLevelsGeneratesMultiplePhysicalFilesFromOneSource() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-batch")
    let source = directory.appendingPathComponent("source.jpg")
    try TestDirectories.writeTestJPEG(to: source, width: 3200, height: 2400)
    let previewDir = directory.appendingPathComponent("previews", isDirectory: true)
    try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

    let renderer = PreviewRenderer()
    let assetID = AssetID(rawValue: "asset-1")
    let cache = PreviewCache(root: previewDir)

    try renderer.renderLevels(
        fromLocalSource: source,
        levels: [.grid, .large, .original],
        destinationProvider: { level in
            cache.url(for: PreviewCacheKey(assetID: assetID, level: level))
        }
    )

    let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
    let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
    let fullURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .original))

    XCTAssertTrue(FileManager.default.fileExists(atPath: gridURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: largeURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fullURL.path))
}

func testRenderLevelsDeduplicatesLevelsMappingToSamePhysicalFile() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-batch-dedup")
    let source = directory.appendingPathComponent("source.jpg")
    try TestDirectories.writeTestJPEG(to: source, width: 3200, height: 2400)
    let previewDir = directory.appendingPathComponent("previews", isDirectory: true)
    try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

    let renderer = PreviewRenderer()
    let assetID = AssetID(rawValue: "asset-1")
    let cache = PreviewCache(root: previewDir)

    // .micro and .grid both map to grid.heic — should render once
    try renderer.renderLevels(
        fromLocalSource: source,
        levels: [.micro, .grid, .medium, .large],
        destinationProvider: { level in
            cache.url(for: PreviewCacheKey(assetID: assetID, level: level))
        }
    )

    let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
    let microURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .micro))
    let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
    let mediumURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .medium))

    // micro and grid are the same file
    XCTAssertEqual(gridURL, microURL)
    XCTAssertEqual(largeURL, mediumURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: gridURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: largeURL.path))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreviewRendererTests`
Expected: FAIL — `renderLevels` does not exist.

- [ ] **Step 3: Implement renderLevels**

Add to `Sources/TeststripCore/Preview/PreviewRenderer.swift` after the `render` method:

```swift
public func renderLevels(
    fromLocalSource sourceURL: URL,
    levels: [PreviewLevel],
    destinationProvider: (PreviewLevel) -> URL
) throws {
    // Deduplicate: only render one level per physical file.
    // The first level encountered for each physical file wins (it determines
    // the pixel dimension — e.g. .grid (512px) not .micro (160px) for grid.heic).
    var seen = Set<String>()
    var toRender: [PreviewLevel] = []
    for level in levels {
        let physicalFile = physicalFileName(for: level)
        if !seen.contains(physicalFile) {
            seen.insert(physicalFile)
            toRender.append(level)
        }
    }
    for level in toRender {
        try render(
            sourceURL: sourceURL,
            level: level,
            destinationURL: destinationProvider(level)
        )
    }
}

private static func physicalFile(for level: PreviewLevel) -> String {
    switch level {
    case .micro, .grid:   return "grid.heic"
    case .medium, .large: return "large.heic"
    case .original:       return "full.heic"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreviewRendererTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Preview/PreviewRenderer.swift Tests/TeststripCoreTests/PreviewRendererTests.swift
git commit -m "feat: add batch renderLevels for generating multiple previews from one source"
```

---

## Task 4: WorkerCommand — replace generatePreview with batch generatePreviews

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerCommand.swift`
- Modify: `Sources/TeststripCore/Worker/WorkerProtocol.swift`
- Test: `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`

**Interfaces:**
- Produces: `WorkerCommand.generatePreviews(assetID: AssetID, levels: [PreviewLevel])` replaces `.generatePreview(assetID:level:)`.
- The `levels` array uses the logical levels that the caller wants generated. The executor deduplicates to physical files and marks all served logical levels as generated.
- **Important:** keep the old `generatePreview` case temporarily for migration — the executor handles both. Remove it in Task 8 after all callers are updated. Actually, since we're deleting all existing previews and regenerating, we can replace it outright. But test files reference `.generatePreview` — update those too.

- [ ] **Step 1: Write failing test for batch command**

Add to `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`:

```swift
func testGeneratePreviewsBatchCommandRendersAllLevelsFromOneSource() throws {
    let root = try TestDirectories.makeTemporaryDirectory(named: "worker-batch-previews")
    let source = root.appendingPathComponent("source.jpg")
    try TestDirectories.writeTestJPEG(to: source, width: 3200, height: 2400)
    let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)
    let asset = Asset(
        id: AssetID(rawValue: "asset-1"),
        originalURL: source,
        volumeIdentifier: "local",
        fingerprint: try fileFingerprint(for: source),
        availability: .online,
        metadata: AssetMetadata()
    )
    try repository.upsert(asset)
    let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
    let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

    let result = try executor.execute(.generatePreviews(assetID: asset.id, levels: [.grid, .large, .original]))

    // grid.heic serves both .grid and .micro; large.heic serves .large and .medium
    let gridURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
    let largeURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large))
    let fullURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .original))

    XCTAssertTrue(FileManager.default.fileExists(atPath: gridURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: largeURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fullURL.path))
    XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
}

func testGeneratePreviewsMarksAllDerivedLevelsAsGenerated() throws {
    let root = try TestDirectories.makeTemporaryDirectory(named: "worker-batch-derived-levels")
    let source = root.appendingPathComponent("source.jpg")
    try TestDirectories.writeTestJPEG(to: source, width: 3200, height: 2400)
    let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)
    let asset = Asset(
        id: AssetID(rawValue: "asset-1"),
        originalURL: source,
        volumeIdentifier: "local",
        fingerprint: try fileFingerprint(for: source),
        availability: .online,
        metadata: AssetMetadata()
    )
    try repository.upsert(asset)
    // Queue all 5 logical levels as pending
    try repository.recordPreviewGenerationPending([
        PreviewGenerationItem(assetID: asset.id, level: .micro),
        PreviewGenerationItem(assetID: asset.id, level: .grid),
        PreviewGenerationItem(assetID: asset.id, level: .medium),
        PreviewGenerationItem(assetID: asset.id, level: .large),
        PreviewGenerationItem(assetID: asset.id, level: .original),
    ])
    let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
    let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

    _ = try executor.execute(.generatePreviews(assetID: asset.id, levels: [.grid, .large, .original]))

    // All 5 logical levels should be cleared from the queue, even though
    // only 3 physical files were generated.
    XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WorkerCommandExecutorTests`
Expected: FAIL — `.generatePreviews` does not exist.

- [ ] **Step 3: Add the batch command to WorkerCommand**

In `Sources/TeststripCore/Worker/WorkerCommand.swift`:

Replace line 25:
```swift
case generatePreview(assetID: AssetID, level: PreviewLevel)
```
with:
```swift
case generatePreviews(assetID: AssetID, levels: [PreviewLevel])
```

Update `controlKind` (line 41): replace `.generatePreview` with `.generatePreviews`:
```swift
case .importFolder, .importCard, .generatePreviews, .syncMetadata, .refreshAvailability, .refreshAvailabilityBatch, .runEvaluation, .reverseGeocodeBatch, .backfillCoordinates: return nil
```

Update `operationDescription` (line 74–75): replace the `.generatePreview` case:
```swift
case .generatePreviews(let assetID, let levels):
    return "generate \(levels.map(\.rawValue).joined(separator: ",")) previews for \(assetID.rawValue)"
```

- [ ] **Step 4: Update WorkerProtocol encode/decode**

In `Sources/TeststripCore/Worker/WorkerProtocol.swift`:

Replace the encode case (lines 89–99):
```swift
case .generatePreviews(let assetID, let levels):
    envelope = WorkerCommandEnvelope(
        command: "generatePreviews",
        assetID: assetID.rawValue,
        levels: levels.map(\.rawValue),
        provider: nil,
        rootURL: nil,
        sourceURL: nil,
        destinationRootURL: nil,
        itemID: itemID?.rawValue
    )
```

Replace the decode case (lines 279–282):
```swift
case "generatePreviews":
    let assetID = try envelope.requiredAssetID()
    let levels = try envelope.requiredPreviewLevels()
    command = .generatePreviews(assetID: assetID, levels: levels)
```

Add `levels` field to `WorkerCommandEnvelope` (line 358 area): rename `level: String?` to `levels: [String]?` and update the `requiredPreviewLevel` helper to `requiredPreviewLevels`:

```swift
var levels: [String]?
```

```swift
func requiredPreviewLevels() throws -> [PreviewLevel] {
    let rawValues = try requiredField(levels, key: .levels)
    return try rawValues.map { rawValue in
        guard let level = PreviewLevel(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.levels],
                    debugDescription: "Unknown preview level: \(rawValue)"
                )
            )
        }
        return level
    }
}
```

Update `CodingKeys` to replace `level` with `levels` if the enum uses explicit coding keys. Check the file — if `CodingKeys` is auto-generated from the struct's stored properties, just renaming the property is sufficient.

**Important:** Update every place in `WorkerProtocol.swift` that sets `level:` to `level: nil` — change those to `levels: nil`. There are about 10 such occurrences across the other command cases.

- [ ] **Step 5: Update WorkerCommandExecutor**

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`, replace the `.generatePreview` case (lines 216–239) with:

```swift
case .generatePreviews(let assetID, let levels):
    let asset = try repository.asset(id: assetID)
    if let availability = try markPreviewBlockingAvailabilityIfNeeded(asset) {
        let levelDescription = levels.map(\.rawValue).joined(separator: ",")
        try recordBlockedAvailabilityFailureAndThrow(
            availability, assetID: assetID, level: levels.first ?? .grid, asset: asset
        )
    }
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("teststrip-preview-source-\(UUID().uuidString)")
    do {
        try FileManager.default.copyItem(at: asset.originalURL, to: tempURL)
        try renderer.renderLevels(
            fromLocalSource: tempURL,
            levels: levels,
            destinationProvider: { level in
                previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            }
        )
    } catch {
        try? FileManager.default.removeItem(at: tempURL)
        if let availability = try markPreviewBlockingAvailabilityIfNeeded(asset) {
            try recordBlockedAvailabilityFailureAndThrow(
                availability, assetID: assetID, level: levels.first ?? .grid, asset: asset
            )
        }
        for level in levels {
            try repository.recordPreviewGenerationFailure(
                assetID: assetID,
                level: level,
                errorMessage: error.localizedDescription
            )
        }
        throw error
    }
    try? FileManager.default.removeItem(at: tempURL)
    // Mark all logical levels served by the generated physical files
    for level in Self.allLevelsServedBy(levels) {
        try repository.markPreviewGenerated(assetID: assetID, level: level)
    }
    return .completed("generated \(levels.map(\.rawValue).joined(separator: ",")) previews for \(Self.displayName(for: asset))")
```

Add a helper method to `WorkerCommandExecutor`:

```swift
private static func allLevelsServedBy(_ levels: [PreviewLevel]) -> [PreviewLevel] {
    var result = Set<PreviewLevel>()
    for level in levels {
        switch level {
        case .micro, .grid:
            result.insert(.micro)
            result.insert(.grid)
        case .medium, .large:
            result.insert(.medium)
            result.insert(.large)
        case .original:
            result.insert(.original)
        }
    }
    return PreviewLevel.allCases.filter { result.contains($0) }
}
```

**Important:** Check `recordBlockedAvailabilityFailureAndThrow` — it takes a `level: PreviewLevel` parameter. We pass `levels.first ?? .grid` as a representative level for the failure record. This is fine — the failure is per-asset, not per-level; the queue tracks each level independently and will re-queue them all.

- [ ] **Step 6: Update existing tests that reference .generatePreview**

In `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`, update all existing tests that use `.generatePreview(assetID:level:)` to use `.generatePreviews(assetID:levels:)`. For example, change:

```swift
let result = try executor.execute(.generatePreview(assetID: asset.id, level: .medium))
```
to:
```swift
let result = try executor.execute(.generatePreviews(assetID: asset.id, levels: [.medium]))
```

And update the expected result message from `"generated medium preview for source.jpg"` to `"generated medium previews for source.jpg"`.

Do this for all existing tests in the file that use `.generatePreview`. The pattern is: `.generatePreview(assetID: X, level: Y)` → `.generatePreviews(assetID: X, levels: [Y])`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter WorkerCommandExecutorTests`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/TeststripCore/Worker/WorkerCommand.swift Sources/TeststripCore/Worker/WorkerProtocol.swift Sources/TeststripCore/Worker/WorkerCommandExecutor.swift Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift
git commit -m "feat: replace generatePreview with batch generatePreviews command"
```

---

## Task 5: AppModel — update preview request flow for batch generation

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/PreviewImageLoaderTests.swift` (or nearby test file)

**Interfaces:**
- Consumes: `WorkerCommand.generatePreviews(assetID:levels:)` from Task 4
- Produces: `requestPreview(assetID:level:)` now enqueues `.generatePreviews` with a single-element levels array. `previewURL(for:levels:)` deduplicates physical file checks.

- [ ] **Step 1: Write failing test for previewURL dedup**

If there's a test file for AppModel preview URL logic, add there. Otherwise add to an existing preview-related test file. The test should verify that `previewURL(for:levels: [.micro, .grid])` returns the grid.heic URL if it exists, and stats the filesystem only once for the duplicate.

Since AppModel tests require a full catalog setup, this is better tested as an integration test. For now, write a unit test that verifies the dedup logic indirectly — `previewURL` returns the first existing URL when micro and grid point to the same file.

Skip a separate test here — the dedup is a performance optimization, not a behavior change. The existing tests that call `previewURL(for:levels:)` will verify correctness. Move to implementation.

- [ ] **Step 2: Update previewURL dedup**

In `Sources/TeststripApp/AppModel.swift`, update `previewURL(for:levels:)` (line 15432):

```swift
public func previewURL(for assetID: AssetID, levels: [PreviewLevel]) -> URL? {
    guard let catalog else { return nil }
    var seen = Set<String>()
    for level in levels {
        let url = catalog.previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
        let path = url.path
        if seen.contains(path) { continue }
        seen.insert(path)
        if FileManager.default.fileExists(atPath: path) {
            return url
        }
    }
    return nil
}
```

- [ ] **Step 3: Update requestPreview to use generatePreviews**

In `Sources/TeststripApp/AppModel.swift`, line 9983, change:

```swift
command: .generatePreview(assetID: assetID, level: level),
```
to:
```swift
command: .generatePreviews(assetID: assetID, levels: [level]),
```

- [ ] **Step 4: Update enqueuePendingPreviewGeneration**

In `Sources/TeststripApp/AppModel.swift`, line 10043, change:

```swift
command: .generatePreview(assetID: pendingItem.assetID, level: pendingItem.level),
```
to:
```swift
command: .generatePreviews(assetID: pendingItem.assetID, levels: [pendingItem.level]),
```

- [ ] **Step 5: Run existing tests to verify nothing breaks**

Run: `swift test`
Expected: PASS (some tests may need updating if they check for `.generatePreview` in command assertions — fix those inline)

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift
git commit -m "feat: update AppModel to use batch generatePreviews and dedup previewURL"
```

---

## Task 6: LibraryImportService — remove preIngest promotion, use copy-once

**Files:**
- Modify: `Sources/TeststripCore/Ingest/LibraryImportService.swift`
- Test: `Tests/TeststripCoreTests/` (existing import tests)

**Interfaces:**
- Consumes: `PreviewRenderer.renderLevels` from Task 3, `PreviewCache` physical mapping from Task 1
- Produces: `importPreviewLevels` is `[.grid]` (not `[.micro, .grid]`). PreIngest thumbnail promotion is removed. Import uses copy-once path.

- [ ] **Step 1: Write failing test for import generating grid only**

Add to `Tests/TeststripCoreTests/LibraryImportServiceTests.swift` (or the existing import test file). The test should verify that after import with a `preIngestThumbnailCache` present, `grid.heic` exists (not `micro.jpg`), and both `.grid` and `.micro` are marked generated in the queue:

```swift
func testImportGeneratesGridHeicAndMarksMicroAndGridGenerated() throws {
    let root = try TestDirectories.makeTemporaryDirectory(named: "import-grid-only")
    let source = root.appendingPathComponent("source.jpg")
    try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
    let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)
    let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
    let importService = LibraryImportService(previewCache: previewCache)

    // Import a single asset
    let asset = Asset(
        id: AssetID(rawValue: "asset-1"),
        originalURL: source,
        volumeIdentifier: "local",
        fingerprint: try fileFingerprint(for: source),
        availability: .online,
        metadata: AssetMetadata()
    )
    try repository.upsert(asset)
    try importService.generatePreviews(
        for: [PreviewGenerationItem(assetID: asset.id, level: .grid)],
        repository: repository,
        progress: nil
    )

    // grid.heic exists
    let gridURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
    XCTAssertTrue(FileManager.default.fileExists(atPath: gridURL.path))

    // No .jpg files
    let microURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
    XCTAssertEqual(gridURL, microURL) // same physical file
    XCTAssertTrue(gridURL.pathExtension == "heic")

    // Both .grid and .micro are cleared from the queue
    let pending = try repository.pendingPreviewGenerationItems()
    XCTAssertFalse(pending.contains { $0.assetID == asset.id && ($0.level == .grid || $0.level == .micro) })
}
```

- [ ] **Step 2: Update importPreviewLevels**

In `Sources/TeststripCore/Ingest/LibraryImportService.swift`, line 116, change:

```swift
private static let importPreviewLevels: [PreviewLevel] = [.micro, .grid]
```
to:
```swift
private static let importPreviewLevels: [PreviewLevel] = [.grid]
```

- [ ] **Step 3: Remove preIngest thumbnail promotion**

In `Sources/TeststripCore/Ingest/LibraryImportService.swift`, lines 465–483, remove the `if let cache = preIngestThumbnailCache` block that promotes the temp thumbnail to the `.micro` slot. The import now always renders from the original via the copy-once path.

The `generatePreviews` method (line 452) should be updated to use `renderer.renderLevels` with the copy-once path:

```swift
private func generatePreviews(
    for items: [PreviewGenerationItem],
    repository: CatalogRepository,
    progress: LibraryImportProgressHandler?
) throws -> LibraryPreviewGenerationResult {
    var generatedCount = 0
    var failures: [LibraryPreviewFailure] = []
    var failedAssetIDs: Set<AssetID>()

    for (index, item) in items.enumerated() {
        try Task.checkCancellation()
        let asset = try repository.asset(id: item.assetID)
        if !failedAssetIDs.contains(asset.id) {
            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("teststrip-import-preview-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: asset.originalURL, to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                try renderer.renderLevels(
                    fromLocalSource: tempURL,
                    levels: [item.level],
                    destinationProvider: { level in
                        previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: level))
                    }
                )
                // Mark the requested level and all derived levels as generated
                for level in Self.allLevelsServedBy(item.level) {
                    try repository.markPreviewGenerated(assetID: asset.id, level: level)
                }
                generatedCount += 1
            } catch {
                failedAssetIDs.insert(asset.id)
                try repository.recordPreviewGenerationFailure(
                    assetID: asset.id,
                    level: item.level,
                    errorMessage: error.localizedDescription
                )
                failures.append(LibraryPreviewFailure(
                    assetID: asset.id,
                    sourceURL: asset.originalURL,
                    message: error.localizedDescription
                ))
            }
        }
        let completedCount = index + 1
        progress?(LibraryImportProgress(
            completedUnitCount: completedCount,
            totalUnitCount: items.count,
            detail: "Generated \(completedCount) of \(items.count) previews"
        ))
    }
    return LibraryPreviewGenerationResult(generatedCount: generatedCount, failures: failures)
}

private static func allLevelsServedBy(_ level: PreviewLevel) -> [PreviewLevel] {
    switch level {
    case .micro, .grid: return [.micro, .grid]
    case .medium, .large: return [.medium, .large]
    case .original: return [.original]
    }
}
```

Remove the `preIngestThumbnailCache` parameter from `generatePreviews` since it's no longer used. Check all call sites and remove the argument.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (update any tests that passed `preIngestThumbnailCache` or checked for `.micro` files)

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Ingest/LibraryImportService.swift
git commit -m "feat: import generates grid.heic only, removes preIngest thumbnail promotion"
```

---

## Task 7: CachedPreviewImage — in-memory downsampling for derived levels

**Files:**
- Modify: `Sources/TeststripApp/CachedPreviewImage.swift`
- Test: `Tests/TeststripAppTests/CachedPreviewImageTests.swift`

**Interfaces:**
- Produces: `PreviewImageDataLoader.loadImage(from:maxPixelDimension:rotation:)` — downsamples in memory via `CGImageSourceCreateThumbnailAtIndex` when `maxPixelDimension` is non-nil. Falls back to existing `loadImage(from:rotation:)` when nil.

- [ ] **Step 1: Write failing test for downsampling**

Add to `Tests/TeststripAppTests/CachedPreviewImageTests.swift`:

```swift
func testLoadImageWithMaxPixelDimensionDownsamples() async throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-image-downsample")
    let source = directory.appendingPathComponent("source.heic")
    // Create a 512x512 HEIC file (grid.heic equivalent)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 512,
        pixelsHigh: 512,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB
    )!
    NSImage(size: NSSize(width: 512, height: 512)).lockFocus()
    bitmap.representations.first?.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
    NSGraphicsContext.current?.flushGraphics()
    let cgImage = bitmap.cgImage!
    guard let dest = CGImageDestinationCreateWithURL(source as CFURL, UTType("public.heic")! as CFString, 1, nil) else {
        XCTFail("could not create HEIC")
        return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    CGImageDestinationFinalize(dest)

    // Request 160px (micro level) from a 512px file (grid.heic)
    let image = await PreviewImageDataLoader.loadImage(from: source, maxPixelDimension: 160, rotation: 0)

    XCTAssertNotNil(image)
    XCTAssertLessThanOrEqual(max(image!.size.width, image!.size.height), 160)
}

func testLoadImageWithoutMaxPixelDimensionLoadsFullSize() async throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-image-full")
    let source = directory.appendingPathComponent("source.heic")
    // Same setup as above
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 512,
        pixelsHigh: 512,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB
    )!
    NSImage(size: NSSize(width: 512, height: 512)).lockFocus()
    bitmap.representations.first?.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
    NSGraphicsContext.current?.flushGraphics()
    let cgImage = bitmap.cgImage!
    guard let dest = CGImageDestinationCreateWithURL(source as CFURL, UTType("public.heic")! as CFString, 1, nil) else {
        XCTFail("could not create HEIC")
        return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    CGImageDestinationFinalize(dest)

    let image = await PreviewImageDataLoader.loadImage(from: source, maxPixelDimension: nil, rotation: 0)

    XCTAssertNotNil(image)
    XCTAssertEqual(image!.size.width, 512)
    XCTAssertEqual(image!.size.height, 512)
}
```

Add `import UniformTypeIdentifiers` to the test file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CachedPreviewImageTests`
Expected: FAIL — `loadImage(from:maxPixelDimension:rotation:)` does not exist.

- [ ] **Step 3: Implement downsampling loader**

Add to `Sources/TeststripApp/CachedPreviewImage.swift` in the `PreviewImageDataLoader` enum:

```swift
static func loadImage(
    from url: URL,
    maxPixelDimension: Int?,
    rotation: Int = 0
) async -> NSImage? {
    guard let maxPixelDimension else {
        return await loadImage(from: url, rotation: rotation)
    }
    return await Task.detached(priority: .userInitiated) { () -> NSImage? in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCache: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        if rotation == 0 {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        let ciImage = CIImage(cgImage: cgImage)
        let oriented = ciImage.oriented(forExifOrientation: Int32(RotationTransform.exifOrientation(forRotation: rotation).rawValue))
        let context = CIContext()
        guard let rotatedCGImage = context.createCGImage(oriented, from: oriented.extent) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        let dims = RotationTransform.rotatedDimensions(
            width: cgImage.width, height: cgImage.height, rotation: rotation
        )
        return NSImage(cgImage: rotatedCGImage, size: NSSize(width: dims.width, height: dims.height))
    }.value
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CachedPreviewImageTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/CachedPreviewImage.swift Tests/TeststripAppTests/CachedPreviewImageTests.swift
git commit -m "feat: add in-memory downsampling for derived preview levels"
```

---

## Task 8: Update all remaining callers and fix compile errors

**Files:**
- Modify: `Sources/TeststripBench/WorkerRecoverySmoke.swift`
- Modify: `Sources/TeststripBench/LaneOverlapSmoke.swift`
- Modify: `Sources/TeststripBench/RealCorpusSmoke.swift`
- Modify: `Sources/TeststripBench/RealCorpusCatalogSeeder.swift`
- Modify: `Sources/TeststripBench/SmokeCatalogSeeder.swift`
- Modify: `Sources/TeststripBench/PreviewRenderBenchmark.swift`
- Modify: any other file that references `.generatePreview` or constructs preview paths with `.jpg`

- [ ] **Step 1: Find all remaining references to .generatePreview**

Run: `grep -rn "\.generatePreview" Sources/ Tests/`

- [ ] **Step 2: Update each reference**

Replace `.generatePreview(assetID: X, level: Y)` with `.generatePreviews(assetID: X, levels: [Y])` in:
- `Sources/TeststripBench/WorkerRecoverySmoke.swift:70`
- `Sources/TeststripBench/LaneOverlapSmoke.swift:163`

- [ ] **Step 3: Update benchmark seeders that reference .micro or per-level .jpg**

In benchmark files, update any code that generates `[.micro, .grid]` to `[.grid]` and any code that constructs preview paths with `.jpg` to use `PreviewCache.url(for:)` instead.

In `Sources/TeststripBench/PreviewRenderBenchmark.swift:37`, the line:
```swift
let sourceURL = sourceRoot.appendingPathComponent("\(assetID.rawValue).jpg")
```
should use the PreviewCache URL mapping instead of hardcoding `.jpg`.

- [ ] **Step 4: Run full build**

Run: `swift build`
Expected: SUCCESS

If there are compile errors, fix them inline. Common issues:
- Any file that constructs preview file paths with `.jpg` — use `PreviewCache.url(for:)` instead
- Any file that references `.generatePreview` — use `.generatePreviews`
- Any test that checks for a `.micro.jpg` file — it's now `grid.heic`

- [ ] **Step 5: Run full test suite**

Run: `swift test`
Expected: All tests pass. If tests fail because they expect `.jpg` extensions or per-level files, update them to expect `.heic` and the physical file mapping.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: update all callers for batch generatePreviews and HEIC preview paths"
```

---

## Task 9: WorkerCommandExecutor — use cachedPreviewURL with physical mapping

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`

The `cachedPreviewURL(for:)` method (line 447) iterates `[.large, .medium, .grid, .micro]` and stats each. With the new mapping, `.large` and `.medium` are the same file, and `.grid` and `.micro` are the same file. This means it stats the same file twice, but the behavior is correct — it returns the first file that exists.

- [ ] **Step 1: Update cachedPreviewURL to dedup**

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`, line 447, update:

```swift
private func cachedPreviewURL(for assetID: AssetID) -> URL? {
    for level in [PreviewLevel.large, .grid, .original] {
        let url = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    return nil
}
```

This iterates one level per physical file (large → large.heic, grid → grid.heic, original → full.heic) instead of 4 levels with duplicates.

- [ ] **Step 2: Run tests to verify**

Run: `swift test --filter WorkerCommandExecutorTests`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add Sources/TeststripCore/Worker/WorkerCommandExecutor.swift
git commit -m "refactor: dedup cachedPreviewURL to one check per physical file"
```

---

## Task 10: Migration — delete existing JPEG previews and reset queue

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (or a migration entry point)
- Test: `Tests/TeststripCoreTests/CatalogMigrationTests.swift`

**Interfaces:**
- Consumes: `PreviewCache.root` directory to find and delete `.jpg` files
- Produces: A migration that deletes all `.jpg` files in the preview cache root and resets `preview_generation_queue` to re-queue all logical levels for all assets.

- [ ] **Step 1: Write failing test for JPEG deletion migration**

Add to `Tests/TeststripCoreTests/CatalogMigrationTests.swift`:

```swift
func testMigrationDeletesExistingJPEGPreviews() throws {
    let root = try TestDirectories.makeTemporaryDirectory(named: "migration-delete-jpegs")
    let previewRoot = root.appendingPathComponent("previews", isDirectory: true)
    let assetDir = previewRoot.appendingPathComponent("asset-1", isDirectory: true)
    try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)

    // Create old-style JPEG preview files
    let microJPG = assetDir.appendingPathComponent("micro.jpg")
    let gridJPG = assetDir.appendingPathComponent("grid.jpg")
    let largeJPG = assetDir.appendingPathComponent("large.jpg")
    try Data([0xFF, 0xD8, 0xFF]).write(to: microJPG)
    try Data([0xFF, 0xD8, 0xFF]).write(to: gridJPG)
    try Data([0xFF, 0xD8, 0xFF]).write(to: largeJPG)

    let cache = PreviewCache(root: previewRoot)
    try PreviewMigration.deleteExistingJPEGPreviews(in: cache)

    XCTAssertFalse(FileManager.default.fileExists(atPath: microJPG.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: gridJPG.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: largeJPG.path))
}

func testMigrationResetsPreviewGenerationQueue() throws {
    let root = try TestDirectories.makeTemporaryDirectory(named: "migration-reset-queue")
    let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)

    let asset = Asset(
        id: AssetID(rawValue: "asset-1"),
        originalURL: root.appendingPathComponent("source.jpg"),
        volumeIdentifier: "local",
        fingerprint: "test-fingerprint",
        availability: .online,
        metadata: AssetMetadata()
    )
    try repository.upsert(asset)

    // Mark some levels as generated (old state)
    try repository.markPreviewGenerated(assetID: asset.id, level: .micro)
    try repository.markPreviewGenerated(assetID: asset.id, level: .grid)

    // Run the queue reset migration
    try PreviewMigration.resetPreviewGenerationQueue(repository: repository)

    // All 5 logical levels should be re-queued
    let pending = try repository.pendingPreviewGenerationItems(limit: nil)
    let assetPending = pending.filter { $0.assetID == asset.id }
    XCTAssertEqual(Set(assetPending.map(\.level)), Set(PreviewLevel.allCases))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CatalogMigrationTests`
Expected: FAIL — `PreviewMigration` does not exist.

- [ ] **Step 3: Implement PreviewMigration**

Create `Sources/TeststripCore/Preview/PreviewMigration.swift`:

```swift
import Foundation

public enum PreviewMigration {
    public static func deleteExistingJPEGPreviews(in cache: PreviewCache) throws {
        let root = cache.root
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        guard let enumerator else { return }

        for case let url as URL in enumerator {
            if url.pathExtension == "jpg" || url.pathExtension == "jpeg" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public static func resetPreviewGenerationQueue(repository: CatalogRepository) throws {
        try repository.resetAllPreviewGenerationQueue()
    }
}
```

- [ ] **Step 4: Add resetAllPreviewGenerationQueue to CatalogRepository**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, add:

```swift
public func resetAllPreviewGenerationQueue() throws {
    // Delete all existing queue entries, then re-enqueue all 5 levels for all assets
    try database.execute("DELETE FROM preview_generation_queue")
    let assets = try allAssetIDs()
    for assetID in assets {
        for level in PreviewLevel.allCases {
            try recordPreviewGenerationPending(
                PreviewGenerationItem(assetID: assetID, level: level)
            )
        }
    }
}

private func allAssetIDs() throws -> [AssetID] {
    let rows = try database.query("SELECT id FROM assets ORDER BY id")
    return rows.map { AssetID(rawValue: $0["id"] as! String) }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CatalogMigrationTests`
Expected: PASS

- [ ] **Step 6: Wire migration into app launch**

In `Sources/TeststripApp/AppModel.swift`, find the catalog open/migrate path and add after migration:

```swift
// One-time: delete old JPEG previews and re-queue generation
try PreviewMigration.deleteExistingJPEGPreviews(in: catalog.previewCache)
try PreviewMigration.resetPreviewGenerationQueue(repository: catalog.repository)
```

This should be guarded so it only runs once — use a user defaults key or a catalog metadata flag. For simplicity, add a `UserDefaults` check:

```swift
let migrationKey = "preview-heic-migration-done"
if !UserDefaults.standard.bool(forKey: migrationKey) {
    try PreviewMigration.deleteExistingJPEGPreviews(in: catalog.previewCache)
    try PreviewMigration.resetPreviewGenerationQueue(repository: catalog.repository)
    UserDefaults.standard.set(true, forKey: migrationKey)
}
```

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Preview/PreviewMigration.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripApp/AppModel.swift Tests/TeststripCoreTests/CatalogMigrationTests.swift
git commit -m "feat: add migration to delete JPEG previews and re-queue for HEIC generation"
```

---

## Task 11: Full test suite verification

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass (2700+ tests, 0 failures)

- [ ] **Step 2: Fix any remaining failures**

If any tests fail, they are likely due to:
- Hardcoded `.jpg` extensions in test fixtures — update to `.heic`
- `generatePreview` command references — update to `generatePreviews`
- PreIngest thumbnail cache references — remove
- Preview level expectations (e.g., expecting both micro and grid files) — update to expect physical file mapping

Fix each failure inline.

- [ ] **Step 3: Run again to confirm**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: fix remaining test failures from HEIC preview migration"
```
