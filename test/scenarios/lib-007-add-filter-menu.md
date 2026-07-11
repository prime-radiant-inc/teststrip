# lib-007-add-filter-menu: the "Add filter" menu covers enum fields with fixed option lists; free-text fields stay typed-only

**What this covers**: `addFilterMenu`
(`Sources/TeststripApp/LibraryGridView.swift`) is a `Menu` with six submenus
plus one direct action, each writing straight to an `AppModel` structured
filter property and calling `applyLibraryFilters()`. Per spec §2b it is now
the query field's **leading accessory** (rendered as `DesignGlyph.filterMenu`
= `line.3.horizontal.decrease`), not a separate trailing plus-circle button
— the query field and the filter menu are one control. It exists *only* for
enum/menu-driven fields that have a fixed, enumerable option set; free-text
fields (`camera`, `lens`, `keyword`, `folder`, `iso`) have **no** entry in
this menu at all — the doc comment above it states this explicitly
("Free-text fields ... stay reachable via typed tokens in the query field
itself"), and grepping the menu body confirms no
camera/lens/keyword/folder/iso submenu exists.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
PICKS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
```
Confirmed against a seeded `--smoke` catalog 2026-07-10: `PICKS=6`.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. `ax_drive.sh press --role AXButton --help "Add a filter"` (the
   `line.3.horizontal.decrease` filter-menu icon, now the query field's
   leading accessory) to open the menu.
3. Assert exactly these six submenu titles are present, each an `AXMenuItem`
   with children (a nested `Menu`, not a leaf `Button`): "Rating", "Flag",
   "Color Label", "Source", "AI Signal", "Metadata Sync", plus one leaf
   `Button` "Review Queue" (also a submenu, see step 5) and one final leaf
   action "Date Range…" (opens a popover, not a submenu).
3a. Open "AI Signal" and assert its leaf items are exactly the 15
   `LibraryQueryToken.signalOptions` display names, including
   "Color Palette" (present in the live menu per run-lib-iter1; the
   submenu is built from `signalOptions` = focus, motionBlur, exposure,
   aesthetics, framing, object, faceCount, faceQuality, eyesOpen,
   eyeSharpness, smile, ocrText, colorPalette, novelty, visualSimilarity,
   rendered via `EvaluationKind.displayName` — "Color Palette" for
   `.colorPalette`).
4. Open "Flag" and assert it contains exactly two leaf items, "Pick" and
   "Reject" (`LibraryQueryToken.flagOptions = [.pick, .reject]`,
   `.rawValue.capitalized` per line 871). Click "Pick".
5. Assert the result-count header now reads `$PICKS` and a "Pick" chip
   appears in the chip row (confirms the menu action writes
   `model.flagFilter` and triggers `applyLibraryFilters()`, lines 869-876).
6. Re-open "Add a filter" and confirm there is **no** "Camera", "Lens",
   "Keyword", "Folder", or "ISO" submenu anywhere in the menu tree — these
   fields are typed-only via the query field (per lib-006's tips popover).
7. Click "Date Range…" and assert a popover opens (distinct from the
   submenus — it's a direct `Button` action at line 933 that flips
   `isShowingDateFilters`, not a `Menu`).

## Expected
- Step 3: exactly 6 submenus + 1 leaf action ("Date Range…"), matching
  `addFilterMenu`'s body verbatim. **Fails if** a submenu is missing,
  renamed, or an extra one appears.
- Step 4: "Flag" has exactly 2 items, "Pick" / "Reject". **Fails if** the
  count differs from `LibraryQueryToken.flagOptions`.
- Step 5: picking "Pick" produces `$PICKS` and a chip. **Fails if** the
  count is off or no chip renders.
- Step 6: no free-text field appears as a menu entry. **Fails if** one does
  — that would mean either the comment at 854-858 is stale or a regression
  added menu-driven free-text filtering without updating the doc comment.
- Step 7: Date Range opens a popover, not a picker list. **Fails if** it's
  missing or behaves like the other submenus.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
"Metadata Sync" (lines 901-914) and "Review Queue" (lines 915-932) are the
odd ones out: every other submenu's items are declarative
`ForEach`-over-`LibraryQueryToken.<x>Options` (so adding an enum case
auto-updates the menu), but these two are hand-written `Button` lists with
no backing `Options` array in `LibraryQueryToken` — a future
`ReviewQueue`/`MetadataSyncFilterOption` case could silently fail to appear
here. Not a bug today (both enums are small and stable), but a
maintenance trap worth flagging. Also, "Metadata Sync"'s two buttons
manually toggle both `metadataSyncPendingFilter` and
`metadataSyncConflictFilter` off/on as a pair (comment says "Single-select,
matching the old picker") — this single-select behavior isn't enforced by
any shared type, just by both buttons remembering to clear the sibling flag;
worth an assertion that clicking "Conflicts" after "Pending" actually clears
`metadataSyncPendingFilter` if this card is later extended.

## Run status
NOT RUN — GUI/AX driving was not attempted this session. Menu structure
confirmed by reading `Sources/TeststripApp/LibraryGridView.swift:859-945`
(`addFilterMenu`) in full, and `LibraryQueryTokenField.swift`'s documented
`ratingOptions`/`flagOptions`/`colorOptions`/`sourceOptions`/`signalOptions`
for the enum-driven submenus. SQL dry-run headlessly against a fresh
`--smoke` catalog on 2026-07-10 (`PICKS=6`); schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`.
