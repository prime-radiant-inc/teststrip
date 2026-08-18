# Pinch-to-Zoom in Loupe + Grid→Loupe Expand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add continuous pinch-to-zoom (1×–1200%+) to the loupe view and an Apple Photos-style pinch-to-expand gesture on grid cells that grows an overlay from the cell into the loupe.

**Architecture:** Replace the loupe's binary fit/1:1 zoom toggle with a continuous scale factor (`loupeZoomScale: CGFloat`) on `AppModel`, driven by `MagnificationGesture`. Generalize `LoupeZoomGeometry` to compute display size at any scale. Add a `MagnificationGesture` on grid cells that, past a threshold, opens the loupe with an overlay transition that grows from the cell's frame.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit, CryptoKit

**Spec:** `docs/superpowers/specs/2026-08-17-pinch-zoom-loupe-design.md`

## Global Constraints

- Swift 6, SwiftPM. Test via `swift test`.
- Non-destructive: no changes to original image files or XMP sidecars.
- Reduce-motion: existing `accessibilityReduceMotion` pattern gates all new animations.
- Existing click-to-zoom-to-point behavior must remain functional alongside pinch.
- Pinch below 1.0× clamps at 1.0× (does NOT dismiss the loupe).
- ESC returns to grid (existing behavior, unchanged).
- Unit tests run: `swift test 2>&1 | tail -5`
- All changes in `Sources/TeststripApp/` and `Tests/TeststripAppTests/`.

---

### Task 1: Continuous Scale in LoupeZoomGeometry

**Files:**
- Modify: `Sources/TeststripApp/LoupeZoomView.swift:43-148` (LoupeZoomGeometry)
- Test: `Tests/TeststripAppTests/LoupeZoomGeometryTests.swift`

**Interfaces:**
- Produces: `LoupeZoomGeometry.maxScale` (computed property), `LoupeZoomGeometry.displaySize(for scale: CGFloat) -> CGSize`, `LoupeZoomGeometry.offset(for:focus:scale:) -> CGSize`, `LoupeZoomGeometry.focus(pannedBy:from:scale:) -> LoupeZoomFocus`, `LoupeZoomGeometry.clampedFocus(_:scale:) -> LoupeZoomFocus`

- [ ] **Step 1: Write failing tests for continuous scale geometry**

Add these tests to `LoupeZoomGeometryTests.swift`:

```swift
func testMaxScaleIsRatioOfActualToFitted() {
    // 4000x2000 image in 1000x800 viewport at displayScale 1:
    // fitted = min(1000/4000, 800/2000) * 4000x2000 = 1000x500
    // actual = 4000x2000
    // maxScale = 4000/1000 = 4.0
    let g = makeGeometry(displayScale: 1)
    XCTAssertEqual(g.maxScale, 4.0, accuracy: 0.001)
}

func testDisplaySizeAtScale1IsFitted() {
    let g = makeGeometry(displayScale: 1)
    assertEqual(g.displaySize(for: 1.0), g.fittedDisplaySize)
}

func testDisplaySizeAtMaxScaleIsActualSize() {
    let g = makeGeometry(displayScale: 1)
    assertEqual(g.displaySize(for: g.maxScale), g.actualSizeDisplaySize)
}

func testDisplaySizeAtIntermediateScale() {
    // scale 2.0 on 4000x2000 in 1000x800 at ds=1:
    // fitted = 1000x500, so displaySize(2.0) = 2000x1000
    let g = makeGeometry(displayScale: 1)
    assertEqual(g.displaySize(for: 2.0), CGSize(width: 2000, height: 1000))
}

func testOffsetScalesWithScale() {
    // At scale 1.0 (fitted), offset should be zero (image fills viewport)
    // At scale 2.0, focus center → offset 0 (centered)
    // At scale 2.0, displaySize = 2000x1000 in viewport 1000x800
    // focus (1,1) clamped: x: halfViewport=1000/2000/2=0.25 → clamp(1,0.25,0.75)=0.75
    //                     y: halfViewport=800/1000/2=0.4 → clamp(1,0.4,0.6)=0.6
    // offset = (0.5-0.75)*2000, (0.5-0.6)*1000 = -500, -100
    let g = makeGeometry(displayScale: 1)
    let centerOffset = g.offset(for: .center, scale: 2.0)
    assertEqual(centerOffset, .zero)
    let cornerOffset = g.offset(for: LoupeZoomFocus(x: 1, y: 1), scale: 2.0)
    assertEqual(cornerOffset, CGSize(width: -500, height: -100))
}

func testFocusPannedByScalesWithDisplaySize() {
    // At scale 2.0, displaySize = 2000x1000; pan 50pt right and down
    // → focus delta = 50/2000 = 0.025 on x, 50/1000 = 0.05 on y
    // → 0.5-0.025=0.475 on x, 0.5-0.05=0.45 on y
    // clamped: x: clamp(0.475, 0.25, 0.75)=0.475; y: clamp(0.45, 0.4, 0.6)=0.45
    let g = makeGeometry(displayScale: 1)
    let result = g.focus(pannedBy: CGSize(width: 50, height: 50), from: .center, scale: 2.0)
    XCTAssertEqual(result.x, 0.475, accuracy: 0.001)
    XCTAssertEqual(result.y, 0.45, accuracy: 0.001)
}

func testClampedFocusScalesWithDisplaySize() {
    // At scale 2.0, displaySize = 2000x1000 in viewport 1000x800
    // x-axis: imageExtent(2000) > viewportExtent(1000) → halfViewport=0.25, clamp(0,0.25,0.75)=0.25
    // y-axis: imageExtent(1000) > viewportExtent(800) → halfViewport=0.4, clamp(0,0.4,0.6)=0.4
    let g = makeGeometry(displayScale: 1)
    let clamped = g.clampedFocus(LoupeZoomFocus(x: 0.0, y: 0.0), scale: 2.0)
    XCTAssertEqual(clamped.x, 0.25, accuracy: 0.001)
    XCTAssertEqual(clamped.y, 0.4, accuracy: 0.001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LoupeZoomGeometryTests 2>&1 | tail -10`
Expected: FAIL — `maxScale`, `displaySize(for:)`, `offset(for:scale:)`, `focus(pannedBy:from:scale:)`, `clampedFocus(_:scale:)` do not exist.

- [ ] **Step 3: Implement continuous scale methods in LoupeZoomGeometry**

Add these to `LoupeZoomGeometry` in `LoupeZoomView.swift` after the existing `fittedDisplaySize` property (after line 66):

```swift
/// Maximum zoom factor: ratio of 1:1 display size to fitted display size.
var maxScale: CGFloat {
    guard fittedDisplaySize.width > 0 else { return 1.0 }
    return actualSizeDisplaySize.width / fittedDisplaySize.width
}

/// Display size at a continuous scale factor (1.0 = fit, maxScale = 1:1).
func displaySize(for scale: CGFloat) -> CGSize {
    let fitted = fittedDisplaySize
    return CGSize(width: fitted.width * scale, height: fitted.height * scale)
}

/// Offset for a focus point at a given scale (not just 1:1).
func offset(for focus: LoupeZoomFocus, scale: CGFloat) -> CGSize {
    let clamped = clampedFocus(focus, scale: scale)
    let display = displaySize(for: scale)
    return CGSize(
        width: (0.5 - clamped.x) * display.width,
        height: (0.5 - clamped.y) * display.height
    )
}

/// Pan by a drag translation at a given scale.
func focus(pannedBy translation: CGSize, from start: LoupeZoomFocus, scale: CGFloat) -> LoupeZoomFocus {
    let display = displaySize(for: scale)
    guard display.width > 0, display.height > 0 else { return clampedFocus(start, scale: scale) }
    return clampedFocus(LoupeZoomFocus(
        x: start.x - translation.width / display.width,
        y: start.y - translation.height / display.height
    ), scale: scale)
}

/// Clamp focus so image edges stay in viewport at a given scale.
func clampedFocus(_ focus: LoupeZoomFocus, scale: CGFloat) -> LoupeZoomFocus {
    let display = displaySize(for: scale)
    return LoupeZoomFocus(
        x: Self.clampedFocusComponent(focus.x, imageExtent: display.width, viewportExtent: viewportSize.width),
        y: Self.clampedFocusComponent(focus.y, imageExtent: display.height, viewportExtent: viewportSize.height)
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LoupeZoomGeometryTests 2>&1 | tail -10`
Expected: PASS — all new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LoupeZoomView.swift Tests/TeststripAppTests/LoupeZoomGeometryTests.swift
git commit -m "Add continuous scale methods to LoupeZoomGeometry

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Loupe Zoom Scale State on AppModel

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift:2136-2142` (zoom state), `7518-7531` (zoom methods), `4939-4941` (reset on selection), `6588-6591` (openAssetInLibraryLoupe)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces: `AppModel.loupeZoomScale: CGFloat` (default 1.0), `AppModel.setLoupeZoomScale(_:)`, `AppModel.zoomLoupeToMax()` — click-to-zoom now sets scale to `maxScale` instead of binary toggle. `resetLoupeZoom()` resets scale to 1.0.
- Consumes: `LoupeZoomGeometry.maxScale` from Task 1 (for `zoomLoupeToMax` the caller must compute maxScale from the asset/viewport; `zoomLoupeToMax` takes the maxScale as a parameter to avoid a viewport dependency in the model).

- [ ] **Step 1: Write failing tests for zoom scale state**

Add these to `AppModelTests.swift` near the existing loupe zoom tests (around line 3880):

```swift
func testLoupeZoomScaleDefaultsToOne() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-scale-default", size: 1)])
    XCTAssertEqual(model.loupeZoomScale, 1.0)
}

func testSetLoupeZoomScaleUpdatesScale() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-scale-set", size: 1)])
    model.setLoupeZoomScale(3.5)
    XCTAssertEqual(model.loupeZoomScale, 3.5, accuracy: 0.001)
}

func testSetLoupeZoomScaleClampsToOne() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-scale-clamp", size: 1)])
    model.setLoupeZoomScale(0.5)
    XCTAssertEqual(model.loupeZoomScale, 1.0, accuracy: 0.001)
}

func testZoomLoupePreservesScaleForPanning() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-pan", size: 1)])
    model.setLoupeZoomScale(4.0)
    XCTAssertEqual(model.loupeZoomScale, 4.0, accuracy: 0.001)
    // Pan: zoomLoupe(to:) changes focus but not scale
    model.zoomLoupe(to: LoupeZoomFocus(x: 0.3, y: 0.7))
    XCTAssertEqual(model.loupeZoomScale, 4.0, accuracy: 0.001)
    XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.3, y: 0.7))
}

func testResetLoupeZoomResetsScaleToOne() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-reset", size: 1)])
    model.setLoupeZoomScale(4.0)
    model.zoomLoupe(to: .center)
    model.resetLoupeZoom()
    XCTAssertEqual(model.loupeZoomScale, 1.0, accuracy: 0.001)
    XCTAssertNil(model.loupeZoomFocus)
}

func testZoomLoupeToMaxSetsScaleAndFocus() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-max", size: 1)])
    model.zoomLoupeToMax(scale: 8.0, focus: .center)
    XCTAssertEqual(model.loupeZoomScale, 8.0, accuracy: 0.001)
    XCTAssertEqual(model.loupeZoomFocus, .center)
}

func testToggleLoupeZoomCyclesBetweenFitAndMax() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-toggle", size: 1)])
    // nil → zoom to max at center
    model.toggleLoupeZoom(maxScale: 8.0)
    XCTAssertEqual(model.loupeZoomScale, 8.0, accuracy: 0.001)
    XCTAssertEqual(model.loupeZoomFocus, .center)
    // max → back to fit
    model.toggleLoupeZoom(maxScale: 8.0)
    XCTAssertEqual(model.loupeZoomScale, 1.0, accuracy: 0.001)
    XCTAssertNil(model.loupeZoomFocus)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppModelTests --filter "LoupeZoomScale\|SetLoupeZoom\|ZoomLoupeToMax\|ToggleLoupeZoomCycles" 2>&1 | tail -10`
Expected: FAIL — `loupeZoomScale`, `setLoupeZoomScale`, `zoomLoupeToMax` do not exist.

- [ ] **Step 3: Add zoom scale state to AppModel**

In `AppModel.swift`, after line 2138 (`loupeZoomFocus`), add:

```swift
// Continuous loupe zoom scale: 1.0 = aspect-fitted, >1.0 = zoomed.
// Reset alongside loupeZoomFocus whenever the selection moves.
public private(set) var loupeZoomScale: CGFloat = 1.0
```

Update `resetLoupeZoom()` (line 7528):

```swift
public func resetLoupeZoom() {
    loupeZoomFocus = nil
    loupeZoomScale = 1.0
    loupeFaceZoomIndex = nil
}
```

Update `zoomLoupe(to:)` (line 7523) — just sets focus, does NOT change scale (used by pan gesture which keeps current scale):
```swift
public func zoomLoupe(to focus: LoupeZoomFocus) {
    loupeZoomFocus = focus
    loupeFaceZoomIndex = nil
}
```

Add new methods after `zoomLoupe(to:)`:

```swift
/// Sets a continuous zoom scale (clamped to >= 1.0).
public func setLoupeZoomScale(_ scale: CGFloat) {
    loupeZoomScale = max(1.0, scale)
    if loupeZoomScale == 1.0 {
        loupeZoomFocus = nil
    } else if loupeZoomFocus == nil {
        loupeZoomFocus = .center
    }
}

/// Click-to-zoom: jumps to maxScale centered on a point.
public func zoomLoupeToMax(scale: CGFloat, focus: LoupeZoomFocus) {
    loupeZoomScale = max(1.0, scale)
    loupeZoomFocus = focus
    loupeFaceZoomIndex = nil
}
```

Update `toggleLoupeZoom()` (line 7518):

```swift
public func toggleLoupeZoom(maxScale: CGFloat = 8.0) {
    if loupeZoomFocus == nil {
        loupeZoomScale = max(1.0, maxScale)
        loupeZoomFocus = .center
    } else {
        resetLoupeZoom()
    }
    loupeFaceZoomIndex = nil
}
```

Update `zoomToNearestFaceOrCycleFace()` (line 7547) to set scale when entering zoom from fit:

```swift
public func zoomToNearestFaceOrCycleFace() {
    guard !loupeFaceFocuses.isEmpty else {
        loupeFaceZoomIndex = nil
        loupeZoomFocus = .center
        return
    }
    let nextIndex: Int
    if let currentIndex = loupeFaceZoomIndex {
        nextIndex = LoupeFaceZoomTargeting.wrappedIndex(current: currentIndex, faceCount: loupeFaceFocuses.count)
    } else {
        nextIndex = LoupeFaceZoomTargeting.nearestFaceIndex(
            to: loupeZoomFocus ?? .center,
            among: loupeFaceFocuses
        ) ?? 0
    }
    loupeFaceZoomIndex = nextIndex
    loupeZoomFocus = loupeFaceFocuses[nextIndex]
    if loupeZoomScale < 1.001 {
        loupeZoomScale = 8.0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "LoupeZoomScale\|SetLoupeZoom\|ZoomLoupeToMax\|ToggleLoupeZoomCycles\|ResetLoupeZoomResetsScale" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "Add continuous loupeZoomScale state to AppModel

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: HUD Shows Dynamic Zoom Percentage

**Files:**
- Modify: `Sources/TeststripApp/LoupeZoomView.swift:154-184` (LoupeZoomHUDPresentation)
- Test: `Tests/TeststripAppTests/LoupeZoomHUDPresentationTests.swift`

**Interfaces:**
- Produces: `LoupeZoomHUDPresentation(scale:fullResolutionStatus:)` — replaces the old init that hardcoded "100%".

- [ ] **Step 1: Write failing tests for dynamic HUD percentage**

Add to `LoupeZoomHUDPresentationTests.swift`:

```swift
func testSatisfiedWithScaleShowsPercentage() {
    let presentation = LoupeZoomHUDPresentation(scale: 2.5, fullResolutionStatus: .satisfied)
    XCTAssertEqual(presentation.zoomLabelText, "250%")
    XCTAssertNil(presentation.statusText)
}

func testLoadingWithScaleShowsPercentage() {
    let presentation = LoupeZoomHUDPresentation(scale: 12.0, fullResolutionStatus: .loading)
    XCTAssertEqual(presentation.zoomLabelText, "1200%")
    XCTAssertEqual(presentation.statusText, "Loading full resolution…")
}

func testUnavailableWithScaleShowsPercentage() {
    let presentation = LoupeZoomHUDPresentation(scale: 4.0, fullResolutionStatus: .unavailable)
    XCTAssertEqual(presentation.zoomLabelText, "400%")
    XCTAssertEqual(presentation.statusText, "Full resolution unavailable")
}

func testScale1Shows100() {
    let presentation = LoupeZoomHUDPresentation(scale: 1.0, fullResolutionStatus: .satisfied)
    XCTAssertEqual(presentation.zoomLabelText, "100%")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LoupeZoomHUDPresentationTests 2>&1 | tail -10`
Expected: FAIL — `LoupeZoomHUDPresentation(scale:fullResolutionStatus:)` does not exist.

- [ ] **Step 3: Update LoupeZoomHUDPresentation**

In `LoupeZoomView.swift`, replace the `LoupeZoomHUDPresentation` init (lines 159-172):

```swift
struct LoupeZoomHUDPresentation: Equatable {
    var zoomLabelText: String
    var statusText: String?
    var isLoading: Bool

    init(scale: CGFloat, fullResolutionStatus: LoupeZoomFullResolutionStatus) {
        zoomLabelText = "\(Int((scale * 100).rounded()))%"
        switch fullResolutionStatus {
        case .satisfied:
            statusText = nil
            isLoading = false
        case .loading:
            statusText = "Loading full resolution…"
            isLoading = true
        case .unavailable:
            statusText = "Full resolution unavailable"
            isLoading = false
        }
    }

    var accessibilityValue: String {
        switch (statusText, isLoading) {
        case (nil, _):
            return zoomLabelText
        case (.some, true):
            return "\(zoomLabelText), loading full resolution"
        case (.some, false):
            return "\(zoomLabelText), full resolution unavailable"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LoupeZoomHUDPresentationTests 2>&1 | tail -10`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LoupeZoomView.swift Tests/TeststripAppTests/LoupeZoomHUDPresentationTests.swift
git commit -m "HUD shows dynamic zoom percentage based on scale

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: MagnificationGesture on Loupe Image

**Files:**
- Modify: `Sources/TeststripApp/LoupeZoomView.swift:191-380` (LoupeZoomStageView)
- Test: `Tests/TeststripAppTests/LoupeZoomHUDPresentationTests.swift` (already updated) — no new tests needed here since gesture wiring is view-level; the geometry and state tests in Tasks 1-2 cover the math.

**Interfaces:**
- Consumes: `AppModel.loupeZoomScale`, `AppModel.setLoupeZoomScale(_:)`, `LoupeZoomGeometry.displaySize(for:)`, `LoupeZoomGeometry.offset(for:scale:)`, `LoupeZoomGeometry.focus(pannedBy:from:scale:)`, `LoupeZoomGeometry.clampedFocus(_:scale:)`, `LoupeZoomHUDPresentation(scale:fullResolutionStatus:)` from Tasks 1-3.

- [ ] **Step 1: Update LoupeZoomStageView to use continuous scale**

In `LoupeZoomView.swift`, update `LoupeZoomStageView`:

1. `isZoomed` (line 201-203) — no change needed. `loupeZoomFocus != nil` is still the correct check because `setLoupeZoomScale(1.0)` clears `loupeZoomFocus` and any scale > 1.0 sets it.

2. Add `@GestureState` and `@State` for pinch tracking (after line 199):
```swift
@GestureState private var pinchScale: CGFloat = 1.0
@State private var pinchBaseScale: CGFloat = 1.0
```

3. `stageContent` (lines 236-247) — no change needed. The existing logic (`if let focus = model.loupeZoomFocus` → zoomed, else → fitted) already works with continuous scale because `setLoupeZoomScale(1.0)` clears `loupeZoomFocus` and any scale > 1.0 sets `loupeZoomFocus`.

4. Update `fittedImage` (lines 249-264) — click-to-zoom now uses `zoomLoupeToMax`:
```swift
private func fittedImage(_ image: NSImage, viewportSize: CGSize) -> some View {
    Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(width: viewportSize.width, height: viewportSize.height)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            let geometry = zoomGeometry(viewportSize: viewportSize, image: image)
            let focus = geometry.focus(atFittedViewportPoint: location)
            model.zoomLoupeToMax(scale: geometry.maxScale, focus: focus)
        }
        .overlay {
            faceBoxOverlay(viewportSize: viewportSize, image: image)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Zoom to 100%")
}
```

5. Update `zoomedImage` (lines 286-308) to use continuous scale and add magnification gesture:
```swift
private func zoomedImage(_ image: NSImage, focus: LoupeZoomFocus, viewportSize: CGSize) -> some View {
    let geometry = zoomGeometry(viewportSize: viewportSize, image: image)
    let displaySize = geometry.displaySize(for: model.loupeZoomScale)
    let offset = geometry.offset(for: focus, scale: model.loupeZoomScale)
    return ZStack {
        Image(nsImage: image)
            .resizable()
            .frame(width: displaySize.width, height: displaySize.height)
            .position(
                x: viewportSize.width / 2 + offset.width,
                y: viewportSize.height / 2 + offset.height
            )
    }
    .frame(width: viewportSize.width, height: viewportSize.height)
    .clipped()
    .contentShape(Rectangle())
    .onTapGesture {
        model.resetLoupeZoom()
    }
    .gesture(panGesture(geometry: geometry))
    .gesture(magnificationGesture(geometry: geometry))
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Return to fit")
}
```

6. Add magnification gesture method after `panGesture` (after line 320):
```swift
private func magnificationGesture(geometry: LoupeZoomGeometry) -> some Gesture {
    MagnificationGesture()
        .onChanged { value in
            if pinchBaseScale == 1.0 {
                pinchBaseScale = model.loupeZoomScale
            }
            let newScale = pinchBaseScale * value
            let clamped = min(max(1.0, newScale), geometry.maxScale)
            model.setLoupeZoomScale(clamped)
        }
        .onEnded { _ in
            pinchBaseScale = 1.0
        }
}
```

7. Update `panGesture` (lines 310-320) to pass the current scale:
```swift
private func panGesture(geometry: LoupeZoomGeometry) -> some Gesture {
    DragGesture(minimumDistance: 1)
        .onChanged { value in
            let start = dragStartFocus ?? model.loupeZoomFocus ?? .center
            dragStartFocus = start
            model.zoomLoupe(to: geometry.focus(
                pannedBy: value.translation,
                from: start,
                scale: model.loupeZoomScale
            ))
        }
        .onEnded { _ in
            dragStartFocus = nil
        }
}
```

7. Update `zoomHUD` (lines 322-345) to pass scale:
```swift
private var zoomHUD: some View {
    let presentation = LoupeZoomHUDPresentation(
        scale: model.loupeZoomScale,
        fullResolutionStatus: model.loupeZoomFullResolutionStatus(for: asset.id)
    )
    return HStack(spacing: 8) {
        if presentation.isLoading {
            ProgressView()
                .controlSize(.small)
        }
        if let statusText = presentation.statusText {
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Text(presentation.zoomLabelText)
            .font(.caption.monospacedDigit().weight(.semibold))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loupe zoom")
    .accessibilityValue(presentation.accessibilityValue)
}
```

8. The full-resolution request `.task(id:)` (lines 219-226) — no change needed. `isZoomed` still correctly gates the request, and `LoupeZoomRenderPolicy` (Task 5) determines whether full-res is actually served.

- [ ] **Step 2: Run all tests to verify nothing breaks**

Run: `swift test 2>&1 | tail -10`
Expected: PASS — all existing tests pass (existing `toggleLoupeZoom` callers may need updating to pass `maxScale:`).

- [ ] **Step 3: Fix any compilation errors from toggleLoupeZoom signature change**

Search for `toggleLoupeZoom` callers and add the `maxScale` parameter where needed. The default value of 8.0 covers most cases; if any test or view calls it without the parameter, the default applies.

Run: `grep -rn "toggleLoupeZoom" Sources/ Tests/`
Fix any calls that pass no arguments — they should compile with the default.

- [ ] **Step 4: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LoupeZoomView.swift
git commit -m "Add MagnificationGesture for continuous pinch-to-zoom in loupe

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Generalize LoupeZoomRenderPolicy for Continuous Scale

**Files:**
- Modify: `Sources/TeststripApp/LoupeZoomView.swift:17-24` (LoupeZoomRenderPolicy)
- Modify: `Sources/TeststripApp/AppModel.swift:10214-10233` (requestLoupeFullResolutionPreview), `10235-10251` (loupeZoomFullResolutionStatus)
- Test: `Tests/TeststripAppTests/LoupeZoomRenderPolicyTests.swift`

**Interfaces:**
- Produces: `LoupeZoomRenderPolicy.fullResolutionIsRequired(cachedLevel:assetMaxPixelDimension:displayScale:)` — new overload that considers the actual display scale to decide if the cached preview is being stretched beyond its native resolution.

- [ ] **Step 1: Write failing test for scale-aware render policy**

Add to `LoupeZoomRenderPolicyTests.swift`:

```swift
func testFullResolutionNotRequiredWhenCachedLevelCoversAtScale() {
    // Large preview (3200px max) covering a 6000px asset at displayScale 2:
    // The loupe shows at most 3200/2 = 1600pt wide. At scale 2.0, the fitted
    // image is ~1000pt, so displaySize = 2000pt < 3200. No original needed.
    XCTAssertFalse(LoupeZoomRenderPolicy.fullResolutionIsRequired(
        cachedLevel: .large,
        assetMaxPixelDimension: 6000,
        displayScale: 2.0,
        loupeScale: 2.0,
        fittedDisplayWidth: 1000
    ))
}

func testFullResolutionRequiredWhenScaleExceedsCachedLevel() {
    // Large preview (3200px) for a 12000px asset at displayScale 1:
    // At maxScale, displaySize = 12000pt >> 3200px. Original needed.
    XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
        cachedLevel: .large,
        assetMaxPixelDimension: 12000,
        displayScale: 1.0,
        loupeScale: 12.0,
        fittedDisplayWidth: 1000
    ))
}

func testFullResolutionRequiredWhenNoCachedLevel() {
    XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
        cachedLevel: nil,
        assetMaxPixelDimension: 6000,
        displayScale: 2.0,
        loupeScale: 3.0,
        fittedDisplayWidth: 1000
    ))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LoupeZoomRenderPolicyTests 2>&1 | tail -10`
Expected: FAIL — new overload doesn't exist.

- [ ] **Step 3: Add scale-aware overload to LoupeZoomRenderPolicy**

In `LoupeZoomView.swift`, add to `LoupeZoomRenderPolicy` after line 23:

```swift
/// Decides if original-resolution is needed at a continuous zoom scale:
/// when the displayed pixel demand exceeds what the cached preview level
/// can deliver without upscaling.
static func fullResolutionIsRequired(
    cachedLevel: PreviewLevel?,
    assetMaxPixelDimension: Int?,
    displayScale: CGFloat,
    loupeScale: CGFloat,
    fittedDisplayWidth: CGFloat
) -> Bool {
    guard let cachedLevel else { return true }
    guard let cachedMaxPixelDimension = cachedLevel.maxPixelDimension else { return false }
    guard assetMaxPixelDimension != nil else { return true }
    // Displayed width in points at the current zoom scale
    let displayedWidth = fittedDisplayWidth * loupeScale * displayScale
    return displayedWidth > CGFloat(cachedMaxPixelDimension)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LoupeZoomRenderPolicyTests 2>&1 | tail -10`
Expected: PASS — all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LoupeZoomView.swift Tests/TeststripAppTests/LoupeZoomRenderPolicyTests.swift
git commit -m "Generalize LoupeZoomRenderPolicy for continuous scale

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Grid Pinch-to-Expand Overlay

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift:191-225` (mainContent — add @Namespace), `9478-9534` (AssetGridCell — add MagnificationGesture), `6588-6591` (openAssetInLibraryLoupe — seed transition)
- Modify: `Sources/TeststripApp/AppModel.swift` (add gridExpandTransition state)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `AppModel.loupeZoomScale`, `LoupeZoomGeometry` from Tasks 1-2.
- Produces: `AppModel.gridExpandTransition: GridExpandTransition?`, `struct GridExpandTransition: Equatable` (cellFrame: CGRect, assetID: AssetID), `AppModel.beginGridExpand(from: CGRect, assetID:)`, `AppModel.endGridExpand()`.

- [ ] **Step 1: Write failing test for grid expand transition state**

Add to `AppModelTests.swift`:

```swift
func testGridExpandTransitionDefaultsToNil() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "grid-expand-default", size: 1)])
    XCTAssertNil(model.gridExpandTransition)
}

func testBeginGridExpandSetsTransition() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "grid-expand-begin", size: 1)])
    let frame = CGRect(x: 100, y: 200, width: 140, height: 100)
    let assetID = AssetID(rawValue: UUID())
    model.beginGridExpand(from: frame, assetID: assetID)
    XCTAssertNotNil(model.gridExpandTransition)
    XCTAssertEqual(model.gridExpandTransition?.cellFrame, frame)
    XCTAssertEqual(model.gridExpandTransition?.assetID, assetID)
}

func testEndGridExpandClearsTransition() {
    let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "grid-expand-end", size: 1)])
    let frame = CGRect(x: 100, y: 200, width: 140, height: 100)
    let assetID = AssetID(rawValue: UUID())
    model.beginGridExpand(from: frame, assetID: assetID)
    model.endGridExpand()
    XCTAssertNil(model.gridExpandTransition)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "GridExpandTransition\|BeginGridExpand\|EndGridExpand" 2>&1 | tail -10`
Expected: FAIL — `gridExpandTransition`, `beginGridExpand`, `endGridExpand` do not exist.

- [ ] **Step 3: Add GridExpandTransition to AppModel**

In `AppModel.swift`, after `loupeZoomScale` (added in Task 2), add:

```swift
/// Active grid→loupe pinch-expand transition, if any.
public private(set) var gridExpandTransition: GridExpandTransition?
```

Add the struct (in `LoupeZoomView.swift` or a new small file — put it in `LoupeZoomView.swift` near the other zoom types):

```swift
/// Frame and asset for a grid→loupe pinch-expand transition.
public struct GridExpandTransition: Equatable, Sendable {
    public var cellFrame: CGRect
    public var assetID: AssetID

    public init(cellFrame: CGRect, assetID: AssetID) {
        self.cellFrame = cellFrame
        self.assetID = assetID
    }
}
```

Add methods to `AppModel`:

```swift
public func beginGridExpand(from frame: CGRect, assetID: AssetID) {
    gridExpandTransition = GridExpandTransition(cellFrame: frame, assetID: assetID)
}

public func endGridExpand() {
    gridExpandTransition = nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "GridExpandTransition\|BeginGridExpand\|EndGridExpand" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Add grid expand pinch scale state to AppModel**

The overlay needs the live pinch scale to grow the image. Add to `AppModel.swift` after `gridExpandTransition`:

```swift
/// Live pinch scale during a grid→loupe expand transition.
public private(set) var gridExpandPinchScale: CGFloat = 1.0

public func setGridExpandPinchScale(_ scale: CGFloat) {
    gridExpandPinchScale = scale
}
```

Update `endGridExpand()` to also reset the pinch scale:

```swift
public func endGridExpand() {
    gridExpandTransition = nil
    gridExpandPinchScale = 1.0
}
```

- [ ] **Step 6: Add MagnificationGesture to grid cells**

The gesture needs the cell's global frame to position the overlay. Since `assetActivation` is a function (not a View struct), it can't hold `@State`. Create a small `ViewModifier` that captures the frame and hosts the gesture.

In `LibraryGridView.swift`, add this private modifier struct near `assetActivation`:

```swift
/// Captures the cell's global frame and hosts a magnification gesture
/// for the grid→loupe pinch-expand.
private struct GridCellPinchModifier: ViewModifier {
    var model: AppModel
    var asset: Asset
    var openInLoupe: (AssetID) -> Void
    @State private var cellFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { cellFrame = proxy.frame(in: .global) }
                }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        model.setGridExpandPinchScale(scale)
                        if scale > 1.3 && model.gridExpandTransition == nil {
                            model.beginGridExpand(from: cellFrame, assetID: asset.id)
                            openInLoupe(asset.id)
                        }
                    }
                    .onEnded { scale in
                        if scale < 1.3 {
                            model.endGridExpand()
                        }
                    }
            )
    }
}
```

Then update `assetActivation` (lines 7869-7914) to apply this modifier. After the existing `.simultaneousGesture(doubleClick)` (line 7903), add:

```swift
.modifier(GridCellPinchModifier(
    model: model,
    asset: asset,
    openInLoupe: openInLoupe
))
```

The full `assetActivation` function becomes:

```swift
func assetActivation(
    for asset: Asset,
    model: AppModel,
    focusCullingSurface: @escaping () -> Void,
    openInLoupe: @escaping (AssetID) -> Void,
    selectAsset: @escaping (AssetID) -> Void
) -> some View {
    let doubleClick = TapGesture(count: 2).onEnded {
        if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .openInLoupe) {
            focusCullingSurface()
        }
        openInLoupe(asset.id)
    }
    return Button {
        if NSEvent.modifierFlags.contains(.shift) {
            if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .batchSelection) {
                focusCullingSurface()
            }
            model.selectBatchRange(to: asset.id)
        } else if NSEvent.modifierFlags.contains(.command) {
            if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .batchSelection) {
                focusCullingSurface()
            }
            model.toggleBatchSelection(asset.id)
        } else {
            if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .singleClickSelection) {
                focusCullingSurface()
            }
            selectAsset(asset.id)
        }
    } label: {
        contentShape(Rectangle())
    }
        .buttonStyle(.plain)
        .simultaneousGesture(doubleClick)
        .modifier(GridCellPinchModifier(
            model: model,
            asset: asset,
            openInLoupe: openInLoupe
        ))
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(asset.originalURL.lastPathComponent)
        .accessibilityValue(assetSelectionAccessibilityValue(for: asset, model: model))
        .accessibilityAction {
            if AssetActivationFocusPolicy.shouldFocusCullingSurface(for: .accessibilitySelection) {
                focusCullingSurface()
            }
            selectAsset(asset.id)
        }
}
```

The `GridCellPinchModifier` captures the cell frame in `@State` via `GeometryReader.onAppear`, then uses it when the pinch exceeds 1.3×. The `beginGridExpand` + `openInLoupe` fires once (guarded by `model.gridExpandTransition == nil`). The `onEnded` cancels if the pinch was too small.

- [ ] **Step 7: Add grid expand overlay to mainContent**

In `LibraryGridView.swift`, update `mainContent` (line 191) to show an overlay when `model.gridExpandTransition` is active. The overlay shows the cell's thumbnail growing from the cell frame, then cross-fades into the loupe.

After the existing `if/else if` block in `mainContent` (around line 224), add an `.overlay`:

```swift
.overlay {
    if let transition = model.gridExpandTransition,
       model.selectedView == .libraryLoupe {
        GridExpandOverlayView(
            model: model,
            transition: transition,
            pinchScale: model.gridExpandPinchScale
        )
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
```

Add the `GridExpandOverlayView` struct in `LibraryGridView.swift`:

```swift
/// Overlay that grows a cell's thumbnail during the grid→loupe pinch-expand.
/// Fades out once the loupe view is visible and has rendered its image.
struct GridExpandOverlayView: View {
    var model: AppModel
    var transition: GridExpandTransition
    var pinchScale: CGFloat

    var body: some View {
        let scaledWidth = transition.cellFrame.width * pinchScale
        let scaledHeight = transition.cellFrame.height * pinchScale
        CachedPreviewImage(
            previewURL: model.previewURL(for: transition.assetID, levels: [.grid]),
            scaling: .fill,
            cacheGeneration: model.previewCacheGeneration(for: transition.assetID)
        )
            .frame(width: scaledWidth, height: scaledHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .position(x: transition.cellFrame.midX, y: transition.cellFrame.midY)
            .opacity(max(0, 1.5 - pinchScale))
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
```

The overlay reuses `CachedPreviewImage` (async, cached) so the grid thumbnail appears instantly — it's already in the cache from the grid display. The overlay fades out as the pinch scale increases past 1.5×, by which point the loupe view is visible underneath. `allowsHitTesting(false)` lets touches pass through to the loupe. `.ignoresSafeArea()` is needed because the cell frame is in global coordinates.

The transition needs to be cleared after the loupe has rendered so the overlay disappears. Add a `.task` to the overlay that waits for the loupe to render, then clears the transition:

```swift
.overlay {
    if let transition = model.gridExpandTransition,
       model.selectedView == .libraryLoupe {
        GridExpandOverlayView(
            model: model,
            transition: transition,
            pinchScale: model.gridExpandPinchScale
        )
        .allowsHitTesting(false)
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            model.endGridExpand()
        }
    }
}
```

This replaces the overlay block from Step 7. The `.task` fires when the overlay appears (when the transition is set) and clears it after 500ms — enough time for the loupe's image to load and the overlay to fade out. If the user pinch-backs (scale < 1.3), `onEnded` calls `endGridExpand()` immediately, the overlay disappears, and the `.task` is cancelled.

- [ ] **Step 8: Handle reduce-motion**

In `mainContent`, when `accessibilityReduceMotion` is true, skip the overlay and open the loupe directly. The existing pattern at line 4012 reads `@Environment(\.accessibilityReduceMotion)`. Add the same read to `mainContent`:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

In the overlay condition, add a reduce-motion check:

```swift
.overlay {
    if !reduceMotion,
       let transition = model.gridExpandTransition,
       model.selectedView == .libraryLoupe {
        GridExpandOverlayView(
            model: model,
            transition: transition,
            pinchScale: model.gridExpandPinchScale
        )
        .allowsHitTesting(false)
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            model.endGridExpand()
        }
    }
}
```

When reduce-motion is on, the overlay is skipped and the loupe appears instantly — the pinch gesture still opens the loupe, just without the growing overlay. The transition is still set (so `beginGridExpand`/`endGridExpand` are called), but without the overlay it has no visual effect. Add a `.task` to the `LoupeView` or `mainContent` to clear the transition when reduce-motion is on:

```swift
.task {
    if reduceMotion && model.gridExpandTransition != nil {
        model.endGridExpand()
    }
}
```

- [ ] **Step 9: Run full test suite**

Run: `swift test 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LoupeZoomView.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "Add grid pinch-to-expand gesture with overlay

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: End-to-End Scenario Test

**Files:**
- Create: `test/scenarios/pinch-zoom-loupe.md`
- Modify: `test/scenarios/LEDGER.md`

**Interfaces:**
- Consumes: all prior tasks.

- [ ] **Step 1: Write the scenario card**

Create `test/scenarios/pinch-zoom-loupe.md`:

```markdown
# Pinch-to-Zoom Loupe Scenario

## Goal
Verify continuous pinch-to-zoom works in the loupe and grid pinch-to-expand opens the loupe.

## Preconditions
- Smoke launch (24 synthetic photos seeded)
- Grid view visible

## Steps

### Open loupe via double-click
1. `ax wait-vended`
2. `ax press --contains "smoke-0.jpg"` (double-click to open loupe)
3. `ax wait --contains "Return to fit"` — verify loupe is showing fitted image

### Verify HUD shows zoom percentage
4. The zoom HUD should NOT be visible (image is fitted, scale 1.0)
5. `ax press --contains "Return to fit"` — click to zoom to 100%
6. `ax wait --contains "100%"` — verify HUD shows 100%

### Return to fit
7. `ax press --contains "Return to fit"` — click again to return to fit
8. Verify HUD is gone

### Return to grid
9. Press Escape
10. `ax wait --contains "smoke-0.jpg"` — verify grid is back

## Catalog Assertions
- `SELECT COUNT(*) FROM assets` = 24 (no changes from zooming)
- `SELECT detail FROM work_sessions ORDER BY rowid DESC LIMIT 1` — no new work sessions from zoom interaction

## Notes
- Pinch gesture simulation via AX is limited on macOS. The scenario verifies click-to-zoom (which now sets continuous scale) and HUD percentage display. Pinch gesture itself is verified manually.
- Reduce-motion: zoom should work without animation; the scale change is instant.
```

- [ ] **Step 2: Register the scenario in the ledger**

Add to `test/scenarios/LEDGER.md`:

```markdown
| pinch-zoom-loupe | pinch-zoom-loupe.md — Pinch-to-zoom in loupe + grid expand scenario | Spec'd | VM e2e (ax+sql) | — | new card authored 2026-08-17; verifies click-to-zoom sets continuous scale, HUD shows percentage, grid→loupe navigation | pending live VM run |
```

- [ ] **Step 3: Run the scenario in VM (if available)**

If the VM is available:
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax "wait-vended"
# Drive through the scenario steps
# Verify catalog assertions
```

- [ ] **Step 4: Commit**

```bash
git add test/scenarios/pinch-zoom-loupe.md test/scenarios/LEDGER.md
git commit -m "Add pinch-zoom-loupe end-to-end scenario card

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
```

- [ ] **Step 5: Update LEDGER status after VM run**

If VM run passes, update status to `Tested-Pass`. If VM unavailable, leave as `Spec'd` with note.
