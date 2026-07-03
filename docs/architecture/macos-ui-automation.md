# macOS UI Automation

## Current State

The SwiftPM-built app bundle renders a real Teststrip window, CoreGraphics can capture it by window id with `script/capture_app_window.sh`, and Accessibility can drive visible grid thumbnails with `AXPress`.

Use Accessibility for focused interaction checks and CoreGraphics window capture for visual review. Synthetic screen-coordinate clicks are still less useful because coordinate calibration varies by launch context and window state.

## Evidence

The basic visual probe is:

```bash
./script/capture_app_window.sh Teststrip /tmp/teststrip-window.png
```

The grid activation probe is:

```bash
./script/verify_grid_activation.sh Teststrip
```

It finds the first visible image thumbnail button, performs `AXPress`, and waits until the inspector exposes that filename as the selected asset. Pass a filename as the second argument to require a specific visible thumbnail.

The Import Path probe is:

```bash
./script/verify_import_path.sh Teststrip
```

It creates a temporary PNG folder, opens the Import Path sheet, fills the focused sheet field, presses Import, and waits until the imported thumbnail is visible. Use it after `./script/build_and_run.sh --verify-smoke` when checking the first-run import flow.

The keyboard culling probe is:

```bash
./script/verify_keyboard_culling.sh Teststrip
```

It selects a visible thumbnail, clears its rating through the Culling menu, sends the `5` key through System Events, and waits until the inspector shows `Rating: 5`.

The selected-photo evaluation probe is:

```bash
./script/verify_evaluation.sh Teststrip
```

It selects a visible thumbnail, presses Evaluate, and waits until provider signals appear in the inspector. Use it with the seeded smoke catalog, which has cached previews available for local-first evaluation.

## Seeded Visual Smoke

Use a fresh temporary app-support directory when a screenshot needs real grid content instead of an empty isolated catalog:

```bash
./script/build_and_run.sh --verify-smoke
./script/capture_app_window.sh Teststrip /tmp/teststrip-seeded-smoke.png
```

`--verify-smoke` creates a fresh isolated app-support directory, runs `TeststripBench seed-app-catalog`, launches the app with `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY`, and verifies the process is running. The seeder writes generated JPEG originals, catalog rows, a starred `Smoke Picks` set, and cached micro/grid/medium/large previews under the same `Teststrip/` app-support layout the app uses. It refuses to write over an existing `catalog.sqlite`, so do not point the raw seeder command at a real catalog.

## Failed Fixes

Do not repeat these without a new hypothesis:

- Clearing saved app state and app defaults.
- Launching with `open -F`.
- Forcing `System Events` process visibility and `tell application "Teststrip" to activate`.
- Adding an app launch hook that calls `NSApp.unhide(nil)`, `NSApp.activate(ignoringOtherApps: true)`, and `makeKeyAndOrderFront`.
- Posting synthetic mouse events with `cliclick` or `CGEvent.postToPid` as the primary verification path.

## Next Work

Keep adding small, scenario-specific Accessibility probes only when they prove user-visible behavior. UI changes should still be verified with model tests where possible plus CoreGraphics window captures for visual regressions.
