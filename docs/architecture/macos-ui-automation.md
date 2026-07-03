# macOS UI Automation

## Current State

The SwiftPM-built app bundle renders a real Teststrip window, and CoreGraphics can capture it by window id with `script/capture_app_window.sh`.

In the Codex desktop launch context, Accessibility does not currently expose that window:

- `System Events` reports the `Teststrip` process as visible but with `0` windows.
- Whole-screen `screencapture` does not include the Teststrip window.
- `screencapture -l <CoreGraphics window id>` captures the rendered app window correctly.
- Synthetic clicks posted through screen coordinates or to the process id do not change grid selection in this state.

The useful automation path today is visual verification by CoreGraphics window capture, not interactive UI driving through Accessibility or Computer Use.

## Evidence

The repeated probe is:

```bash
osascript -e 'tell application "System Events" to tell process "Teststrip" to get {frontmost, visible, count of windows}'
./script/capture_app_window.sh Teststrip /tmp/teststrip-window.png
```

Expected current result in this environment:

```text
false, true, 0
/tmp/teststrip-window.png
```

The app logs also show LaunchServices/AppKit restoring a SwiftUI window while later reporting `No windows open yet` through the Accessibility path.

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
- Posting synthetic mouse events with `cliclick` or `CGEvent.postToPid`.

## Next Work

The likely durable fix is to revisit packaging/window management rather than patching view code blindly. Until then, UI changes should be verified with model tests where possible plus CoreGraphics window captures for visual regressions.
