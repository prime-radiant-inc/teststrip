# end-of-set-move-rejects: deciding all 24 shows completion, and Move Rejects relocates files on disk

**What this covers**: the Cull workspace's end-of-set handoff
(`CullCompletionPresentation`, `accessibilityLabel("End of set")`) once every
seeded frame has a flag, and that "Move Rejects…" actually moves the
rejected originals on disk (not just in the catalog).

## Pre-state
```bash
./script/build_and_run.sh --smoke   # seeds 24 synthetic photos
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Decide all 24 frames (P or X each, advancing with Space) — a driver loop
   is fine here (this is bulk setup, not the assertion). Confirm via sqlite:
   `SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL;` reads 0.
3. Assert the completion state renders: `ax_drive.sh find --contains "End of set"`
   (accessibility label) or the visible completion copy/actions.
4. Record the rejected originals' paths:
   ```bash
   REJECTS=$(sqlite3 "$DB" "SELECT original_path FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject';")
   ```
5. Click "Move Rejects…" (`ax_drive.sh press --role AXButton --label "Move Rejects…"`),
   complete the destination-folder sheet.
6. Assert on disk: every path in `$REJECTS` no longer exists at its old
   location and exists at the new destination; assert the catalog's
   `original_path` for those rows now points at the new location (relocation,
   not a copy — old path gone).

## Expected
- Step 3: completion state visible once the last frame is decided.
- Step 6: every rejected original is physically moved (old path gone, new
  path exists) and the catalog's `original_path` tracks the move. **Fails
  if** files are copied instead of moved (both paths exist), or the catalog
  still points at the stale path.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Completion-state and
Move Rejects wiring confirmed by source read:
`Sources/TeststripApp/CullCompletionPresentation.swift:17`,
`Sources/TeststripApp/LibraryGridView.swift:3570-3615` (end-of-set handoff,
`accessibilityLabel("End of set")`), `:3625` (`Button("Move Rejects…")`).
Needs a human-present re-run.
