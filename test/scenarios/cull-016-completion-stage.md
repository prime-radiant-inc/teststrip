# cull-016-completion-stage: deciding all frames shows the end-of-set handoff, Review Picks/Move Rejects/dismiss all work

**What this covers**: as a photographer finishing a cull pass, once every
frame in scope is decided I want a handoff (export / move rejects / review
picks) instead of an empty stage, and I want it to get out of my way again if
I want to keep working. Covers inventory items 46-51:
`CullCompletionPresentation.presentation` (46, gating + five-action set —
`Sources/TeststripApp/CullCompletionPresentation.swift:88-103`, which
delegates the action-set build to `.summary` at `:32-76` — the core four
always, `.savePicksAsSet` appended at `:65-67` only when `picks > 0`),
`applyCullCompletionReviewPicks` (47 — `AppModel.swift:6854-6861`), the
`isCullCompletionDismissed` `onChange` guards on
scope/asset (48 — `LibraryGridView.swift:3924-3925`), the folded
autopilot + `CullingSessionCompletionSummary` banners inside the stage (49 —
`LibraryGridView.swift:3974-3987`), `openCullingSessionPicks` (50 —
`AppModel.swift:5661-5671`), and `cullRemainingSinglesFromCullingCompletion`
(51 — `AppModel.swift:5728-5753`). Also verified: "Move Rejects…" physically
relocates rejected originals on disk, not just in the catalog.

## Pre-state
```bash
./script/build_and_run.sh --smoke   # seeds 24 synthetic photos
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull.
2. Decide all remaining frames (P or X each, advancing with Space) — a
   driver loop is fine here (bulk setup, not the assertion). `--smoke`
   pre-seeds flags on 11 of the 24 (verified 2026-07-10), so only the rest
   need deciding. Confirm via sqlite:
   `SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL;` reads 0.
3. Assert the completion stage renders (item 46): `ax_drive.sh find --contains
   "End of set"` (the stage's `accessibilityLabel`) and `ax_drive.sh find
   --contains "Nothing left to decide"`. **This card is the authoritative
   post-drop completion action set** (verified directly against
   `Sources/TeststripApp/CullCompletionPresentation.swift:9-16,62-67` and
   `LibraryGridView.swift:4009-4028` — see `cull-025-run-strip-completion.md`'s
   "Rendering the summary" bullet, which cites this card's Step 3 as
   authoritative for the action set and keeps its own copy of the five
   titles in sync with it, rather than deriving them independently):
   assert exactly the five titles — "Export", "Move Rejects…",
   "Move Rejects to Trash…", "Review Picks", "Save Picks as Set" — are
   present (`ax_drive.sh find --role AXButton --label "Export"` /
   `--label "Move Rejects…"` / `--label "Move Rejects to Trash…"` /
   `--label "Review Picks"` / `--label "Save Picks as Set"`; the last is
   conditional on `picks > 0`, guaranteed on this fixture — `--smoke`'s flag
   formula, `index.isMultiple(of: 5) ? .reject : (index.isMultiple(of: 3) ?
   .pick : nil)`, seeds several picks among the 24 assets). There is no
   sixth "Continue" *action button* — "Continue culling" is a separate
   plain-style dismiss control below the action row
   (`LibraryGridView.swift:3993-3997`), not a
   `CullCompletionPresentation.Action` case; there is likewise no
   "Review AI Suggestions" action — that ceremony was deleted from the
   source entirely by SP-D0 (`cull-025`'s Source, Actions rule).
4. **Review Picks (item 47).** Click "Review Picks"
   (`ax_drive.sh press --role AXButton --label "Review Picks"`). Assert the
   scope indicator now reads "Picks" and the visible set narrows to picked
   frames only (same scope-cycle assertion pattern as cull-020's step 4):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';"
   ```
5. **Dismissal clears on navigation (item 48).** Cycle scope back to `.all`
   (press `S` three times: Picks→Rejects→All) so completion re-evaluates and
   the stage reappears (it's gated to `.unrated`/`.all` scopes only — see
   Sharp edges). Click "Continue culling"
   (`ax_drive.sh press --role AXButton --label "Continue culling"`); assert
   the stage disappears and the loupe image reappears
   (`ax_drive.sh find --contains "End of set"` now fails). Without changing
   scope or asset, confirm the dismissal *sticks* — re-check
   `find --contains "End of set"` still fails. Then advance one frame with
   any nav key (e.g. `→`) or cycle scope once; assert the stage is showing
   again (`isCullCompletionDismissed` reset by the `onChange` on
   `selectedAssetID`/`cullScope`).
6. Record the rejected originals' paths:
   ```bash
   REJECTS=$(sqlite3 "$DB" "SELECT original_path FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject';")
   ```
7. Click "Move Rejects…" (`ax_drive.sh press --role AXButton --label "Move Rejects…"`),
   complete the destination-folder sheet.
8. Assert on disk: every path in `$REJECTS` no longer exists at its old
   location and exists at the new destination; assert the catalog's
   `original_path` for those rows now points at the new location (relocation,
   not a copy — old path gone).

## Expected
- Step 3: completion stage visible once the last frame is decided, with
  exactly the five-title action row (Export/Move Rejects…/Move Rejects to
  Trash…/Review Picks/Save Picks as Set). **Fails if** a sixth action
  button renders (in particular "Review AI Suggestions" — deleted from the
  source, not gated to absent), or any of the five is missing.
- Step 4: scope indicator and visible set both read Picks-only after Review
  Picks. **Fails if** the scope doesn't change, or the wrong scope is
  selected.
- Step 5: "Continue culling" dismisses the stage and the dismissal survives
  until the next scope/asset change, at which point it reappears. **Fails
  if** the stage never comes back after dismissal (48's `onChange` guard is
  missing/broken), or dismissing on one asset silently dismisses it for
  every asset (scope-wide instead of asset/scope-scoped).
- Step 8: every rejected original is physically moved (old path gone, new
  path exists) and the catalog's `original_path` tracks the move. **Fails
  if** files are copied instead of moved (both paths exist), or the catalog
  still points at the stale path.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Completion is gated to `.unrated`/`.all` scopes only**
  (`CullCompletionPresentation.presentation` `guard scope == .unrated || scope
  == .all`). It is deliberately suppressed in `.picks`/`.rejects` review
  scopes (those scopes exclude unflagged frames by definition, so a naive
  undecided-count check would false-positive there). Step 5's scope cycle
  back to `.all` exists to make the stage reappear for the dismissal check —
  don't skip it.
- **Items 49-51 (folded autopilot/session banners, "View Picks", "Cull
  Remaining Singles") are NOT exercised by this card.** They render only when
  `model.cullingSessionCompletion` (a `CullingSessionCompletionSummary`) is
  non-nil, which is set at `AppModel.swift:12806` — that path is reached from
  a stack-cull work-session flow, not from plain bulk-deciding singles via
  P/X in a fresh `--smoke` launch (confirmed by reading the surrounding code:
  it's set when a *work session* of kind stack-cull completes, not on the
  ad-hoc per-asset flag writes this card performs). This is the same
  persisted-stack/work-session fixture gap noted in `cull-004-stack-promote-return.md`
  and `cull-014-stack-rail.md`: `--smoke` has no persisted stacks, so no
  stack-cull work session exists to complete and populate
  `cullingSessionCompletion`. A follow-up card (or an extension of this one)
  needs whatever fixture/gesture those two cards find for constructing a
  persisted stack, then driving a stack-cull work session to completion, to
  cover `openCullingSessionPicks` (50) and
  `cullRemainingSinglesFromCullingCompletion` (51). Flagging as an open
  question rather than fabricating an untestable step here.
- The autopilot banner is suppressed above the stage once `completion != nil`
  (folded into the stage body instead per `LibraryGridView.swift:3865-3867`
  and `:3975-3977`) — an undismissed banner reappears inside
  `cullCompletionStage`, still with its own Review/Undo all controls.

## Run status
UNRUN since the rename/extension in this revision — the original Move
Rejects/completion-stage assertions (steps 1-3, 6-8) were verified headlessly
by source read on 2026-07-10 against
`Sources/TeststripApp/CullCompletionPresentation.swift:17`,
`Sources/TeststripApp/LibraryGridView.swift:3570-3615` (original line
numbers before this revision's re-read; current numbers cited above),
`:3625` (`Button("Move Rejects…")`). Steps 4-5 (Review Picks, dismissal) are
newly added and have not been dry-run against a live catalog or AX tree.
Needs a human-present re-run, including confirming the `onChange` dismissal
behavior actually matches source (SwiftUI `onChange` ordering can surprise).

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation — this card is now
authoritative)**: Step 3 was rewritten from a stale 3-action assertion
(missing "Move Rejects to Trash…" and "Save Picks as Set", which predate
this task and were never about autopilot) to the full, verified five-title
post-drop action set, cross-referenced from `cull-025-run-strip-completion.md`
so the two cards no longer conflict on what the completion stage's action
row actually contains. The banner-suppression Sharp-edges bullet's citations
were re-verified against the current tree and its speculative
`cull-017-autopilot-review.md`-combination caveat was replaced with the
actual (now-confirmed) behavior: an undismissed banner reappears inside the
completion stage, unaffected by SP-D0. Supersedes prior status: the
2026-07-10 source read predates both the three-action staleness and the
ghost-derivation model. Needs a fresh VM run.
