# import-005-sidecar-on-import: importing alongside .xmp sidecars folds, conflicts, or isolates a bad file — never aborts the batch

**What this covers**: inventory item 8. Three sub-scenarios, each its own
Steps/Expected pair, all driven from the same ingest code path
(`Sources/TeststripCore/Ingest/IngestService.swift:130-186`):
(a) an asset imported next to a **valid pre-existing `.xmp`** sidecar folds
the sidecar's metadata into the catalog
(`MetadataSyncPlanner.decision` → `.importSidecar`, folded at
`IngestService.swift:158-164`); (b) a **second import of the same content**
whose sidecar now disagrees with catalog metadata that changed in between
produces a `metadata_sync_state` row with `status='conflict'`
(`MetadataSyncPlanner.swift:42-47`, recorded via
`repository.recordMetadataSyncConflict`, `IngestService.swift:227-233`) —
**not currently reachable through user gestures alone** (see the (b) rewrite
below and the Sharp edges note); this card instead exercises the two
behaviors a re-import of already-cataloged content actually produces under
new-only ON (default) vs OFF; (c) an **unparsable/corrupt sidecar** flags only
that one asset as a conflict
(`IngestService.swift:173-186`: the catch block routes an unparsable sidecar
into `sidecarConflicts` rather than rethrowing) while the rest of the batch
still imports successfully.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

- **Sidecar naming**: a sidecar for `foo.jpg` lives at `foo.jpg.xmp`
  (`XMPSidecarStore.defaultSidecarURL`,
  `Sources/TeststripCore/Metadata/XMPSidecarStore.swift:20-22`).
- **A valid minimal XMP packet** (the exact attribute/element shape
  `XMPPacket.parse` expects — root `x:xmpmeta`/`adobe:ns:meta/`, an
  `rdf:Description` carrying `xmp:Rating`, `ts:Pick`, and a `dc:subject`
  `rdf:Bag`; verified against `Sources/TeststripCore/Metadata/XMPPacket.swift:99-163`
  and confirmed well-formed with `xmllint --noout` on 2026-07-10):
  ```bash
  cat > /tmp/import-005-valid.xmp <<'XMPEOF'
  <?xml version="1.0" encoding="UTF-8"?>
  <x:xmpmeta xmlns:x="adobe:ns:meta/">
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:ts="https://teststrip.app/xmp/1.0/" xmp:Rating="5" ts:Pick="pick">
        <dc:subject>
          <rdf:Bag>
            <rdf:li>sunset</rdf:li>
          </rdf:Bag>
        </dc:subject>
      </rdf:Description>
    </rdf:RDF>
  </x:xmpmeta>
  XMPEOF
  ```
- **A corrupt/unparsable sidecar** — truncated XML, not even well-formed
  (confirmed `xmllint --noout` fails on it with a namespace/parse error):
  ```bash
  printf '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF><rdf:Description rdf:about="" xmp:Rating="3"' > /tmp/import-005-corrupt.xmp
  ```
- **Fixture folder for (a) and (c)** — one asset with the valid sidecar, one
  with the corrupt sidecar, one with no sidecar at all (the batch-survival
  control):
  ```bash
  FIXTURE=$(mktemp -d)/sidecars
  mkdir -p "$FIXTURE"
  printf 'frame-a' > "$FIXTURE/valid-frame.jpg"
  cp /tmp/import-005-valid.xmp "$FIXTURE/valid-frame.jpg.xmp"
  printf 'frame-b' > "$FIXTURE/corrupt-frame.jpg"
  cp /tmp/import-005-corrupt.xmp "$FIXTURE/corrupt-frame.jpg.xmp"
  printf 'frame-c' > "$FIXTURE/plain-frame.jpg"
  ```

## Steps

### (a) Valid sidecar folds on import
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Import `$FIXTURE` via the typed-path route:
   ```bash
   script/submit_import_path.sh Teststrip "$FIXTURE"
   ```
3. Wait for completion, then read the catalog:
   ```bash
   sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE original_path = '$FIXTURE/valid-frame.jpg';"
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id = (SELECT id FROM assets WHERE original_path = '$FIXTURE/valid-frame.jpg');"
   ```

### (b) Re-importing already-cataloged content with an out-of-band sidecar edit
Confirmed unreachable as originally written (see Sharp edges): the app's own
metadata writes immediately mirror to the sidecar and re-sync
`lastSynced`/`catalog_generation` at write time, so a re-import can never
observe *both* "catalog changed since last sync" AND "sidecar changed since
last sync" through this recipe — `localChanged` is always false by the time
the sidecar edit is picked up. This sub-scenario instead exercises the two
behaviors that a re-import of already-cataloged content actually produces,
gated by the **import-new-only** toggle:

4. **Change the catalog side** of `valid-frame.jpg`'s metadata through the
   app (not the sidecar) — e.g. rate it differently via the inspector
   (`ax_drive.sh press --role AXButton --help "Rate 2"` with the asset
   selected). This write immediately mirrors to the sidecar and updates
   `lastSynced` (confirmed live 2026-07-10).
5. **Change the sidecar out-of-band** to a third, different rating (not the
   original 5, not the step-4 rating):
   ```bash
   sed -i '' 's/Rating="5"/Rating="1"/' "$FIXTURE/valid-frame.jpg.xmp"
   ```
6a. **Re-import with import-new-only ON (the default)**:
   ```bash
   script/submit_import_path.sh Teststrip "$FIXTURE"
   ```
   `.skipCatalogedContent` early-continues before the sidecar is even
   examined (`IngestService.swift:102-121`) — ground-truth:
   ```bash
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id = (SELECT id FROM assets WHERE original_path = '$FIXTURE/valid-frame.jpg');"
   sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE original_path = '$FIXTURE/valid-frame.jpg';"
   ```
6b. **Re-import with import-new-only OFF** (toggle off in the confirmation
   sheet, same folder): the planner now runs and folds the sidecar
   (`.importSidecar`, unconditional overwrite — not `.conflict`, since
   `localChanged` is false per the note above):
   ```bash
   script/submit_import_path.sh Teststrip "$FIXTURE"
   ```
   ```bash
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id = (SELECT id FROM assets WHERE original_path = '$FIXTURE/valid-frame.jpg');"
   sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE original_path = '$FIXTURE/valid-frame.jpg';"
   ```

### (c) Corrupt sidecar isolates one asset, batch still completes
8. (Uses the same import from Steps 2/3, which already included
   `corrupt-frame.jpg` and `plain-frame.jpg` in the batch — no separate
   import needed.) Ground-truth all three fixture assets landed:
   ```bash
   sqlite3 "$DB" "SELECT original_path FROM assets WHERE original_path LIKE '$FIXTURE/%' ORDER BY original_path;"
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id = (SELECT id FROM assets WHERE original_path = '$FIXTURE/corrupt-frame.jpg');"
   ```

## Expected
- (a) Step 3: `metadata_json` shows `rating=5`, the keyword `sunset`, no
  reject/pick mismatch — the sidecar's values, not the smoke-seed defaults.
  `metadata_sync_state.status` is **not** `'conflict'` (a fresh import always
  folds unconditionally per `MetadataSyncPlanner.swift:24-25` — there is no
  `metadata_sync_state` row with status `'conflict'` for this asset). **Fails
  if** the catalog metadata is empty/default (the fold never happened) or a
  conflict was recorded for a first-time import.
- (b) Step 6a (new-only ON, default): `metadata_sync_state.status` stays
  `'synced'` and `metadata_json` still shows the step-4 rating (2) — the
  sidecar's step-5 edit (rating 1) is never examined. **Fails if** the status
  changed to `'conflict'` or the rating changed (would mean
  `.skipCatalogedContent` stopped early-continuing, a different bug).
- (b) Step 6b (new-only OFF): `metadata_sync_state.status` stays `'synced'`
  and `metadata_json` now shows the sidecar's step-5 rating (1) — an
  unconditional fold, not a conflict record. **Fails if** `status` becomes
  `'conflict'` (would mean `localChanged` was somehow true, contradicting the
  write-time re-sync this sub-scenario documents) or the rating didn't
  change (the fold didn't run).
- **Product gap, not a card failure**: neither 6a nor 6b ever produces
  `metadata_sync_state.status = 'conflict'` for this recipe. Out-of-band
  sidecar edits/corruption on already-synced content are invisible to the
  app — new-only ON never looks at the sidecar again, and new-only OFF
  silently overwrites the catalog with the sidecar's value with no dual-
  divergence detection. There is no UI-reachable rescan trigger that stages
  the `(localChanged, sidecarChanged)` = `(true, true)` conflict branch; see
  `activity-006-xmp-lifecycle.md` sub-case A/B (same finding, confirmed twice)
  for the cross-referenced product gap.
- (c) Step 8: all three of `valid-frame.jpg`, `corrupt-frame.jpg`, and
  `plain-frame.jpg` appear as cataloged assets — the corrupt sidecar did not
  abort the batch. `corrupt-frame.jpg`'s `metadata_sync_state.status` is
  `'conflict'`. **Fails if** fewer than 3 rows are cataloged (the corrupt
  sidecar took the whole import down) or if `corrupt-frame.jpg` shows no
  conflict record at all (the bad sidecar was silently dropped instead of
  being flagged for review).

## Cleanup
```bash
rm -rf "$FIXTURE" /tmp/import-005-valid.xmp /tmp/import-005-corrupt.xmp
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **Sub-scenario (b) cannot be produced on a first-time import**, and — per a
  2026-07-10 live run — **not through a same-content re-import either.**
  `MetadataSyncPlanner.decision` (`MetadataSyncPlanner.swift:24-25`) always
  returns `.importSidecar` unconditionally when `lastSynced == nil`, true for
  every brand-new asset. The conflict branch instead needs
  `(localChanged, sidecarChanged) = (true, true)` on a re-import. But every
  in-app metadata write immediately mirrors to the sidecar and updates
  `lastSynced`/`catalog_generation` at write time (verified live: rating
  `valid-frame.jpg` via the inspector both wrote `metadata_json` and re-synced
  `lastSynced` in the same gesture) — so by the time a re-import runs,
  `localChanged` is always false, and dual divergence can never be staged
  through user gestures alone; there is no UI-reachable rescan trigger that
  would re-evaluate `localChanged` against a stale `lastSynced` (cross-ref
  `activity-006-xmp-lifecycle.md`). The steps above were rewritten to assert
  the two behaviors that a re-import of already-cataloged content actually
  produces (silently-ignored sidecar edit under new-only ON; unconditional
  fold under new-only OFF) rather than an unreachable conflict.
- **No dedicated conflict table.** There is no `xmp_conflicts` or
  `sidecar_conflicts` table in the schema
  (`Sources/TeststripCore/Catalog/CatalogMigrations.swift`) — conflicts are
  rows in the general-purpose `metadata_sync_state` table
  (`CatalogMigrations.swift:29-38`) with `status = 'conflict'`
  (`CatalogRepository.swift:1973-1981, 2026-2027`), the same table used for
  the ordinary background sync scan. A card or driver assuming a
  purpose-built conflicts table would query the wrong thing.
- The `xmllint --noout` check on the fixtures in Pre-state is a cheap,
  independent sanity check (not a Teststrip API) — it does not guarantee
  `XMPPacket.parse` accepts the valid fixture (that parser is stricter:
  specific namespace URIs, specific attribute/element local names), only
  that the corrupt fixture is corrupt for the right reason (malformed XML,
  not merely semantically wrong XMP). Confirmed by reading
  `XMPPacket.parse`'s namespace/attribute expectations
  (`XMPPacket.swift:99-163`) against the hand-built `valid.xmp`, but this was
  not exercised through the actual Swift parser in this headless pass.

## Run status
BLOCKED-CONSOLE — no host GUI/display in this environment; no AX steps were
executed live, and the fixtures were not run through an actual import (only
`xmllint`-checked for well-formedness and hand-verified against
`XMPPacket.parse`'s expected shape by reading source). Source-confirmed the
fold/conflict/corrupt-isolation wiring:
`Sources/TeststripCore/Ingest/IngestService.swift:130-186`,
`Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift:13-48`,
`Sources/TeststripCore/Catalog/CatalogRepository.swift:2026-2027` — read
2026-07-10. The `metadata_sync_state` schema and the general
`assets`/`metadata_json` query shape were ground-truthed headlessly against a
seeded `--smoke` catalog the same day (schema per
`CatalogMigrations.swift:12-38`); the specific per-asset queries in this card
(filtered by `original_path` under a fixture folder) were not run against a
populated fixture import since that requires a live app to drive the ingest.
Needs a human-present or console-unlocked re-run to actually drive Steps 2,
4, and 6a/6b and confirm the fixtures behave as predicted.
