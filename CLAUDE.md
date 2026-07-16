# Working on Teststrip

Teststrip is a macOS photo management app (Swift 6, SwiftPM, SwiftUI/AppKit) —
Jesse's daily-driver alpha. Catalog-first and non-destructive: a SQLite catalog
is the operational truth, originals stay in place, and portable metadata mirrors
to XMP sidecars. A supervised out-of-process worker does previews, evaluation,
and face embedding over a JSON-lines protocol.

## Priorities and working style

- **The bar is "Jesse can dogfood it," not synthetic budgets.** Ship working
  feature coverage toward a usable alpha.
- **Don't over-engineer performance.** Prefer the simplest correct approach;
  the measure-fix-measure loop is seductive and can eat a whole push, so don't
  chase micro-optimizations or a numeric probe budget. Optimize for readability
  and correctness first.
- **Finish what you touch — don't defer.** No "later sub-project," no punting a
  known problem to a backlog. If something's worth fixing, fix it now; if a
  feature is in scope, build it fully. Leave the tree cleaner than you found it.
- **Every user-facing feature gets an automated end-to-end scenario.** Don't
  ask Jesse to eyeball an assertion you can drive yourself — write a scenario
  driver (see below) that does the clicks and checks catalog ground truth.

## Non-negotiable invariants

- **Auto-apply with provenance.** Machine labels (scene keywords, captions,
  face/person identity, autopilot pick/reject flags) auto-apply to the catalog
  immediately, tagged `origin = ai` (unconfirmed) and shown with a subtle
  ✨ — for people the flag is *prominent*, review-first. Unconfirmed AI labels are **never**
  written to `.xmp` sidecars; an explicit user gesture **confirms** a label
  (flips `origin → user` and, for sidecar-eligible fields, writes the sidecar
  — identity has no XMP field) or **removes** it. Unconfirmed AI flags/ratings
  are tentative and **never** drive destructive or committing operations
  (move/trash-rejects, the persisted Picks set, export) — a tentative-only
  flag counts as undecided. Removing an AI label deletes it and records the
  removal (`removed_ai_labels`) so promotion never resurrects it; rejecting a
  suggested face records `rejected_face_people`. Assert the negative in tests:
  an AI label lands with `origin=ai` and no sidecar; after confirm,
  `origin=user` and the sidecar is written; a tentative reject is not
  relocated/trashed/exported.
- **Non-destructive.** Original image bytes are never modified. Edits go to
  the catalog and mirror to `.xmp` sidecars; a sidecar is written only once a
  rating/flag/keyword/caption/creator/copyright carries `user` origin — set
  directly, or an AI label confirmed.

## Key docs (read these before diving in)

- `docs/dogfooding.md` — how to launch and what to expect in a real session.
- `test/scenarios/README.md` — the end-to-end scenario-testing harness: the
  `ax_drive.sh` accessibility driver, the isolated-launch mechanics, and the
  hard-won driving realities. Read it before writing or running any live UI test.
- `docs/architecture/` — system architecture.
- `docs/product/narrative-select-reference.md` — the selection/review workflow
  reference product (narrative.so/select).

## End-to-end verification (the short version; details in test/scenarios/README.md)

- **Interactive launches run in the Tart VM, never on Jesse's console.** Any
  launch you intend to look at or drive (AX driving, menu checks, visual
  verification, scenario cards) goes through `script/vm_scenario_run.sh`
  (setup/sync/launch/ax/sql verbs; see the "Running scenarios in a Tart VM"
  section of test/scenarios/README.md). Local launches steal focus and hit the
  locked-console wall. Building, unit tests, and launch-and-quit smoke checks
  (no driving, no focus needed) stay on the host.
- **`make` is the task-runner entry point for the host-safe workflows.** `make`
  (or `make help`) lists the targets: `build`, `test` (unit tests), `verify`
  (the full headless gate — unit tests + sandboxed build + all headless
  verifiers), `run`/`smoke` (dogfood / isolated seeded launch), and
  `package`/`package-dry`. Each is a thin delegation to `script/` (or `swift`
  for `build`/`test`). Interactive AX scenario driving is deliberately *not* a
  target — it's VM-bound; drive it with `script/vm_scenario_run.sh`.
- **Launch isolated, never against the real catalog.** `build_and_run.sh
  --smoke` seeds 24 synthetic photos into a throwaway app-support dir;
  `--isolated` alone is *empty*; `--sample-photos`/`--faces` seed real photos.
  The catalog lives at `$ISOLATED/Teststrip/catalog.sqlite` (nested; the
  top-level `catalog.sqlite` is a stub).
- **Drive with `script/ax_drive.sh`** (`wait-vended`/`find`/`wait`/`press`/`type`),
  which re-asserts frontmost via System Events every poll — the primitive macOS
  permits when another app holds focus. Never rely on
  `NSRunningApplication.activate` (refused when unfocused). Match icon-only
  controls by `--help` (AXHelp) and empty sheet fields by `--contains` against
  the placeholder.
- **Keep the app warm during long waits.** A backgrounded/idle SwiftUI app parks
  its accessibility tree ("idle-wedge") and becomes undrivable; re-assert
  frontmost (`ax_drive.sh wait-vended`) on every poll while waiting for the
  worker, and drive promptly after launch. `script/verify_people_clustering.sh`
  is the reference pattern.
- **Assert against catalog ground truth, not just the render** — the UI can lag;
  the SQLite catalog, sidecar files, and on-disk originals are authoritative.
