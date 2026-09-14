# app-007-go-history: Go ▸ Back/Forward walk the view-history stacks

**What this covers**: Jesse jumps between sets/queues and expects
browser-style back/forward. Inventory items 27-28: the Go menu's Back (⇧⌘[)
and Forward (⇧⌘]) gated by `canNavigateBack`/`canNavigateForward`
(`NavigationCommands`, `Sources/TeststripApp/main.swift:299-333`); history is
a pair of `LibrarySource` stacks (`navigationBackStack`/`navigationForwardStack`,
`Sources/TeststripApp/AppModel.swift:2069-2070`), and a new navigation clears
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
`navigationForwardStack`, `AppModel.swift:2069-2070`), and the field name
itself had drifted (`forwardStack` → `navigationForwardStack`). Also fixed
Step 3's example row: `Places` no longer exists as a sidebar source (it was
a lens masquerading as a source, per `LibrarySource.swift`'s own doc
comment, and is now the Map lens) — substituted a Smart Collection/saved-set
example. Re-verified `NavigationCommands`'s line range
(`main.swift:297-325`, drifted from `:285-318`). Supersedes prior status: no
prior run evidence exists on this card at all — it never had a `## Run
status` section before this note; the fixes only affect what a future
runner would read as ground truth.

## Run status
**LIVE RUN 2026-09-14, Tart VM `teststrip-e2e`** (`script/vm_scenario_run.sh`, run dir
`smoke-1789374443`, `launch smoke`, 24 assets): Steps 1-7 all PASS.

- **Step 2 (gating at launch)**: System Events one-pass Go-menu read → `Back || enabled=false ||
  cmd=[ || mods=1`, `Forward || enabled=false || cmd=] || mods=1` (`mods=1` = ⇧, so the items
  render ⇧⌘[ / ⇧⌘]). Both disabled on the fresh launch; no error banner on a no-op Back press.
- **Step 3 (build history)**: three distinct sidebar rows driven by `ax press --role AXButton
  --label ...` (rows vend title-less `AXButton`s whose `AXDescription` is the row name). Identifying
  chrome = the `AXStaticText` `desc=Scope` line at the top of the result area:
  `All Photos, 24 photos` → `Rejects, 5 photos · Reject` → `Smoke Picks, 8 photos · Smoke Picks`.
  Go menu after the third click: `Back enabled=true / Forward enabled=false`.
- **Step 4 (Back)**: `⇧⌘[` → `Rejects, 5 photos · Reject` (exactly the previous row); Go menu
  `Forward` now `enabled=true`. Second `⇧⌘[` → `All Photos, 24 photos` (the row before that).
  Each hop lands on exactly the adjacent entry.
- **Step 5 (Forward)**: `⇧⌘]` once → `Rejects, 5 photos · Reject` (the middle scope re-renders).
- **Step 6 (new nav clears forward)**: after Back×2 we were at `All Photos` with `Forward` enabled;
  clicking a *different* row `SmokeOriginals` → scope `SmokeOriginals, 24 photos · Folder:
  SmokeOriginals`, Go menu `Forward enabled=false` / `Back enabled=true`. Stale forward history is
  discarded.
- **Step 7 (bottom of the stack)**: repeated `⇧⌘[` walked the full back stack
  (`SmokeOriginals → Rejects → All Photos → Picks`) and at the oldest entry (`Picks, 6 photos ·
  Pick`) `Back` reads `enabled=false`; four further `⇧⌘[` presses are no-ops — the view stays on
  `Picks` and `Back` stays disabled. No `AXSheet`/`AXAlert`/error text appeared at any point
  (gate prevents underflow rather than erroring).

**Sharp-edge answers (observed, not guessed)**:
- **Lens switches do NOT push history.** From the oldest entry (`Back` disabled, `Forward` enabled),
  `⌘3` (Loupe) then `⌘2` (Grid) left the Go menu unchanged (`Back disabled / Forward enabled`) and
  the source at `Picks`. History tracks `LibrarySource` selections only.
- **The launch-default source is not pushed.** A fresh launch starts on `All Photos` with an empty
  back stack; the very first click to another row pushes nothing (back stack stays empty until the
  *second* distinct selection). Confirmed by a clean walk: from the launch state, clicking `Picks`
  then `Smoke Picks` left a 1-deep back stack (`Back` disabled after the first `⇧⌘[`), whereas a
  later 3-row sequence (`All Photos → Rejects → Smoke Picks`) produced the expected 2-deep stack.
  This matches the "root of the stack is the launch state" reading of `canNavigateBack`.

**Stale citations** (symbols alive, behaviour exactly as described): `NavigationCommands`
`main.swift:299-333` → `:311-330`; `AppModel.swift` `navigationBackStack`/
`navigationForwardStack` `:2069-2070` → `:2204-2205` (`canNavigateBack` `:5366`,
`canNavigateForward` `:5369`).
