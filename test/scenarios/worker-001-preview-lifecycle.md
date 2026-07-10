# worker-001-preview-lifecycle: Preview badges track the worker from queued to built

**What this covers**: the grid cell's preview-status badge as the
out-of-process worker actually processes an asset — "Preview queued" →
"Building preview" (and "Preview issue" if a request errors) → a rendered
thumbnail. `--smoke`'s 24 synthetic photos are **pre-rendered** (their
previews already exist on disk at launch), so this card cannot observe the
lifecycle against the smoke seed alone — it imports a small fresh fixture
folder mid-card so there are assets that genuinely start queued/building.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
FIXTURES=$(mktemp -d)/fresh
swift run TeststripBench seed-dup-fixtures "$FIXTURES"
IMPORT_DIR="$FIXTURES/card2"   # N=4 shared + M=2 new JPEGs; any small folder works
```
Confirm the smoke seed really is pre-rendered before relying on that premise:
```bash
sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue;"   # expect 0 at idle
```
(Verified against a seeded `--smoke` catalog 2026-07-10: reads 0 — nothing
queued, because `--smoke` pre-renders. Confirms the card must import fresh
content to see a queued/building state at all.)

## Steps
1. `script/ax_drive.sh wait-vended`, then confirm idle (query above reads 0)
   before importing — a stale queue from a prior run would make Step 3's
   "queued" observation ambiguous.
2. **Import `$IMPORT_DIR`.** Use the typed-path route so no native panel is
   needed: relaunch (or drive) with `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`,
   open the card-import sheet (`script/submit_import_path.sh Teststrip
   "$IMPORT_DIR"`), leave defaults, start import. Do **not** wait for
   completion before the next step — the race is the point.
3. **Catch the in-flight state.** Within the first second or two after
   import starts, poll both the render and ground truth in the same beat:
   ```bash
   sqlite3 "$DB" "SELECT asset_id, level, attempt_count FROM preview_generation_queue;"
   ```
   For at least one freshly imported asset, find its grid cell
   (`ax_drive.sh wait --role AXStaticText --contains "<filename>"` after
   scrolling into view) and read its status badge's `AXHelp`/title. Per
   `AssetGridPreviewStatusPresentation.presentation`
   (`Sources/TeststripApp/LibraryGridView.swift:7111-7146`) the badge title is
   exactly one of:
   - `"Preview queued"` — a `preview_generation_queue` row exists, `level` in
     `{grid, micro}`, `attempt_count == 0`, no `last_error`.
   - `"Building preview"` — the asset's `.grid`/`.micro` level is in the
     worker's *active* levels (dispatched, not just queued).
   - `"Preview issue"` — a thumbnail-level queue row has `attempt_count > 0`
     or a non-empty `last_error` (a retried/failed generate).
4. **Wait for drain**, staying frontmost every poll (`ax_drive.sh
   wait-vended` before each check — a backgrounded app parks its AX tree):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue WHERE asset_id IN (
     SELECT id FROM assets WHERE original_path LIKE '%$IMPORT_DIR%');"
   ```
   Poll until 0.
5. **Assert the landed state.** The badge disappears (title 4 (line 7124)
   guards on `previewURL == nil` — once a preview URL exists the badge
   presentation returns `nil`) and the grid cell renders an actual thumbnail
   image, not a placeholder icon.

## Expected
- Step 3: at least one freshly imported asset is observed with a queued or
  building badge (title exactly `"Preview queued"` or `"Building preview"`,
  cross-checked against the `preview_generation_queue` row). **Fails if**
  every imported asset already shows a thumbnail on the very first poll — the
  race was missed and the card proves nothing; tighten the poll interval and
  retry rather than treating it as pass.
- Step 5: **Fails if** the queue drains to 0 in ground truth but the grid
  cell keeps showing a queued/building badge (render lags catalog — a real
  UI bug) or never renders a thumbnail at all.
- If any thumbnail-level row shows `attempt_count > 0` at any poll, capture
  its `last_error` and report — that's the `"Preview issue"` path exercised
  by a real generation failure, not the happy path this card targets.

## Cleanup
```bash
rm -rf "$FIXTURES"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Preview generation on 6 small fixture JPEGs is typically sub-second on
  Apple silicon — the "queued"/"building" window may be narrow. Poll tightly
  (every 100-200ms) right after starting import rather than after a fixed
  sleep, or the race in Step 3 will be missed entirely.
- The badge's `AssetGridPreviewStatusPresentation` only inspects `.grid`/
  `.micro` levels (`thumbnailLevels` at LibraryGridView.swift:7123); larger
  preview levels (medium/large) queuing or failing does not move this badge.
  Don't confuse a stalled `.medium` loupe preview with a stalled thumbnail.
- `seed-dup-fixtures` is built for the duplicate-detection card, not this
  one — it is used here only because it is a convenient, known-small, fast
  fixture generator (`DuplicateFixtureSeederTests`). Any small folder of
  fresh JPEGs works equally well.

## Run status
SQL (idle-queue check) was ground-truthed headlessly against a seeded
`--smoke` catalog on 2026-07-10 (schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`); badge title strings
were confirmed by reading `AssetGridPreviewStatusPresentation.presentation`
source directly, not observed live. The import-then-poll AX/live-driving
steps (2-5) were not run — no host GUI available in this session — and need
a human-present or console-unlocked re-run.
