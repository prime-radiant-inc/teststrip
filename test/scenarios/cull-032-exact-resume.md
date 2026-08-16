# cull-032-exact-resume: quitting mid-run and relaunching offers resume at the exact frame with all decisions intact

**What this covers**: a cull run persists to a JSON file
(`cull-run-tracker.json` in the app-support directory) so quitting mid-run
and relaunching restores the exact frame position and all viewed/skipped
state. Covers SP-D Task 2: `CullRunTracker.Persistence` (save/load),
`cullRunTrackerURL`, `saveCullRunTracker()`, `resumeCullRunIfNeeded()` in
`AppModel.swift`. The tracker is UI state — NEVER persisted to the catalog.

## Pre-state
```bash
./script/build_and_run.sh --smoke   # seeds 24 synthetic photos
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TRACKER="$ISOLATED/Teststrip/cull-run-tracker.json"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Start a cull run (⌘R → Return). Decide a few frames (P or X, advancing with
   Space). Skip at least one frame (Space on an undecided frame). Note the
   current position from the counter (e.g., "7 of 24").
3. Assert the tracker file exists:
   ```bash
   test -f "$TRACKER" && echo "tracker exists" || echo "MISSING"
   ```
   Read the tracker JSON and verify it contains viewed and skipped asset IDs:
   ```bash
   cat "$TRACKER" | python3 -m json.tool | head -20
   ```
4. Quit the app (⌘Q). Relaunch with the same isolated directory:
   ```bash
   ./script/build_and_run.sh --smoke
   ```
   (The `--smoke` re-seeds metadata but the tracker file persists if the
   isolated dir is the same — verify the tracker file survives relaunch.)
5. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull. Assert the
   app offers to resume the run: `ax_drive.sh find --contains "Resume"` or
   the cull position counter shows the same position as step 2.
6. Assert the viewed/skipped state is restored: the scope line shows the same
   counts as before the quit (verify via `ax_drive.sh find --contains
   "skipped"`).

## Expected
- Step 3: tracker JSON file exists and contains viewedAssetIDs and
  skippedAssetIDs arrays. **Fails if** the file is missing (save not called on
  mutation) or empty.
- Step 5: after relaunch, the run resumes at the exact frame. **Fails if** the
  tracker is not loaded (resumeCullRunIfNeeded not called or fails silently).
- Step 6: viewed/skipped counts match the pre-quit state. **Fails if** the
  tracker was reset on resume instead of restored.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The tracker file lives at `$ISOLATED/Teststrip/cull-run-tracker.json` (in
  the app-support root, NOT the catalog). It is NEVER written to the SQLite
  catalog.
- `--smoke` re-seeds metadata flags on 11/24 photos. If the re-seed overwrites
  the isolated directory, the tracker file may be lost. The test should verify
  the tracker survives relaunch — if `--smoke` clears the directory, use
  `--isolated` for the relaunch (empty catalog) or verify the tracker file's
  persistence separately.
- The tracker resets on `startCullRunTracking()` (when a new run starts), NOT
  on scope cycling. Resuming a run should NOT reset the tracker.
- Decisions made outside the run (in the Library, between quit and relaunch)
  are respected: the run counts them and walks to what's still undecided.

## Run status
UNRUN — scenario card authored for SP-D Task 2. Awaits implementation
completion and VM run.
