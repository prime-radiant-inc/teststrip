# places-map-and-geocode: GPS photos cluster on the map and reverse-geocode to names

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
- **GPS-tagged fixtures in the catalog.** THIS IS A KNOWN FIXTURE GAP: no seed
  command (`--isolated`/`--sample-photos`) is known to produce GPS-tagged
  originals. The unit tests build them with
  `TeststripCoreTests` `writeTestJPEGWithGPS(...)`, but there is no live-import
  fixture generator. Until one exists, this card cannot reach its pre-state
  cleanly — see Sharp edges. Do not fake coordinates directly into the DB and
  call it an end-to-end pass.

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

## Expected
- Step 1: `GEO ≥ 1`. **Fails if** 0 — GPS never ingested; the rest is moot.
- Step 3: ≥ 1 cluster with a count; the coverage badge reflects `GEO`/total.
  **Fails if** the map is empty despite `GEO ≥ 1` (ingest → map projection broke).
- Step 4/5: a real locality string in the UI that also exists in `place_cache`.
  **Fails if** the UI shows only raw coordinates, or shows a name absent from
  `place_cache` (UI fabricating a name the cache doesn't back). Quote the UI
  string and the matching `place_cache` row.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **Fixture gap is the headline finding until closed.** The honest first
  deliverable of running this card is: "cannot reach pre-state — no GPS
  live-import fixture." Recommend adding a `seed-geo-catalog` bench subcommand
  (reusing `writeTestJPEGWithGPS`) or a fixture folder of GPS JPEGs the Import
  flow can consume, mirroring how `--sample-photos` seeds a folder. Only then is
  this card runnable end to end.
- Reverse geocoding is throttled and coordinate-rounded; give step 4 a generous
  `waitFor` (≥ 30s) and don't conclude "no name" until the geocode queue drains
  (watch Activity). A `SKIP no network` from the smoke means names can't be
  asserted at all this run — report that, don't pass on clusters alone.
- Confirm the `technical_metadata_json` latitude JSON path against a real row
  (`sqlite3 "$DB" "SELECT technical_metadata_json FROM assets LIMIT 1;"`) — a
  wrong path silently reads 0 and makes step 1 vacuous.
