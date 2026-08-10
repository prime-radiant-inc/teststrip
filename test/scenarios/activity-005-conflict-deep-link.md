# activity-005-conflict-deep-link: clicking a conflict row deep-links into the Grid lens; ⌘⇧0 only toggles the popover

**What this covers**: `AppModel.revealConflicts(_:)` (`AppModel.swift:2961-2982`),
invoked when a conflict row in the Activity popover is clicked
(`ActivityCenterView.selectConflict`, `ActivityCenterView.swift:262-267`) —
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
   lens first (⌘1 or ⌘6) so step 3's lens-switch assertion is meaningful —
   if you start in the Grid lens, the "switches to Grid" claim is
   unfalsifiable.
2. Seed an XMP conflict (per `quiet-activity-badge.md` step 3: rate an asset
   via the inspector so a sidecar exists, then edit the sidecar's
   `xmp:Rating` out-of-band to diverge from the catalog) and trigger the
   next sync scan (see Sharp edges — no UI trigger; may need relaunch).
   Note `$SRC`, the conflicted asset's `original_path` / id.
3. Open the Activity popover, click the conflict row. Per
   `revealConflicts` (`AppModel.swift:2961-2982`), assert **all** of the
   following in order:
   - `selectedView == .grid` and `selectedSource.kind == .metadataSyncConflicts`
     — the app switched to the Grid lens and to the Metadata Sync Conflicts
     source regardless of which lens/source was active before the click. (A
     deep link with an explicit destination, not a plain source selection —
     the source comment at `AppModel.swift:2963-2965` states this lands in
     Grid "regardless of the current lens.")
   - `selectedAssetID == $SRC`'s asset id.
   - Any active Library query/filter text field is empty
     (`clearLibraryQueryFilters()`, `AppModel.swift:11747-11770`, zeroes
     every filter: search text, keyword/folder/camera/lens text, rating,
     flag, color label, ISO, date range, geo bounds, availability, saved
     evaluation-kind filters, and `metadataSyncConflictFilter` itself before
     re-setting it in the next line below).
   - `metadataSyncConflictFilter == true` — the grid is scoped to
     conflicted assets only (`AppModel.swift:2971`, applied *after*
     `clearLibraryQueryFilters()` clears it, so the net effect is "only this
     filter active").
   - The grid's batch selection contains exactly `$SRC` (and every id passed
     to `revealConflicts`, which is `[conflict.assetID]` — a single id from
     the popover row click): `clearBatchSelection()` then
     `setBatchSelection(assetID, isSelected: true)` for each
     (`AppModel.swift:2973-2976`). With a single conflicted asset this reads
     as an ordinary single selection, not multi-select "batch mode" — the
     card should not assert a batch-mode UI affordance appears, since one
     selected id doesn't visually differ from a normal single selection.
   - `isInspectorVisible == true` and the inspector is scrolled to the Info
     section (`scrollInspector(to: .info)`, `AppModel.swift:2980-2981`) — the
     stacked-sections inspector (see `inspect-001-toggle-tabs.md`) renders
     Info/Describe/AI/People all at once now, so this is a scroll target, not
     a tab switch; the Info section shows `$SRC`'s metadata/conflict detail.
4. Cross-check the grid's rendered selection against the ground truth: the
   selected cell's AX state should match `$SRC`'s filename, and the
   inspector pane (if visible in the AX tree) should show `$SRC`'s metadata.

### ⌘⇧0 — popover toggle only, not a deep-link shortcut
5. With the Activity popover closed and no conflict selected, press `⌘⇧0`.
   Confirmed by source (`main.swift:574-585`, `ActivityCommands`): the
   shortcut is bound to `model.isActivityCenterPresented.toggle()` only — it
   does **not** call `revealConflicts`, does not switch lens/source, and does
   not clear or set any Library filter state. Assert:
   - The popover opens (or closes, if it was open) — AX: the popover's
     container becomes visible/hidden.
   - `selectedView`, `selectedSource`, `selectedAssetID`,
     `metadataSyncConflictFilter`, and the batch selection are all
     **unchanged** from their pre-shortcut values — press ⌘⇧0 from a
     non-Grid lens with an existing selection and confirm none of that state
     moved.

## Expected
- Step 3: **Fails if** any bullet doesn't hold — most importantly, if the
  lens doesn't switch to Grid, if `metadataSyncConflictFilter`
  isn't the *only* active filter afterward (stale filters from before the
  click leaking through), or if the inspector doesn't scroll to Info.
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
  (`AppModel.swift:2961`) — the task brief's "or equivalent" hedge wasn't
  needed; this is the real name.

## Run status
NOT RUN — no host GUI available in this session. All wiring in this card is
confirmed by direct source citation (`Sources/TeststripApp/AppModel.swift:2963-2980`,
`Sources/TeststripApp/ActivityCenterView.swift:262-267`,
`Sources/TeststripApp/main.swift:572-584`), not by driving the UI or
querying a live catalog beyond the shared XMP-conflict-seeding technique
already ground-truthed in `quiet-activity-badge.md`. Needs a human-present
or console-unlocked re-run to drive the AX steps and confirm rendered
selection/inspector state matches the model-level assertions above.

**Reconciled 2026-08-09 (Task 13, unified-shell sweep)**: this card's every
assertion was built on the deleted `Workspace` enum and `selectedWorkspace`
property — `revealConflicts` no longer switches a workspace at all; it sets
`selectedView = .grid` and `selectedSource = .metadataSyncConflicts`
(`AppModel.swift:2961-2982`, re-read and re-cited line-for-line above,
correcting drift from the old `:2531-2547` range) regardless of which lens
was active. The stale ⌘3 preamble (People was ⌘3 under the old three-case
`Workspace`; People is ⌘6 under `LibraryLens`) is fixed. `inspectorTab ==
.info` doesn't exist any more either — Task 6/9's stacked-sections inspector
(`inspect-001-toggle-tabs.md`) replaced tab-switching with
`scrollInspector(to:)`, so Step 3's last bullet now asserts a scroll target,
not a selected tab. `ActivityCommands`/⌘⇧0's citation (`main.swift:524-536`
→ `:572-583`) and `selectConflict`'s (`ActivityCenterView.swift:315-321` →
`:262-267`) were also re-verified and corrected — both had drifted.
Supersedes prior status: the NOT RUN note above cites a `selectedWorkspace`
property and an `inspectorTab` tab-switch that no longer exist in source at
all — it is not valid evidence for anything about this card's current
assertions, only for the fact that this card has never been driven live.
Needs a fresh VM run.
