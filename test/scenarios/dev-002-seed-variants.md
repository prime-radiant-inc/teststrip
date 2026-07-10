# dev-002-seed-variants: build_and_run.sh isolated seed variants

**What this covers**
As a developer I want each of `script/build_and_run.sh`'s isolated-catalog
seed variants (`--smoke`, `--faces`, `--sample-photos`, plain `--isolated`) to
launch with the catalog contents the docs promise, so a scenario card that
picks a variant for its fixture needs (synthetic count, real photos, faces,
empty) can trust it. Covers the seed-variant capability-inventory entries
described in `test/scenarios/README.md`'s "How a card is run" section. Script
under test: `script/build_and_run.sh` (`--verify-*` launch/quit forms).

## Pre-state
- Repo checked out at `/Users/jesse/git/projects/teststrip`, working directory
  the repo root.
- No app instance running: `pkill -x Teststrip; pkill -x TeststripApp; pkill -x TeststripWorker` (ignore failures).
- Each step below produces its own throwaway isolated app-support dir (a
  fresh `mktemp -d` per invocation, since `ISOLATED_APPLICATION_SUPPORT` is
  script-local state, not passed between invocations) — recover the path from
  the script's own stdout line `... is using isolated application support at <dir>`.

## Steps

All four steps are **host-console-touching**: each launches the real app via
`open -n`, waits for it to report running, then is quit immediately. No UI is
driven beyond that launch/quit.

1. Plain isolated (empty catalog):
   ```bash
   OUT=$(./script/build_and_run.sh --verify-isolated); echo "$OUT"
   ISO=$(echo "$OUT" | sed -n 's/.*isolated application support at //p')
   DB="$ISO/Teststrip/catalog.sqlite"
   ls -la "$DB"
   sqlite3 "$DB" "SELECT count(*) FROM assets;"
   pkill -x Teststrip
   ```
2. Smoke (24 synthetic photos, override via `TESTSTRIP_SMOKE_ASSET_COUNT`):
   ```bash
   OUT=$(./script/build_and_run.sh --verify-smoke); echo "$OUT"
   ISO=$(echo "$OUT" | sed -n 's/.*isolated application support at //p')
   DB="$ISO/Teststrip/catalog.sqlite"
   sqlite3 "$DB" "SELECT count(*) FROM assets;"
   pkill -x Teststrip
   ```
3. Sample photos (real JPEGs from `sample-data/photos/wordpress-photo-directory`,
   downloaded via `script/download_sample_photos.sh` on first use if absent):
   ```bash
   OUT=$(./script/build_and_run.sh --verify-sample-photos); echo "$OUT"
   ISO=$(echo "$OUT" | sed -n 's/.*isolated application support at //p')
   DB="$ISO/Teststrip/catalog.sqlite"
   sqlite3 "$DB" "SELECT count(*) FROM assets;"
   pkill -x Teststrip
   ```
4. Faces (real JPEGs from `sample-data/photos/faces` via `sample-data/faces.tsv`):
   ```bash
   OUT=$(./script/build_and_run.sh --verify-faces); echo "$OUT"
   ISO=$(echo "$OUT" | sed -n 's/.*isolated application support at //p')
   DB="$ISO/Teststrip/catalog.sqlite"
   sqlite3 "$DB" "SELECT count(*) FROM assets;"
   pkill -x Teststrip
   ```

## Expected
- All four: `ls -la "$DB"` shows a non-empty `catalog.sqlite` at
  `$ISO/Teststrip/catalog.sqlite` (the nested path — the top-level
  `$ISO/catalog.sqlite`, if present, is a separate zero-byte stub per
  `test/scenarios/README.md` and must NOT be the one queried).
- Step 1 (`--verify-isolated`, no seed flag set): `SELECT count(*) FROM assets`
  returns `0` — plain `--isolated` performs no seeding (`SMOKE`, `SAMPLE_PHOTOS`,
  `REAL_CORPUS` are all `0`, so `open_app()`'s seeding branches are skipped
  and the catalog is created empty by the app itself on first launch).
- Step 2 (`--verify-smoke`): `SELECT count(*) FROM assets` returns `24` by
  default. This is controlled by `TESTSTRIP_SMOKE_ASSET_COUNT` (script line
  ~20: `SMOKE_ASSET_COUNT="${TESTSTRIP_SMOKE_ASSET_COUNT:-24}"`, passed as the
  count argument to `swift run TeststripBench seed-app-catalog`); re-running
  with `TESTSTRIP_SMOKE_ASSET_COUNT=5 ./script/build_and_run.sh --verify-smoke`
  should instead yield `5`.
- Step 3 (`--verify-sample-photos`): `SELECT count(*) FROM assets` returns a
  count equal to the number of files present in
  `sample-data/photos/wordpress-photo-directory` at seed time (whatever
  `download_sample_photos.sh` populated from
  `sample-data/wordpress-photo-directory.tsv` — record the exact number
  observed, do not assume a fixed constant since it depends on the manifest).
- Step 4 (`--verify-faces`): same shape as step 3 but rooted at
  `sample-data/photos/faces` / `sample-data/faces.tsv` — record the observed
  count.
- All four: `Teststrip is running from <dist path>` appears in `$OUT`, and
  `Teststrip is using isolated application support at <dir>` appears (isolated
  path line present for all — `ISOLATED=1` is set for every variant here,
  including plain `--isolated`).

## Cleanup
```bash
pkill -x Teststrip 2>/dev/null || true
pkill -x TeststripApp 2>/dev/null || true
pkill -x TeststripWorker 2>/dev/null || true
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--faces` and `--sample-photos` both set `SAMPLE_PHOTOS=1` and reuse the
  same `seed_sample_catalog` codepath — `--faces` just overrides
  `SAMPLE_PHOTOS_MANIFEST`/`SAMPLE_PHOTOS_DIR` to the faces-specific fixture
  before falling into the same case-arm logic. There is no separate
  "seed-faces-catalog" bench subcommand.
- First run of `--verify-sample-photos` or `--verify-faces` on a machine
  without the sample photo corpus already downloaded will trigger
  `script/download_sample_photos.sh`, which fetches over the network — this
  can make the first invocation much slower than subsequent ones and is not
  itself asserted here (only the resulting DB state is).
- Every step calls `stop_running_app` before building, so running these steps
  back-to-back is safe, but running this card while Jesse has a real dogfood
  session open on the same machine will kill it — same caveat as dev-001.
- The isolated app-support directory is recovered here by scraping the
  script's own stdout line rather than a documented flag; there's no
  `--print-isolated-path`-style option. If that stdout wording ever changes,
  this card's `sed` extraction breaks silently (empty `$ISO`) rather than
  erroring loudly — worth watching for in CI output, not something this card
  can self-detect.
- `--verify-*` never exits the app on its own; each step above explicitly
  `pkill`s afterward. Skipping that leaves the worker process alive against
  a throwaway catalog.
