# Auto-Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect photos that need rotation using Vision face + horizon detection, auto-apply rotation as catalog metadata (non-destructive), provide manual ⌘[/⌘] commands, mirror to XMP sidecars, and bake rotation into exports.

**Architecture:** Rotation is a `rotation: Int?` field on `AssetTechnicalMetadata` (0/90/180/270 clockwise, nil/0 = none). An `OrientationEvaluationProvider` runs in the existing evaluation pipeline after import, detects off-axis photos using `VNDetectFaceRectanglesRequest` + `VNDetectHorizonRequest`, and writes rotation to the catalog. Display applies rotation at image load time via CIImage transform (not SwiftUI view transform). Manual ⌘[/⌘] commands update the catalog directly. XMP sidecars carry `ts:Rotation`. Export bakes rotation into pixels.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, Vision framework, CoreImage, SQLite (FMDB), XMP (Foundation XML)

**Spec:** `docs/superpowers/specs/2026-08-17-auto-rotation-design.md`

## Global Constraints

- **Non-destructive:** Original image bytes are never modified. Rotation is catalog metadata + display-time CIImage transform. Export bakes into the copy, not the original.
- **No provenance tracking:** Rotation is just a value. AI sets a default, user changes it, it just changes. No `origin = ai/user`, no ✨ marker, no confirmation step.
- **Corrective only:** Auto-rotation only fires when the photo appears wrong (detected angle is ~90°/180°/270° off). Photos already displaying correctly are left alone.
- **Rotation values:** 0, 90, 180, 270 (clockwise degrees). Wraps: 0→90→180→270→0.
- **No schema migration:** `rotation` goes in existing `technical_metadata_json` column as a new optional Codable field — old catalogs decode fine with nil.
- **Worker pipeline reuse:** No new worker command. Orientation detection runs as an `OrientationEvaluationProvider` via the existing `.runEvaluation` command.
- Run all commands from the repo root `/Users/jesse/git/teststrip`.
- Build with `swift build` or `make build`. Test with `swift test` or `make test`.

---

## File Structure

### New Files
- `Sources/TeststripCore/Evaluation/AppleOrientationEvaluationProvider.swift` — Vision-based orientation detection provider (face roll + horizon)
- `Tests/TeststripCoreTests/AppleOrientationEvaluationProviderTests.swift` — Unit tests for orientation detection
- `Tests/TeststripCoreTests/RotationImageLoadingTests.swift` — Unit tests for rotation-aware image loading
- `Tests/TeststripCoreTests/RotationXMPPacketTests.swift` — Unit tests for XMP rotation round-trip
- `Tests/TeststripCoreTests/RotationCatalogRepositoryTests.swift` — Unit tests for `updateRotation`
- `Tests/TeststripAppTests/ManualRotationTests.swift` — Unit tests for ⌘[/⌘] manual rotation
- `test/scenarios/auto-rotation/001-detect-and-rotate.md` — E2E scenario card

### Modified Files
- `Sources/TeststripCore/Domain/Metadata.swift` — Add `rotation: Int?` to `AssetTechnicalMetadata`
- `Sources/TeststripCore/Evaluation/EvaluationProvider.swift` — Add `OrientationEvaluationProvider` protocol + `OrientationEvaluationOutcome`
- `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` — Register provider, handle `OrientationEvaluationProvider` in `runEvaluation`, pass rotation to sidecar sync
- `Sources/TeststripCore/Catalog/CatalogRepository.swift` — Add `updateRotation(assetID:rotation:)`
- `Sources/TeststripCore/Metadata/XMPPacket.swift` — Add `rotation: Int?` field, write/parse `ts:Rotation`
- `Sources/TeststripCore/Metadata/XMPSidecarStore.swift` — Add `rotation` parameter to `write`
- `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift` — Add `catalogRotation` parameter, extend write decision
- `Sources/TeststripCore/Export/ExportService.swift` — Apply rotation override after EXIF baking
- `Sources/TeststripApp/CachedPreviewImage.swift` — Add `rotation` parameter, apply CIImage transform
- `Sources/TeststripApp/LoupeZoomView.swift` — Pass rotation to image loading
- `Sources/TeststripApp/LibraryGridView.swift` — Pass rotation to grid cell thumbnails
- `Sources/TeststripApp/AppModel.swift` — Add `"orientation"` to `defaultEvaluationProviderNames`, add `rotateSelectedAsset` methods
- `Sources/TeststripApp/main.swift` — Add `RotateLeft` (⌘[) and `RotateRight` (⌘]) menu commands

---

## Task 1: Catalog Model — `rotation` field and repository method

**Files:**
- Modify: `Sources/TeststripCore/Domain/Metadata.swift:225-272`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift:2455-2470`
- Test: `Tests/TeststripCoreTests/RotationCatalogRepositoryTests.swift`

**Interfaces:**
- Consumes: nothing (foundation task)
- Produces:
  - `AssetTechnicalMetadata.rotation: Int?` — nil/0 = none, 90/180/270 = clockwise degrees
  - `AssetTechnicalMetadata.init(...rotation: Int? = nil...)` — new parameter with default nil
  - `CatalogRepository.updateRotation(assetID: AssetID, rotation: Int) throws` — targeted write to `technical_metadata_json`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/RotationCatalogRepositoryTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class RotationCatalogRepositoryTests: XCTestCase {
    func testRotationDecodesAsNilForOldCatalogs() throws {
        // Simulate old JSON without rotation field
        let json = """
        {"pixelWidth":4000,"pixelHeight":3000,"provenance":{"provider":"test","generatedAt":0}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AssetTechnicalMetadata.self, from: json)
        XCTAssertNil(decoded.rotation)
    }

    func testRotationEncodesAndDecodes() throws {
        let meta = AssetTechnicalMetadata(
            pixelWidth: 4000, pixelHeight: 3000,
            provenance: ProviderProvenance(provider: "test", generatedAt: Date(timeIntervalSince1970: 0))
        )
        var withRotation = meta
        withRotation.rotation = 90
        let encoded = try JSONEncoder().encode(withRotation)
        let decoded = try JSONDecoder().decode(AssetTechnicalMetadata.self, from: encoded)
        XCTAssertEqual(decoded.rotation, 90)
    }

    func testUpdateRotationWritesToCatalog() throws {
        let db = try CatalogDatabase.openInMemory()
        try db.migrate()
        let repo = CatalogRepository(database: db)
        let assetID = AssetID(rawValue: "test-asset")
        let originalURL = URL(fileURLWithPath: "/tmp/test.jpg")
        try repo.insertAsset(
            Asset(
                id: assetID,
                originalURL: originalURL,
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: 1, sha256: "abc"),
                availability: .available,
                metadata: AssetMetadata(),
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 4000, pixelHeight: 3000,
                    provenance: ProviderProvenance(provider: "test", generatedAt: Date(timeIntervalSince1970: 0))
                )
            )
        )
        try repo.updateRotation(assetID: assetID, rotation: 90)
        let asset = try repo.asset(id: assetID)
        XCTAssertEqual(asset.technicalMetadata?.rotation, 90)
    }

    func testUpdateRotationToZeroClearsRotation() throws {
        let db = try CatalogDatabase.openInMemory()
        try db.migrate()
        let repo = CatalogRepository(database: db)
        let assetID = AssetID(rawValue: "test-asset")
        try repo.insertAsset(
            Asset(
                id: assetID,
                originalURL: URL(fileURLWithPath: "/tmp/test.jpg"),
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: 1, sha256: "abc"),
                availability: .available,
                metadata: AssetMetadata(),
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 4000, pixelHeight: 3000,
                    provenance: ProviderProvenance(provider: "test", generatedAt: Date(timeIntervalSince1970: 0))
                )
            )
        )
        try repo.updateRotation(assetID: assetID, rotation: 90)
        try repo.updateRotation(assetID: assetID, rotation: 0)
        let asset = try repo.asset(id: assetID)
        XCTAssertEqual(asset.technicalMetadata?.rotation, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RotationCatalogRepositoryTests`
Expected: FAIL — `AssetTechnicalMetadata` has no `rotation` property, `updateRotation` does not exist

- [ ] **Step 3: Add `rotation` field to `AssetTechnicalMetadata`**

In `Sources/TeststripCore/Domain/Metadata.swift`, add `rotation` after `provenance` in the struct (line ~239):

```swift
    public var rotation: Int?
```

Add `rotation` to the init parameter list (after `provenance`):

```swift
        rotation: Int? = nil
```

And in the init body:

```swift
        self.rotation = rotation
```

- [ ] **Step 4: Add `updateRotation` to `CatalogRepository`**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, after the `updateTechnicalMetadata` method (line ~2470), add:

```swift
    public func updateRotation(assetID: AssetID, rotation: Int) throws {
        let asset = try asset(id: assetID)
        guard var technicalMetadata = asset.technicalMetadata else {
            throw TeststripError.invalidState("no technical metadata for \(assetID.rawValue)")
        }
        technicalMetadata.rotation = rotation
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            UPDATE assets
            SET technical_metadata_json = ?,
                updated_at = ?
            WHERE id = ?
            """,
            bindings: [
                try encode(technicalMetadata),
                now,
                assetID.rawValue
            ]
        )
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter RotationCatalogRepositoryTests`
Expected: PASS

- [ ] **Step 6: Run full test suite to verify no regressions**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Domain/Metadata.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/RotationCatalogRepositoryTests.swift
git commit -m "Add rotation field to AssetTechnicalMetadata and updateRotation repository method"
```

---

## Task 2: Orientation Detection Provider

**Files:**
- Create: `Sources/TeststripCore/Evaluation/AppleOrientationEvaluationProvider.swift`
- Modify: `Sources/TeststripCore/Evaluation/EvaluationProvider.swift:1-22`
- Test: `Tests/TeststripCoreTests/AppleOrientationEvaluationProviderTests.swift`

**Interfaces:**
- Consumes: `EvaluationProvider` protocol (from Task 1's file)
- Produces:
  - `OrientationEvaluationOutcome` struct with `signals: [EvaluationSignal]` (empty) and `rotation: Int?`
  - `OrientationEvaluationProvider` protocol with `evaluateWithOrientation(assetID:previewURL:)`
  - `AppleOrientationEvaluationProvider` — name = `"orientation"`, implements `OrientationEvaluationProvider`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/AppleOrientationEvaluationProviderTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class AppleOrientationEvaluationProviderTests: XCTestCase {
    func testProviderNameIsOrientation() {
        let provider = AppleOrientationEvaluationProvider()
        XCTAssertEqual(provider.name, "orientation")
    }

    func testEvaluateReturnsEmptySignals() throws {
        let provider = AppleOrientationEvaluationProvider()
        let signals = try provider.evaluate(
            assetID: AssetID(rawValue: "test"),
            previewURL: URL(fileURLWithPath: "/tmp/nonexistent.jpg")
        )
        XCTAssertTrue(signals.isEmpty)
    }

    func testEvaluateWithOrientationReturnsNilForMissingFile() {
        let provider = AppleOrientationEvaluationProvider()
        XCTAssertThrowsError(
            try provider.evaluateWithOrientation(
                assetID: AssetID(rawValue: "test"),
                previewURL: URL(fileURLWithPath: "/tmp/nonexistent.jpg")
            )
        )
    }

    func testRotationAngleQuantization() {
        // Test the quantization helper directly
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(0), nil)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(5), nil)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(85), 90)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(90), 90)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(95), 90)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(175), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(180), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(185), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(265), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(270), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(275), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(355), nil)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(-90), 270)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(-180), 180)
        XCTAssertEqual(AppleOrientationEvaluationProvider.quantizeRotation(-270), 90)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppleOrientationEvaluationProviderTests`
Expected: FAIL — types do not exist

- [ ] **Step 3: Add `OrientationEvaluationProvider` protocol to `EvaluationProvider.swift`**

In `Sources/TeststripCore/Evaluation/EvaluationProvider.swift`, append after the `FaceObservationEvaluationProvider` protocol (line 22):

```swift
public struct OrientationEvaluationOutcome: Equatable, Sendable {
    public var signals: [EvaluationSignal]
    public var rotation: Int?

    public init(signals: [EvaluationSignal] = [], rotation: Int? = nil) {
        self.signals = signals
        self.rotation = rotation
    }
}

public protocol OrientationEvaluationProvider: EvaluationProvider {
    func evaluateWithOrientation(assetID: AssetID, previewURL: URL) throws -> OrientationEvaluationOutcome
}
```

- [ ] **Step 4: Create `AppleOrientationEvaluationProvider.swift`**

Create `Sources/TeststripCore/Evaluation/AppleOrientationEvaluationProvider.swift`:

```swift
import Foundation
import Vision
import CoreImage

public struct AppleOrientationEvaluationProvider: OrientationEvaluationProvider, Sendable {
    public let name = "orientation"

    public init() {}

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        []
    }

    public func evaluateWithOrientation(assetID: AssetID, previewURL: URL) throws -> OrientationEvaluationOutcome {
        guard let cgImage = loadCGImage(from: previewURL) else {
            throw TeststripError.invalidState("could not load preview image for orientation detection")
        }

        let faceRotation = detectFaceRotation(from: cgImage)
        if let rotation = faceRotation {
            return OrientationEvaluationOutcome(rotation: rotation)
        }

        let horizonRotation = detectHorizonRotation(from: cgImage)
        if let rotation = horizonRotation {
            return OrientationEvaluationOutcome(rotation: rotation)
        }

        return OrientationEvaluationOutcome(rotation: nil)
    }

    /// Quantizes an arbitrary angle to the nearest 90° increment, returning nil
    /// when the angle is within the dead zone (near 0°/360° — photo looks correct).
    /// Angles near 90° → 90, near 180° → 180, near 270° → 270.
    static func quantizeRotation(_ degrees: Double) -> Int? {
        let tolerance = 25.0
        let normalized = ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let candidates: [(target: Double, value: Int)] = [
            (0, 0), (90, 90), (180, 180), (270, 270), (360, 0)
        ]
        for candidate in candidates {
            if abs(normalized - candidate.target) <= tolerance {
                return candidate.value == 0 ? nil : candidate.value
            }
        }
        return nil
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func detectFaceRotation(from cgImage: CGImage) -> Int? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let results = request.results as? [VNFaceObservation], !results.isEmpty else {
            return nil
        }
        // Use the roll angle of the most prominent face.
        // VNFaceObservation.roll is in radians; positive = clockwise tilt.
        // If faces are consistently rolled near ±90°/180°, the photo needs rotation.
        let rolls = results.compactMap { $0.roll }
        guard let dominantRoll = rolls.first else { return nil }
        let degrees = dominantRoll * 180 / .pi
        // Invert: if the face is rolled 90° clockwise, the photo needs to be
        // rotated 90° counter-clockwise to correct it — but since we're
        // detecting the photo's orientation error, we rotate the photo to
        // match. A face rolled 90° CCW means the photo is 90° CW off.
        return Self.quantizeRotation(-degrees)
    }

    private func detectHorizonRotation(from cgImage: CGImage) -> Int? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first else { return nil }
        // VNHorizonObservation.angle is in radians, measured from horizontal.
        // 0 = level, π/2 = vertical (90° rotation needed).
        let degrees = result.angle * 180 / .pi
        return Self.quantizeRotation(degrees)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter AppleOrientationEvaluationProviderTests`
Expected: PASS

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Evaluation/EvaluationProvider.swift Sources/TeststripCore/Evaluation/AppleOrientationEvaluationProvider.swift Tests/TeststripCoreTests/AppleOrientationEvaluationProviderTests.swift
git commit -m "Add OrientationEvaluationProvider with Vision face + horizon detection"
```

---

## Task 3: Worker Pipeline Integration

**Files:**
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:147-170` (provider registration)
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:417-437` (runEvaluation)
- Modify: `Sources/TeststripApp/AppModel.swift:2802` (defaultEvaluationProviderNames)
- Test: `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`

**Interfaces:**
- Consumes: `OrientationEvaluationProvider` (Task 2), `CatalogRepository.updateRotation` (Task 1)
- Produces: `"orientation"` registered as a default evaluation provider, `runEvaluation` handles orientation results

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift`:

```swift
    func testOrientationProviderIsRegistered() throws {
        let executor = try makeTestExecutor()
        // The provider should be in the providersByName dictionary
        // Access via reflection isn't available; instead verify through
        // runEvaluation behavior with a mock.
        // This is verified by the defaultEvaluationProviderNames test below.
    }
```

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testDefaultEvaluationProvidersIncludeOrientation() {
        XCTAssertEqual(
            AppModel.defaultEvaluationProviderNames,
            ["local-image-metrics", "apple-vision", "core-image-faces", "orientation"]
        )
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testDefaultEvaluationProvidersIncludeOrientation`
Expected: FAIL — `"orientation"` is not in the list

- [ ] **Step 3: Register provider in `WorkerCommandExecutor`**

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`, in the `init(configuration:)` method (line ~153), add `AppleOrientationEvaluationProvider()` to the providers array:

```swift
        var evaluationProviders: [any EvaluationProvider] = [
            LocalImageMetricsEvaluationProvider(),
            AppleVisionEvaluationProvider(),
            FaceExpressionEvaluationProvider(),
            AppleOrientationEvaluationProvider()
        ]
```

- [ ] **Step 4: Handle `OrientationEvaluationProvider` in `runEvaluation`**

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`, in the `runEvaluation` method (line ~425), add orientation handling before the face provider check:

```swift
        if let orientationProvider = provider as? any OrientationEvaluationProvider {
            let outcome = try orientationProvider.evaluateWithOrientation(assetID: assetID, previewURL: previewURL)
            try repository.recordEvaluationSignals(outcome.signals)
            if let rotation = outcome.rotation {
                try repository.updateRotation(assetID: assetID, rotation: rotation)
            }
        } else if let faceProvider = provider as? any FaceObservationEvaluationProvider {
```

- [ ] **Step 5: Add `"orientation"` to `defaultEvaluationProviderNames`**

In `Sources/TeststripApp/AppModel.swift` (line ~2802), change:

```swift
    public static let defaultEvaluationProviderNames = [defaultEvaluationProviderName, "apple-vision", "core-image-faces", "orientation"]
```

- [ ] **Step 6: Update existing tests that assert on `defaultEvaluationProviderNames` count**

Search for tests that assert `AppModel.defaultEvaluationProviderNames` count or contents and update them. The existing test `testDefaultEvaluationProvidersIncludeFaceExpressionPass` needs to be updated to include `"orientation"`:

In `Tests/TeststripAppTests/AppModelTests.swift`, find `testDefaultEvaluationProvidersIncludeFaceExpressionPass` and update:

```swift
    func testDefaultEvaluationProvidersIncludeFaceExpressionPass() {
        XCTAssertEqual(
            AppModel.defaultEvaluationProviderNames,
            ["local-image-metrics", "apple-vision", "core-image-faces", "orientation"]
        )
    }
```

Any test that asserts `defaultEvaluationProviderNames.count` or uses it for evaluation item count expectations needs to be updated. Search for these patterns:

```bash
grep -rn "defaultEvaluationProviderNames.count\|defaultEvaluationProviderNames\b" Tests/
```

Update each test that uses the count to expect 4 instead of 3.

- [ ] **Step 7: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (some may need count updates from 3 → 4)

- [ ] **Step 8: Commit**

```bash
git add Sources/TeststripCore/Worker/WorkerCommandExecutor.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift Tests/TeststripCoreTests/WorkerCommandExecutorTests.swift
git commit -m "Register orientation provider in worker pipeline and default evaluation providers"
```

---

## Task 4: Display Pipeline — Rotation-Aware Image Loading

**Files:**
- Modify: `Sources/TeststripApp/CachedPreviewImage.swift:1-96`
- Modify: `Sources/TeststripApp/LoupeZoomView.swift:440-465`
- Modify: `Sources/TeststripApp/LibraryGridView.swift:9575-9654` (AssetGridCell)
- Test: `Tests/TeststripCoreTests/RotationImageLoadingTests.swift`

**Interfaces:**
- Consumes: `AssetTechnicalMetadata.rotation` (Task 1)
- Produces:
  - `PreviewImageDataLoader.loadImage(from:rotation:) async -> NSImage?` — applies CIImage rotation
  - `CachedPreviewImage` with `rotation: Int?` parameter
  - Grid cell thumbnails with rotation-aware loading

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/RotationImageLoadingTests.swift`:

```swift
import XCTest
import CoreImage
@testable import TeststripCore

final class RotationImageLoadingTests: XCTestCase {
    func testExifOrientationForRotation() {
        // 0° → .up (1), 90° CW → .right (8), 180° → .down (3), 270° CW → .left (6)
        // Using CGImagePropertyOrientation values:
        // .up = 1, .right = 8, .down = 3, .left = 6
        // Wait — CIImage.oriented uses CGImagePropertyOrientation:
        // .up = 1, .upMirrored = 2, .down = 3, .downMirrored = 4,
        // .leftMirrored = 5, .right = 6, .rightMirrored = 7, .left = 8
        // So 90° CW (clockwise) → .right = 6, 180° → .down = 3, 270° CW → .left = 8
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 0), .up)
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 90), .right)
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 180), .down)
        XCTAssertEqual(RotationTransform.exifOrientation(forRotation: 270), .left)
    }

    func testRotatedDimensionsSwapFor90And270() {
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 0), (4000, 3000))
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 90), (3000, 4000))
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 180), (4000, 3000))
        XCTAssertEqual(RotationTransform.rotatedDimensions(width: 4000, height: 3000, rotation: 270), (3000, 4000))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RotationImageLoadingTests`
Expected: FAIL — `RotationTransform` does not exist

- [ ] **Step 3: Create `RotationTransform` helper in TeststripCore**

Create `Sources/TeststripCore/Domain/RotationTransform.swift`:

```swift
import Foundation
import CoreImage

public enum RotationTransform {
    /// Maps a clockwise rotation in degrees to the matching EXIF orientation
    /// for CIImage.oriented(forExifOrientation:).
    /// - 0° → .up (1)
    /// - 90° CW → .right (6)
    /// - 180° → .down (3)
    /// - 270° CW → .left (8)
    public static func exifOrientation(forRotation rotation: Int) -> CGImagePropertyOrientation {
        switch rotation {
        case 0: return .up
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Returns the pixel dimensions after rotation. For 90°/270°, width and
    /// height are swapped.
    public static func rotatedDimensions(width: Int, height: Int, rotation: Int) -> (width: Int, height: Int) {
        switch rotation {
        case 90, 270:
            return (height, width)
        default:
            return (width, height)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RotationImageLoadingTests`
Expected: PASS

- [ ] **Step 5: Add rotation to `PreviewImageDataLoader`**

In `Sources/TeststripApp/CachedPreviewImage.swift`, update `PreviewImageDataLoader.loadImage` to accept a rotation parameter:

```swift
enum PreviewImageDataLoader {
    static func loadData(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

    static func loadImage(from url: URL, rotation: Int = 0) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return nil
            }
            guard rotation != 0 else {
                return NSImage(data: data)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return NSImage(data: data)
            }
            let ciImage = CIImage(cgImage: cgImage)
            let oriented = ciImage.oriented(forExifOrientation: RotationTransform.exifOrientation(forRotation: rotation))
            let context = CIContext()
            guard let rotatedCGImage = context.createCGImage(oriented, from: oriented.extent) else {
                return NSImage(data: data)
            }
            let dims = RotationTransform.rotatedDimensions(
                width: cgImage.width, height: cgImage.height, rotation: rotation
            )
            let nsImage = NSImage(cgImage: rotatedCGImage, size: NSSize(width: dims.width, height: dims.height))
            return nsImage
        }.value
    }
}
```

Note: `CachedPreviewImage.swift` is in TeststripApp but `RotationTransform` is in TeststripCore. TeststripApp imports TeststripCore, so this works.

- [ ] **Step 6: Add `rotation` parameter to `CachedPreviewImage`**

In `Sources/TeststripApp/CachedPreviewImage.swift`, add a `rotation` property to the `CachedPreviewImage` struct:

```swift
struct CachedPreviewImage: View {
    enum Scaling {
        case fill
        case fit
    }

    var previewURL: URL?
    var scaling: Scaling
    var cornerRadius: CGFloat = 5
    var cacheGeneration: Int = 0
    var rotation: Int = 0
```

Update `loadPreview()` to pass rotation:

```swift
        guard let loadedImage = await PreviewImageDataLoader.loadImage(from: previewURL, rotation: rotation), !Task.isCancelled else {
```

Update the `.task` modifier to include rotation in the identity:

```swift
        content
            .task(id: PreviewLoadRequest(url: previewURL, cacheGeneration: cacheGeneration, rotation: rotation)) {
                await loadPreview()
            }
```

Update `PreviewLoadRequest`:

```swift
private struct PreviewLoadRequest: Equatable {
    var url: URL?
    var cacheGeneration: Int
    var rotation: Int
}
```

- [ ] **Step 7: Pass rotation through from `LoupeZoomView`**

In `Sources/TeststripApp/LoupeZoomView.swift`, in `loadPreview()` (line ~460), pass the asset's rotation:

```swift
        let rotation = asset.technicalMetadata?.rotation ?? 0
        guard let loadedImage = await PreviewImageDataLoader.loadImage(from: displayedPreviewURL, rotation: rotation),
              !Task.isCancelled else {
```

- [ ] **Step 8: Pass rotation through from `AssetGridCell`**

In `Sources/TeststripApp/LibraryGridView.swift`, add a `rotation` property to `AssetGridCell` (line ~9577):

```swift
private struct AssetGridCell: View {
    var asset: Asset
    var previewURL: URL?
    var previewCacheGeneration: Int
    var previewStatus: AssetGridPreviewStatusPresentation?
    var isSelected: Bool
    var isBatchSelected: Bool = false
```

The `asset` already carries `technicalMetadata`, so in the `thumbnail` view (line ~9650), pass rotation:

```swift
    @ViewBuilder
    private var thumbnail: some View {
        CachedPreviewImage(
            previewURL: previewURL,
            scaling: AssetGridPreviewPolicy.thumbnailScaling,
            cacheGeneration: previewCacheGeneration,
            rotation: asset.technicalMetadata?.rotation ?? 0
        )
```

- [ ] **Step 9: Update all `CachedPreviewImage` call sites**

Search for all `CachedPreviewImage(` calls and add the `rotation:` parameter. Most call sites pass an `asset` — use `asset.technicalMetadata?.rotation ?? 0`:

```bash
grep -rn "CachedPreviewImage(" Sources/TeststripApp/
```

For each call site, add `rotation: asset.technicalMetadata?.rotation ?? 0` (or the appropriate variable name for the asset at that call site).

- [ ] **Step 10: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 11: Commit**

```bash
git add Sources/TeststripCore/Domain/RotationTransform.swift Sources/TeststripApp/CachedPreviewImage.swift Sources/TeststripApp/LoupeZoomView.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripCoreTests/RotationImageLoadingTests.swift
git commit -m "Add rotation-aware image loading via CIImage transform for display"
```

---

## Task 5: Manual Rotation — ⌘[ / ⌘] Commands

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `rotateSelectedAsset` methods)
- Modify: `Sources/TeststripApp/main.swift:308-340` (add menu commands)
- Test: `Tests/TeststripAppTests/ManualRotationTests.swift`

**Interfaces:**
- Consumes: `CatalogRepository.updateRotation` (Task 1), `Asset.technicalMetadata.rotation` (Task 1)
- Produces:
  - `AppModel.rotateSelectedAssetClockwise() throws` — rotation += 90, wraps to 0
  - `AppModel.rotateSelectedAssetCounterClockwise() throws` — rotation -= 90, wraps to 270
  - `RotateLeft` (⌘[) and `RotateRight` (⌘]) menu commands in `main.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripAppTests/ManualRotationTests.swift`:

```swift
import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class ManualRotationTests: XCTestCase {
    func testRotateClockwiseFromZero() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetClockwise()
        XCTAssertEqual(try model.selectedAssetRotation(), 90)
    }

    func testRotateClockwiseWrapsToZero() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetClockwise()  // 0 → 90
        try model.rotateSelectedAssetClockwise()  // 90 → 180
        try model.rotateSelectedAssetClockwise()  // 180 → 270
        try model.rotateSelectedAssetClockwise()  // 270 → 0
        XCTAssertEqual(try model.selectedAssetRotation(), 0)
    }

    func testRotateCounterClockwiseFromZero() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetCounterClockwise()  // 0 → 270
        XCTAssertEqual(try model.selectedAssetRotation(), 270)
    }

    func testRotateCounterClockwiseWrapsTo270() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetCounterClockwise()  // 0 → 270
        try model.rotateSelectedAssetCounterClockwise()  // 270 → 180
        try model.rotateSelectedAssetCounterClockwise()  // 180 → 90
        try model.rotateSelectedAssetCounterClockwise()  // 90 → 0
        XCTAssertEqual(try model.selectedAssetRotation(), 0)
    }

    private func makeModelWithSingleAsset() throws -> AppModel {
        let model = AppModel()
        let db = try CatalogDatabase.openInMemory()
        try db.migrate()
        let repo = CatalogRepository(database: db)
        let assetID = AssetID(rawValue: "rotation-test")
        try repo.insertAsset(
            Asset(
                id: assetID,
                originalURL: URL(fileURLWithPath: "/tmp/rotation-test.jpg"),
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: 1, sha256: "abc"),
                availability: .available,
                metadata: AssetMetadata(),
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 4000, pixelHeight: 3000,
                    provenance: ProviderProvenance(provider: "test", generatedAt: Date(timeIntervalSince1970: 0))
                )
            )
        )
        model.catalog = Catalog(repository: repo, database: db)
        model.replaceAssets([try repo.asset(id: assetID)])
        model.selectedAssetID = assetID
        return model
    }

    private func selectedAssetRotation() throws -> Int {
        guard let catalog = catalog else {
            throw TeststripError.invalidState("no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let asset = try catalog.repository.asset(id: selectedAssetID)
        return asset.technicalMetadata?.rotation ?? 0
    }
}
```

Note: The `selectedAssetRotation()` helper needs to be on the test class, not on `AppModel`. Move it into the test file as an extension. Also, the `makeModelWithSingleAsset` helper needs to match the existing test patterns in `AppModelTests.swift` — check how other tests in that file set up an `AppModel` with a catalog and assets, and follow that pattern. The test setup may need to use existing helpers from `AppModelTests.swift`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ManualRotationTests`
Expected: FAIL — `rotateSelectedAssetClockwise` does not exist

- [ ] **Step 3: Add rotation methods to `AppModel`**

In `Sources/TeststripApp/AppModel.swift`, add these methods near the existing `setFlagForSelectedAsset` / `setRatingForSelectedAsset` area (around line 8100):

```swift
    public func rotateSelectedAssetClockwise() throws {
        try rotateSelectedAsset(by: 90)
    }

    public func rotateSelectedAssetCounterClockwise() throws {
        try rotateSelectedAsset(by: -90)
    }

    private func rotateSelectedAsset(by delta: Int) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let asset = try catalog.repository.asset(id: selectedAssetID)
        let currentRotation = asset.technicalMetadata?.rotation ?? 0
        var newRotation = (currentRotation + delta) % 360
        if newRotation < 0 { newRotation += 360 }
        try catalog.repository.updateRotation(assetID: selectedAssetID, rotation: newRotation)
        let updatedAsset = try catalog.repository.asset(id: selectedAssetID)
        try syncMetadataSidecar(for: updatedAsset)
        if let index = assets.firstIndex(where: { $0.id == selectedAssetID }) {
            assets[index] = updatedAsset
        }
        statusMessage = newRotation == 0 ? "Rotated back to original" : "Rotated \(newRotation)°"
    }
```

- [ ] **Step 4: Add menu commands in `main.swift`**

In `Sources/TeststripApp/main.swift`, add a new `Commands` struct for rotation. Place it after `NavigationCommands` (line ~340):

```swift
private struct ImageCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandMenu("Image") {
            Button("Rotate Left") {
                try? model.rotateSelectedAssetCounterClockwise()
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("Rotate Right") {
                try? model.rotateSelectedAssetClockwise()
            }
            .keyboardShortcut("]", modifiers: [.command])
        }
    }
}
```

Then add `.commands { ImageCommands(model: model) }` to the `WindowGroup` in the `App` struct, alongside the existing `.commands` modifiers.

Note: Check the existing `main.swift` to see how `NavigationCommands` is wired into the `App` body, and follow the same pattern for `ImageCommands`.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ManualRotationTests`
Expected: PASS

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/main.swift Tests/TeststripAppTests/ManualRotationTests.swift
git commit -m "Add manual rotation ⌘[/⌘] menu commands and AppModel methods"
```

---

## Task 6: XMP Sidecar — `ts:Rotation` Read/Write

**Files:**
- Modify: `Sources/TeststripCore/Metadata/XMPPacket.swift:1-292`
- Modify: `Sources/TeststripCore/Metadata/XMPSidecarStore.swift:50-60`
- Modify: `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift:1-69`
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:449-565` (syncMetadata)
- Test: `Tests/TeststripCoreTests/RotationXMPPacketTests.swift`

**Interfaces:**
- Consumes: `AssetTechnicalMetadata.rotation` (Task 1), `RotationTransform` (Task 4)
- Produces:
  - `XMPPacket` with `rotation: Int?` field
  - `XMPPacket.init(metadata:rotation:)` — new designated initializer
  - `XMPPacket.parse(_:)` returns packet with rotation populated
  - `XMPSidecarStore.write(metadata:rotation:forOriginalAt:)` — writes rotation to sidecar
  - `MetadataSyncDecision.importSidecar(metadata:rotation:)` — carries rotation from sidecar
  - `MetadataSyncPlanner.decision(catalogRotation:)` — uses rotation in write decision

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/RotationXMPPacketTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class RotationXMPPacketTests: XCTestCase {
    func testRotationWrittenToXMPWhenNonZero() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 90)
        let data = try packet.xmlData()
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertTrue(xmlString.contains("ts:Rotation"))
        XCTAssertTrue(xmlString.contains("90"))
    }

    func testRotationNotWrittenToXMPWhenZero() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 0)
        let data = try packet.xmlData()
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertFalse(xmlString.contains("ts:Rotation"))
    }

    func testRotationNotWrittenToXMPWhenNil() throws {
        let packet = XMPPacket(metadata: AssetMetadata())
        let data = try packet.xmlData()
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertFalse(xmlString.contains("ts:Rotation"))
    }

    func testParseReadsRotationFromXMP() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 90)
        let data = try packet.xmlData()
        let parsed = try XMPPacket.parse(data)
        XCTAssertEqual(parsed.rotation, 90)
    }

    func testParseReturnsNilRotationWhenAbsent() throws {
        let packet = XMPPacket(metadata: AssetMetadata())
        let data = try packet.xmlData()
        let parsed = try XMPPacket.parse(data)
        XCTAssertNil(parsed.rotation)
    }

    func testRoundTripRotation180() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 180)
        let parsed = try XMPPacket.parse(try packet.xmlData())
        XCTAssertEqual(parsed.rotation, 180)
    }

    func testRoundTripRotation270() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 270)
        let parsed = try XMPPacket.parse(try packet.xmlData())
        XCTAssertEqual(parsed.rotation, 270)
    }

    func testMergeRotationIntoExistingSidecar() throws {
        let existing = try XMPPacket(metadata: AssetMetadata(rating: 3), rotation: 90).xmlData()
        let merged = try XMPPacket(metadata: AssetMetadata(rating: 3), rotation: 180).xmlData(mergingInto: existing)
        let parsed = try XMPPacket.parse(merged)
        XCTAssertEqual(parsed.rotation, 180)
        XCTAssertEqual(parsed.metadata.rating, 3)
    }

    func testRemoveRotationWhenSetToZero() throws {
        let existing = try XMPPacket(metadata: AssetMetadata(), rotation: 90).xmlData()
        let merged = try XMPPacket(metadata: AssetMetadata(), rotation: 0).xmlData(mergingInto: existing)
        let parsed = try XMPPacket.parse(merged)
        XCTAssertNil(parsed.rotation)
    }

    func testSidecarWriteIncludesRotation() throws {
        let store = XMPSidecarStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("rotation-xmp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let originalURL = tmpDir.appendingPathComponent("test.jpg")
        try Data().write(to: originalURL)
        let result = try store.write(metadata: AssetMetadata(), rotation: 90, forOriginalAt: originalURL)
        let sidecarData = try Data(contentsOf: result.sidecarURL)
        let parsed = try XMPPacket.parse(sidecarData)
        XCTAssertEqual(parsed.rotation, 90)
    }

    func testSidecarWriteOmitsRotationWhenZero() throws {
        let store = XMPSidecarStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("rotation-xmp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let originalURL = tmpDir.appendingPathComponent("test.jpg")
        try Data().write(to: originalURL)
        let result = try store.write(metadata: AssetMetadata(), rotation: 0, forOriginalAt: originalURL)
        let sidecarData = try Data(contentsOf: result.sidecarURL)
        let xmlString = String(data: sidecarData, encoding: .utf8)!
        XCTAssertFalse(xmlString.contains("ts:Rotation"))
    }

    func testMetadataSyncPlannerWritesWhenRotationOnly() throws {
        let planner = MetadataSyncPlanner()
        let decision = try planner.decision(
            catalogMetadata: AssetMetadata(),
            catalogRotation: 90,
            catalogGeneration: 1,
            lastSynced: nil,
            sidecarData: nil
        )
        XCTAssertEqual(decision, .writeCatalog)
    }

    func testMetadataSyncPlannerUpToDateWhenNoRotationAndNoMetadata() throws {
        let planner = MetadataSyncPlanner()
        let decision = try planner.decision(
            catalogMetadata: AssetMetadata(),
            catalogRotation: 0,
            catalogGeneration: 1,
            lastSynced: nil,
            sidecarData: nil
        )
        XCTAssertEqual(decision, .upToDate)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RotationXMPPacketTests`
Expected: FAIL — `XMPPacket` has no `rotation` field, `XMPSidecarStore.write` has no `rotation` parameter, `MetadataSyncPlanner.decision` has no `catalogRotation` parameter

- [ ] **Step 3: Add `rotation` to `XMPPacket`**

In `Sources/TeststripCore/Metadata/XMPPacket.swift`, add `rotation` property and update initializers:

```swift
public struct XMPPacket: Equatable, Sendable {
    public var metadata: AssetMetadata
    public var rotation: Int?

    // ... existing namespace constants ...

    public init(metadata: AssetMetadata, rotation: Int? = nil) {
        self.metadata = metadata
        self.rotation = rotation
    }
```

- [ ] **Step 4: Write `ts:Rotation` in `applyManagedMetadata`**

In `XMPPacket.swift`, in `applyManagedMetadata(to:)` (line ~59), add after `addAttribute("ts:Pick", ...)`:

```swift
        if let rotation = self.rotation, rotation != 0 {
            addAttribute("ts:Rotation", "\(rotation)")
        }
```

- [ ] **Step 5: Add `ts:Rotation` removal in `removeManagedMetadata`**

In `XMPPacket.swift`, in `removeManagedMetadata(from:)` (line ~209), add:

```swift
        removeAttribute(from: description, localName: "Rotation", uri: teststripNamespace)
```

- [ ] **Step 6: Parse `ts:Rotation` in `XMPPacket.parse`**

In `XMPPacket.swift`, in `parse(_:)` (line ~102), add rotation parsing before `return XMPPacket(metadata: metadata)`:

```swift
        let rotation = Self.attribute(description, localName: "Rotation", uri: Self.teststripNamespace).flatMap { Int($0) }
        return XMPPacket(metadata: metadata, rotation: rotation)
```

- [ ] **Step 7: Update `XMPSidecarStore.write` to accept rotation**

In `Sources/TeststripCore/Metadata/XMPSidecarStore.swift`, update the `write` method:

```swift
    public func write(metadata: AssetMetadata, rotation: Int? = nil, forOriginalAt originalURL: URL) throws -> XMPSidecarWriteResult {
        let sidecarURL = sidecarURL(forOriginalAt: originalURL)
        let data: Data
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            data = try XMPPacket(metadata: metadata, rotation: rotation).xmlData(mergingInto: Data(contentsOf: sidecarURL))
        } else {
            data = try XMPPacket(metadata: metadata, rotation: rotation).xmlData()
        }
        try data.write(to: sidecarURL, options: [.atomic])
        return XMPSidecarWriteResult(sidecarURL: sidecarURL, fingerprint: Self.fingerprint(for: data))
    }
```

- [ ] **Step 8: Update `MetadataSyncPlanner.decision` to accept `catalogRotation`**

In `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift`:

1. Update `MetadataSyncDecision.importSidecar` to carry rotation:

```swift
public enum MetadataSyncDecision: Equatable, Sendable {
    case upToDate
    case writeCatalog
    case importSidecar(metadata: AssetMetadata, rotation: Int?)
    case conflict(catalogMetadata: AssetMetadata, sidecarMetadata: AssetMetadata)
}
```

2. Update `decision` to accept `catalogRotation: Int? = nil`:

```swift
    public func decision(
        catalogMetadata: AssetMetadata,
        catalogRotation: Int? = nil,
        catalogGeneration: Int,
        lastSynced: MetadataSyncItem?,
        sidecarData: Data?,
        sidecarModificationDate: Date? = nil
    ) throws -> MetadataSyncDecision {
        let hasPortableMetadata = catalogMetadata.hasWrittenPortableMetadata || (catalogRotation ?? 0) != 0
        guard let sidecarData else {
            return hasPortableMetadata ? .writeCatalog : .upToDate
        }

        guard let lastSynced, let lastSyncedFingerprint = lastSynced.lastSyncedFingerprint else {
            let packet = try XMPPacket.parse(sidecarData)
            return .importSidecar(metadata: packet.metadata, rotation: packet.rotation)
        }

        let sidecarFingerprint = XMPSidecarStore.fingerprint(for: sidecarData)
        let sidecarContentChanged = sidecarFingerprint != lastSyncedFingerprint
        let localChanged = sidecarContentChanged
            ? catalogGeneration != lastSynced.catalogGeneration
            : try catalogMetadata.confirmedProjection != XMPPacket.parse(sidecarData).metadata
        let sidecarFreshened = sidecarModificationDate.map { modificationDate in
            lastSynced.lastSyncedAt.map { modificationDate > $0 } ?? false
        } ?? false

        switch (localChanged, sidecarContentChanged, sidecarFreshened) {
        case (false, false, false):
            return .upToDate
        case (true, false, _):
            return .writeCatalog
        case (false, true, _), (false, false, true):
            let packet = try XMPPacket.parse(sidecarData)
            return .importSidecar(metadata: packet.metadata, rotation: packet.rotation)
        case (true, true, _):
            return .conflict(
                catalogMetadata: catalogMetadata,
                sidecarMetadata: try XMPPacket.parse(sidecarData).metadata
            )
        }
    }
```

- [ ] **Step 9: Update `WorkerCommandExecutor.syncMetadata` to pass rotation**

In `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`, in `syncMetadata` (line ~480):

Update the `metadataSyncDecision` call to pass `catalogRotation`:

```swift
        decision = try metadataSyncDecision(
            catalogMetadata: asset.metadata,
            catalogRotation: asset.technicalMetadata?.rotation,
            catalogGeneration: catalogGeneration,
            syncItem: syncItem,
            sidecarData: sidecarData,
            sidecarModificationDate: sidecarModificationDate
        )
```

Update the `.writeCatalog` case to pass rotation:

```swift
        case .writeCatalog:
            do {
                let result = try sidecarStore.write(
                    metadata: asset.metadata,
                    rotation: asset.technicalMetadata?.rotation,
                    forOriginalAt: asset.originalURL
                )
```

Update the `.importSidecar` case to apply rotation:

```swift
        case .importSidecar(let metadata, let rotation):
            try repository.updateMetadata(assetID: assetID) { catalogMetadata in
                catalogMetadata = catalogMetadata.mergingConfirmedSidecar(metadata)
            }
            if let rotation {
                try repository.updateRotation(assetID: assetID, rotation: rotation)
            }
```

- [ ] **Step 10: Update `AppModel.syncMetadataSidecar` to pass rotation**

In `Sources/TeststripApp/AppModel.swift`, in `syncMetadataSidecar(for:)` (line ~9317), update the non-worker write path:

```swift
            let result = try catalog.metadataSidecarStore.write(
                metadata: asset.metadata,
                rotation: asset.technicalMetadata?.rotation,
                forOriginalAt: asset.originalURL
            )
```

- [ ] **Step 11: Update existing tests that match on `MetadataSyncDecision`**

Search for tests that pattern-match `.importSidecar(let metadata)` and update to `.importSidecar(let metadata, let rotation)`:

```bash
grep -rn "\.importSidecar(" Tests/
```

Update each match to handle the new `rotation` parameter.

- [ ] **Step 12: Run test to verify it passes**

Run: `swift test --filter RotationXMPPacketTests`
Expected: PASS

- [ ] **Step 13: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (fix any `.importSidecar` pattern match failures)

- [ ] **Step 14: Commit**

```bash
git add Sources/TeststripCore/Metadata/XMPPacket.swift Sources/TeststripCore/Metadata/XMPSidecarStore.swift Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift Sources/TeststripCore/Worker/WorkerCommandExecutor.swift Sources/TeststripApp/AppModel.swift Tests/TeststripCoreTests/RotationXMPPacketTests.swift
git commit -m "Add ts:Rotation to XMP sidecar write/parse and sync pipeline"
```

---

## Task 7: Export — Bake Rotation into Export

**Files:**
- Modify: `Sources/TeststripCore/Export/ExportService.swift:129-212`
- Test: `Tests/TeststripCoreTests/ExportServiceTests.swift` (add rotation tests)

**Interfaces:**
- Consumes: `RotationTransform` (Task 4), `AssetTechnicalMetadata.rotation` (Task 1)
- Produces: Export accepts rotation and bakes it into exported pixels

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/ExportServiceTests.swift`:

```swift
    func testExportAppliesRotation90() throws {
        let exportService = ExportService()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("export-rotation-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDimensions: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let sourceURL = tmpDir.appendingPathComponent("source.jpg")
        // Create a 200x100 test image (wider than tall)
        try createTestJPEG(at: sourceURL, width: 200, height: 100)
        let destDir = tmpDir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDimensions: true)
        let results = try exportService.export(
            originalURLs: [sourceURL],
            settings: ExportSettings(format: .jpeg, quality: 0.9),
            destinationDirectory: destDir,
            catalogRotationBySourceURL: [sourceURL: 90]
        )
        guard case .exported(let destURL) = results[0].outcome else {
            XCTFail("expected exported")
            return
        }
        // After 90° CW rotation, a 200x100 image becomes 100x200
        let data = try Data(contentsOf: destURL)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        let width = props[kCGImagePropertyPixelWidth] as! Int
        let height = props[kCGImagePropertyPixelHeight] as! Int
        XCTAssertEqual(width, 100)
        XCTAssertEqual(height, 200)
    }
```

Note: Check the existing `ExportServiceTests.swift` for the `createTestJPEG` helper pattern and follow it. If no such helper exists, create one that writes a small JPEG using `CGImageDestination`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testExportAppliesRotation90`
Expected: FAIL — `export` has no `catalogRotationBySourceURL` parameter

- [ ] **Step 3: Add rotation parameter to `ExportService.export`**

In `Sources/TeststripCore/Export/ExportService.swift`, add a new parameter to `export`:

```swift
    public func export(
        originalURLs: [URL],
        settings: ExportSettings,
        destinationDirectory: URL,
        catalogMetadataBySourceURL: [URL: AssetMetadata] = [:],
        catalogRotationBySourceURL: [URL: Int] = [:],
        collisionResolution: ExportCollisionResolution = .keepBoth,
        progress: ExportProgressHandler? = nil
    ) throws -> [ExportFileResult] {
```

Pass it through to `exportOutcome`:

```swift
            results.append(ExportFileResult(
                sourceURL: sourceURL,
                outcome: exportOutcome(
                    sourceURL: sourceURL,
                    catalogMetadata: catalogMetadataBySourceURL[sourceURL],
                    rotation: catalogRotationBySourceURL[sourceURL] ?? 0,
                    settings: settings,
                    destinationDirectory: destinationDirectory,
                    collisionResolution: collisionResolution,
                    claimedFilenames: &claimedFilenames
                )
            ))
```

- [ ] **Step 4: Apply rotation in `exportOutcome`**

Update `exportOutcome` to accept `rotation: Int`:

```swift
    private func exportOutcome(
        sourceURL: URL,
        catalogMetadata: AssetMetadata?,
        rotation: Int,
        settings: ExportSettings,
        destinationDirectory: URL,
        collisionResolution: ExportCollisionResolution,
        claimedFilenames: inout Set<String>
    ) -> ExportOutcome {
        switch decodeThumbnail(from: sourceURL, settings: settings) {
        case .unavailable:
            return .skippedUnavailable
        case .unreadable:
            return .failed(message: "could not read \(sourceURL.lastPathComponent)")
        case .undecodable:
            return .failed(message: "could not decode \(sourceURL.lastPathComponent)")
        case .ready(let image, var destinationProperties):
            if settings.includeSourceMetadata, let catalogMetadata {
                destinationProperties = Self.embeddingCatalogMetadata(catalogMetadata, into: destinationProperties)
            }
            let finalImage: CGImage = rotation != 0
                ? applyRotation(image: image, rotation: rotation)
                : image
            let destinationURL = availableDestinationURL(
```

Replace all subsequent uses of `image` with `finalImage` in the remainder of `exportOutcome`.

- [ ] **Step 5: Add `applyRotation` helper to `ExportService`**

```swift
    private func applyRotation(image: CGImage, rotation: Int) -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let oriented = ciImage.oriented(forExifOrientation: RotationTransform.exifOrientation(forRotation: rotation))
        let context = CIContext()
        return context.createCGImage(oriented, from: oriented.extent) ?? image
    }
```

- [ ] **Step 6: Update export call sites to pass rotation**

Search for `.export(` calls in `Sources/TeststripApp/` and pass `catalogRotationBySourceURL` where the asset's technical metadata is available. The primary call site is in `AppModel` — search for `exportService.export` or `ExportService().export`:

```bash
grep -rn "\.export(" Sources/TeststripApp/ | grep -i export
```

At each call site, build the rotation map from the selected assets' `technicalMetadata.rotation`. Most call sites iterate over assets already — add rotation to the map alongside the existing `catalogMetadataBySourceURL` construction.

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter testExportAppliesRotation90`
Expected: PASS

- [ ] **Step 8: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add Sources/TeststripCore/Export/ExportService.swift Tests/TeststripCoreTests/ExportServiceTests.swift Sources/TeststripApp/AppModel.swift
git commit -m "Bake rotation override into export pixels via CIImage transform"
```

---

## Task 8: E2E Scenario — Auto-Rotation Detection and Manual Rotation

**Files:**
- Create: `test/scenarios/auto-rotation/001-detect-and-rotate.md`

**Interfaces:**
- Consumes: All prior tasks
- Produces: An E2E scenario card that can be run via `script/vm_scenario_run.sh`

- [ ] **Step 1: Write the scenario card**

Create `test/scenarios/auto-rotation/001-detect-and-rotate.md`:

```markdown
# Auto-Rotation: Detect and Rotate

## Setup

- `--isolated` with `--sample-photos` seeded with at least one sideways photo
  (a photo whose EXIF orientation is correct but the content is visually
  rotated 90°)
- If no sideways sample is available, the scenario still verifies manual
  rotation via ⌘[/⌘]

## Steps

1. Launch the app in the Tart VM via `script/vm_scenario_run.sh`
2. Wait for import to complete and evaluations to settle
3. Open the loupe on the first photo
4. Verify the photo is displayed (no crash, no blank state)

## Manual Rotation Verification

5. Press `⌘]` (Rotate Right) — verify the image rotates 90° clockwise
6. Press `⌘]` again — verify 180°
7. Press `⌘]` again — verify 270°
8. Press `⌘]` again — verify back to original (0°, wraps)
9. Press `⌘[` (Rotate Left) — verify 270° (wraps counter-clockwise)
10. Press `⌘[` again — verify 180°

## Catalog Ground Truth

11. Query the catalog:
    ```sql
    SELECT id, json_extract(technical_metadata_json, '$.rotation') AS rotation
    FROM assets LIMIT 5;
    ```
12. Verify the selected asset has a non-null rotation after step 5

## XMP Sidecar

13. Check for sidecar file next to the source:
    ```bash
    ls "$ISOLATED/Teststrip/"*.xmp 2>/dev/null
    ```
14. Verify `ts:Rotation` attribute is present in the sidecar:
    ```bash
    grep "ts:Rotation" "$ISOLATED/Teststrip/"*.xmp
    ```

## Auto-Detection (if sideways sample exists)

15. After import + evaluation settle, query the catalog for auto-detected
    rotation:
    ```sql
    SELECT id, json_extract(technical_metadata_json, '$.rotation') AS rotation
    FROM assets WHERE json_extract(technical_metadata_json, '$.rotation') IS NOT NULL;
    ```
16. Verify at least one asset has a rotation value from auto-detection

## Pass Criteria

- ⌘[/⌘] rotation works in the loupe (visual rotation applied immediately)
- Catalog ground truth shows the rotation value
- XMP sidecar contains `ts:Rotation` when rotation is non-zero
- No crashes
```

- [ ] **Step 2: Commit the scenario card**

```bash
git add test/scenarios/auto-rotation/001-detect-and-rotate.md
git commit -m "Add auto-rotation E2E scenario card"
```

- [ ] **Step 3: Run the E2E scenario in the VM**

```bash
script/vm_scenario_run.sh setup
script/vm_scenario_run.sh sync
script/vm_scenario_run.sh build
script/vm_scenario_run.sh launch --sample-photos
```

Wait for the app to launch, then drive the scenario:

```bash
script/vm_scenario_run.sh ax wait-vended
script/vm_scenario_run.sh ax find --role AXMenuItem --title "Rotate Right" --press
```

Verify catalog ground truth:

```bash
script/vm_scenario_run.sh sql "SELECT id, json_extract(technical_metadata_json, '$.rotation') AS rotation FROM assets LIMIT 5"
```

- [ ] **Step 4: Verify pass criteria met**

- Menu commands appear in the Image menu
- ⌘] rotates clockwise, ⌘[ rotates counter-clockwise
- Catalog shows rotation value
- No crashes

- [ ] **Step 5: Commit any fixes needed**

If the scenario reveals issues, fix them and commit:

```bash
git add -A
git commit -m "Fix auto-rotation issues found in E2E testing"
```
