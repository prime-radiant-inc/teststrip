# app-003-workspace-switching: ⌘1/⌘2/⌘3 and the toolbar switcher land on the right workspace

**What this covers**: Jesse flips between Cull/Library/People all session; the
toolbar `Picker("Workspace", ...)` and the shared ⌘1/⌘2/⌘3 keyboard shortcuts
both route through `AppModel.selectWorkspace(_:)`, so they must never disagree.
Inventory items 9-12: `Workspace` enum titles/keys
(`Sources/TeststripApp/AppModel.swift:47-84`), ⌘1/2/3 in `WorkspaceCommands`
(`Sources/TeststripApp/main.swift`), the principal segmented picker, and
`lastSubView` restore with defaults loupe/grid/people
(`Workspace.defaultSubView`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Press ⌘2 (Library). Assert the AX tree shows Library-only roots: the query
   token field (`ax_drive.sh find --role AXTextField --contains "Search your library"`)
   and the grid/timeline/map view-mode controls; assert the Cull HUD and
   People queue are absent.
3. Press ⌘1 (Cull). Assert the Cull sidebar (source picker incl. "Autopilot
   Proposals") and HUD are present; the Library token field is absent.
4. Press ⌘3 (People). Assert the People queue root is present; the Cull HUD
   and Library token field are absent.
5. Click the toolbar workspace switcher's "Library" segment directly (not the
   shortcut) — `ax_drive.sh press --role AXRadioButton --label "Library"` (or
   whatever role the `Picker` renders as; inspect first with a full AX dump if
   the role guess misses). Assert the same Library-only roots reappear.
6. Repeat step 5 for "Cull" and "People" segments, asserting each lands on the
   matching workspace root.
7. **Sub-view memory (item 12).** In Library, switch the sub-view to Timeline
   (View ▸ Timeline). Press ⌘1 (Cull), then ⌘2 (Library) again. Assert the
   Timeline chrome is what renders — the workspace re-entered on its
   remembered sub-view, not its `defaultSubView` (.grid). Then quit-and-fresh
   isolated relaunch is NOT part of this card (session restore is app-006);
   only in-session memory is asserted here.

## Expected
- Every ⌘1/⌘2/⌘3 press and every switcher click lands on the workspace whose
  distinguishing chrome (HUD vs. token field vs. queue) is present and no
  other workspace's chrome leaks through.
- **Fails if** the keyboard shortcut and the switcher click ever disagree on
  which workspace is active, or if a prior workspace's chrome remains visible
  after switching (a stale AX subtree).
- Step 7: Library re-enters on Timeline. **Fails if** it lands back on the
  grid — `lastSubView` memory is broken and every workspace switch would
  reset Jesse's view.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The toolbar `Picker` may render its segments as `AXRadioButton`s or as a
  single control; dump the AX tree once before guessing roles.
- The host console can be locked (Jesse away); the app then launches
  windowless and every AX assertion false-negatives. Prefer the Tart VM
  (`script/vm_scenario_run.sh`), or check
  `ioreg -n Root -d1 -a | grep IOConsoleLocked` first.
- A prior run of this card was BLOCKED-CONSOLE; `AppModel.selectWorkspace` /
  `Workspace.keyEquivalent` were confirmed by source read only. The live
  assertions still need a first green run.
