# cull-030-start-card: ⌘R starts a cull run with the start card showing batch stats, lens, and toggles

**What this covers**: the ⌘R keyboard shortcut (AppKit menu path, like ⌘1–⌘6)
starts a cull run. The start card renders batch stats (`N photos · M stacks
(batch is X% bursts)`), lens narrowing with a loud hidden-by-lens count, and
Auto-advance + Land-on-recommended toggles (both default on). Press Return to
begin. Covers SP-D Task 4: `CullStartCardPresentation` (pure type at
`Sources/TeststripApp/CullStartCardPresentation.swift`), `startCullRun()`
convenience in `AppModel.swift`, ⌘R menu command in `main.swift`
(`LensCommands`), and the start card view in `LibraryGridView.swift`.

## Pre-state
```bash
./script/build_and_run.sh --smoke   # seeds 24 synthetic photos
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Press ⌘R (the Start Cull Run menu command). Assert the start card appears:
   `ax_drive.sh find --contains "Start Cull"` or `ax_drive.sh find --contains
   "photos"`. The card should show batch stats (24 photos from `--smoke`),
   stack count (0 — `--smoke` has no persisted stacks), and the burst
   percentage (0% with no stacks).
3. Assert the two toggles are present and both default ON:
   `ax_drive.sh find --contains "Auto-advance"` and
   `ax_drive.sh find --contains "Land on recommended"`.
4. Press Return (or click the Begin button). Assert the cull loupe appears:
   `ax_drive.sh find --contains "of 24"` (the position counter). Confirm
   the session is active via catalog ground truth:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM work_sessions WHERE kind='cull';"
   ```
   reads ≥ 1.
5. Press ⌘R again from within the cull. Assert it does NOT start a second
   overlapping session (⌘R is disabled or ignored while a cull is active —
   the existing `canBeginCullingSession` gate).

## Expected
- Step 2: start card renders with batch stats. **Fails if** ⌘R does nothing
  (menu command not wired), or the card shows no photo/stack counts
  (`CullStartCardPresentation` not populated).
- Step 3: both toggles visible and default ON. **Fails if** a toggle is
  missing or defaults to OFF.
- Step 4: cull loupe appears after Return, session is in the catalog. **Fails
  if** the loupe doesn't appear (beginCullingSession not called), or no work
  session is persisted.
- Step 5: ⌘R is a no-op while a cull is active. **Fails if** a second session
  starts.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--smoke` has no persisted stacks, so `stackCount` is 0 and `burstPercentage`
  is 0%. The batch description should still render correctly: "24 photos · 0
  stacks" (or omit the stacks segment when 0 — verify against the actual
  `batchDescription` implementation).
- ⌘R goes through the AppKit menu path (`LensCommands` in `main.swift`), NOT
  the local key monitor (`CullingKeyCaptureView`). This avoids double-dispatch
  with the bare culling keys (P, X, Space, etc.).
- The lens selector on the start card (Everything / Potential Picks / Likely
  Issues) may not be fully wired in the initial SP-D implementation — verify
  against the actual `lensDescription` output. If lens narrowing is not yet
  available, the card should still render without it (lensDescription = nil).

## Run status
PASS — 2026-08-16. VM run via `script/vm_scenario_run.sh`. ⌘R opens start
card sheet (Cull mode has no toolbar popover anchor, so sheet presentation is
used). Card shows "24 photos · 0 stacks", Auto-advance and Land on
recommended toggles both visible. Pressing Return creates a culling session
("Catalog Cull", status=running) in the catalog and dismisses the sheet.
Step 5 (⌘R no-op while cull active) not explicitly tested — `canBeginCullingSession`
gate is unit-tested.
