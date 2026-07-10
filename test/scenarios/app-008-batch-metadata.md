# app-008-batch-metadata: ⌥⌘M opens the batch-metadata sheet and its scope picker governs the write

**What this covers**: Jesse tags a whole shoot in one pass. Inventory item 30
plus the sheet flow: Metadata ▸ Batch Metadata… (⌥⌘M) bumps
`batchMetadataRequestToken` (`MetadataActionCommands`,
`Sources/TeststripApp/main.swift:320-333`;
`AppModel.requestBatchMetadataSheet`, `AppModel.swift:2093-2099`), disabled
while importing or with an empty catalog; the sheet's segmented scope picker
(selected / visible / current scope via `BatchScopeMode`), the all-catalog
confirmation gate when the scope is unfiltered, keyword suggestions, and the
apply writing to the catalog + sidecars
(`LibraryGridView.batchMetadataPopover`, `LibraryGridView.swift:1062+`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Baseline the keyword ground truth before any write:
```bash
sqlite3 "$DB" "SELECT count(*) FROM assets WHERE metadata_json LIKE '%scenario-kw%';"   # expect 0
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 (Library).
2. **Open via keyboard.** Press ⌥⌘M. `ax_drive.sh wait --contains "Batch
   Metadata"`. Assert the scope picker renders with its segments (Selected /
   Visible / current-scope titles per `BatchScopeMode`) and a count line.
3. **Selected scope writes only the selection.** Close the sheet. Select
   exactly 2 grid thumbnails (click + shift/cmd-click). Reopen (⌥⌘M),
   choose the Selected scope, type a distinctive keyword `scenario-kw`
   into the keyword field, apply.
4. **Ground truth: exactly 2 rows changed.**
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE metadata_json LIKE '%scenario-kw%';"   # exactly 2
   ```
   Also assert an `.xmp` sidecar now exists next to those 2 originals (and
   only those) containing the keyword, and the originals' bytes are
   unchanged (compare a pre-captured hash of one original).
5. **All-catalog scope requires explicit confirmation.** Clear filters,
   reopen the sheet, pick the current-scope segment. Because no filters are
   active this targets the whole catalog: assert a confirmation affordance
   appears (`requiresAllCatalogConfirmation`) and that apply is inert until
   it is checked. Cancel without applying; re-run the step-4 count — still 2
   (nothing written by an unconfirmed all-catalog pass).
6. **Gating (item 30).** With the catalog empty (`--isolated` relaunch) or
   during an active import, open the Metadata menu: `Batch Metadata…` is
   disabled. (Empty-catalog relaunch is sufficient; the mid-import variant
   is optional.)

## Expected
- Step 2: sheet opens from the keyboard alone. **Fails if** ⌥⌘M is inert —
  the token plumbing between menu and view broke.
- Step 4: exactly 2 catalog rows and exactly 2 sidecars carry the keyword;
  original bytes untouched. **Fails if** the count is 0 (write lost), >2
  (scope leak — the worst outcome: a selected-scope action touched the whole
  library), or any original's hash changed.
- Step 5: unconfirmed all-catalog apply writes nothing. **Fails if** the
  confirmation gate is missing or apply works without it.
- Step 6: menu item disabled when empty/importing.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--smoke` is not a clean slate (11 flagged, 4 rated) — use a unique
  keyword string and count baseline-relative, never absolute metadata state.
- There is no `keywords` column; keywords live in `metadata_json`. The
  `LIKE '%scenario-kw%'` probe is deliberately schema-agnostic; confirm with
  `json_extract` once you've seen the JSON shape.
- The sheet renders as a popover/sheet whose fields may have placeholder-only
  identification — match empty fields with `--contains` against the
  placeholder per the README.
- Confirm-before-write nuance: typed keywords applied by the user ARE a user
  gesture (they write); the *suggestion* chips must not write until clicked.
  If a suggestion appears in step 3, assert it is absent from the catalog
  until explicitly applied.
