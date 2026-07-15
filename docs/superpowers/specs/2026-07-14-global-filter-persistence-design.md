# Global Filter Persistence — Design Spec

**Date:** 2026-07-14
**Status:** Decided by Jesse (the WHAT is fixed; this spec designs the HOW)
**Branch:** `feat/global-filter-persistence`

## Decision (Jesse's words)

> "filters should ALWAYS be persistent when switching to any view or mode. if
> i've filtered in the library and go to cull… I still want those filters."

The active library filter set is a **single persistent scope** that carries
across every view (Grid / Loupe / Timeline / Map / People) and every mode
(Library ↔ Cull). Entering Cull culls **within** the current filtered set;
switching back to Library preserves the filters exactly.

## Current model (findings)

- **One shared `assets` array** feeds both the Library grid and the Cull
  loupe / filmstrip / cull-grid. Cull does not have a separate asset source;
  it navigates the same `assets`, further narrowed only by `cullScope`
  (`unrated`/`picks`/`rejects`/`all` — a pick-flag *review* scope cycled with
  `s`, orthogonal to the library filters).
- **The persistent filter scope** = the filter fields (`librarySearchText`,
  `keywordFilterText`, `folderFilterText`, `minimumRatingFilter`, `flagFilter`,
  `colorLabelFilter`, `cameraFilterText`, `lensFilterText`, `minimumISOFilter`,
  `captureDateStartFilter`, `captureDateEndFilter`, `geoBoundsFilter`,
  `availabilityFilter`, `evaluationKindFilter`, `needsKeywordsFilter`,
  `needsEvaluationFilter`, `likelyIssuesFilter`, `potentialPicksFilter`,
  `providerFailuresFilter`, `metadataSyncPendingFilter`,
  `metadataSyncConflictFilter`) + `selectedAssetSetID` + the token-parsed
  `detachedLibraryFilterPredicates` + `librarySortOption`. They compile in
  `currentLibraryQuery()`, drive `reload()`, and populate `assets`. All are
  persisted for session restore.
- **A bare view switch** (`selectedView = …`, incl. the Library view toggle
  and the Cull sub-view switches) and a **bare mode switch**
  (`selectWorkspace(_:)`) mutate only `selectedView`. They already leave the
  filter scope untouched, so ⌘1→Cull already navigates the filtered `assets`
  and ⌘2→Library already shows the same filters.

### Where the scope diverges today (what breaks the invariant)

The scope is clobbered only by the **whole-scope "Cull" entry**:
`beginCullingSession(named:)` (the Library toolbar Cull button + the
Culling menu). It snapshots the current scope into a hidden `work-input-*`
set and calls `applyAssetSet(inputSetID)`, which **`clearLibraryQueryFilters()`
and switches `selectedAssetSetID` to the snapshot**. After a real cull the live
filters are gone — returning to Library shows a frozen snapshot with no chips.
This is exactly Jesse's "go to cull and I lose my filters."

The reason it clears rather than keeps: the in-progress culling session is
discovered by `activeCullingSession(repository:)` via
`selectedAssetSetID` matching a session's input/output set (or a `session:`
search token). Progress / completion / the picks output set are all computed
from the session's **recorded input snapshot** (`cullingInputAssetIDs(in:)`),
fully decoupled from the active browsing scope — so the only thing the
`selectedAssetSetID = inputSetID` switch actually provides is *session
discovery*.

## Design (the HOW)

### Principle

The persistent filter scope is authoritative and is **never** mutated by a view
switch or a mode switch. A culling session is an activity **overlaid on** the
current scope, not a replacement for it — its identity is tracked separately
from the scope.

### Change 1 — Lock the invariant (characterization + guard tests)

Add tests asserting that every view transition
(`grid ↔ libraryLoupe ↔ timeline ↔ map`) and every mode transition
(`library ↔ cull ↔ people`, via `selectWorkspace`) leaves the full filter
scope (every filter field, `selectedAssetSetID`, `librarySortOption`) and the
loaded `assets` unchanged, and that entering Cull navigates the filtered
`assets`. These pass against today's code; they exist to freeze the behavior —
important because a parallel People sub-project is editing the same files.

### Change 2 — Whole-scope Cull entry preserves the filter scope

`beginCullingSession(named:)`, when begun over a **pure filter scope**
(`selectedAssetSetID == nil`):

- keeps the live filter fields intact (no `clearLibraryQueryFilters`),
- does **not** switch `selectedAssetSetID` (stays `nil`) — the cull navigates
  the already-loaded filtered `assets`,
- still records the session's `work-input-*` snapshot (unchanged) for
  progress / completion / output / resumption,
- tracks the in-progress session via a new `activeCullingSessionID`.

Begun over an **already-selected explicit set** (`selectedAssetSetID != nil`,
i.e. a manual/snapshot/dynamic saved set): unchanged from today (that set *is*
the persistent scope; there are no live filter fields to preserve).

Mechanics:

- New `private var activeCullingSessionID: WorkSessionID?` on `AppModel`.
- `beginCullingSession`: compute `inputSetID` via `cullingInputSetID`
  (unchanged snapshot). Branch on `selectedAssetSetID == nil`: pure-filter path
  keeps filters/assets and only sets `selectedView = .loupe`; set-scope path
  keeps today's `applyAssetSet(inputSetID)` + selection restore. Set
  `activeCullingSessionID = sessionID` at the end of both paths.
- `activeCullingSession(repository:)`: add `activeCullingSessionID` as a final
  fallback, after the existing `selectedAssetSetID` and `session:`-token checks.
- `clearLibraryQueryFilters()`: also clear `activeCullingSessionID`. This is the
  single choke point every explicit re-scope funnels through (sidebar nav,
  saved-set apply, review queue, Cull source picker, Clear Filters), so
  navigating away ends session tracking — mirroring exactly how today's
  `selectedAssetSetID`-based discovery ends when you navigate away.

### Deliberate non-goals (keep the diff focused)

- The Cull sidebar **"Cull From" source picker** (recent import, Top Picks,
  Needs Eyes, diagnostics queues) and **"Cull These"** (`cullCurrentSelection`)
  stay explicit re-scoping gestures: choosing a *different* set to cull, like
  Library sidebar navigation. They legitimately change the scope. Composing a
  queue source with an unrelated rating filter is a larger design not asked for
  here.
- **Dynamic saved sets** as the scope keep today's cull behavior (the cull
  snapshots them). Only the pure-filter scope (`selectedAssetSetID == nil`) —
  the exact reported case — is preserved. Broadening to dynamic sets is a
  possible follow-up.
- No new Cull UI (no filter chrome in Cull, no new source row). This is a model
  behavior change.

## Invariants preserved

- **Auto-apply with provenance / confirm-before-write:** unchanged. No labels
  are written by any switch; culling still writes flags via the same gestures.
- **Non-destructive:** unchanged.
- Session progress, the persisted Picks output set, resumption via Recent Work,
  and stack culling are all computed off the session record and are unaffected.

## Testing

- Unit (`Tests/TeststripAppTests`): view/mode-switch persistence guards;
  whole-scope cull-over-filters preserves filters and `selectedAssetSetID`
  stays nil; the cull still tracks progress to completion and builds the picks
  output set with `selectedAssetSetID == nil`; returning to Library shows the
  live filtered grid. Negative assertion: nothing in the filter fields is
  cleared by `selectWorkspace`/`selectedView`.
- The one existing test that documented the old clear-on-cull behavior
  (`testBeginningCullingSessionCreatesHiddenInputSetForAdhocSearch`) is updated
  to the new invariant.
