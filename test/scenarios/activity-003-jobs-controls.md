# activity-003-jobs-controls: Activity popover jobs list caps at 4 and exposes per-job controls

**What this covers**: the Activity popover's "Activity" jobs section
(`ActivityCenterView.jobsSection`) — display caps at 4 rows with a
"+N more queued" line beyond that, and per-job controls whose visibility is
state-gated: star (persist/pin a work session), pause/resume (first row
only, queue-wide not per-job), and cancel (row-specific, with a distinct
control when the row is the actively-running job vs. a queued one). Also the
idle-worker row: a Stop affordance that appears only when the worker process
is alive but has nothing dispatched or queued.

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
   `activity-icon-states.md` step 1 for the same timing window).
2. **Cap-at-4 assertion**: count job rows in the popover
   (`ax_drive.sh find --role AXStaticText` against each job's title text, or
   count `AXGroup`/row containers under the jobs section). If more than 4
   jobs are ever visible simultaneously, assert exactly 4 render and a row
   reads `"N more queued"` where `N = totalJobs - 4`
   (`ActivityCenterView.swift:97-100`, exact string
   `"\(jobs.count - 4) more queued"`).
   `--smoke`'s 24-photo seed produces at most one or two concurrent
   preview/evaluation jobs in practice (see Sharp edges) — this assertion may
   not be exercisable without a larger corpus; if the popover never shows
   more than 4 rows, note that and fall back to a source-cited structural
   check instead of failing the card.
3. **Star control**: on any visible job row, if a star icon is present
   (`ax_drive.sh find --role AXButton --help "Star work"` or
   `"Unstar work"`), press it. Assert the help text flips
   (`Star work` ↔ `Unstar work`) and, once starred,
   `work_sessions.starred = 1` for that row's session id:
   ```bash
   sqlite3 "$DB" "SELECT id, starred FROM work_sessions WHERE id = '<job-id>';"
   ```
   The star button only renders when `canToggleWorkSessionStarred` is true —
   `catalog != nil && persistedWorkActivityIDs.contains(activity.id)`
   (`AppModel.swift:4326-4328`) — an activity that hasn't been persisted as a
   `work_sessions` row yet (e.g. the live in-progress import) has no star
   control. Don't expect it on every row.
4. **Pause/resume (first row only)**: pause and resume controls render only
   on `index == 0` (`showsQueueControls`, `ActivityCenterView.swift:94-95,
   136-155`) — never on row 2+, regardless of that row's own status. Confirm
   by AX: `ax_drive.sh find --role AXButton --help "Pause background work"`
   must not exist under any row past the first. Pressing it calls
   `model.pauseBackgroundWork()`, which is queue-wide (not scoped to one
   job) — assert that other queued rows' status also read Paused after the
   press, and separately assert the pause-notice text per step 4b below:
   ```bash
   sqlite3 "$DB" "SELECT id, status FROM work_sessions WHERE status IN ('queued','running','paused');"
   ```
4b. **Pause notice text has two variants** (`AppModel.backgroundWorkPauseNotice`,
   `AppModel.swift:2441-2444`), rendered below the jobs section
   (`ActivityCenterView.swift:28-32`) — assert the exact string matching
   whichever state was live at the moment Pause was pressed:
   - If nothing was actively running when paused (only queued items):
     `ax_drive.sh find --role AXStaticText --contains "Queue paused"` — exact
     text `"Queue paused"`.
   - If a job was actively running when paused (it finishes before the pause
     takes effect): exact text `"Queue paused after current task"`. Trigger
     this variant by pausing while a row's status reads Running rather than
     Queued.
   Both variants are mutually exclusive with each other and disappear
   entirely (no notice text at all) once resumed.
5. **Cancel semantics differ by row role**
   (`ActivityCenterView.swift:127-165`):
   - If the row *is* the actively-dispatched job
     (`model.activeWork?.id == job.activity.id && job.activity.status == .running`),
     the cancel button reads AXHelp `"Cancel work"` and calls
     `model.cancelActiveWork()` — it replaces the pause/resume slot entirely
     (mutually exclusive with step 4's controls on that row).
   - Otherwise, a queued/paused row's cancel button (when `job.canCancel`,
     i.e. `canCancelBackgroundWorkActivity` — the row's `work_sessions.status`
     is queued/running/paused, `AppModel.swift:2462-2467`) reads AXHelp
     `"Cancel this work item"` and calls
     `model.cancelBackgroundWork(id:)` scoped to that session id only.
   Press the row-scoped cancel on a queued (non-active) row; assert only that
   row's `work_sessions.status` becomes `cancelled`, siblings unaffected:
   ```bash
   sqlite3 "$DB" "SELECT id, status FROM work_sessions;"
   ```
6. **Idle-worker row**: wait for the queue to fully drain (poll per
   `activity-icon-states.md` step 2). Once drained, assert the idle-worker
   row appears: `ax_drive.sh find --role AXStaticText --contains "Worker idle"`
   with a co-located Stop button
   (`ax_drive.sh find --role AXButton --help "Stop idle worker"`). The row's
   condition is `canStopIdleWorkerProcess` =
   `transport.isRunning && dispatchedItemIDs.isEmpty && no queue item in an
   active status` (`WorkerSupervisor.swift:115-117`) — i.e. the worker
   *process* is alive but has nothing dispatched or queued, distinct from
   the toolbar's idle badge state which only reflects the queue, not the
   process. Press Stop; assert the worker process is no longer running
   (`model.isWorkerProcessRunning` false / no `Teststrip-Worker` process in
   `ps`), and the idle-worker row disappears (nothing left to stop).

## Expected
- Step 2: **Fails if** more than 4 job rows render simultaneously without a
  "+N more queued" line, or the line's count arithmetic is off by one.
- Step 4: **Fails if** a pause or resume control appears on any row other
  than the first, or if pressing pause only affects the pressed row instead
  of the whole queue.
- Step 4b: **Fails if** the notice text doesn't distinguish the
  running-when-paused case from the queued-only case, or if it persists
  after resume.
- Step 5: **Fails if** the active job's cancel button and a queued row's
  cancel button are not distinguishable by help text, or if row-scoped
  cancel affects sibling rows' status.
- Step 6: **Fails if** the idle-worker row appears while any queue item is
  still active, or persists after a successful Stop, or Stop fails to
  actually terminate the worker process.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- `--smoke`'s 24-photo seed drains its preview/evaluation queue quickly
  (single-digit seconds) and there is no seed variant that guarantees more
  than 4 concurrent jobs — the cap-at-4 and "+N more queued" assertions
  (step 2) may be **structurally confirmable only** (cite
  `ActivityCenterView.swift:94-101`) rather than live-exercisable against
  `--smoke`. This is a fixture gap, not a card bug — note it explicitly if
  hit rather than silently skipping the assertion.
- `work_sessions` and `source_roots` are both empty immediately after a
  fresh `--smoke` launch (confirmed via `sqlite3` 2026-07-10) — background
  jobs only populate `work_sessions` once real preview/evaluation work is
  dispatched, which is transient. Cards driving this file live must catch
  the popover in that window (right after launch) or trigger new work
  (e.g. an import) to repopulate it.
- Pause/resume being queue-wide rather than per-job is a real, deliberate
  product decision (`AppModel.canPauseBackgroundWork` reads
  `backgroundWorkQueue.isPaused`, a single flag) — not a bug, but worth
  re-confirming Jesse still wants that semantics per the "Star concept
  triplication" open item in `docs/product/focused-workspaces-followups.md`.

## Run status
NOT RUN — no host GUI available in this session; SQL grounding
(`work_sessions`/`source_roots` emptiness on a fresh `--smoke` catalog) was
verified headlessly against a seeded `--smoke` catalog on 2026-07-10 (schema
per `Sources/TeststripCore/Catalog/CatalogMigrations.swift`). All control
semantics above are confirmed by direct source citation
(`Sources/TeststripApp/ActivityCenterView.swift`,
`Sources/TeststripApp/AppModel.swift`,
`Sources/TeststripCore/Worker/WorkerSupervisor.swift`), not by driving the
UI. Needs a human-present or console-unlocked re-run to confirm the AX
labels/help text render as sourced and to attempt step 2's cap assertion
against real concurrent load.
