# app-007-go-history: Go ▸ Back/Forward walk the view-history stacks

**What this covers**: Jesse jumps between sets/queues and expects
browser-style back/forward. Inventory items 27-28: the Go menu's Back (⇧⌘[)
and Forward (⇧⌘]) gated by `canNavigateBack`/`canNavigateForward`
(`NavigationCommands`, `Sources/TeststripApp/main.swift:285-318`); history is
a pair of `SidebarRowTarget` stacks (`navigationBackStack`/`forwardStack`,
`Sources/TeststripApp/AppModel.swift:1814-1817`), and a new navigation clears
the forward stack.

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **Gating at launch.** Open the Go menu via System Events; assert both
   `Back` and `Forward` are present with ⇧⌘[ / ⇧⌘] and both are DISABLED
   (no history yet).
3. **Build history.** In Library, click three distinct sidebar rows in
   sequence (e.g. All Photographs → a review queue → Places/another set).
   Record which chrome identifies each (result-header text or queue title).
4. **Back.** Press ⇧⌘[ twice. After each press assert the rendered scope is
   the previous row's (match the recorded identifying chrome). Go menu:
   `Forward` is now ENABLED.
5. **Forward.** Press ⇧⌘] once; assert the middle scope re-renders.
6. **New navigation clears forward (item 28).** Click a *different* sidebar
   row (not the one forward would go to). Open the Go menu: `Forward` must
   be DISABLED again; `Back` enabled.
7. **Bottom of the stack.** Press ⇧⌘[ repeatedly until `Back` disables;
   assert no error surfaces and the view stays on the oldest scope
   (the gate prevents underflow rather than erroring).

## Expected
- Step 2: both items disabled on a fresh launch. **Fails if** enabled with
  empty stacks (pressing them would throw into `errorMessage`).
- Steps 4-5: each Back/Forward lands on exactly the adjacent history entry —
  quote the header text observed at each hop. **Fails if** a hop skips an
  entry or lands on the wrong scope.
- Step 6: Forward disabled after a fresh navigation. **Fails if** stale
  forward history survives — forward would then jump somewhere Jesse never
  expects.
- Step 7: Back disables at the oldest entry; no error banner ever appears.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Reading a menu item's enabled state requires the menu to be open;
  script open+read in one AppleScript pass (menus vend only while open).
- History records `SidebarRowTarget`s — sidebar-row navigations. Sub-view
  toggles (Grid↔Timeline) may or may not push history; establish which by
  observation before asserting, and record the answer in the run notes
  rather than guessing.
- If a Back hop renders the right scope but the sidebar highlight lags,
  trust the header/scope chrome and catalog-backed row counts over the
  highlight.
