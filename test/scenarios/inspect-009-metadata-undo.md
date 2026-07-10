# inspect-009-metadata-undo: ⌘Z/⇧⌘Z on metadata edits use a dedicated undo stack with labeled change groups

**What this covers**: the inspector's metadata edits go through a dedicated
undo/redo stack (`metadataUndoStack`/`metadataRedoStack` on `AppModel`) that
**replaces** AppKit's standard `.undoRedo` command group
(`CommandGroup(replacing: .undoRedo)`, `main.swift:249`) rather than layering
on top of it — so ⌘Z/⇧⌘Z for metadata edits is a distinct mechanism from any
other undo surface in the app. Each change group carries a human-readable
label (e.g. "Rating · 3 photos" for a 3-photo batch edit), and starting a new
edit after an undo clears the redo stack.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
SRC_A=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
SRC_B=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1 OFFSET 1;")
SRC_C=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1 OFFSET 2;")
RATING_A_BEFORE=$(sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.rating') FROM assets WHERE original_path='$SRC_A';")
RATING_B_BEFORE=$(sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.rating') FROM assets WHERE original_path='$SRC_B';")
RATING_C_BEFORE=$(sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.rating') FROM assets WHERE original_path='$SRC_C';")
```
`--smoke`'s pre-seeded ratings vary per asset (per README.md, "4/24 rated
3") — record the actual before-values above rather than assuming 0, since
undo must restore the *exact* prior value, not a bare "0".

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 Library; multi-select
   `$SRC_A`, `$SRC_B`, `$SRC_C` (⌘-click each thumbnail); ⌥⌘2 for Describe.
2. Press "Rate 5" (`ax_drive.sh press --role AXButton --help "Rate 5"`).
   Assert all three assets now show `"rating":5` in `metadata_json`:
   ```bash
   sqlite3 "$DB" "SELECT original_path, json_extract(metadata_json,'\$.rating') FROM assets WHERE original_path IN ('$SRC_A','$SRC_B','$SRC_C');"
   ```
3. **Group label.** Before undoing, there's no direct AX surface for the
   pending undo label short of the (disabled-by-default, but here we're
   asserting content not disabled-state) Edit menu item text — assert the
   menu's "Undo Metadata Change" item is enabled
   (`model.canUndoMetadataChange`, `main.swift:255-256`). If the menu item
   title itself is dynamic elsewhere in the app (some AppKit undo surfaces
   append the action name), check for a title containing "Rating · 3 photos"
   (`photoCountDescription`, scoped label built in
   `updateSelectedAssetsMetadata`, `AppModel.swift:6467-6470`); if the menu
   title is static ("Undo Metadata Change" always, not dynamically suffixed
   per `main.swift:252-256`'s hardcoded string), note that the label is
   consumed by `model.lastUndoableActionLabel`
   (`AppModel.swift:2386-2388`) and/or `model.statusMessage` rather than the
   menu text — confirm which surface actually renders "Rating · 3 photos" to
   the user on the live run and correct this step's exact assertion target.
4. Press ⌘Z. Assert all three assets revert to their pre-seeded ratings
   (`$RATING_A_BEFORE`/`$RATING_B_BEFORE`/`$RATING_C_BEFORE`, not a blanket
   0) — `undoMetadataChange` applies `change.before` per asset
   (`AppModel.swift:6402-6409`), so a batch of 3 with mixed starting ratings
   must restore each to its own prior value, not a shared one. Confirm
   `model.statusMessage` (if surfaced in the UI, e.g. a toast/status bar)
   reads "Undid: Rating · 3 photos" (`AppModel.swift:6408`).
5. Press ⇧⌘Z (Redo). Assert all three assets are back to rating 5. Confirm
   the redo status text if visible: "Redid: Rating · 3 photos"
   (`AppModel.swift:6417`).

### Redo clears on a new edit after undo
6. Press ⌘Z again (undo the rating-5 batch, back to pre-seeded values).
7. Make a **new, different** edit: with the same 3-asset selection, press
   "Reject" flag (`ax_drive.sh press --role AXButton --help "Reject"`).
   Assert all three now show `"flag":"reject"`.
8. Assert the Redo menu item ("Redo Metadata Change") is now **disabled**
   (`model.canRedoMetadataChange` false, `main.swift:258-262`) —
   `recordMetadataChangeGroup` clears `metadataRedoStack` on every new
   recorded group (`AppModel.swift:6395-6400`). **This is the point of the
   step**: the rating-5 redo that was available after step 6 is gone once a
   new edit (the reject) was made.
9. Press ⇧⌘Z anyway (should be a no-op given the disabled state, but confirm
   behaviorally too): assert `metadata_json` for all three assets is
   unchanged by the keypress (still `"flag":"reject"`, ratings still at
   their step-6 undone values) — `redoMetadataChange` guards on
   `metadataRedoStack.popLast()` returning nil and simply returns
   (`AppModel.swift:6411-6412`).

### Single-asset label (no "· N photos" suffix)
10. Deselect down to just `$SRC_A`. Set its color label to "Purple". Assert
    the recorded label is the bare `"Color label"` (no photo-count suffix,
    since `changes.count == 1` — `updateSelectedAssetsMetadata`'s
    `scopedLabel` ternary only appends `"· N photos"` when `changes.count >
    1`, `AppModel.swift:6467-6470`). ⌘Z; assert `$SRC_A`'s label reverts.

## Expected
- Step 2: all three assets rated 5. **Fails if** the batch rating missed any
  asset in the multi-select.
- Step 4: each asset restores to its own individual pre-edit rating (not a
  single shared value), and the undo is one gesture for all three (a single
  ⌘Z, not three). **Fails if** ⌘Z only reverts one asset, or reverts all
  three to the same (wrong) value.
- Step 5: redo restores rating 5 to all three. **Fails if** redo is a no-op
  or partial.
- Step 8: Redo is disabled after a new edit follows an undo. **Fails if**
  the stale rating-5 redo is still available (a real bug — redoing at that
  point would silently resurrect a discarded change alongside the reject
  edit, corrupting the edit history from the user's perspective).
- Step 9: the disabled redo doesn't mutate state even if ⇧⌘Z is pressed
  anyway. **Fails if** it does.
- Step 10: single-asset label omits the count suffix. **Fails if** it always
  appends "· 1 photos" or similar.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Where the label text actually surfaces to the user is not fully
  confirmed from static reading** — `main.swift`'s menu item titles are the
  hardcoded strings "Undo Metadata Change"/"Redo Metadata Change", not
  dynamically built from `lastUndoableActionLabel`; the scoped label
  ("Rating · 3 photos") appears to live in `model.statusMessage`
  (`AppModel.swift:6408,6417`) and `model.lastUndoableActionLabel`
  (`:2386-2388`), whose UI surface (status bar? toast?) needs confirming
  live — step 3/4/5's exact assertion target should be corrected against
  whatever surface actually renders it.
- This card only exercises the batch (`...ForSelectedAssets`) family's undo
  labeling. The keyword/caption/creator/copyright (`...ForSelectedAsset`,
  singular) family also calls `recordMetadataChangeGroup` and shares the
  same stack (`AppModel.swift:6420-6445` region), so a single caption edit
  and a single rating edit interleave on one undo stack — not separately
  probed here, but worth confirming a mixed undo history (rating, then
  caption, then ⌘Z ⌘Z) unwinds in strict LIFO order across the two families
  if a follow-up card is warranted.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed
statically: `Sources/TeststripApp/main.swift:248-263`
(`MetadataHistoryCommands`, `CommandGroup(replacing: .undoRedo)`, ⌘Z/⇧⌘Z
bindings gated on `canUndoMetadataChange`/`canRedoMetadataChange`),
`Sources/TeststripApp/AppModel.swift:2378-2388` (`canUndoMetadataChange`,
`canRedoMetadataChange`, `lastUndoableActionLabel`), `:6395-6418`
(`recordMetadataChangeGroup` clearing the redo stack on every new group,
`undoMetadataChange`, `redoMetadataChange`), `:6443-6470`
(`updateSelectedAssetsMetadata`, the `scopedLabel` "· N photos" suffix logic
via `photoCountDescription`). Needs a human-present re-run. All SQL in this
card was run headlessly against a seeded --smoke catalog on 2026-07-10
(schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift); the
pre-seeded per-asset ratings for the three chosen targets were read directly
rather than assumed.
