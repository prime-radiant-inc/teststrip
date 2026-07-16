# cull-017-autopilot-review: Autopilot proposes, badges the grid, you review (selected/all), commit, dismiss, undo

**What this covers**: as a photographer who just imported a shoot with
Autopilot armed, I want machine-proposed keeps/cuts surfaced as provisional
grid badges I can scan, then either commit them (selected subset or all) or
dismiss/undo. Covers the design-1b autopilot loop merged at migration 17 —
`runAutopilot` (`AppModel.swift:9061`) → provisional `autopilot_proposals`
rows, plus (per the later auto-apply-with-provenance model,
`applyTentativeAutopilotProposals`, `AppModel.swift:9131`) each proposed
asset's tentative pick/reject already written into `metadata_json.flag`,
tagged `origin=ai` (`aiUnconfirmedFields` contains `flag`) — the `AutopilotBannerView`
Review/Undo-all/Dismiss controls (item 52 —
`LibraryGridView.swift:3356-3441`, `AppModel.swift:9243`
`dismissAutopilotRunSummary`) → grid-cell KEEP/CUT badges from
`AutopilotBadgePresentation.badge(for:)` (item 53 —
`LibraryGridView.swift:3319-3329`, wired via `autopilotDecision:` on
`AssetGridCell` at `:3311`) → the review toolbar's Commit selected / Commit
all / Dismiss selected controls, `commitAutopilotProposals`
(`AppModel.swift:9289`) being the gesture that *confirms* the tentative
writes rather than first-writing them (item 54 —
`LibraryGridView.swift:2360-2394`). The load-bearing assertion is now the
**auto-apply-with-provenance** invariant, not confirm-before-write: a run's
keep/cut proposals land in `metadata_json` immediately, `origin=ai`
(unconfirmed) and never synced to the `.xmp` sidecar; an explicit Commit is
what confirms them (flips to `origin=user`, writes the sidecar); Undo all
must revert the run's tentative writes back to the pre-run state. (See
`people-020-ai-label-provenance.md`, which drives this same mechanism
end-to-end and flagged this card as stale on this one point.)

## Pre-state
- **This card drives the post-import armed-Autopilot path, not the on-demand
  gesture.** `runAutopilot` (`AppModel.swift:9061`) has two entry points: an
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
   "Autopilot"`. Baseline (ground truth):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                       # PROP0 (expect 0)
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"          # GEN0 (write signal)
   ```
2. **Import the fixture** (drives the whole Import Path flow — path field →
   Review Import → the primary button ("Import N Photos"); Autopilot-after-import is seeded from the armed
   setting):
   ```bash
   ./script/submit_import_path.sh Teststrip "$IMP"
   ```
3. **Wait for the imported set to evaluate and autopilot to run.** Poll until
   proposals appear:
   ```bash
   for i in $(seq 1 60); do p=$(sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"); [ "$p" -gt 0 ] && break; sleep 2; done
   ```
   Also expect the banner: `script/ax_drive.sh wait --role AXStaticText
   --contains "Autopilot"`.
4. **Assert proposals exist, each landed as a *tentative, unconfirmed* write,
   and the grid badges are provisional (items 52-53).** In Library workspace,
   for each imported asset with a pick/reject proposal, assert the grid cell
   shows a KEEP or CUT badge matching `autopilot_proposals.kind`
   (`ax_drive.sh find --contains "KEEP"` / `"CUT"` scoped near that tile —
   scroll it into view first per the README's virtualized-grid gotcha):
   ```bash
   sqlite3 "$DB" "SELECT asset_id, kind FROM autopilot_proposals WHERE run_id = (SELECT run_id FROM autopilot_proposals ORDER BY created_at DESC LIMIT 1);"
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                        # > PROP0
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # > GEN0 (the run's own tentative writes)
   ```
   Cross-check: every asset in the run with a pick/reject proposal already has
   `metadata_json.flag` set to that proposal's value, but tagged `origin=ai`
   (`aiUnconfirmedFields` contains `flag`) — this is the run's own tentative
   write, not yet a confirmed verdict, and not yet synced to any `.xmp`
   sidecar:
   ```bash
   sqlite3 "$DB" "SELECT a.id, json_extract(a.metadata_json,'\$.flag') FROM assets a
     JOIN autopilot_proposals p ON p.asset_id = a.id AND p.kind IN ('pick','reject')
     WHERE EXISTS (SELECT 1 FROM json_each(a.metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
   ```
   The grid badge itself still reads `autopilot_proposals` directly
   (`autopilotProposalDecision(for:)`), independent of the tentative
   `metadata_json` write — so the badge assertion above is unaffected by this
   card's reconciliation, only the "nothing written yet" framing was wrong.
5. **Banner Dismiss (item 52), not the review path.** Before opening review,
   click the banner's "Dismiss" (`ax_drive.sh press --role AXButton --contains
   "Dismiss"` scoped to the banner, not the review toolbar which doesn't exist
   yet at this point). Assert the banner disappears
   (`ax_drive.sh find --contains "Autopilot"` in the banner region now fails)
   but `autopilot_proposals` rows and `SUM(catalog_generation)` are
   unchanged — dismissing the banner only hides the summary UI
   (`dismissAutopilotRunSummary`), it does not delete proposals or write
   anything:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM autopilot_proposals;"                        # unchanged from step 4
   sqlite3 "$DB" "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"           # unchanged from step 4 (already > GEN0 from the run's own tentative writes; Dismiss adds no further write)
   ```
   The grid badges (item 53) must still render — they read `autopilot_proposals`
   directly via `autopilotProposalDecision(for:)`, not through the banner.
6. **Re-run is not available from a dismissed banner** — relaunch is overkill
   for a card; instead accept the banner is gone for the rest of this run and
   drive review directly via whatever affordance opens it (grep confirmed
   `beginAutopilotReview()` is only wired from the banner's Review button and
   from `cullCompletionStage`'s folded banner — if the plain banner is gone,
   the review path may only be reachable by not dismissing it. **Reorder the
   card in practice**: run steps 4-6 non-destructively (inspect only, don't
   dismiss), THEN branch: dismiss-and-verify-nothing-changes as one leaf,
   separately open Review as another leaf, on two independent runs of steps
   1-4 if the driving agent finds Dismiss is a dead end once clicked. Note
   this ordering risk explicitly when actually driving the card.
7. **Open review (undismissed banner).** `script/ax_drive.sh press --role
   AXButton --contains "Review"`; then `script/ax_drive.sh wait --role
   AXStaticText --contains "Reviewing"`. Batch-select a subset (not all) of
   the proposed assets in the grid (shift-click or ⌘-click per whatever the
   grid's multi-select gesture is).
8. **Commit selected (item 54, partial commit).**
   `script/ax_drive.sh press --role AXButton --contains "Commit"` matching the
   "Commit N" button (N = selection count, not the full proposal count —
   distinguish from "Commit all N" by exact label). The selected assets'
   `metadata_json.flag`/keyword already reflected the proposal tentatively
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
- Step 3: `autopilot_proposals` becomes > 0 and the banner appears within ~120s.
  **Fails if** proposals stay 0 or an error alert shows.
- Step 4: proposals > `PROP0`, `SUM(catalog_generation)` > `GEN0` (the run's
  own tentative writes), every proposed pick/reject asset's `metadata_json.flag`
  is already set but `aiUnconfirmedFields` contains `flag` and no `.xmp`
  reflects it yet, and every proposed asset's grid cell shows the matching
  KEEP/CUT badge. **Fails if** a proposed asset's `flag` is set without
  `aiUnconfirmedFields` containing `flag` (a tentative verdict silently landed
  as confirmed — report immediately, do not soften it), if a sidecar already
  exists for it, or a badge doesn't match `autopilot_proposals.kind`, or a
  `keyword`-kind proposal wrongly shows a KEEP/CUT badge (source says keyword
  proposals carry no badge).
- Step 5: banner Dismiss hides the banner but changes nothing further in the
  catalog (proposal rows and the generation sum are unchanged from step 4)
  and the grid badges persist. **Fails if** Dismiss deletes proposal
  rows, writes any metadata, or also clears the grid badges.
- Step 7: "Reviewing N proposals" appears with N ≥ 1.
- Step 8: "Commit N" (N = current selection) confirms only the selected
  assets — their `aiUnconfirmedFields` drops `flag` and their `.xmp` now
  reflects the value, while unselected assets in the same run stay
  tentative/unconfirmed. **Fails if** the partial commit confirms every
  proposal instead of just the selection (Commit selected and Commit all
  behave identically — the commit scoping is broken).
- Step 9: `GEN1 > GEN0` after "Commit all N" confirms the rest (note this
  inequality was already true after step 4's tentative writes — it does not
  by itself prove Commit did anything; the `aiUnconfirmedFields`/sidecar
  checks in steps 4 and 8 are the load-bearing assertions).
- Step 11: the generation sum settles back toward `GEN0` (Undo reverted both
  the run's tentative writes and any confirmed commits). Quote `GEN0`, the
  post-step-8 sum, `GEN1`, and the final sum side by side.

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
- **Open question (step 6): whether Review is still reachable after the
  banner's Dismiss.** `beginAutopilotReview()` appears wired only from the
  standalone banner's Review button (`LibraryGridView.swift:2296-2301`) and
  the folded banner inside the completion stage
  (`LibraryGridView.swift:3582-3587`) — not from anywhere else. If Dismiss
  genuinely removes the only path to Review for that run, items 52 (Dismiss)
  and 54 (Review→Commit) may be mutually exclusive per run and this card's
  steps 5-11 need two separate import runs rather than one sequential run.
  Flagging for the runner rather than guessing; resolve empirically on first
  execution and fix the step ordering here if so.
- "Commit N" / "Dismiss selected" in the review toolbar are both disabled
  when the batch selection is empty (`.disabled(selectedIDs.isEmpty)`) —
  don't forget to select before asserting those buttons are pressable.

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
