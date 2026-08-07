# Unified shell: sources × lenses — design

**Decision date:** 2026-08-07. Brainstormed with Jesse (visual companion
session; mockups in `.superpowers/brainstorm/91019-1786126501/content/`).
This spec replaces the two-workspace shell and the post-import banner. The
SP-D run-lifecycle spec (kata #12, second half) will be designed against
this shell and is out of scope here. Pre-release, single user: **no
back-compat anywhere** (Jesse, 2026-08-07).

## Problem

The post-import completion banner (`ImportCompletionPresentation`, rendered
by `LibraryGridView.importCompletionSummary`) stacks a headline, four metric
tiles, and up to nine action buttons — roughly 280pt of chrome. Its nine
actions collapse to four real intents (cull it / browse it / fix problems /
run analysis); three of the buttons are different doors into culling the
same set. The amber issue *metrics* are styled like the action *buttons*, so
problems read as tasks. Nearly every action duplicates a sidebar source that
already shows the same count. Underneath that local mess is a structural
one: Cull and Library are separate workspaces with separate sidebars, so
"what am I looking at" and "how am I looking at it" are entangled, and
culling is welded to bespoke entry points instead of being available over
any set.

## Decisions (Jesse, 2026-08-07)

1. **Sidebar-native import surface.** The banner is deleted, not restyled.
   Import follow-ups live in the sidebar; every count lives in exactly one
   place.
2. **Completion moment = thin toast + Start culling.** One capsule,
   top-right; fades after ~10s and docks into the Activity Center bell as
   the receipt. No other completion chrome.
3. **All imports are listed and cullable — "or really any search."** Import
   history is a durable sidebar section; any query that names a set of
   photos can be a cull scope.
4. **One sidebar, six lenses.** The Cull|Library workspace split dissolves.
   Cull, Grid, Loupe, Timeline, Map, People are top-level views (⌘1–⌘6)
   over the selected source. Most of the old "Cull From" rows are really
   smart collections.
5. **People respects the source.** People over an import is "who's in this
   shoot"; the global grouping queue is People × All Photos. No lens
   ignores the nouns.
6. **Spec split: shell first, SP-D lifecycle second.** This spec is the
   shell. The run lifecycle (minimal start card, resume, completion
   ceremonies) follows, designed against it.
7. **No back-compat.** Nobody is using the tool yet. No migration shims, no
   legacy keybindings, no preserved UserDefaults for the old workspace
   selection.

## Design

### Information architecture: sources × lenses

- A **source** is a noun: a set of photos named by the sidebar (All Photos,
  an import, a smart collection, a saved set, the transient selection) or
  by a search query.
- A **lens** is how you look at the selected source: **Cull, Grid, Loupe,
  Timeline, Map, People**, switched by a single toolbar control and ⌘1–⌘6
  (same order). The old Cull|Library Picker and its ⌘1/⌘2 bindings are
  deleted.
- Switching lenses never changes the selected source or selection;
  selecting a source never changes the lens (with one exception: a source
  the current lens disables on — see lens rules — falls back to Grid).
- A persistent **scope line** under the toolbar names the source and shows
  lens-appropriate status (Cull: run progress "854 photos · 326 stacks ·
  ✓ 15 · ✕ 5 · 407 left"; browse lenses: result count and active filters).
- One window minimum width: 1000pt (the old per-workspace 800/1000 split
  goes away). ⌘I inspector unchanged and available in every lens.

### Sidebar (one, everywhere)

Sections, top to bottom:

- **Library** — All Photos (catalog count).
- **Imports** — dated history, newest first: the most recent 3 rows plus an
  "All imports…" overflow row with the total. Backed by the existing
  `work_sessions` (import-kind rows: title, detail, status, `issues_json`)
  joined to `asset_sets` membership — **no schema change**. Row label
  derives from the session's date and source-folder text already carried in
  its title/detail.
- **Smart Collections** — the old Cull From rows, which were always live
  queries: Picks, Potential Picks, Likely Issues, Not analyzed yet,
  Rejects, 5 Stars, Needs Keywords, Faces Found, OCR Found, and the
  SP-D0 AI Suggestions source (ghost-derived, appears only when a ghost
  exists). Plus **"+ New from search…"**: saves the current search query as
  a named smart collection (live query, count updates).
- **Sets** — saved `asset_sets` (static membership), starred first.
- **Selection** — transient, bottom, only while a selection exists.

Clicking any source shows it in the current lens. Counts render at the
right edge as today; warning-toned rows are amber.

### Import rows

An import row expands (disclosure) to import-scoped children:

- **Stacks** — the import's time-adjacent stack groups.
- **⚠ Skipped files** — from the session's `issues_json`.
- **⚠ Preview failed** — preview-generation failures within the import.
- **⚠ Likely issues** — the flagged/likely-issue query scoped to the
  import.
- **Faces found** — face-carrying assets within the import.
- **Keywords** — the batch keyword-suggestion review surface, scoped to
  the import (the banner was its only entry point; this is its new home).

Children render only with nonzero counts. Warning children (Skipped files,
Preview failed) are **diagnostic sources**: they open in Grid for
inspection and the Cull lens disables on them (nothing there is cullable —
skipped files aren't even in the catalog; their "grid" is the issue list).
Verbs with no set to show move to the import row's **context menu**:
Evaluate import (run local reads), Manual Compare over the import.

### Import completion moment

- On completion, a **toast** appears top-right: ✓ count, skipped-count
  warning if any, and a **Start culling** button. It fades after ~10s (or
  on click/dismiss) and docks into the Activity Center bell, which keeps
  the full receipt: counts, issue list, Start culling. The new import row
  appears in the sidebar with a brief pulse.
- Existing-only imports ("No new photos imported — N already in catalog")
  get the same toast shape with that copy and no Start culling button.
- Start culling selects the import as the source and enters the Cull lens.
- **Deleted outright:** `ImportCompletionPresentation`,
  `ImportCompletionMetricRow`, `ImportCompletionActionPresentation`, the
  `importCompletionSummary`/`importCompletionMetric`/
  `importCompletionAction` render stack in `LibraryGridView`,
  `LibraryGridChromePolicy.shouldShowImportCompletionSummary`, and the
  `dismissedImportCompletionSummaryID` state. `AppModel`'s
  `latestImportCompletionSummary` survives as the toast/receipt data
  source.

### Cull anything

- The Cull lens runs over whatever source is selected — an import, a smart
  collection, a set, the selection, All Photos.
- Browse lenses (Grid, Loupe, Timeline, Map) carry the token search field.
  When a query is active, the results header gains **"Cull these"** (hand
  the current result set to the Cull lens as its source) and **"Save as
  set"** (materialize membership into `asset_sets`). "+ New from search…"
  in the sidebar saves the query itself as a live smart collection.
- Precise run semantics (scope snapshotting, resume, completion) are the
  SP-D lifecycle spec's job. This spec's contract: every source — and a
  handed-off search result — can be the Cull lens's input.

### Lens rules

- Every lens is source-scoped. People over a source shows that source's
  faces and grouping queue; People × All Photos is the global queue.
  People and Cull keep their focused chrome (no search field), as today.
- Lens availability: Cull disables on diagnostic sources and empty
  sources; everything else works everywhere. A disabled lens is visibly
  disabled in the switcher with the reason on hover; selecting a source
  the current lens disables on falls back to Grid.
- Lens switching preserves source, selection, and (where meaningful) the
  focused asset.

## Behavior changes (the honest list)

1. The post-import banner is gone; its nine actions are replaced by the
   toast button, sidebar sources, and the import row's context menu.
2. ⌘1/⌘2 stop meaning Cull/Library; ⌘1–⌘6 select lenses. The workspace
   Picker is gone. No legacy bindings.
3. The Cull sidebar and Library sidebar become one sidebar; "Cull From"
   as a concept disappears (those rows are Smart Collections now).
4. Import history becomes visible and navigable; older imports are
   cullable again at any time.
5. Any search can be culled and saved (as a set or a smart collection).
6. People becomes source-scoped; the global queue moves to All Photos.
7. Batch keyword-suggestion review is reachable from import rows instead
   of the dead banner.

## Invariants (unchanged, re-asserted in tests)

All SP-D0 invariants hold: ghosts are `origin = ai`, unconfirmed, never
sidecar-written, never counted as decided, never driving destructive or
committing operations; auto-apply with provenance; original bytes
untouched. Import remains non-destructive and in-place. Nothing in this
spec touches metadata semantics — it relocates chrome.

## Out of scope

- SP-D run lifecycle: minimal start card, lenses-with-loud-accounting
  refinements, exact resume, completion ceremonies, unifying
  `CullingSessionCompletionSummary` with `CullCompletionPresentation`.
- Any change to import mechanics, preview generation, evaluation, or
  metadata handling.
- Smart-collection editing UI beyond "+ New from search…" (rename/delete
  via context menu is in; a query-builder editor is not).
- Multi-window.

## Testing

**Unit (TDD):**

- Sidebar presentation: section composition, import-row labels from
  `work_sessions` fields, recent-3 + overflow, nonzero-only children,
  scoped child counts, warning tones.
- Completion toast presentation: full/existing-only variants, Start
  culling presence, receipt content; the banner presentation types are
  gone (compile-level) and the chrome policy no longer special-cases
  import summaries.
- Lens scoping: switching lenses preserves source/selection; People query
  scoped to source vs All Photos; Cull disabled on diagnostic/empty
  sources with Grid fallback.
- Cull-these handoff: a query result set becomes the Cull lens input;
  Save as set writes `asset_sets` membership; New-from-search persists a
  live query.

**End-to-end (scenario cards, VM, seeded batch):** import a batch; assert
the toast appears with Start culling and no banner chrome exists; let the
toast dock and assert the bell holds the receipt; expand the import row
and assert scoped child counts against the catalog; cull from an older
import; run a token search, Cull these, assert the Cull scope line names
the search; switch ⌘1–⌘6 across a fixed source and assert the source
never changes; People over an import vs All Photos. Audit existing cards
that touch the banner, workspace switching, or ⌘1/⌘2 and reconcile them
in the same push.
