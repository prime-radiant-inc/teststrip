# cull-027-blaze-through-prefetch: Landing on a burst warms its stack and the next stops without visiting them; a render-gated Return arms the stack commit and fires the moment the preview lands

**What this covers**: two related pieces of "blaze-through" behavior for a
photographer culling a fast burst. (a) Landing on any frame of a multi-frame
stack in the cull loupe silently warms `.large` previews for the rest of
that stack plus the landing frame of each of the next three stops and the
previous stop — at back-of-queue priority, so it never preempts what the
user is actually looking at — so arrow-key advance almost never lands on a
soft/placeholder frame. (b) If the staged frame's `.large` preview genuinely
isn't rendered yet, Return no longer just complains and drops the gesture:
it **arms** the stack commit (toast: "Rendering full preview… will keep
when ready") and fires the exact same pick/reject decision automatically
the instant the render lands — no second keypress required. Any other input
before it fires — an arrow key, another flag/rating shortcut, a rail
action — disarms it: the commit can never land against a frame the user has
since moved past.

Source (re-verified against the working tree on this branch at HEAD
`11cdf360`, 2026-07-30; every symbol below was re-grepped fresh, not carried
over from any older card):
- **The planner**, `CullPrefetchPlanner.warmAssetIDs`
  (`Sources/TeststripApp/CullPrefetchPlanner.swift:9-36`): a pure function
  over the stop sequence. Given the staged asset's stop, it lists — in
  priority order — the staged asset itself, then its stack-mates forward
  from the staged frame then backward (`:18-23`), then the landing asset
  (`recommendedStackLandingAssetID`) of each of the next `nextStackCount`
  stops (default `3`, `:12`, `:24-30`), then the landing asset of exactly
  the one previous stop (`:31-33`), deduped (`:34-35`). No caller overrides
  `nextStackCount` (`AppModel.swift` calls `warmAssetIDs` with only `stops:`/
  `stagedAssetID:`/`landingAssetID:`, `:9444-9448`), so the live default is
  always 3. `CullPrefetchPlannerTests.swift` covers the ordering, first/
  last-stop edge cases, and nil-landing/dedup handling directly against this
  pure function — this card proves the wiring live, not those cases again.
- **The driver**, `AppModel.requestVisibleCullPreview(assetID:)`
  (`AppModel.swift:9437-9440`): the cull loupe's per-frame request, wired at
  `LibraryGridView.swift:3894-3900` — only when `presentation.showsCullChrome`
  (the plain Library loupe still uses the old ±1 deck-order
  `requestVisibleLoupePreview`). It requests the visible frame's own preview
  at `.front` priority first (`requestVisibleLoupeAssetPreview`, unchanged —
  for `.loupe(isVisible: true, requestedFullResolution: false)` that request
  is level `.large`, `Sources/TeststripCore/Preview/PreviewScheduler.swift:35-40`),
  then calls `refreshCullPrefetchWindow(around:)`
  (`AppModel.swift:9442-9477`) to turn the planner's warm set into gated
  `.back`-priority requests: skips an asset that already has a cached
  `.large` (`:9457`), is unavailable (`:9458-9459`), or has exhausted its
  automatic render attempts (`:9460`); otherwise
  `requestPreview(assetID:level:.large, placement: .back)` (`:9469`). A
  window slide cancels only the *undispatched* stragglers this same driver
  itself enqueued (`cullPrefetchItemIDs`, `:9450-9455`) — never an item some
  other path is tracking, including the staged frame's own front-placed
  request (`:9462-9468`, the review-round-1 fix in `20a72ce1`); anything
  already `.running` is left to finish. `CullPrefetchDriverTests.swift`
  covers the gating/dedup/cancel-scoping directly.
- **The render gate now arms instead of just complaining**,
  `promoteCurrentFrameAndRejectSiblings` (`AppModel.swift:6387-6443`): the
  guard at `:6410` (`previewURL(for: context.selectedAssetID, levels:
  [.large]) != nil`, `previewURL(for:levels:)` at `:14152-14161` — a live
  `FileManager.fileExists` check against the preview-cache file for that
  exact level, no fallback to a smaller cached level) is unchanged, but the
  closed-gate branch now calls `armStackCommit(stagedAssetID:asset:)`
  (`:6411`, function at `:6445-6466`) instead of just setting an
  informational toast and returning. `armStackCommit` re-checks stored
  availability and attempt-exhaustion — the same gates the prefetch driver
  uses (`:6448-6450`) — and if the render can genuinely never succeed it
  refuses to arm and shows `"Preview unavailable — not committed"`
  (`renderUnavailableFeedback`, `:6513-6521`) instead. Otherwise it
  front-places a fresh preview request (`:6461`, jumping whatever queue
  position the frame's own visible request already held) and *only then*
  records `armedStackCommitAssetID = stagedAssetID` (`:6462` — ordered after
  the throwing request per the `11cdf360` review fix, so a request failure
  can never leave a dangling arm with no work item to ever resolve it) and
  shows `"Rendering full preview… will keep when ready"`
  (`armedCommitFeedback`, `:6503-6511`, `isInformational: true` — no
  metadata write yet).
- **The fire hook**, inside the worker-completion handler
  (`AppModel.swift:10453-10458`): every completed preview render calls
  `fireArmedStackCommitIfReady(previewAssetID:)` (`:6472-6491`), a no-op
  unless the completed asset *is* the armed one (`:6473`). If it is, it
  re-checks that the selection hasn't moved, that a Return-capturing cull
  sub-view is still active (`isCullingMenuShortcutActive`, `:2112-2113`,
  delegating to `CullingKeyCaptureGate.isActive`,
  `CullingKeyCaptureView.swift:11-15` — true for `.loupe`/`.compare`/
  `.abCompare`, false for `.cullGrid`; the `11cdf360` review fix replaced a
  hardcoded `selectedView == .loupe` check that silently ate an arm made
  from Compare/A-B), and that the `.large` file genuinely exists now
  (`:6481`) — then disarms and calls `promoteCurrentFrameAndRejectSiblings()`
  again (`:6485-6487`), which this time finds the gate open and commits for
  real with the exact same pick/reject/toast/undo-group semantics
  `cull-023-return-commit-undo.md` already covers in depth (unchanged by
  this branch).
- **Disarm is deliberately promiscuous** — anything other than a repeat
  Return clears `armedStackCommitAssetID`: `selectAssetID` on any target
  other than the armed asset (`:4854-4860` — covers every arrow-key/Space/
  click navigation path, since they all funnel through this one choke
  point); the top of `applyCullingShortcut` for any shortcut that isn't
  `.promoteAndRejectSiblings` itself (`:6632-6639` — a repeat Return
  re-arms the same asset, the specced no-op); and every rail/menu/Inspector
  write path that bypasses `applyCullingShortcut` entirely —
  `applyCompareFlags` (`:6103-6112`, the shared Compare/A-B "keep" write
  path), `keepAllFramesInSelectedCullingStack` (`:6553-6557`),
  `keepTopRankedFramesInSelectedCullingStack` (`:6562-6564`),
  `setFlagForSelectedAsset` (`:7350-7355`), and `setFlagForSelectedAssets`
  (`:7419-7422`). A render *failure* on the armed asset also disarms, inside
  the queue-changed handler (`:4485-4491`), showing the same
  `renderUnavailableFeedback` toast — not exercised live by this card (no
  seed fixture induces a genuine render failure; see Sharp edges).
- **Fixture reality**: `burst` (`seed-burst-catalog` →
  `SmokeCatalogSeeder` with `BurstFixtureLayout`'s capture offsets,
  `Sources/TeststripBench/main.swift:424-437`,
  `Sources/TeststripBench/SmokeCatalogSeeder.swift:33-54`) pre-renders
  **every** level including `.large` for every asset before the app ever
  launches (`renderedLevels`, `SmokeCatalogSeeder.swift:63`) — the same fact
  `cull-023-return-commit-undo.md`'s Sharp edges already established for its
  own (now-stale) Step 7. That means neither the prefetch proof nor the
  armed-commit leg is observable against a freshly-launched `burst` catalog
  as-is: every `.large` file this card cares about already exists at t=0
  regardless of whether the app's own prefetch/render-gate code runs at
  all. This card works around it without a new fixture generator: it
  **deletes the specific `.large` files under test from the live launched
  instance's preview cache**
  (`$RUN_DIR/Teststrip/Previews/<assetID>/large.jpg` —
  `Sources/TeststripCore/Preview/PreviewCache.swift:20-26` for the
  `<root>/<assetID>/<level>.jpg` layout, `Sources/TeststripApp/
  AppCatalog.swift:95-102` for `previewCacheRoot = Teststrip/Previews`;
  asset IDs here (`smoke-N`) are already path-safe so the directory name is
  the literal ID, `Sources/TeststripCore/Preview/PathSafeName.swift:8-19`)
  **before triggering the code path under test**, then observes whether
  they come back. `previewURL(for:levels:)` is a live `FileManager`
  existence check, not a cached DB flag (confirmed above), so this is a
  clean, minimally-invasive way to manufacture a genuinely-missing preview
  against an otherwise fully-rendered fixture. Deleting a file this way
  leaves no trace in any DB table, so `enqueuePendingPreviewGeneration`'s
  generic background scan (`AppModel.swift:9104-9158`, driven by
  `pendingPreviewGenerationItems`, a DB-side pending list) can never pick it
  up independently — the only thing that can notice and re-request a
  deleted file is a live `previewURL(...) == nil` check in the code paths
  this card targets, which keeps the proof clean. Unlike
  `cull-023-return-commit-undo.md`'s Pre-state, this technique never
  touches the shared `burst` seed template — every deletion happens against
  the fresh per-launch copy under `$RUN_DIR`, so no template cleanup is
  needed afterward.
- **Landing frames without evaluation signals**: `burst` never seeds
  evaluation signals (no `EvaluationSignal`/scoring code anywhere in
  `SmokeCatalogSeeder.swift`), so `recommendedStackLandingAssetID`
  (`AppModel.swift:7303-7306`) falls back to `stack.assetIDs.first` for
  every stack — i.e., capture order — matching `cull-023`'s own confirmed
  default landing on `smoke-0`. `BurstFixtureLayout.burstFrameCounts = [3,
  4, 3, 4]`, `singleCount = 4` (`SmokeCatalogSeeder.swift:34-35`): group1 =
  `smoke-0,1,2`; group2 = `smoke-3,4,5,6`; group3 = `smoke-7,8,9`; group4 =
  `smoke-10,11,12,13`; singles = `smoke-14,15,16,17` — the same partition
  `cull-023` documents, landing frames `smoke-0`/`smoke-3`/`smoke-7`/
  `smoke-10` respectively (each stack's first frame). The shared flag
  formula (`index.isMultiple(of: 5) ? .reject : (index.isMultiple(of: 3) ?
  .pick : nil)`, `SmokeCatalogSeeder.swift:147`) gives baseline flags
  `smoke-0=reject` (confirmed), `smoke-1,2=NULL`; `smoke-3=pick,
  smoke-4=NULL, smoke-5=reject, smoke-6=pick` — re-verified live in Step 1
  below, matching `cull-023-return-commit-undo.md`'s own confirmed baseline
  table exactly (same fixture, same formula, unchanged by this branch).
- **Toast mechanics** (unchanged by this branch, re-verified at current
  line numbers): the toast `Text` is `decisionToast`
  (`LibraryGridView.swift:4513`), whose AX title is the literal
  `decisionText` string with no accessibility-label override, and it fades
  after 2 real seconds (`showDecisionToastThenFade`,
  `LibraryGridView.swift:4492-4498`, `Task.sleep(for: .seconds(2))`) — poll
  immediately after each keypress, matching
  `cull-023-return-commit-undo.md`/`cull-022-flow-grammar-walk.md`'s
  identical caution.

## Pre-state
```bash
script/vm_scenario_run.sh sync burst
script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
RUN_DIR=$(script/vm_scenario_run.sh shell "ls -dt ~/teststrip-vm/run/burst-* | head -1")
PREVIEWS="$RUN_DIR/Teststrip/Previews"
echo "$RUN_DIR"
```
This card never patches the shared `burst` seed template (unlike
`cull-023-return-commit-undo.md`) — every file deletion below targets
`$RUN_DIR` (this launch's fresh copy) — so no template cleanup is needed
afterward. The app is still on its default Library grid at this point:
`AppModel.load(catalog:...)` (the factory the real app launch uses)
initializes `selectedView: .grid` (`AppModel.swift:4672`), and
`restoreSessionStateIfAvailable()` (`:11906-11912`) — called right after —
keys its lookup by `catalog.paths.root` (`SessionRestoreStore(...).load()`,
`:11908`), which is this launch's unique `$RUN_DIR`-rooted path and so can
never match a persisted entry from any earlier launch; there is nothing to
restore, and `.grid` stands. Do **not** press ⌘1 yet; the deletions in
Step 2 must land before the cull loupe ever mounts and fires its first
preview request, or there is nothing to observe.

## Steps

1. **Confirm the seed baseline — flags and pre-rendered previews — before
   touching anything.**
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'), catalog_generation
      FROM assets WHERE id IN ('smoke-0','smoke-1','smoke-2','smoke-3','smoke-4','smoke-5','smoke-6')
      ORDER BY id;"
   ```
   Expect `smoke-0|reject|<g0>`, `smoke-1|NULL|<g1>`, `smoke-2|NULL|<g2>`,
   `smoke-3|pick|<g3>`, `smoke-4|NULL|<g4>`, `smoke-5|reject|<g5>`,
   `smoke-6|pick|<g6>` (Source above). Capture those seven
   `catalog_generation` values as named variables — Steps 3, 4, and 6 assert
   against them:
   ```bash
   GEN0_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-0';")
   GEN1_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-1';")
   GEN2_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-2';")
   GEN3_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-3';")
   GEN4_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-4';")
   GEN5_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-5';")
   GEN6_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-6';")
   echo "$GEN0_BEFORE $GEN1_BEFORE $GEN2_BEFORE $GEN3_BEFORE $GEN4_BEFORE $GEN5_BEFORE $GEN6_BEFORE"
   ```

   Confirm the fixture really did pre-render `.large` everywhere (else the
   deletion technique below proves nothing — `smoke-0` is included here
   too, since Step 4 deletes it and a silent no-op `rm -f` against an
   already-missing file would mask that):
   ```bash
   for id in smoke-0 smoke-1 smoke-2 smoke-3 smoke-7 smoke-10 smoke-14; do
     script/vm_scenario_run.sh shell "test -f '$PREVIEWS/$id/large.jpg' && echo PRESENT || echo MISSING"
   done   # expect PRESENT x7
   ```

2. **Delete the prefetch target set, then land on `smoke-0` for the first
   time this session.** Delete every `.large` file the planner is expected
   (and *not* expected) to touch once the stage lands on `smoke-0`:
   ```bash
   script/vm_scenario_run.sh shell "rm -f \
     '$PREVIEWS/smoke-1/large.jpg' '$PREVIEWS/smoke-2/large.jpg' \
     '$PREVIEWS/smoke-3/large.jpg' '$PREVIEWS/smoke-7/large.jpg' \
     '$PREVIEWS/smoke-10/large.jpg' '$PREVIEWS/smoke-14/large.jpg'"
   ```
   `smoke-1`/`smoke-2` are `smoke-0`'s in-stack siblings; `smoke-3`/
   `smoke-7`/`smoke-10` are the landing frames of the next three stops
   (group2/group3/group4); `smoke-14` is the landing frame of the *fourth*
   next stop (the first single) — one stop past the planner's
   `nextStackCount: 3` window, the negative control.

   Now press ⌘1 (`script/vm_scenario_run.sh key 'keystroke "1" using
   {command down}'`) — this is the *first* time the cull loupe mounts this
   session, so its `.task(id: LoupeContentKey(...))` fires
   `requestVisibleCullPreview(smoke-0)` for the first time, with the six
   files above already missing. Confirm the initial selection is `smoke-0`
   (`ax find --role AXStaticText --contains "smoke-0.jpg"`) and the scope
   chip is absent (`cullScope` defaults to `.all`, matching
   `cull-023-return-commit-undo.md`'s Step 1 — no `S` press needed). If
   `smoke-0` isn't selected, the deletions above already happened before
   any landing occurred, so it's still safe to navigate (`Space`/`key code
   49`) until it is before continuing — nothing has been requested yet.

3. **Without pressing anything else — no arrows, no Return, nothing that
   touches any of the six frames above** — poll every ~3s for up to 60s
   (single-lane preview generation, `managedWorkerKindRunningLimits[.previewGeneration]
   = 1`, `AppCatalog.swift:43-51` — five renders happen strictly
   sequentially):
   ```bash
   for id in smoke-1 smoke-2 smoke-3 smoke-7 smoke-10 smoke-14; do
     script/vm_scenario_run.sh shell "test -f '$PREVIEWS/$id/large.jpg' && echo PRESENT || echo MISSING"
   done
   ```
   Also re-confirm the seven `catalog_generation` values are byte-identical
   to Step 1's captures — a prefetch render must never touch the catalog,
   only the preview cache:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, catalog_generation FROM assets
      WHERE id IN ('smoke-0','smoke-1','smoke-2','smoke-3','smoke-4','smoke-5','smoke-6')
      ORDER BY id;"
   # Compare each row's value against GEN0_BEFORE..GEN6_BEFORE from Step 1 by eye.
   ```

4. **Armed commit: delete the staged frame's own `.large`, press Return,
   assert the write is deferred.**
   ```bash
   script/vm_scenario_run.sh shell "rm -f '$PREVIEWS/smoke-0/large.jpg'"
   script/vm_scenario_run.sh key 'key code 36'   # Return
   ```
   Immediately poll the toast:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "Rendering full preview… will keep when ready"
   ```
   Immediately re-check ground truth — the falsification leg: any of these
   three values differing from Step 1's baseline is a FAIL, proving the
   gate did **not** defer the write:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'), catalog_generation
      FROM assets WHERE id IN ('smoke-0','smoke-1','smoke-2') ORDER BY id;"
   ```
   Expect exactly `smoke-0|reject|GEN0_BEFORE`, `smoke-1|NULL|GEN1_BEFORE`,
   `smoke-2|NULL|GEN2_BEFORE` — unchanged.

5. **Wait for the deferred render, then assert the commit fired
   automatically.** Poll every ~3s for up to 45s, staying frontmost each
   poll (`ax_drive.sh wait-vended` — idle-wedge):
   ```bash
   script/vm_scenario_run.sh shell "test -f '$PREVIEWS/smoke-0/large.jpg' && echo PRESENT || echo MISSING"
   ```
   Once it lands, poll the toast promptly (2s fade):
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "Kept smoke-0.jpg (was ✕) · rejected 2 · ⌘Z undoes"
   ```
   Ground truth — the flags landed with no tentative marker (this fixture's
   equivalent of "origin = user": a real flag value with `aiUnconfirmedFields`
   not containing `flag`):
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag'),
             catalog_generation
      FROM assets WHERE id IN ('smoke-0','smoke-1','smoke-2') ORDER BY id;"
   ```
   Expect `smoke-0|pick|0|<bumped>`, `smoke-1|reject|0|<bumped>`,
   `smoke-2|reject|0|<bumped>` — the force-flip promote
   (`cull-023-return-commit-undo.md`'s Step 2 leg, same fixture, same
   values) ran automatically, no second Return.

6. **Disarm: repeat the deletion on a fresh stack, arm, then move away
   before the render lands.** The Step 5 commit's post-commit advance
   (`applyCullingStackDecision`'s tail, `AppModel.swift:6610-6622`) lands
   selection on `smoke-3` (group2's landing frame, the very next stop) —
   confirm with `ax find --role AXStaticText --contains "smoke-3.jpg"`; if
   it isn't there, navigate to it (`→`/`key code 124`) before continuing.
   Record group2's baseline (already known from Step 1:
   `GEN3_BEFORE`…`GEN6_BEFORE`, flags `pick,NULL,reject,pick`). Delete
   `smoke-3`'s `.large` and press Return, then **immediately** (no
   intervening `find`/`sql` round-trip) press `→`:
   ```bash
   script/vm_scenario_run.sh shell "rm -f '$PREVIEWS/smoke-3/large.jpg'"
   script/vm_scenario_run.sh key 'key code 36'    # Return -- arms smoke-3
   script/vm_scenario_run.sh key 'key code 124'   # -> -- disarms immediately
   ```
   Wait 60s (a generous margin past the render time observed in Step 5 —
   long enough that the deferred commit would certainly have fired by now
   if the disarm hadn't held), then assert group2's flags/generations are
   **completely unchanged** from the recorded baseline — the falsification
   leg: any change here is a FAIL, proving the disarm did not hold:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'), catalog_generation
      FROM assets WHERE id IN ('smoke-3','smoke-4','smoke-5','smoke-6') ORDER BY id;"
   ```
   Expect `smoke-3|pick|GEN3_BEFORE`, `smoke-4|NULL|GEN4_BEFORE`,
   `smoke-5|reject|GEN5_BEFORE`, `smoke-6|pick|GEN6_BEFORE` — byte-identical
   to Step 1. (The deferred render itself is *not* cancelled by disarming —
   only the commit is gated — so `smoke-3/large.jpg` may still reappear on
   disk during or after this wait; that is expected and not part of the
   falsification. See Sharp edges.)

## Expected
- Step 3: **Fails if** any of `smoke-1`/`smoke-2`/`smoke-3`/`smoke-7`/
  `smoke-10` is still `MISSING` at the end of the 60s wait budget (the
  prefetch never fired, or fired for the wrong set), **or if** `smoke-14`
  ever reads `PRESENT` within the same window (the window leaked one stop
  past `nextStackCount: 3`), **or if** any `catalog_generation` value
  changed (a preview render wrote to the catalog, which it must never do).
- Step 4: **Fails if** the toast doesn't read exactly `"Rendering full
  preview… will keep when ready"`, or if any of `smoke-0`/`smoke-1`/
  `smoke-2`'s flag or `catalog_generation` differs from the Step 1 baseline
  — a write before the render landed is exactly the invariant this leg
  exists to catch.
- Step 5: **Fails if** the `.large` file never lands within the 45s budget,
  or if it lands but the toast/ground-truth commit never follows (the arm
  was dropped rather than fired), or if the committed flags/toast disagree
  with the Step 2 force-flip baseline `cull-023-return-commit-undo.md`
  already established for this exact fixture.
- Step 6: **Fails if** any of group2's four flags or `catalog_generation`
  values differs from the Step 1 baseline at any point during or after the
  wait — that would mean the disarm didn't actually prevent the deferred
  commit from firing.

## Cleanup
```bash
script/vm_scenario_run.sh shell "pkill -x Teststrip 2>/dev/null || true"
```
No seed-template cleanup needed (Source above) — every mutation this card
makes lives under `$RUN_DIR`, which `launch` never reuses across runs.

## Sharp edges
- **The toast fades after 2 real seconds** (`showDecisionToastThenFade`,
  `LibraryGridView.swift:4492-4498`) — poll immediately after each
  keypress; don't interleave several other `find`/`sql` round-trips first.
- **Keep the app frontmost during every wait.** A backgrounded/idle SwiftUI
  app parks its accessibility tree (idle-wedge, `test/scenarios/README.md`)
  — re-assert with `ax_drive.sh wait-vended` on each poll during the 45-60s
  render waits in Steps 3/5/6.
- **Step 6's disarm is a real (if generous) race, not a synchronous
  guarantee.** Pressing `→` merely has to land *before* the worker's
  completion callback fires for `smoke-3`'s render — not before the render
  starts. In practice the worker round-trip (dispatch over the JSON-lines
  protocol to a separate process, decode, render, encode, report back) is
  far slower than two back-to-back `osascript` keystrokes, but if this leg
  ever flakes with the flags landing anyway, suspect a driving-side delay
  between the two keystrokes (an accidental `find`/`sql` call slipped in
  between) before concluding it's an app bug.
- **Order matters in Step 3: check `smoke-14`'s absence there, not later.**
  Step 6 deliberately lands on `smoke-7` if the disarm's `→` is pressed
  from `smoke-3` in some future variant of this card — `smoke-7`'s *own*
  forward-3 window would then legitimately include `smoke-14` (it's one
  stop closer from that vantage point) and start warming it for real. This
  card's own Step 6 lands on `smoke-3`→(disarm arrow), which does not reach
  that far, but any edit to this card's navigation must re-check which
  stop's window `smoke-14` falls inside before reusing it as a negative
  control elsewhere.
- **The render-failure disarm path (`AppModel.swift:4485-4491`,
  `"Preview unavailable — not committed"`) is not exercised here.** No seed
  fixture in this repo induces a genuine preview-generation failure (a
  corrupted/unreadable original); this leg is source-verified only (Source
  above), matching how `cull-023-return-commit-undo.md`'s own Step 7 stayed
  source-only for the analogous reason.
- **`cull-023-return-commit-undo.md`'s Step 7 remains not executable by
  that card** even after this card closes the underlying behavior gap —
  that card's fixture is never mutated to use the deletion technique, since
  Step 7 was never that card's focus (force-flip/protection/sidecar/undo/
  standalone are). This card is the one that exercises the render-gate/
  armed-commit leg live.

## Run status
UNRUN — authored 2026-07-30, source-cited against the working tree at HEAD
`11cdf360` by directly reading `CullPrefetchPlanner.swift`,
`CullPrefetchPlannerTests.swift`, `CullPrefetchDriverTests.swift`,
`AppModel.swift` (`requestVisibleCullPreview`, `refreshCullPrefetchWindow`,
`promoteCurrentFrameAndRejectSiblings`, `armStackCommit`,
`disarmStackCommit`, `fireArmedStackCommitIfReady`, `armedCommitFeedback`,
`renderUnavailableFeedback`, `promoteDecisionFeedback`, `selectAssetID`,
`applyCullingShortcut`, `applyCompareFlags`,
`keepAllFramesInSelectedCullingStack`,
`keepTopRankedFramesInSelectedCullingStack`, `setFlagForSelectedAsset`,
`setFlagForSelectedAssets`, `previewURL(for:levels:)`,
`enqueuePendingPreviewGeneration`, `recommendedStackLandingAssetID`),
`CullingKeyCaptureView.swift` (`CullingKeyCaptureGate`),
`LibraryGridView.swift` (the cull-chrome `.task` dispatch, `decisionToast`,
`showDecisionToastThenFade`), `AppCatalog.swift` (`previewCacheRoot`,
`managedWorkerKindRunningLimits`), `PreviewCache.swift`, `PathSafeName.swift`,
`PreviewScheduler.swift`, `SmokeCatalogSeeder.swift`/`BurstFixtureLayout`,
and `BenchmarkCommand.swift`/`main.swift`'s `seed-burst-catalog` wiring.
Needs a live Tart VM run per `test/scenarios/README.md` (tracked
separately).
