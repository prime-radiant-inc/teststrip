# Performance Harness

TeststripBench exposes explicit catalog scale targets from the v1 design:

```bash
swift run TeststripBench catalog-baseline
swift run TeststripBench catalog-stress
```

`catalog-baseline` seeds 500,000 synthetic catalog assets. `catalog-stress` seeds 1,000,000 synthetic catalog assets. A numeric argument still runs an ad hoc catalog scale count, for example:

```bash
swift run TeststripBench 250000
```

The catalog benchmark measures synthetic asset seeding, total count, first-page load, middle-page load, filtered count for 4+ star assets, and filtered first-page load. Its synthetic rows also include representative flag, color label, keyword, source availability, folder, camera, lens, ISO, and capture-date values, and the machine-readable summary records count timings for those common filter predicates. It uses the same `CatalogRepository` APIs as the app grid paging path.

For repeatable alpha regression checks, run:

```bash
script/verify_catalog_scale.sh 100000
script/verify_import_preview_drain.sh 100
script/verify_preview_render.sh 100
script/verify_metadata_write.sh 1000
script/verify_source_availability.sh 1000
script/verify_offline_reconnect_smoke.sh
```

The catalog verifier parses the benchmark summary, checks the asset count, and enforces the current 0.2s default threshold for first/middle/filtered page loads and representative filter counts. Seed time is reported by `TeststripBench` but intentionally excluded from the filter/page threshold.

The metadata-write verifier wraps the `metadata-write` benchmark and enforces catalog update count, sidecar count, synced fingerprint count, zero pending sync items, unchanged originals, and the current 5s default metadata-write threshold. Override the timing gate with `TESTSTRIP_METADATA_WRITE_MAX_SECONDS` when intentionally measuring slower hardware or stress paths.

The import-preview-drain verifier wraps the `import-preview-drain` benchmark and enforces imported/catalog asset counts, queued-preview count before drain, generated-preview count, zero preview failures, zero pending previews after drain, cached-preview count, and the current 5s import / 10s drain thresholds. Override the timing gates with `TESTSTRIP_IMPORT_PREVIEW_DRAIN_MAX_IMPORT_SECONDS` and `TESTSTRIP_IMPORT_PREVIEW_DRAIN_MAX_DRAIN_SECONDS` when intentionally measuring slower hardware or larger source batches.

The preview-render verifier wraps the generated-image `preview-render` benchmark, enforces the source image count, all four cache levels per source, cached-preview count, and the current 5s default preview-render threshold. Override the timing gate with `TESTSTRIP_PREVIEW_RENDER_MAX_SECONDS` when intentionally measuring slower hardware or larger source batches.

The source-availability verifier wraps the `source-availability` benchmark and enforces catalog asset count, refreshed asset count, deterministic online/missing/stale source counts, and the current 5s default source refresh threshold. Override the timing gate with `TESTSTRIP_SOURCE_AVAILABILITY_MAX_SECONDS` when intentionally measuring slower hardware, remote volumes, or larger source batches.

The offline reconnect smoke verifier wraps the `offline-reconnect-smoke` benchmark and enforces cached-preview readability before and after reconnect, one restored online asset, XMP sidecar path migration, and unchanged original/sidecar bytes. Override the timing gate with `TESTSTRIP_OFFLINE_RECONNECT_SMOKE_MAX_SECONDS` when intentionally measuring slower disks or mounted storage.

Foreground app workflow probes are intentionally separate from the headless benchmark gates because they depend on macOS Accessibility focus. When they are run, `script/verify_app_workflows.sh Teststrip` now emits `teststrip_app_workflow_resource` snapshots after each step, and `script/verify_import_path.sh Teststrip` emits app/worker CPU plus RSS metrics beside the import and preview counters. Treat these as diagnostic snapshots until enough local runs exist to set honest red/yellow/green thresholds.

Additional focused commands cover the other hot paths that currently matter for alpha:

```bash
swift run TeststripBench import-deferred 1000
swift run TeststripBench import-preview-drain 100
swift run TeststripBench preview-render 100
swift run TeststripBench sample-preview-render sample-data/photos/wordpress-photo-directory
swift run TeststripBench metadata-write 1000
swift run TeststripBench source-availability 1000
swift run TeststripBench offline-reconnect-smoke
```

`import-deferred` creates a synthetic folder, catalogs it in place, and verifies preview work is queued instead of generated synchronously. `import-preview-drain` creates generated JPEG sources, imports with preview generation deferred, and drains the queued preview work through `LibraryImportService.resumePendingPreviews`. `preview-render` creates generated JPEG sources and renders all cache levels through `PreviewRenderer`. `sample-preview-render` imports an existing sample-photo directory and generates cached previews through the same immediate-preview import path used by the sample catalog smoke workflow. `metadata-write` updates catalog metadata, writes XMP sidecars, marks sync fingerprints, and verifies the original files were not changed. `source-availability` creates synthetic original files, catalogs their fingerprints, then refreshes catalog source states after a deterministic mix of unchanged, missing, and stale source files. `offline-reconnect-smoke` creates a catalog entry whose old root is unavailable, keeps a cached preview readable, reconnects the source to a mounted root, moves XMP sync state to the relocated sidecar, and verifies originals/sidecars were not changed.

Every `TeststripBench` command keeps its human-readable output and also prints one machine-readable summary line:

```text
benchmark-summary	{"benchmark":"deferred_import","count":3,"measurements":{"import_deferred":0.017},"metrics":{"catalog_assets":3,"imported_assets":3,"pending_previews":6,"progress_events":8}}
```

The prefix is stable. The JSON payload contains the benchmark name, requested count, numeric result metrics, and measured step durations in seconds. Scripts should parse this line instead of scraping the human timing text.

## Local Evidence

On July 3, 2026, local debug runs produced:

| Command | Seed | Count | First Page | Middle Page | Filter Count | Filtered Page |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `swift run TeststripBench catalog-baseline` | 12.285s | 0.003s | 0.008s | 0.020s | 0.136s | 0.008s |
| `swift run TeststripBench catalog-stress` | 25.083s | 0.006s | 0.008s | 0.032s | 0.271s | 0.008s |

These are not release-mode acceptance numbers, but they prove the current SQLite-backed catalog path can page 500k and 1M synthetic catalogs without loading the full catalog into app memory.

On July 4, 2026, local debug runs produced:

| Command | Count | Slowest Checked Page/Filter |
| --- | ---: | ---: |
| `script/verify_catalog_scale.sh 100000` | 100,000 assets | 0.098s (`count_camera_smokecam_2`) |

| Command | Duration | Primary Counts |
| --- | ---: | --- |
| `swift run TeststripBench import-deferred 1000` | 0.402s | 1,000 imported/catalog assets, 2,000 pending previews, 16 progress events |
| `swift run TeststripBench preview-render 100` | 1.551s | 100 generated JPEG sources, 400 rendered previews, 400 cached previews |
| `swift run TeststripBench sample-preview-render sample-data/photos/wordpress-photo-directory` | 0.202s | 12 real sample-photo sources, 12 catalog assets, 24 cached previews |
| `swift run TeststripBench metadata-write 1000` | 1.451s | 1,000 catalog updates, 1,000 sidecars, 1,000 synced fingerprints, 0 pending sync items, 1,000 unchanged originals |
| `script/verify_preview_render.sh 100 5` | 1.602s | 100 generated JPEG sources, 400 rendered previews, 400 cached previews |
| `script/verify_metadata_write.sh 25 5` | 0.048s | 25 catalog updates, 25 sidecars, 25 synced fingerprints, 0 pending sync items, 25 unchanged originals |

On July 5, 2026, a local debug run produced:

| Command | Import | Preview Drain | Primary Counts |
| --- | ---: | ---: | --- |
| `script/verify_import_preview_drain.sh 100 5 10` | 0.033s | 0.516s | 100 imported/catalog assets, 200 pending previews before drain, 200 generated previews, 0 failures, 0 pending previews after drain, 200 cached previews |

These runs prove the benchmark harnesses are executable and exercise real app paths, not that the alpha has final performance thresholds. The generated-image `preview-render` command isolates renderer/cache throughput; the real-image `sample-preview-render` command includes sample import and immediate preview generation overhead; the `import-preview-drain` verifier covers the deferred-preview recovery path the app depends on when originals are on slow, remote, removable, or intermittently available storage.

| Command | Source Refresh | Primary Counts |
| --- | ---: | --- |
| `script/verify_source_availability.sh 1000 5` | 0.723s | 1,000 catalog/refreshed assets, 334 online sources, 333 missing sources, 333 stale sources |

The `source-availability` verifier covers the bounded catalog refresh path the app depends on when a loaded window contains originals on local, remote, removable, or intermittently available storage.

On July 6, 2026, a local debug run produced:

| Command | Reconnect | Primary Counts |
| --- | ---: | --- |
| `script/verify_offline_reconnect_smoke.sh` | 0.021s | 1 catalog asset, cached preview readable before/after reconnect, 1 reconnected online asset, sidecar path updated, original and sidecar unchanged |

The `offline-reconnect-smoke` verifier covers the catalog-first offline workflow the app depends on when cached previews are available but originals live on remounted NAS, removable, or cloud-backed storage.
