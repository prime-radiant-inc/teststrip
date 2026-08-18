# Pinch-to-Zoom Loupe Scenario

## Goal
Verify continuous pinch-to-zoom works in the loupe — including from the fitted
(non-zoomed) state — by synthesizing real `NSEventTypeMagnify` gesture events
and driving them through the live UI in the Tart VM.

## Preconditions
- Smoke launch (24 synthetic photos seeded) via `vm_scenario_run.sh sync smoke && launch smoke`
- App launched and frontmost (`ax wait-vended Teststrip`)
- Gesture toolchain deployed: `script/pinch_deploy.sh` (requires Hammerspoon installed on host)

## Automated Driver

`script/verify_pinch_zoom.sh` runs the full scenario end-to-end in the VM.
It synthesizes magnify events with `script/pinch_post.m` (backed by
Hammerspoon's `libeventtapevent.dylib`) and verifies state transitions via AX.

## Steps

### Open loupe via Loupe lens
1. `ax wait-vended Teststrip`
2. `key 'keystroke "3" using command down'` — press ⌘3 for Loupe lens
3. `ax wait --contains "Zoom to 100%"` — verify loupe is in fitted state

### Verify fitted state
4. Assert "Zoom to 100%" is present (fitted image accessibility label)
5. Assert "Return to fit" is absent (zoomed image not rendered)
6. Assert "Loupe zoom" is absent (zoom HUD only shows when zoomed)

### Pinch out from fitted state (automated)
7. Post magnify events: `pinch_post <pid> 1.0 2.0 30 20`
   - Posts 30 NSEventTypeMagnify events via `kCGSessionEventTap`
   - Magnification deltas are cumulative: 0.0 → 1.0 (100% size increase = 2× scale)
   - Events are created with `tl_CGEventCreateFromGesture` (from Hammerspoon's dylib)
8. Assert "Zoom to 100%" is absent (fitted image swapped out)
9. Assert "Return to fit" is present (zoomed image rendered)
10. Assert "Loupe zoom" HUD is present (zoom state active)

### Pinch back to fitted state (automated)
11. Post reverse magnify events: `pinch_post <pid> 2.0 1.0 30 20`
    - Magnification deltas: 0.0 → -0.5 (50% size decrease = 1× scale)
    - On gesture end, `magnificationGesture.onEnded` calls `resetLoupeZoom`
      when `loupeZoomScale ≤ 1.02`
12. Assert "Zoom to 100%" is present (fitted image restored)
13. Assert "Return to fit" is absent (zoomed image gone)
14. Assert "Loupe zoom" HUD is absent (zoom state exited)

### Return to grid
15. `key 'key code 53'` — press Escape
16. `ax wait --contains "Grid"` — verify grid is back

## Catalog Assertions
- `sql smoke 'SELECT COUNT(*) FROM assets'` = 24 (no changes from zooming)
- `sql smoke 'SELECT COUNT(*) FROM work_sessions'` = 0 (no new work sessions from zoom interaction)

## Verification Indicators

The zoom state is verified through three AX elements that appear/disappear
based on `isZoomed` (`model.loupeZoomFocus != nil`):

| State | "Zoom to 100%" | "Return to fit" | "Loupe zoom" HUD |
|-------|---------------|-----------------|------------------|
| Fitted | present | absent | absent |
| Zoomed | absent | present | present |

- **"Zoom to 100%"**: `accessibilityLabel` on the fitted image (`fittedImage`)
- **"Return to fit"**: `accessibilityLabel` on the zoomed image (`zoomedImage`)
- **"Loupe zoom"**: zoom HUD overlay, only rendered when `isZoomed` (`.overlay { if isZoomed { zoomHUD } }`)

## Notes

### How pinch event synthesis works

macOS does not expose a public API to create `NSEventTypeMagnify` (type 30)
events. `CGEvent` cannot create type 30 directly — `NSEvent(CGEvent:)` returns
nil with "unrecognized type is 30". The solution uses Hammerspoon's
`libeventtapevent.dylib`, which contains the private `tl_CGEventCreateFromGesture`
function (from Nathan Vander Wilt's TouchEvents framework, 2010) compiled into
the dylib itself. The function creates a CGEvent (type 29, `kCGEventGesture`)
that the CGEvent-to-NSEvent bridge remaps to type 30 (magnify). Events are
posted via `CGEventPost(kCGSessionEventTap, event)` — **not** `CGEventPostToPid`,
which does not deliver gesture events reliably.

### Magnification value mapping

Per `NSEvent.h`: magnification is a cumulative delta, not a scale factor.
A magnification of 1.0 = 100% size increase. SwiftUI's `MagnificationGesture`
value = `1 + magnification`, so `newScale = baseScale * (1 + magnification)`.
The `pinch_post` tool computes: `totalMag = toScale / fromScale - 1.0`.

### Key constants
- `kTLInfoSubtypeMagnify = 0x08` (gesture subtype for magnify)
- IOHIDEvent phases: began=1, changed=2, ended=4
- `kTLInfoKeyGestureSubtype`, `kTLInfoKeyGesturePhase`, `kTLInfoKeyMagnification`
  are `const CFStringRef*` — dlsym returns a pointer to the pointer, must dereference

### Build/deploy
- `script/pinch_post.m` — the synthesizer source (ObjC)
- `script/pinch_deploy.sh` — builds pinch_post, extracts arm64 slice of
  Hammerspoon's dylib + LuaSkin.framework, deploys to VM
- Hammerspoon must be installed on the host (`/Applications/Hammerspoon.app`)

### Unit test coverage
The unit test `testPinchFromFittedStateEntersZoomMode` in
`AppModelTests.swift` covers the model-level behavior: `setLoupeZoomScale(>1.0)`
when `loupeZoomFocus == nil` enters zoom mode (sets focus to `.center`),
and `resetLoupeZoom` on pinch-end at ~1.0 returns to fit.

### VM-verified 2025-08-18
All steps pass in Tart VM with macOS 15. The pinch synthesizer successfully
drives the fitted → zoomed → fitted cycle through the live UI.
