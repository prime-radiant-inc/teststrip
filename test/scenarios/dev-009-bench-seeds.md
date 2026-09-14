# dev-009-bench-seeds: TeststripBench catalog and fixture seed subcommands

**What this covers**
As a developer preparing fixtures for other scenario cards (Places/geocode,
duplicate-detection, and any card needing a pre-populated app-support
catalog without going through the live import UI), I want the
`TeststripBench` CLI's four seed subcommands — `seed-app-catalog`,
`seed-sample-catalog`, `seed-geo-fixtures`, `seed-dup-fixtures` — to produce
exactly the tables/rows/files they claim in their printed summaries. Covers
the `TeststripBench` executable target (`Sources/TeststripBench/main.swift`,
`SmokeCatalogSeeder.swift`, `SampleCatalogSeeder.swift`,
`GeoFixtureSeeder.swift`, `DuplicateFixtureSeeder.swift`); no GUI, no
`build_and_run.sh`.

## Pre-state
- Build the bench binary once:
  ```bash
  swift build --product TeststripBench -c debug
  BIN=$(swift build --product TeststripBench --show-bin-path)/TeststripBench
  ```
- A throwaway scratch root (never a real `~/Library/Application Support/Teststrip`):
  ```bash
  D=$(mktemp -d)
  ```
- Note the CLI takes **positional arguments**, not flags — there is no
  `--catalog-path`. Each seed subcommand's directory/count args are
  positional per `BenchmarkCommand.parse()` (`Sources/TeststripBench/BenchmarkCommand.swift`
  lines 30–145): `seed-geo-fixtures <dir> [count=12]` (line 84),
  `seed-dup-fixtures <dir>` (line 97), `seed-app-catalog <app-support-dir>
  [count=24]` (line 101), `seed-sample-catalog <app-support-dir> <photo-dir>`
  (line 135). All directory
  arguments default to the current working directory if omitted — always
  pass them explicitly to stay inside `$D`.
- `seed-sample-catalog` needs a real photo directory as its second argument;
  use the repo's committed real-photo fixture set:
  `sample-data/photos/loc-free-to-use` (12 JPEGs + one `.xmp` sidecar,
  already in the repo, no download needed).

## Steps
1. **`seed-geo-fixtures`:**
   ```bash
   "$BIN" seed-geo-fixtures "$D/geo" 8
   ```
2. **`seed-dup-fixtures`:**
   ```bash
   "$BIN" seed-dup-fixtures "$D/dup"
   ```
3. **`seed-app-catalog`:**
   ```bash
   "$BIN" seed-app-catalog "$D/appsupport" 6
   ```
4. **`seed-sample-catalog`:**
   ```bash
   "$BIN" seed-sample-catalog "$D/appsupport2" \
     "$(cd "$(git rev-parse --show-toplevel)" && pwd)/sample-data/photos/loc-free-to-use"
   ```
5. **Cross-check catalog ground truth** for steps 3–4:
   ```bash
   sqlite3 "$D/appsupport/Teststrip/catalog.sqlite" ".tables"
   sqlite3 "$D/appsupport/Teststrip/catalog.sqlite" "SELECT count(*) FROM assets;"
   sqlite3 "$D/appsupport2/Teststrip/catalog.sqlite" "SELECT count(*) FROM assets;"
   ```

## Expected
- Step 1: exit `0`, stdout (captured live on this checkout):
  ```
  TeststripBench seed geo fixtures
  directory: <D>/geo
  count: 8
  total fixtures: 8
  gps-bearing fixtures: 4
  gps latitude: 48.8584
  gps longitude: 2.2945
  ```
  `ls "$D/geo" | wc -l` reports `8` (`GEO_0000.jpg` … `GEO_0007.jpg`). Per
  `GeoFixtureSeeder.run()` (lines 34–56), `gpsBearingCount = max(1, count/2)` —
  the first half (indices `0..<4`) carry GPS EXIF at
  `48.8584, 2.2945` (Eiffel Tower, matching `verify_reverse_geocode_smoke.sh`'s
  default coordinate); the rest carry none. **Fails if** file count != 8 or
  `gps-bearing fixtures` != `count/2`.
- Step 2: exit `0`, stdout:
  ```
  TeststripBench seed dup fixtures
  directory: <D>/dup
  card1: <D>/dup/card1
  card2: <D>/dup/card2
  card1 frames: 4
  card2 shared frames: 4
  card2 new frames: 2
  card2 frames: 6
  ```
  `$D/dup/card1` contains exactly `FRAME_0000.jpg`…`FRAME_0003.jpg` (4
  files); `$D/dup/card2` contains those same 4 filenames (byte-identical
  copies via `FileManager.copyItem`, so content hashes match — this is the
  fixture `duplicate-detection-import-new-only.md` depends on) plus
  `NEW_0004.jpg`, `NEW_0005.jpg` (2 new files, 6 total). **Fails if** any
  `card1/FRAME_*.jpg` differs byte-for-byte from its `card2` counterpart
  (`cmp` them), or if `card2` file count != 6.
- Step 3: exit `0`, stdout:
  ```
  TeststripBench seed app catalog
  application support: <D>/appsupport
  count: 6
  evaluation fixtures: none
  seed app catalog: <elapsed>s
  catalog: <D>/appsupport/Teststrip/catalog.sqlite
  preview cache: <D>/appsupport/Teststrip/Previews
  source images: 6
  catalog assets: 6
  cached previews: 12
  benchmark-summary	{"benchmark":"seed_app_catalog","count":6,"measurements":{"seed_app_catalog":<elapsed>},"metrics":{"cached_previews":12,"catalog_assets":6,"source_images":6}}
  ```
  (12 cached previews = 6 assets × 2 preview levels, per
  `SmokeCatalogSeeder.renderedLevels` = `[.grid, .large]` —
  `PreviewCache.physicalFile` maps micro/grid → `grid.heic` and medium/large
  → `large.heic`, so those two logical levels are two physical files per
  asset.) Step 5's `.tables` query lists (captured live 2026-09-13 — 21
  tables): `asset_sets`, `assets`, `catalog_meta`,
  `contact_reference_faces`, `dismissed_face_assets`, `dismissed_faces`,
  `evaluation_failures`, `evaluation_signals`, `face_observations`,
  `geocode_queue`, `metadata_sync_state`, `people`, `person_assets`,
  `person_faces`, `place_cache`, `preview_generation_queue`,
  `rejected_face_people`, `relocation_manifest_entries`, `removed_ai_labels`,
  `source_roots`, `work_sessions` (full catalog schema from
  `CatalogDatabase.migrate()`, not just an `assets` table). **Fails if**
  `SELECT count(*) FROM assets` != `6`, contradicting the printed
  `catalog assets: 6`.
- Step 4: exit `0`, stdout:
  ```
  TeststripBench seed sample catalog
  application support: <D>/appsupport2
  photo directory: .../sample-data/photos/loc-free-to-use
  seed sample catalog: <elapsed>s
  catalog: <D>/appsupport2/Teststrip/catalog.sqlite
  preview cache: <D>/appsupport2/Teststrip/Previews
  source images: 12
  catalog assets: 12
  cached previews: 12
  benchmark-summary	{"benchmark":"seed_sample_catalog","count":0,"measurements":{"seed_sample_catalog":<elapsed>},"metrics":{"cached_previews":12,"catalog_assets":12,"source_images":12}}
  ```
  (12 = the JPEG count in `loc-free-to-use`, the `.xmp` sidecar is not a
  separate asset; 12 cached previews = 12 assets × 1 physical file —
  `LibraryImportService.importPreviewLevels` is `[.grid]`, so
  `.generateImmediately` writes one `grid.heic` per asset via
  `LibraryImportService`, a different code path from `SmokeCatalogSeeder`'s
  two-level `[.grid, .large]` render.) Step 5's third query: `12`. **Fails
  if** `catalog assets` != `12` or the command errors with `sample photo
  directory does not exist`.
- Both `seed-app-catalog` and `seed-sample-catalog` **refuse to seed over an
  existing catalog** — rerunning step 3 or step 4 with the same
  `$D/appsupport`/`$D/appsupport2` a second time must fail with
  `refusing to seed {smoke,sample} catalog over existing catalog: <path>`
  and a non-zero exit. Verify this negative case:
  ```bash
  "$BIN" seed-app-catalog "$D/appsupport" 6; echo "exit=$?"
  ```
  **Fails if** it exits `0` or silently overwrites/duplicates rows.

## Cleanup
```bash
rm -rf "$D"
```
No app-support directories under `$TMPDIR/teststrip-app-support.*` are
touched (bench seeds write to an arbitrary caller-chosen path, not the
`build_and_run.sh` isolated-launch convention), so
`script/reset_isolated_test_data.sh` is not applicable here — the `rm -rf
"$D"` above is sufficient and this card creates no other state.

## Sharp edges
- The CLI has **no help/usage text and no flag validation** — an unknown
  first argument (e.g. a typo'd subcommand name) silently falls through to
  `BenchmarkCommand.parse()`'s final `return .catalogScale(count: Int(firstArgument) ?? catalogBaselineCount)`
  (line 143), which runs the 500k-row `catalog-baseline` benchmark instead
  of failing loudly. A mistyped subcommand name looks like a hang, not an
  error — if a card seems to be running "slow," check the exact spelling
  before assuming a real perf problem.
- `seed-geo-fixtures`/`seed-dup-fixtures` write only image fixtures to a
  plain directory — they do **not** seed a catalog at all (no
  `application-support`-style argument, no `catalog.sqlite` produced). Cards
  that need GPS/dup fixtures *inside* a catalog still need a separate import
  step (e.g. via the live app or `seed-app-catalog`/`seed-sample-catalog`
  against a directory these two commands populated first).
- `seed-app-catalog`'s and `seed-sample-catalog`'s "refuse to overwrite"
  guard means these are one-shot per destination directory — a card that
  wants a fresh catalog on every run must pass a fresh `mktemp -d` path each
  time, not reuse a fixed scratch location.
- `seed-real-corpus-catalog` (a catalog-seeding subcommand visible in
  `BenchmarkCommand.parse()`, line 127) exists alongside these four but was
  out of scope for this card per the task brief; it follows the same
  positional-arg/no-overwrite pattern as `seed-sample-catalog` if a future
  card needs it. Two more seeders have since joined `parse()` out of this
  card's scope: `seed-face-stack-fixtures <dir> <source-photo-dir>`
  (line 89) and `seed-burst-catalog <app-support-dir> [fixtures...]`
  (line 115).

## Run status
**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: removed
`autopilot_proposals` from Step 3's captured `.tables` inventory —
SP-D0 dropped it forward-only, so a fresh `seed-app-catalog` run's schema no
longer includes it. Supersedes prior status: LEDGER records this card
`Tested-Pass`, but that result was captured against a schema that included
`autopilot_proposals` — not valid evidence for the current table list.
Needs a fresh host CLI run to re-capture `.tables`.

**Verified 2026-09-13 (host m4.local, macOS 26.5.2 / Darwin 25.5.0, main
checkout @ 6c3df364, no GUI)**: built `swift build --product TeststripBench
-c debug` and ran all four subcommands against a `mktemp -d` scratch root.
- Step 1 matched exactly: 8 files `GEO_0000..0007.jpg`, `gps-bearing
  fixtures: 4`, Eiffel `48.8584/2.2945`.
- Step 2 matched exactly: card1 = 4 frames, card2 = 6; all four shared
  `FRAME_*.jpg` byte-identical to their card2 counterparts (`cmp -s`), two
  `NEW_*.jpg`.
- Steps 3–4 matched except the preview count: both print `cached previews:
  12` (and `cached_previews: 12` in `benchmark-summary`), not the 24 this
  card captured — corrected above, along with the mechanism (smoke = 6×2
  levels `[.grid, .large]`; sample = 12×1 file, `importPreviewLevels =
  [.grid]`). Step 3 stdout also now carries an `evaluation fixtures: none`
  line (added since the last capture; `Sources/TeststripBench/main.swift:445`).
- Step 5 `.tables` re-captured: **21 tables** — the card's inventory was
  missing `contact_reference_faces`, `rejected_face_people`,
  `removed_ai_labels` (added above). `SELECT count(*) FROM assets` returned
  `6` (appsupport) and `12` (appsupport2), matching the printed
  `catalog assets`.
- Negative case confirmed for both: re-running the seed prints
  `refusing to seed smoke catalog over existing catalog: <path>` /
  `refusing to seed sample catalog over existing catalog: <path>` and exits
  `133` (SIGABRT via `fatalError`, as the LEDGER note predicted).
- Card citations to `BenchmarkCommand.parse()` corrected: `76–105`→`30–145`
  (per-command: geo 84, dup 97, app-catalog 101, sample 135), unknown-arg
  fallback `106`→`143`, `seed-real-corpus-catalog` `90`→`127`;
  `GeoFixtureSeeder.run()` `34–56` remains correct.
