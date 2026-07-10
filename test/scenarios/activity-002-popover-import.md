# activity-002-popover-import: Activity popover shows live import phase/progress with cancel, and surfaces errors

**What this covers**: inventory items 20-21 — the Activity Center popover's
import section renders live progress and a phase label while an import job
runs, with a cancel affordance; and how a completed-with-errors import is (or
isn't) surfaced distinctly rather than silently swallowed. Types and views
are `ActivityCenterPresentation`/`ImportProgressRow`
(`Sources/TeststripApp/ActivityCenterPresentation.swift`) rendered by
`ActivityCenterView` (`Sources/TeststripApp/ActivityCenterView.swift`) — both
names confirmed against source before drafting this card.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Baseline verified 2026-07-10: 24 assets, no active `work_sessions`
(`SELECT count(*) FROM work_sessions WHERE status IN ('queued','running')` →
0 at idle), no `importError`.

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

### Part A — live progress + phase text + cancel
1. `script/ax_drive.sh wait-vended Teststrip`.
2. Start an import of a folder with enough files that the import doesn't
   finish before the popover can be inspected (use `--sample-photos` volume
   or a larger fixture folder if `--smoke`'s import is too fast to observe
   mid-flight — confirm live).
3. Open the Activity popover (toolbar Activity button). Assert the import
   section renders: a `ProgressView` bound to `progress.fraction` and a phase
   label (`importSection`, `Sources/TeststripApp/ActivityCenterView.swift:68-85`).
   The phase label comes from `ImportProgressRow.phaseLabel`
   (`Sources/TeststripApp/ActivityCenterPresentation.swift:29-53`), which is
   status-driven: `"Queued"` / `"Importing"` (while `.running`) / `"Paused"` /
   `"Done"` / `"Failed"` / `"Cancelled"`. Assert the visible text is exactly
   `"Importing"` while the import runs — **not** a generic "Working…" or the
   activity's raw title.
4. Assert the cancel button is present: an `xmark.circle` icon button, AXHelp
   exactly **"Cancel import"** (`Sources/TeststripApp/ActivityCenterView.swift:76-82`).
   `ax_drive.sh find --role AXButton --help "Cancel import"`.
5. Click cancel (`ax_drive.sh press --role AXButton --help "Cancel import"`);
   this calls `model.cancelImportWork()`
   (`Sources/TeststripApp/AppModel.swift:7174`). Assert the phase label
   transitions to `"Cancelled"` (`ImportProgressRow.phaseLabel`'s `.cancelled`
   branch) and, on ground truth, the import's `work_sessions` row lands in
   `status='cancelled'`:
   ```bash
   sqlite3 "$DB" "SELECT status FROM work_sessions WHERE kind='ingest' ORDER BY created_at DESC LIMIT 1;"
   ```

### Part B — completed-with-errors surfacing
6. Re-launch (or use a fresh import) with a fixture that produces
   `skippedSourceFileCount > 0` and/or `previewFailures` — the two inputs to
   `importCompletionWarningText`
   (`Sources/TeststripApp/AppModel.swift:11091-11106`). Wait for completion.
7. **Ground-truth what actually got recorded**:
   ```bash
   sqlite3 "$DB" "SELECT status, detail, failure_count FROM work_sessions WHERE kind='ingest' ORDER BY created_at DESC LIMIT 1;"
   ```
   (column names confirmed against `Sources/TeststripCore/Catalog/CatalogMigrations.swift:93-109`:
   `work_sessions` has `failure_count` and `issues_json`, matching
   `AppWorkActivity.failureCount`/`.issues`.)
8. **Surfacing assertion — this is the part likely to fail, see Sharp edges**:
   open the Activity popover and look for a *distinct* error row. Per source,
   a completed-with-errors import is recorded with `status: .completed`
   (`recordCompletedImportActivity`, `Sources/TeststripApp/AppModel.swift:11158-11189`)
   — the same status as a clean import — with the warning folded into the
   **same job row's detail text** as a parenthetical suffix (e.g. "Imported 6
   photos (2 files skipped)", `importCompletionDetail`,
   `Sources/TeststripApp/AppModel.swift:11235-11247`). `jobRow`
   (`Sources/TeststripApp/ActivityCenterView.swift:105-176`) renders that
   detail as a 2-line-truncated caption with no distinct styling, icon, or
   section for the error condition — `color(for:)`
   (`Sources/TeststripApp/ActivityCenterView.swift:189-198`) only
   distinguishes `.failed`/`.cancelled` (red) from `.completed` (green); a
   completed-with-warnings row reads green, identical to a clean import,
   differing only in caption text a user must read closely.
   Assert (falsifiably) whether a distinct error affordance exists: **fails
   if** the only signal of a partial failure is text buried in a
   two-line-truncated caption — that is the "silently swallowed" failure mode
   this card was written to catch, and per source reading it appears to be
   the actual current behavior (see Sharp edges).

## Expected
- Step 3: **fails if** the phase label doesn't read exactly `"Importing"`
  while running, or doesn't transition through the documented states.
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
- **Suspected product gap**: reading `Sources/TeststripApp/ActivityCenterView.swift`
  end to end, there is no code path that renders a distinct error row for a
  completed-with-errors import — `jobsSection`/`jobRow` render every
  `ActivityJobRow` uniformly regardless of `failureCount`/`issues`, and
  `WorkSessionIssue` (`Sources/TeststripCore/Work/WorkSession.swift:36-40`,
  populated by `workSessionIssues(for:)` at
  `Sources/TeststripApp/AppModel.swift:11249-11257`) is never read anywhere in
  `ActivityCenterView.swift` — grep confirms zero references to `.issues` in
  that file. If the live run confirms no distinct row/indicator exists, this
  is the bug worth flagging to Jesse: partial-failure imports currently look
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
- `importError` (the red text row, `Sources/TeststripApp/ActivityCenterView.swift:20-24`)
  is a *different*, harder-failure signal — set only by `failImportActivity`
  (`Sources/TeststripApp/AppModel.swift:11259-11274`) when the import throws
  outright (e.g. the source folder vanished mid-import), not by a
  partial/soft failure. Don't conflate the two: this card's Part B is about
  the soft-failure (`.completed` with warnings) case, which is the one with
  no distinct surfacing; the hard-failure `importError` row already is
  visually distinct (red text, separate from the job list).

## Run status
SOURCE-GROUNDED, AX-UNRUN, ONE OPEN QUESTION. Phase-label states, the cancel
button's AXHelp, `cancelImportWork()`, and the completed-with-errors code
path (which appears to have no distinct popover surfacing) were all
confirmed by reading source with file:line references above on 2026-07-10.
The `work_sessions` idle baseline and the `failure_count`/`issues_json`
column names were confirmed against a freshly seeded `--smoke` catalog and
`CatalogMigrations.swift` the same day. The Step 6 fixture recipe for
genuine preview/skip failures (as opposed to silently-excluded unsupported
extensions) is unconfirmed — an open question for whoever runs this card live. The
Part A steps (progress/phase/cancel) need a human-present or
isolated-console re-run; not run live this session due to concurrent-agent
build contention on the shared `dist/Teststrip.app`. Schema per
`Sources/TeststripCore/Catalog/CatalogMigrations.swift` (version 19).
