# inspect-003-sync-status-conflict-resolver: Sync status priority and the three conflict resolutions

**What this covers**: the Info tab's metadata sync status line — its
priority ordering (conflict beats pending beats synced beats nothing shown)
— and, for the conflict state specifically, the field-by-field diff and all
three resolution actions (Merge Missing, Use Catalog, Use XMP), each
verified against real catalog and sidecar state on disk. This is structured
as three independent mini-scenarios (one per resolution), each starting from
a freshly forced conflict, since resolving destroys the conflict state.

## Pre-state (shared setup, repeated per mini-scenario)
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
```
`metadata_sync_state` is empty on a fresh `--smoke` catalog (confirmed by
dry-run: `SELECT * FROM metadata_sync_state` returns 0 rows) — `synced`,
`pending`, and `conflict` states must all be induced by the steps below, not
pre-seeded. Schema (`sqlite3 "$DB" ".schema metadata_sync_state"`):
```sql
CREATE TABLE metadata_sync_state (
    asset_id TEXT PRIMARY KEY NOT NULL,
    sidecar_path TEXT NOT NULL,
    catalog_generation INTEGER NOT NULL,
    last_synced_fingerprint TEXT NOT NULL,
    status TEXT NOT NULL,          -- 'pending' | 'conflict'
    updated_at REAL NOT NULL
);
```
There is no `'synced'` row in this table — `synced` is a derived Info-tab
state (`asset.metadata.hasWrittenPortableMetadata` with no pending/conflict
row present; see `InspectorMetadataSyncStatus.init`,
`Sources/TeststripApp/InspectorView.swift:371-378`).

## Part A — priority ordering (non-destructive, single pass)
### Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 Library; select `$SRC`.
2. Before any rating: assert **no** sync status line renders in Info (no
   sidecar written yet, `InspectorMetadataSyncStatus.init` returns nil).
3. Rate `$SRC` 4 stars (`ax_drive.sh press --role AXButton --help "Rate 4"`,
   on the Describe tab). Switch to Info. Assert the sync status line now
   reads **"Saved to sidecar · `<basename>.xmp`"** in green (the `synced`
   kind, `InspectorView.swift:792-797`) — confirm on disk:
   ```bash
   test -f "$SRC.xmp" && grep -o 'xmp:Rating="[0-9-]*"' "$SRC.xmp"
   ```
4. **Force `pending`.** Make the sidecar folder briefly unwritable, then
   change the rating again to trigger a sync attempt that fails and queues:
   ```bash
   chmod 000 "$(dirname "$SRC")"
   ```
   Rate `$SRC` 2 stars via the UI. Assert the sync status line now reads
   "XMP sync pending" (yellow, `arrow.triangle.2.circlepath`,
   `InspectorMetadataSyncStatus.init` pending branch,
   `InspectorView.swift:360-370`) — cross-check:
   ```bash
   sqlite3 "$DB" "SELECT asset_id, status FROM metadata_sync_state WHERE asset_id=(SELECT id FROM assets WHERE original_path='$SRC');"
   ```
   Restore permissions: `chmod 755 "$(dirname "$SRC")"`. Click the Info tab's
   "Retry" button (`InspectorView.swift:847-853`,
   `model.retrySelectedMetadataSync`); assert the status line reverts to
   "Saved to sidecar" and the `metadata_sync_state` row for `$SRC` is gone
   (`clearMetadataSyncState` / re-synced path).
5. **Priority check**: while both a conflict and pending state could
   theoretically coexist for the same asset, `InspectorMetadataSyncStatus.init`
   checks `conflictItems` before `pendingItems` before the synced fallback
   (`InspectorView.swift:330-378`) — Part B directly forces a `conflict` row
   and confirms it is what renders (conflict is the only state under test
   there, so this is the priority order's top rung; pending-over-synced was
   just shown in step 4).

## Part B — the conflict resolver, three ways
Each of B1/B2/B3 starts fresh: relaunch `--smoke` (`Pre-state` above) and
repeat this force-a-conflict setup before its own resolution step.

### Forcing a real conflict (repeat before each of B1/B2/B3)
1. Select `$SRC`; rate it 5 stars via Describe (writes catalog + sidecar,
   `synced` state per Part A step 3).
2. Externally edit the sidecar's rating to disagree with the catalog:
   ```bash
   sed -i '' 's/xmp:Rating="5"/xmp:Rating="2"/' "$SRC.xmp"
   ```
3. Also change the catalog side so both sides disagree with the last-synced
   fingerprint (not just the sidecar): set a color label via the UI
   (Describe tab, e.g. click the "Red" label swatch). This mutates the
   catalog after the sidecar was already hand-edited, so both sides now
   differ from `last_synced_fingerprint` — the actual trigger for `conflict`
   is the catalog write's `applyMetadataSnapshot` path detecting the sidecar
   changed out from under it (verify against
   `CatalogRepository.swift` conflict-marking call, e.g. around
   `try metadataSyncItem(...)`/`markMetadataSynced` callers — confirm exact
   trigger condition by reading `Sources/TeststripCore/Catalog/CatalogRepository.swift:1973-2027`
   at run time; the mechanism is fingerprint-mismatch detection on sidecar
   write, not a special "external edit" flag).
4. Switch to Info. Assert the sync status line reads "XMP conflict" (red,
   `InspectorMetadataSyncStatus.init` conflict branch,
   `InspectorView.swift:330-359`), and the field diff shows exactly the rows
   that differ — expect a **Rating** row (`5` → `2`, catalog → sidecar) at
   minimum (`conflictRows`, `InspectorView.swift:419-429`, which only emits
   a row per field when `catalogValue != sidecarValue`,
   `InspectorView.swift:431-434`). Confirm on disk:
   ```bash
   sqlite3 "$DB" "SELECT status FROM metadata_sync_state WHERE asset_id=(SELECT id FROM assets WHERE original_path='$SRC');"
   sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE original_path='$SRC';"
   grep -o 'xmp:Rating="[0-9-]*"' "$SRC.xmp"
   ```

### B1 — Merge Missing
5. Click "Merge Missing" (`InspectorMetadataConflictActionPresentation`,
   title "Merge Missing", `InspectorView.swift:1315-1321`,
   `model.resolveSelectedMetadataConflictByMergingMissingSidecarFields`).
6. Assert: since **rating is non-zero on the catalog side (5)**, the merge
   keeps the catalog's rating (catalog wins on non-missing fields —
   `metadataByMergingMissingSidecarFields`, `AppModel.swift:6639-6664`, only
   overwrites a field when the *catalog* side is the zero/nil/empty
   "missing" sentinel). Confirm: `metadata_json` still shows `"rating":5`,
   and the rewritten sidecar now also carries `xmp:Rating="5"` (merge writes
   a merged sidecar, `AppModel.swift:6813-6822`). Assert
   `metadata_sync_state` no longer has a `conflict` row for `$SRC`.

### B2 — Use Catalog
5. (Fresh conflict per the shared steps above.) Click "Use Catalog"
   (`model.resolveSelectedMetadataConflictUsingCatalog`,
   `AppModel.swift:6324-6329`).
6. Assert the catalog's rating (5) is unchanged and the sidecar is
   overwritten to match: `xmp:Rating="5"` on disk after the click, replacing
   the hand-edited `"2"`. Assert `metadata_sync_state` conflict row cleared.

### B3 — Use XMP
5. (Fresh conflict per the shared steps above.) Click "Use XMP"
   (`model.resolveSelectedMetadataConflictUsingSidecar`,
   `AppModel.swift:6331-6336`, `resolveMetadataConflictUsingSidecar`,
   `AppModel.swift:6780-6811`).
6. Assert the catalog's rating is overwritten to the sidecar's hand-edited
   value (`2`): `sqlite3 "$DB" "SELECT metadata_json ..."` shows `"rating":2`.
   Assert this is undoable: `⌘Z` reverts the rating back to 5 in the catalog
   (per `recordMetadataChangeGroup(label: "Resolved XMP conflict", ...)`,
   `AppModel.swift:6803-6807` — only recorded `if originalAsset.metadata !=
   sidecarMetadata`, i.e. only when the resolution actually changed
   something).

### B4 — sidecar-unreadable disables Merge Missing and Use XMP
7. (Fresh conflict per shared steps, but before viewing Info tab) corrupt the
   sidecar so it fails to parse:
   ```bash
   echo "not xml" > "$SRC.xmp"
   ```
8. Switch to Info. Assert the conflict detail text reads "XMP sidecar
   metadata could not be read..." (`conflictDetail`,
   `InspectorView.swift:410-413`) and that "Merge Missing" and "Use XMP" are
   both disabled (`isEnabled: sidecarMetadataReadable` on both action kinds,
   `InspectorView.swift:1313-1336`) while "Use Catalog" remains enabled
   (`isEnabled: true` unconditionally, `:1322-1327`).

## Expected
- Part A step 2: no status line pre-sidecar. **Fails if** a status renders
  before any write.
- Part A step 3: "Saved to sidecar" (green) after first rating write, and the
  on-disk XMP carries the matching rating. **Fails if** the label, color, or
  on-disk value diverges.
- Part A step 4: pending renders while the sidecar folder is unwritable, and
  clears to synced after Retry succeeds. **Fails if** pending never appears,
  or Retry doesn't clear the `metadata_sync_state` row.
- Part B step 4: conflict renders with a Rating diff row showing `5` → `2`.
  **Fails if** the diff is empty, wrong-directioned, or the wrong kind
  (pending/synced) renders instead.
- B1: catalog rating (5) wins because it's non-zero; sidecar is rewritten to
  match. **Fails if** the merge instead took the sidecar's `2`, or the
  sidecar wasn't rewritten.
- B2: sidecar forcibly matches catalog (5). **Fails if** the sidecar still
  shows `2` after the click.
- B3: catalog forcibly matches sidecar (2), and the change is undoable via
  ⌘Z. **Fails if** the catalog doesn't move to `2`, or ⌘Z doesn't restore
  `5`.
- B4: Merge Missing and Use XMP are both disabled, Use Catalog stays enabled,
  when the sidecar is unreadable. **Fails if** any disabled action is
  clickable, or Use Catalog is also (wrongly) disabled.

## Cleanup
```bash
rm -f "$SRC.xmp"
chmod 755 "$(dirname "$SRC")" 2>/dev/null || true
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The exact fingerprint-mismatch mechanism that flips a `metadata_sync_state`
  row from absent/pending to `conflict` was not verified live (blocked
  console) — step B's "forcing a real conflict" recipe (hand-edit sidecar,
  then make an unrelated catalog write) is inferred from
  `CatalogRepository.swift:1973-2027` and needs confirmation on first live
  run; if it doesn't trigger, dump `metadata_sync_state` after each sub-step
  to find where the status actually flips, and correct this card rather than
  quietly declaring success.
- B1-B3 mutate shared isolated state destructively (each needs the conflict
  re-forced) — do not attempt to reuse one conflict across multiple
  resolutions; a resolved conflict clears the `metadata_sync_state` row
  entirely and there is no "undo the resolution and get the conflict back"
  path other than re-forcing it.
- Part A step 4's `chmod 000` on the *directory* containing `$SRC` may also
  block reading the original for preview generation, not just sidecar
  writes — watch for an unrelated preview-failure status appearing
  simultaneously and don't conflate it with the pending-sync status under
  test.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed
statically: `Sources/TeststripApp/InspectorView.swift:283-448`
(`InspectorMetadataSyncStatus`, priority via `init(asset:pendingItems:
conflictItems:...)`, `conflictRows`, `conflictDetail`), `:862-886`
(`metadataConflictControls`, `applyMetadataConflictAction`), `:1296-1338`
(`InspectorMetadataConflictActionPresentation.actions(sidecarMetadataReadable:)`),
`Sources/TeststripApp/AppModel.swift:6324-6420` (the three
`resolveSelectedMetadataConflict*` entry points, `retrySelectedMetadataSync`,
undo/redo stack), `:6639-6664` (`metadataByMergingMissingSidecarFields`,
catalog-wins-on-non-missing semantics), `:6780-6860` (Use XMP / Merge Missing
implementations, undo-group recording only on an actual change),
`Sources/TeststripCore/Metadata/XMPPacket.swift:68` (`xmp:Rating="N"`
serialization used for the hand-edit in step B2). Needs a human-present
re-run. All SQL and schema in this card were run headlessly against a seeded
--smoke catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift); `metadata_sync_state`
was confirmed empty on a fresh smoke seed.
