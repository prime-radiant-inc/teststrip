# cull-009-keymap-overlay: ? shows the full cull keyboard cheat-sheet, including monitor-only shortcuts

**What this covers**: as a new user of the Cull workspace, I want `?` to pop
up a complete keyboard cheat-sheet — including the option-arrow stack-nav
alternates that have no menu entry and are otherwise undiscoverable — so I
don't have to memorize the keymap from documentation. Covers item 26 (`?`
toggles the overlay) and item 69 (the overlay lists monitor-only shortcuts).

Source:
- `Sources/TeststripApp/AppModel.swift:5447-5448` — `.showKeyMap` toggles
  `isKeyMapOverlayVisible` (`?`, keyed via the exact-case `.character("?")`
  match at `:235-236`, so plain `?` — not shift-adjusted — fires it).
- `Sources/TeststripApp/LibraryGridView.swift:203-206` — the overlay is shown
  `if model.isKeyMapOverlayVisible`, and `.onExitCommand` (Esc) also sets it
  false — so **Esc dismisses in addition to** a repeated `?` (the doc
  comment at `LibraryGridView.swift:8567` says "Esc or a repeated `?`
  dismisses it"; a second `?` toggles `isKeyMapOverlayVisible` back to
  false, same boolean).
- `Sources/TeststripApp/LibraryGridView.swift:8564-8615` — `KeyMapOverlayView`:
  heading `"Keyboard Shortcuts"`, a dismiss button (accessibility label
  `"Dismiss key map"`), and `ForEach(CullingCommandMenuPresentation.sections)`
  rendering each section's uppercased title and each item's `title` +
  `key.displayText` as plain `Text`.
- `Sources/TeststripApp/AppModel.swift:480-521` — `CullingCommandMenuPresentation.sections`,
  the single source of truth for what the overlay lists. Real section
  titles: `"Navigation"`, `"Ratings"`, `"Color Labels"`, `"Flags"`,
  `"Loupe"`, `"Filter"`. Real monitor-only items (`isMonitorOnly: true`,
  `:488-489`): `"Previous Stack (Option)"` (key `"⌥←"`) and `"Next Stack
  (Option)"` (key `"⌥→"`) — the only two `isMonitorOnly` entries in the
  whole list; they exist purely for `?`-overlay discoverability since a menu
  binding would double-fire alongside `↑`/`↓`'s existing stack-nav (comment
  at `:453-455`).
  **Note**: `G`/`C`/`B` (subview switches, item 25) are **not** listed in
  `CullingCommandMenuPresentation` at all — they have no section/menu entry.
  Don't assert their presence in the overlay; that would be a false
  assertion this draft caught by reading the actual section list.

## Pre-state
```bash
./script/build_and_run.sh --smoke
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. ⌘1 for Cull; select a frame and open the loupe (Return). On this FIRST
   entry to the Cull workspace in the session, assert the one-time
   discoverability hint appears via the decision toast:
   `script/ax_drive.sh find --contains "Press ? for keyboard shortcuts"`
   (within its 2s window). Leave Cull (⌘2) and return (⌘1): assert the hint
   does NOT reappear — it is once per session (persona-8 defect: the ?
   overlay was undiscoverable).
2. Press `?`. Assert the overlay appears:
   `script/ax_drive.sh wait --role AXStaticText --contains "Keyboard Shortcuts"`.
3. Assert at least three real section headings render (quoting the actual
   values from `CullingCommandMenuPresentation`, not guessed ones):
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "NAVIGATION"
   script/ax_drive.sh find --role AXStaticText --contains "FLAGS"
   script/ax_drive.sh find --role AXStaticText --contains "LOUPE"
   ```
   (section titles are rendered `.uppercased()` at
   `LibraryGridView.swift:8591`, so match the uppercased form.)
4. Assert at least two real item rows render by title:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "Promote Frame & Reject Siblings"
   script/ax_drive.sh find --role AXStaticText --contains "Cycle EXIF Overlay"
   ```
5. Assert the two `isMonitorOnly` entries are present — these are the ones
   otherwise undiscoverable, so their presence here is the load-bearing
   assertion for item 69:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "Previous Stack (Option)"
   script/ax_drive.sh find --role AXStaticText --contains "Next Stack (Option)"
   ```
   Also assert their key labels render as `"⌥←"`/`"⌥→"` (the same row,
   `HStack` with title and key text as siblings, `LibraryGridView.swift:8594-8602`):
   `script/ax_drive.sh find --role AXStaticText --contains "⌥←"`.
6. Press Esc. Assert the overlay is gone:
   `script/ax_drive.sh find --role AXStaticText --contains "Keyboard Shortcuts"`
   should now fail to match, and the loupe's normal chrome (e.g. pick/reject
   pills) should be reachable again (a subsequent keystroke like `p` should
   pick the frame, proving focus returned to the culling surface rather than
   being stuck on the dismissed overlay).
7. Re-open with `?`, then press `?` again (not Esc). Assert this also
   dismisses the overlay (the "repeated `?` dismisses it" claim from the
   doc comment) — same assertion as step 6.

## Expected
- Step 2: overlay heading appears within a couple seconds of the keypress.
  **Fails if** it never appears — `.showKeyMap`/`isKeyMapOverlayVisible`
  wiring broken.
- Step 3/4: the quoted section and item titles render verbatim (case-
  sensitive per the actual uppercasing/title-casing in source). **Fails if**
  any of these specific strings are absent — don't substitute a looser
  substring that would pass even if the section list changed.
- Step 5: both monitor-only entries and both `⌥` key glyphs are present.
  **Fails if** either is missing — that's the actual discoverability gap
  item 69 exists to close; a missing entry here is a real regression, not a
  flaky assertion to soften.
- Step 6: overlay fully dismissed via Esc, and keyboard focus/routing
  recovers (proven by a working `p` keystroke afterward).
- Step 7: overlay fully dismissed via a second `?` press, independent of
  Esc.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **G/C/B (item 25's subview-switch shortcuts) are absent from the overlay
  by design** (not a bug this card should report) — `CullingCommandMenuPresentation.sections`
  has no entries for `.showCullGrid`/`.showCompare`/`.showABCompare`. If a
  future change is expected to add them, that's a product decision for
  Jesse, not something to assert against here.
- The overlay's frame is fixed at `360×420` with a `ScrollView`
  (`LibraryGridView.swift:8587-8609`); if the section/item list grows past
  what fits, later sections may be off-screen in the AX tree until scrolled
  — mirror the grid's lazy-virtualization caveat from `test/scenarios/README.md`
  if an assertion for a late section (e.g. `"Filter"`) ever flakes.
- This card only drives from the loupe (`CullingKeyCaptureGate.isActive`
  requires `workspace == .cull && selectedView != .cullGrid` — see
  `cull-008-subview-keys-gcb.md`); `?` is not wired while `.cullGrid` is
  showing (GridKeyCaptureView has no `?` binding), so don't try to trigger
  this overlay from the grid subview.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md.
