# cull-002-loupe-navigation: Left/Right stack nav, Up/Down within-stack nav, Space, and end-of-scope pagination in the Cull loupe

**Reconciled 2026-07-13 (cull-stack-rail branch)**: the arrow mapping this
card exercises was remapped by the vertical current-stack rail work.
**Previously** Left/Right stepped the linear scope and Up/Down jumped
between stacks, with an ⌥←/⌥→ monitor-only alternate for the stack jump.
**Now** Up/Down step *within* the current stack and Left/Right jump
*between* stacks (landing on the new stack's AI-recommended frame); the
⌥←/⌥→ mechanism has been **deleted outright** — Option-held arrows are no
longer decoded into any shortcut at all. This revision rewrites every
stack-nav assertion below to the new mapping and removes the ⌥-arrow legs
entirely; nothing here should be read as covering the old mapping. See
`cull-021-stack-rail-nav.md` for the vertical rail's own dedicated coverage
of within/across-stack nav, recommended-frame landing, and the rail's
visual chips — this card stays focused on the loupe's base Left/Right/Space
navigation plus the (now within-stack) Up/Down and end-of-scope pagination.

**What this covers**: as a photographer working through a shoot in the Cull
loupe, I want Space to step linearly through the active scope, Left/Right
to jump between stacks (landing on the next/previous stack's
AI-recommended frame), Up/Down to step within the currently-selected
stack, and — once Space reaches the end of the `.all` scope with more
assets on disk than are loaded — the loupe to page in more rather than
dead-ending. Covers:
- **Space (linear advance) and toast-clearing**:
  `Sources/TeststripApp/AppModel.swift:5853-5855` (`.nextPhoto` calls
  `clearCullingMetadataDecisionFeedback()` before
  `selectNextAssetForCulling()`, `:6085-6107`, pagination branch at
  `:6095-6103` — unchanged by this branch's remap). Space
  (`CullingKeyCaptureView.swift:158-159`) is the *only* Cull-loupe key that
  still reaches `.nextPhoto`. `.previousPhoto`
  (`AppModel.swift:5850-5852`, → `selectPreviousAssetForCulling`,
  `:6449-6471`, pagination branch at `:6459-6467`) is **not** bound to any
  key in the Cull loupe any more — it is dispatched only by the Library
  loupe's chevron buttons (`LibraryGridView.swift:4683-4691`
  `CullingNavDirection.shortcut`, wired into `libraryLoupeNavBar`,
  `:3976-3982`, a different, non-culling view). Left no longer reverses
  Space's advance — see the next bullet for what Left/Right dispatch now.
- **Remapped arrow dispatch** (this branch): `CullingShortcut.init(event:)`
  now maps `leftArrow`/`rightArrow` → `.previousStack`/`.nextStack` and
  `upArrow`/`downArrow` → `.previousCandidateInStack`/`.nextCandidateInStack`
  (`Sources/TeststripApp/CullingKeyCaptureView.swift:149-157`; the static
  key-based mapping used for the `?`/menu advertisement agrees,
  `AppModel.swift:238-245`). Dispatch: `applyCullingShortcut`,
  `AppModel.swift:5856-5867` — `.previousStack`/`.nextStack` resolve through
  `selectPreviousStackForCulling`/`selectNextStackForCulling`
  (`:6258-6270`, preferring a persisted stack-cull session
  (`selectPersistedCullingStack`) and falling back to the in-memory
  `AssetStackBuilder`-derived `cullingStacks()`, landing on
  `recommendedStackLandingAssetID` — the new stack's ranked-recommended
  frame, or its first frame if nothing is ranked, `:6442-6447`).
  `.previousCandidateInStack`/`.nextCandidateInStack` resolve through
  `selectPreviousCandidateInStack`/`selectNextCandidateInStack`
  (`:6276-6295`, moving within `selectedCullingStackScope.assetIDs`, no
  wrap).
- **⌥←/⌥→ removed, not merely relabeled**: there is no Option-arrow branch
  left anywhere in the key-capture path. `CullingShortcut.init(event:)`
  guards `relevantModifiers.isEmpty` before decoding anything
  (`CullingKeyCaptureView.swift:128-129`,
  `event.modifierFlags.intersection([.command, .control, .option])`) — with
  Option held this is non-empty, so the initializer returns `nil` and
  `handleLocalKeyDown` passes the raw event straight through unhandled
  (`:94-96`, `return event`). There is also no `isMonitorOnly` menu entry
  for it any more: `CullingCommandMenuPresentation.sections`'s Navigation
  section (`AppModel.swift:511-516`) lists only "Previous/Next Frame in
  Stack" (↑/↓) and "Previous/Next Stack" (←/→) — no Option-arrow row, no
  `isMonitorOnly` flag on any entry (see `cull-009-keymap-overlay.md`'s
  parallel reconciliation).
- End-of-`.all`-scope pagination: `selectNextAssetForCulling`'s pagination
  branch at `AppModel.swift:6095-6103` (`cullScope == .all, index ==
  assets.count - 1, hasMoreAssets` triggers `loadMoreAssets()`, `:9612`) —
  reachable via `Space` now, not `Right` (`Right` dispatches `.nextStack`,
  not `.nextPhoto`; see the Space bullet above). The mirror-image
  `loadPreviousAssets()` (`:9634`) branch inside
  `selectPreviousAssetForCulling` (`:6459-6467`) is, like `.previousPhoto`
  itself, unreachable from any Cull-loupe key post-remap — step 7 below
  only exercises the forward/Space leg.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Fallback: `script/vm_scenario_run.sh setup && sync smoke && launch smoke`,
then `vm_scenario_run.sh ax ...` / `sql smoke ...` in place of the direct
calls below.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull, landing in
   the Cull loupe (`.loupe`).
2. Record the initially-selected asset id (`script/ax_drive.sh find --role
   AXStaticText --contains "frame"` for the filmstrip position text, or read
   `selectedAssetID` indirectly via the loupe's filename label). Cycle scope
   with `S` until it reads "All" (`script/ax_drive.sh find --contains
   "All"`), so navigation isn't scope-filtered for the rest of this card —
   note `--smoke`'s baseline flags mean Unrated/Picks/Rejects are all
   non-empty, so starting from `All` avoids scope-boundary surprises in
   steps 3-4.
3. **Space — linear advance.** Press `Space`. Assert the displayed filename
   changes to the next asset in catalog order, and any decision toast (if
   one was showing from a prior step) is cleared —
   `applyCullingShortcut(.nextPhoto)` calls
   `clearCullingMetadataDecisionFeedback()` unconditionally before moving
   (`AppModel.swift:5853-5855`). This is the linear-scope probe for this
   card now; Left/Right no longer perform this move (see step 4).
4. **Right — stack nav (remapped).** Press `Right`. Per
   `CullingShortcut.init(event:)` (`CullingKeyCaptureView.swift:152-153`),
   `Right` dispatches `.nextStack` → `selectNextStackForCulling()`
   (`AppModel.swift:5859-5861`, `:6258-6262`), which on a catalog with real
   multi-frame stacks lands on the next stack's
   `recommendedStackLandingAssetID` (`:6442-6447`: the ranked winner, or
   the stack's first frame if nothing is ranked). **On `--smoke` this is a
   designed no-op**: the seeder assigns `capturedAt` 900 seconds (15
   minutes) apart per asset
   (`Sources/TeststripBench/SmokeCatalogSeeder.swift:136-137`,
   `1_704_067_200 + index*900`), far outside `AssetStackBuilder`'s 2-second
   `maximumCaptureGap`, and there is no persisted `work-stack-` session in a
   fresh `--smoke` catalog (per README) — so `cullingStacks()` partitions
   all 24 assets into 24 **singleton** stacks
   (`.filter { $0.assetIDs.count > 1 }`, `AppModel.swift:6143-6145`) and
   `selectCullingStack(_:)`'s `indexedStacks` jump list is empty, so its
   guard returns before moving anything (`:6398-6407`). The toast still
   clears — `clearCullingMetadataDecisionFeedback()` runs unconditionally
   before the guarded call. Assert: the selected asset does **not** change,
   no crash/error alert, and the toast (if any) clears. Genuine
   stack-to-stack landing on a real multi-frame fixture is
   `cull-021-stack-rail-nav.md`'s job (`burst` seed variant, its steps
   10-11) — don't duplicate that coverage here.
5. **Left — mirrors Right.** Press `Left`. Per `CullingShortcut.init(event:)`
   (`CullingKeyCaptureView.swift:150-151`), `Left` dispatches
   `.previousStack` → `selectPreviousStackForCulling()`
   (`AppModel.swift:5856-5858`, `:6265-6269`) — assert the identical
   no-op/toast-clear behavior as step 4, for the same singleton-stack
   reason.
6. **Up/Down — within-stack nav (remapped), same singleton caveat.** Press
   `Down`, then `Up`. For the same reason established in steps 4-5
   (`--smoke`'s all-singleton catalog), both are a **designed no-op** via a
   different code path: `selectedCullingStackScope` returns `nil` when the
   selected asset's stack has only one member (`cullingStacks()` filters to
   `$0.assetIDs.count > 1`, `AppModel.swift:6143-6145`), so
   `moveSelectionWithinCurrentCullingStack` (`:6284-6295`) guard-fails at
   its first `guard` (`:6285-6289`) and the selection does not move. Toast
   clearing still applies (`:5862-5867`). This does *not* exercise genuine
   multi-frame within-stack candidate movement or stack-to-stack
   landing-on-recommended behavior — see Sharp edges and
   `cull-021-stack-rail-nav.md` for that coverage on the `burst` fixture.
7. **Pagination**: find the last loaded asset in `.all` scope. Query the
   loaded count so far and compare to the catalog total:
   ```bash
   TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")   # expect 24 for --smoke
   ```
   `--smoke` only seeds 24 assets and the Cull loupe's initial page may
   already cover all 24 (`hasMoreAssets` false) — if so, this step cannot be
   exercised against `--smoke` as seeded; note this and either (a) confirm
   `hasMoreAssets` is false and the grid simply stops advancing at the last
   asset without erroring, or (b) if a larger seed variant is available,
   rerun against it. Navigate to the last asset (repeated `Space` or
   jump via grid). Press `Space` once more:
   - If `hasMoreAssets` was true: assert `loadMoreAssets()` fired — the
     loaded asset count grows and the selection lands on the newly-loaded
     next asset.
   - If `hasMoreAssets` was false: assert the selection simply stays on the
     last asset (no crash, no wraparound, no error alert).
8. **Non-destructive invariant (persona-8 defect)**: after all the pure
   navigation above — arrows, Space, stack keys, pagination, with NO
   rating/flag/keyword/caption gesture in this card — assert that **zero**
   `.xmp` sidecars exist next to the originals and no metadata write was
   queued:
   ```bash
   SRC_DIR=$(sqlite3 "$DB" "SELECT original_path FROM assets LIMIT 1;" | xargs dirname)
   find "$SRC_DIR" -name '*.xmp' | wc -l    # must be 0
   sqlite3 "$DB" "SELECT count(*) FROM metadata_sync_state WHERE state='pending';"  # must be 0
   ```
   (Adjust table/column names against `CatalogMigrations.swift` before
   running; do not weaken to "few" — the count is exactly 0.)

## Expected
- Step 8: browsing writes nothing — zero sidecars, zero pending metadata
  syncs after pure navigation. **Fails if** even one `.xmp` appears for a
  merely-visited photo (the Rating=0 sidecar-spray defect).
- Step 3: the filename advances forward exactly as `Space` (`.nextPhoto`)
  dictates, and any decision toast clears. **Fails if** the toast survives
  the Space press, or Space does something other than advance to the next
  asset in catalog order.
- Steps 4-5: on `--smoke`'s all-singleton catalog, `Right`/`Left` leave the
  selection unchanged (empty stack-jump list — designed no-op) while still
  clearing any decision toast. **Fails if** Right/Left move the selection
  at all on an all-singleton catalog, or on a catalog with real
  multi-frame stacks (see `cull-021-stack-rail-nav.md`) fail to land on
  the documented recommended-or-first frame of the neighboring stack.
- Step 6: Up/Down leave the selection unchanged in `--smoke`'s
  all-singleton-stacks case (designed no-op — within-stack nav has nowhere
  to go on a singleton), for the same underlying reason as steps 4-5.
  **Fails if** Up/Down move the selection at all on an all-singleton
  catalog, or if on a catalog with real multi-frame stacks (see
  `cull-021-stack-rail-nav.md`) Up/Down no-op or skip frames.
- Step 7: either pagination measurably grows the loaded set and advances
  past the pre-pagination end, or (if `--smoke` has no `hasMoreAssets` at
  all) the loupe holds steady at the last frame without error. **Fails if**
  pressing `Space` at the end throws, shows an error alert, or silently
  wraps to the first asset.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **`--smoke` cannot exercise genuine multi-frame within/across-stack nav.**
  Every asset lands in its own singleton stack (see steps 4-6). Real
  coverage of ↑/↓-within-a-stack and ←/→-landing-on-the-recommended-frame
  now lives in `cull-021-stack-rail-nav.md` against the `burst` seed
  variant — don't duplicate that coverage here; this card only proves the
  all-singleton no-op case and the ordinary linear Space advance.
- **Pagination may be untestable against `--smoke`'s 24-asset seed** if the
  Cull loupe's initial working set already loads all 24 (`hasMoreAssets ==
  false` from the start). Confirm this empirically in the live run and note
  the actual outcome — don't force a false pass by asserting the no-op branch
  when a real page boundary was reachable, or vice versa.
- **The ⌥←/⌥→ mechanism this card used to test no longer exists.** Do not
  resurrect an `isMonitorOnly`/Option-arrow assertion here; the whole
  mechanism (menu entries and event handling alike) was deleted by the
  cull-stack-rail branch, not merely renamed.

## Run status
NOT RUN AGAINST THE NEW MAPPING — reconciled 2026-07-13 to the branch's
remapped arrows (↑/↓ within-stack, ←/→ across-stack landing on the
recommended frame, ⌥←/⌥→ deleted); source-cited against the current working
tree. The LEDGER's prior "Verified" status for this card predates the
remap and covers the *old* mapping only — treat this revision as needing a
fresh human-present/VM execution per `test/scenarios/README.md` before it
can be called Verified again.
