# lib-017-footer-density-zoom: footer counts, selection-clear, density presets, and zoom slider

**What this covers**: the Library grid's footer bar (`footer`,
`Sources/TeststripApp/LibraryGridView.swift:2469-2521`) — the library-count
and status text, the "N selected" batch label with its clear-selection
button, the three density presets (Compact/Comfortable/Large), and the zoom
slider's range/step. Companion unit coverage:
`Tests/TeststripAppTests/LibraryGridLayoutTests.swift` (pure layout math) —
this card proves the same constants drive the assembled footer UI.

Exact values, verified at `Sources/TeststripApp/LibraryGridLayout.swift:4-76`:

- `minimumThumbnailWidth = 96`, `defaultThumbnailWidth = 140`,
  `largeThumbnailWidth = 220`, `maximumThumbnailWidth = 260`.
- `thumbnailZoomStep = 8` — each ⌘+/⌘- press moves the stored width by ±8,
  clamped to `[96, 260]` (`zoomedThumbnailWidth`/`clampedThumbnailWidth`,
  lines 61-67).
- `densityLabel` (lines 24-33) is a **derived** label from the live
  thumbnail width, not a fixed 3-way switch tied only to the presets:
  `< 120` → **"Compact"**; `>= 200` → **"Large"**; otherwise → **"Comfortable"**.
  So a width of 140 (the default) reads "Comfortable", and manual zoom via
  ⌘+/⌘- can land on a width between presets that still resolves to one of
  the three labels by this threshold, not by exact preset match.
- `footerDensityControls` (lines 39-57) exposes exactly 3 preset buttons:
  Compact → sets width to 96 exactly; Comfortable → 140 exactly; Large → 220
  exactly. `isSelected` on each is `densityLabel == control.title`, so
  clicking "Large" (width 220) shows Large selected, but zooming to width 210
  via the slider *also* shows Large selected (same `>= 200` bucket) even
  though it doesn't match the preset's exact 220 value — a control can appear
  selected without being at its own snap point.
- `gridSpacing` (lines 20-22): **5pt** when `densityLabel == "Compact"**, else
  **11pt**. This is inter-cell spacing, not a control-layout constant — verify
  visually via `capture_app_window.sh`, not AX (no direct AX exposure of
  spacing).
- **⌘+/⌘- zoom shortcuts live only in `main.swift`'s `ZoomCommands`
  (`Sources/TeststripApp/main.swift:561-577`), not inside `LibraryGridView`
  itself.** They're an app-menu `CommandGroup(after: .toolbar)` bound to
  `@AppStorage("LibraryGridView.thumbnailWidth")`, calling the same
  `LibraryGridLayout.zoomedThumbnailWidth` used by the in-grid slider — so the
  menu and the view stay in sync via the shared `@AppStorage` key, but the
  menu commands are testable/drivable only through the app's Zoom menu, not
  by finding a control inside the grid view's own AX subtree.
- `@AppStorage("LibraryGridView.thumbnailWidth")` default is
  `LibraryGridLayout.defaultThumbnailWidth` = **140** (`main.swift:562`,
  `LibraryGridView.swift:56`) — persists across relaunches via
  `UserDefaults`, scoped to the isolated app-support dir for a `--smoke`
  session (not Jesse's real prefs).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Confirm the footer's count text (`model.libraryCountText`) reflects
   `$TOTAL` (24) on first launch, and no "N selected" label/clear button is
   present (batch selection starts empty).
3. ⌘-click two grid cells to batch-select them. Confirm the footer now shows
   "2 selected" (`Label("\(model.selectedBatchAssetCount) selected", ...)`,
   line 2481) and a borderless "Clear selected batch" button
   (`AXHelp == "Clear selected batch"`) appears.
4. `ax_drive.sh press --role AXButton --help "Clear selected batch"`. Confirm
   the "N selected" label and clear button both disappear.
5. Click the "Compact" density preset (`ax_drive.sh find --role AXButton
   --label "Compact"` or similar — the exact AX role/title for
   `footerDensityControls` buttons should be confirmed live, they may render
   as a segmented control). Confirm `@AppStorage` value becomes 96 (read via
   `defaults read` on the isolated app's prefs domain, or infer from cell size
   shrinking in a captured screenshot) and grid spacing visibly tightens.
6. Click "Large". Confirm width becomes 220 and cells visibly grow.
7. Send ⌘+ (Zoom In, from the app's Zoom menu, not the grid) 3 times from a
   width-220 baseline. Confirm the stored width becomes 220+24=244 (still
   "Large" per the `>= 200` bucket) — read back via the same prefs mechanism
   as step 5, or via the density control's `isSelected`/accessibilityValue
   reading `"244 px, Large"` (`accessibilityValue`, `LibraryGridLayout.swift:
   35-37`).
8. Send ⌘+ repeatedly past 260. Confirm the value clamps at exactly 260 and
   stops increasing (does not overflow or wrap).
9. Send ⌘- repeatedly past 96 (from a low starting width). Confirm it clamps
   at exactly 96.

## Expected
- Step 2: count text and absence of "N selected" match ground truth.
  **Fails if** the count is wrong, or a stale "N selected" persists from a
  previous session's AppStorage/state leak.
- Step 3-4: label count matches the actual batch-selection size; clear button
  empties `model.selectedBatchAssetCount` to 0 and removes both the label and
  the button. **Fails if** clicking the clear button only visually hides the
  label without actually clearing `selectedBatchAssetCount` (check via
  subsequent footer state, not just the immediate render).
- Steps 5-6: preset clicks set the *exact* documented widths (96/140/220),
  not approximate values. **Fails if** a preset click lands off by any
  amount — these are meant to be exact snap points.
- Steps 7-9: zoom step is exactly 8 per press; clamping is exact at the
  documented bounds (96 and 260), never overshoots past them even after many
  presses. **Fails if** the step size drifts, or clamping allows a value
  outside `[96, 260]`.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The `densityLabel` bucket boundaries (`<120`, `>=200`, else) mean the
  "selected" state of a density preset button can go stale/ambiguous once a
  user free-zooms with ⌘+/⌘- into the gap between presets — e.g. width 150
  (via ⌘+ from 140) shows *no* preset as exactly matching its own value, but
  `isSelected` still lights up "Comfortable" (140's bucket) even though the
  actual width is 150, not 140. Worth confirming visually whether this reads
  as "close enough" or as a misleading UI state.
- Reading the persisted `@AppStorage` value from the isolated instance
  requires knowing its `UserDefaults` domain/bundle-id under the isolated
  app-support dir — confirm the exact mechanism (`defaults read <bundle-id>
  LibraryGridView.thumbnailWidth` against the isolated domain, not the real
  one) before relying on it in Step 5/7-9; if isolation doesn't cleanly
  separate `UserDefaults` domains, those steps may need to fall back to
  visual/screenshot inference only.

## Run status
NOT RUN — no live GUI launch performed for this task (headless-only
constraint). All layout constants verified by direct source read at
`Sources/TeststripApp/LibraryGridLayout.swift:4-76`; footer chrome and
⌘+/⌘- menu-only location verified at
`Sources/TeststripApp/LibraryGridView.swift:2469-2521` and
`Sources/TeststripApp/main.swift:561-577`. Needs a live AX session for all
Steps; Step 5's exact AX role/title for density-preset buttons needs live
confirmation since it wasn't verified in this pass.
