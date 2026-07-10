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
   **`--smoke` is not a clean slate**: it pre-seeds metadata (11/24 photos
   flagged, 4/24 rated 3) and contains **no persisted stacks** — write
   assertions baseline-relative, and don't expect stack-gesture cards to run
   against it. Ground-truth SQL must match the app's *advertised* semantics
   (e.g. `rating:3` filters rating ≥ 3 per the search-tips text), and every
   query should be dry-run against a seeded catalog before the card relies on
   it. See `docs/product/focused-workspaces-followups.md` for the current
   fixture-gap list.
   Confirm the running instance is the freshly built one, not a process left up
   from a prior run.
2. **Drive via accessibility, not pixels — with `script/ax_drive.sh`.** This
   reusable helper is the recommended driver; it folds in the reliability fixes
   below so cards don't hand-roll a walker that flakes. Verbs:
   - `ax_drive.sh wait-vended` — block until the app is frontmost and its window
     subtree is actually drivable (run this first).
   - `ax_drive.sh find --role AXButton --label "Export"` — exit 0 if it exists.
   - `ax_drive.sh wait --role AXStaticText --contains "Reviewing"` — wait for
     something to appear (assert a transition).
   - `ax_drive.sh press --role AXButton --help "Rate 5"` — AXPress the first
     match. Match by `--label` (title/description/value), `--help` (AXHelp, for
     icon-only controls), or `--contains` (substring).
   - `ax_drive.sh type --contains "…" --text "1024"` — set a single field's
     value. Good for an unambiguous field (export long-edge); for the multi-field
     Import Path / Import Card sheets use **`script/submit_import_path.sh App
     DIR`** instead, which sheet-scopes the path field and drives the whole flow
     (path → Review Import → Start Import).

   It re-asserts frontmost through **System Events** on every poll iteration —
   the primitive macOS permits when another app holds focus. (The older
   `verify_*.sh` scripts inline their own walker and call `activate_app.sh`
   once; that works in the headless gate, which drives immediately after launch,
   but flakes in an interactive session.) Three realities `ax_drive.sh` handles
   for you, but that still bound what's possible:
   - **AX content is only vended while the app is genuinely key.** A driver that
     grabs focus once and then dumps sees an empty window subtree (menu bar
     only) the moment focus slips. `ax_drive.sh` re-asserts frontmost via System
     Events every poll iteration; if you must hand-roll, do the same — never
     rely on `NSRunningApplication.activate`, which macOS refuses when another
     app holds focus.
   - **A long-idle instance can wedge its own AX tree.** If `wait-vended` times
     out on an app that has sat unused for minutes (window present, but its
     subtree won't traverse and even `capture_app_window.sh` fails), relaunch
     the instance rather than fighting it — a fresh `--smoke` launch vends
     immediately. Drive shortly after launch, and keep it warm during long
     worker waits (re-assert frontmost each poll — the `verify_people_clustering.sh`
     pattern).
   - **A locked macOS console launches GUI apps windowless.** While the screen
     is locked (Jesse away), a newly launched app runs with **zero windows** —
     `count of windows = 0`, the process idles healthily, the catalog
     initializes, nothing errors. It looks exactly like a launch regression and
     can burn a whole bisect. Check first:
     `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked`. If locked, all
     foreground/AX/window verification is impossible until unlock — queue it and
     re-validate the known-good baseline before trusting any bisect verdict that
     spans an absence.
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
| `ux-simplification-chrome.md` | Find Best Shots + collapsed toolbar + Copilot→Review chrome |

**Focused workspaces** — the ⌘1/⌘2/⌘3 Cull/Library/People chrome (Task 22/23):

| Card | Surface under test |
| --- | --- |
| `workspace-switching.md` | ⌘1/⌘2/⌘3 and the toolbar switcher agree on the active workspace |
| `quiet-activity-badge.md` | Activity icon idle→badge→popover→navigate-to-asset |
| `token-query-filter.md` | Query token field narrows the grid to the matching catalog rows |
| `cull-pass-scope-and-undo.md` | P/X/S/Return keyboard loop; stack Return is one gesture; ⌘Z reverts the pass |
| `end-of-set-move-rejects.md` | Completion state on deciding all frames; Move Rejects relocates files on disk |
| `library-loupe-no-cull-chrome.md` | Library's loupe has no pick/reject pills |
| `inspector-describe-suggested-keyword.md` | ⌘I opens the inspector; accepting a suggestion writes catalog + sidecar |
| `people-confirm-writes-on-return.md` | Arrow-focus then Return confirms; `person_assets` appears only after |
| `people-naming-sheet-return-routing.md` | Return with the naming sheet open triggers Create, not the queue confirm |
| `activity-icon-states.md` | Idle/working/problem-badge states of the toolbar Activity icon |
| `workspace-minimum-width-floors.md` | Library 1000pt / Cull 800pt / People 700pt floors hold chrome without clipping |

## Running scenarios in a Tart VM

Jesse's host console gets stolen/locked by other work mid-session, which
wedges any card at the "locked console" trap above. `script/vm_scenario_run.sh`
runs the interactive AX-driven half of a card inside a Tart macOS VM whose
auto-login GUI session never locks, while **building stays on the host** — the
VM never runs `swift build`; it only receives a pre-built `.app` bundle and a
pre-seeded isolated catalog over rsync.

```bash
script/vm_scenario_run.sh setup            # clone+boot the VM once, grant TCC
script/vm_scenario_run.sh sync smoke faces # build locally, seed variants, rsync in
script/vm_scenario_run.sh launch smoke     # fresh isolated copy of the smoke catalog
script/vm_scenario_run.sh ax wait-vended Teststrip
script/vm_scenario_run.sh ax find --role AXButton --label Import
script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets;"
script/vm_scenario_run.sh shell            # interactive ssh session, e.g. to send
                                            # a keyboard shortcut via osascript
```

Seed variants mirror `build_and_run.sh`'s flags: `smoke` (24 synthetic
photos), `faces` (`sample-data/photos/faces`), `empty` (unseeded). `sync`
treats a variant's local seed directory as an idempotent template — it won't
reseed over an existing catalog (pass a second positional isn't needed; delete
`$TMPDIR/teststrip-vm-seeds/<variant>` to force a reseed) — and `launch`
copies that template fresh into `~/teststrip-vm/run/<variant>-<timestamp>` on
every call, so cards never inherit state from a prior run.

TCC: the Cirrus base image ships with SIP disabled, so `setup` grants
`kTCCServiceAccessibility`/`kTCCServiceAppleEvents` directly via
`sudo sqlite3` against `/Library/Application Support/com.apple.TCC/TCC.db` —
no manual System Settings click needed. If a future base image ships with SIP
enabled, this direct-DB grant will fail loudly and a one-time manual grant in
the `tart run` viewer window becomes the fallback.

`vm_scenario_run.sh` owns VM lifecycle, build/seed sync, and the
launch/ax/sql primitives — it does not encode any card's specific step
sequence, matching how `ax_drive.sh` itself is a primitive rather than a card
runner. Driving a card's Steps is still done by hand (or by an agent) issuing
a sequence of `vm_scenario_run.sh ax ...`/`sql ...` calls per the card's file.

## Fixture status

Cards that need synthetic photos with specific properties (GPS tags for
Places, byte-identical duplicates for dedup) declare the exact fixture they
need in their Pre-state. Where no seed command produces that fixture yet, the
card says so explicitly and names the gap — an unrunnable card that documents
what's missing is honest; a card quietly rewritten to dodge the gap is not.
