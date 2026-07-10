# cull-018-compare-survey: Compare survey — header, contenders toggle, badges/metrics, group actions, reject-refill, and the shared key monitor

**What this covers**: as a photographer culling a shoot I want to lay several
near-duplicate frames side by side with rank/flaw badges and focus metrics so
that I can keep the best frame — via the guided group action or by dropping
into manual culling. Covers inventory items 55-62:

- Item 55 — `CompareSurveyPresentation` (`LibraryGridView.swift:4699-4820`):
  `primaryAsset`, `alternateAssets`, `framePositionText` ("Frame N of M"),
  `groupCountText` ("N frames"), `groupKindText` ("Compare set" /
  "Candidate stack"), `recommendationText`, `recommendedAssetID`,
  `comparativeVerdictText`.
- Item 56 — `contendersOnly` (init param `:4724`; `isContendersOnly =
  contendersOnly && isContendersModeAvailable` at `:4765`). UI toggle button
  in `compareHeader` (`:6133-6142`), title "Top 3 contenders" / "Full set"
  (`:4808-4810`), help "Narrows the compare grid to the top 3 ranked
  contenders" / "Shows the full compare set again" (`:4812-4816`);
  `static let contenderCount = 3`.
- Item 57 — "Evaluate Compare" button (`:6143-6152`, help "Runs evaluation
  for compare frames with cached previews"), gated by
  `model.canRequestCompareAssetEvaluations` (`AppModel.swift:2639-2641`) =
  worker alive AND at least one compare asset has a cached preview — NOT an
  N-selected-frames gate.
- Item 58 — tile chrome: `CompareSurveyActionPresentation`
  (`LibraryGridView.swift:5044-5073`), `CompareDecisionBadge` (`:5075-5092`;
  texts include "PRIMARY", "PICKED", "REJECTED", "N STAR", "✦ BEST", "#N",
  "EYES CLOSED", "SOFT"), `CompareFocusMetric` (`:5094-5110`; unevaluated
  tiles show title "No read yet", value "Evaluate").
- Item 59 — keep-primary group action button (`:6368-6375`). Its title is
  DYNAMIC ("Keep primary" or "Keep primary · reject N", `:4869-4872`) —
  match by help: "Marks the current compare primary as Pick and the visible
  alternates as Reject". Calls
  `model.keepComparePrimaryAndRejectAlternates()` (`AppModel.swift:4989`).
- Item 60 — "Choose manually" button (`:6384-6391`, fixed title, help "Open
  this compare set in stack-aware manual culling") →
  `model.beginManualCullingFromCompareSet()` (`AppModel.swift:4245`), which
  creates a manual-culling `WorkSession` and switches to loupe.
- Item 61 — `focusCullingSurface()` is called before the model write in
  every compare action handler (`applyCompareGroupChoice`
  `LibraryGridView.swift:6431-6438`, and the same pattern at `:6455-6504`).
  It only bumps a focus-request counter for the key-capture view — UI focus
  management, not a write gate.
- Item 62 — reject-refill: `CompareRefillOrdering.afterReject`
  (`AppModel.swift:348-363`), invoked from `setFlagForSelectedAsset` via
  `refillCompareSetAfterReject` (`AppModel.swift:5930-5959`) only when
  `selectedView == .compare`; refill pool = undecided members of the
  candidate stack.
- Plus the previously flagged **compare-monitor ambiguity**, resolved by
  source read — see Steps 8-9 and Sharp edges.

**Data-source note (drives Pre-state)**: `CompareView` does NOT consume a
multi-select. It calls `model.compareAssets()` (`LibraryGridView.swift:6048`
→ `AppModel.swift:4945-4961`), resolving in priority order: persisted work
stack anchored on the selection → internal `compareAssetIDs` (auto-built on
entering `.compare`, `AppModel.swift:5222-5244`) → visual-similarity
candidate stack → plain window of neighbors around the selection. With
`--smoke` (no persisted stacks), selecting one tile and pressing the Compare
mode key is sufficient — the set self-populates from stack/window fallbacks.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
BASELINE=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NOT NULL;")
```
Pick unflagged anchors up front:
```bash
sqlite3 "$DB" "SELECT id, original_path FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL LIMIT 6;"
```

## Steps
1. **Enter Compare on an unflagged anchor.** Press ⌘1 (Cull), click an
   unflagged tile (scroll into view first — virtualized grid), then switch
   the subview to Compare (toolbar mode button, or the grid's compare key —
   check the View menu's "Compare" item for the binding; the A/B sibling is
   bare `b`, Compare is its neighbor in `LibraryTopBarModeItem`s near
   `LibraryGridView.swift:4477`).
2. **Assert the survey header (item 55).**
   `script/ax_drive.sh wait --contains "frames"` (the `groupCountText`);
   `ax_drive.sh find --contains "Frame "` (framePositionText "Frame N of M");
   `ax_drive.sh find --contains "Compare set"` OR `--contains "Candidate stack"`
   (groupKindText — record which; `--smoke` without persisted stacks should
   yield one of these two fallback kinds).
3. **Assert provisional tile chrome (item 58) and no writes.** Unevaluated
   frames show the placeholder metric:
   `ax_drive.sh find --contains "No read yet"`. The primary tile carries the
   "PRIMARY" badge: `ax_drive.sh find --contains "PRIMARY"`. Ground truth —
   rendering the survey wrote nothing:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NOT NULL;"   # == BASELINE
   ```
4. **Evaluate Compare gating (item 57).** If previews haven't been cached
   yet, the button is disabled; wait for the worker to cache at least one
   compare preview, then:
   `script/ax_drive.sh press --role AXButton --contains "Evaluate Compare"`.
   Poll ground truth for evaluation signals on the compare-set members:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals WHERE asset_id IN (<compare-set-ids>);"
   ```
   After signals land, expect rank badges ("#1"…"#3", `:4962-4966`) and/or
   "✦ BEST" (`:4989`), and real metric lanes replacing "No read yet". Keep
   the app frontmost during the wait (idle-wedge; re-run `wait-vended` per
   poll).
5. **Contenders toggle (item 56).** This step REQUIRES step 4's evaluation
   signals to have landed first: `isContendersModeAvailable` is
   `!rankedCandidates.isEmpty` (LibraryGridView.swift, CompareSurveyPresentation
   init), and with zero `evaluation_signals` rows the button carries
   `.disabled(true)` — pressing it then is a **designed no-op**, not a
   defect (verified against source 2026-07-10; run-cull-iter2's "inert
   toggle" was on the zero-signals `--smoke` seed). Note AXPress on a
   disabled SwiftUI button still "succeeds" from the driver's side — check
   the AXEnabled attribute or the title flip, not the press result. With
   signals present, press
   `script/ax_drive.sh press --role AXButton --help "Narrows the compare grid to the top 3 ranked contenders"`.
   Assert the button title flips to "Full set"
   (`ax_drive.sh find --contains "Full set"`) and at most 3 tiles render.
   Press it again (help "Shows the full compare set again") and assert the
   full set returns. Catalog unchanged throughout (re-run the step-3 count).
6. **Reject-refill (item 62) — PROBE via X.** Note the current compare-set
   filenames. Select an alternate tile and press `X`. Assert:
   (a) that asset now reads `reject` in `metadata_json`; (b) the rejected
   tile leaves the survey; (c) if an undecided stack sibling exists outside
   the visible set, exactly one new tile appends
   (`CompareRefillOrdering.afterReject`, `AppModel.swift:348-363`) — if the
   candidate pool is exhausted the set just shrinks; record which happened.
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id='<rejected-id>';"
   ```
7. **Keep primary, reject alternates (item 59).** ⌘Z the step-6 reject
   first to restore a clean set. Then:
   `script/ax_drive.sh press --role AXButton --help "Marks the current compare primary as Pick and the visible alternates as Reject"`
   (title is dynamic — do not match "Keep primary" text alone). Assert
   ground truth: the primary asset is `pick`, every visible alternate is
   `reject`, nothing outside the set changed:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN (<compare-set-ids>);"
   ```
   Then ⌘Z once and assert the whole group reverts (one gesture).
8. **PROBE — P/X/Return under the shared monitor (resolved ambiguity).**
   With Compare active and the primary selected, press `P`. Finding from
   source: `GridKeyCaptureView` commands are SUPPRESSED in `.compare`
   (`GridKeyCommand.isAllowed(in:)`, `GridKeyCaptureView.swift:97-113`,
   `default: false`), but `CullingKeyCaptureView` IS active
   (`CullingKeyCaptureGate.isActive`, `CullingKeyCaptureView.swift:11-15`:
   `workspace == .cull && selectedView != .cullGrid`). So `P` fires
   grid-cull pick semantics on `selectedAssetID` via
   `applyCullingShortcut(.pick)` → `applyCullingCommandAndAdvance`
   (`AppModel.swift:5414-5458`). Assert the selected asset's flag becomes
   `pick` in the catalog. ⌘Z to revert.
9. **PROBE — Return in Compare.** Press Return. Finding from source: Return
   maps to `.promoteAndRejectSiblings` →
   `promoteCurrentFrameAndRejectSiblings()` (`AppModel.swift:5351-5359`),
   which is a DIFFERENT write path from the item-59 button and **silently
   no-ops** unless the selected asset is in a persisted work stack or a
   `cullingStacks()` entry. In `--smoke` (no persisted stacks) the expected
   behaviors are: no-op if the anchor isn't in a derived culling stack, or a
   stack promote if it is. Assert whichever ground truth shows, and record
   it:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NOT NULL;"
   ```
   **Fails if** Return writes something that matches neither path (e.g.
   rejects visible non-stack alternates the way the button would).
10. **Choose manually (item 60).**
    `script/ax_drive.sh press --role AXButton --contains "Choose manually"`.
    Assert the app switches to the loupe (culling chrome present) and a
    manual work session row appeared:
    ```bash
    sqlite3 "$DB" "SELECT id, kind, intent, status FROM work_sessions ORDER BY created_at DESC LIMIT 1;"
    ```
    The newest row's kind/intent should read as manual culling over the
    compare set — quote the actual values. Confirm starting the session
    wrote no asset flags by itself (flag count unchanged from before the
    click).

## Expected
- Step 2: header shows position, count, and kind texts. **Fails if** the
  survey is empty with a valid anchor selected (data-source fallbacks
  broken) or the kind text is missing.
- Step 3: badges/metrics render with the catalog untouched (== BASELINE
  delta from any earlier steps only). **Fails if** merely opening Compare
  writes any flag — confirm-before-write violation; report, don't soften.
- Step 4: Evaluate Compare is pressable once a preview is cached, and
  signals rows appear for compare-set members. **Fails if** the button
  stays disabled with a live worker + cached previews, or pressing it
  writes `metadata_json` (evaluation must only add `evaluation_signals`).
- Step 5: contenders mode caps visible tiles at 3 and round-trips cleanly.
  **Fails if** the toggle changes catalog state or is enabled before any
  ranking exists.
- Step 6: X rejects exactly the selected alternate and the set refills from
  undecided stack siblings (or shrinks when exhausted). **Fails if** the
  rejected tile stays, or the refill pulls an already-decided frame.
- Step 7: one gesture writes pick + N rejects exactly over the visible set;
  one ⌘Z reverts all of it. **Fails if** alternates outside the visible
  (e.g. contenders-hidden) set are rejected, or undo splits the group.
- Step 8: P writes `pick` on the selected asset (culling monitor is live in
  Compare). **Fails if** nothing happens (would contradict the
  `CullingKeyCaptureGate` read — re-verify and update this card) — and note
  either way this is grid-cull semantics, not a compare-specific action.
- Step 9: Return either no-ops or performs a stack promote per the
  stack-membership guard; it must NOT behave like the item-59 button.
- Step 10: a work session row appears, view switches to loupe, and no
  asset flags were written by the switch itself.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the app instance you launched.

## Sharp edges
- **Compare-monitor ambiguity — RESOLVED by source read, pending live
  confirmation.** Two overlay key monitors coexist
  (`LibraryGridView.swift:179-202`). In `.compare`, `GridKeyCaptureView` is
  gated off but `CullingKeyCaptureView` is active, so P/X apply grid-cull
  pick/reject to the selected survey tile (X additionally triggers the
  item-62 refill), while Return runs `promoteCurrentFrameAndRejectSiblings`
  — a stricter, stack-guarded path that can silently no-op while the "Keep
  primary" button is enabled (`canKeepComparePrimaryAndRejectAlternates` =
  `catalog != nil && !compareAssets().isEmpty` is looser). This
  button-vs-Return divergence is a genuine UX inconsistency worth a ledger
  note even if the probes pass as predicted.
- **The keep-primary button title is dynamic** ("Keep primary" vs "Keep
  primary · reject N") — always match by `--help`.
- **Evaluate Compare's gate depends on the worker and cached previews**, not
  selection count. On a slow preview pipeline the button can stay disabled
  for a while; that's the gate working, not a bug. Keep the app frontmost
  during the wait (idle-wedge).
- **Contenders toggle is disabled until ranking data exists**
  (`isContendersModeAvailable`); don't assert it pressable pre-evaluation.
- **`--smoke` has no persisted stacks**, so the survey set comes from the
  candidate-stack/window fallbacks and step 6's refill may find no
  candidates (set shrinks — legitimate). A fixture with a real
  multi-frame similar-stack would exercise refill deterministically;
  fixture gap per README.
- Badge/metric *values* (rank order correctness, focus scores) are not
  asserted — only their presence; correctness of the evaluator is unit-test
  territory, and AX exposes the strings but not a trustworthy ranking
  oracle.
- The exact Compare subview key/toolbar binding was not pinned down by
  source read (A/B is `b`; Compare's key wasn't verified) — step 1 says to
  use the toolbar mode button / View menu; correct this card with the key
  once observed.
- `focusCullingSurface()` before writes (item 61) is focus plumbing, not a
  data gate; the card verifies compare actions still work after the call
  (i.e. writes land), not any observable ordering — the ordering claim is
  source-verified only (`LibraryGridView.swift:6431-6504`).

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md. All
source claims (line numbers, labels, help strings, gate conditions, both
key-monitor paths) verified by source read on 2026-07-10; no SQL dry-run or
live AX run yet.
