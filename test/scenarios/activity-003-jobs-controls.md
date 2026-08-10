# activity-003-jobs-controls: one published row per work kind, with queue Pause/Resume and kind-scoped Cancel

**What this covers**: the Activity popover projects all active background work
into one published snapshot per `WorkSessionKind`. Every row shares the current
queue-wide Pause/Resume state. Cancel is different: it requests cancellation
only for the active item IDs represented by the selected published kind row.
After all lanes settle, the still-running worker appears as `Worker idle` with
a Stop action.

This is the current per-kind surface. The retired per-item list, four-row cap,
`+N more queued`, first-row-only controls, and star/pin affordance are not part
of the product and are not tested here.

Source: `Sources/TeststripApp/ActivityCenterPresentation.swift`
(`ActivityKindRow.rows` grouping and total rule),
`Sources/TeststripApp/ActivityCenterView.swift` (row progress and controls),
`Sources/TeststripApp/AppModel.swift` (`activeWorkKindRows`, queue-wide
pause/resume, kind-scoped Cancel, idle-worker projection, and coalesced
publication), and `Sources/TeststripCore/Worker/WorkerSupervisor.swift`
(dispatched-item soft cancellation).

## Pre-state

Every scripted UI, filesystem, and catalog operation must go through the Tart
wrapper. The determinate-bar inspection and row-scoped Cancel below are
explicit visible gestures inside Tart because the current AX driver cannot
bind them; neither may be replaced by a host command. Copy the 130 public
`smokebig` originals into a card-owned folder and import them into a fresh
`empty` catalog. Do not launch the pre-populated `smokebig` catalog and do not
use a host launch-window timing trick.

```bash
script/vm_scenario_run.sh sync empty smokebig
script/vm_scenario_run.sh launch empty
script/vm_scenario_run.sh ax wait-vended Teststrip
test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets;")" -eq 0

script/vm_scenario_run.sh shell '
set -eu
fixture="$HOME/teststrip-vm/fixtures/activity-003-smokebig"
rm -rf "$fixture"
mkdir -p "$fixture"
set -- "$HOME"/teststrip-vm/isolated/smokebig/Teststrip/SmokeOriginals/*.jpg
test "$#" -eq 130
for source in "$@"; do
    cp "$source" "$fixture/$(basename "$source")"
done
test "$(find "$fixture" -type f -name "*.jpg" | wc -l | tr -d " ")" -eq 130
test "$(find "$fixture" -type f -name "*.xmp" | wc -l | tr -d " ")" -eq 0
'
```

## Steps

### 1. Import without automatic evaluation and establish a durable preview load

1. Record the ingest frontier. Drive the real Import Path sheets with wrapper
   AX, turn the default-on automatic-read checkbox **off**, and start the exact
   130-photo import:

   ```bash
   BEFORE_INGEST_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='ingest';")
   script/vm_scenario_run.sh ax press --role AXButton --label "Import Path"
   script/vm_scenario_run.sh ax wait --role AXTextField --label "Folder path"
   script/vm_scenario_run.sh ax type --role AXTextField --label "Folder path" --text "/Users/admin/teststrip-vm/fixtures/activity-003-smokebig"
   script/vm_scenario_run.sh ax press --role AXButton --label "Review Import"
   script/vm_scenario_run.sh ax wait --role AXCheckBox --label "Read imported frames automatically"
   script/vm_scenario_run.sh ax press --role AXCheckBox --label "Read imported frames automatically"
   script/vm_scenario_run.sh ax wait --role AXButton --label "Import 130 Photos"
   script/vm_scenario_run.sh ax press --role AXButton --label "Import 130 Photos"
   ```

2. Bind the new ingest by `rowid` and wait for its persisted completion. Then
   wait until at least 40 assets have a cached grid preview while real preview
   backlog remains. Zero evaluation signals proves the toggle was off:

   ```bash
   attempt=0
   INGEST_SESSION_ID=
   while [ "$attempt" -lt 120 ]; do
       INGEST_SESSION_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='ingest' AND rowid > $BEFORE_INGEST_ROWID AND status='completed' ORDER BY rowid LIMIT 1;")
       test -n "$INGEST_SESSION_ID" && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test -n "$INGEST_SESSION_ID"
   test "$(script/vm_scenario_run.sh sql empty "SELECT status FROM work_sessions WHERE id='$INGEST_SESSION_ID';")" = completed
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets;")" -eq 130

   attempt=0
   while [ "$attempt" -lt 120 ]; do
       CACHED_GRID_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets a WHERE NOT EXISTS (SELECT 1 FROM preview_generation_queue q WHERE q.asset_id=a.id AND q.level='grid');")
       PENDING_PREVIEW_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
       test "$CACHED_GRID_COUNT" -ge 40 && test "$PENDING_PREVIEW_COUNT" -gt 0 && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$CACHED_GRID_COUNT" -ge 40
   test "$PENDING_PREVIEW_COUNT" -gt 0
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM evaluation_signals;")" -eq 0
   ```

   If all preview rows drain before this condition, the fixture did not sustain
   the card and the run fails. Do not replace it with a launch race.

### 2. Freeze the queue, add one finite evaluation batch, then publish both kinds

3. Open the positive working control and pause the one visible Generate row.
   Wait for exact `Queue paused`, not the transient `Queue paused after current
   task`: the exact text proves all dispatched work reached a terminal and no
   new command can dispatch while the queue stays frozen.

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - working"
   script/vm_scenario_run.sh ax wait --role AXStaticText --label "Generate previews"
   script/vm_scenario_run.sh ax press --role AXButton --help "Pause background work"
   script/vm_scenario_run.sh ax wait --role AXStaticText --label "Queue paused"
   script/vm_scenario_run.sh ax find --role AXButton --help "Resume background work"
   script/vm_scenario_run.sh key 'key code 53'
   ```

4. While frozen, invoke the real `Evaluate Matches` menu action. It enqueues
   one finite batch over at most 40 cached assets; automatic import evaluation
   is off, so preview completions cannot append hidden recognition IDs after
   the published row is bound.

   ```bash
   script/vm_scenario_run.sh ax press --role AXMenuItem --label "Evaluate Matches"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - working"
   script/vm_scenario_run.sh ax wait --role AXStaticText --label "Evaluate photos"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused"
   ```

5. Capture all static text in one AX traversal and both generic Cancel controls
   in one control traversal. This avoids straddling two coalesced publications:

   ```bash
   ACTIVITY_TEXT=$(script/vm_scenario_run.sh ax find --role AXStaticText)
   PREVIEW_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Generate previews" { count += 1 } END { print count + 0 }')
   EVALUATION_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Evaluate photos" { count += 1 } END { print count + 0 }')
   CONTROL_TEXT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item")
   CANCEL_CONTROL_COUNT=$(printf '%s\n' "$CONTROL_TEXT" | awk 'NF { count += 1 } END { print count + 0 }')
   RESUME_CONTROL_COUNT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Resume background work" | awk 'NF { count += 1 } END { print count + 0 }')
   test "$PREVIEW_ROW_COUNT" -eq 1
   test "$EVALUATION_ROW_COUNT" -eq 1
   test "$CANCEL_CONTROL_COUNT" -eq 2
   test "$RESUME_CONTROL_COUNT" -eq 2
   ```

   Many underlying commands still produce exactly one published row per kind.
   The visible snapshot—not private supervisor state—is the Cancel ID binding.

6. Inspect both progress indicators in the VM. They must be determinate bars,
   not spinners: every published preview/evaluation item has
   `totalUnitCount == 1`. The general rule is all-or-nothing over the **published
   items** in one kind: sum totals only when every item has one; one `nil` total
   makes the aggregate indeterminate. There is no numeric fraction in the row.

7. Resume from either row. Wait for the two Pause controls to replace Resume,
   then capture one static-text snapshot with both kind titles and at least two
   `Running` labels:

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Resume background work"
   script/vm_scenario_run.sh ax wait --role AXButton --help "Pause background work"
   PAUSE_CONTROL_COUNT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Pause background work" | awk 'NF { count += 1 } END { print count + 0 }')
   ACTIVITY_TEXT=$(script/vm_scenario_run.sh ax find --role AXStaticText)
   PREVIEW_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Generate previews" { count += 1 } END { print count + 0 }')
   EVALUATION_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Evaluate photos" { count += 1 } END { print count + 0 }')
   RUNNING_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Running" { count += 1 } END { print count + 0 }')
   test "$PAUSE_CONTROL_COUNT" -eq 2
   test "$PREVIEW_ROW_COUNT" -eq 1
   test "$EVALUATION_ROW_COUNT" -eq 1
   test "$RUNNING_ROW_COUNT" -ge 2
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Queue paused after current task"
   ```

   The returned Pause controls are the positive publication barrier for the
   negative notice assertions.

### 3. Cancel the finite published evaluation kind; preview continues

8. Capture one visible snapshot and preview depth at the action boundary. Then
   use the Tart VM's visible UI to click the `xmark.circle` on the **Evaluate
   photos** row. This is one explicit manual row-scoped gesture inside the VM.

   ```bash
   ACTIVITY_TEXT_AT_CANCEL=$(script/vm_scenario_run.sh ax find --role AXStaticText)
   PREVIEW_ROWS_AT_CANCEL=$(printf '%s\n' "$ACTIVITY_TEXT_AT_CANCEL" | awk '$0 == "Generate previews" { count += 1 } END { print count + 0 }')
   EVALUATION_ROWS_AT_CANCEL=$(printf '%s\n' "$ACTIVITY_TEXT_AT_CANCEL" | awk '$0 == "Evaluate photos" { count += 1 } END { print count + 0 }')
   CONTROL_TEXT_AT_CANCEL=$(script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item")
   CANCEL_CONTROLS_AT_CANCEL=$(printf '%s\n' "$CONTROL_TEXT_AT_CANCEL" | awk 'NF { count += 1 } END { print count + 0 }')
   PENDING_BEFORE_CANCEL=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
   test "$PREVIEW_ROWS_AT_CANCEL" -eq 1
   test "$EVALUATION_ROWS_AT_CANCEL" -eq 1
   test "$CANCEL_CONTROLS_AT_CANCEL" -eq 2
   test "$PENDING_BEFORE_CANCEL" -gt 0
   ```

   **Do not** substitute
   `script/vm_scenario_run.sh ax press --help "Cancel this work item"`.
   `ax_drive.sh` can only press the first of two identically helped buttons and
   cannot bind it to the adjacent title. First-match order is not evidence.

   All recognition IDs were enqueued while frozen and then published in the
   visible Evaluate row. `cancelWork(kind:)` therefore requests exactly that
   finite ID set. Do not query `work_sessions` for preview/evaluation IDs;
   those queue items are not persisted ingest sessions.

9. A dispatched evaluation does not disappear at the request. It stays running
   until its natural terminal, finalizes as `cancelled`, and retires on the next
   publication. Poll for the changed positive control set—one generic Cancel
   control—plus decreasing preview depth. Only then assert Evaluate is absent:

   ```bash
   attempt=0
   while [ "$attempt" -lt 60 ]; do
       CONTROL_TEXT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item")
       CANCEL_CONTROL_COUNT=$(printf '%s\n' "$CONTROL_TEXT" | awk 'NF { count += 1 } END { print count + 0 }')
       PENDING_AFTER_CANCEL=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
       test "$CANCEL_CONTROL_COUNT" -eq 1 && test "$PENDING_AFTER_CANCEL" -lt "$PENDING_BEFORE_CANCEL" && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$CANCEL_CONTROL_COUNT" -eq 1
   test "$PENDING_AFTER_CANCEL" -lt "$PENDING_BEFORE_CANCEL"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Generate previews"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Evaluate photos"
   ```

   The one remaining Cancel control now belongs unambiguously to Generate.
   Preview depth falling proves the sibling lane continued while evaluation
   cancellation waited for its natural terminal and next publication.

### 4. Idle worker appears only after preview drain and final publication

10. Close the popover and poll the preview queue to zero. Then wait for exact
    `Activity` to replace working, reopen it, and assert `Worker idle` and Stop:

   ```bash
   script/vm_scenario_run.sh key 'key code 53'
   attempt=0
   while [ "$attempt" -lt 240 ]; do
       PENDING_PREVIEW_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
       test "$PENDING_PREVIEW_COUNT" -eq 0 && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$PENDING_PREVIEW_COUNT" -eq 0

   attempt=0
   while [ "$attempt" -lt 12 ]; do
       script/vm_scenario_run.sh ax find --role AXButton --help "Activity" && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$attempt" -lt 12
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax wait --role AXStaticText --label "Worker idle"
   script/vm_scenario_run.sh ax find --role AXButton --help "Stop idle worker"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Generate previews"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Evaluate photos"
   ! script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item"
   ```

11. Stop the idle worker. Wait for the positive quiet replacement before
    asserting the idle row is gone:

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Stop idle worker"
   script/vm_scenario_run.sh ax wait --role AXStaticText --label "No active work"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Worker idle"
   ! script/vm_scenario_run.sh ax find --role AXButton --help "Stop idle worker"
   ```

## Expected

- Grouping fails unless a frozen multi-item workload produces exactly one
  Generate row and one Evaluate row in one published snapshot.
- Progress fails if either all-known-total row is indeterminate, or if a future
  mixed-total published kind remains determinate.
- Pause/Resume fails unless exact `Queue paused` proves the frozen state and all
  rows replace Resume with Pause together.
- Cancel fails if the action is automated by first-match order, if Evaluate is
  assumed to disappear immediately, if controls do not change two-to-one, or
  if preview depth does not continue falling.
- Idle fails if it appears before preview depth reaches zero and both active
  rows retire, or if Stop does not replace it with the quiet state.

## Cleanup

```bash
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
script/vm_scenario_run.sh shell 'rm -rf "$HOME/teststrip-vm/fixtures/activity-003-smokebig"'
```

## Sharp edges

- Non-ingest Cancel buttons intentionally share one AXHelp string and have no
  row-scoped accessibility identifier. The manual VM gesture is required until
  the product or driver exposes one.
- Automatic import reads must be off. Otherwise preview completions can enqueue
  recognition IDs after the coalesced row was published, weakening its ID bind.
- A dispatched Cancel is soft. The worker is not interrupted; its natural
  terminal finalizes the item as cancelled and frees the lane.
- `work_sessions` binds ingest history only, not every preview/evaluation item.
- Visual determinate-vs-indeterminate inspection is manual because the current
  AX driver does not print numeric `ProgressView` values.

## Run status

**Spec'd — NOT RUN (2026-08-10).** No step in this rewritten procedure was
freshly driven. It replaces the fast pre-rendered `--smoke` window, direct host
commands, stale per-item/four-row-cap expectations, transient pause text,
immediate-cancel assumptions, and false preview/evaluation `work_sessions`
queries with a frozen finite workload and positive publication barriers.

Historical evidence remains historical:

- 2026-07-13 source reconciliation established per-kind aggregation,
  queue-wide Pause/Resume, kind-scoped Cancel, and the idle-worker row.
- The old smoke attempt captured the popover but could not sustain useful job
  rows. It did not execute this procedure and is not a current pass.
- Unit tests cover aggregation and supervisor cancellation mechanics; this card
  still needs its assembled VM run.

**Task 7 note (2026-07-11)**: Cull review-queue rows remain in the Cull
sidebar. They are navigation sources, not background jobs, and are intentionally
outside this popover card.
