# activity-004-sources-conflicts-quiet: Activity popover Sources refresh/reconnect, XMP Conflicts rows, and the quiet "No active work" state

**What this covers**: three independent sections of the Activity popover
(`ActivityCenterView`) — the Sources section's per-row refresh/reconnect
actions, the XMP Conflicts section listing conflicted assets separately from
Sources, and the popover's quiet floor state, `"No active work"`, when
nothing needs attention.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps

### 1. Quiet floor state
1. `script/ax_drive.sh wait-vended Teststrip`, then wait for the
   preview/evaluation queue to drain (poll per `activity-icon-states.md`
   step 2 — 0 rows across `preview_generation_queue` +
   active `work_sessions`).
2. Open the Activity popover. With no jobs, no import in progress, no
   offline sources, and no XMP conflicts, assert the exact quiet-state text
   (`ActivityCenterView.swift:42-46`, `isQuiet(_:)` at lines 59-64):
   `ax_drive.sh find --role AXStaticText --contains "No active work"`. This
   is the *only* thing that renders in the popover body at true idle — no
   other section header (`"Sources"`, `"XMP Conflicts"`, `"Activity"`)
   should be present.

### 2. Sources — refresh and reconnect are separate, per-row actions
`--smoke` seeds no `source_roots` rows (confirmed empty via `sqlite3`
2026-07-10) — the Sources section's two row families
(`AppModel.activityCenterPresentation`, `AppModel.swift:2489-2511`) are:
  - **availability rows** (`SourceStatusRow` per non-online
    `sourceAvailabilitySummaries` bucket) — always show a refresh action
    (`refreshActionID` is the availability's raw value, never nil for these
    rows), never a reconnect action.
  - **bookmark-repair rows** (`SourceStatusRow` per registered
    `sourceRoots` entry whose security-scoped bookmark needs repair) — show
    a reconnect action (`reconnectActionID = root.path`), never refresh.
3. Seed an offline asset (per `activity-icon-states.md` step 3):
   ```bash
   sqlite3 "$DB" "UPDATE assets SET original_path = '/Volumes/NoSuchVolume/x.jpg' WHERE id = 'smoke-0';"
   ```
   and trigger a source-availability rescan (see Sharp edges — no UI
   trigger exists; this may require an app restart against the mutated
   catalog, or waiting for the next scan the app runs on its own).
4. In the popover's Sources section, assert an availability row whose name
   reads exactly `"Offline Originals"`
   (`sourceAvailabilityDisplayName(.offline)`, `AppModel.swift:11776-11789`)
   with a secondary status label `"Offline"` (`source.availability.rawValue
   .capitalized`, `ActivityCenterView.swift:239-243`) and a refresh button:
   `ax_drive.sh find --role AXButton --help "Refresh source availability"`.
   Press it; it calls `model.refreshVisibleAssetAvailability()`
   (`ActivityCenterView.swift:267-273`) — assert the row disappears once the
   asset's `original_path` is restored:
   ```bash
   sqlite3 "$DB" "UPDATE assets SET original_path = (SELECT original_path FROM assets WHERE id != 'smoke-0' LIMIT 1) WHERE id = 'smoke-0';"
   # (restore to a valid on-disk path before refreshing, or the row won't clear)
   ```
5. For a bookmark-repair row (requires a registered `source_roots` entry
   whose bookmark needs repair — not producible by `--smoke`; needs a
   card-import or Import Path flow that registers a source root, then an
   out-of-band invalidation of its security-scoped bookmark), assert the
   reconnect button `ax_drive.sh find --role AXButton --help "Reconnect <name>"`
   opens `SourceReconnectSheet` (`ActivityCenterView.swift:275-278`) rather
   than acting inline — distinct from refresh, which acts immediately with
   no sheet.

### 3. XMP Conflicts — listed separately from Sources
6. Seed an XMP conflict (per `quiet-activity-badge.md` step 3 — edit a
   sidecar out-of-band so catalog and sidecar diverge) and trigger the next
   sync scan.
7. Open the popover. Assert the conflict renders under its own `"XMP
   Conflicts"` header (`ActivityCenterView.swift:296-313`), never merged
   into the `"Sources"` list — the two sections are structurally
   independent `VStack`s gated on `presentation.sources.isEmpty` and
   `presentation.xmpConflicts.isEmpty` respectively
   (`ActivityCenterView.swift:36-41`). Both can be simultaneously visible
   (an offline source and an XMP conflict at once) without merging into a
   combined list.

## Expected
- Step 2: **Fails if** `"No active work"` renders alongside any other
  section, or fails to render when all sections are genuinely empty.
- Step 4: **Fails if** the refresh action doesn't clear the row once the
  path is restored, or if a reconnect button (rather than refresh) appears
  on an availability row.
- Step 5: **Fails if** reconnect acts without opening the sheet, or if a
  refresh button (rather than reconnect) appears on a bookmark-repair row.
- Step 7: **Fails if** conflict rows appear inside the Sources section, or
  the two headers never coexist when both kinds of problem are present
  simultaneously.

## Cleanup
```bash
sqlite3 "$DB" "UPDATE assets SET original_path = (SELECT original_path FROM assets WHERE id != 'smoke-0' LIMIT 1) WHERE id = 'smoke-0';" 2>/dev/null || true
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **No UI-reachable trigger exists for source-availability or
  metadata-sync-conflict rescans** — both fire only off worker-queue events
  (`docs/product/focused-workspaces-followups.md`, "Known test-fixture
  gaps": *"No UI-reachable trigger exists for the metadata-sync-conflict or
  source-availability rescans — both fire only off worker-queue events."*).
  Steps 3 and 6 above may need an app relaunch against the mutated catalog
  (forcing a fresh scan at startup) rather than a live in-session trigger —
  confirm which works before relying on either in a run.
- `--smoke` seeds zero `source_roots` rows, so the bookmark-repair row path
  (step 5) needs a fixture this card cannot self-produce; it's included for
  completeness with the gap called out rather than silently dropped.
- Verified all five `sourceAvailabilityDisplayName` strings by direct read of
  `AppModel.swift:11776-11789`: Online → "Online Originals", Offline →
  "Offline Originals", Missing → "Missing Originals", Moved → "Moved
  Originals", Stale → "Stale Originals". Step 4 only exercises Offline; a
  future card could sweep the rest.

## Run status
NOT RUN — no host GUI available in this session. `source_roots` emptiness
and the offline-source `UPDATE` technique were verified headlessly against a
seeded `--smoke` catalog on 2026-07-10 (schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`). Section
structure/control wiring confirmed by source citation
(`Sources/TeststripApp/ActivityCenterView.swift`,
`Sources/TeststripApp/AppModel.swift:2489-2511`). Needs a human-present or
console-unlocked re-run to drive the AX steps, and confirmation of the exact
`sourceAvailabilityDisplayName` strings.
