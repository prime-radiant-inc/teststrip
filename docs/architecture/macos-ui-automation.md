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

The selected-thumbnail feedback probe is:

```bash
./script/verify_grid_selection_feedback.sh Teststrip
```

It presses a visible thumbnail and waits until that same thumbnail exposes `Selected` through Accessibility. Use it when changing grid-cell selection visuals or activation behavior.

The Import Path probe is:

```bash
./script/verify_import_path.sh Teststrip
```

It creates a temporary PNG folder, opens the Import Path sheet, fills the focused sheet field, presses Import, waits for visible import feedback, and then waits until the imported thumbnail is visible. Use it after `./script/build_and_run.sh --verify-smoke` when checking the first-run import flow.

The probe also emits `teststrip_import_metric` lines for feedback visibility duration, import visibility duration, import count, app/worker CPU and RSS snapshots, pending preview count after a fixed sample window, and final preview-drain status. Use a larger count when checking import and preview throughput:

```bash
TESTSTRIP_AX_IMPORT_COUNT=600 TESTSTRIP_AX_TIMEOUT_SECONDS=75 ./script/verify_import_path.sh Teststrip
```

The full app workflow wrapper chains the focused UI probes and emits `teststrip_app_workflow_resource` snapshots after each step:

```bash
./script/verify_app_workflows.sh Teststrip
```

Each snapshot records the app and worker PID, CPU percent, and RSS in KB. These numbers are diagnostic evidence, not pass/fail thresholds; use them to catch obviously hot or growing processes while keeping the individual probes responsible for behavioral assertions.

The submit-only Import Path helper is:

```bash
./script/submit_import_path.sh Teststrip /path/to/photos
```

It opens the Import Path sheet, submits a directory, and exits without waiting for visible feedback or walking the whole app accessibility tree. Use it with catalog polling when separating raw catalog/import latency from AX traversal overhead. A 600-image smoke import measured through this path reached the catalog about 0.12s after submit and completed import work about 0.53s after submit, while the full AX visibility probe still reported much slower target-visible timings.

Primary Card Import uses `NSOpenPanel` folder selection for both the card/source folder and the destination root, because sandboxed packaged runs need user-granted security-scoped access. Typed card-path helpers are useful for automation and latency isolation, but they are not proof of sandbox import permissions; sandboxed card-import smoke should exercise the panel route when focus-stealing UI automation is acceptable.

The imported-grid culling probe is:

```bash
./script/verify_imported_grid_culling.sh Teststrip
```

It imports a temporary image set, targets a non-first imported thumbnail, verifies selected-thumbnail feedback, applies a keyboard 5-star rating, and waits until the inspector exposes `Rating: 5`. Use it when checking the path Jesse reported as janky: import, click an imported image, and rate it.

The keyboard culling probe is:

```bash
./script/verify_keyboard_culling.sh Teststrip
```

It selects a visible thumbnail, clears its rating through the Culling menu, sends the `"5"` keystroke through System Events, and waits until the inspector shows `Rating: 5`. Use character keystrokes rather than raw key codes in these probes; raw key codes are keyboard-layout and synthetic-event-shape fragile.

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

To clean up old isolated smoke catalogs without touching the real catalog, first run:

```bash
./script/reset_isolated_test_data.sh
```

The default mode is a dry run. It only reports direct `teststrip-app-support.*` directories under `${TMPDIR:-/tmp}` or `TESTSTRIP_ISOLATED_TEST_DATA_ROOT`, only when they contain Teststrip catalog/preview/smoke markers, and skips app-support roots that belong to a currently running Teststrip process. Add `--delete` after reviewing the dry-run output.

## Failed Fixes

Do not repeat these without a new hypothesis:

- Clearing saved app state and app defaults.
- Launching with `open -F`.
- Forcing `System Events` process visibility and `tell application "Teststrip" to activate`.
- Adding an app launch hook that calls `NSApp.unhide(nil)`, `NSApp.activate(ignoringOtherApps: true)`, and `makeKeyAndOrderFront`.
- Posting synthetic mouse events with `cliclick` or `CGEvent.postToPid` as the primary verification path.

## Next Work

Keep adding small, scenario-specific Accessibility probes only when they prove user-visible behavior. UI changes should still be verified with model tests where possible plus CoreGraphics window captures for visual regressions.
