# cull-033-completion-mini-runs: one-key numbered jumps start scoped mini-runs from the completion summary

**What this covers**: when the completion summary appears (all frames
decided), each line is a one-key jump (1–6) for a scoped mini-run: 1 Cull
undecided, 2 Cull skipped, 3 Cull never-viewed, 4 Review ✨, 5 Export, 6 Move
rejects. Covers SP-D Task 6: `MiniRun` type and `miniRuns` array in
`CullCompletionPresentation.swift`, mini-run starter methods in `AppModel.swift`
(`cullUndecidedFromCompletion()`, `cullSkippedFromCompletion()`,
`cullNeverViewedFromCompletion()`, `reviewAIFromCompletion()`), and numbered
buttons in `LibraryGridView.swift`'s completion stage.

## Pre-state
```bash
./script/build_and_run.sh --smoke   # seeds 24 synthetic photos
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Start a cull run (⌘R → Return). Skip a few frames (Space without P/X).
   Then decide all remaining frames (P or X each, advancing with Space).
   Confirm all decided:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL;"
   ```
   reads 0 (all have confirmed flags — tentative ✨ flags don't count).
3. Assert the completion stage renders: `ax_drive.sh find --contains "End of
   set"` and `ax_drive.sh find --contains "Nothing left to decide"`.
4. Assert the mini-run numbered jumps are present:
   - "1 Cull undecided" (if undecidedCount > 0 — after step 2, undecided should
     be 0, so this line may be omitted; verify the actual behavior)
   - "2 Cull skipped" (if skippedCount > 0 — we skipped frames in step 2)
   - "3 Cull never-viewed" (if neverViewedCount > 0 — frames the run never
     landed on)
   - "4 Review ✨" (if awaitingReviewCount > 0 — only if autopilot ran)
   - "5 Export" (always available)
   - "6 Move rejects" (if rejectCount > 0)
   Use `ax_drive.sh find --contains "Cull skipped"` etc. to verify each.
5. Press "2" (or click the "Cull skipped" button). Assert a new culling
   session starts, scoped to the skipped frames: the loupe appears and the
   position counter shows a narrowed set. Verify via the catalog:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM work_sessions WHERE kind='cull';"
   ```
   reads ≥ 2 (the original session + the mini-run session).
6. Decide all frames in the mini-run. Assert the completion stage appears
   again with updated counts (skipped should now be 0).

## Expected
- Step 4: mini-run numbered jumps render with stable numbers (1=undecided,
  2=skipped, 3=never-viewed, 4=review, 5=export, 6=move). Zero-count lines are
  omitted but numbers don't renumber. **Fails if** numbers are unstable or
  zero-count lines render.
- Step 5: pressing a mini-run number key starts a scoped cull. **Fails if**
  the key does nothing (mini-run starter not wired) or starts the wrong scope.
- Step 6: the mini-run completes and the summary updates. **Fails if** the
  skipped count doesn't decrease or the completion stage doesn't reappear.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Mini-run numbers are stable: 1=undecided, 2=skipped, 3=never-viewed,
  4=review, 5=export, 6=move. If a count is 0, that entry is omitted but the
  remaining entries keep their canonical numbers (no renumbering).
- Export (5) is always available — it doesn't depend on a count being > 0.
- Move rejects (6) appears only if rejectCount > 0.
- The ceremonies (Export, Move Rejects, Save Picks as Set) are separate from
  the mini-run numbered jumps — they render below the numbered jumps, matching
  the tutorial's layout.
- `--smoke` has no autopilot/AI proposals, so the "4 Review ✨" line will be
  omitted (awaitingReviewCount = 0). To test this line, run autopilot first.
- After step 2 decides all frames, "undecided" should be 0, so the "1 Cull
  undecided" line should be omitted. The skipped frames from step 2 provide
  the "2 Cull skipped" entry.

## Run status
PASS (2026-08-16) — VM run via `script/vm_scenario_run.sh`. Drove through
all 24 frames (Space to skip 13 undecided, advance through 11 pre-decided);
completion stage appeared with "End of set" / "Nothing left to decide" /
"One-key mini-runs". Mini-run buttons accessible via `ax_drive.sh find`
(e.g. "5 Export"). Clicked "Cull skipped" via AXPress → new culling session
scoped to 13 skipped frames. Decided all 13 with P → completion reappeared
with "0 skipped · 0 never viewed". Catalog: 0 nil-flagged assets, 2 culling
sessions (1 completed + 1 running). Added `.accessibilityLabel` and
`.keyboardShortcut` to mini-run buttons for testability.
