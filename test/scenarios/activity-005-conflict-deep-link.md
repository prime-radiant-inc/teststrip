# activity-005-conflict-deep-link: clicking a conflict row deep-links into Library; ⌘⇧0 only toggles the popover

**What this covers**: `AppModel.revealConflicts(_:)` (`AppModel.swift:2531-2547`),
invoked when a conflict row in the Activity popover is clicked
(`ActivityCenterView.selectConflict`, `ActivityCenterView.swift:315-321`) —
the exact sequence of state mutations it performs to land the user on the
conflicted asset. Also `⌘⇧0`, which is **not** wired to `revealConflicts` —
confirmed by source, it only toggles the Activity popover's presentation.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`. Switch to the Cull or People
   workspace first (⌘1 or ⌘3) so step 3's workspace-switch assertion is
   meaningful — if you start in Library, the "switches to Library" claim is
   unfalsifiable.
2. Seed an XMP conflict (per `quiet-activity-badge.md` step 3: rate an asset
   via the inspector so a sidecar exists, then edit the sidecar's
   `xmp:Rating` out-of-band to diverge from the catalog) and trigger the
   next sync scan (see Sharp edges — no UI trigger; may need relaunch).
   Note `$SRC`, the conflicted asset's `original_path` / id.
3. Open the Activity popover, click the conflict row. Per
   `revealConflicts` (`AppModel.swift:2531-2547`), assert **all** of the
   following in order:
   - `selectedView == .grid` and `selectedWorkspace == .library` — the app
     switched to the Library grid regardless of which workspace/subview was
     active before the click.
   - `selectedAssetID == $SRC`'s asset id.
   - Any active Library query/filter text field is empty
     (`clearLibraryQueryFilters()`, `AppModel.swift:9655-9678`, zeroes
     every filter: search text, keyword/folder/camera/lens text, rating,
     flag, color label, ISO, date range, geo bounds, availability, saved
     evaluation-kind filters, and `metadataSyncConflictFilter` itself before
     re-setting it in the next line below).
   - `metadataSyncConflictFilter == true` — the grid is scoped to
     conflicted assets only (`AppModel.swift:2539`, applied *after*
     `clearLibraryQueryFilters()` clears it, so the net effect is "only this
     filter active").
   - The grid's batch selection contains exactly `$SRC` (and every id passed
     to `revealConflicts`, which is `[conflict.assetID]` — a single id from
     the popover row click): `clearBatchSelection()` then
     `setBatchSelection(assetID, isSelected: true)` for each
     (`AppModel.swift:2541-2543`). With a single conflicted asset this reads
     as an ordinary single selection, not multi-select "batch mode" — the
     card should not assert a batch-mode UI affordance appears, since one
     selected id doesn't visually differ from a normal single selection.
   - `inspectorTab == .info` and `isInspectorVisible == true`
     (`AppModel.swift:2545-2546`) — the Info tab of the inspector is open
     and pinned, showing `$SRC`'s metadata/conflict detail.
4. Cross-check the grid's rendered selection against the ground truth: the
   selected cell's AX state should match `$SRC`'s filename, and the
   inspector pane (if visible in the AX tree) should show `$SRC`'s metadata.

### ⌘⇧0 — popover toggle only, not a deep-link shortcut
5. With the Activity popover closed and no conflict selected, press `⌘⇧0`.
   Confirmed by source (`main.swift:524-536`, `ActivityCommands`): the
   shortcut is bound to `model.isActivityCenterPresented.toggle()` only — it
   does **not** call `revealConflicts`, does not switch workspace, and does
   not clear or set any Library filter state. Assert:
   - The popover opens (or closes, if it was open) — AX: the popover's
     container becomes visible/hidden.
   - `selectedWorkspace`, `selectedAssetID`, `metadataSyncConflictFilter`,
     and the batch selection are all **unchanged** from their pre-shortcut
     values — press ⌘⇧0 from a non-Library workspace with an existing
     selection and confirm none of that state moved.

## Expected
- Step 3: **Fails if** any bullet doesn't hold — most importantly, if the
  workspace doesn't switch to Library, if `metadataSyncConflictFilter`
  isn't the *only* active filter afterward (stale filters from before the
  click leaking through), or if the inspector doesn't open to Info.
- Step 5: **Fails if** ⌘⇧0 does anything beyond toggling popover visibility
  — in particular, if it turns out to also invoke `revealConflicts` or
  mutate filter/selection state, the original task assumption ("likely
  jumps to Activity or clears deep-link state") would be correct instead of
  the current source reading, and this card's Step 5 assertion is wrong;
  re-confirm against `main.swift` before trusting either.

## Cleanup
```bash
rm -f "$SRC.xmp"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **No UI-reachable trigger exists for the metadata-sync-conflict rescan**
  (`docs/product/focused-workspaces-followups.md`, "Known test-fixture
  gaps") — step 2's "trigger the next sync scan" may require an app
  relaunch against the mutated catalog rather than an in-session action.
  This is the same gap `quiet-activity-badge.md` and `activity-icon-states.md`
  are already PARTIAL for.
- `revealConflicts` takes `[AssetID]`, plural, but `selectConflict` in
  `ActivityCenterView` only ever calls it with a single-element array (one
  row = one asset) — there is currently no UI path that exercises the
  multi-id batch-selection branch of `revealConflicts` with more than one
  id. If a future UI adds multi-select-conflict-rows, this card's step 3
  batch-selection assertion should be extended to cover N > 1.
- The function name is `revealConflicts`, confirmed exact
  (`AppModel.swift:2531`) — the task brief's "or equivalent" hedge wasn't
  needed; this is the real name.

## Run status
NOT RUN — no host GUI available in this session. All wiring in this card is
confirmed by direct source citation (`Sources/TeststripApp/AppModel.swift:2531-2547`,
`Sources/TeststripApp/ActivityCenterView.swift:315-321`,
`Sources/TeststripApp/main.swift:524-536`), not by driving the UI or
querying a live catalog beyond the shared XMP-conflict-seeding technique
already ground-truthed in `quiet-activity-badge.md`. Needs a human-present
or console-unlocked re-run to drive the AX steps and confirm rendered
selection/inspector state matches the model-level assertions above.
