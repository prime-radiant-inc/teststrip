# lib-001-sidebar-sections: Library sidebar sections render in fixed order with correct rows, badges, and disabled state

**What this covers**: the Library workspace's `SidebarView` — the `Section`s
render in the fixed order Collections / Saved Sets (only if any exist) /
Folders (only if any exist); Collections is built from All Photographs +
Recent Import + starred saved sets + Recent Work, in that order
(`Sources/TeststripApp/AppModel.swift:11603-11634`); folder rows carry
tree indent and an independently-tappable disclosure chevron distinct from
row selection; a placeholder row renders disabled; and a matched-work query
replaces the merged Recent+Starred Work rows with `work-matched-*` rows.

Ground truth for the row model is `AppModel.defaultSidebarSections`
(`AppModel.swift:11576-11645`) and `SidebarView.swift:17-30,142-186` for how
each row/disclosure renders.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
`--smoke` seeds 24 synthetic assets under folders, no saved sets and no
work-session rows beyond whatever the seeding import itself produced — check
`asset_sets` and confirm the Recent Import / Recent Work rows come from the
seeding import's own work-session record, not a separate seed:
```bash
sqlite3 "$DB" "SELECT count(*) FROM asset_sets;"   # expect 0 -- see Sharp edges
sqlite3 "$DB" "SELECT id, kind, status FROM work_sessions ORDER BY started_at DESC LIMIT 5;"
```
This card cannot exercise the "starred saved sets in Collections" or "Saved
Sets" section rows — `--smoke` creates no `asset_sets` rows — see Sharp
edges for the fixture gap. Item 5 (matched-work rows) needs a plain-text
Library query that matches a work-session title/detail; the seeding import's
own session (kind `ingest`, title "Import photos") should match on a
substring of its detail text.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. `ax_drive.sh find --role AXStaticText --label "Collections"` — the first
   `Section` header must exist, and appear above any "Saved Sets" or
   "Folders" header in the AX tree (assert ordering via
   `capture_app_window.sh` or by comparing y-position/traversal order — AX
   groups are traversed top-to-bottom).
3. Within Collections, assert row order: "All Photographs" first
   (`ax_drive.sh find --role AXButton --label "All Photographs"`), then (if
   present) "Recent Import", then any starred-set rows, then Recent Work rows
   (`work-recent-*`).
4. `ax_drive.sh find --role AXStaticText --label "Folders"` — since `--smoke`
   seeds files under folder paths, a "Folders" section must exist below
   Collections (and below Saved Sets if present).
5. Pick a folder row that has children (`catalogFolders` from the seeded
   import — check `SELECT DISTINCT source_root_relative_dir FROM assets;`
   against `$DB` to find one with descendants). Assert it renders a disclosure
   chevron (`ax_drive.sh find --role AXButton --help "Expand <title>"`,
   per `SidebarView.swift:184`) as a *separate* AX button from the row's own
   selection button — pressing the chevron must not select the row, and
   pressing the row label must not toggle expansion.
6. Press the chevron. Assert its `AXHelp` flips to `"Collapse <title>"` and
   a child row appears one indent level deeper (`.padding(.leading, depth *
   14)`, `SidebarView.swift:151`) — compare the child row's frame x-origin to
   the parent's and confirm it's offset by roughly 14pt.
7. Type a plain-text Library query (⌘2, focus the query field, type a
   substring of the seeding import's work-session detail text, e.g. part of
   the folder name), press Return. Assert the Collections section's work rows
   are now `work-matched-*` (their sidebar id prefix per
   `AppModel.swift:11627-11631`) rather than `work-recent-*`/`work-starred-*`
   — confirm via the row's accessibility value/detail text matching the
   session, and that clearing the query restores `work-recent-*` rows.
8. Assert a disabled/placeholder row (if any renders — e.g. an empty Recent
   Import slot before any import has happened) is not AX-pressable: `disabled`
   per `row.isSelectable` (`AppModel.swift:919-921`, `SidebarRowButton`
   `.disabled(!row.isSelectable)` at `SidebarView.swift:165`). If `--smoke`'s
   seeding import always produces a Recent Import row, this sub-check may be
   unrunnable against this fixture — note that rather than fabricating one.

## Expected
- Step 2/4: Collections precedes Folders in traversal order, and (per code)
  would precede Saved Sets too if any saved sets existed. **Fails if** any
  section is missing or ordered differently than
  Collections → Saved Sets → Folders.
- Step 3: "All Photographs" is the first Collections row. **Fails if** any
  other row (Recent Import, a starred set, Recent Work) sorts above it —
  the code always prepends it first (`AppModel.swift:11604-11610`).
- Step 5: the disclosure chevron is a distinct AX element from the row
  button, and neither tap target activates the other's action. **Fails if**
  clicking the chevron also calls `select(row)`, or clicking the row toggles
  expansion — this was the specific bug the sibling-button design in
  `SidebarView.swift:134-141` was written to avoid.
- Step 6: chevron `AXHelp` toggles Expand/Collapse and a child row renders
  indented ~14pt deeper than its parent. **Fails if** the child doesn't
  appear, or renders at the same indent as its parent.
- Step 7: work rows use the `work-matched-*` id prefix while a matching query
  is active, and clearing the query restores `work-recent-*`/`work-starred-*`
  rows. **Fails if** the merged Recent+Starred rows persist alongside the
  matched rows (code replaces, not appends — `AppModel.swift:11617-11632`),
  or if clearing the query leaves stale matched rows.
- Step 8: a disabled row cannot be AX-pressed (its Button carries
  `.disabled(true)`, so `ax_drive.sh press` against it should have no effect
  on selection/navigation). **Fails if** a placeholder row is selectable, or
  if the tri-state disabled visual (`opacity(0.62)`, secondary foreground —
  `SidebarView.swift:405-406`) is absent while the row is in fact disabled.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--smoke` does not seed any `asset_sets` rows, so the "starred saved sets
  render in Collections" and "Saved Sets section" behaviors (items 2-3 of
  the inventory this card was asked to cover) are **not exercised here** —
  see `lib-002-saved-set-context-menus.md`'s Pre-state for the same gap,
  which needs a saved set created through the running app (no seed flag
  creates one) before either card's Saved-Sets-specific assertions can run.
- **Possible duplicate-ID bug**: a starred saved set's row is rendered twice
  when starred — once in the Collections section
  (`AppModel.swift:11615-11616`, via `Self.sidebarRow(for: $0, ...)`) and
  again in the Saved Sets section (`AppModel.swift:11636`) — and both calls
  produce the *same* `SidebarRow.id` (`"asset-set-\(assetSet.id.rawValue)"`,
  `AppModel.swift:11819`). SwiftUI `List`/`ForEach` normally assumes stable
  identity is unique across the identified collection; two rows sharing an
  id in the same `List` (even across different `Section`s) is a documented
  footgun for selection/diffing behavior. This card doesn't have a fixture to
  exercise it (no seeded saved sets — see gap above); flagging for whoever
  picks up the Saved-Sets fixture to also check whether SwiftUI/AX visibly
  misbehaves (e.g. `ax_drive.sh find --label` matching only the first
  instance, or a context-menu action applying to the wrong instance) once a
  starred set exists.

## Run status
NOT RUN — headless authoring only; needs a live AX run. No live GUI launch or
`ax_drive.sh` invocation was performed for this card. Source line numbers
above were read directly from `Sources/TeststripApp/SidebarView.swift` and
`Sources/TeststripApp/AppModel.swift` on 2026-07-10; the `asset_sets` seed
gap was confirmed by grepping `script/build_and_run.sh` for asset-set seeding
(none found) rather than by running SQL against a live catalog.
