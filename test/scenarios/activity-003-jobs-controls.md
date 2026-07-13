**Task 7 note (2026-07-11)**: the Cull sidebar's former "Diagnostics"
disclosure (Rejects/Five Stars/Needs Keywords/Faces Found/OCR Found/Provider
Failures review-queue counts) was evaluated for a move into this popover's
job-details area per spec §2a bullet 3, and **not** moved — those rows are
click-to-cull review-queue sources, not background-job/source-availability
status, and this popover has no structural equivalent (the per-kind rows
section, `kindRowsSection`, is `work_sessions` rows grouped by kind;
`sourcesSection` is source-root availability). They now render inline in the
Cull sidebar's main list instead (`cull-015-sidebar-sources.md`). This
popover's rows/sections are unchanged by Task 7.

# activity-003-jobs-controls: Activity popover shows one bar per active work kind, with per-kind pause/resume/cancel

**What this covers**: **Reconciled 2026-07-13** for the per-kind-lanes
rewrite (`docs/superpowers/specs/2026-07-13-parallel-worker-lanes-design.md`).
The Activity popover's "Activity" section now renders one aggregate row per
active `WorkSessionKind` — `ActivityCenterPresentation.kindRows:
[ActivityKindRow]`, projected by `ActivityKindRow.rows(from:canPause:canResume:)`
(`Sources/TeststripApp/ActivityCenterPresentation.swift:72-139`) and rendered
by `kindRowsSection`/`kindRow`
(`Sources/TeststripApp/ActivityCenterView.swift:64-128`) — **replacing** the
former per-ITEM `jobsSection`/`jobRow` this card used to test: the star/pin
control, the cap-at-4-with-"+N more queued" line, and first-row-only
pause/resume are all **gone** (`ActivityKindRow` carries no `starred` field,
and grep of both files confirms zero references to "star" or "more
queued"). What's still there, in a per-kind rather than per-item shape:
- **Pause/resume are still queue-wide**, not scoped to a kind — despite
  being drawn on every kind row, `pauseWork(kind:)`/`resumeWork(kind:)` just
  delegate to `pauseBackgroundWork()`/`resumeBackgroundWork()`
  (`Sources/TeststripApp/AppModel.swift:7854-7860` →
  `7784-7808`), ignoring the `kind` parameter entirely. Because
  `canPause`/`canResume` are computed once and passed identically to every
  produced row (`ActivityCenterPresentation.swift:108-112, 134-135`), *every*
  visible kind row shows the same pause/resume affordance at the same
  time — there's no "first row only" concept anymore, because there's no
  concept of row order gating it to begin with.
- **Cancel is genuinely kind-scoped** — `cancelWork(kind:)`
  (`Sources/TeststripApp/AppModel.swift:7847-7852`) fans out over just that
  kind's active items via `WorkerSupervisor.cancel(id:)` per item
  (`Sources/TeststripCore/Worker/WorkerSupervisor.swift:195-211`), which the
  supervisor's own comment documents as leaving "sibling lanes running"
  (lines 198-201) — the concurrent-lanes headline feature this rewrite
  shipped. This is the one place per-kind vs. per-item genuinely matters now.
- **The idle-worker row is unchanged** by this rewrite.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`, then click the toolbar Activity
   button to open the popover while import/preview work is still draining
   (right after `--smoke` launch, before the queue empties — see
   `activity-001-icon-states.md` step 1 for the same timing window). For
   steps 4-6, which need **two concurrently active kinds** to be meaningful,
   prefer driving straight into `activity-007-per-kind-lanes.md`'s fixture
   (a mid-session import of `sample-data/photos/jesse-pictures`, 79 real
   JPEGs) rather than relying on `--smoke`'s fast-draining 24-photo seed —
   see Sharp edges.
2. **One row per active kind, not per item**: with the popover open, count
   rows under the "Activity" header (`kindRowsSection`,
   `Sources/TeststripApp/ActivityCenterView.swift:64-73`) by their title text
   (`ax_drive.sh find --role AXStaticText --label "<title>"` for each of the
   worker-dispatched kinds' titles — "Import photos", "Generate previews",
   "Evaluate photos", "Sync sidecars", "Check sources", "Find places",
   "Backfill locations"; full map at
   `Sources/TeststripApp/ActivityCenterPresentation.swift:85-100`). Assert no
   title appears twice — even if several `.previewGeneration` items are
   in-flight at once, they roll into a single "Generate previews" bar
   (`ActivityKindRow.rows` groups by kind before building rows,
   `Sources/TeststripApp/ActivityCenterPresentation.swift:113-118`).
3. **Determinate vs. indeterminate progress**: for a visible kind row, its
   `ProgressView` is determinate — `value: completedUnitCount, total:
   max(totalUnitCount, 1)` — only if **every** active item of that kind
   currently has a `totalUnitCount`; the aggregate `total` is computed as
   `nil` the moment even one item of that kind lacks one
   (`Sources/TeststripApp/ActivityCenterPresentation.swift:122-123`,
   `totals.count == items.count ? totals.reduce(0, +) : nil`), which renders
   a plain indeterminate `ProgressView()`
   (`Sources/TeststripApp/ActivityCenterView.swift:78-84`). Confirm which
   case is live for at least one row by cross-checking
   `completedUnitCount`/`totalUnitCount` isn't rendered numerically anywhere
   in the row when indeterminate (there's no percentage text — only the
   spinner) versus a literal fraction when determinate.
4. **Per-kind pause/resume is queue-wide, applied uniformly to every row**:
   with at least two kind rows visible (e.g. "Generate previews" and
   "Evaluate photos"), assert **both** show a pause button — `pause.circle`,
   AXHelp exactly `"Pause background work"`
   (`Sources/TeststripApp/ActivityCenterView.swift:91-99`) — at the same
   time; this is the same boolean (`canPauseBackgroundWork`,
   `Sources/TeststripApp/AppModel.swift:2742-2745`) passed to every row, not
   a first-row-only gate. Press pause on **either** row's button
   (`model.pauseWork(kind:)` → `pauseBackgroundWork()`,
   `Sources/TeststripApp/AppModel.swift:7854-7856` → `7784-7795`). Assert:
   - the **other** visible row's control also flips from pause to resume
     (`play.circle`, AXHelp `"Resume background work"`,
     `Sources/TeststripApp/ActivityCenterView.swift:100-108`) — proving one
     press paused the whole queue, not just the pressed row's kind.
   - the pause notice renders below the kind-rows section
     (`model.backgroundWorkPauseNotice`,
     `Sources/TeststripApp/AppModel.swift:2751-2754`; rendered at
     `Sources/TeststripApp/ActivityCenterView.swift:25-29`) with the correct
     variant: exact text `"Queue paused"` if nothing was running the instant
     it was pressed, `"Queue paused after current task"` if a lane was
     actively running.
   - ground truth: poll `work_sessions`/`preview_generation_queue` a few
     seconds apart; no additional item transitions from queued to running
     while paused (`BackgroundWorkQueue.activateRunnableItems()` early-returns
     while `isPaused`, `Sources/TeststripCore/Work/BackgroundWorkQueue.swift:89-90`)
     — a currently-running item is allowed to finish (see Sharp edges: its
     `status` does **not** flip to `.paused`, it just keeps reading whatever
     it already was).
     ```bash
     sqlite3 "$DB" "SELECT kind, status FROM work_sessions WHERE status IN ('queued','running');"
     ```
5. **Resume**: press either row's resume button
   (`model.resumeWork(kind:)` → `resumeBackgroundWork()`,
   `Sources/TeststripApp/AppModel.swift:7858-7860` → `7797-7808`). Assert the
   pause notice disappears entirely (no notice text at all) and, if items
   remain queued, progress resumes across **all** active kinds, not only the
   one whose button was pressed.
6. **Per-kind cancel — the concurrency-preserving semantics**: with two kind
   rows active, press cancel on **one** row only
   (`xmark.circle`, AXHelp `"Cancel this work item"` for a non-`.ingest` kind
   or `"Cancel import"` for `.ingest`,
   `Sources/TeststripApp/ActivityCenterView.swift:109-121`). This calls
   `model.cancelWork(kind:)` (or `cancelImportWork()` for `.ingest`), which
   cancels only that kind's currently-active items
   (`Sources/TeststripApp/AppModel.swift:7847-7852`) via
   `WorkerSupervisor.cancel(id:)` per item — per-item cancel, leaving sibling
   lanes running by design (`Sources/TeststripCore/Worker/WorkerSupervisor.swift:195-211`).
   Assert:
   - the cancelled kind's row disappears from the popover (its last active
     item lands in `.cancelled`, so `canCancel`
     (`Sources/TeststripApp/ActivityCenterPresentation.swift:136`) goes false
     and no items remain to roll into a row) while the **other** kind's row
     is still present and its `completedUnitCount` (or the underlying
     table's row count) has increased across two samples a few seconds
     apart — proving the sibling lane kept running rather than being
     terminated alongside the cancelled one.
   - ground truth:
     ```bash
     sqlite3 "$DB" "SELECT kind, status FROM work_sessions WHERE kind = '<cancelled-kind>' ORDER BY updated_at DESC LIMIT 5;"
     ```
     the cancelled kind's active items read `cancelled`; a parallel query for
     the sibling kind shows `queued`/`running` rows still present.
7. **Idle-worker row** (unchanged by this rewrite): wait for the queue to
   fully drain (poll per `activity-001-icon-states.md` step 2). Once drained,
   assert the idle-worker row appears:
   `ax_drive.sh find --role AXStaticText --contains "Worker idle"`
   (`model.idleWorkerStatusText`, `Sources/TeststripApp/AppModel.swift:2764-2766`)
   with a co-located Stop button
   (`ax_drive.sh find --role AXButton --help "Stop idle worker"`,
   `Sources/TeststripApp/ActivityCenterView.swift:154-168`). The row's
   condition is `canStopIdleWorkerProcess` = `transport.isRunning &&
   dispatchedItemIDs.isEmpty && no queue item in an active status`
   (`Sources/TeststripCore/Worker/WorkerSupervisor.swift:116-118`) — with
   concurrent lanes this now means **no lane** has anything dispatched, not
   just a single one-at-a-time slot, but the observable condition is the
   same: worker process alive, nothing dispatched or queued. Press Stop;
   assert the worker process is no longer running (`model.isWorkerProcessRunning`
   false / no `Teststrip-Worker` process in `ps`), and the idle-worker row
   disappears (nothing left to stop).

## Expected
- Step 2: **Fails if** two rows ever render for the same kind simultaneously,
  or a row's title doesn't match the exact map in
  `ActivityKindRow.title(for:)`.
- Step 3: **Fails if** a row shows a determinate progress value while any of
  its underlying items lacks a `totalUnitCount`, or vice versa.
- Step 4: **Fails if** a pause control appears on only one of several active
  kind rows, or if pressing pause on one row leaves another row's
  pause/resume control unchanged (proving it wrongly scoped pause to a single
  kind), or if the notice text doesn't distinguish the running-when-paused
  case from the queued-only case.
- Step 5: **Fails if** resuming only un-pauses the kind whose button was
  pressed, or the notice text persists after resume.
- Step 6: **Fails if** cancelling one kind's row also stops or cancels the
  other active kind's work — that would be a regression of the concurrent
  per-lane cancel semantics this rewrite exists to ship.
- Step 7: **Fails if** the idle-worker row appears while any queue item is
  still active, or persists after a successful Stop, or Stop fails to
  actually terminate the worker process.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **Dropped from this card, confirmed gone from source**: the "+N more
  queued" cap-at-4 line and the star/pin control. Grep of
  `ActivityCenterView.swift` and `ActivityCenterPresentation.swift` finds no
  match for "more queued", "star", or "Unstar" — and `ActivityKindRow`
  (`Sources/TeststripApp/ActivityCenterPresentation.swift:72-83`) simply has
  no `starred` field to surface, unlike the retired `ActivityJobRow` (which
  held the full `AppWorkActivity`, itself still `starred`-bearing at the
  `WorkSession`/`work_sessions.starred` layer — that column is untouched, it
  is just never read by this popover anymore).
- **`WorkSessionStatus.paused` is never actually assigned to a live
  `BackgroundWorkItem`** — this predates the per-kind rewrite (it's a
  property of `Sources/TeststripCore/Work/BackgroundWorkQueue.swift`, which
  this branch didn't touch) but is newly load-bearing for this card because
  the prior version of this card assumed a paused row's status flips to
  `"Paused"`. It doesn't: `pause()` (`BackgroundWorkQueue.swift:138-140`)
  only flips the queue-level `isPaused` flag; grep of `Sources/` for
  `= .paused` finds zero assignments anywhere, only defensive
  `.contains([...])` filter checks. So a kind row's status label
  (`label(for:)`, `Sources/TeststripApp/ActivityCenterView.swift:130-139`)
  keeps reading whatever it was before the pause ("Running" for the item
  that was mid-flight, "Queued" for backlog items) — the *only* visible
  paused indicator is the separate notice text below the kind-rows section.
  Step 4 above asserts the notice, not a per-row "Paused" status label;
  don't reintroduce that assumption.
- `--smoke`'s 24-photo seed is pre-rendered (no queued previews at idle,
  confirmed in `worker-001-preview-lifecycle.md`) and drains its
  preview/evaluation queue within single-digit seconds — steps 2-6 need
  either the launch-window timing trick (step 1) or a fresh mid-session
  import to reliably have two kinds visibly active long enough to drive by
  hand. `activity-007-per-kind-lanes.md` is the card that establishes and
  exercises that fixture in depth; this card can piggyback on the same
  import rather than re-deriving a fixture.

## Run status
NOT RUN — reconciled 2026-07-13 for the per-kind-lanes rewrite; no host GUI
available in this session. All control semantics above (pause/resume
uniformity across rows, per-kind cancel fan-out and sibling-lane survival,
the dead `.paused` status finding, the idle-worker row) are confirmed by
direct source citation (`Sources/TeststripApp/ActivityCenterView.swift`,
`Sources/TeststripApp/ActivityCenterPresentation.swift`,
`Sources/TeststripApp/AppModel.swift`,
`Sources/TeststripCore/Worker/WorkerSupervisor.swift`,
`Sources/TeststripCore/Work/BackgroundWorkQueue.swift`), not by driving the
UI. Needs a human-present or console-unlocked re-run (VM, per
`test/scenarios/README.md`) to confirm the AX labels/help text render as
sourced and to drive the two-active-kinds scenario against real concurrent
load.
