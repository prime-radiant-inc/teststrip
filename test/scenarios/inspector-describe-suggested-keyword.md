# inspector-describe-suggested-keyword: ⌘I opens the inspector, and accepting a suggestion writes catalog + sidecar

**What this covers**: ⌘I toggles the tabbed inspector; the Describe tab's
suggested-keyword chip is a one-click accept that writes to both the catalog
and the `.xmp` sidecar (confirm-before-write: not written until clicked).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Pick a target with at least one keyword suggestion available (may require
running evaluation over the scope first so `selectedSuggestedKeywords` is
populated):
```bash
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library, select
   `$SRC`'s grid cell.
2. Press ⌘I. Assert the inspector panel opens with a Describe tab
   (`ax_drive.sh find --role AXButton --label "Describe"` or the tab-bar
   equivalent).
3. Confirm-before-write: `test ! -e "$SRC.xmp" || ! grep -qi "<suggested-keyword>" "$SRC.xmp"` —
   no sidecar keyword yet from merely opening the inspector/tab.
4. Click a suggested-keyword chip (`ax_drive.sh press --role AXButton --help "Accept <keyword>"`).
5. Assert the keyword now appears as a removable chip in the keywords list
   (catalog write reflected in UI).
6. Assert on disk: `sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE original_path='$SRC';"`
   includes the keyword, and `$SRC.xmp` exists with `dc:subject`/keyword entry
   matching it.

## Expected
- Step 2: Describe tab present after ⌘I; ⌘I again closes the inspector.
- Step 3: nothing written before the click (confirm-before-write holds).
- Step 6: keyword present in both `metadata_json` and the sidecar. **Fails
  if** either is missing, or if the keyword was written before the click.

## Cleanup
```bash
rm -f "$SRC.xmp"
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed:
`Sources/TeststripApp/InspectorView.swift:462` (`case .describe: "Describe"`),
`:1058-1094` (`suggestedKeywordChips`, `.help("Accept \(suggestion.keyword)")`,
`model.acceptSuggestedKeywordForSelectedAsset`),
`Sources/TeststripApp/main.swift:480-482` (⌘I `toggleInspector`). Needs a
human-present re-run. All SQL in this card was run headlessly against a seeded --smoke catalog on 2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift).
