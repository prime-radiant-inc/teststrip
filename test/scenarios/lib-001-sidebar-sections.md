# lib-001-sidebar-sections: the unified sidebar renders source sections in fixed order with correct rows, counts, and disclosure state

**What this covers**: the one `SidebarView` shared by every lens. Its nonempty
sections render in the fixed order Library / Imports / Smart Collections /
Sets / Folders / Recent Work / Selection; Library always leads with All
Photos, while the other sections appear only when they have rows
(`Sources/TeststripApp/UnifiedSidebarPresentation.swift:89-103,127-245`).
Imports owns ingest sessions, Smart Collections owns nonzero queues and saved
dynamic searches, Sets owns static membership, Recent Work excludes imports,
and Selection is transient and last. `AppModel.buildSidebarSections`
(`AppModel.swift:1982-2005`) supplies that presentation, and `SidebarView`
renders the returned sections unchanged (`SidebarView.swift:24-55`). Folder
rows retain their independently tappable disclosure chevron and tree indent
(`SidebarView.swift:237-288`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
```
`--smoke` seeds 24 synthetic assets under folders plus ONE starred saved
set ("smoke-picks" / "Smoke Picks", `SmokeCatalogSeeder`), and no
work-session rows beyond whatever the seeding import itself produced — check
`asset_sets` and confirm the Recent Import / Recent Work rows come from the
seeding import's own work-session record, not a separate seed:
```bash
sqlite3 "$DB" "SELECT count(*) FROM asset_sets;"   # expect 1 ("Smoke Picks", starred)
sqlite3 "$DB" "SELECT id, kind, status FROM work_sessions ORDER BY started_at DESC LIMIT 5;"
```
The starred "Smoke Picks" set exercises static-set rendering in **Sets**;
starred static sets sort before unstarred ones. The seeding import belongs in
**Imports**, never Recent Work. A matched-work check needs a non-ingest work
session whose title/detail matches the query; if the fixture has only its
ingest session, record that leg as fixture-blocked rather than expecting an
import to appear in Recent Work.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for the Grid lens.
2. `ax_drive.sh find --role AXStaticText --label "Library"` — the first
   `Section` header must exist, with "All Photos" as its first row, and appear
   above every other section in the AX tree (assert ordering via
   `capture_app_window.sh` or by comparing y-position/traversal order — AX
   groups are traversed top-to-bottom).
3. If the seed import produced an output set, assert an "Imports" section
   follows Library and contains its date/folder row and count. The ingest row
   must not also appear in Recent Work. If more than three imports exist,
   assert the newest three plus "All imports…".
4. Assert nonzero built-in queues appear under "Smart Collections" and the
   starred static "Smoke Picks" appears once under "Sets", not under Library
   or Smart Collections. A zero-count queue must not render.
5. `ax_drive.sh find --role AXStaticText --label "Folders"` — since `--smoke`
   seeds files under folder paths, a "Folders" section must exist below
   the preceding populated sections.
6. Pick a folder row that has children (`catalogFolders` from the seeded
   import — check `SELECT DISTINCT source_root_relative_dir FROM assets;`
   against `$DB` to find one with descendants). Assert it renders a disclosure
   chevron (`ax_drive.sh find --role AXButton --help "Expand <title>"`,
   per `SidebarView.swift:271-288`) as a *separate* AX button from the row's own
   selection button — pressing the chevron must not select the row, and
   pressing the row label must not toggle expansion.
7. Press the chevron. Assert its `AXHelp` flips to `"Collapse <title>"` and
   a child row appears one indent level deeper (`.padding(.leading, depth *
   14)`, `SidebarView.swift:254`) — compare the child row's frame x-origin to
   the parent's and confirm it's offset by roughly 14pt.
8. If a non-ingest work session is available, type a matching query and assert
   the Recent Work section shows the matched row instead of the ordinary
   recent/starred merge; clearing the query restores the ordinary rows. If no
   such session exists, record the fixture gap.
9. Select one grid cell. Assert a "Selection" section appears last with count
   1; add a second cell to the batch and assert the count becomes 2. Selecting
   that row scopes to the current selection source.

## Expected
- Steps 2-5: populated sections follow Library → Imports → Smart Collections
  → Sets → Folders → Recent Work, with Selection last when present. **Fails
  if** a row appears in two sections, an ingest appears in Recent Work, or
  "All Photos" is not the first Library row.
- Step 6: the disclosure chevron is a distinct AX element from the row
  button, and neither tap target activates the other's action. **Fails if**
  clicking the chevron also calls `select(row)`, or clicking the row toggles
  expansion — this was the specific bug the sibling-button design in
  `SidebarView.swift:237-288` was written to avoid.
- Step 7: chevron `AXHelp` toggles Expand/Collapse and a child row renders
  indented ~14pt deeper than its parent. **Fails if** the child doesn't
  appear, or renders at the same indent as its parent.
- Step 8: matched work replaces the ordinary Recent Work merge rather than
  appending to it. **Fails if** both variants remain or clearing the query
  leaves stale matched rows.
- Step 9: Selection is transient, last, and its count tracks the batch.
  **Fails if** it persists after selection clears or scopes to stale IDs.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--smoke`'s one starred static set covers the starred-first Sets ordering;
  it does not cover an unstarred peer or a saved dynamic search under Smart
  Collections. Create those live if their relative ordering needs proof.
- The seeding import is intentionally excluded from Recent Work now that
  Imports owns ingest history. A matched-work assertion therefore needs a
  culling/export/relocation/collecting session, not the seed import.

## Run status
NOT RUN AGAINST THE UNIFIED-SIDEBAR CONTENT — headless reconciliation only;
needs a live AX run. The section model was re-read at
`UnifiedSidebarPresentation.swift:89-245`, its model
wiring at `AppModel.swift:1982-2005`, and rendering/disclosures at
`SidebarView.swift:24-55,237-288`. This supersedes the former body, which
described the deleted Collections/Saved Sets composition and treated ingest
history as Recent Work.

## Fix notes (persona-fixes-5, 2026-07-11)
PENDING-VM: idle-catalog CPU runaway root-caused to the geocode dispatch
loop — `enqueuePendingGeocoding()` gated on raw `geocodeQueueDepth()`, so a
coordinate whose attempts were exhausted (CLGeocoder unreachable) kept the
depth > 0 forever and each empty batch completion immediately redispatched
another. Fixed by gating on `pendingGeocodeQueueDepth(maximumAttemptCount:)`
(rows with attempt_count below the executor max). Unit-tested at AppModel
level; live idle-soak verification on the VM is still pending (Tart VM
stopped this session).
