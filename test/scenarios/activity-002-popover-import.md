# activity-002-popover-import: Activity popover shows live import progress (as the .ingest kind row) with cancel, and surfaces errors

**What this covers**: inventory items 20-21 — the Activity Center popover
renders live progress for an in-flight import with a cancel affordance, and
how a completed-with-errors import is (or isn't) surfaced distinctly rather
than silently swallowed. **Reconciled 2026-07-13** for the per-kind-lanes
rewrite: the popover's dedicated `importSection` is gone — import now folds
in as an ordinary `.ingest` `ActivityKindRow` titled "Import photos"
(`ActivityKindRow.title(for:)`, `Sources/TeststripApp/ActivityCenterPresentation.swift:87`),
rendered by the same `kindRowsSection`/`kindRow` every other work kind uses
(`Sources/TeststripApp/ActivityCenterView.swift:64-128`). `ImportProgressRow`
(`Sources/TeststripApp/ActivityCenterPresentation.swift:5-30`) still exists
and is still constructed onto `ActivityCenterPresentation.importProgress`
(`Sources/TeststripApp/ActivityCenterPresentation.swift:155,169`), but grep
confirms zero references to `importProgress` in `ActivityCenterView.swift` —
it's a `LibraryGridView` concern now, and a narrower one than "consumed
elsewhere" suggests: `LibraryGridView.swift:438` reads only its `.fraction`
field, for the toolbar icon's small circular progress ring
(`activityToolbarIcon`, `ProgressView(value: presentation.importProgress?.fraction)`).
`ImportProgressRow.phaseLabel`/`.cancelActionID` (the fields that would carry
the "Importing"/"Cancelled" phase text and a cancel target) have **zero**
readers anywhere in `Sources/` outside their own definition — grep confirms
it. (`LibraryGridView.swift:2899-2901`'s `importProgressPresentation` looks
similar by name but is unrelated: it builds a *different* type,
`ImportProgressPresentation` (`LibraryGridView.swift:8937`), straight
from `model.visibleImportActivity`, never touching `ImportProgressRow` at
all — don't conflate the two when reading this file.) Don't conflate any of
this with what this card tests: the Activity popover's `.ingest` kind row,
which gets its status/detail from `ActivityKindRow`, not from
`ImportProgressRow`.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Baseline verified 2026-07-10: 24 assets, no active `work_sessions`
(`SELECT count(*) FROM work_sessions WHERE status IN ('queued','running')` →
0 at idle), no `importError`. Schema/behavior around `work_sessions` and
import completion is unaffected by the per-kind-lanes rewrite — only the
popover's rendering of it changed — so this baseline still holds.

Fixture folder with a mix of importable and unimportable files, for the
completed-with-errors half of this card:
```bash
FIXTURES=$(mktemp -d)/activity-import
mkdir -p "$FIXTURES"
swift run TeststripBench seed-dup-fixtures "$(mktemp -d)/seed"   # reuse real JPEGs
cp "$(mktemp -d)"/nonexistent 2>/dev/null || true                 # placeholder; see Sharp edges
```
See Sharp edges — this card's error-path fixture (files that fail
preview/backup, as opposed to merely unsupported extensions the importer
skips silently) is not yet proven producible headlessly; document what's
actually achievable during the live run rather than forcing a fixture that
doesn't reflect a real failure mode.

## Steps

### Part A — live progress + status + cancel, as the .ingest kind row
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Start an import of a folder with enough files that the import doesn't
   finish before the popover can be inspected (use `--sample-photos` volume
   or a larger fixture folder if `--smoke`'s import is too fast to observe
   mid-flight — confirm live; `sample-data/photos/jesse-pictures`, 79 real
   JPEGs, is a proven larger fixture — see `activity-007-per-kind-lanes.md`).
3. Open the Activity popover (toolbar Activity button). Assert exactly one
   kind row renders for the import — titled exactly **"Import photos"**
   (`ActivityKindRow.title(for:)` `.ingest` case,
   `Sources/TeststripApp/ActivityCenterPresentation.swift:87`) — under the
   "Activity" header (`kindRowsSection`, `Sources/TeststripApp/ActivityCenterView.swift:64-73`).
   The row shows a `ProgressView` (determinate if the activity has a
   `totalUnitCount`, else indeterminate — `kindRow`,
   `Sources/TeststripApp/ActivityCenterView.swift:78-84`) and a status label
   from `label(for:)` (`Sources/TeststripApp/ActivityCenterView.swift:130-139`).
   Assert the visible status text is exactly **"Running"** while the import
   runs (`.running` → `"Running"`, line 133) — **not** `"Importing"`. That
   `"Importing"` string is `ImportProgressRow.phaseLabel`'s
   (`Sources/TeststripApp/ActivityCenterPresentation.swift:20-29`), which per
   the note above no longer feeds this popover; conflating the two would be
   testing dead code.
4. Assert the cancel button is present: an `xmark.circle` icon button, AXHelp
   exactly **"Cancel import"** — the `.ingest`-specific branch of the shared
   cancel control (`row.kind == .ingest ? "Cancel import" : "Cancel this work
   item"`, `Sources/TeststripApp/ActivityCenterView.swift:109-121`, ternary at
   line 120). `ax_drive.sh find --role AXButton --help "Cancel import"`.
5. Click cancel (`ax_drive.sh press --role AXButton --help "Cancel import"`);
   the `.ingest` branch calls `model.cancelImportWork()`
   (`Sources/TeststripApp/ActivityCenterView.swift:111-113` →
   `Sources/TeststripApp/AppModel.swift:7862-7879`). Assert the row's status
   label transitions to **"Cancelled"** (`label(for:)`'s `.cancelled` branch,
   line 137) and, on ground truth, the import's `work_sessions` row lands in
   `status='cancelled'`:
   ```bash
   sqlite3 "$DB" "SELECT status FROM work_sessions WHERE kind='ingest' ORDER BY created_at DESC LIMIT 1;"
   ```

### Part B — completed-with-errors surfacing
6. Re-launch (or use a fresh import) with a fixture that produces
   `skippedSourceFileCount > 0` and/or `previewFailures` — the two inputs to
   `importCompletionWarningText`
   (`Sources/TeststripApp/AppModel.swift:12093-12108`). Wait for completion.
7. **Ground-truth what actually got recorded**:
   ```bash
   sqlite3 "$DB" "SELECT status, detail, failure_count FROM work_sessions WHERE kind='ingest' ORDER BY created_at DESC LIMIT 1;"
   ```
   (column names confirmed against `Sources/TeststripCore/Catalog/CatalogMigrations.swift:93-109`:
   `work_sessions` has `failure_count` and `issues_json`, matching
   `AppWorkActivity.failureCount`/`.issues`.)
8. **Surfacing assertion — this is the part likely to fail, see Sharp edges**:
   open the Activity popover and look for a *distinct* error row/indicator on
   the "Import photos" kind row. Per source, a completed-with-errors import is
   recorded with `status: .completed`
   (`recordCompletedImportActivity`, `Sources/TeststripApp/AppModel.swift:12160-12191`)
   — the same status as a clean import — with the warning folded into the
   **same row's detail text** as a parenthetical suffix (e.g. "Imported 6
   photos (2 files skipped)", `importCompletionDetail`,
   `Sources/TeststripApp/AppModel.swift:12237-12249`). `kindRow`
   (`Sources/TeststripApp/ActivityCenterView.swift:75-128`) renders that
   detail as a 2-line-truncated caption (`row.detail`, line 123-126) with no
   distinct styling, icon, or section for the error condition —
   `color(for:)` (`Sources/TeststripApp/ActivityCenterView.swift:141-150`)
   only distinguishes `.failed`/`.cancelled` (red) from `.completed` (green);
   a completed-with-warnings row reads green, identical to a clean import,
   differing only in caption text a user must read closely. This is now
   structurally *more* certain to be true than before the per-kind rewrite:
   `ActivityKindRow` (`Sources/TeststripApp/ActivityCenterPresentation.swift:72-101`)
   doesn't even carry a `failureCount`/`issues` field at all — the prior
   per-item `ActivityJobRow` at least held the full `AppWorkActivity` (which
   does have those fields, just unread by the view); the new aggregate row
   can't surface them even if a future edit wanted to, without adding fields
   to the struct first.
   Assert (falsifiably) whether a distinct error affordance exists: **fails
   if** the only signal of a partial failure is text buried in a
   two-line-truncated caption — that is the "silently swallowed" failure mode
   this card was written to catch, and per source reading it appears to be
   the actual current behavior (see Sharp edges).

## Expected
- Step 3: **fails if** the status label doesn't read exactly `"Running"`
  while running, or more than one row renders for a single in-flight import.
- Step 4/5: **fails if** no cancel button exists, or clicking it doesn't move
  the `work_sessions` row to `cancelled`.
- Step 8: **fails if** — inverted from the usual convention, because source
  reading suggests the negative is what's true — a distinct, non-text-buried
  error indicator (icon, color, separate row/section) is genuinely absent
  from the popover for a completed-with-errors import. If the live run shows
  one does exist (this card's static-source read could be wrong, or a
  surface this reading missed renders it), record that and correct this
  card's Sharp edges rather than treating the mismatch as a pass/fail
  ambiguity.

## Cleanup
```bash
rm -rf "$FIXTURES"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **Suspected product gap, now structurally reinforced**: reading
  `Sources/TeststripApp/ActivityCenterView.swift` and
  `Sources/TeststripApp/ActivityCenterPresentation.swift` end to end, there is
  no code path that renders a distinct error row for a completed-with-errors
  import — `kindRowsSection`/`kindRow` render every `ActivityKindRow`
  uniformly regardless of the underlying items' `failureCount`/`issues`, and
  `WorkSessionIssue` (`Sources/TeststripCore/Work/WorkSession.swift:36-40`,
  populated by `workSessionIssues(for:)` at
  `Sources/TeststripApp/AppModel.swift:12251-12259`) is never read anywhere in
  either file — grep confirms zero references to `.issues`/`failureCount` in
  both. If the live run confirms no distinct row/indicator exists, this is
  the bug worth flagging to Jesse: partial-failure imports currently look
  identical (green "Done") to clean ones in the popover, differing only in a
  parenthetical clause inside a 2-line-truncated caption.
- The Step 6 fixture (files that cause `previewFailures` or
  `skippedSourceFileCount`, as opposed to unsupported extensions the importer
  silently excludes from its candidate list before ever counting them) isn't
  proven producible with an existing seeder — confirm during the live run
  which concrete file condition (corrupt JPEG? permission-denied file?
  duplicate filename collision?) actually drives `skippedSourceFileCount` or
  `previewFailures` up, and record the working fixture recipe back into this
  card once confirmed.
- `importError` (the red text row, `Sources/TeststripApp/ActivityCenterView.swift:17-21`)
  is a *different*, harder-failure signal — set only by `failImportActivity`
  (`Sources/TeststripApp/AppModel.swift:12261-12276`) when the import throws
  outright (e.g. the source folder vanished mid-import), not by a
  partial/soft failure. Don't conflate the two: this card's Part B is about
  the soft-failure (`.completed` with warnings) case, which is the one with
  no distinct surfacing; the hard-failure `importError` row already is
  visually distinct (red text, separate from the kind rows).
- **Concurrent lanes don't change this card's assertions, only its
  citations.** `.ingest` runs as its own lane alongside `.previewGeneration`/
  `.recognition` under the per-kind-lanes rewrite
  (`docs/superpowers/specs/2026-07-13-parallel-worker-lanes-design.md`), but
  the import row's own status/progress/cancel semantics are unchanged by
  that — a single `.ingest` item behaves the same whether or not sibling
  lanes are also active. See `activity-007-per-kind-lanes.md` for the
  concurrency-specific assertions (two kinds' bars advancing at once).

## Run status
SOURCE-GROUNDED, AX-UNRUN, ONE OPEN QUESTION. Reconciled 2026-07-13 against
the per-kind-lanes rewrite (`ActivityCenterView.swift`,
`ActivityCenterPresentation.swift` re-read in full; `AppModel.swift`
citations re-verified at their current line numbers on this branch). The
status-label states, the cancel button's AXHelp, `cancelImportWork()`, and
the completed-with-errors code path (which appears to have no distinct
popover surfacing, now structurally more certain given `ActivityKindRow`'s
narrower field set) were all confirmed by reading source with file:line
references above on 2026-07-13. The `work_sessions` idle baseline and the
`failure_count`/`issues_json` column names were confirmed against a freshly
seeded `--smoke` catalog and `CatalogMigrations.swift` on 2026-07-10 and are
unaffected by this rewrite. The Step 6 fixture recipe for genuine
preview/skip failures (as opposed to silently-excluded unsupported
extensions) is unconfirmed — an open question for whoever runs this card
live. The Part A steps (progress/status/cancel) need a human-present or
isolated-console re-run; not run live this session (markdown-only
reconciliation pass, no VM available). Schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` (`version = 19`,
re-verified unchanged on this branch on 2026-07-13).
