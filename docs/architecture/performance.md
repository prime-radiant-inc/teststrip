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
