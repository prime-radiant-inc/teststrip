# reject-relocation-move-and-back: Move rejects to a folder, then move them back

**What this covers**: the reject-relocation feature merged at migration 16 —
Teststrip's first origin-relocating action. Flagging a photo Reject, then
**Move Rejects**, must physically move the original file (and its XMP sidecar)
into the chosen folder, record a `relocation_manifest_entries` row, and be
fully reversible via **Move back**. The load-bearing assertions are on the
filesystem: the original leaves its source path on Move, and returns to the
exact same path on Move back — per-file atomic, nothing orphaned.

## Pre-state
- Fresh build, isolated catalog:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
- A scratch destination folder that does NOT already exist inside any source
  root: `REJECTS=$(mktemp -d)/rejects` (do not `mkdir` it; let the app create it).
- At least one seeded photo visible in the grid.

## Steps
1. **Capture a source original's path** (ground truth):
   ```bash
   SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
   test -f "$SRC" && echo "present: $SRC"
   ```
2. **Flag it Reject.** `script/activate_app.sh Teststrip`; AX-press the first
   grid thumbnail to select it, then AX-press the inspector control whose
   accessible label is **"Reject"**. Re-dump; confirm the reject state renders
   (the verdict/flag shows Reject on the selected asset).
3. **Assert the flag is provisional-but-persisted** (reject flag is a user
   gesture, so it IS written — unlike autopilot proposals):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE keep_state='reject' OR rating < 0;"
   ```
   Expect ≥ 1. (Verify the real column via `.schema assets` first.)
4. **Move Rejects.** AX-press the toolbar button labeled **"Move Rejects"**.
   A confirmation appears, then the native folder panel. In the panel, navigate
   to `$REJECTS` (Cmd+Shift+G, type the path, Enter) and confirm. `waitFor` an
   `AXStaticText` **"Reject relocation complete"**.
5. **Assert the original physically moved**:
   ```bash
   test ! -f "$SRC" && echo "left source: OK"        # original gone from source path
   ls "$REJECTS"                                       # original now here
   sqlite3 "$DB" "SELECT count(*) FROM relocation_manifest_entries;"   # ≥ 1
   ```
6. **Move back.** AX-press the **"Move back"** button (on the relocation
   completion surface). `waitFor` the completion state to clear.
7. **Assert the original returned to its exact original path**:
   ```bash
   test -f "$SRC" && echo "restored: $SRC"
   test -z "$(ls -A "$REJECTS" 2>/dev/null)" && echo "rejects dir emptied"
   ```

## Expected
- Step 4: "Reject relocation complete" within 20s. **Fails if** it never
  appears or an error alert shows.
- Step 5: `$SRC` no longer exists at its source path, appears under `$REJECTS`,
  and manifest count ≥ 1. **Fails if** the original file is still at `$SRC`
  (nothing moved) OR exists in neither place (data loss — report immediately).
- Step 7: `$SRC` exists again at the identical path; `$REJECTS` is empty.
  **Fails if** the original did not return, or returned to a different path.
  Quote the `$SRC` path and the `test -f` results before and after.

## Cleanup
```bash
rm -rf "$(dirname "$REJECTS")"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **The destination is a native `NSOpenPanel`** — there is no typed-path test
  hook for reject relocation (only card import has `TESTSTRIP_CARD_IMPORT_ROUTE`).
  Drive it via AX: focus the panel, Cmd+Shift+G, type `$REJECTS`, Enter, then
  press the panel's default button. If AX cannot reach the panel, that is a
  reportable driveability gap — note it and recommend adding a
  `rejectDestinationParent` test override mirroring the card-import route, rather
  than faking the move.
- Assert on the **filesystem**, not the grid. The grid may keep showing a cached
  preview for a moved-away original (previews are cached independently of the
  original's availability). The `test -f` on the real path is authoritative.
- Confirm the reject `keep_state`/`rating` column names against `.schema assets`
  before trusting step 3's count.
