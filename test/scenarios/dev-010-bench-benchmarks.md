# dev-010-bench-benchmarks: TeststripBench fast subcommands and summary contract

**What this covers**
As a developer I want a quick, host-console-only confidence check that the
`TeststripBench` executable's fast smoke subcommands (`metadata-write`,
`card-import-smoke`, `worker-recovery-smoke`) still run to completion and
still emit a well-formed machine-readable summary line, so a change to
`Sources/TeststripBench/` or the underlying catalog/worker code can't
silently break the benchmark harness `script/verify_headless_workflows.sh`
and CI rely on. This covers the "benchmark tooling stays runnable" leg of the
capability inventory — the bench binary itself, not any UI surface. Scripts
exercised: none directly; the `TeststripBench` executable target
(`Sources/TeststripBench/main.swift`, `BenchmarkCommand.swift`,
`BenchmarkSummary.swift`) built via `swift build --product TeststripBench`.

## Pre-state
- Fresh checkout, repo root. No app launch, no isolated catalog — each
  `TeststripBench` invocation creates and tears down its own temp workspace
  under `BenchmarkWorkspace.temporaryRoot()` (see `main.swift`'s top-level
  `defer { try? fileManager.removeItem(at: root) }`).
- Build once:
  ```bash
  swift build --product TeststripBench
  BIN="$(swift build --show-bin-path)/TeststripBench"
  ```

## Steps
1. **metadata-write** (default count via explicit arg 100, matching
   `verify_headless_workflows.sh`'s `TESTSTRIP_HEADLESS_METADATA_COUNT:-100}`):
   ```bash
   "$BIN" metadata-write 100
   ```
2. **card-import-smoke** (count 12, matching the headless gate's default):
   ```bash
   "$BIN" card-import-smoke 12
   ```
3. **worker-recovery-smoke** (count 24, matching the headless gate's default):
   ```bash
   "$BIN" worker-recovery-smoke 24
   ```
4. For each run, extract and parse the machine-readable summary line — the
   only line beginning with the literal prefix `benchmark-summary\t`
   (`BenchmarkSummary.machineReadablePrefix` in
   `Sources/TeststripBench/BenchmarkSummary.swift`):
   ```bash
   "$BIN" metadata-write 100 | grep '^benchmark-summary' | cut -f2- | python3 -m json.tool
   ```

## Expected
There is **no TSV file and no `--output`/`--format` flag** — the "summary" is
a single JSON object printed to stdout on the last line, prefixed with
`benchmark-summary` + a tab (see `BenchmarkSummary.machineReadableLine()`,
which does `Self.machineReadablePrefix + payload` with
`machineReadablePrefix = "benchmark-summary\t"`). Assert the printed line,
not a file on disk.

- Step 1 (`metadata-write 100`), actual output observed on a real run:
  ```
  TeststripBench metadata write
  count: 100
  metadata write: 0.246s
  updated assets: 100
  catalog assets: 100
  sidecars: 100
  matching sidecar metadata: 100
  synced fingerprints: 100
  pending sync items: 0
  unchanged originals: 100
  benchmark-summary	{"benchmark":"metadata_write","count":100,"measurements":{"metadata_write":0.24617695808410645},"metrics":{"catalog_assets":100,"matching_sidecar_metadata":100,"pending_sync_items":0,"sidecars":100,"synced_fingerprints":100,"unchanged_originals":100,"updated_assets":100}}
  ```
  JSON keys present (top level): `benchmark`, `count`, `measurements`,
  `metrics` (exactly these four — `BenchmarkSummary` is `Codable` with only
  those stored properties). `metrics` sub-keys for this benchmark:
  `catalog_assets`, `matching_sidecar_metadata`, `pending_sync_items`,
  `sidecars`, `synced_fingerprints`, `unchanged_originals`, `updated_assets`.
  `measurements` sub-key: `metadata_write` (a float, seconds).
  **Fails if** `updated_assets` != 100, `catalog_assets` != 100, or
  `pending_sync_items` != 0 (would mean the sync-fingerprint write didn't
  settle), or the JSON fails to parse.

- Step 2 (`card-import-smoke 12`), actual output observed:
  ```
  TeststripBench card import smoke
  count: 12
  card import smoke: 0.141s
  imported assets: 12
  catalog assets: 12
  destination originals: 12
  cached previews: 24
  source originals unchanged: 12
  source roots: 1
  destination catalog assets: 12
  benchmark-summary	{"benchmark":"card_import_smoke","count":12,"measurements":{"card_import_smoke":0.14063596725463867},"metrics":{"cached_previews":24,"catalog_assets":12,"destination_catalog_assets":12,"destination_originals":12,"imported_assets":12,"source_originals_unchanged":12,"source_roots":1}}
  ```
  **Fails if** `imported_assets` != 12, `catalog_assets` != 12, or
  `source_originals_unchanged` != 12 (source-of-truth originals must stay
  byte-unchanged per the non-destructive invariant).

- Step 3 (`worker-recovery-smoke 24`), actual output observed:
  ```
  TeststripBench worker recovery smoke
  count: 24
  worker recovery smoke: 0.479s
  catalog assets: 24
  recovered preview work: 24
  running work: 1
  queued work: 23
  dispatched commands: 1
  pending previews: 24
  worker process started: yes
  benchmark-summary	{"benchmark":"worker_recovery_smoke","count":24,"measurements":{"worker_recovery_smoke":0.47898292541503906},"metrics":{"catalog_assets":24,"dispatched_commands":1,"pending_previews":24,"queued_work":23,"recovered_preview_work":24,"running_work":1,"worker_process_started":1}}
  ```
  **Fails if** `worker_process_started` != 1, `recovered_preview_work` !=
  `catalog_assets` (24), or `dispatched_commands` != 1 (would mean the
  worker-death-recovery path didn't re-dispatch after the simulated crash —
  this is the exact regression `4962f0d fix: recover the work queue when the
  worker process dies` targets).

All three completed in well under a second each (0.246s / 0.141s / 0.479s
measured wall time internally; `time` wrapper showed 0.276s / 0.154s / 0.502s
total process time) — confirms the brief's "fast subset" framing; none needed
to be skipped as slow/heavy.

## Cleanup
Each `TeststripBench` invocation self-cleans its temp workspace via its own
`defer` block; nothing external to remove. No app was launched, no isolated
catalog was created.

## Sharp edges
- There is no `--output` or `--format` flag on any of these three
  subcommands (confirmed by reading `BenchmarkCommand.parse` — no such flags
  are parsed for `metadata-write`/`card-import-smoke`/`worker-recovery-smoke`).
  Anyone expecting a TSV artifact on disk (as the brief hypothesized) will not
  find one; the summary contract is the single stdout line described above.
- The human-readable lines above the `benchmark-summary` line (`"updated
  assets: 100"` etc.) duplicate the JSON metrics but are not a stable
  contract — they're plain `print()` calls with no prefix marker, so a
  parser should key off the `benchmark-summary\t` line only.
- `worker-recovery-smoke`'s `running_work`/`queued_work`/`dispatched_commands`
  values (1/23/1) reflect the benchmark's synthetic crash-and-recover
  scenario at the moment it samples the queue — they are not simply
  "24 items all recovered to queued"; a card asserting exact values here
  should re-verify against `Sources/TeststripBench/WorkerRecoverySmoke.swift`
  if the recovery timing changes.
