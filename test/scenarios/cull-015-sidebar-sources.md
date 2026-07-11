# cull-015-sidebar-sources: Cull sidebar's "Cull From" source groups (zero-count omission, "Nothing to cull" empty state)

**What this covers**: As a photographer culling a shoot I want to jump
straight into a specific working set — recent import, autopilot proposals
awaiting review, the review queues, or my current Library selection — from
the Cull sidebar without manually rebuilding a filter each time, and I want
zero-count groups to simply not appear (not render disabled) so the sidebar
never shows a dead-end row; when every source is empty I want an honest
"Nothing to cull" message instead of a blank list. Covered inventory items
41-45 (group presence-by-count, activation semantics, proposals-row
conditional visibility, diagnostics rows folded into the main list, stack
list decided-checkmarks). Source: `CullSidebarView` at
`Sources/TeststripApp/CullSidebarView.swift` (source groups `:45-47`, row
rendering `:53-66`, empty-state text `:16-19`, stack list `:28-35,76-124`),
`activateCullSource`/`cullSourcePresentation`/`CullSourcePresentation.
visibleSources`/`.isEmpty` at `Sources/TeststripApp/AppModel.swift`.

**Task 7 revision (2026-07-11)**: the former separate `DisclosureGroup(
"Diagnostics", ...)` is gone. Its six rows now render as an ordinary group
(`.diagnostics`) inside the same `"Cull From"` section as every other
group, filtered by the same zero-count-omission rule — because they are
click-to-cull review queues (Rejects/Five Stars/Needs Keywords/Faces
Found/OCR Found/Analysis Failures), not background-job status, they were
**not** moved into the Activity popover (see `activity-003` for why: the
popover's jobs/sources/conflicts sections have no equivalent for
catalog-content review queues — moving them there would have silently
dropped their click-to-cull navigation). Also: rows are **omitted** at
count 0 rather than rendered `disabled` — the previous `.disabled(source
.count == 0)` behavior is gone; `CullSourcePresentation.visibleSources`
filters `count > 0` and the section shows literal text "Nothing to cull"
when `.isEmpty` is true across every group.

**Exact group set and predicates** (read from source, corrects any guessed
predicates): six groups rendered in this fixed order —
`.recentImport`, `.autopilotProposals`, `.topPicks`, `.needsEyes`,
`.diagnostics`, `.selection` (`CullSidebarView.swift:45-47`) — each filtered
through `presentation.visibleSources` (count > 0 only). `cullSourcePresentation`
(`AppModel.swift`) builds:
- `.recentImport`: present only if `latestImportCompletionSummary != nil`
  (title/count from that summary) — **absent entirely** on a bare `--smoke`
  launch with no in-session import, not just disabled.
- `.autopilotProposals`: present only if `!pendingAutopilotProposals.isEmpty`
  — same "absent, not disabled" pattern; title always "Autopilot Proposals".
- `.topPicks`: always two rows, `ReviewQueue.picks` and `.potentialPicks`,
  count from `reviewQueueCounts[queue]`.
- `.needsEyes`: always two rows, `.likelyIssues` and `.needsEvaluation`.
- `.diagnostics`: six rows — `.rejects`, `.fiveStars`, `.needsKeywords`,
  `.facesFound`, `.ocrFound`, `.providerFailures` — now rendered inline, not
  behind a disclosure triangle.
- `.selection`: always one row, count = `selectedBatchAssetIDs.count` if
  non-empty else `1` if a single asset is selected else `0`.
- **Activation** (`activateCullSource`): `.recentImport` →
  `beginCullingFromLatestImportCompletion()`; `.autopilotProposals` →
  `beginAutopilotReview()` (routes into the confirm-before-write review
  flow, **not** a culling session — nothing is written by clicking it);
  `.reviewQueue(queue)` (topPicks/needsEyes/diagnostics rows) →
  `applyReviewQueue(queue)` then `beginCullingSession(named:)`;
  `.selection` → `cullCurrentSelection()`.
- Stack list: rendered only `if !stackEntries.isEmpty` from
  `model.cullingStackListEntries()` — **`--smoke` has no persisted stacks**
  per `test/scenarios/README.md`, so this section is expected absent on
  `--smoke`; this card notes that as untestable-without-fixture rather than
  asserting it.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
script/ax_drive.sh press --role AXButton --help "Cull" # ⌘1
```

## Steps
1. Confirm `.recentImport` and `.autopilotProposals` rows are **absent**
   (not merely disabled) on a bare `--smoke` launch with no in-session
   import or autopilot run:
   ```bash
   script/ax_drive.sh find --contains "Autopilot Proposals"   # expect not-found
   ```
   This is the negative-assertion pattern the assignment calls out — a
   `find` that must fail is the point, don't soften it into "don't check".
2. For each row expected present (`Top Picks`, `Potential Picks`, `Likely
   Issues`, `Needs Evaluation`, any of the six Diagnostics rows with a
   nonzero count, `Selection`), compute ground truth via the review-queue's
   real predicate. Read `ReviewQueue`'s predicate definitions (`grep -n
   "case .picks\|case .potentialPicks\|case .likelyIssues\|case
   .needsEvaluation\|case .rejects\|case .fiveStars\|case .needsKeywords\|
   case .facesFound\|case .ocrFound\|case .providerFailures"
   Sources/TeststripApp/AppModel.swift` or wherever `ReviewQueue` lives)
   before writing the SQL — do not guess a predicate. For each row, assert
   the rendered count text matches the query result, and separately assert
   that any row whose query result is 0 does **not** render at all (find
   returns not-found, not a disabled button — the sidebar omits, never
   disables):
   ```bash
   script/ax_drive.sh find --role AXButton --contains "Top Picks"
   ```
3. Click a non-zero-count `.topPicks` or `.needsEyes` row (`Selection` is
   simplest — select 1-2 assets in the grid first so its count is nonzero):
   ```bash
   script/ax_drive.sh press --contains "Selection"
   ```
   Assert the grid/loupe scope narrows to exactly that source's asset set —
   cross-check the visible/scoped asset ids against the same predicate used
   for the count in step 2 (for `.selection`, the ids you selected).
4. Confirm the (former) Diagnostics rows now render inline in the same
   `"Cull From"` section, with no disclosure triangle to expand:
   ```bash
   script/ax_drive.sh find --role AXDisclosureTriangle --contains "Diagnostics"  # expect not-found
   ```
   For whichever of the six rows has a nonzero count on this fixture, assert
   it renders directly in the list (`Rejects`, `Five Stars` or whatever
   `.fiveStars.presentation.title` actually renders as — read
   `ReviewQueue.presentation` before asserting literal titles, `Needs
   Keywords`, `Faces Found`, `OCR Found`, `Analysis Failures` — use the real
   `.presentation.title` strings from source, not these English glosses).
   If every diagnostics predicate is 0 on this fixture, assert none of the
   six appear and note that as the honest untestable-without-fixture outcome
   for the "row renders with a nonzero count" half of this assertion.
5. Assert the stack list section (`"Stacks · Auto-Grouped"`) is **absent**
   on `--smoke`, consistent with the no-persisted-stacks fact:
   ```bash
   script/ax_drive.sh find --contains "Auto-Grouped"   # expect not-found
   ```
   Note this as the honest "untestable on this fixture" outcome for the
   decided-checkmark sub-assertion, rather than skipping the row silently.
6. Force an all-empty state (e.g. a bare `--smoke` launch before any
   evaluation/import work has populated any queue, if such a window exists,
   or a scoped catalog with zero assets) and assert the section shows the
   literal text `"Nothing to cull"` in place of any rows:
   ```bash
   script/ax_drive.sh find --contains "Nothing to cull"
   ```
   If no reachable state makes every source simultaneously empty on this
   fixture, note that as untestable-without-fixture rather than fabricating
   one — the model-level unit tests (`testIsEmptyIsTrueOnlyWhenAllSources
   AreZeroCount`, `CullSourcePresentationTests.swift`) already cover the
   presentation-layer logic directly.

## Expected
- Step 1: both rows absent. **Fails if** either renders with count 0 instead
  of not rendering at all — that would contradict the "present only if
  non-empty" reading of `cullSourcePresentation`.
- Step 2: every present row's count matches its `ReviewQueue` predicate's
  sqlite count, and any zero-count row is absent entirely (not disabled).
  **Fails if** any row's count is off by even one, a nonzero row is missing,
  or a zero-count row still renders (disabled or not).
- Step 3: clicking narrows scope to exactly the source's set — same asset
  ids, no more, no fewer. **Fails if** the click no-ops, or narrows to the
  wrong set.
- Step 4: no disclosure triangle exists; whichever Diagnostics rows have a
  nonzero count render inline in `"Cull From"`, titled per the real
  `ReviewQueue.presentation.title` strings. **Fails if** a disclosure
  triangle still exists, a nonzero row is missing/extra, or titled something
  not read from source.
- Step 5: stack section absent on `--smoke`. Documented as
  untestable-without-fixture for the decided-checkmark rendering itself —
  **not** a pass/fail assertion pending a stack-bearing fixture (see
  `cull-013-filmstrip.md`/`cull-014-stack-rail.md` for the shared gap).
- Step 6: `"Nothing to cull"` renders iff every source is zero-count.
  **Fails if** the text renders while any source has a nonzero count, or
  fails to render when every source is confirmed zero-count.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **`ReviewQueue`'s exact predicates and `.presentation.title`/`.systemImage`
  strings were not read in this pass** — `ReviewQueue` wasn't opened;
  `grep -rn "enum ReviewQueue"` before writing the final SQL/AX-match
  strings for steps 2 and 4. Do not invent title strings.
- Step 3's "grid/loupe scope narrows" assertion depends on exactly what
  `beginCullingSession(named:)`/`cullCurrentSelection()` actually change in
  `model` (scope vs. an explicit asset-id filter vs. a query) — not
  independently traced in this pass; read those functions before writing
  the final ground-truth query, since "scope" here may not map cleanly onto
  `CullScope`.
- This card assumes `latestImportCompletionSummary` stays nil across a bare
  `--smoke` launch (no import happened in-session) — if `--smoke`'s seeder
  itself sets that summary as a side effect (not verified), step 1 would
  need revision; the seeder writes directly to the catalog rather than
  going through the app's import path, so this is believed safe but wasn't
  independently traced through `AppModel`.
- The stack-fixture gap (step 5) is identical to the one flagged in
  `cull-013-filmstrip.md` and `cull-014-stack-rail.md` — all three cards
  need the same real fix (a seed variant that produces either a
  persisted `work-stack-` set or a tight-enough-in-time burst to
  auto-group) before their stack-specific assertions can actually run.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md
