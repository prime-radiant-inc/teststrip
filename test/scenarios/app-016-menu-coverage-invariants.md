# app-016-menu-coverage-invariants: every action enum is mirrored by a menu item (unit-test method)

**What this covers**: menus are Teststrip's system of record — every
culling shortcut, workspace, sub-view, inspector tab, zoom, file, and
move-rejects/updates action must have a menu item, pinned by
`AppMenuCoveragePresentation` (`Sources/TeststripApp/main.swift:96-135`)
against the underlying action-producing enums. Inventory items 54-55.

**Method: this is a unit-test-method card, not an AX-driven one.** The
invariant lives in `Tests/TeststripAppTests/MenuCoveragePresentationTests.swift`
and is enumerable exhaustively there; driving 30+ menu items live would
re-prove less, slower. The card exists so the story-loop runner executes and
green-checks the suite explicitly.

## Pre-state
Clean checkout, no app launch needed.

## Steps
1. Run the suite:
   ```bash
   swift test --filter MenuCoveragePresentationTests 2>&1 | tail -20
   ```
2. Confirm all 8 tests ran and passed (culling shortcuts, workspaces,
   sub-views-except-people, inspector tabs + toggle, zoom, file menu
   import/export, move-rejects, check-for-updates).
3. **Spot-check the presentation isn't vacuous** (the test compares two
   in-app constants; a rename in both places passes the test while breaking
   muscle memory): grep that the load-bearing user-facing strings are still
   what the docs/cards use —
   ```bash
   grep -n '"Move Rejects…"\|"Check for Updates…"\|"Import Folder…"\|"Export…"' Sources/TeststripApp/main.swift
   ```

## Expected
- Step 1-2: `Executed 8 tests, with 0 failures` (count may grow as menus
  grow — 0 failures is the invariant; quote the actual count). **Fails if**
  any test fails or the filter matches zero tests (suite renamed — coverage
  silently gone).
- Step 3: all four literals present. **Fails if** a title drifted — update
  the dependent scenario cards in the same change.

## Cleanup
None (read-only test run).

## Sharp edges
- The test enumerates presentation constants against enums, so it catches
  *missing* coverage, not *inert* menu items — pair with app-004/app-012's
  live routing checks; neither substitutes for the other.
- Culling menu items no longer carry a real `.keyboardShortcut` (removed to
  fix a double-fire bug — see `menuKeyboardShortcut` in `main.swift`), so
  the key is advertised as a title suffix instead: `Pick (P)`, `1 Star (1)`,
  `Promote Frame & Reject Siblings (⏎)`, etc., built by
  `CullingCommandMenuItem.menuDisplayTitle` (`AppModel.swift`) from the same
  `CullingShortcutKey.displayText` the `?` overlay uses. Covered by
  `testCullingMenuItemsAdvertiseTheirKeyInTheTitle`. If a live menu walk
  (app-012) sees a Culling item with no `(key)` suffix, that's a
  regression, not a design choice — every non-monitor-only item must have
  one.
- Known gap (inventory): Run Autopilot, Scan for Faces, Evaluate Photo/Scope
  are NOT enumerated in `AppMenuCoveragePresentation` — they're rename-
  fragile. If a run of app-012 finds one missing from the live menu, this
  suite will NOT have caught it; consider that a product gap worth a
  Sharp-edges note, not a card failure here.
- Test output must be pristine: unrelated warnings/errors in the filtered
  run are reportable per the testing rules.
