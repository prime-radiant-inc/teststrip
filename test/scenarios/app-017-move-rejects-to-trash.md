# app-017-move-rejects-to-trash: Move rejects to the macOS Trash, then move them back

**What this covers**: Trash-and-ux-coherence spec Part 1 — the trash sibling
of app-010's folder relocation. Culling ▸ "Move Rejects to Trash…"
(`AppModel.requestMoveRejectsToTrash` / `moveRejectsToTrashRequestToken`,
`Sources/TeststripApp/main.swift` CullingCommands) and the matching
end-of-set completion button both drive `AppModel.moveRejectsToTrash`, which
differs from folder relocation in three load-bearing ways: (1) files go to
the real platform Trash via `FileManagerRecycler`/`FileManager.trashItem`
(recoverable in Finder), not a chosen folder; (2) the catalog row and cached
previews are **removed**, not repointed — `deleteAsset` + `PreviewCache
.deleteAll`; (3) **Move back** re-inserts the row from the manifest's
`asset_snapshot_json` and moves the file back from its Trash URL, rather than
just reversing a path. The preflight sheet's warning copy and "Move N to
Trash" primary button (`RejectRelocationSheetPresentation`) are asserted at
the unit level (`RejectRelocationPreflightTests`); this card proves the
end-to-end filesystem/catalog behavior a unit test can't reach.

## Pre-state
- Fresh build, isolated catalog:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  PREVIEWS="$ISOLATED/Teststrip/Previews"
  ```
- No `TESTSTRIP_REJECT_DESTINATION_DIR` override — the Trash isn't a
  user-chosen folder, so trash mode has no destination panel to bypass.
- At least one seeded photo visible in the grid.

## Steps
1. **Capture a source original's path, its asset id, and a checksum**
   (ground truth):
   ```bash
   ASSET_ID=$(sqlite3 "$DB" "SELECT id FROM assets ORDER BY id LIMIT 1;")
   SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets WHERE id='$ASSET_ID';")
   test -f "$SRC" && echo "present: $SRC"
   SUM=$(shasum -a 256 "$SRC" | awk '{print $1}')
   echo "checksum: $SUM"
   ls "$PREVIEWS/$ASSET_ID" 2>/dev/null && echo "preview cached before trash"
   ```
2. **Flag it Reject.** `script/activate_app.sh Teststrip`; AX-press the first
   grid thumbnail to select it, then AX-press the inspector control whose
   accessible label is **"Reject"**. Re-dump; confirm the reject state renders.
3. **Move Rejects to Trash.** Open the Culling menu (System Events menu-bar
   click) and AX-press **"Move Rejects to Trash…"**. A confirmation sheet
   appears — assert its primary button's title is **"Move N to Trash"** (N =
   the reject count) and it carries the warning copy "Files go to the macOS
   Trash and the catalog forgets them." before confirming. Toggle the
   confirmation checkbox on, then AX-press the primary button. `waitFor` an
   `AXStaticText` **"Reject relocation complete"**.
4. **Assert the original moved to the real Trash and the catalog forgot it**:
   ```bash
   test ! -f "$SRC" && echo "left source: OK"
   TRASH_HIT=$(find "$HOME/.Trash" -maxdepth 1 -iname "$(basename "$SRC")*" 2>/dev/null | head -1)
   test -n "$TRASH_HIT" && echo "found in Trash: $TRASH_HIT"
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE id='$ASSET_ID';"          # expect 0
   sqlite3 "$DB" "SELECT count(*) FROM relocation_manifest_entries WHERE asset_id='$ASSET_ID';"  # expect 1
   ls "$PREVIEWS/$ASSET_ID" 2>/dev/null; echo "exit=$?"                       # expect nonzero (dir gone)
   ```
5. **Move back.** AX-press the **"Move back"** button (on the relocation
   completion surface). `waitFor` the completion state to clear.
6. **Assert the original returned byte-identical and the row is back**:
   ```bash
   test -f "$SRC" && echo "restored: $SRC"
   SUM2=$(shasum -a 256 "$SRC" | awk '{print $1}')
   test "$SUM" = "$SUM2" && echo "checksum match: OK"
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE id='$ASSET_ID';"          # expect 1
   ```

## Expected
- Step 3: the sheet's primary button reads "Move N to Trash" (not a folder
  name) and the warning copy is present. "Reject relocation complete" appears
  within 20s. **Fails if** the button says anything else, the warning copy is
  missing, or the completion state never appears.
- Step 4: `$SRC` gone from its source path, a same-named item present under
  `$HOME/.Trash`, the asset row count is 0, a manifest entry exists, and the
  preview directory is gone. **Fails if** the row still exists (catalog didn't
  forget it), the file exists in neither the source nor the Trash (data
  loss — report immediately), or the preview directory survives.
- Step 6: `$SRC` exists again at the identical path with an identical SHA-256
  checksum (byte-identical, proving non-destructive round-trip), and the
  asset row count is back to 1. **Fails if** the checksum differs, the path
  differs, or the row wasn't re-inserted.

## Cleanup
```bash
rm -f "$HOME/.Trash/$(basename "$SRC")"* 2>/dev/null
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **This is the real Finder Trash**, not a fake — `FileManagerRecycler` calls
  `FileManager.trashItem`. Run this card in the VM per the spec (never against
  a real machine's Trash with real photos). Empty the VM's Trash in cleanup if
  disk space matters between runs.
- **Move back can partially fail** if the Trash was emptied out-of-band
  between trash and restore (the manifest's Trash URL is gone); that's a
  documented skip-with-issue path, not a bug — this card's happy path doesn't
  exercise it, but don't confuse a stale Trash URL from a prior run with a
  regression.
- Don't assert on the grid re-appearing the asset — assert on `assets` row
  count and the filesystem, same discipline as app-010.
- The end-of-set completion state also exposes "Move Rejects to Trash…" as a
  plain (non-prominent) button beside "Move Rejects…"; Export stays the one
  prominent verb per spec Part 2 principle 2. Not driven by this card's
  happy path (menu path is sufficient to prove the model wiring) but worth a
  spot-check if the completion surface is touched later.
