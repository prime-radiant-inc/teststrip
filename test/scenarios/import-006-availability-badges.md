# import-006-availability-badges: Source availability states badge distinctly and gate full-res access

**What this covers**: inventory items 10-12 — the five `SourceAvailability` states
(`online`/`offline`/`missing`/`moved`/`stale`, `Sources/TeststripCore/Domain/SourceAvailability.swift:1-7`),
each rendering a distinct badge (`AssetSourceStatusPresentation.presentation(for:)`,
`Sources/TeststripApp/LibraryGridView.swift:8436-8465`, tint at :8467-8474); and the
invariant that a non-`online` source gates the UI to cached-preview-only
(`SourceAvailability.requiresCachedPreviewOnly`, `Sources/TeststripApp/AppModel.swift:12005-12013`).
The load-bearing scenario: rename a source's on-disk directory out from under a
running, already-imported catalog and assert the badge transitions once the
rescan runs.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
ORIGINALS="$ISOLATED/Teststrip/SmokeOriginals"
```
`--smoke` seeds 24 assets whose `original_path` all live under `$ORIGINALS`
(verified 2026-07-10 against a fresh seed: `SELECT original_path FROM assets`
returns paths of the form `$ORIGINALS/smoke-N.jpg`; `SELECT availability, count(*)
FROM assets GROUP BY availability` reads `online|24` at seed time — no source
starts in any of the four non-online states).

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **Idle assertion**: assert the grid's "Refresh source status" button in the
   query-token toolbar is present but has no attention badge — it is a plain
   `arrow.clockwise` icon button, AXHelp exactly `"Refresh source status"`
   (`Sources/TeststripApp/LibraryGridView.swift:711-718`). Assert `.disabled` is
   false: `model.canRefreshVisibleAssetAvailability` gates it
   (`Sources/TeststripApp/AppModel.swift:2643`).
3. **Rename the source directory out from under the running app** (the
   catalog still believes it's online — nothing watches the filesystem):
   ```bash
   mv "$ORIGINALS" "${ORIGINALS}.moved-away"
   ```
   Confirm the catalog hasn't noticed yet — SQL still reads `online` (no
   filesystem watcher; `SourceAvailabilityProbe` only runs when explicitly
   invoked, see Sharp edges):
   ```bash
   sqlite3 "$DB" "SELECT availability, count(*) FROM assets GROUP BY availability;"
   ```
4. **Trigger the rescan** — this is a worker-driven batch job, not an inline
   probe: `ax_drive.sh press --role AXButton --help "Refresh source status"`
   calls `AppModel.refreshVisibleAssetAvailability()`, which (with a worker
   configured) batches the visible asset IDs by `volumeIdentifier` and enqueues
   `.refreshAvailabilityBatch` commands as `.sourceScan` work items
   (`Sources/TeststripApp/AppModel.swift:8967-8980`, batching at :9102-9121).
   The worker process executes each batch via
   `SourceAvailabilityProbe().availability(for:)`
   (`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:284-300`) and
   writes the result back with `updateAvailability`.
5. Wait for the `.sourceScan` work session to complete:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM work_sessions WHERE kind='sourceScan' AND status IN ('queued','running');"
   ```
   (poll to 0, staying frontmost per README).
6. **Re-check availability**:
   ```bash
   sqlite3 "$DB" "SELECT availability, count(*) FROM assets GROUP BY availability;"
   ```
7. Assert the grid badge for a renamed-away asset now shows the "Missing"
   presentation (title "Missing", detail "Original missing; cached previews
   only", SF Symbol `photo.badge.exclamationmark`,
   `Sources/TeststripApp/LibraryGridView.swift:8446-8451`) with orange tint
   (`AssetSourceStatusPresentation.tint`, default case, :8467-8474 — only
   "Stale" gets `.yellow`).
8. **Gate assertion**: open the inspector (⌘I) on a now-missing asset; assert
   full-res/export actions are disabled or show the cached-preview-only
   messaging — `requiresCachedPreviewOnly` is `true` for `.missing`
   (`Sources/TeststripApp/AppModel.swift:12008`), matching the inspector's
   `availabilityText` (`Sources/TeststripApp/InspectorView.swift:34-36`).

## Expected
- Step 3: pre-refresh SQL still reads `online|24` — **fails if** availability
  changed without the rescan running (would mean an undocumented filesystem
  watcher exists, contradicting the worker-driven model this card assumes).
- Step 6: **fails if** availability is not `missing` for the renamed assets —
  either the probe didn't run, or (per Sharp edges) it classified them as
  `offline` instead because the fixture path superficially resembles a mounted
  volume.
- Step 7: **fails if** the badge doesn't render, renders the wrong title/tint,
  or a `stale`-only yellow tint leaks onto a `missing`/`offline`/`moved` badge.
- Step 8: **fails if** any full-res-only affordance (export at full
  resolution, "reveal in Finder" on the original) stays enabled for a
  cached-preview-only asset.

## Cleanup
```bash
mv "${ORIGINALS}.moved-away" "$ORIGINALS"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **Renaming a local temp-dir fixture yields `.missing`, not `.offline`.**
  `SourceAvailabilityProbe.availability(for:)`
  (`Sources/TeststripCore/Domain/SourceAvailabilityProbe.swift:6-22`) only
  returns `.offline` when the *volume root* is unreachable, and it only
  computes a volume root for paths under `/Volumes/<name>`
  (`volumeRoot(for:)`, :24-30). `--smoke` originals live under
  `$TMPDIR/teststrip-app-support.*`, not `/Volumes`, so a plain `mv`-away always
  surfaces as `missing`. Exercising the true `offline` state (external volume
  unmounted) needs a fixture under `/Volumes` — not producible headlessly in
  this sandbox; note it as a gap rather than faking it with `missing`.
- **`.moved` is not produced by the probe at all.** The `moved` case is written
  only by `CatalogRepository.reconnectSourceRoot` when a reconnect target's
  fingerprint doesn't match (see `import-007-refresh-reconnect.md`) — it isn't
  a state the source-scan rescan can discover on its own; a file relocated
  without going through Reconnect just reads as `missing` until reconnected.
- No automatic on-launch or filesystem-watch rescan exists — availability is
  refreshed only by explicit UI action (this card's toolbar button, or the
  Activity popover's "Refresh source availability", `Sources/TeststripApp/ActivityCenterView.swift:244-251`)
  or by `refreshSelectedAssetAvailability()` on selection
  (`Sources/TeststripApp/AppModel.swift:8959-8965`). A card that assumes a
  passive background scan will hang forever waiting for a badge that never
  appears on its own.

## Run status
SQL-GROUNDED, AX-UNRUN. All SQL and the `.missing`-vs-`.offline` distinction
were verified 2026-07-10 headlessly against a freshly seeded `--smoke`
catalog (baseline `online|24`; `mv` did not itself change the DB, confirming
no filesystem watcher). The AX steps (button press, badge render, inspector
gating) are source-confirmed by file:line above but need a human-present or
isolated-console re-run — this session's shared build host had concurrent
agents contending for `dist/Teststrip.app`, and the seeded instance used for
the SQL check was torn down (by its own `timeout` wrapper) before the AX
half could be driven. Schema per `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
(version 19).
