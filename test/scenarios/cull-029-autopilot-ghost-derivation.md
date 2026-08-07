# cull-029-autopilot-ghost-derivation: the unconfirmed AI flag is the only record of a machine proposal — badges, review queue, and sidebar count all derive from it, and a user override never resurrects

**What this covers**: Jesse runs autopilot on a seeded batch, sees ghost
badges on the frames it proposed, rejects one directly, and confirms the
badge — and the frame's eligibility for a future proposal — is gone for
good. SP-D0 deleted the `autopilot_proposals` status table outright
(`DROP TABLE IF EXISTS autopilot_proposals`,
`Sources/TeststripCore/Catalog/CatalogMigrations.swift:263`, forward-only,
no back-out); the machine's flag opinion — the ✨ "ghost" — now lives
nowhere but the unconfirmed AI flag already sitting in `metadata_json`.
Every surface this card drives reads that one field, never a status row:

- `AutopilotGhost.kind(in:)` (`Sources/TeststripCore/Autopilot/
  AutopilotGhost.swift:15`, verified against the working tree
  2026-08-06) — the single derivation source: `nil` unless
  `metadata.aiUnconfirmedFields.contains(.flag)`, in which case it returns
  `metadata.flag`. A frame can have no status at all.
- `CatalogRepository.assetIDsWithAutopilotGhost()`
  (`Sources/TeststripCore/Catalog/CatalogRepository.swift:449`, verified
  2026-08-06) — the catalog-wide SQL twin of the same predicate
  (`json_extract(metadata_json,'$.flag') IS NOT NULL AND EXISTS (... WHERE
  json_each.value = 'flag')`), used for the review queue and sidebar count
  so neither silently shrinks to whatever the grid happens to have loaded.
- `AppModel.beginAutopilotReview()` (`Sources/TeststripApp/AppModel.swift:9830`,
  verified 2026-08-06) narrows the grid to exactly
  `autopilotGhostAssetIDs` (declared `:2256`, refreshed from
  `assetIDsWithAutopilotGhost()` by `refreshAutopilotGhostAssetIDs()`
  at `:13221`, itself called from `refreshCatalogSidebarCounts()` and — for
  the relaunch leg below — unconditionally from `AppModel.load(catalog:)`
  at `:4718`). `cullSourcePresentation` (`:5871`, verified 2026-08-06)
  appends the "Autopilot Proposals" `CullSource` to the Cull sidebar's "Cull
  From" list only `if !autopilotGhostAssetIDs.isEmpty` (`:5885`), with
  `count: autopilotGhostAssetIDs.count` (`:5891`) — so the row itself
  disappears the instant no ghost remains, rather than sitting there at 0.
- `AutopilotBadgePresentation.badge(for:)`
  (`Sources/TeststripApp/LibraryGridView.swift:3608`, verified 2026-08-06)
  maps a ghost's own flag value straight to the grid tile's badge — `.pick`
  → `("KEEP", isKeep: true)`, `.reject` → `("CUT", isKeep: false)`, `nil` →
  no badge — called at three grid-cell call sites with
  `autopilotDecision: AutopilotGhost.kind(in: asset.metadata)`
  (`:2370`, `:7663`, `:8120`). The grid cell collapses to one AX element, so
  the badge shows up in the cell's accessibility **value**, not a separate
  label: `AssetGridCellAccessibilityValue.value(...)` appends
  `"Autopilot proposes \(isKeep ? "keep" : "cut")"` (`:8318-8319`) whenever
  `AutopilotBadgePresentation.badge(for:)` returns non-nil — this is what
  `ax find --contains "Autopilot proposes keep"` / `"...cut"` matches below.
- `CullCompletionPresentation.summary(assets:viewedAssetIDs:skippedAssetIDs:)`
  (`Sources/TeststripApp/CullCompletionPresentation.swift:32`, verified
  2026-08-06) classifies every asset by `confirmedProjection.flag` — a
  ghost's flag is AI-unconfirmed, so it is never `.pick`/`.reject` here,
  always `undecided` (`:43-52`), and the completion gate
  (`presentation(...)`, `:88-103`) requires `undecided == 0` before it ever
  renders — a scope still carrying a ghost never reaches the completion
  stage. Unlike the pre-SP-D0 build this branch replaces,
  `cullCompletionStage`/`cullCompletionRunDetailText`
  (`Sources/TeststripApp/LibraryGridView.swift:3958-4031`, verified
  2026-08-06) carry **no `sparkleAwaiting` field, no "awaiting review" text,
  and no `.reviewAISuggestions` action at all** — the whole ceremony
  `cull-025-run-strip-completion.md` documented is gone from the source, not
  merely gated to zero (confirmed by grep: zero hits for
  `reviewAISuggestions`/`sparkleAwaiting`/"awaiting review" anywhere under
  `Sources/TeststripApp/`, 2026-08-06). The detail line is exactly
  `"\(skipped) skipped · \(neverViewed) never viewed"` (`:4030`).
- **Gone is gone, precisely**: `AppModel.setFlagForSelectedAsset(_:)`
  (`AppModel.swift:7352-7380`) routes a `U` (`.clearFlag`, key mapped
  `AppModel.swift:296`) two different ways depending on whether the flag is
  *still tentative* at the moment `U` lands (`:7362-7367`): if
  `aiUnconfirmedFields` still contains `.flag`, `U` is the **reject**
  gesture — it calls `removeAIField(.flag, for:)` (`:8391-8420`), which
  clears the flag **and** unconditionally records the rejected value in
  `removed_ai_labels` (`asset_id, field, value, created_at` —
  `Sources/TeststripCore/Catalog/CatalogMigrations.swift:231-238`) at
  `AppModel.swift:8413`. `applyTentativeAutopilotProposals` (`:9712-9759`)
  checks exactly that table before re-proposing the same value on a later
  run (`:9719`, `:9728-9732`) — this is the entire resurrection-prevention
  mechanism, pinned live by
  `testClearingATentativeGhostRecordsItsRemovalAndSuppressesTheNextRun`
  (`Tests/TeststripAppTests/AppModelTests.swift:5935-5963`). If instead the
  flag was already **confirmed** (a prior `P`/`X` already ran — confirming
  unconditionally removes `.flag` from `aiUnconfirmedFields` per the same
  function's doc comment, `:7371-7374`), `U` takes the plain-clear branch
  instead (`updateSelectedAssetMetadata`, no `removeAIField` call, no
  `removed_ai_labels` row) — the frame returns to genuinely neutral
  undecided, not "rejected," so nothing blocks a later run from proposing it
  again. This distinction is load-bearing for Step 5 below and is pinned
  separately by `testDirectFlagThenClearLeavesNoGhostAnywhere`
  (`AppModelTests.swift:5905-5931`, whose own comment: "A direct user flag
  replaces the ghost; pressing U afterwards returns the frame to neutral
  undecided").

## Pre-state
VM, `smoke` variant:
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended Teststrip
```
Baselines (`sql smoke` targets the newest `run/smoke-*` dir, i.e. the one
`launch` just created):
```bash
script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='autopilot_proposals';"   # expect 0 — the table is gone
GHOST0=$(script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');")   # expect 0
GEN0=$(script/vm_scenario_run.sh sql smoke "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;")
```

## Steps
1. **Evaluate the visible scope.** ⌘2 for Library
   (`script/vm_scenario_run.sh key 'keystroke "2" using {command down}'`),
   then ⇧⌘E:
   ```bash
   script/vm_scenario_run.sh key 'keystroke "e" using {shift down, command down}'
   ```
   Poll to a full drain, keeping the app warm between polls (idle-wedge):
   ```bash
   for i in $(seq 1 60); do
     n=$(script/vm_scenario_run.sh sql smoke "SELECT count(DISTINCT asset_id) FROM evaluation_signals;")
     [ "$n" -ge 24 ] && break
     script/vm_scenario_run.sh ax wait-vended Teststrip
     sleep 2
   done
   ```
2. **Run autopilot.** Culling ▸ Run Autopilot — reachable as a plain AX
   element without opening the menu bar title first (`people-020-ai-label-
   provenance.md`'s identical pattern):
   ```bash
   script/vm_scenario_run.sh ax press --role AXMenuItem --label "Run Autopilot"
   ```
   Poll for ghosts, keeping the app warm:
   ```bash
   for i in $(seq 1 60); do
     GHOSTN=$(script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');")
     [ "$GHOSTN" -gt "$GHOST0" ] && break
     script/vm_scenario_run.sh ax wait-vended Teststrip
     sleep 2
   done
   ```
   Record the ghost asset ids and their flag values (this is `$G1`, `$G2`,
   … below, in `rowid` order) and re-confirm the table stays gone:
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag') ORDER BY rowid;"
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='autopilot_proposals';"   # still 0 — never recreated
   ```
   **If the loop times out with `GHOSTN == GHOST0`, stop — see Sharp edges.**
   This fixture is expected to hit exactly that branch (see below); do not
   force Steps 3-7 forward on a synthetic run to make the card "pass."
3. **Ghost badges render.** In Library, scroll `$G1`'s tile into view by
   filename (`ax_drive.sh find --contains "$G1.jpg"` — the grid is lazily
   virtualized, README) and read its accessibility value:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Autopilot proposes keep"   # if $G1's flag is 'pick'
   script/vm_scenario_run.sh ax find --contains "Autopilot proposes cut"    # if $G1's flag is 'reject'
   ```
   Repeat for every ghost id from Step 2, matching each one's own flag
   value — no exceptions, and no table is consulted anywhere in this
   render path (Source above).
4. **Sidebar source and count.** ⌘1 for Cull
   (`script/vm_scenario_run.sh key 'keystroke "1" using {command down}'`).
   Assert the row exists:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Autopilot Proposals"
   ```
   Cross-check the count against the same catalog-wide predicate
   `beginAutopilotReview()` uses (ground truth, not the render):
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # must equal GHOSTN
   ```
5. **Reject a ghost directly — gone is gone, and nothing resurrects (P0).**
   On `$G1` (still tentative — do not press `P`/`X` first; see Source's
   "Gone is gone, precisely" note on why order matters here), select its
   tile and press `U` directly:
   ```bash
   script/vm_scenario_run.sh key 'keystroke "u"'
   script/vm_scenario_run.sh sql smoke "SELECT json_extract(metadata_json,'\$.flag'), json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id='\$G1';"   # expect NULL, NULL
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM removed_ai_labels WHERE asset_id='\$G1' AND field='flag';"   # expect 1
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE id='\$G1' AND EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # expect 0
   ```
   Re-check `$G1`'s tile: neither "Autopilot proposes keep" nor "...cut" may
   appear. Then re-run Culling ▸ Run Autopilot
   (`ax press --role AXMenuItem --label "Run Autopilot"`) and re-run the
   same three queries — **still NULL/NULL, still exactly 1, still 0**:
   `removed_ai_labels` must suppress the re-proposal so nothing can
   resurrect `$G1`.

   **Secondary leg — override then clear, only if `GHOSTN >= 2` (`$G2`
   exists).** This is a *different*, also-correct behavior — do not conflate
   it with the P0 above. Press a decisive flag key on `$G2` (`P` or `X`,
   either confirms), then press `U`:
   ```bash
   script/vm_scenario_run.sh key 'keystroke "p"'   # or "x" — either confirms $G2's flag
   script/vm_scenario_run.sh sql smoke "SELECT json_extract(metadata_json,'\$.flag'), json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id='\$G2';"   # expect <pick|reject>, NULL — confirmed, ghost already gone
   script/vm_scenario_run.sh key 'keystroke "u"'
   script/vm_scenario_run.sh sql smoke "SELECT json_extract(metadata_json,'\$.flag'), json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id='\$G2';"   # expect NULL, NULL
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM removed_ai_labels WHERE asset_id='\$G2' AND field='flag';"   # expect 0 — confirm-then-clear never "rejects" anything
   ```
   `$G2` is now genuinely neutral, not suppressed — a later Autopilot run
   *may* legitimately re-propose it. That is correct behavior per Source's
   distinction, not a resurrection of the original ghost (which was already
   erased the moment `P`/`X` confirmed it, several lines above).
6. **Complete the run; no ✨ ink anywhere.** Decide every remaining frame
   with `P`/`X` (poll the HUD's "N left" segment after each decision) until:
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL OR EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # 0
   ```
   Assert the completion stage:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Nothing left to decide"
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "never viewed"      # the detail line, e.g. "0 skipped · 0 never viewed"
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "awaiting review"   # expect NOT-FOUND
   script/vm_scenario_run.sh ax find --role AXButton --contains "Review AI Suggestions" # expect NOT-FOUND
   ```
   This step's absence-of-ceremony assertions hold **regardless of
   `GHOSTN`** — `sparkleAwaiting`/`.reviewAISuggestions` are gone from the
   source entirely (Source above), not merely zero for this fixture — so
   this step remains meaningful even in the fixture-gap branch where Steps
   3-5 could not run.
7. **Relaunch: badges survive, banner does not.** Quit the app and reopen
   it against the **same** run directory, not a fresh copy — `launch`
   (`cmd_launch`, `script/vm_scenario_run.sh:282-343`) always stamps a brand
   new `run/<variant>-<timestamp>` on every call, so it can never be used
   for a relaunch leg (see Sharp edges). Go through `shell` instead, which
   creates no new run dir, so `sql smoke`'s "newest `run/smoke-*` dir"
   resolution (`cmd_sql`, `:347-351`) keeps targeting the very catalog this
   card has been mutating:
   ```bash
   script/vm_scenario_run.sh shell 'osascript -e "tell application \"Teststrip\" to quit"'
   script/vm_scenario_run.sh shell 'latest=$(ls -dt /Users/admin/teststrip-vm/run/smoke-* | head -1); open -n /Users/admin/teststrip-vm/dist/Teststrip.app --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$latest"'
   script/vm_scenario_run.sh ax wait-vended Teststrip
   ```
   **Reorder the card in practice** (the same ordering-conflict pattern
   `cull-017-autopilot-review.md`'s Sharp edges already documents for its
   own Dismiss/Review conflict): Step 6 decides *every* remaining frame,
   which necessarily includes any ghost besides `$G1`/`$G2`, so by the time
   Step 6 finishes there is nothing left with a live ghost to assert
   survives a relaunch. Drive this step as an independent branch instead —
   either (a) hold back one ghost id from Step 6's sweep (skip deciding it,
   so completion never gates in that branch, and drive this step's
   quit/relaunch/assert sequence in isolation without ever reaching Step
   6), or (b) re-run Steps 1-4 fresh on a new `launch smoke` and quit
   immediately after Step 4 with at least one ghost still undecided, before
   doing Step 5 or 6 at all. Do not attempt to run Steps 6 and 7 back to
   back against the same undecided ghost — they are mutually exclusive
   outcomes for the same asset, exactly like cull-017's Dismiss/Review pair.
   Assert:
   ```bash
   script/vm_scenario_run.sh ax find --contains "Autopilot proposes"      # expect FOUND for the surviving ghost
   script/vm_scenario_run.sh ax find --contains "Autopilot reviewed"      # expect NOT-FOUND (the run-time-only banner; AutopilotBannerPresentation, LibraryGridView.swift:3628, set only by runAutopilot's in-memory autopilotRunSummary, AppModel.swift:9695, never reloaded by `load(catalog:)`)
   ```

## Expected
- Step 1: `evaluation_signals` reaches 24 distinct assets. **Fails if** it
  stalls or an error alert shows.
- Step 2: `GHOSTN` grows past `GHOST0` on an evaluated scope, and
  `autopilot_proposals` never exists as a table. **Fails if** any row or
  even an empty table named `autopilot_proposals` appears (the DROP was
  supposed to be forward-only and unconditional), or if a ghost asset's
  `flag` is set without `aiUnconfirmedFields` containing `flag` — a
  tentative verdict silently landing as confirmed is a provenance-invariant
  violation: report immediately, do not soften it. **If `GHOSTN == GHOST0`
  after the full drain, this is the honest fixture-gap branch (Sharp
  edges) — mark the card NOT-RUN for Steps 3-5/7, not a pass and not a
  failure.**
- Step 3: every ghost id's tile shows the badge matching its own
  `metadata_json.flag`. **Fails if** a badge is missing, wrong, or present
  on an asset with no ghost.
- Step 4: the "Autopilot Proposals" row is present with count == `GHOSTN`.
  **Fails if** the row is absent while `GHOSTN > 0`, present while
  `GHOSTN == 0`, or its count disagrees with the SQL cross-check.
- Step 5: **Fails if** the ghost returns in `metadata_json` for `$G1` after
  `U`, if its badge reappears, if a second Autopilot run re-proposes a flag
  for `$G1`, or if `removed_ai_labels` does not gain exactly the one row for
  `$G1`/`flag`. Resurrection is the exact bug this spec exists to kill —
  this is a P0, not a nitpick; a runner must not talk themselves out of a
  failure here by arguing the badge "looks" gone without the SQL and re-run
  checks. (Secondary leg: **fails if** `$G2`'s `removed_ai_labels` count is
  nonzero after confirm-then-clear — that would mean a plain neutral-clear
  is wrongly recording a rejection it never made.)
- Step 6: **Fails if** the detail line contains "awaiting review", if a
  "Review AI Suggestions" button is present, or if any ✨ count appears
  anywhere in the completion stage — regardless of `GHOSTN`.
- Step 7: **Fails if** a ghost tile loses its badge across relaunch (ghosts
  must survive natively via `metadata_json`, no reconstruction step
  required) or if the "Autopilot reviewed" banner reappears (it is
  run-time-only and must not be reloaded from disk).

## Cleanup
```bash
script/vm_scenario_run.sh shell 'osascript -e "tell application \"Teststrip\" to quit"'
```
`vm_scenario_run.sh`'s `run/<variant>-<timestamp>` directories are
per-launch throwaways (`cmd_launch` copies the seed template fresh every
call) — this card makes no template mutation (unlike `cull-025`'s Leg A),
so there is nothing to reset before the next card in the same VM session
runs `sync smoke`/`launch smoke` again.

## Sharp edges
- **This card's mandated fixture (`smoke`) cannot structurally produce a
  flag ghost — this is a near-certainty, not just a "may."**
  `AutopilotProposalPlanner.cullProposals` only emits pick/reject proposals
  `for stack in stacks where stack.assetIDs.count > 1`
  (`Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift:36`) —
  standalone (single-member) stops are never eligible. `AssetStackBuilder`
  only groups two assets into the same stack when their capture gap is
  `<= defaultMaximumCaptureGap` (`Sources/TeststripCore/Search/
  AssetStackBuilder.swift:14`, `= 2` seconds), but `--smoke`'s seeder spaces
  every asset `TimeInterval(index * 900)` apart when no explicit
  `captureOffsets` are given (`Sources/TeststripBench/
  SmokeCatalogSeeder.swift:136`) — 900 seconds, 450x the grouping
  threshold — and `build_and_run.sh --smoke`'s seeding call passes none
  (`Sources/TeststripBench/main.swift:424`). So every one of `smoke`'s 24
  stops is standalone by construction, `cullProposals` never runs for any
  of them, and a live Evaluate+Run Autopilot pass on `smoke` can only ever
  produce **keyword**-kind proposals (gated on `input.
  keywordCandidatesByAssetID`, unrelated to the flag ghost this card is
  about) — never a flag ghost. Per the Honesty requirement this card was
  written under: **if `GHOSTN == GHOST0` after the Step 1/2 drain, that is
  this exact fixture gap, not a failure** — mark Steps 3-5 and 7
  NOT-RUN rather than forcing a pass, and do not chase it as a product bug.
  A stack-bearing seed (e.g. `burst`) would be needed to exercise the
  ghost-producing path live — though `cull-017-autopilot-review.md` and
  `cull-025-run-strip-completion.md` already flag that even `burst`'s flat
  synthetic frames crossing autopilot's rankability floor
  (`CullingQualityScore.qualityScore`) is not established; this card does
  not attempt to resolve that, only to name it precisely for whichever
  fixture the controller substitutes. `cull-025`'s Pre-state (Leg A) shows
  the alternative if a live run is wanted regardless: hand-seed a tentative
  ghost directly into a template's `metadata_json` before `launch` (no
  `autopilot_proposals` row needed anymore, unlike that card's own
  now-outdated Leg A seed SQL — SP-D0 dropped that table, so only the
  `metadata_json` UPDATE half of that recipe still applies).
- **`launch` always copies the seed template fresh — it cannot relaunch
  against an existing catalog.** `cmd_launch` (`script/
  vm_scenario_run.sh:282-343`) unconditionally stamps a new
  `run/<variant>-<timestamp>` directory and points
  `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` at it on every call — there is
  no flag to reuse a prior run dir. Step 7's relaunch therefore goes
  through `shell` (which creates no run dir) issuing the exact same `open
  -n ... --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=...` invocation
  `cmd_launch` itself uses (`:341`), pointed at the *existing* `run/smoke-*`
  directory via `ls -dt | head -1` — the same resolution `cmd_sql` uses
  (`:350`), so every `sql smoke` call after this relaunch keeps targeting
  the same catalog. **This exact mechanism is unverified until the live
  run** — the controller will confirm it on first execution and correct
  this card if `open -n`'s working directory or TCC prompt behaves
  differently than `cmd_launch`'s own use of the identical command line.
- **Idle-wedge.** Re-assert frontmost (`ax wait-vended`) on every poll
  iteration in Steps 1, 2, and 6 — a backgrounded/idle instance parks its
  AX tree and a plain `sleep` loop without re-assertion will eventually
  read an empty window subtree instead of a real "not yet" result.
- **Virtualized grid.** Off-screen thumbnails are not in the AX tree at
  all (README) — Step 3 must scroll each ghost tile into view by filename
  before asserting its accessibility value, or a true positive will read as
  a false "not found."
- **Order matters for Step 5's P0 leg.** `U` on a still-tentative ghost and
  `U` on an already-confirmed flag take genuinely different code paths
  (Source's "Gone is gone, precisely" note) — only the former writes
  `removed_ai_labels` and is what suppresses a future re-proposal. Pressing
  `P`/`X` on `$G1` before `U` would silently convert this into the
  secondary (non-suppressing) leg and the P0 assertions would legitimately
  fail for reasons that have nothing to do with a resurrection bug — do not
  reorder these two legs.
- **The sidebar row's exact AX text for the count is unverified.**
  `CullSidebarView.sourceRow` (`Sources/TeststripApp/CullSidebarView.swift:
  53-66`) builds the row from a plain `Button { HStack { Label(...); Text(
  String(source.count)) } }` with no explicit `.accessibilityLabel`/
  `.accessibilityValue` override, so the exact concatenated string SwiftUI
  exposes (likely something like `"Autopilot Proposals, N"` but not
  confirmed against a live AX dump) is not pinned by this card — Step 4
  treats the row's title match plus the SQL cross-check as authoritative
  and does not assert a specific combined string; record the live value on
  first execution.

## Run status
NOT RUN — card authored 2026-08-06 alongside the SP-D0 ghost-derivation
push; source-cited against the working tree at `287f574c`, not yet driven.
Needs a live VM run. Prediction, stated plainly per this card's own Sharp
edges: Steps 1-2 should run cleanly, but Steps 3-5 and 7 are very likely to
land in the fixture-gap branch (`GHOSTN == GHOST0`) on the `smoke` variant
as specified, for the structural reason cited above — that outcome is a
fixture gap to document, not a defect to chase, and the card should be
marked NOT-RUN (not Tested-Fail) if it lands there.
