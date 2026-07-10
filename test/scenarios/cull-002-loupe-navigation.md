# cull-002-loupe-navigation: Left/Right/Space, Up/Down stack nav, ⌥←/⌥→, and end-of-scope pagination in the Cull loupe

**What this covers**: as a photographer working through a shoot in the Cull
loupe, I want Left/Right (and Space) to step through the active scope,
Up/Down to jump between stacks, the ⌥←/⌥→ alternate to work identically, and
— once I reach the end of the `.all` scope with more assets on disk than are
loaded — the loupe to page in more rather than dead-ending. Covers:
- Left/Right/Space navigation and toast-clearing:
  `Sources/TeststripApp/AppModel.swift:5416-5421` (`.previousPhoto`/
  `.nextPhoto` both call `clearCullingMetadataDecisionFeedback()` before
  moving), `selectNextAssetForCulling`/`selectPreviousAssetForCulling` at
  `:5585-5629` and `:5897-5919`.
- Up/Down stack nav: `.previousStack`/`.nextStack` at `AppModel.swift:5422-
  5427`, resolving through `selectNextStackForCulling`/
  `selectPreviousStackForCulling` (`:5741-5753`), which prefer a *persisted*
  stack-cull session (`selectPersistedCullingStack`) and fall back to the
  in-memory `AssetStackBuilder`-derived `cullingStacks()` (`:5643-5645`).
- ⌥←/⌥→: handled directly inside the key monitor, not through
  `CullingShortcut.init(key:)` — `Sources/TeststripApp/
  CullingKeyCaptureView.swift:113-126`. The menu-item entries exist only for
  the `?` key-map overlay's discoverability and are marked
  `isMonitorOnly: true` (`AppModel.swift:488-489`) specifically so `Commands`
  doesn't *also* bind ⌥←/⌥→ — a bare `.keyboardShortcut` binding alongside the
  key monitor would double-fire the same physical keystroke once from AppKit's
  local monitor and once from SwiftUI's `Commands` responder chain.
- End-of-`.all`-scope pagination: `selectNextAssetForCulling`'s pagination
  branch at `AppModel.swift:5595-5603` (`cullScope == .all, index ==
  assets.count - 1, hasMoreAssets` triggers `loadMoreAssets()`,
  `:8777`); the mirror-image `loadPreviousAssets()` branch for Left at
  `:5907-5915`.

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
3. Press `Right`. Assert the displayed filename changes to the next asset in
   catalog order and any decision toast (if one was showing from a prior
   step) is cleared — `applyCullingShortcut(.nextPhoto)` calls
   `clearCullingMetadataDecisionFeedback()` unconditionally before moving
   (`AppModel.swift:5419-5421`).
4. Press `Left`. Assert it returns to the asset from step 2.
5. Press `Space`. Per `CullingShortcut.init(event:)`
   (`CullingKeyCaptureView.swift:157-158`), Space maps to `.nextPhoto` too —
   assert the same forward step as `Right` (not an auto-advance-after-
   decision — no flag/rating was set this step).
6. **Stack nav caveat**: `--smoke`'s seeder assigns `capturedAt` 15 minutes
   apart per asset (`Sources/TeststripBench/SmokeCatalogSeeder.swift:105`,
   `1_704_067_200 + index*900`), far outside `AssetStackBuilder`'s 2-second
   `maximumCaptureGap`, and there is no persisted `work-stack-` session in a
   fresh `--smoke` catalog (per README). So `cullingStacks()` partitions all
   24 assets into 24 **singleton** stacks — and stack *navigation* is a
   **designed no-op** on an all-singleton catalog: `selectCullingStack`
   builds its jump list from `cullingStacks()`, which filters to multi-frame
   stacks only (`AppModel.swift`, `allCullingStacks(...).filter {
   $0.assetIDs.count > 1 }`), and guard-returns when that list is empty. The
   filmstrip's "stack N / M" text counts *all* stacks including singletons
   (`allCullingStacks`), so the position text and the nav keys intentionally
   disagree on `--smoke`. Press `Down` and assert the selection does NOT
   move; press `Up` and assert the same. (Verified live 2026-07-10: both
   keys dispatch `.nextStack`/`.previousStack` to the monitor — traced to
   `applyCullingShortcut` — and the no-op is the multi-frame filter, not a
   dispatch failure.) This does *not* exercise genuine multi-frame
   stack-to-stack jumping — see Sharp edges.
7. Press ⌥→ (Option-Right-Arrow). Assert it behaves identically to step 6's
   `Down` (both resolve to `.nextStack`) — same designed no-op here. This
   confirms the monitor-only alternate actually fires; it has no Commands-
   menu binding to verify against (that's the point of `isMonitorOnly`).
   Press ⌥← to return.
8. **Pagination**: find the last loaded asset in `.all` scope. Query the
   loaded count so far and compare to the catalog total:
   ```bash
   TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")   # expect 24 for --smoke
   ```
   `--smoke` only seeds 24 assets and the Cull loupe's initial page may
   already cover all 24 (`hasMoreAssets` false) — if so, this step cannot be
   exercised against `--smoke` as seeded; note this and either (a) confirm
   `hasMoreAssets` is false and the grid simply stops advancing at the last
   asset without erroring, or (b) if a larger seed variant is available,
   rerun against it. Navigate to the last asset (repeated `Right`/`⌘⇧]` or
   jump via grid). Press `Right` once more:
   - If `hasMoreAssets` was true: assert `loadMoreAssets()` fired — the
     loaded asset count grows and the selection lands on the newly-loaded
     next asset.
   - If `hasMoreAssets` was false: assert the selection simply stays on the
     last asset (no crash, no wraparound, no error alert).

## Expected
- Steps 3-5: filename changes forward/backward/forward exactly as Left/
  Right/Space dictate; toast clears on every navigation keystroke. **Fails
  if** the toast survives a navigation press (stale decision feedback shown
  next to a different photo), or if Space does something other than advance.
- Step 6-7: Up/Down and ⌥←/⌥→ leave the selection unchanged in `--smoke`'s
  all-singleton-stacks case (designed no-op — stack nav only jumps between
  multi-frame stacks). **Fails if** they move the selection at all on an
  all-singleton catalog, or if on a catalog with multi-frame stacks they
  no-op or skip stacks.
- Step 8: either pagination measurably grows the loaded set and advances
  past the pre-pagination end, or (if `--smoke` has no `hasMoreAssets` at
  all) the loupe holds steady at the last frame without error. **Fails if**
  pressing `Right` at the end throws, shows an error alert, or silently
  wraps to the first asset.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **`--smoke` cannot exercise genuine multi-frame stack-to-stack nav.** Every
  asset lands in its own singleton stack (see step 6). To test Up/Down
  jumping *across* a real multi-frame stack, this card would need either a
  seed variant with EXIF `capturedAt` values within 2s of each other in the
  same folder, or a persisted `work-stack-` session (see
  `cull-004-stack-promote-return.md`'s investigation into
  `beginStackCullingFromLatestImportCompletion`). Neither exists today for
  `--smoke`; documenting the gap here rather than asserting behavior nobody
  can currently trigger with the standard fixture.
- **Pagination may be untestable against `--smoke`'s 24-asset seed** if the
  Cull loupe's initial working set already loads all 24 (`hasMoreAssets ==
  false` from the start). Confirm this empirically in the live run and note
  the actual outcome — don't force a false pass by asserting the no-op branch
  when a real page boundary was reachable, or vice versa.
- `isMonitorOnly` on `CullingCommandMenuItem` is purely about menu-vs-monitor
  duplication (see What this covers); it says nothing about whether the
  shortcut is "safe" or "advanced" — don't over-read the name.

## Run status
UNRUN — SQL not yet dry-run against a live catalog; needs human-present
execution per test/scenarios/README.md.
