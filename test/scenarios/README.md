# Teststrip end-to-end scenario cards

Each `*.md` here is one **scenario card**: a falsifiable test a runner agent
executes by driving the *live* macOS app the way Jesse would. A green
`swift test` proves the wiring in isolation; a card proves the wiring as
assembled and rendered. Both are needed — write the card even when the unit
tests pass.

These cover the flagship surfaces that unit tests and the headless gate
(`script/verify_headless_workflows.sh`) can't reach: they only exist in the
assembled AppKit UI. The core culling flow (grid activation, selection,
keyboard cull, evaluate, import, card-import) is already driven live by
`script/verify_app_workflows.sh`; those cards are not duplicated here.

## How a card is run

1. **Build fresh and launch isolated.** Every card's Pre-state launches with
   `./script/build_and_run.sh --isolated` (or a seed variant). `--isolated`
   points the app at a throwaway application-support directory under
   `$TMPDIR`, so a driving session never touches Jesse's real catalog at
   `~/Library/Application Support/Teststrip`. Confirm the running instance is
   the freshly built one, not a process left up from a prior run.
2. **Drive via accessibility, not pixels.** The pattern the `verify_*.sh`
   scripts use: `script/activate_app.sh Teststrip` to bring it frontmost
   (raw `NSRunningApplication.activate` is refused when another app holds
   focus — see `script/activate_app.sh`), then an inline `swift -e` AX walker
   that finds an element by role + accessible label, `AXPerformAction`s it,
   and `waitFor`s a predicate on the re-dumped tree. Match on the labels the
   card quotes (button titles, `accessibilityLabel`s), never brittle indices.
3. **Assert against ground truth, not just the render.** The UI can lag or
   lie. Cross-check every rendered claim against the on-disk catalog
   (`$ISOLATED/catalog.sqlite`) or the filesystem (relocated originals, XMP
   sidecars, exported files) — that is authoritative.
4. **Capture evidence you re-read.** A screenshot via
   `script/capture_app_window.sh` and/or the on-disk value. Evidence you
   didn't inspect is evidence you don't have.
5. **Clean up idempotently.** `script/reset_isolated_test_data.sh --delete`
   removes the throwaway catalog. Never touch state you didn't create.

## The confirm-before-write invariant

Teststrip's core promise: machine labels stay provisional until an explicit
user gesture writes them. Several cards assert the *negative* — that nothing
was written to disk before the confirming click. Those negative assertions
are the point; do not weaken them to make a card pass.

## Cards

| Card | Surface under test |
| --- | --- |
| `autopilot-review-commit-undo.md` | Autopilot proposal → Review → Commit → Undo all |
| `reject-relocation-move-and-back.md` | Move Rejects to folder, then Move back (origin-relocating) |
| `duplicate-detection-import-new-only.md` | Content-hash dedup on re-import (import-new-only) |
| `places-map-and-geocode.md` | GPS ingest → Places map clustering → reverse-geocoded names |
| `export-presets-with-exif.md` | Export presets + optional EXIF/IPTC carry checkbox |

## Fixture status

Cards that need synthetic photos with specific properties (GPS tags for
Places, byte-identical duplicates for dedup) declare the exact fixture they
need in their Pre-state. Where no seed command produces that fixture yet, the
card says so explicitly and names the gap — an unrunnable card that documents
what's missing is honest; a card quietly rewritten to dodge the gap is not.
