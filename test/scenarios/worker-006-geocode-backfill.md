# worker-006-geocode-backfill: Geocode queue processes in throttled batches with a negative cache

**SKIP-offline. This card requires real reverse-geocoding network calls and
cannot be executed in a network-isolated CI/sandbox environment. It must be
run manually on a machine with network access.**

**What this covers**: the geocode pipeline processes GPS-tagged assets in
throttled batches of 50
(`AppModel.geocodeBatchSize`, `Sources/TeststripApp/AppModel.swift:7322`,
scan-limited to 500 pending coordinates per enqueue pass,
`geocodeEnqueueScanLimit`, `AppModel.swift:7323`), results land in
`place_cache`
(`Sources/TeststripCore/Catalog/CatalogMigrations.swift:212-220`), assets
with no resolvable location get a **nil-cached negative result** rather than
being re-queried every time (`reverseGeocodeBatch`'s comment and behavior,
`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:328-330`: "A nil
result (no place found) is still cached with all-nil components so the
coordinate leaves the queue and is never retried forever" —
`recordPlaceName` with all-nil fields, `CatalogRepository.swift:577-597`),
successful geocodes have map-visible effects, and the pipeline degrades
gracefully offline — a failed lookup increments `geocode_queue.attempt_count`
(`recordGeocodeFailure`, `CatalogRepository.swift:562-574`) up to
`reverseGeocodeMaximumAttemptCount = 5`
(`WorkerCommandExecutor.swift:115`), not a crash or wedge.

## Pre-state
```bash
./script/build_and_run.sh --sample-photos   # needs real GPS-tagged photos, not --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Confirm the sample corpus actually has GPS-tagged assets before relying on
this card — if `--sample-photos` doesn't seed any, use `--real-corpus` or a
manually GPS-tagged fixture instead:
```bash
sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_valid(technical_metadata_json)
  AND json_extract(technical_metadata_json, '\$.latitude') IS NOT NULL;"
```

## Steps
1. `script/ax_drive.sh wait-vended`. Record the pre-geocode state:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM geocode_queue;"
   sqlite3 "$DB" "SELECT count(*) FROM place_cache;"
   ```
2. **Trigger the geocode pass.** `AppModel.enqueuePendingGeocoding`
   (`AppModel.swift:7325-7334`) scans up to 500 pending coordinates and
   dispatches a `geocode-batch` work item under a single `WorkSessionID`
   that re-dispatches under the same ID until the queue drains — confirm the
   live trigger (an automatic scan on launch, or an explicit action) against
   the running app rather than assuming.
3. **Assert batch size.** While geocoding is in progress, confirm the
   worker command is bounded to `geocodeBatchSize = 50` per dispatch —
   cross-check via `work_sessions`/`WorkerCommand.reverseGeocodeBatch(limit:)`
   if the limit is observable (e.g. via `--logs`), or infer it from the
   pacing of `place_cache` growth (batches of ≤50 landing at a time, not all
   pending coordinates at once).
4. **Assert successful results are map-visible.**
   ```bash
   sqlite3 "$DB" "SELECT coordinate_key, display_name FROM place_cache WHERE display_name IS NOT NULL LIMIT 5;"
   ```
   Open the Places map (`ax_drive.sh wait-vended`, navigate to Places);
   assert a resolved location cluster renders with the expected place name
   for at least one geocoded asset.
5. **Assert the negative cache.** Find (or construct) an asset whose GPS
   coordinate resolves to nothing (open ocean, a coordinate with no
   locality) — or force a resolvable one to look unresolvable by testing
   offline first (Step 7) so its `place_cache` row lands all-NULL. Then:
   ```bash
   sqlite3 "$DB" "SELECT coordinate_key, locality, administrative_area, country, display_name
     FROM place_cache WHERE display_name IS NULL;"
   ```
   Re-run the geocode pass (Step 2 again) and confirm this coordinate is
   **not** re-queried — it should have left `geocode_queue` after the first
   nil result and never re-enter without a new asset introducing that
   coordinate:
   ```bash
   sqlite3 "$DB" "SELECT * FROM geocode_queue WHERE coordinate_key = '<that key>';"   # expect no row
   ```
6. **Assert graceful offline degradation.** Disconnect network (or block the
   geocoding endpoint), then trigger the geocode pass again for a coordinate
   that hasn't been cached yet:
   ```bash
   sqlite3 "$DB" "SELECT coordinate_key, attempt_count, last_error FROM geocode_queue ORDER BY updated_at DESC LIMIT 5;"
   ```
   **Fails if** the app crashes, wedges, or the geocode work item never
   completes/fails cleanly. Expect `attempt_count` to increment and
   `last_error` populated, with the item remaining queued (not dropped) up
   to `reverseGeocodeMaximumAttemptCount = 5` retries, and no visible error
   surfaced as a hard failure elsewhere in the UI.

## Expected
- Step 3: **Fails if** a single dispatch geocodes more than 50 coordinates
  in one pass — the throttle exists specifically to respect the geocoding
  API's rate limits; a larger batch is a real regression, not just a
  cosmetic deviation.
- Step 4: **Fails if** a `place_cache` row with a non-null `display_name`
  has no map-visible effect (the Places view doesn't reflect it, or shows a
  different name than the cached one).
- Step 5: **Fails if** a coordinate with an all-NULL `place_cache` row gets
  re-added to `geocode_queue` and re-queried on a subsequent pass — that's
  the silent-retry-forever regression this behavior guards against.
- Step 6: **Fails if** the app crashes/wedges when offline, or if a failed
  lookup is retried unboundedly past `reverseGeocodeMaximumAttemptCount`
  without ever landing in a terminal state.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance. Restore network connectivity if disabled for
Step 6.

## Sharp edges
- This card is inherently non-deterministic in its *content* (real
  geocoding results depend on the live service and the sample corpus's
  actual coordinates) even though its *mechanics* (batch size, negative
  cache, retry cap) are deterministic and grounded in source. Don't
  over-fit assertions to specific place names; assert the mechanism, not
  the exact string.
- `reverseGeocodeRequestInterval` throttles *within* a batch (a sleep
  between individual lookups, `WorkerCommandExecutor.swift:325-327`), which
  is a separate throttle from the 50-item batch cap — don't conflate
  "geocoding is slow" (the intra-batch pacing) with "geocoding never
  exceeds 50 per pass" (the batch cap) when diagnosing a failure.
- `enqueueMissingGeocodeCoordinates`'s scan is capped at 500
  (`geocodeEnqueueScanLimit`) per invocation
  (`CatalogRepository.swift:518` excludes coordinates already in
  `place_cache`) — a corpus with more than 500 distinct new coordinates
  needs multiple enqueue passes to fully drain; don't read a single pass's
  incomplete queue as a bug.

## Run status
**SKIP-offline** — not executable in this (network-isolated) session. Source
citations (batch size, scan limit, negative-cache behavior, retry cap,
`place_cache`/`geocode_queue` schema) were grep-confirmed against
`Sources/TeststripApp/AppModel.swift`,
`Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`,
`Sources/TeststripCore/Catalog/CatalogRepository.swift`, and
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` on 2026-07-10. No SQL
or live driving was run. Needs a human-present re-run, on a network-connected
machine, with real GPS-tagged sample photos, and needs the actual
geocode-trigger UI/timing confirmed against the running app before the card
can be trusted as written.
