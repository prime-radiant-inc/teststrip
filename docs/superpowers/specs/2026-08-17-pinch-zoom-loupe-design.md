# Pinch-to-Zoom in Loupe + Grid→Loupe Expand

## Overview

Add continuous pinch-to-zoom (1×–1200%) to the loupe view, and an Apple Photos-style pinch-to-expand gesture on grid cells that grows an overlay from the cell into the loupe.

## Requirements

### R1: Continuous Loupe Zoom

- Scale factor `loupeZoomScale: CGFloat` on `AppModel`, default `1.0` (fit).
- `LoupeZoomGeometry.displaySize(for scale:)` interpolates between `fittedDisplaySize` (scale=1.0) and `actualSizeDisplaySize` (scale = maxScale where 1 image pixel = 1 display pixel).
- `maxScale` = `actualSizeDisplaySize.width / fittedDisplaySize.width` (varies per image).
- Clamp scale to `[1.0, maxScale]`.
- Pan via existing `DragGesture` / `LoupeZoomFocus` continues to work at any scale > 1.0.
- HUD shows `Int(scale * 100)%` (e.g., "250%", "1200%") instead of hardcoded "100%".

### R2: Pinch Gesture on Loupe Image

- `MagnificationGesture` on `LoupeZoomStageView`'s zoomed image.
- `@GestureState pinchScale` (transient). On change: `loupeZoomScale = max(1.0, baseScale * pinchScale)` where `baseScale` is the scale at gesture start.
- On gesture end: commit final scale (no snap, stays where the user leaves it, clamped to [1.0, maxScale]).
- Existing click-to-zoom-to-point stays: click sets `scale = maxScale` and `focus` to clicked point. User can then pinch from there.

### R3: Full-Resolution Escalation

- `LoupeZoomRenderPolicy` currently escalates to original-resolution preview when `loupeZoomFocus != nil` (binary). Generalize: request full-resolution when `loupeZoomScale` exceeds the threshold where the cached preview level can't cover the displayed pixels.
- Threshold: `scale > (cachedPreviewPixelWidth / fittedDisplayWidth)`. When the cached preview (large=3200, medium=1600) would be stretched beyond its native resolution, escalate to original.

### R4: Grid Pinch-to-Expand Overlay

- `MagnificationGesture` on `AssetGridCell`.
- When pinch exceeds ~1.3×, begin the expand transition:
  1. Capture cell frame in global coordinates (`GeometryReader`).
  2. Open the loupe (`model.openAssetInLibraryLoupe(asset.id)`) with transition state.
  3. Present a zoom overlay: the cell's `CachedPreviewImage` at a higher preview level (medium/large), positioned at the cell's original frame, scaled by `pinchScale`.
  4. At ~2.0× threshold, cross-fade into the real `LoupeView`.
- `@Namespace` hoisted to `mainContent` (`LibraryGridView.swift:191`) to span both grid and loupe branches.
- Transient state on `AppModel`: `gridExpandTransition` (cell frame + progress).
- `openAssetInLibraryLoupe` seeds the transition; it completes when the loupe view appears.
- Reduce-motion: skip overlay animation, open loupe directly (existing `accessibilityReduceMotion` pattern).

### R5: Loupe Pinch-Back Behavior

- Pinching below 1.0× clamps at 1.0× (does NOT close the loupe).
- ESC or back gesture returns to grid (existing behavior, unchanged).

## Non-Goals

- No zoom on grid cells that stay in the grid (the pinch always transitions to loupe).
- No changes to the thumbnail size slider (that stays for grid density).
- No rotation gesture.
- No double-tap-to-zoom (click-to-zoom already exists; pinch is additive).

## Files Touched

| File | Change |
|---|---|
| `Sources/TeststripApp/AppModel.swift` | `loupeZoomScale: CGFloat`, `gridExpandTransition` state, update `openAssetInLibraryLoupe`, zoom scale reset on selection move |
| `Sources/TeststripApp/LoupeZoomView.swift` | Continuous scale in `LoupeZoomGeometry`, `MagnificationGesture` on `LoupeZoomStageView`, HUD percentage, render policy threshold |
| `Sources/TeststripApp/LibraryGridView.swift` | `MagnificationGesture` on `AssetGridCell`, zoom overlay view, `@Namespace` in `mainContent` |
| `Tests/TeststripAppTests/` | LoupeZoomGeometry scaling tests, AppModel zoom scale state tests |

## Testing

- **Unit:** `LoupeZoomGeometry.displaySize(for:)` interpolation, clamping, `maxScale` computation. AppModel zoom scale state transitions.
- **Scenario (VM):** Open grid → pinch a cell → verify loupe opens → pinch zoom to >100% → verify HUD shows percentage → ESC back to grid. (Pinch simulation via CGEvent magnification or AX gesture if available; fallback: keyboard-driven zoom if pinch can't be driven.)
