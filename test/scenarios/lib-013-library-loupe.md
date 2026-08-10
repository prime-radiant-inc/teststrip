# lib-013-library-loupe: the Loupe lens is plain navigation, no pick/reject pills, and it survives a relaunch

**What this covers**: `LoupePresentation.showsCullChrome` — the **Loupe
lens**'s route (`.libraryLoupe`) is metadata/navigation only; it must not
show the culling HUD's pick/reject pills, which belong exclusively to the
Cull lens's own `.loupe` sub-mode. `LoupePresentation(mode:)`
(`Sources/TeststripApp/AppModel.swift:32-34`) sets `showsCullChrome = mode
== .loupe` — true only for the Cull lens's route, false for
`.libraryLoupe`. Unlike the old two-workspace model, the Loupe lens **is**
session-restorable: it is one of the five non-Cull `LibraryLens` cases, and
`isRestorableLens` (`AppModel.swift:11927-11929`) is `lens != .cull` — the
Loupe lens survives a quit/relaunch like Grid/Timeline/Map/People do.

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘3 for the Loupe lens.
2. Assert the loupe view opens directly (an image-stage AX element, no
   grid) — the Loupe lens's default route is `.libraryLoupe`
   (`LibraryLens.defaultViewMode`, `LibraryLens.swift:58-67`), so there is
   no separate "enter the loupe from the grid" gesture needed to reach it
   via the lens switcher/⌘3 (contrast with Grid lens ⌘2, whose route is
   `.grid`).
3. Assert **absence** of cull chrome: no pick pill (`ax_drive.sh find --role AXButton --help "Rate 1"`
   style pick/reject controls, or whatever the HUD's pick/reject button
   AXHelp/label is) and no stack rail. Only navigation (prev/next) and the
   EXIF metadata overlay should be present.
4. Press Esc. Assert it stays in the Loupe lens (Esc navigates within the
   loupe if it does anything at all here — there is no "return to a
   different lens" behavior to assert, unlike the Cull lens's `.loupe`
   sub-mode, which has its own Esc-to-grid contract tested elsewhere).
5. **Session restore.** Select a specific asset in the Loupe lens, quit,
   and relaunch (Tart VM, per `test/scenarios/README.md`'s quit/relaunch
   mechanics — reuse the same isolated run dir, don't call `launch` again).
   Assert the app comes back in the Loupe lens on the same asset — unlike
   Cull, which `isRestorableLens` forces to Grid on any relaunch, the Loupe
   lens has no such exception.

## Expected
- Step 3: **Fails if** any pick/reject affordance is present in the Loupe
  lens — that would leak Cull-only chrome into it, violating
  `LoupePresentation.showsCullChrome`'s split.
- Step 5: the Loupe lens and its selected asset both survive a relaunch.
  **Fails if** the relaunch instead lands in Grid (would mean
  `isRestorableLens` regressed to excluding Loupe as well as Cull) or drops
  the asset selection.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
retitled and reworded "the Library workspace's loupe" to "the Loupe lens"
throughout, and the entry-key preamble from ⌘2 to ⌘3
(`LibraryLens.keyEquivalent`, `LibraryLens.swift:46-55`: `.loupe`'s key is
`"3"`; ⌘2 is now the Grid lens). Added Step 5, a new session-restore leg —
the Loupe lens is one of the five lenses `isRestorableLens` keeps
restorable (`AppModel.swift:11770-11772`, `lens != .cull`), a fact worth
asserting here rather than only in `app-006-session-restore.md`/
`app-019-lens-shell.md`, since this is the card that already owns the
Loupe-lens-specific chrome contract. `LoupePresentation.showsCullChrome`'s
split (`AppModel.swift:22-34`) is unchanged in substance by this push — only
the enclosing concept (workspace → lens) and the entry key changed.
Supersedes prior status: the prior BLOCKED-CONSOLE note's "the Library
workspace's loupe (`.libraryLoupe`)" framing and its ⌘2 entry point describe
the deleted two-workspace model; `showsCullChrome`'s own logic is untouched,
so that half of the prior citation still holds, but the entry key and the
enclosing-concept language do not. Needs a fresh VM run — still
BLOCKED-CONSOLE-equivalent until run in the Tart VM per
`test/scenarios/README.md`.
