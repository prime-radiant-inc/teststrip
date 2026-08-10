# app-007-go-history: Go ▸ Back/Forward walk the view-history stacks

**What this covers**: Jesse jumps between sets/queues and expects
browser-style back/forward. Inventory items 27-28: the Go menu's Back (⇧⌘[)
and Forward (⇧⌘]) gated by `canNavigateBack`/`canNavigateForward`
(`NavigationCommands`, `Sources/TeststripApp/main.swift:299-333`); history is
a pair of `LibrarySource` stacks (`navigationBackStack`/`navigationForwardStack`,
`Sources/TeststripApp/AppModel.swift:2021-2022`), and a new navigation clears
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
3. **Build history.** In the Grid lens, click three distinct sidebar rows in
   sequence (e.g. All Photos → a Smart Collection → a saved set). Record
   which chrome identifies each (result-header text or queue title).
   (`Places` no longer exists as a sidebar source — it was a lens
   masquerading as a source, per `LibrarySource.swift`'s own doc comment,
   and is now the Map lens.)
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
- History records `LibrarySource`s — source selections, not lens switches.
  Lens changes (Grid↔Timeline) may or may not push history; establish which
  by observation before asserting, and record the answer in the run notes
  rather than guessing.
- If a Back hop renders the right scope but the sidebar highlight lags,
  trust the header/scope chrome and catalog-backed row counts over the
  highlight.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell survivor sweep)**: this
card cited `SidebarRowTarget`, which no longer exists anywhere in `Sources/`
(`grep -rn "SidebarRowTarget" Sources/` → nothing) — the navigation-history
stacks are now `[LibrarySource]` (`navigationBackStack`/
`navigationForwardStack`, `AppModel.swift:2021-2022`), and the field name
itself had drifted (`forwardStack` → `navigationForwardStack`). Also fixed
Step 3's example row: `Places` no longer exists as a sidebar source (it was
a lens masquerading as a source, per `LibrarySource.swift`'s own doc
comment, and is now the Map lens) — substituted a Smart Collection/saved-set
example. Re-verified `NavigationCommands`'s line range
(`main.swift:297-325`, drifted from `:285-318`). Supersedes prior status: no
prior run evidence exists on this card at all — it never had a `## Run
status` section before this note; the fixes only affect what a future
runner would read as ground truth.
