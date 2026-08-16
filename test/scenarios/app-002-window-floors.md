# app-002-window-floors: the window holds its chrome at its one minimum width

**What this covers**: Jesse works on a laptop screen and shrinks the window;
the chrome must hold at its documented floor. There is now **one floor for
the whole app**, not a per-workspace split: `AppWindowLayoutMetrics
.minimumWidth == 1000` (`Sources/TeststripApp/main.swift:9`), applied via
`.frame(minWidth:minHeight:)` regardless of which lens is selected
(`main.swift:44-47`). The comment directly above the constant states the
reason: "the per-workspace 1000/800 split went away with the Cull|Library
split — there is no longer a workspace paying for another workspace's
chrome." `minimumHeight = 720`, `defaultWidth = 1520`, `defaultHeight = 820`
(`main.swift:9-12`) are unchanged and also lens-independent. There is no
People-specific floor of any width — People is a Library sub-view (now a
lens), not a workspace, and never had its own `AppWindowLayoutMetrics` entry
to begin with in the current design; the two-floor (Library 1000/Cull 800)
and three-floor (+People 700) framings this card previously tested both
describe removed code.

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Resize the window to exactly 1000pt wide (AppleScript `System Events`
   `set size of window 1 of process "Teststrip" to {1000, <h>}`, or drag via
   AX if a resize verb exists). Do this once, while in the Grid lens (⌘2).
   Assert: no horizontal scrollbar appears on the window itself, and the
   query token field, result header, and lens switcher are all still
   present in the AX tree (`ax_drive.sh find` each), none reporting a frame
   that extends past the window's right edge (compare AXFrame width to
   window width if available).
3. Without resizing again, press ⌘1 (Cull). Assert: the sidebar, HUD, and
   pick/reject controls remain present and unclipped at the same 1000pt
   width — there is nothing to re-resize to, since Cull enforces the same
   floor as every other lens.
4. Press ⌘6 (People). Assert: People's panels are present without being
   pushed off-screen or overlapping, and no panel's AXFrame extends past the
   window or reports a negative origin, still at 1000pt.
5. Attempt to resize below 1000pt (e.g. request 900pt via the same System
   Events verb). Assert the window refuses — its resulting AXSize width
   stays at 1000, proving SwiftUI's `minWidth` clamp is actually enforced,
   not merely documented. Repeat this refusal check while each of Cull,
   Grid, and People is the active lens — the floor must hold identically in
   all three, since there is only one constant gating it.

## Expected
- Every key element listed above is present and fully within the window
  frame at the 1000pt floor, in every lens tried.
- **Fails if** any control's AXFrame width+origin exceeds the window width
  (clipped/overflowing chrome), if an element that should be present
  (sidebar, HUD, queue panel) is missing at the floor, or if the window
  ever accepts a resize below 1000pt in any lens (would mean
  `AppWindowLayoutMetrics.minimumWidth` stopped being the single source of
  truth the comment above it claims it is).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- A prior run was BLOCKED-CONSOLE: the floor value was confirmed by source
  read only; the resize assertions have never run live.
- Resizing via System Events `set size of window 1` uses points on a
  non-retina VM display; confirm the resulting AXSize actually reads the
  requested width before asserting anything about clipping.
- Item 8's default 1520x820 only applies to a first-ever window; an isolated
  launch with a fresh app-support dir still restores frame from the
  `com.teststrip.app` defaults domain if one exists on the machine. Assert
  the default size only on a VM/user account that has never run the app, or
  after `defaults delete com.teststrip.app` — otherwise skip that assertion
  and say so.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
rewritten for the single-floor model. Deleted the Library-1000/Cull-800
comparison and the "People rides the Library floor, no separate 700pt floor"
framing — both described a per-workspace `minimumWidth(for:)` function that
no longer exists; current `AppWindowLayoutMetrics` is three flat constants
with no per-lens branch at all (confirmed by reading `main.swift:5-13` and
its own comment explaining the removal). Rewrote Steps 2-5 to test one floor
held across lens switches rather than three floors held per-workspace.
Supersedes prior status: the prior BLOCKED-CONSOLE note's source citation
(`AppWindowLayoutMetrics.minimumWidth(for:)`, a per-workspace function) is to
code this push deleted — that citation, and any future run against the old
two/three-floor premise, would fail step 2 immediately by looking for a
function signature that doesn't exist. Needs a fresh VM run.
