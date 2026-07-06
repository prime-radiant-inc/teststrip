# Teststrip Alpha Handoff - 2026-07-06

## Branch

`wip/teststrip-usable-foundation`

## Current State

The branch is moving toward a usable macOS alpha for local-first, non-destructive, external-file-based photo management and culling. It is not alpha-complete yet. The most useful source of truth remains `docs/superpowers/plans/2026-07-03-teststrip-usable-alpha.md`.

## Latest Commits

- `9aeb808` - Avoid culling focus steal on grid selection.
- `efeb8b1` - Record import scan count progress.
- `25ac422` - Show active import scan counts.
- `1888620` - Add count-aware catalog scale thresholds.
- `208d3fe` - Record import confidence banner progress.
- `372f0ff` - Make import progress feel explicit.
- `97bd695` - Record real corpus app smoke progress.
- `1a6b33b` - Seed app catalogs from the real corpus.

## Verification From Latest Slices

- `swift test --filter LibraryGridLayoutTests` passed after the grid activation focus policy change.
- `swift test` passed after `9aeb808`: 989 tests, 5 skipped, 0 failures.
- `./script/build_and_run.sh --build` rebuilt and signed `dist/Teststrip.app` plus `TeststripWorker` after `9aeb808`.
- `swift test --filter ImportProgressPresentationTests` passed after active unknown-total import scan count presentation.
- `script/verify_catalog_scale.sh 100000`, `500000`, and `1000000` passed with measured count-aware thresholds.

Foreground UI automation was intentionally avoided in the latest slices because Jesse asked to minimize focus-stealing automation while using the machine.

## What Changed Most Recently

- Ordinary grid click selection and command/shift batch selection no longer force the hidden culling key-capture view to become first responder. Loupe opening and accessibility selection still request culling focus.
- Active unknown-total import scans now show `Counting photos` before any discovered candidates and `<n> found` once scanning has progress but no final total yet.
- Catalog-scale verifier defaults are now count-aware for 100k, 500k, and 1M synthetic catalogs while still allowing explicit threshold overrides.

## Important Current Gaps

- The product is still not a full usable alpha. Keep the goal active.
- Import UX still needs real workflow verification when focus-stealing automation is acceptable or Jesse is idle.
- Selection/click behavior still needs live verification against an imported/real corpus catalog; the code-level focus issue was addressed, but the UI should be checked visually when allowed.
- Mockup parity is still incomplete. Known user-noted items were inspected: grid thumbnails currently use `.fit` plus catalog aspect ratio, and inspector preview dimensions are pinned, so do not churn those without reproducing a current failure.
- Large-catalog foreground app workflow resource thresholds remain diagnostic-only.
- RAW coverage still lacks collected local fixtures for Canon CRW and Sigma/Foveon RAW; do not commit photo corpus data.

## Suggested Next Slice

Start with one of these, depending on available UI automation window:

1. If foreground UI automation is acceptable or Jesse is idle: run a real imported-grid selection/import workflow smoke against the ignored real corpus and verify the click/focus change plus import progress presentation in the app.
2. If UI automation must stay non-focus-stealing: improve batch-selection visual acknowledgement at the presentation/model level, with tests first, because command/shift-selected cells may still look too subtle.
3. If staying headless: continue catalog/XMP conflict and writeback gaps from the alpha plan.

## Useful Commands

```bash
git status --short --branch
git log --oneline -8
swift test
./script/build_and_run.sh --build
script/verify_catalog_scale.sh 100000
script/verify_catalog_scale.sh 500000
script/verify_catalog_scale.sh 1000000
```

Use foreground UI scripts only when approved or idle, per Jesse's current constraint.
