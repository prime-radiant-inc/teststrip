# import-002-card-copy: Import Card copies into managed storage, dedupes in-batch, and refuses to silently overwrite a collision

**What this covers**: inventory items 2, 7. "Import Card" is the
`.copyToDestination` ingest mode (`IngestPlanner.copyFromCard`,
`IngestPlan.Mode.copyToDestination`) — the source card is never mutated;
files are copied to a chosen destination
(`Sources/TeststripCore/Ingest/IngestService.swift:391`:
`FileManager.default.copyItem(at: sourceFile, to: destinationURL)`). Three
behaviors under test: (1) the source card's files are byte-identical and
mtime-identical after import; (2) byte-identical content appearing twice in
one import batch is copied once, not twice
(`acceptedContentSources` dedupe, `IngestService.swift:227-231`); (3) two
*different*-content source files that would land on the same destination
filename throw rather than silently overwrite
(`IngestService.swift:376-379`: `throw TeststripError.io("ingest destination
already exists ...")` when `contentsEqual` is false).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
- **Card fixture folder**: a source folder simulating a memory card, with a
  duplicate-content pair (same bytes, two filenames) plus one unique frame:
  ```bash
  CARD=$(mktemp -d)/card
  mkdir -p "$CARD"
  printf 'unique-frame-%s' "$(date +%s%N)" > "$CARD/unique.jpg"
  printf 'dup-frame-%s' "$(date +%s%N)" > "$CARD/dup-a.jpg"
  cp "$CARD/dup-a.jpg" "$CARD/dup-b.jpg"   # byte-identical to dup-a.jpg
  shasum -a 256 "$CARD"/*.jpg | sort > /tmp/import-002-card-before.sha256
  for f in "$CARD"/*.jpg; do stat -f "%N %m %z" "$f"; done | sort > /tmp/import-002-card-before.stat
  ```
- **Destination folder** for the copy (a plain empty dir the sheet will be
  pointed at — Import Card requires an explicit destination, unlike Import
  Folder):
  ```bash
  DEST=$(mktemp -d)/managed
  ```
- **Collision fixture** for step 4 — a second card whose `unique.jpg` has the
  *same filename* as an already-imported file but *different* content:
  ```bash
  CARD2=$(mktemp -d)/card2
  mkdir -p "$CARD2"
  printf 'DIFFERENT-CONTENT-%s' "$(date +%s%N)" > "$CARD2/unique.jpg"
  ```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Drive the card-import sheet via the typed-path route
   (`TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`, see
   `LibraryGridChromePolicy.primaryCardImportRoute`,
   `Sources/TeststripApp/LibraryGridView.swift:7268-7275`, default
   `.userGrantedPanel`; `typed-path` maps to `.typedPathSheet`) so no native
   panel is needed. Relaunch (or set the env var on the already-isolated
   process) with `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`, open Import ▾ →
   From Card…, type `$CARD` as the source and `$DEST` as the destination,
   leave duplicate handling at the default (import-all — this card is not
   testing cross-card dedupe, see `import-004-new-only-dedupe.md` for that),
   confirm, press the primary button ("Import N Photos"), wait for completion.
3. **Ground-truth the copy and the source**:
   ```bash
   shasum -a 256 "$CARD"/*.jpg | sort > /tmp/import-002-card-after.sha256
   for f in "$CARD"/*.jpg; do stat -f "%N %m %z" "$f"; done | sort > /tmp/import-002-card-after.stat
   diff /tmp/import-002-card-before.sha256 /tmp/import-002-card-after.sha256
   diff /tmp/import-002-card-before.stat /tmp/import-002-card-after.stat
   find "$DEST" -type f | sort
   sqlite3 "$DB" "SELECT original_path, content_hash FROM assets WHERE original_path LIKE '$DEST%' ORDER BY original_path;"
   ```
4. **Collision case**: import `$CARD2` into the same `$DEST` (same route,
   destination unchanged, so `unique.jpg` in `$CARD2` collides on filename
   with the already-copied `$DEST/unique.jpg` but has different bytes). Start
   Import, wait for the import to finish or surface an error.
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE original_path = '$DEST/unique.jpg';"
   shasum -a 256 "$DEST/unique.jpg" "$CARD2/unique.jpg"
   ```

## Expected
- Step 3 (source untouched): both `diff`s empty. **Fails if** the card's own
  files changed — Import Card must copy, never mutate the source, per the
  non-destructive invariant.
- Step 3 (dedupe): `find "$DEST" -type f` lists **one** file for the
  `dup-a.jpg`/`dup-b.jpg` pair, not two, and the catalog has exactly one
  `assets` row for that content hash. **Fails if** both byte-identical copies
  land in `$DEST` and get cataloged as two separate assets — that means the
  in-batch dedupe (`acceptedContentSources`,
  `Sources/TeststripCore/Ingest/IngestService.swift:227-231`) isn't wired.
- Step 4: **fails if** `$DEST/unique.jpg` silently becomes `$CARD2`'s bytes
  (the shasums would then match and the pre-existing frame is gone — a
  silent overwrite, the worst outcome) or if the import reports success with
  no error surfaced anywhere. **Passes if** either (a) the import summary /
  activity surfaces a per-file error for `$CARD2/unique.jpg` (skipped-file
  handler path, `IngestService.swift:216-219`) while `$DEST/unique.jpg`
  keeps its original bytes, or (b) the whole import sheet reports a failure
  and nothing from `$CARD2` is copied. Quote which of the two happened —
  this card only asserts that overwrite-with-different-content never happens
  silently; it does not mandate one specific UI presentation of the error.

## Cleanup
```bash
rm -rf "$CARD" "$CARD2" "$DEST" \
       /tmp/import-002-card-before.sha256 /tmp/import-002-card-after.sha256 \
       /tmp/import-002-card-before.stat /tmp/import-002-card-after.stat
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **No ready-made driver script for the card-import sheet.** Unlike
  `submit_import_path.sh` (Import Folder only), there is no
  `submit_import_card.sh`; `import-004-new-only-dedupe.md` hand-drives the
  same sheet with `ax_drive.sh find`/`press`/`type` verbs and documents the
  route env var — reuse that pattern rather than inventing a new one.
- The collision-throw path (`TeststripError.io("ingest destination already
  exists ...")`, `IngestService.swift:376-379`) is caught per-file by the
  `skippedSourceFile` handler when the caller supplies one
  (`IngestService.swift:216-219`); only an *absent* handler propagates it as
  a hard batch abort. Confirm which behavior the app's card-import call site
  actually wires (`AppModel.swift` around the `cardImportTaskFactory`,
  line ~3536) before asserting Step 4's exact UI shape — this card's Expected
  is deliberately written to accept either presentation and only fails the
  silent-overwrite case.
- Verify `dup-a.jpg`/`dup-b.jpg` are genuinely byte-identical
  (`shasum -a 256`) before importing, same caveat as
  `import-004-new-only-dedupe.md`'s sharp edge — any incidental byte
  difference (e.g. from `cp` preserving different xattrs, which doesn't
  affect content hash, but a re-encode would) invalidates the dedupe
  assertion.

## Run status
BLOCKED-CONSOLE — no host GUI/display in this environment; Steps 1-2 and 4
were not driven live. Source-confirmed: `.copyToDestination` copies via
`FileManager.default.copyItem` and never touches the source
(`Sources/TeststripCore/Ingest/IngestService.swift:353-373, 375-396`); in-batch
content dedupe via `acceptedContentSources`
(`IngestService.swift:97-99, 227-231`); the collision throw
(`IngestService.swift:376-379`); and the typed-path card-import route env var
`TESTSTRIP_CARD_IMPORT_ROUTE=typed-path` →
`LibraryGridChromePolicy.primaryCardImportRoute`
(`Sources/TeststripApp/LibraryGridView.swift:2551, 7266-7275`, confirmed by
reading source 2026-07-10). The `assets.content_hash`/`original_path` columns
were ground-truthed against a seeded `--smoke` catalog the same day (schema
per `CatalogMigrations.swift:12-25`). Needs a human-present or
console-unlocked re-run to actually drive the sheet and observe the
collision's UI presentation.
