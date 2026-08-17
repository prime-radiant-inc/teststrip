# lib-001-sidebar-sections: Unified sidebar sections render in fixed order with correct rows, counts, and disabled state

**What this covers**: the one sidebar shared across every lens —
`SidebarView` rendering `model.sidebarSections` (built by
`UnifiedSidebarPresentation.sections()`,
`Sources/TeststripApp/UnifiedSidebarPresentation.swift:127-243`, called from
`AppModel.buildSidebarSections()` at `AppModel.swift:2055-2078`). Seven
sections in fixed order: **Library** / **Imports** / **Smart Collections** /
**Sets** / **Folders** / **Recent Work** / **Selection**. Library, Smart
Collections, and Sets always render; Imports, Folders, Recent Work, and
Selection are conditional (empty → absent). A Cull-lens-only
"Stacks · Auto-Grouped" section renders outside `sidebarSections`
(`SidebarView.swift:46-55`).

Smart Collections lists ten collections in fixed order
(`UnifiedSidebarPresentation.swift:106-109`: picks, potentialPicks,
likelyIssues, needsEvaluation, rejects, fiveStars, needsKeywords, facesFound,
ocrFound, providerFailures); only those with count > 0 render as rows
(`:170-178`), plus an "AI Suggestions" row if autopilot ghosts exist
(`:180-188`), plus saved dynamic sets (`:191-193`). The section header carries
a "New from search…" add button (`SidebarView.swift:110-117`).

Sets carries static membership sets only, starred first (`:196-200`). The
section header carries a "New Set from Selection…" add button
(`SidebarView.swift:102-109`).

Folders renders a tree built by `FolderTreePresentation.build()`
(`FolderTreePresentation.swift:32-77`); folder rows with children carry an
independently-tappable disclosure chevron as a *sibling* AX button
(`SidebarView.swift:272-288`), distinct from the row's own selection button;
child rows indent by `depth * 14` (`SidebarView.swift:254`).

Rows with `target == nil` (the running-import row, the "All imports…"
overflow) render disabled: `.disabled(!row.isSelectable)` at
`SidebarView.swift:268`, with `.opacity(0.62)` and secondary foreground at
`SidebarView.swift:553-554`.

A work-history search replaces merged Recent+Starred work rows with matched
rows (`UnifiedSidebarPresentation.swift:211-213`).

Ground truth: `UnifiedSidebarPresentation.sections()` at
`UnifiedSidebarPresentation.swift:127-243`, rendered by
`SidebarView.swift:24-56`, row content at `SidebarView.swift:246-289`,
`SidebarRowView` at `SidebarView.swift:520-559`.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
`--smoke` seeds 24 synthetic assets in a single flat source-root directory
(no subfolder hierarchy), ONE starred static saved set ("smoke-picks" /
"Smoke Picks"), and one import session. The import session is `.ingest`
kind, so it appears in the Imports section and is filtered out of Recent
Work (which carries only non-ingest kinds). Confirm:
```bash
sqlite3 "$DB" "SELECT count(*) FROM asset_sets;"              # expect 1 ("Smoke Picks", starred)
sqlite3 "$DB" "SELECT id, kind, status FROM work_sessions ORDER BY started_at DESC LIMIT 5;"
sqlite3 "$DB" "SELECT count(*) FROM assets WHERE flag = 'pick';"   # expect 6
sqlite3 "$DB" "SELECT count(*) FROM assets WHERE flag = 'reject';" # expect 5
sqlite3 "$DB" "SELECT count(*) FROM assets WHERE rating = 5;"      # expect 4
```

Expected `--smoke` sidebar (sections that render):
- **Library** — "All Photos" (count 24)
- **Imports** — one row for the seeding import session
- **Smart Collections** — "Picks" (6), "Not analyzed yet" (24), "Rejects" (5),
  "5 Stars" (4); zero-count collections omitted, not disabled
- **Sets** — "Smoke Picks" (starred, static)
- **Folders** — one root folder row (no children → no disclosure chevron)
- **Recent Work** — absent (no non-ingest work activities in `--smoke`)
- **Selection** — absent (no selection in fresh smoke)
- **Stacks · Auto-Grouped** — absent unless Cull lens is selected

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Assert section order in the AX tree (top-to-bottom traversal): "Library"
   first, then "Imports", then "Smart Collections", then "Sets", then
   "Folders". "Recent Work" and "Selection" must NOT appear in a fresh
   `--smoke` catalog (no non-ingest work, no selection).
3. **Library section**: `ax_drive.sh find --role AXButton --label "All Photos"`
   — the single row in this section; assert its count badge shows "24"
   (the `countText` value via `accessibilityValue`).
4. **Imports section**: `ax_drive.sh find --role AXStaticText --label "Imports"`
   — header exists. One import-session row below it; assert it is AX-pressable
   (`target != nil`).
5. **Smart Collections section**: `ax_drive.sh find --role AXStaticText --label
   "Smart Collections"` — header exists, and carries an "New from search"
   add button (`SidebarView.swift:110-117`). Assert rows appear in order:
   "Picks", "Not analyzed yet", "Rejects", "5 Stars" (the nonzero-count
   collections). Assert "Potential Picks", "Likely Issues", "Needs Keywords",
   "Faces Found", "OCR Found", "Analysis Failures" are ABSENT (zero count →
   omitted, `:170-171`).
6. **Sets section**: `ax_drive.sh find --role AXStaticText --label "Sets"` —
   header exists, carries an "New Set from Selection" add button
   (`SidebarView.swift:102-109`). One row: "Smoke Picks" (the starred static
   set). Assert it is AX-pressable.
7. **Folders section**: `ax_drive.sh find --role AXStaticText --label
   "Folders"` — header exists. One folder row below it (the single source-root
   directory). Assert it has NO disclosure chevron
   (`ax_drive.sh find --role AXButton --help "Expand <title>"` must NOT find
   one) because the flat `--smoke` seed produces a single folder with no
   children (`FolderTreePresentation.build` → one root node, no children).
   Assert the folder row IS AX-pressable (it has a `target`).
8. **Disabled state**: In a fresh `--smoke` catalog there is no running import
   and only one import session (≤ 3), so no `target == nil` row renders. To test
   the disabled visual, create a live import (drag a small folder onto the app)
   and assert the running-import row (`import-running-*`) renders with
   `.opacity(0.62)` and `.foregroundStyle(.secondary)` (`SidebarView.swift:553-554`)
   and is not AX-pressable (`.disabled(!row.isSelectable)` at
   `SidebarView.swift:268`). If no live import is available, note this
   sub-check as unrunnable against the `--smoke` fixture rather than
   fabricating one.

## Expected
- Step 2: sections render in the order Library → Imports → Smart Collections
  → Sets → Folders, with Recent Work and Selection absent. **Fails if** any
  section is missing, out of order, or if Recent Work / Selection appears in a
  fresh `--smoke` catalog.
- Step 3: "All Photos" is the sole Library row, with count 24. **Fails if**
  the count is wrong or the row is missing.
- Step 4: the Imports section renders with one pressable row. **Fails if**
  the section is absent (the seeding import always produces a session) or the
  row is not AX-pressable.
- Step 5: Smart Collections rows appear in the fixed order
  `smartCollectionOrder` (`:106-109`), with only nonzero-count collections
  rendered. **Fails if** a zero-count collection (e.g. "Potential Picks",
  "Faces Found") renders as a disabled row instead of being omitted, or if
  the rendered collections are out of order.
- Step 6: the Sets section renders with "Smoke Picks" as the sole row,
  pressable, with the "New Set from Selection" add button in the header.
  **Fails if** the section is absent or the add button is missing.
- Step 7: the Folders section renders one row with no disclosure chevron.
  **Fails if** a chevron appears on a childless folder row (the code sets
  `disclosure = .none` when `!node.hasChildren`,
  `UnifiedSidebarPresentation.swift:363`).
- Step 8: a `target == nil` row (running import) renders disabled with
  `opacity(0.62)` and is not AX-pressable. **Fails if** the row is pressable
  or the disabled visual is absent. If no such row exists in the fixture, note
  as unrunnable.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--smoke` seeds all 24 assets in one flat directory
  (`sourceRoot.appendingPathComponent("\(assetID.rawValue).jpg")`), so the
  Folders section has exactly one childless root row. The disclosure-chevron
  sibling-button design (`SidebarView.swift:272-288`) and child-indent
  (`depth * 14`) can only be tested with a multi-folder fixture (e.g.
  `--sample-photos` pointed at a directory tree, or a live import of a nested
  folder). Anyone adding such a fixture should verify: (a) the chevron is a
  distinct AX element from the row button, (b) pressing the chevron does not
  select the row, (c) pressing the row does not toggle expansion, (d) child
  rows indent ~14pt deeper than the parent.
- The matched-work query behavior (`UnifiedSidebarPresentation.swift:211-213`:
  search replaces merged Recent+Starred rows with matched rows) is untestable
  on `--smoke` because Recent Work is absent (the only work session is
  `.ingest` kind, filtered out). Testing requires a non-ingest work session
  (culling, export, relocation).
- `--smoke` seeds exactly one saved set, the starred "Smoke Picks". A
  non-starred set still has no seed and must be created live through the app
  if a card needs a plain (non-starred) Sets row.

## Run status
NOT RUN — headless authoring only; needs a live AX run. Source line numbers
read from `Sources/TeststripApp/UnifiedSidebarPresentation.swift`,
`Sources/TeststripApp/SidebarView.swift`,
`Sources/TeststripApp/FolderTreePresentation.swift`, and
`Sources/TeststripApp/AppModel.swift` on 2026-08-16.

Reconciled 2026-08-16 (issue #9): rewrote from pre-unified-shell
Collections / Saved Sets / Folders structure to the current unified sidebar
(Library / Imports / Smart Collections / Sets / Folders / Recent Work /
Selection) implemented by `UnifiedSidebarPresentation`. The old card
described `AppModel.buildSidebarSections()` at line 2031 and
`SidebarView.swift:17-30,142-186` — all superseded by the unified shell. The
"Excluded unified-shell journey debt" note that was at the bottom of the
old card is now resolved by this rewrite.
