# cull-017-autopilot-review: Autopilot proposes, badges the grid, you review (selected/all), commit, dismiss, undo

**What this covers**: as a photographer who just imported a shoot with
Autopilot armed, I want machine-proposed keeps/cuts surfaced as provisional
grid badges I can scan, then either commit them (selected subset or all) or
dismiss/undo. `runAutopilot` (`AppModel.swift:9594`) plans in-memory
`AutopilotProposal`s (`AutopilotProposalPlanner`, never persisted — SP-D0
dropped the `autopilot_proposals` status table outright,
`DROP TABLE IF EXISTS autopilot_proposals`, forward-only, no back-out) and
immediately applies each `.pick`/`.reject` straight into the asset's own
`metadata_json.flag` (`applyTentativeAutopilotProposals`,
`AppModel.swift:9655`), tagged `origin=ai` (`aiUnconfirmedFields` contains
`flag`) — this AI-origin, unconfirmed flag **is** the "ghost"
(`AutopilotGhost.kind(in:)`,
`Sources/TeststripCore/Autopilot/AutopilotGhost.swift:15`), the single
source of truth for "the machine proposed a flag." There is no longer, and
now can never again be, a persisted "proposal" row distinct from the ghost
sitting in the asset's own metadata. The `AutopilotBannerView` Review/Undo
all/Dismiss controls (item 52 — `LibraryGridView.swift:3556-3603`,
`AppModel.swift:9760` `dismissAutopilotRunSummary`) → grid-cell KEEP/CUT
badges from `AutopilotBadgePresentation.badge(for:)` (item 53 —
`LibraryGridView.swift:3518-3530`, wired via
`autopilotDecision: AutopilotGhost.kind(in: asset.metadata)` on
`AssetGridCell` at `:2346`/`:8029` and in
`AssetGridCellAccessibilityValue.value(...)` at `:7576`) → the review
toolbar's Commit selected / Commit all / Dismiss selected controls,
`commitAutopilotProposals(assetIDs:)`
(`AppModel.swift:9808`) being the gesture that *confirms* the ghost (clears
`aiUnconfirmedFields`, writes the sidecar) rather than first-writing
anything, and `dismissAutopilotProposals(assetIDs:)` (`AppModel.swift:9854`)
being the gesture that *removes* it (records `removed_ai_labels`, the same
recorded-removal mechanism a direct `U` uses). The load-bearing assertion is
the **auto-apply-with-provenance** invariant: a run's keep/cut proposals
land in `metadata_json` immediately, `origin=ai` (unconfirmed) and never
synced to the `.xmp` sidecar; an explicit Commit confirms them (flips to
`origin=user`, writes the sidecar); Dismiss removes them (records
`removed_ai_labels`, no sidecar, and suppresses a future re-proposal); Undo
all reverts the run's tentative writes back to the pre-run state. (See
`people-020-ai-label-provenance.md`, which drives this same mechanism
end-to-end, and `cull-029-autopilot-ghost-derivation.md`, which owns the
ghost-derivation architecture end-to-end on-demand — this card is the
armed-import-triggered, Review-toolbar-specific companion, not a
duplicate.)

## Pre-state
- **This card drives the post-import armed-Autopilot path, not the on-demand
  gesture.** `runAutopilot` (`AppModel.swift:9594`) has two entry points: an
  on-demand one via Culling ▸ Run Autopilot (`runAutopilotOnCurrentScope()`,
  scope `.visible` — driven by `app-012-autopilot-evaluate-commands.md`), and
  the post-import armed run this card exercises (`runArmedImportAutopilot`,
  scope `.assetIDs(importedAssetIDs)`), invoked once when an import with
  Autopilot armed finishes evaluating. The "Autopilot on" checkbox itself is
  only the persisted *setting* that arms post-import runs; toggling it on a
  static catalog with no import in flight does nothing on its own. So this
  card imports a folder to trigger a run.
- An import fixture folder of a few frames (want ≥4 so a partial "Commit
  selected" is distinguishable from "Commit all"):
  ```bash
  FIX=$(mktemp -d); swift run TeststripBench seed-dup-fixtures "$FIX" >/dev/null
  IMP="$FIX/card1"        # 4 distinct JPEGs
  ```
- Fresh build, isolated seeded catalog:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```

## Steps
1. **Arm autopilot and record the baseline.** `script/ax_drive.sh wait-vended`,
   then arm the setting: `script/ax_drive.sh press --role AXCheckBox --contains
   "Autopilot"`. Baseline (ground truth — `autopilot_proposals` no longer
   exists as a table, SP-D0 dropped it forward-only, so the baseline is the
   ghost count, the same query `cull-029`'s Step 2 uses):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # GHOST0 (expect 0)
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # GEN0 (write signal)
   ```
2. **Import the fixture** (drives the whole Import Path flow — path field →
   Review Import → the primary button ("Import N Photos"); Autopilot-after-import is seeded from the armed
   setting):
   ```bash
   ./script/submit_import_path.sh Teststrip "$IMP"
   ```
3. **Wait for the imported set to evaluate and autopilot to run.** Poll until
   ghosts appear:
   ```bash
   for i in $(seq 1 60); do g=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"); [ "$g" -gt "$GHOST0" ] && break; sleep 2; done
   ```
   Also expect the banner: `script/ax_drive.sh wait --role AXStaticText
   --contains "Autopilot"`.
4. **Assert ghosts exist, each landed as a *tentative, unconfirmed* write,
   and the grid badges are provisional (items 52-53).** In the Grid lens,
   for each imported asset carrying a ghost, assert the grid cell shows a
   KEEP or CUT badge matching the ghost's own flag value
   (`ax_drive.sh find --contains "KEEP"` / `"CUT"` scoped near that tile —
   scroll it into view first per the README's virtualized-grid gotcha):
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets
     WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # > GHOST0
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # > GEN0 (the run's own tentative writes)
   ```
   The ghost query above already **is** the tentative-write cross-check — a
   ghost is by definition `metadata_json.flag` set with `aiUnconfirmedFields`
   containing `flag` (`AutopilotGhost.kind(in:)`), not yet a confirmed
   verdict and not yet synced to any `.xmp` sidecar. There is no separate
   join needed the way the pre-drop `autopilot_proposals` table required.
   The grid badge itself reads the ghost directly
   (`AutopilotBadgePresentation.badge(for: AutopilotGhost.kind(in:
   asset.metadata))`) — no table is consulted anywhere in this render path.
5. **Banner Dismiss (item 52), not the review path.** Before opening review,
   click the banner's "Dismiss" (`ax_drive.sh press --role AXButton --contains
   "Dismiss"` scoped to the banner, not the review toolbar which doesn't exist
   yet at this point). Assert the banner disappears
   (`ax_drive.sh find --contains "Autopilot"` in the banner region now fails)
   but the ghosts and `SUM(catalog_generation)` are unchanged — dismissing the
   banner only clears `model.autopilotRunSummary`
   (`dismissAutopilotRunSummary`); it does not touch `autopilotGhostAssetIDs`,
   remove any ghost, or write anything:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"   # unchanged from step 4
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # unchanged from step 4 (already > GEN0 from the run's own tentative writes; Dismiss adds no further write)
   ```
   The grid badges (item 53) must still render — they read the ghost
   directly via `AutopilotGhost.kind(in:)`, not through the banner.
6. **Review is reachable after Dismiss — the open question this card used to
   flag is resolved.** Dismissing the banner only clears
   `model.autopilotRunSummary`; it leaves `autopilotGhostAssetIDs` (and the
   ghosts themselves) untouched, so the sidebar's "AI Suggestions" row
   (`LibrarySource.autopilotSuggestions`, `LibrarySource.swift:48,89`) stays
   present and clickable — pressing it drives `selectSidebarRow(_:)`
   (`AppModel.swift:4701`) → `selectSource(_:)` (`AppModel.swift:4764`) →
   `applySource`'s `.autopilotSuggestions` case →
   `applyAutopilotSuggestionsScope()` (`AppModel.swift:9782`), which sets
   `isAutopilotReviewActive = true` and narrows the grid to the ghost-
   carrying assets without touching the lens — a banner Dismiss is **not**
   a one-way door to Review; it is simply one of three independent entry
   points into that review state (the standalone banner's own "Review"
   button and `cullCompletionStage`'s folded banner both instead call
   `beginAutopilotReview()`, `AppModel.swift:9773`, which additionally
   switches to the Grid lens; neither is re-driven here). ⌘1 for Cull,
   then click the sidebar row: `script/ax_drive.sh press --contains
   "AI Suggestions"`; then `script/ax_drive.sh wait --role
   AXStaticText --contains "Reviewing"`.
7. **Batch-select a subset (not all) of the ghost-carrying assets** in the
   grid (shift-click or ⌘-click per whatever the grid's multi-select gesture
   is).
8. **Commit selected (item 54, partial commit).**
   `script/ax_drive.sh press --role AXButton --contains "Commit"` matching the
   "Commit N" button (N = selection count, not the full ghost count —
   distinguish from "Commit all N" by exact label). The selected assets'
   `metadata_json.flag`/keyword already reflected the ghost tentatively
   (step 4); Commit is what *confirms* it — assert only the selected assets'
   `aiUnconfirmedFields` no longer contains `flag` (and their `catalog_generation`
   bumps again, and their `.xmp` sidecar now reflects the value), while the
   unselected assets in the run stay tentative/unconfirmed (`aiUnconfirmedFields`
   still contains `flag`, no sidecar):
   ```bash
   sqlite3 "$DB" "SELECT id, catalog_generation, json_extract(metadata_json,'\$.flag'), json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id IN (<all imported ids>);"
   ```
9. **Commit all remaining.** `script/ax_drive.sh press --role AXButton
   --contains "Commit all"`. Assert the remaining (previously unselected)
   assets are now also written:
   ```bash
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # GEN1 > GEN0
   ```
10. **Undo all.** `script/ax_drive.sh press --role AXButton --contains "Undo all"`.
11. **Assert undo reverted the committed writes**:
    ```bash
    sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # generations settle back
    ```

## Expected
- Step 3: the ghost count becomes > `GHOST0` and the banner appears within
  ~120s. **Fails if** it stays at `GHOST0` or an error alert shows.
- Step 4: ghost count > `GHOST0`, `SUM(catalog_generation)` > `GEN0` (the
  run's own tentative writes), every ghost-carrying asset's
  `metadata_json.flag` is already set with `aiUnconfirmedFields` containing
  `flag` and no `.xmp` reflects it yet, and every ghost-carrying asset's grid
  cell shows the matching KEEP/CUT badge. **Fails if** a ghost's `flag` is
  set without `aiUnconfirmedFields` containing `flag` (a tentative verdict
  silently landed as confirmed — report immediately, do not soften it), if a
  sidecar already exists for it, or a badge doesn't match the ghost's own
  flag value.
- Step 5: banner Dismiss hides the banner but changes nothing further in the
  catalog (the ghost count and the generation sum are unchanged from step 4)
  and the grid badges persist. **Fails if** Dismiss clears any ghost, writes
  any metadata, or also clears the grid badges.
- Step 6: the "AI Suggestions" sidebar row is present and clickable
  after Dismiss, and clicking it reaches "Reviewing N proposals" with N ≥ 1.
  **Fails if** the row is absent, disabled, or clicking it fails to open
  review — that would mean Dismiss really is a one-way door, contradicting
  Source's resolution of the prior open question.
- Step 8: "Commit N" (N = current selection) confirms only the selected
  assets — their `aiUnconfirmedFields` drops `flag` and their `.xmp` now
  reflects the value, while unselected assets in the same run stay
  tentative/unconfirmed. **Fails if** the partial commit confirms every
  ghost instead of just the selection (Commit selected and Commit all
  behave identically — the commit scoping is broken).
- Step 9: `GEN1 > GEN0` after "Commit all N" confirms the rest (note this
  inequality was already true after step 4's tentative writes — it does not
  by itself prove Commit did anything; the `aiUnconfirmedFields`/sidecar
  checks in steps 4 and 8 are the load-bearing assertions).
- Step 11: the generation sum settles back toward `GEN0` (Undo reverted both
  the run's tentative writes and any confirmed commits). Quote `GEN0`, the
  post-step-8 sum, `GEN1`, and the final sum side by side.
- **Dismiss (review toolbar), documented but not driven live by this card**:
  `dismissAutopilotProposals(assetIDs:)` (`AppModel.swift:9854`) records
  `removed_ai_labels` for each dismissed ghost's flag value and writes no
  sidecar — the same recorded-removal mechanism a direct `U` on a tentative
  flag uses (source-verified; this card never presses "Dismiss selected"
  live, only banner Dismiss and Commit — see Sharp edges for the gap and
  `cull-029-autopilot-ghost-derivation.md`'s Step 6 P0 leg for the
  equivalent `U`-based coverage of the same underlying gesture).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the app instance you launched. Leave any pre-existing Teststrip untouched.

## Sharp edges
- **An on-demand "run autopilot" gesture does exist** — Culling ▸ Run
  Autopilot, wired to `runAutopilotOnCurrentScope()` and driven by
  `app-012-autopilot-evaluate-commands.md` — but this card exercises the
  *other* entry point: the post-import armed run (`runArmedImportAutopilot`,
  over the imported set). Toggling "Autopilot on" by itself does not trigger a
  run on a static catalog — it only arms the next import; Import remains this
  card's trigger.
- Ground truth uses `SUM(catalog_generation)` as a coarse write signal because
  the `--smoke` seed already populates ratings/flags on every asset, which
  makes a "rating IS NOT NULL" check vacuous. A generation bump means *some*
  metadata changed — but under the auto-apply-with-provenance model the run
  itself causes a bump the moment it applies its tentative proposals (step 4),
  and Commit causes a *second* bump per confirmed asset (step 8). The
  generation sum alone can't distinguish "tentative" from "confirmed"; the
  `aiUnconfirmedFields` and `.xmp`-existence checks in steps 4/8 are what
  actually prove the confirm-only-on-Commit invariant, not the generation sum.
- Autopilot proposes only over frames that have evaluations. The imported set
  auto-evaluates because "Read imported frames" defaults on; if proposals stay
  0, confirm the import finished (`SELECT count(*) FROM assets` grew) and give
  evaluation time to drain before concluding failure.
- **Resolved (step 6): Review stays reachable after the banner's Dismiss.**
  There are three independent paths into review state — the standalone
  banner's Review button and `cullCompletionStage`'s folded banner both
  call `beginAutopilotReview()` (`AppModel.swift:9773`, which additionally
  switches to the Grid lens); the sidebar's "AI Suggestions" row
  (`LibrarySource.autopilotSuggestions`, `LibrarySource.swift:48,89`) is
  the third, reaching the same review state via `selectSidebarRow(_:)` →
  `selectSource(_:)` → `applyAutopilotSuggestionsScope()`
  (`AppModel.swift:4701,4764,9782`) without touching the lens. Dismissing
  the banner only clears `model.autopilotRunSummary`
  (`dismissAutopilotRunSummary`) — it never touches `autopilotGhostAssetIDs`
  or any ghost, so the sidebar row (present whenever `autopilotGhostCount >
  0`, `UnifiedSidebarPresentation.swift:179-187`) survives Dismiss and stays
  clickable. Items 52 (Dismiss) and 54 (Review→Commit) are **not** mutually
  exclusive; one sequential import run (steps 1-11 as ordered above)
  exercises both without a second import.
- "Commit N" / "Dismiss selected" in the review toolbar are both disabled
  when the batch selection is empty (`.disabled(selectedIDs.isEmpty)`) —
  don't forget to select before asserting those buttons are pressable.
- **This card never drives "Dismiss selected" live**, despite its own title
  promising "review (selected/all), commit, dismiss, undo" — Steps 1-11
  only ever exercise Commit selected/Commit all/Undo all. Real coverage gap,
  not a card-authoring shortcut: a future revision should add a leg that
  seeds a second batch of ghosts, presses "Dismiss selected" on a subset,
  and asserts `removed_ai_labels` gains one row per dismissed ghost's flag
  value with no sidecar written (see the new Expected bullet above for the
  source-verified fact this leg would pin).

## Run status
NOT RUN AGAINST THE RECONCILED CONTENT — reconciled 2026-07-15 to the
auto-apply-with-provenance model (`people-020-ai-label-provenance.md`, which
flagged this card as stale on exactly this point): the run's tentative
pick/reject proposals now write to `metadata_json` immediately, `origin=ai`
(unconfirmed), and Commit is what confirms them (not the first write) —
steps 4/5/8 and their Expected bullets, plus the Sharp edges note on
`SUM(catalog_generation)`, were rewritten to match; the banner/badge/menu
composition and Dismiss-hides-nothing-but-the-summary behavior are
unaffected. Supersedes prior status: an earlier UNRUN note (source-read
2026-07-10) covered the *old* confirm-before-write framing — not valid
evidence for this revision. Needs a human-present re-run.

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: rewritten
wholesale to ghost ground truth. `autopilot_proposals` no longer exists as a
table (SP-D0 dropped it forward-only) — every `SELECT ... FROM
autopilot_proposals` query (baseline, poll loop, and the Step 4 cross-check)
became the ghost query `EXISTS (SELECT 1 FROM
json_each(metadata_json,'$.aiUnconfirmedFields') WHERE value='flag')`, the
same predicate `cull-029-autopilot-ghost-derivation.md` pins; the grid
badge's source changed from `autopilotProposalDecision(for:)` (deleted) to
`AutopilotGhost.kind(in: asset.metadata)` (Steps 4-5). Step 6's prior open
question — "is Review reachable after Dismiss" — is **resolved**: the Cull
sidebar's "Autopilot Proposals" source is a third, independent entry point
into `beginAutopilotReview()` that Dismiss never disturbs, so Step 6 now
drives that route directly instead of speculating about a two-import
workaround; Steps 7-11 renumbered down by one to absorb the merge of the
old "open review" step into the new Step 6. Added an Expected bullet and a
Sharp-edges gap note documenting that `dismissAutopilotProposals` now
records `removed_ai_labels` (behavior change 6 of the ghost-derivation
spec) — this card still doesn't drive "Dismiss selected" live, a real
pre-existing gap this reconciliation surfaced rather than closed.
**Supersedes prior status**: the 2026-07-15 reconciliation above, and any
run against it, predates the `autopilot_proposals` drop and the sidebar
Review route — not valid evidence for this revision. Needs a fresh VM run.

**Reconciled 2026-08-09 (Task 13, unified-shell preamble sweep)**: Steps 1's
and 135's ⌘1 presses are unchanged in effect (⌘1 selects the Cull lens under
`LibraryLens`). Found and fixed one substantive stale reference beyond the
mechanical preamble: Step 4 said "In Library workspace" — the two-workspace
`Workspace` enum's Library case, which no longer exists — corrected to "In
the Grid lens" (this step doesn't press a key to get there; it just
describes checking the grid cells, which render in the Grid lens after the
import lands). Supersedes prior status: the 2026-08-06 ghost-derivation
reconciliation above is unaffected — it never depended on workspace naming
— but still needs a fresh VM run per its own text.

**Reconciled 2026-08-09 (Task 13 review fix, second pass)**: the sweep above
marked this whole card `Reconciled` while Step 6 was still stale — a task
review caught it. Step 6 (its body, its Expected bullet, and the Sharp-edges
"Resolved" note) cited three symbols that don't exist anywhere in `Sources/`
(`cullSourcePresentation`, `CullSource.Target.autopilotProposals`,
`activateCullSource`), a bogus line citation (`AppModel.swift:5858-5859` is
unrelated code inside `compareGroupKind`), and drove
`ax_drive.sh press --contains "Autopilot Proposals"` against a label the live
UI has not rendered since before this push's base commit — the row is titled
**"AI Suggestions"** (`LibrarySource.autopilotSuggestions`,
`LibrarySource.swift:48,89`). Rewrote Step 6 and the Sharp-edges note to cite
the real chain: the sidebar row presses through `selectSidebarRow(_:)`
(`AppModel.swift:4701`) → `selectSource(_:)` (`AppModel.swift:4764`) →
`applySource`'s `.autopilotSuggestions` case →
`applyAutopilotSuggestionsScope()` (`AppModel.swift:9782`), a second,
independent path into review state alongside `beginAutopilotReview()`
(`AppModel.swift:9773`, the banner Review button's and
`cullCompletionStage`'s path) — the sidebar route sets
`isAutopilotReviewActive` without touching the lens, per
`applyAutopilotSuggestionsScope()`'s own doc comment. `--contains "AI
Suggestions"` replaces the dead AX label; kept as a `--contains` match per
the house convention for pressing a sidebar row (`cull-015-sidebar-
sources.md`'s Step 3, `import-011-completion-toast-and-import-rows.md`'s
skipped-files row press), since the string is unique in the live UI
(verified: `grep -rn "AI
Suggestions" Sources/` has exactly one live title definition plus one doc
comment; the only other live string containing it, "Review AI Suggestions",
was itself deleted — confirmed absent by `cull-025`/`cull-029`'s own
expect-not-found assertions). Also re-verified every other symbol/line
citation in the card while at it, not just Step 6, per the same "citations
drift 30-160 lines" hazard: found and fixed a second, independent problem —
five more `AppModel.swift`/`LibraryGridView.swift` citations in the card's
own opening paragraph and Pre-state bullet (`runAutopilot`,
`applyTentativeAutopilotProposals`, `dismissAutopilotRunSummary`,
`commitAutopilotProposals`, `dismissAutopilotProposals`, the
`AutopilotBannerView`/`AutopilotBadgePresentation` line ranges, and the
`AssetGridCell`/`AssetGridCellAccessibilityValue` wiring sites) were stale by
87-112 lines, all corrected against current source. The symbols themselves
were already correct; only the line numbers had drifted. Steps 1-5, 7-11,
the remaining Sharp-edges bullets, and the two Run-status notes above are
otherwise unaffected and left as written — this reconciliation touches only
citations, not claims.
**Supersedes prior status**: the "Task 13, unified-shell preamble sweep" note
directly above marked the whole card reconciled without checking Step 6 —
that clearance did not cover Step 6's dead symbols, wrong AX label, or the
line-citation drift found here; this note is what actually clears them.
Needs a fresh VM run.
