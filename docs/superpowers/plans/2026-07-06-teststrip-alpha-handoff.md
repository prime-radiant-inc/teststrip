# Teststrip Alpha Handoff - 2026-07-06

## Branch

`wip/teststrip-usable-foundation`

## Current State

The branch is moving toward a usable macOS alpha for local-first, non-destructive, external-file-based photo management and culling. It is not alpha-complete yet. The most useful source of truth remains `docs/superpowers/plans/2026-07-03-teststrip-usable-alpha.md`.

## Latest Commits

- `abea302` - Guard unreadable XMP conflict actions.
- `6fe63c9` - Record latest Teststrip alpha handoff.
- `3def39f` - Protect pending XMP writes from stale sidecars.
- `ce011c0` - Make batch-selected grid cells obvious.
- `1743716` - Record grid focus handoff.
- `9aeb808` - Avoid culling focus steal on grid selection.
- `25ac422` - Show active import scan counts.
- `1888620` - Add count-aware catalog scale thresholds.
- `372f0ff` - Make import progress feel explicit.
- `97bd695` - Record real corpus app smoke progress.

## Verification From Latest Slices

- `swift test --filter InspectorViewTests` passed after `abea302`: 20 tests, 0 failures.
- `swift test --filter AppModelTests` passed after `abea302`: 386 tests, 0 failures.
- `swift test` passed after `abea302`: 994 tests, 5 skipped, 0 failures.
- `./script/build_and_run.sh --build` rebuilt and signed `dist/Teststrip.app` plus `TeststripWorker` after `abea302`.
- `swift test --filter WorkerCommandExecutorTests` and `swift test --filter MetadataSyncTests` passed after the pending XMP write freshness fix.
- `swift test` passed after `3def39f`: 992 tests, 5 skipped, 0 failures.
- `script/verify_metadata_write.sh 1000` passed after `3def39f` with 1,000 matching sidecars, 1,000 synced fingerprints, 0 pending sync items, and 1,000 unchanged originals.
- `./script/build_and_run.sh --build` rebuilt and signed `dist/Teststrip.app` plus `TeststripWorker` after `3def39f`.
- `swift test --filter LibraryGridLayoutTests` passed after both the batch-selection chrome and grid activation focus policy changes.
- `swift test --filter ImportProgressPresentationTests` passed after active unknown-total import scan count presentation.
- `script/verify_catalog_scale.sh 100000`, `500000`, and `1000000` passed with measured count-aware thresholds.

Foreground UI automation was intentionally avoided in the latest slices because Jesse asked to minimize focus-stealing automation while using the machine.

## What Changed Most Recently

- Unreadable or unparsable selected XMP conflict sidecars now have explicit model/presentation state. The inspector disables sidecar-dependent `Merge Missing` and `Use XMP` actions while keeping `Use Catalog` available to recreate the sidecar from catalog metadata.
- Pending worker-backed XMP writes without a previous sidecar checkpoint now stay catalog-first: older existing sidecars are overwritten with catalog metadata, newer sidecars become conflicts, and original image bytes remain untouched.
- Batch-only selected grid cells now get a visible orange outline, so command/shift selection no longer depends only on the small top-left badge.
- Ordinary grid click selection and command/shift batch selection no longer force the hidden culling key-capture view to become first responder. Loupe opening and accessibility selection still request culling focus.
- Active unknown-total import scans now show `Counting photos` before any discovered candidates and `<n> found` once scanning has progress but no final total yet.
- Catalog-scale verifier defaults are now count-aware for 100k, 500k, and 1M synthetic catalogs while still allowing explicit threshold overrides.

## Important Current Gaps

- The product is still not a full usable alpha. Keep the goal active.
- Import UX still needs real workflow verification when focus-stealing automation is acceptable or Jesse is idle.
- Selection/click behavior still needs live verification against an imported/real corpus catalog; the code-level focus and batch-selection visibility issues were addressed, but the UI should be checked visually when allowed.
- Mockup parity is still incomplete. Known user-noted items were inspected: grid thumbnails currently use `.fit` plus catalog aspect ratio, and inspector preview dimensions are pinned, so do not churn those without reproducing a current failure.
- Large-catalog foreground app workflow resource thresholds remain diagnostic-only.
- RAW coverage still lacks collected local fixtures for Canon CRW and Sigma/Foveon RAW; do not commit photo corpus data.

## Suggested Next Slice

Start with one of these, depending on available UI automation window:

1. If foreground UI automation is acceptable or Jesse is idle: run a real imported-grid selection/import workflow smoke against the ignored real corpus and verify the click/focus change plus import progress presentation in the app.
2. If staying non-focus-stealing: continue catalog/XMP live-review polish at the presentation/model level, or strengthen headless conflict-review workflow coverage.
3. If avoiding XMP: continue mockup parity/live-placeholder cleanup or saved-set/work-session gaps.

## Useful Commands

```bash
git status --short --branch
git log --oneline -8
swift test
./script/build_and_run.sh --build
script/verify_metadata_write.sh 1000
script/verify_catalog_scale.sh 100000
script/verify_catalog_scale.sh 500000
script/verify_catalog_scale.sh 1000000
```

Use foreground UI scripts only when approved or idle, per Jesse's current constraint.
