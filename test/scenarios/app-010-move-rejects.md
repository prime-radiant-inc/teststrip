# app-010-move-rejects: Move rejects to a folder, then move them back

**What this covers**: Jesse finishes a cull and sweeps the rejects out of the
shoot folder — reversibly. Inventory items 34-37: Culling ▸ Move Rejects…
request-token path gated on non-empty/non-importing
(`Sources/TeststripApp/main.swift` CullingCommands,
`AppModel.requestMoveRejects`); the preflight sheet + confirm with the
`TESTSTRIP_REJECT_DESTINATION_DIR` override; per-file move of original +
sidecar with a `relocation_manifest_entries` row (WorkSession persisted
first, abortable); and the completion banner's **Move back** (manifest
reverse) + Dismiss. Underlying feature merged at migration 16 —
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
  Launch with the typed-path destination override so the native folder panel is
  bypassed deterministically:
  ```bash
  REJECTS=$(mktemp -d)/rejects
  TESTSTRIP_REJECT_DESTINATION_DIR="$REJECTS" ./script/build_and_run.sh --smoke
  ```
  The confirmation sheet before the move still appears (only the folder picker
  is bypassed); AX-confirm it as in Step 4.
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
   With `TESTSTRIP_REJECT_DESTINATION_DIR` set the folder panel is skipped and
   the destination is `$REJECTS`; a confirmation sheet still appears — AX-confirm
   it. `waitFor` the **"Move back"** button (AXLabel "Move back", AXHelp "Move
   these photos back to where they came from") — this is the completion
   banner's only AX-exposed static content; the banner's own "Reject
   relocation complete" string is set as its *container* accessibilityLabel
   (`.contain` children policy), which `ax find`/`waitFor`'s title/description/
   value substring match does not surface as a separate element. Driven live
   in the VM twice (app-010, app-017): the string never matched, but "Move
   back" reliably did. (Without the override, navigate the native panel to
   `$REJECTS` via Cmd+Shift+G first.)
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
- Step 4: the completion banner's "Move back" button appears within 20s.
  **Fails if** it never appears or an error alert shows.
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
- **The destination is a native `NSOpenPanel`**, bypassed here by the
  `TESTSTRIP_REJECT_DESTINATION_DIR` env override (set in Pre-state). With that
  var set, Step 4 skips the folder panel entirely and moves to `$REJECTS`
  directly — the confirmation sheet still appears and must be confirmed. If you
  run without the override, drive the panel via AX: focus it, Cmd+Shift+G, type
  `$REJECTS`, Enter, press the default button.
- Assert on the **filesystem**, not the grid. The grid may keep showing a cached
  preview for a moved-away original (previews are cached independently of the
  original's availability). The `test -f` on the real path is authoritative.
- Confirm the reject `keep_state`/`rating` column names against `.schema assets`
  before trusting step 3's count. Per `CatalogMigrations.swift` there is no
  `rating` column — flag/rating live in `metadata_json`; expect a
  `json_extract(metadata_json, ...)` query instead.
- Item 34's menu entry: Culling ▸ Move Rejects… reaches the same
  `requestMoveRejects()` token as the toolbar button. Run Step 4 via the menu
  at least once (System Events menu-bar click) to prove the menu path, and
  note it is disabled while importing or when the catalog is empty.
