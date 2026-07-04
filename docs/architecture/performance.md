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

The catalog benchmark measures synthetic asset seeding, total count, first-page load, middle-page load, filtered count for 4+ star assets, and filtered first-page load. It uses the same `CatalogRepository` APIs as the app grid paging path.

Additional focused commands cover the other hot paths that currently matter for alpha:

```bash
swift run TeststripBench import-deferred 1000
swift run TeststripBench preview-render 100
swift run TeststripBench sample-preview-render sample-data/photos/wordpress-photo-directory
swift run TeststripBench metadata-write 1000
```

`import-deferred` creates a synthetic folder, catalogs it in place, and verifies preview work is queued instead of generated synchronously. `preview-render` creates generated JPEG sources and renders all cache levels through `PreviewRenderer`. `sample-preview-render` imports an existing sample-photo directory and generates cached previews through the same immediate-preview import path used by the sample catalog smoke workflow. `metadata-write` updates catalog metadata, writes XMP sidecars, marks sync fingerprints, and verifies the original files were not changed.

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

| Command | Duration | Primary Counts |
| --- | ---: | --- |
| `swift run TeststripBench import-deferred 1000` | 0.402s | 1,000 imported/catalog assets, 2,000 pending previews, 16 progress events |
| `swift run TeststripBench preview-render 100` | 1.551s | 100 generated JPEG sources, 400 rendered previews, 400 cached previews |
| `swift run TeststripBench sample-preview-render sample-data/photos/wordpress-photo-directory` | 0.202s | 12 real sample-photo sources, 12 catalog assets, 24 cached previews |
| `swift run TeststripBench metadata-write 1000` | 1.451s | 1,000 catalog updates, 1,000 sidecars, 1,000 synced fingerprints, 0 pending sync items, 1,000 unchanged originals |

These runs prove the benchmark harnesses are executable and exercise real app paths, not that the alpha has final performance thresholds. The generated-image `preview-render` command isolates renderer/cache throughput; the real-image `sample-preview-render` command includes sample import and immediate preview generation overhead.
