# lib-011-view-toggle-routing: the six-lens switcher and the Cull sub-mode routes

**What this covers**: the five-tag `librarySubViewToggle` Picker this card
used to test is gone — `LibraryGridView.swift` no longer has a
`Picker("Library View", ...)`. The authoritative control is now the toolbar
`lensSwitcher` (`Sources/TeststripApp/LibraryGridView.swift:499-526`), six
buttons bound to `LibraryLens` (`Sources/TeststripApp/LibraryLens.swift:10-16`):
`.cull`, `.grid`, `.loupe`, `.timeline`, `.map`, `.people`, titled "Cull",
"Grid", "Loupe", "Timeline", "Map", "People" in that declaration order
(`LibraryLens.title`, `:20-29`), each with an ⌘1–⌘6 key equivalent
(`LibraryLens.keyEquivalent`, `:46-55`) wired via `LensCommands`
(`Sources/TeststripApp/main.swift:164-183`). `LibraryViewMode` still has 9
cases, but four of them (`.loupe`, `.compare`, `.abCompare`, `.cullGrid`) are
now transient Cull-lens sub-modes reached by g/c/b in-view key monitors, not
switcher tags — `.libraryLoupe` is the Loupe lens's own route, distinct from
`.loupe` (the Cull lens's loupe). Picking a lens calls
`AppModel.selectLens(_:)`, which only ever writes `selectedView` — it never
touches `selectedSource` (`AppModel.swift:4938-4941`).

The `body` switch's priority order is unchanged from the prior revision of
this card: `.people` first, then `.timeline`, then `.map`, then (if
`model.assets.isEmpty`) an empty-state view *before* checking
`.loupe`/`.libraryLoupe`, then `.compare`, `.abCompare`, and finally the
default `assetGrid` branch for `.grid`/`.cullGrid`/anything else unmatched
(`Sources/TeststripApp/LibraryGridView.swift:89-121` — line numbers are
approximate; locate by the `switch model.selectedView` in `body`, not by
these numbers, since this file churns).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
Confirmed against a seeded `--smoke` catalog 2026-07-10: `TOTAL=24` (grid is
non-empty, so the empty-state branch does not intercept the Grid/Loupe cases
below). Re-confirm `TOTAL` fresh on any re-run rather than trusting this
number to still hold.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Assert the toolbar's `lensSwitcher` container (`.accessibilityLabel
   ("Lens")`, `LibraryGridView.swift:525`) holds exactly six buttons, labelled
   "Cull", "Grid", "Loupe", "Timeline", "Map", "People", in that order — no
   more, no fewer:
   ```bash
   for name in Cull Grid Loupe Timeline Map People; do
     script/ax_drive.sh find --role AXButton --label "$name"
   done
   ```
3. Select "Grid" (⌘2 or the button). Assert the rendered content is the lazy
   asset grid (`assetGrid`, scrollable, `$TOTAL` cells reachable by
   scrolling) — confirms the fallback `else` branch handles `.grid`.
4. Select "Loupe" (⌘3). Assert the rendered content switches to a
   single-photo loupe view (no grid cells present) — confirms the
   `.loupe || .libraryLoupe` branch fires for `.libraryLoupe` specifically
   (the route this lens uses, `LibraryLens.defaultViewMode` for `.loupe` is
   `.libraryLoupe`), and that it renders before the `.compare`/`.abCompare`
   checks. See `lib-013-library-loupe.md` for this route's no-cull-chrome
   contract.
5. Select "Timeline" (⌘4). Assert a date-grouped/timeline-specific layout
   renders (distinct chrome from the grid).
6. Select "Map" (⌘5). Assert a map view renders (e.g. an `MKMapView`/places
   cluster surface).
7. Select "People" (⌘6). Assert the People canvas renders (the review strip
   / "ALL PEOPLE" panel from `PeopleView`, no asset grid cells).
8. Cycle back to "Grid" (⌘2) and confirm the grid reappears with the same
   `$TOTAL` cell count as step 3 (round-trip, no state loss).
9. **Cull sub-modes are not switcher tags.** Select "Cull" (⌘1). Assert the
   lens lands on its default sub-mode, `.loupe` (window subtitle "Loupe" —
   see `app-019-lens-shell.md`'s note on this subtitle colliding with the
   Loupe lens's own). Press `g`/`c`/`b` in turn and assert the Cull lens's
   sub-mode changes (grid/compare/A-B) each time, with the lens switcher's
   "Cull" button remaining the selected one throughout
   (`.accessibilityValue("Selected")`) — these are in-Cull routes, not
   entries on `lensSwitcher`.

## Expected
- Step 2: exactly 6 buttons, matching `LibraryLens.allCases`/`.title`
  verbatim, in declaration order. **Fails if** a 7th button appears, one is
  missing, or the order/labels drift from `LibraryLens`.
- Steps 3-7: each lens routes to its documented view. **Fails if** any lens
  renders the wrong content, or if selecting "Timeline"/"Map" incorrectly
  falls through to the grid.
- Step 8: Grid survives a round trip through the other lenses with no
  content loss. **Fails if** the grid shows fewer than `$TOTAL` cells after
  cycling.
- Step 9: g/c/b change the Cull lens's sub-mode without ever changing which
  `lensSwitcher` button reads selected. **Fails if** pressing g/c/b appears
  to switch lenses (the "Cull" button loses its selected state) or does
  nothing.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The `body` switch's empty-state check sits between the `.map` check and the
  `.loupe`/`.libraryLoupe` check, but after the `.people` and `.timeline`
  checks — on an empty catalog, Timeline and Map still render their real
  (empty) views, but Loupe, Compare, and the plain grid all get pre-empted by
  the generic `emptyLibraryView`. This looks intentional but is worth a
  dedicated empty-catalog card (`--isolated` with no seed) to confirm Loupe
  doesn't silently show a generic "no photos" screen when a photo *is*
  selected but preview generation hasn't finished — not verified here since
  `--smoke` always seeds 24 assets.
- `LibraryViewMode` has both `.loupe` and `.libraryLoupe` as separate cases
  handled by the same `body` branch — the Loupe lens only ever sets
  `.libraryLoupe`; `.loupe` is reached from the Cull lens's `g` route. This
  card's Step 4/Step 9 exercise both sides of that distinction; see
  `lib-013-library-loupe.md` for the Cull-side loupe chrome difference in
  depth.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
rewritten in place. `librarySubViewToggle` — the 5-tag
`Picker("Library View", ...)` this card exercised — was deleted along with
the two-workspace shell; there is no picker of that shape in current source
(`grep -n "Library View" Sources/TeststripApp/LibraryGridView.swift` finds
nothing). The successor is the six-button `lensSwitcher` bound to
`LibraryLens`, plus the g/c/b in-view routes for the Cull lens's transient
sub-modes, both verified against current source (`LibraryLens.swift:10-55`,
`LibraryGridView.swift:499-526`, `main.swift:164-183`). Steps 3-8 are
line-for-line the same assertions as before (same `body`-switch routing),
retargeted from picker-tag selection to lens-button/keyboard selection; Step
9 is new, replacing the old card's implicit assumption that People and the
cull sub-modes were peers on one picker. Supersedes prior status: the
2026-07-10 NOT RUN note verified `librarySubViewToggle` and its 5 tags by
source read — that control no longer exists, so nothing about its prior
non-run carries forward as evidence for this revision. Needs a fresh VM run.
