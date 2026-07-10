# lib-011-view-toggle-routing: the Library View picker's 4 tags each route the body to the correct sub-view

**What this covers**: `librarySubViewToggle`
(`Sources/TeststripApp/LibraryGridView.swift:442-451`) is a `Picker("Library
View", ...)` bound to `model.selectedView` (`LibraryViewMode`) offering
exactly 4 tags — `.grid` ("Grid"), `.libraryLoupe` ("Loupe"), `.timeline`
("Timeline"), `.map` ("Map") — even though `LibraryViewMode` itself
(`AppModel.swift:6-20`) has 9 cases total (`grid`, `loupe`, `libraryLoupe`,
`compare`, `abCompare`, `timeline`, `map`, `people`, `cullGrid`); the other 5
are reached by other routes (⌘I inspector, Cull workspace, People
workspace, A/B compare shortcut, etc.), not this picker. The view's `body`
(`LibraryGridView.swift:74-120`) switches on `model.selectedView` in a
specific priority order — `.people` first, then `.timeline`, then `.map`,
then (if `model.assets.isEmpty`) an empty-state view *before* checking
`.loupe`/`.libraryLoupe`, then `.compare`, `.abCompare`, and finally the
default `assetGrid` branch for `.grid` and anything else unmatched.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
Confirmed against a seeded `--smoke` catalog 2026-07-10: `TOTAL=24` (grid is
non-empty, so the empty-state branch at line 87 does not intercept the
Grid/Loupe cases below).

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library (only
   Library shows this picker — `WorkspaceChromePolicy.showsLibraryViewToggle`
   returns true only for `workspace == .library`,
   `LibraryGridView.swift:7225-7227`).
2. `ax_drive.sh find --role AXRadioButton --label "Grid"` (or the
   segmented-picker equivalent) and assert all 4 labels exist: "Grid",
   "Loupe", "Timeline", "Map" — no more, no fewer.
3. Select "Grid". Assert the rendered content is the lazy asset grid
   (`assetGrid`, scrollable `LazyVGrid` with `$TOTAL` cells reachable by
   scrolling) — confirms the fallback `else` branch at line 101-120 handles
   `.grid`.
4. Select "Loupe". Assert the rendered content switches to a single-photo
   loupe view (no grid cells present) — confirms line 91's
   `.loupe || .libraryLoupe` branch fires for `.libraryLoupe` specifically
   (the tag this picker uses, per line 448), and that it renders before the
   `.compare`/`.abCompare` checks.
5. Select "Timeline". Assert a date-grouped/timeline-specific layout
   renders (distinct chrome from the grid) — confirms line 77's branch,
   which fires *before* the empty-state and loupe checks.
6. Select "Map". Assert a map view renders (e.g. a `MKMapView`/places
   cluster surface) — confirms line 85's branch.
7. Cycle back to "Grid" and confirm the grid reappears with the same
   `$TOTAL` cell count as step 3 (round-trip, no state loss).

## Expected
- Step 2: exactly 4 tags, matching `librarySubViewToggle` verbatim.
  **Fails if** a 5th tag appears (e.g. someone wires `.people` or
  `.compare` into this picker) or one is missing/mislabeled.
- Steps 3-6: each tag routes to its documented view per the `body`
  switch's priority order. **Fails if** any tag renders the wrong content,
  or if selecting "Timeline"/"Map" incorrectly falls through to the grid
  (would indicate the `body` branch order regressed — e.g. if the
  empty-state check at line 87 were reordered above `.timeline`/`.map`,
  those modes would show blank library instead of their real content on an
  empty catalog; not applicable here since `$TOTAL=24`, but worth a
  follow-up card against an empty `--isolated` catalog).
- Step 7: Grid survives a round trip through the other 3 modes with no
  content loss. **Fails if** the grid shows fewer than `$TOTAL` cells after
  cycling.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
The `body` switch's empty-state check (`model.assets.isEmpty`, line 87) sits
*between* the `.map` check and the `.loupe`/`.libraryLoupe` check, but
*after* the `.people` and `.timeline` checks. That means on an empty
catalog, Timeline and Map still render their real (empty) views, but Loupe,
Compare, and the plain grid all get pre-empted by the generic
`emptyLibraryView` instead of their own mode-specific empty state. This
looks intentional (Timeline/Map likely have their own empty-state chrome)
but is worth a dedicated empty-catalog card (`--isolated` with no seed) to
confirm Loupe doesn't silently show a generic "no photos" screen when a
photo *is* selected but preview generation hasn't finished — not verified
here since `--smoke` always seeds 24 assets. Also note `LibraryViewMode`
has both `.loupe` and `.libraryLoupe` as separate cases handled by the same
`body` branch (line 91) — the picker only ever sets `.libraryLoupe` (line
448); `.loupe` is reached from elsewhere (the Cull workspace's loupe route,
per the file's own comment at lines 438-441 distinguishing "the plain-chrome
Library loupe" from "the culling loupe"). This card doesn't cover that
other route — see `library-loupe-no-cull-chrome.md` for the Cull-side loupe
chrome distinction.

## Run status
NOT RUN — GUI/AX driving was not attempted this session. Picker and routing
logic confirmed by reading `Sources/TeststripApp/LibraryGridView.swift:73-120`
and `438-451` in full, and `LibraryViewMode`'s full case list at
`Sources/TeststripApp/AppModel.swift:6-20`. SQL dry-run headlessly against a
fresh `--smoke` catalog on 2026-07-10 (`TOTAL=24`); schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`.
