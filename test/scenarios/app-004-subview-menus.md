# app-004-subview-menus: the View menu's lens items and Cull sub-mode group route correctly

**What this covers**: Jesse switches lenses and Cull sub-views from the menu
bar. The View menu is built by `LensCommands` (`Sources/TeststripApp/
main.swift:164-183`) as two groups separated by a `Divider()`: the six
`LibraryLens` items (`AppMenuCoveragePresentation.lensActionIDs`, `:94`,
each with an ⌘1–⌘6 `.keyboardShortcut`), then the four Cull sub-mode items
(`AppMenuCoveragePresentation.cullSubModeMenuModes`, `:99`: `.loupe`,
`.cullGrid`, `.compare`, `.abCompare`), titled via
`LibraryViewMode.cullSubModeMenuTitle` (`:146-158`) and carrying **no** key
equivalent — the successor to the old `LibraryViewMode.subViewMenuKey`,
which no longer exists. People is **not excluded** from this menu the way
the prior revision's header claimed: it is one of the six lens items
(⌘6), just not a member of the Cull sub-mode group below the divider — the
"People excluded" framing only ever meant "excluded from the sub-mode
group," which this revision states explicitly rather than leaving ambiguous.
The bare g/c/b keys that drive the same four Cull sub-modes are owned
entirely by the in-view key monitors (`CullingKeyCaptureView`/
`GridKeyCaptureView`) — main.swift's own comment above
`cullSubModeButton(for:)` explains why they are deliberately **not** also
bound as bare menu key equivalents (a menu-bound key double-fired alongside
the monitor's own switch, `run-cull-iter2 cull-008`). Menus stay clickable;
the `?` key-map overlay documents the keys.

One naming quirk worth asserting explicitly: "Loupe" appears **twice** in
this menu — once as the Loupe lens item (⌘3, routes to `.libraryLoupe`) and
once as the Cull sub-mode item (no key, routes to `.loupe`, reached live by
`g`). They are titled identically but are different `Button`s at different
menu positions routing to different `LibraryViewMode` cases.

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **Menu inventory.** Via System Events, read the View menu's items in
   order. Assert the lens group's six titles appear first, in
   `LibraryLens.allCases` order: `Cull`, `Grid`, `Loupe`, `Timeline`, `Map`,
   `People`. Assert a divider follows, then the Cull sub-mode group's four
   titles: `Loupe`, `Cull Grid`, `Compare`, `A/B Compare`
   (`LibraryViewMode.cullSubModeMenuTitle`'s four non-nil cases).
3. **Key equivalents.** Read each item's key equivalent: the six lens items
   carry ⌘1 through ⌘6 respectively (no other modifier); all four Cull
   sub-mode items show **no** key equivalent at all — not g/c/b, not
   anything else.
4. **Lens items route.** Click View ▸ `Timeline`; assert the Timeline chrome
   renders. Click View ▸ `Grid`; assert the plain library grid renders.
5. **Cull sub-mode items route within the Cull lens.** Click View ▸ `Cull`
   (⌘1) to land in the Cull lens, then click View ▸ `Compare` (the
   sub-mode item below the divider, not the lens item — there is only one
   "Compare" title, unlike "Loupe"). Assert the app is in the Cull lens's
   Compare sub-mode.
6. **The "Loupe" collision.** From the Cull lens's Compare sub-mode, click
   View ▸ `Loupe` — since two items share this title, click the **first**
   one encountered by System Events' menu-item order (the lens-group item,
   per step 2's ordering) and assert it lands on the Loupe **lens**
   (`.libraryLoupe`, window subtitle "Loupe", scope line unchanged — the
   Loupe lens still shows whatever source was selected). Return to Cull
   (⌘1), open Compare again, then click the **second** "Loupe" (the
   sub-mode item below the divider) and assert it lands on the Cull lens's
   own loupe sub-mode (`.loupe`) instead — same window subtitle text, but a
   different `selectedView` case and the Cull-only HUD chrome (pick/reject
   pills) present, which the Loupe lens's `.libraryLoupe` route never shows
   (see `lib-013-library-loupe.md`). Record which one AX actually resolves
   first if this step surprises you — System Events menu traversal order is
   not independently verified here.
7. **Bare keys live only in cull sub-modes.** In the Cull lens press `c`;
   assert Compare renders. Switch to the Grid lens, click into the grid,
   press `c`; record what actually happens (see Sharp edges) — a bare menu
   key equivalent is honored by AppKit menus regardless of which lens is
   frontmost, since binding is unconditional at the `Button` level; a
   failure here is only if `c` does nothing in Cull, or double-steps (fires
   twice per press).

## Expected
- Step 2: exactly ten titles in the two-group, divider-separated order
  given above. **Fails if** a lens or sub-mode is missing/renamed/reordered,
  or if People is missing from the lens group (it must be present there,
  even though it has no sub-mode-group counterpart).
- Step 3: the six lens items carry ⌘1–⌘6 and nothing else; the four Cull
  sub-mode items carry no key equivalent. **Fails if** any sub-mode item
  advertises g/c/b (would mean the old bare-key menu binding came back and
  would double-fire against the in-view monitor) or a lens item's shortcut
  is wrong.
- Steps 4-6: each activation renders the named lens/sub-mode. **Fails if** a
  menu item is inert or lands elsewhere, or if the two same-titled "Loupe"
  items are not actually distinguishable by behavior (same subtitle is
  expected and not a failure by itself; landing in the same `selectedView`
  case for both would be).
- Step 7: `c` switches sub-modes in Cull. **Fails if** `c` does nothing in
  Cull, or fires the switch twice per press (the double-fire regression
  `main.swift`'s `cullSubModeButton` comment documents guarding against).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The double-fire regression is real and documented in `main.swift` above
  `cullSubModeButton(for:)`: g/c/b are deliberately NOT menu-bound as bare
  key equivalents because the in-view key monitor already owns them. If
  pressing `g`/`c`/`b` inside a Cull sub-mode advances two steps per press,
  that is the regression this design guards against — report it as a bug.
- Reading menu-item key equivalents needs System Events (`key equivalent`
  / `keyboard shortcut` properties of menu items), not `ax_drive.sh find`;
  menus only vend while open — script the open+read in one AppleScript.
- Step 7's Grid-lens branch is exploratory, same as the prior revision: the
  source gives no bare key to any menu item at all now (there is nothing to
  give one), so there is no menu-level `c` binding to fire outside Cull.
  Do not fail the card on either outcome for a Grid-lens `c` press; fail
  only on a double-step or a dead key inside Cull.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
rewritten in place. The View menu's shape changed from "8 sub-view modes in
two groups (cull group + library group), People excluded" to "6 lenses,
divider, 4 Cull sub-modes" — Timeline and Map are now top-level lens items,
not a library sub-group; People is a lens item, not excluded from the menu
at all (only from the sub-mode group below the divider, which this revision
states explicitly instead of the prior ambiguous "People excluded" header).
`LibraryViewMode.subViewMenuKey`, which the prior revision cited for the
g/c/b key-equivalent claim, does not exist in current source — the successor
`LibraryViewMode.cullSubModeMenuTitle` supplies titles only, and confirmed by
reading `main.swift`'s `cullSubModeButton(for:)` and its preceding comment,
no bare key equivalent is bound at the menu-item level at all (verified:
`grep -n "keyboardShortcut" Sources/TeststripApp/main.swift` shows it applied
only to the six lens `Button`s, never to a `cullSubModeButton`). Added Step
6's "Loupe" name-collision check, which the prior revision's picker-based
premise had no equivalent of (a Picker can't have two tags with the same
label reachable independently; a menu can). Supersedes prior status: the
prior revision's entire menu-shape premise (8 items, cull/library grouping)
describes a menu that was rebuilt from scratch by this push — no prior run
of that structure is evidence about this one. Needs a fresh VM run.
