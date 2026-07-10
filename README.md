# Teststrip

A macOS photo-culling app. Catalog-first and non-destructive: a SQLite catalog
is the operational truth, your original image files are never modified, and
portable metadata mirrors to XMP sidecars. A supervised out-of-process worker
handles preview rendering, image evaluation, and face embedding.

> **⚠️ Early development build.** Teststrip is not ready for general use.
> It is under active development, changes rapidly, and has rough edges,
> missing features, and bugs. Data-safety invariants (originals untouched,
> catalog + sidecars only) are core design principles and are tested, but you
> should not yet trust it as the only home for anything you can't re-import.

## What it does today

- **Cull** — keyboard-first loupe culling with auto-grouped stacks, provisional
  AI reads (sharpness, eyes, duplicates), compare/A-B views with synced zoom,
  and a one-gesture promote-frame-and-reject-siblings workflow.
- **Library** — token-based search and filtering, saved sets, timeline and map
  views, on-demand tabbed inspector.
- **People** — local face detection and grouping with a confirm-before-write
  naming queue. Nothing is labeled until you say so.

All machine judgments stay provisional until an explicit user gesture writes
them. Original bytes are never touched; edits live in the catalog and mirror
to `.xmp` sidecars.

## Requirements

- macOS 14+ on Apple silicon
- Swift 6 toolchain (to build from source)

## Building

```sh
swift build
./script/build_and_run.sh          # build and launch against your library
./script/build_and_run.sh --smoke  # isolated throwaway library with seeded photos
```

See `docs/dogfooding.md` for the real-session guide and
`test/scenarios/README.md` for the end-to-end test harness.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
