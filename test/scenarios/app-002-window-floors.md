# app-002-window-floors: each workspace holds its chrome at its minimum window width

**What this covers**: Jesse works on a laptop screen and shrinks the window;
each workspace must hold its chrome at its documented floor. Inventory items
7-8: per-workspace `AppWindowLayoutMetrics.minimumWidth(for:)`
(Library 1000pt / Cull 800pt) live-switches with the workspace, and minHeight
720 / default 1520x820 (`Sources/TeststripApp/main.swift`). People is a Library
sub-view now, not its own workspace, so it rides the Library 1000pt floor (its
old 700pt floor is gone).

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Press ⌘2 (Library). Resize the window to exactly 1000pt wide (AppleScript
   `System Events` `set size of window 1 of process "Teststrip" to {1000, <h>}`,
   or drag via AX if a resize verb exists). Assert: no horizontal scrollbar
   appears on the window itself, the query token field, result header, and
   grid/view-mode switcher are all still present in the AX tree
   (`ax_drive.sh find` each), and none report a frame that extends past the
   window's right edge (compare AXFrame width to window width if available).
3. Press ⌘1 (Cull). Resize to 800pt. Assert: sidebar (source picker), HUD,
   and pick/reject controls remain present and unclipped.
4. Still in Library (⌘2), select **People** from the Library sub-view toggle.
   People rides the Library floor now, so the window still refuses to shrink
   below 1000pt. Resize toward 1000pt and assert: People's panels are present
   without being pushed off-screen or overlapping, and no panel's AXFrame
   extends past the window or reports a negative origin. **There is no separate
   700pt People floor** — asking for <1000pt clamps to the Library floor.

## Expected
- Every key element listed above is present and fully within the window
  frame at that workspace's documented floor.
- **Fails if** any control's AXFrame width+origin exceeds the window width
  (clipped/overflowing chrome), or if an element that should be present
  (sidebar, HUD, queue panel) is missing at the floor — meaning the fixed
  320pt panels don't actually fit in 700pt and something got squeezed out
  instead of adapting.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- A prior run was BLOCKED-CONSOLE: floor values confirmed by source read
  only (`Sources/TeststripApp/main.swift`); the resize assertions have never
  run live. People no longer has its own floor — it's a Library view — so the
  only floors to enforce are Library 1000pt and Cull 800pt.
- Resizing via System Events `set size of window 1` uses points on a
  non-retina VM display; confirm the resulting AXSize actually reads the
  requested width before asserting anything about clipping — SwiftUI clamps
  to `minWidth`, so asking for less than the floor is the cheap way to prove
  the floor is enforced (window refuses to shrink below it).
- Item 8's default 1520x820 only applies to a first-ever window; an isolated
  launch with a fresh app-support dir still restores frame from the
  `com.teststrip.app` defaults domain if one exists on the machine. Assert
  the default size only on a VM/user account that has never run the app, or
  after `defaults delete com.teststrip.app` — otherwise skip that assertion
  and say so.
