# cull-015-sidebar-sources: the sidebar's Smart Collections section (zero-count omission, AI Suggestions, saved dynamic sets)

**What this covers**: As a photographer I want to jump straight into a
review queue — Picks, Rejects, Needs Keywords, autopilot ghosts pending
review, or a saved search — from the sidebar without manually rebuilding a
filter each time, and I want zero-count rows to simply not appear (not
render disabled) so the sidebar never shows a dead-end row.

**The "Cull From" sidebar and `CullSidebarView` are gone.** This push
deleted the Cull-lens-only sidebar entirely — `find . -iname
"CullSidebarView.swift"` finds nothing, and there is no `activateCullSource`/
`cullSourcePresentation`/`CullSourcePresentation` in current source either.
There is now **one sidebar, every lens**, built by `UnifiedSidebarPresentation
.sections(...)` (`Sources/TeststripApp/UnifiedSidebarPresentation.swift:
122-243`) and rendered by `SidebarView`. This card is rewritten to the
**Smart Collections** section, its direct successor for click-to-cull review
queues.

**Exact row set and predicates** (read from source, not guessed):
`UnifiedSidebarPresentation.smartCollectionOrder` (`:104-107`) is a **fixed
10-item order** — `.picks`, `.potentialPicks`, `.likelyIssues`,
`.needsEvaluation`, `.rejects`, `.fiveStars`, `.needsKeywords`,
`.facesFound`, `.ocrFound`, `.providerFailures` — each mapped through
`SmartCollection.presentation.title` (`AppModel.swift:620-644`): "Picks",
"Potential Picks", "Likely Issues", **"Not analyzed yet"** (note: the title
string differs from the enum case name `needsEvaluation` — use the real
string), "Rejects", "5 Stars", "Needs Keywords", "Faces Found", "OCR Found",
"Analysis Failures" (the tenth and last of this fixed order). Building the
section (`sections(...)`, `:178-194`):
- Each of the 10 is filtered by `smartCollectionCounts[collection] > 0`
  (`:180`) — a `compactMap` returning `nil` for a zero/missing count, so a
  zero-count row is **omitted entirely**, never rendered `disabled`.
- `AI Suggestions` (`LibrarySource.autopilotSuggestions`, title fixed at
  `"AI Suggestions"`, `LibrarySource.swift:89`) is appended **after** the 10,
  present only while `autopilotGhostCount > 0` (`:189-196` — the parameter is
  `autopilotGhostAssetIDs.count`, passed in from `AppModel.swift:1993`).
  There is no zero-count disabled state for this row either.
- Every **saved dynamic set** (`AssetSet.isDynamic`, i.e. a saved search)
  joins the section last, one row per set (`:198-200` — "a saved dynamic
  search IS a smart collection — that is exactly what the section header's
  '+ New from search…' produces").
- The whole section (`UnifiedSidebarPresentation.smartCollectionsSectionTitle
  == "Smart Collections"`) is appended to the sidebar **only if** the
  combined row list is non-empty (`:193-194`) — there is no "Nothing to
  cull"/all-empty message any more (`grep -rn "Nothing to cull" Sources/`
  finds zero hits); the section simply does not render.

**Activation.** Clicking a row calls `AppModel.selectSidebarRow(_:)`
(`AppModel.swift:4695`) → `selectSource(_:)`/`applySource(_:)`
(`:4744`,`:4824`), which switches on `LibrarySource.kind`:
`.smartCollection(let collection)` → `applySmartCollection(collection)`
(`:10961-10971` — installs the collection's `query.predicates` as detached
filters and reloads); `.autopilotSuggestions` → `applyAutopilotSuggestionsScope()`
(`:9727-...` — loads `assetIDsWithAutopilotGhost()` directly rather than via
a `SetQuery`). `applySource` then re-resolves the active lens
(`LensRules.resolvedLens`, `LibraryLens.swift:137-144`): selecting
`Analysis Failures` while in the Cull lens forces a fallback to Grid, since
`LibrarySource.isDiagnostic` is true only for `.smartCollection
(.providerFailures)` (`LibrarySource.swift:78-79`) — the same behavior
`app-019-lens-shell.md` Step 7 already drives; this card asserts it again
from the sidebar-contract side rather than duplicating that card's setup.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
```

## Steps
1. Confirm `AI Suggestions` is **absent** (not merely disabled) on a bare
   `--smoke` launch with no autopilot run yet:
   ```bash
   script/ax_drive.sh find --contains "AI Suggestions"   # expect not-found
   ```
   This is the negative-assertion pattern the invariant calls out — a
   `find` that must fail is the point, don't soften it into "don't check".
2. For each of the 10 fixed-order rows, compute ground truth via
   `SmartCollection.query`'s real predicates (`AppModel.swift:645-...` —
   read the actual `SetQuery` for each case before writing SQL; do not
   guess). For each row, assert the rendered count text matches the query
   result, titled per `.presentation.title` (not the enum case name —
   `needsEvaluation` renders as "Not analyzed yet"), and separately assert
   that any row whose query result is 0 does **not** render at all (find
   returns not-found, not a disabled button — the sidebar omits, never
   disables):
   ```bash
   script/ax_drive.sh find --role AXButton --contains "Picks"
   ```
3. Click a non-zero-count row (`Rejects` is simplest on `--smoke`, which
   pre-flags some assets):
   ```bash
   script/ax_drive.sh press --contains "Rejects"
   ```
   Assert the grid/loupe scope narrows to exactly that collection's asset
   set — cross-check the visible/scoped asset ids against
   `SmartCollection.rejects.query`'s predicate run directly against the DB.
4. Force `Analysis Failures` into existence (`--smoke` seeds no provider
   failures) and confirm it renders as the **tenth** row, after all other
   nonzero rows and before `AI Suggestions`/any saved dynamic set:
   ```bash
   ASSET_ID=$(sqlite3 "$DB" "SELECT id FROM assets LIMIT 1;")
   sqlite3 "$DB" "INSERT INTO evaluation_failures (asset_id, provider, message, failed_at, updated_at) VALUES ('$ASSET_ID', 'test-provider', 'synthetic failure', strftime('%s','now'), strftime('%s','now'));"
   ```
   Relaunch or trigger a sidebar refresh, then select `Analysis Failures`
   while in the Cull lens. Assert the app falls back to Grid and the Cull
   lens switcher segment renders `.disabled` with AXHelp `"Nothing here is
   cullable"`:
   ```bash
   script/ax_drive.sh find --role AXButton --label "Cull" --help "Nothing here is cullable"
   ```
5. **AI Suggestions ordering and presence.** With provider failures seeded
   from step 4 (`AI Suggestions` still absent, no autopilot run yet),
   confirm `Analysis Failures` renders but `AI Suggestions` does not. Then
   run autopilot (or otherwise populate `autopilotGhostAssetIDs`) and assert
   `AI Suggestions` now appears, positioned after `Analysis Failures` and
   before any saved dynamic set:
   ```bash
   script/ax_drive.sh find --contains "AI Suggestions"
   ```
6. **Saved dynamic sets join the section.** Save the current search as a
   set via the section header's "+ New from search…" (creates an
   `AssetSet` with `isDynamic == true`). Assert a new row for it appears in
   the Smart Collections section (not the Sets section, which is
   static-membership only), after the fixed 10 and `AI Suggestions`.
7. **All-empty means the section is absent, not a message.** Note: on
   `--smoke` this is expected untestable without a scoped/empty catalog, since
   `--smoke` seeds enough flags/ratings that some of the 10 rows are always
   nonzero. If a reachable state makes every source simultaneously
   zero-count, confirm the whole `"Smart Collections"` header disappears
   from the sidebar rather than rendering with an empty-state message —
   the model-level unit tests already cover
   `sections(...)`'s `if !smartRows.isEmpty` gate directly; document this
   step's outcome (tested or untestable-on-this-fixture) rather than
   fabricating a scoped catalog.

## Expected
- Step 1: `AI Suggestions` absent. **Fails if** it renders with count 0
  instead of not rendering at all.
- Step 2: every present row's count matches its `SmartCollection.query`'s
  sqlite count, titled per `.presentation.title` exactly (not the enum case
  name), and any zero-count row is absent entirely. **Fails if** any row's
  count is off by even one, a nonzero row is missing, mistitled, or a
  zero-count row still renders (disabled or not).
- Step 3: clicking narrows scope to exactly the collection's query result —
  same asset ids, no more, no fewer. **Fails if** the click no-ops, or
  narrows to the wrong set.
- Step 4: `Analysis Failures` is the tenth row (last of the fixed order,
  before `AI Suggestions`/sets); selecting it while in Cull falls back to
  Grid with the documented AXHelp. **Fails if** the row appears out of
  order, the fallback doesn't fire, or the AXHelp text is wrong.
- Step 5: `AI Suggestions` presence tracks `autopilotGhostAssetIDs`
  non-emptiness exactly, and it always renders after the fixed 10. **Fails
  if** it appears with zero ghosts, or renders out of position.
- Step 6: a saved dynamic set appears in Smart Collections, not Sets.
  **Fails if** it's missing, duplicated, or lands in the wrong section.

## Cleanup
```bash
sqlite3 "$DB" "DELETE FROM evaluation_failures WHERE provider = 'test-provider';"
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `SmartCollection.query`'s exact predicates were read from source for this
  revision (`AppModel.swift`, the `query` computed property immediately
  below `presentation`) but the SQL translations for steps 2-3 should still
  be dry-run against a scratch/seeded catalog before trusting a literal
  count, per this task's own verification bar.
- Step 4/5's stack-fixture-style gap does not apply here — `Analysis
  Failures` and `AI Suggestions` are both directly seedable/forceable
  without a stack fixture, unlike the old card's stack-list section (which
  this rewrite drops entirely, since Stacks is not part of Smart
  Collections — it is its own, Cull-only sidebar section; see
  `app-019-lens-shell.md` Step 6 for that contract instead).
- This card intentionally does not re-test the diagnostic-lens-fallback
  mechanism in depth (AXHelp text, `LensRules.resolvedLens`'s general
  shape) — `app-019-lens-shell.md` Step 7 already owns that; this card's
  Step 4 only confirms it fires from a Smart Collections row specifically.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
rewritten wholesale. `CullSidebarView`, `activateCullSource`,
`cullSourcePresentation`, and `CullSourcePresentation` — everything this
card previously cited — were deleted along with the Cull-lens-only sidebar;
`grep -rn "CullSidebarView\|CullSourcePresentation" Sources/` finds nothing.
The successor is `UnifiedSidebarPresentation`'s Smart Collections section,
which this revision verified line-by-line against current source: the fixed
10-item `smartCollectionOrder`, each title from `SmartCollection
.presentation.title` (catching the `needsEvaluation` → "Not analyzed yet"
title mismatch the old card's English glosses would have missed),
`AI Suggestions`'s append-after-the-10 position and its
`autopilotGhostCount > 0` gate, saved dynamic sets joining last, and the
absence of any "Nothing to cull" string anywhere in `Sources/`. Dropped the
former Diagnostics-disclosure-group content (already folded into the flat
list in a prior task, now further folded into Smart Collections rather than
a separate `.diagnostics` group) and the Stack-list section (moved to
`app-019-lens-shell.md`'s scope, since Stacks is Cull-lens-only sidebar
chrome, not a Smart Collection). Supersedes prior status: the entire prior
revision describes a sidebar (`CullSidebarView`, Cull-lens-only, six source
groups including `.recentImport`/`.selection`) that this push deleted along
with the two-workspace shell — none of its predicates, row titles, or
group structure describe current code. The 2026-08-06 SP-D0 note above (on
`autopilotGhostAssetIDs` replacing `pendingAutopilotProposals`) remains
historically accurate but describes a predicate on a type that no longer
exists either. Needs a fresh VM run.
