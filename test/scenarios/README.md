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
   `./script/build_and_run.sh --smoke` (or a seed variant). **`--smoke` seeds
   24 synthetic photos** into a throwaway application-support directory under
   `$TMPDIR`; **plain `--isolated` gives an *empty* catalog** — use `--smoke`
   when the card needs seeded content, `--sample-photos`/`--real-corpus` when
   it needs real photos (faces, EXIF, GPS). Either way the app never touches
   Jesse's real catalog at `~/Library/Application Support/Teststrip`. Note the
   catalog lives at **`$ISOLATED/Teststrip/catalog.sqlite`** (nested under a
   `Teststrip/` subdir; the top-level `catalog.sqlite` is a zero-byte stub).
   Confirm the running instance is the freshly built one, not a process left up
   from a prior run.
2. **Drive via accessibility, not pixels.** The pattern the `verify_*.sh`
   scripts use: `script/activate_app.sh Teststrip` to bring it frontmost
   (raw `NSRunningApplication.activate` is refused when another app holds
   focus — see `script/activate_app.sh`), then an inline `swift -e` AX walker
   that finds an element by role + accessible label, `AXPerformAction`s it,
   and `waitFor`s a predicate on the re-dumped tree. Match on the labels the
   card quotes (button titles, `accessibilityLabel`s), never brittle indices.
   Three hard-won realities of driving this app, learned running these cards:
   - **AX content is only vended while the app is genuinely key.** A separate
     `swift` process that starts after focus has slipped back to the terminal
     sees an empty window subtree (menu bar only). Call `app.activate` *inside*
     the driving process and retry the dump in a short loop until the window's
     children appear before acting.
   - **The grid is lazily virtualized.** Off-screen thumbnails are not in the
     AX tree at all — scroll the target into view before matching its filename,
     or you will get a false "not found." Present-but-not-visible ≠ absent.
   - **Icon-only controls carry their meaning in `AXHelp`, not the title.** The
     star rating buttons AX-title as `"Favorite"` (the SF Symbol default); their
     distinguishing label is the help text `"Rate 1"…"Rate 5"`. Match on
     `kAXHelpAttribute` for such controls, and read ratings/labels from the
     catalog's `metadata_json` (there is no `rating` column) and the sidecar's
     `xmp:Rating="N"` attribute.
3. **Assert against ground truth, not just the render.** The UI can lag or
   lie. Cross-check every rendered claim against the on-disk catalog
   (`$ISOLATED/Teststrip/catalog.sqlite`) or the filesystem (relocated originals, XMP
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

**Happy paths** — the everyday journeys a real session lives in:

| Card | Journey under test |
| --- | --- |
| `import-cull-pick-happy-path.md` | Import a folder → auto-evaluate → cull → accept a recommendation → see it in Picks |
| `rate-writes-xmp-happy-path.md` | Rate a photo → `.xmp` sidecar written, original bytes untouched |
| `people-name-face-group-happy-path.md` | Face grouping → confirm/name a group → person persists (written only on confirm) |

**Flagship surfaces** — the sharp edges unit tests and the headless gate can't reach:

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
