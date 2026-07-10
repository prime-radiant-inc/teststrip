# app-004-subview-menus: the View menu's sub-view items and bare g/c/b keys route correctly

**What this covers**: Jesse switches sub-views from the menu bar and with the
bare cull keys. Inventory items 13-15: the View menu lists all 8 sub-view
modes with a divider between the cull and library groups, People excluded
(`AppMenuCoveragePresentation.subViewMenuModes` +
`WorkspaceCommands.subViewButton`, `Sources/TeststripApp/main.swift:100-210`);
bare menu key equivalents g/c/b exist only for the cull sub-views
(`LibraryViewMode.subViewMenuKey`); and the Library header's
segmented sub-view toggle (Grid / Loupe(.libraryLoupe) / Timeline / Map,
`WorkspaceChromePolicy.showsLibraryViewToggle`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **Menu inventory (item 13).** Via System Events, read the View menu's
   items. Assert these 8 titles appear, in two groups split by a divider:
   cull group `Loupe`, `Grid`, `Compare`, `A/B Compare`; library group
   `Library Grid`, `Library Loupe`, `Timeline`, `Map`. Assert there is NO
   `People` sub-view item (People is a workspace, not a sub-view).
3. **Bare keys only on cull sub-views (item 14).** Read each item's key
   equivalent: `Grid`=g, `Compare`=c, `A/B Compare`=b, all with no
   modifiers; the four library items and `Loupe` show no key equivalent.
4. **Menu items route.** Press ⌘2 (Library), then click View ▸ `Timeline`.
   Assert the Timeline chrome renders. Click View ▸ `Compare`; assert the
   app lands in the Cull workspace's Compare view (a sub-view selection
   implies its owning workspace).
5. **Library segmented toggle (item 15).** Back in Library (⌘2), find the
   header's segmented sub-view toggle; assert it has exactly four segments —
   Grid, Loupe, Timeline, Map — and that clicking `Loupe` lands on the
   *library* loupe (no pick/reject pills; that distinction is
   lib-013-library-loupe's deep card, here just assert absence of the cull
   HUD).
6. **Bare keys live only in cull views.** In the Cull workspace press `c`;
   assert Compare renders. Switch to Library, click into the grid, press
   `c`; assert the view does NOT change to Compare (bare keys are cull
   in-view captures mirrored by the menu, not global hotkeys — but note the
   Sharp edge below and record what actually happens).

## Expected
- Step 2: exactly the 8 titles, correct grouping, no People. **Fails if**
  a mode is missing/renamed or People appears.
- Step 3: g/c/b on exactly those three items. **Fails if** a library item
  carries a bare key (it would steal typing) or a cull key is missing.
- Steps 4-5: each activation renders the named sub-view and its owning
  workspace. **Fails if** a menu item is inert or lands elsewhere.
- Step 6: `c` switches views in Cull. In Library, record the observed
  behavior; a bare menu key equivalent IS honored by AppKit menus
  regardless of workspace, so if `c` switches to Compare from Library that
  matches the menu-as-system-of-record design — a failure here is only if
  `c` does nothing in Cull, or double-steps (fires twice per press).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The double-fire regression is real and documented in `main.swift`
  (`menuKeyboardShortcut`): arrow/Return keys are deliberately NOT menu-bound
  because the in-view key monitor already owns them. If pressing `g`/`c`/`b`
  inside a cull view advances two steps per press, that is the regression
  this design guards against — report it as a bug.
- Reading menu-item key equivalents needs System Events (`key equivalent`
  / `keyboard shortcut` properties of menu items), not `ax_drive.sh find`;
  menus only vend while open — script the open+read in one AppleScript.
- Step 6's Library branch is exploratory: the source gives bare keys to the
  menu items unconditionally, so they are likely app-wide. Do not fail the
  card on either outcome; fail only on the double-step or a dead key.
