# lib-014-map-clusters-scoping: GPS photos cluster on the map and reverse-geocode to names, scoped to the active query

**What this covers**: the Places feature merged at migrations 18/19 — GPS
ingest from photo EXIF, the `.map` view's bounded-SQL cluster bubbles, TOP
LOCATIONS, the coverage badge, and throttled CLGeocoder reverse-geocoding into
the coordinate-rounded `place_cache`. The load-bearing assertions: photos with
GPS produce map clusters (photos without GPS don't), and a cluster resolves to
a human place name, cross-checked against the `place_cache` table.

## Pre-state
- Fresh build, isolated catalog:
  ```bash
  ./script/build_and_run.sh --isolated
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
- **Network reachable** — reverse geocoding is a live CLGeocoder round-trip.
  First confirm the geocoder path works at all:
  ```bash
  ./script/verify_reverse_geocode_smoke.sh    # expect "PASS <locality>"; SKIP means offline → this card can't assert names
  ```
- **GPS-tagged fixtures on disk to import.** Generate a fixture folder with the
  bench seeder — half the JPEGs carry GPS EXIF at the Eiffel Tower (48.8584,
  2.2945, matching `verify_reverse_geocode_smoke.sh`), the rest carry none:
  ```bash
  GEO_FIXTURES=$(mktemp -d)/geo
  swift run TeststripBench seed-geo-fixtures "$GEO_FIXTURES" 8
  ```
  Then import `$GEO_FIXTURES` through the app's Import flow (drive the import
  with `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path` and type `$GEO_FIXTURES`, or use
  the folder-import panel). The GPS-bearing subset produces map clusters; the
  rest do not. Do not fake coordinates directly into the DB and call it an
  end-to-end pass.

## Steps
1. **Confirm GPS coordinates were ingested** (ground truth, after importing the
   GPS fixture folder via the Import flow):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_valid(technical_metadata_json) AND json_extract(technical_metadata_json,'\$.latitude') IS NOT NULL;"
   ```
   Expect ≥ 1. Call it `GEO`.
2. **Open Places.** `script/activate_app.sh Teststrip`; AX-press the top-bar
   mode item labeled **"Places"** (or the sidebar row "Places"). `waitFor` the
   breadcrumb/title to read **"Places"**.
3. **Assert clusters render.** Re-dump; find the map's cluster bubbles
   (accessible as count-bearing elements) and the coverage badge. At least one
   cluster must show a photo count.
4. **Assert a reverse-geocoded name appears.** `waitFor` (throttled geocoding
   may take seconds) a TOP LOCATIONS entry or cluster label bearing a place
   name (non-empty, non-coordinate text).
5. **Cross-check against place_cache**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM place_cache WHERE locality IS NOT NULL AND locality<>'';"
   ```
   Expect ≥ 1, and the name shown in the UI must match a `place_cache` row.

6. **Assert the map is query-scoped, not whole-catalog** (per commit
   `62e0a31`, "fix: scope Library Map geo queries to the current filtered
   result set" — `AppModel.refreshPlaceData` now passes
   `currentLibraryQuery()` through to
   `CatalogRepository.placeClusters(bounds:cellSize:matching:)`,
   `.topLocations(limit:matching:)`, and `.geotaggedCoverage(matching:)`,
   which push the shared `SetQuery` WHERE-building (`compileClauses`) into the
   geo SQL instead of materializing filtered asset IDs). With Places/Map open
   and clusters showing the full `GEO` count, type a query token in the
   Library search field that excludes some of the GPS-tagged fixtures (e.g. a
   `keyword:`/filename-scoped token matching only a subset — pick one from the
   imported fixture set), submit it, and:
   - Assert the coverage badge's numerator drops to match only the assets the
     token matches (cross-check with
     `sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_valid(technical_metadata_json) AND json_extract(technical_metadata_json,'\$.latitude') IS NOT NULL AND <token's equivalent WHERE clause>;"`).
   - Assert cluster bubble counts sum to that scoped count, not `GEO`.
   - Clear the token; assert clusters/coverage revert to the full `GEO` count.
   This must hold live, not just on route entry — `AppModel.reload()` refreshes
   place data while Map is the active view per the commit's stated behavior.

## Expected
- Step 1: `GEO ≥ 1`. **Fails if** 0 — GPS never ingested; the rest is moot.
- Step 3: ≥ 1 cluster with a count; the coverage badge reflects `GEO`/total.
  **Fails if** the map is empty despite `GEO ≥ 1` (ingest → map projection broke).
- Step 4/5: a real locality string in the UI that also exists in `place_cache`.
  **Fails if** the UI shows only raw coordinates, or shows a name absent from
  `place_cache` (UI fabricating a name the cache doesn't back). Quote the UI
  string and the matching `place_cache` row.
- Step 6: **Fails if** applying a query token does not narrow the map's
  clusters/top-locations/coverage — i.e. the surfaces still reflect the whole
  catalog rather than the active `SetQuery`, regressing commit `62e0a31`.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **The GPS fixture folder comes from `TeststripBench seed-geo-fixtures`**
  (see Pre-state). It writes `<count>` JPEGs into the target dir, `count/2` of
  them tagged with Eiffel-Tower GPS EXIF (round-trip-verified through
  `ImageIODecodeProvider` in `GeoFixtureSeederTests`), the rest untagged. Import
  that folder through the live Import flow — do not seed coordinates into the DB.
- Reverse geocoding is throttled and coordinate-rounded; give step 4 a generous
  `waitFor` (≥ 30s) and don't conclude "no name" until the geocode queue drains
  (watch Activity). A `SKIP no network` from the smoke means names can't be
  asserted at all this run — report that, don't pass on clusters alone.
- Confirm the `technical_metadata_json` latitude JSON path against a real row
  (`sqlite3 "$DB" "SELECT technical_metadata_json FROM assets LIMIT 1;"`) — a
  wrong path silently reads 0 and makes step 1 vacuous.
- Step 6 (query-scoping) is new as of commit `62e0a31`; the scoping code path
  (`AppModel.refreshPlaceData` → `CatalogRepository.placeClusters/topLocations/geotaggedCoverage(matching:)`)
  was confirmed by reading the diff, not by a live drive — no live GUI drive
  has been performed for this addition. Needs a human-present or VM run
  before this step can be marked passing.

## Run status
NOT YET RUN — this card (renamed from `places-map-and-geocode.md`) has no
recorded live pass; prior notes above were headless/source-verification only.
Step 6 is newly added and equally unrun. Needs a human-present or VM re-run
per `test/scenarios/README.md`.
