# Global Filter Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use
> superpowers:test-driven-development for every task — failing test first,
> then the smallest implementation that makes it pass. Steps use checkbox
> (`- [ ]`) syntax.

**Goal:** The active library filter scope persists across every view and mode
switch; entering Cull culls within the current filtered set and returning to
Library preserves the filters. Spec:
`docs/superpowers/specs/2026-07-14-global-filter-persistence-design.md`.

**Tech stack:** Swift 6, SwiftPM, SwiftUI/AppKit, XCTest. All work in the
worktree `/Users/jesse/git/projects/teststrip/.worktrees/filter-persistence`
on branch `feat/global-filter-persistence`.

## Global constraints

- **Smallest reasonable change.** Touch only `AppModel.swift` production code
  and add tests. No new UI, no changes to `LibraryGridView.swift`,
  `CullSidebarView.swift`, `SetQuery.swift`, or the source picker.
- **Minimize churn in shared regions** — a parallel People sub-project edits
  `AppModel.swift`. Keep edits localized to `beginCullingSession`,
  `activeCullingSession(repository:)`, `clearLibraryQueryFilters()`, and one
  new stored property. Do not reformat surrounding code.
- **TDD, always.** Failing test first. Assert against catalog/model ground
  truth. Test output must be pristine.
- **Do not clear filters on any bare view/mode switch.**
- Commit at each task boundary with a conventional prefix
  (`test:` / `feat:` / `docs:`).

## Key facts for the implementer (verified in the current code)

- `AppModel.selectWorkspace(_:)` (~line 4507) sets only `selectedView`.
- The Library view toggle and cull sub-view switches set `selectedView`
  directly. None clear filters.
- `beginCullingSession(named:intent:)` (~line 5260): guards `!assets.isEmpty`,
  computes `inputSetID = try cullingInputSetID(...)`, then
  `try applyAssetSet(id: inputSetID)` (which clears filters + switches
  `selectedAssetSetID` + reloads to `.grid`), restores `previousSelection`,
  sets `selectedView = .loupe`, records the activity.
- `cullingInputSetID(...)` (~line 12050) reuses `selectedAssetSetID` when it is
  a manual/snapshot set; otherwise upserts a `work-input-<sessionID>` snapshot
  from `currentAssetScopeIDs(...)` and returns it (already refreshes
  `savedAssetSets` + rebuilds the sidebar).
- `activeCullingSession(repository:)` (~line 11617): returns the session whose
  input/output set matches `selectedAssetSetID`, else the session named by a
  `session:` token in `librarySearchText`, else nil.
- `updateActiveCullingSessionProgressAfterFlagChange()` (~line 11636) and
  `cullingInputAssetIDs(in:)` (~line 11830) compute progress/completion/output
  from the session's **recorded input snapshot**, independent of
  `selectedAssetSetID`.
- `clearLibraryQueryFilters()` (~line 10860) resets all filter fields +
  `detachedLibraryFilterPredicates`. It is called by `applyAssetSet`,
  `applyReviewQueue`, every re-scoping `applySidebarTarget` case,
  `clearLibraryFilters`, `applyEvaluationKindFilter`, etc.
- Test harness: `makeModelWithCatalogAssets(named:assets:)` →
  `(AppModel, CatalogRepository)`; `makeAsset(id:path:rating:…)`. Set filter
  fields, call `applyLibraryFilters()` (== `reload()`), assert `model.assets`.

---

## Task 1 — Lock the view/mode-switch persistence invariant (tests only)

**Files:**
- Add: `Tests/TeststripAppTests/AppModelFilterPersistenceTests.swift`
  (self-contained; give it its own small catalog helper like
  `CullSourcePresentationTests.swift` does, or reuse the in-file pattern).

**Tests (all pass against current code — they are regression guards):**
- `testModeSwitchLibraryToCullToLibraryPreservesFilters`: seed catalog assets
  spanning ratings; set `minimumRatingFilter = 4`, `librarySearchText`,
  `keywordFilterText`, a `librarySortOption`; `applyLibraryFilters()`. Capture
  `assets`, all filter fields, `selectedAssetSetID`, `librarySortOption`.
  `selectWorkspace(.cull)`; assert entering Cull leaves `assets` == the filtered
  set and every field unchanged. `selectWorkspace(.library)`; assert every
  field + `assets` still unchanged.
- `testEnteringCullNavigatesWithinFilteredSet`: with an active
  `minimumRatingFilter`, after `selectWorkspace(.cull)` assert every asset in
  `model.assets` satisfies the filter (rating ≥ 4).
- `testLibraryViewToggleAcrossGridTimelineMapPreservesFilters`: set filters;
  cycle `selectedView = .timeline`, `.map`, `.libraryLoupe`, `.grid`; assert
  filter fields + `selectedAssetSetID` unchanged after each.
- `testModeSwitchToPeoplePreservesFilters`: set filters;
  `selectWorkspace(.people)`; assert filter fields + `selectedAssetSetID`
  unchanged; `selectWorkspace(.library)`; assert still unchanged.

**Commit:** `test: lock library-filter persistence across view/mode switches`.

---

## Task 2 — Whole-scope Cull entry preserves the filter scope

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Add tests to: `Tests/TeststripAppTests/AppModelFilterPersistenceTests.swift`
- Modify: `Tests/TeststripAppTests/AppModelTests.swift`
  (`testBeginningCullingSessionCreatesHiddenInputSetForAdhocSearch`, ~line 9743)

**Failing tests first:**
- `testCullingWholeFilterScopePreservesFiltersAndKeepsSetNil`: seed assets;
  set `librarySearchText`/`minimumRatingFilter` (a pure-filter scope, no
  `selectedAssetSetID`); `applyLibraryFilters()`. `beginCullingSession(named:)`.
  Assert: filter fields **unchanged** (not cleared); `selectedAssetSetID == nil`;
  `selectedView == .loupe`; `assets` still the filtered set; the session's
  recorded `inputSetIDs.first` is a `work-input-*` snapshot of the filtered ids;
  `recentWork.first?.id == session.id`.
- `testCullingWholeFilterScopeTracksProgressToCompletion`: from a pure-filter
  scope with N assets, `beginCullingSession`; pick/reject each via
  `applyCullingCommand`; assert the persisted session reaches `.completed` with
  the right `completedUnitCount` and a picks output set — proving progress is
  discovered via `activeCullingSessionID` while `selectedAssetSetID == nil`.
- `testReturningToLibraryAfterFilterScopeCullShowsLiveFilteredGrid`: after the
  cull, `selectWorkspace(.library)`; assert the filter chips/fields are intact
  and `assets` == the live filtered query (not a frozen snapshot).
- Update `testBeginningCullingSessionCreatesHiddenInputSetForAdhocSearch` to the
  new invariant: after `beginCullingSession` over the ad-hoc search, assert
  `selectedAssetSetID == nil` and the filter fields (`librarySearchText`,
  `minimumRatingFilter`, `flagFilter`) are **preserved**; the hidden
  `work-input-*` input set still exists in the repository and is still excluded
  from the Saved Sets sidebar section; `assets == [keeper.id]`. Drop the manual
  `clearLibraryFilters()` step and re-navigate from the preserved filters.

**Implementation (`AppModel.swift`):**
1. Add `private var activeCullingSessionID: WorkSessionID?` beside the other
   culling-session state.
2. In `beginCullingSession`, replace the unconditional
   `try applyAssetSet(id: inputSetID)` + selection-restore with:
   - if `selectedAssetSetID == nil` (pure filter scope): do **not** call
     `applyAssetSet`; keep filters and `assets`; set `selectedView = .loupe`.
   - else (explicit/dynamic set already selected): keep today's
     `try applyAssetSet(id: inputSetID)` + `if previousSelection in assets
     { selectedAssetID = previousSelection }` + `selectedView = .loupe`.
   - after the branch, set `activeCullingSessionID = sessionID`.
3. In `activeCullingSession(repository:)`, after the `selectedAssetSetID` and
   `activeWorkSessionFilterID` checks, add:
   `if let activeCullingSessionID { let s = try repository.session(id:
   activeCullingSessionID); return s.kind == .culling ? s : nil }`.
4. In `clearLibraryQueryFilters()`, add `activeCullingSessionID = nil`.

Run the full culling test group (`beginCullingSession`, cull-completion,
output-set, resumption, stack-cull) to confirm set-scope culls are unchanged.

**Commit:** `feat: whole-scope cull preserves the live library filter scope`.

---

## Task 3 — Verify + docs

- [ ] `swift build` clean; `swift test` green.
- [ ] `make verify` once near the end.
- [ ] If any behavior described here differs from what shipped, reconcile the
  spec's "Design" section to match the code (docs must not drift).

**Commit:** `docs: note global filter persistence behavior` (if any doc edit).
