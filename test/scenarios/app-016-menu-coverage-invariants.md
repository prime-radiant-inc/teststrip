# app-016-menu-coverage-invariants: every action enum is mirrored by a menu item (unit-test method)

**What this covers**: menus are Teststrip's system of record — every culling
shortcut, lens, Cull sub-mode, inspector section, zoom, file, and
move-rejects/updates action must have a menu item, pinned by
`AppMenuCoveragePresentation` (`Sources/TeststripApp/main.swift:93-139`)
against the underlying action-producing enums. Re-anchored on
`AppMenuCoveragePresentation.lensActionIDs` (`:94`, `LibraryLens.allCases`'s
six titles) and `.cullSubModeMenuModes` (`:99`, the four transient Cull
sub-modes) — the successors to the pre-unified-shell `workspaceActionIDs`/
`subViewMenuModes` this card used to cite, both deleted by this push.

**F14 (the same-commit menu rule, `.superpowers/sdd/2026-08-07-unified-
shell/code-map.md`)**: a `LibraryLens`/`LibraryViewMode` enum change must
land in `AppMenuCoveragePresentation` in the *same commit* — the presentation
layer is hand-maintained (menus are built ad hoc as SwiftUI `Button`s, not
generated from the enum), so nothing except this test suite catches a lens
added to the enum but never wired into `LensCommands`, or vice versa. Every
lens/sub-mode-shape task in this push carried this rule; this card exists so
a future task keeps carrying it.

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
2. Confirm all 11 tests ran and passed:
   `testCullingMenuCoversEveryShortcutItem`,
   `testViewMenuCoversEveryLens` (asserts `lensActionIDs` == `LibraryLens
   .allCases.map(\.title)` and its count is exactly 6),
   `testEveryViewModeIsReachableFromAMenuItem` (asserts every
   `LibraryViewMode` case is reachable either as a lens's `defaultViewMode`
   or as a member of `cullSubModeMenuModes`, and that every sub-mode has a
   non-nil `cullSubModeMenuTitle`),
   `testViewMenuCoversEveryInspectorSectionScrollActionAndTheInspectorToggle`,
   `testViewMenuCoversZoomInAndOut`,
   `testFileMenuCoversImportAndExportActions`,
   `testCullingMenuCoversMoveRejectsAction`,
   `testCullingMenuCoversMoveRejectsToTrashAction`,
   `testFileMenuCoversNewSetFromSelectionAction`,
   `testSupportMenuCoversCheckForUpdatesAction`,
   `testCullingMenuItemsAdvertiseTheirKeyInTheTitle`.
3. **Spot-check the presentation isn't vacuous** (the test compares two
   in-app constants; a rename in both places passes the test while breaking
   muscle memory): grep that the load-bearing user-facing strings are still
   what the docs/cards use —
   ```bash
   grep -n '"Move Rejects…"\|"Check for Updates…"\|"Import Folder…"\|"Export…"' Sources/TeststripApp/main.swift
   ```

## Expected
- Step 1-2: `Executed 11 tests, with 0 failures` (count may grow as menus
  grow — 0 failures is the invariant; quote the actual count). **Fails if**
  any test fails or the filter matches fewer than 11 tests (a test renamed
  or removed — coverage silently gone; more than 11 is fine and expected as
  the menu grows, just quote the new count).
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
- The six `LensCommands` items (⌘1–⌘6) DO carry a real `.keyboardShortcut`
  (`main.swift:173`) — they are not subject to the double-fire hazard the
  bullet above describes, because there is no in-view key monitor
  independently owning digit keys the way there is for P/X/ratings. Don't
  conflate the two key-advertising strategies when reading `main.swift`.
- Known gap (inventory): Run Autopilot, Scan for Faces, Evaluate Photo/Scope
  are NOT enumerated in `AppMenuCoveragePresentation` — they're rename-
  fragile. If a run of app-012 finds one missing from the live menu, this
  suite will NOT have caught it; consider that a product gap worth a
  Sharp-edges note, not a card failure here.
- Test output must be pristine: unrelated warnings/errors in the filtered
  run are reportable per the testing rules.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
re-anchored on `lensActionIDs`/`cullSubModeMenuModes`
(`Sources/TeststripApp/main.swift:94,99`), which replaced
`workspaceActionIDs`/`subViewMenuModes` when the workspace shell was deleted.
Corrected the test count and roster: the suite now holds 11 tests, not 8 —
`testViewMenuCoversEveryLens` and `testEveryViewModeIsReachableFromAMenuItem`
are the direct successors of the old "workspaces"/"sub-views-except-people"
tests this card named, and three tests present in current source
(`testFileMenuCoversNewSetFromSelectionAction`,
`testCullingMenuCoversMoveRejectsToTrashAction`,
`testCullingMenuItemsAdvertiseTheirKeyInTheTitle`) were absent from the
prior revision's roster — confirmed by reading
`Tests/TeststripAppTests/MenuCoveragePresentationTests.swift` in full
(`grep -c "func test"` = 11) rather than trusting the old count. Added the
explicit F14 statement per the task brief. Supersedes prior status: the
prior revision's "8 tests" figure and its workspace-era test names describe
a version of this suite that predates the lens rewrite; that count was never
re-verified against source before now and would fail step 2 outright if
followed literally. Needs a fresh run (`swift test --filter
MenuCoveragePresentationTests`) — not VM-bound, so this one can run headless
whenever picked up.
