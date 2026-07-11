# import-001-folder-in-place: Import Folder never touches the original bytes, and fresh assets come online

**What this covers**: inventory items 1, 6, 9. "Import Folder" is the
`.addInPlace` ingest mode (`IngestPlanner.addFolder`, `IngestPlan.Mode.addInPlace`) —
`prepareOriginalFile` is a no-op for this mode
(`Sources/TeststripCore/Ingest/IngestService.swift:359-361`: `case .addInPlace: return`),
so nothing is copied, moved, or rewritten; the source folder is cataloged
where it sits. The load-bearing assertion is that every original file's bytes
and mtime are identical before and after import — not "looks unchanged in the
UI," but a checksum/mtime diff against a pre-import snapshot. Item 9: freshly
imported assets must come online correctly — `availability = 'online'` in the
catalog, not `missing`/`offline`/`stale` (`Sources/TeststripCore/Domain/SourceAvailability.swift`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
- **Fixture folder** — a handful of plain files stand in for photos; the
  ingest scanner only cares about file bytes/mtime for this card, not decode
  validity:
  ```bash
  FIXTURE=$(mktemp -d)/inplace
  mkdir -p "$FIXTURE"
  for n in 1 2 3; do
    printf 'frame-%d-%s' "$n" "$(date +%s%N)" > "$FIXTURE/frame-$n.jpg"
  done
  ```
- **Snapshot checksums and mtimes before import** (the pre-state the whole
  card is falsified against):
  ```bash
  shasum -a 256 "$FIXTURE"/*.jpg | sort > /tmp/import-001-before.sha256
  for f in "$FIXTURE"/*.jpg; do stat -f "%N %m %z" "$f"; done | sort > /tmp/import-001-before.stat
  ```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Import `$FIXTURE` via the typed-path route (no native panel needed; the
   isolated launch always exposes it per
   `LibraryGridChromePolicy.shouldExposeImportPathControl`,
   `Sources/TeststripApp/LibraryGridView.swift:7282-7284`, which is gated on
   `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` being set — true for every
   `build_and_run.sh --isolated/--smoke` launch):
   ```bash
   script/submit_import_path.sh Teststrip "$FIXTURE"
   ```
   This drives Import Path → types the path → Review Import → the primary
   button (labeled "Import N Photos", matched by the driver's title-prefix
   helper since N varies with the scan).
3. Wait for the import to complete (`ax_drive.sh wait --role AXStaticText --contains "Import"` or
   poll `model.isImporting` indirectly via the toolbar Import button re-enabling —
   `ax_drive.sh find --role AXButton --label "Import"` once no longer disabled).
4. **Re-checksum and re-stat the same files, in place**:
   ```bash
   shasum -a 256 "$FIXTURE"/*.jpg | sort > /tmp/import-001-after.sha256
   for f in "$FIXTURE"/*.jpg; do stat -f "%N %m %z" "$f"; done | sort > /tmp/import-001-after.stat
   diff /tmp/import-001-before.sha256 /tmp/import-001-after.sha256
   diff /tmp/import-001-before.stat /tmp/import-001-after.stat
   ```
5. **Ground-truth the catalog**:
   ```bash
   sqlite3 "$DB" "SELECT original_path, availability FROM assets WHERE original_path LIKE '$FIXTURE/%' ORDER BY original_path;"
   ```
   (Verified column names against `Sources/TeststripCore/Catalog/CatalogMigrations.swift:12-25`:
   `assets.original_path`, `assets.availability`; a fresh `--smoke` catalog
   dry-run on 2026-07-10 shows all 24 seeded assets with `availability='online'`.)

## Expected
- Step 4: both `diff`s are empty. **Fails if** either checksum or mtime
  changed — that means Import Folder copied, re-encoded, or touched the
  originals, violating the non-destructive invariant (see `CLAUDE.md`
  "Non-destructive": original image bytes are never modified).
- Step 5: exactly 3 rows, one per fixture file, each `availability = 'online'`.
  **Fails if** a row is missing (the asset never came online — silently
  dropped) or shows `availability` other than `'online'` (comes online as
  stale/missing instead of a normal available asset).
- Step 5 (path check): `original_path` for each row equals the fixture file's
  own path, not a path under any managed-storage/import-destination
  directory — proof this was an in-place catalog, not a copy.

## Cleanup
```bash
rm -rf "$FIXTURE" /tmp/import-001-before.sha256 /tmp/import-001-after.sha256 \
       /tmp/import-001-before.stat /tmp/import-001-after.stat
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- `submit_import_path.sh` drives the **Import Path** dev/automation control,
  which is functionally the same `.addInPlace` ingest path as the toolbar
  "Import ▾ → Folder…" item (both call `model.requestImportFolder()` /
  `IngestPlanner.addFolder`) — using it instead of the native NSOpenPanel
  route is a driving-mechanism substitution, not a semantic one, and keeps
  this card headless-runnable via the typed-path sheet.
- The fixture files are plain text stand-ins, not real JPEGs. That's fine for
  checksum/mtime/availability assertions (this card never touches decode,
  preview generation, or EXIF), but don't reuse this fixture for a card that
  needs valid image bytes.

## Run status
BLOCKED-CONSOLE — no host GUI/display in this environment, so the AX-driven
Steps 1-3 were not executed live. Source-confirmed the wiring: `.addInPlace`
mode is a no-op copy path
(`Sources/TeststripCore/Ingest/IngestService.swift:359-361`), and the toolbar/
typed-path routes both funnel through the same `IngestPlanner.addFolder`
(`Sources/TeststripCore/Ingest/IngestPlanner.swift:47-56`). The Step 5 catalog
query and the `availability` column semantics were ground-truthed headlessly
against a seeded `--smoke` catalog on 2026-07-10
(`/var/folders/.../teststrip-app-support.*/Teststrip/catalog.sqlite`, schema
per `CatalogMigrations.swift`): all 24 seeded assets read `availability='online'`.
The checksum/mtime diff (Steps 1-4) needs a human-present or console-unlocked
re-run to drive the actual import through the app.
