# lib-013-library-loupe: Library's loupe is plain navigation, no pick/reject pills

**What this covers**: `LoupePresentation.showsCullChrome` — the Library
workspace's loupe (`.libraryLoupe`) is metadata/navigation only; it must not
show the culling HUD's pick/reject pills, which belong exclusively to the
Cull workspace's `.loupe` mode.

## Pre-state
```bash
./script/build_and_run.sh --smoke
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library, grid
   view.
2. Press Return (or double-click) on a grid cell to enter the loupe.
3. Assert the loupe view opens (an image-stage AX element replaces the grid).
4. Assert **absence** of cull chrome: no pick pill (`ax_drive.sh find --role AXButton --help "Rate 1"`
   style pick/reject controls, or whatever the HUD's pick/reject button
   AXHelp/label is) and no stack rail. Only navigation (prev/next) and the
   EXIF metadata overlay should be present.
5. Press Esc. Assert it returns to the Library grid (not to Cull).

## Expected
- Step 4: **Fails if** any pick/reject affordance is present in the Library
  loupe — that would leak Cull-only chrome into Library, violating the
  workspace split in `LoupePresentation.showsCullChrome`.
- Step 5: Esc returns to the grid in the same workspace (Library), not to
  Cull.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. `showsCullChrome`
split confirmed at `Sources/TeststripApp/AppModel.swift` (comment above
`LoupePresentation`, "the Library loupe (`.libraryLoupe`) is plain navigation
plus the EXIF metadata overlay only"). Needs a human-present re-run.
