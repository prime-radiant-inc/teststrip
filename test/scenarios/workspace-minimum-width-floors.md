# workspace-minimum-width-floors: each workspace holds its chrome at its minimum window width

**What this covers**: `AppWindowLayoutMetrics.minimumWidth(for:)`
(Library 1000pt / Cull 800pt / People 700pt, `Sources/TeststripApp/main.swift:10-16`)
— resizing to each workspace's floor must not clip or overflow chrome.
People's `PeopleView` uses 320pt fixed-width panels, called out as the
tightest fit at the 700pt floor.

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
4. Press ⌘3 (People). Resize to 700pt. Assert: the queue's 320pt fixed panels
   are both present without being pushed off-screen or overlapping — this is
   the tightest fit (700pt window with two ~320pt panels leaves ~60pt for
   chrome/padding), so check carefully for any panel whose AXFrame origin is
   negative or extends past 700pt.

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

## Run status
BLOCKED-CONSOLE — locked console prevents any AX/window-resize step. Floor
values confirmed by source read (`Sources/TeststripApp/main.swift:10-16`).
The 320pt-panel risk at the People floor is a code-inspection flag, not yet
run live — needs a human-present re-run, and if it fails, treat it as a
genuine layout bug (not a scenario-authoring adjustment).
