# Auto-Rotation Design

## Overview

Detect photos that need rotation using Apple's Vision framework (face orientation + horizon detection) and auto-apply a rotation override as catalog metadata — non-destructive, no original file bytes touched. Provide manual ⌘[/⌘] keyboard commands for user rotation. Mirror rotation to XMP sidecars for portability.

## Motivation

Some photos have wrong or missing EXIF orientation metadata, so they display sideways or upside down in the grid and loupe. Jesse wants the app to automatically detect these photos using on-device ML and correct them — without modifying the original image bytes. Manual rotation commands let the user fix any case the ML gets wrong.

## Design Decisions

- **ML approach**: Face + horizon detection. Uses `VNDetectFaceRectanglesRequest` (face roll angles) and `VNDetectHorizonRequest` (horizon line angle). Both are Apple Vision framework APIs — no new ML models to bundle.
- **Corrective only**: Auto-rotation only fires when the photo appears wrong (detected angle is ~90°/180°/270° off). Photos already displaying correctly are left alone.
- **No provenance tracking**: AI-detected rotation is set as a default. If the user changes it, it just changes. No `origin = ai/user` distinction, no ✨ marker, no confirmation step.
- **Pipeline integration**: Runs as an `OrientationEvaluationProvider` in the existing evaluation pipeline — reuses the `runEvaluation` worker command and its scheduling.
- **Display approach**: Rotation applied at image load time via CIImage transform — no preview re-rendering, no SwiftUI view transform, no zoom/pan math changes.
- **Manual shortcuts**: `⌘[` = rotate counter-clockwise, `⌘]` = rotate clockwise.

## Section 1: Catalog Model

Add a `rotation: Int?` field to `AssetTechnicalMetadata`:

```swift
public var rotation: Int?  // nil/0 = none, 90/180/270 = clockwise degrees
```

- No provenance tracking — AI sets a default, user changes it, it just changes.
- Stored in the existing `technical_metadata_json` column (JSON, no schema migration). Synthesized Codable uses `decodeIfPresent` for optionals, so old catalogs decode fine with nil.
- `CatalogRepository` gets `updateRotation(assetID:rotation:)` for targeted column writes (same pattern as `updateTechnicalMetadata`).
- `pixelWidth`/`pixelHeight` stay as-is — they reflect the original file. Display dimensions are computed from them + rotation at render time.

## Section 2: Orientation Detection

A new `OrientationEvaluationProvider` that runs as part of the existing evaluation pipeline.

### Provider Structure

Following the `FaceObservationEvaluationProvider` pattern:

```swift
public struct OrientationEvaluationOutcome: Equatable, Sendable {
    public var signals: [EvaluationSignal]   // empty — rotation isn't a signal
    public var rotation: Int?                  // nil = no change needed, 0/90/180/270
}

public protocol OrientationEvaluationProvider: EvaluationProvider {
    func evaluateWithOrientation(assetID: AssetID, previewURL: URL) throws -> OrientationEvaluationOutcome
}
```

### Detection Logic

Corrective only — only fires when the photo looks wrong:

1. Load the cached preview as a CGImage.
2. Run `VNDetectFaceRectanglesRequest` — if faces are detected with consistent roll angles near ±90°/180°, the photo needs that rotation.
3. If no faces (or faces are ambiguous), run `VNDetectHorizonRequest` — if the horizon is detected at ~90°/180°/270°, suggest that rotation.
4. If neither detects a significant off-axis angle, return `nil` (photo appears correct — no intervention).
5. Return the rotation in 90° increments (0/90/180/270).

### Integration into Worker Pipeline

- Add `"orientation"` to `defaultEvaluationProviderNames` in `AppModel`.
- `WorkerCommandExecutor.runEvaluation` checks `as? any OrientationEvaluationProvider` and writes rotation to the catalog via `repository.updateRotation(assetID:rotation:)`.
- Runs automatically after import (same scheduling as existing providers — `enqueueImportEvaluationsForCachedPreviews`).

## Section 3: Display Pipeline

Apply rotation at image load time using CIImage — not as a SwiftUI view transform. This keeps zoom/pan math correct because the NSImage is already rotated before the view sees it.

### Rotation-Aware Image Loading

- Add a `rotation` parameter to the preview image loading path (`PreviewImageDataLoader.loadImage(from:rotation:)`).
- If rotation != 0: create CGImage from the preview data, apply `CIImage.oriented(forExifOrientation:)` with the matching EXIF orientation (90° CW → `.right`, 180° → `.down`, 270° CW → `.left`), then create a new NSImage from the rotated CGImage.
- For 90°/270° rotations, swap width/height in the NSImage size.
- CIImage rotation is GPU-accelerated and fast — no perceptible latency.

### Affected Display Surfaces

- **Loupe view** (`LoupeZoomView`): Passes rotation through to `PreviewImageDataLoader`. No zoom/pan math changes needed — the loaded image is already correct.
- **Grid thumbnails**: Same rotation-aware loading. Grid cell aspect ratio computation accounts for rotation (swaps width/height for 90°/270°).
- **Face box overlays**: Face coordinates are relative to the preview image. After rotation, face box positions need to be transformed (rotate the normalized coordinates). The face overlay rendering applies the same coordinate transform.

No preview re-rendering — the preview JPEGs stay as-is (EXIF-baked). Rotation is applied each time the image is loaded from cache. This is non-destructive: original untouched, previews untouched, rotation is a display-time transform.

## Section 4: Manual Rotation

### Keyboard Shortcuts

- `⌘[` = rotate counter-clockwise (rotation -= 90, wrapping to 270)
- `⌘]` = rotate clockwise (rotation += 90, wrapping to 0)
- Registered as menu commands in `main.swift` (like existing `⌘⇧[` / `⌘⇧]` view history commands).

### Behavior

- Updates `rotation` on the asset's `technicalMetadata` in the catalog via `CatalogRepository.updateRotation`.
- Immediate visual feedback — the display pipeline applies rotation at image load time, so the next render shows the rotated image immediately (no worker round-trip needed).
- Works in both grid and loupe views — the command is available whenever a photo is selected.
- Rotation wraps: 0 → 90 → 180 → 270 → 0.

### Menu Placement

- "Rotate Left" (⌘[) and "Rotate Right" (⌘]) under the existing Image menu (or a new Rotate submenu).

## Section 5: XMP Sidecar

Add rotation to the XMP sidecar for portability:

- New attribute `ts:Rotation` in the teststrip namespace (`https://teststrip.app/xmp/1.0/`) — same namespace as the existing `ts:Pick`.
- Written whenever rotation is non-zero (no provenance tracking — rotation is just a value, so it goes to the sidecar immediately, not gated on user confirmation).
- `XMPPacket.applyManagedMetadata` writes `ts:Rotation` when rotation != 0.
- `XMPPacket` is extended to carry an optional `rotation: Int?` alongside its existing `AssetMetadata`. The `parse` method reads `ts:Rotation` and returns it; the sidecar sync pipeline (`MetadataSyncPlanner` / `SidecarRescanService`) applies it to `AssetTechnicalMetadata.rotation` on the catalog side. This is a new path — `XMPPacket` currently only represents `AssetMetadata`, so rotation is carried as a separate field on the packet struct, not inside `AssetMetadata`.
- The sidecar stores the rotation override; the original file's EXIF orientation is never touched.

### Sidecar Write Trigger

- Rotation follows a simplified write rule: any non-zero rotation triggers a sidecar write (alongside any existing metadata). No `aiUnconfirmedFields` gating — rotation is not part of the provenance system.
- `AssetMetadata.hasWrittenPortableMetadata` is extended to also check `rotation != 0` — so a sidecar is written when rotation is set even if no other portable metadata exists.

## Section 6: Export

Apply rotation during export so exported images are visually correct:

- `ExportService` already uses `kCGImageSourceCreateThumbnailWithTransform: true` (bakes EXIF orientation). After that, apply the rotation override using the same CIImage transform as the display pipeline.
- The exported image has both EXIF orientation and rotation override baked into pixels. The export destination's EXIF orientation is set to 1 (up) — same as the existing EXIF baking pattern.
- Rotation value comes from the asset's `technicalMetadata.rotation` (passed to the export via the existing `catalogMetadataBySourceURL` mapping or a new parameter).

## Non-Destructive Invariant

- Original image bytes are never modified.
- Rotation is stored in the catalog (`technical_metadata_json`) and mirrored to XMP sidecar (`ts:Rotation`).
- Preview JPEGs are not re-rendered — rotation is a display-time CIImage transform.
- Export bakes rotation into the exported copy (not the original).

## Testing

- **Unit tests**: Orientation detection logic (face roll → rotation, horizon angle → rotation, no detection → nil), rotation-aware image loading (CIImage transform correctness, dimension swapping), XMP sidecar round-trip (write `ts:Rotation`, parse it back), catalog repository `updateRotation`.
- **E2E scenario**: Import a sideways photo, verify auto-rotation is detected and applied, verify the loupe displays it upright, verify manual ⌘[/⌘] rotation works, verify the XMP sidecar contains `ts:Rotation`, verify export produces an upright image.
