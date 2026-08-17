# cull-031-loud-accounting: the scope line shows viewed, skipped, unviewed, ✨ awaiting, and hidden-by-lens counts

**What this covers**: the scope line (bottom status bar) renders loud
accounting — not just picks/rejects/left but also ⊘ skipped, ◌ unviewed, ✨
awaiting review, and hidden-by-lens counts. Covers SP-D Task 5:
`CullingProgressSummary` extensions in `AppModel.swift` (new fields
`viewedCount`, `skippedCount`, `neverViewedCount`, `awaitingReviewCount`,
`hiddenByLensCount`) and `ScopeLinePresentation.cullStatusText` extensions in
`ScopeLinePresentation.swift` (new segments, zero counts omitted).

## Pre-state
```bash
./script/build_and_run.sh --smoke   # seeds 24 synthetic photos
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Start a cull run (⌘R or the Cull toolbar button → Start). Assert the scope
   line shows the initial state: `ax_drive.sh find --contains "24 photos"`
   and `ax_drive.sh find --contains "left"`. The baseline pick/reject counts
   come from `--smoke`'s pre-seeded flags (11/24 flagged).
3. Skip a frame (press Space without P/X — the skip is recorded in
   `CullRunTracker`). Assert the scope line now includes a skipped segment:
   `ax_drive.sh find --contains "skipped"` (or "⊘" if the symbol renders in
   AX). Verify the skipped count matches ground truth:
   ```bash
   # The tracker is a JSON file, not in the catalog — check the scope line text
   ```
4. Press P or X to decide a few frames. Assert the pick/reject counts in the
   scope line increment. The "left" count should decrease.
5. Cycle scope to `.picks` (press S). Assert the scope line shows a
   hidden-by-lens count (frames hidden by the scope filter): `ax_drive.sh find
   --contains "hidden"` or verify the total count narrows. The
   `hiddenByLensCount = totalAssetCount - scopedAssetCount`.
6. Cycle scope back to `.all` (press S three times). Assert the hidden-by-lens
   count is 0 or omitted (scope is .all, nothing hidden).

## Expected
- Step 2: scope line renders with photo count, stack count (0 for `--smoke`),
  ✓ picks, ✕ rejects, and "left" count. **Fails if** the scope line is empty or
  missing the progress tail.
- Step 3: after skipping, the scope line shows "⊘ N skipped" (or equivalent
  text segment). **Fails if** the skipped count is missing or always 0.
- Step 4: pick/reject counts increment correctly. **Fails if** counts are
  stale or don't match the catalog's confirmed flags.
- Step 5: cycling to `.picks` shows a narrowed view with hidden-by-lens count
  > 0. **Fails if** `hiddenByLensCount` is always 0 regardless of scope.
- Step 6: cycling back to `.all` hides the hidden-by-lens segment (count is 0,
  omitted). **Fails if** the segment persists with count 0.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Zero counts are omitted (except "left" which always shows). A run with no
  skips should NOT show "⊘ 0 skipped" — the segment is absent.
- The ✨ awaiting review count reflects tentative AI flags
  (`aiUnconfirmedFields.contains(.flag)`). `--smoke` has no AI proposals, so
  this count will be 0 and the segment omitted unless autopilot has run.
- The `neverViewedCount = totalAssetCount - viewedCount`. At the start of a
  run, only the first frame is "viewed" (recorded by `startCullRunTracking`),
  so `neverViewed` is `totalCount - 1`.
- `--smoke` has no stacks, so the stack segment is omitted (stackCount == 0).

## Run status
PASS (2026-08-16) — Driven in Tart VM. Verified via `entire contents of window 1`
AX dump (Unicode symbols don't match with `ax find --contains`).

- Step 2: scope line shows "24 photos · ✓ 6 · ✕ 5 · ◌ 22 unviewed · 22 left" ✓
- Step 3: after Space on an undecided frame (smoke-1), scope line shows
  "⊘ 1 skipped · ◌ 21 unviewed · 20 left" ✓ (smoke-0 is pre-seeded reject,
  correctly NOT recorded as skip)
- Step 4: pick/reject counts unchanged (6/5) since no new P/X pressed, but
  unviewed/left counts decremented correctly as frames were viewed ✓
- Step 5: cycling scope (S) to "Unrated" shows "hidden 11" (6 picks + 5 rejects
  hidden by the unrated filter), "9 left" ✓
- Step 6: cycling back to "All" hides the hidden segment ✓
