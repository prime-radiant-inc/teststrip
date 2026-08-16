# activity-007-per-kind-lanes: preview and evaluation lanes overlap, publish separately, and cancel independently

**What this covers**: preview generation (`.previewGeneration`) and evaluation
(`.recognition`) run in separate worker lanes. A controlled finite workload must
produce one published `Generate previews` row and one published `Evaluate
photos` row at the same time, with catalog output from both moving in the same
observation window. A Cancel request for the published evaluation kind must
leave preview generation running. No machine result may create a person
assignment or sidecar without an explicit user confirmation.

The Activity rows are coalesced view snapshots. Two visible rows alone prove
grouping, not concurrent execution; the paired catalog deltas below are the
execution proof. Conversely, catalog deltas alone do not prove that the view
published both kinds; the exact row counts are required too.

Source: `Sources/TeststripApp/AppCatalog.swift` (per-kind running limits and
concurrent dispatch capacity),
`Sources/TeststripApp/ActivityCenterPresentation.swift` (one aggregate row per
kind and published-total rule), `Sources/TeststripApp/ActivityCenterView.swift`
(bars and controls), `Sources/TeststripApp/AppModel.swift` (published kind rows,
finite Evaluate Matches scheduling, and kind-scoped Cancel), and
`Sources/TeststripCore/Worker/WorkerSupervisor.swift` (soft cancellation and
sibling-lane preservation).

## Pre-state

Run the assembled app only in Tart, and route every scripted action through the
wrapper. The determinate-bar inspection and row-scoped Cancel below are
explicit visible gestures inside Tart because the current AX driver cannot
bind them; neither may be replaced by a host command. Import copies of the 130
public `smokebig` originals into a fresh `empty` catalog. The pre-populated
`smokebig` catalog has cached previews and is not a valid fixture for this card.

```bash
script/vm_scenario_run.sh sync empty smokebig
script/vm_scenario_run.sh launch empty
script/vm_scenario_run.sh ax wait-vended Teststrip
test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets;")" -eq 0
test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")" -eq 0
test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM evaluation_signals;")" -eq 0

script/vm_scenario_run.sh shell '
set -eu
fixture="$HOME/teststrip-vm/fixtures/activity-007-smokebig"
record="$HOME/teststrip-vm/fixtures/activity-007-smokebig.sha256"
rm -rf "$fixture"
rm -f "$record"
mkdir -p "$fixture"
set -- "$HOME"/teststrip-vm/isolated/smokebig/Teststrip/SmokeOriginals/*.jpg
test "$#" -eq 130
for source in "$@"; do
    cp "$source" "$fixture/$(basename "$source")"
done
test "$(find "$fixture" -type f -name "*.jpg" | wc -l | tr -d " ")" -eq 130
test "$(find "$fixture" -type f -name "*.xmp" | wc -l | tr -d " ")" -eq 0
find "$fixture" -type f -name "*.jpg" -exec shasum {} \; | sort > "$record"
test "$(wc -l < "$record" | tr -d " ")" -eq 130
'
```

The checksum record is outside the imported folder, so it cannot become a
skipped import file. All filesystem generation and later comparison remain
inside the VM wrapper.

## Steps

### 1. Import without automatic evaluation and establish a durable preview load

1. Record the ingest frontier. Drive the real Import Path sheets with wrapper
   AX, turn the default-on automatic-read checkbox **off**, and start the exact
   130-photo import:

   ```bash
   BEFORE_INGEST_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='ingest';")
   script/vm_scenario_run.sh ax press --role AXButton --label "Import Path"
   script/vm_scenario_run.sh ax wait --role AXTextField --label "Folder path"
   script/vm_scenario_run.sh ax type --role AXTextField --label "Folder path" --text "/Users/admin/teststrip-vm/fixtures/activity-007-smokebig"
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

5. Capture all static text in one AX traversal and both generic control sets in
   one traversal each. This avoids straddling two coalesced publications:

   ```bash
   ACTIVITY_TEXT=$(script/vm_scenario_run.sh ax find --role AXStaticText)
   PREVIEW_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Generate previews" { count += 1 } END { print count + 0 }')
   EVALUATION_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Evaluate photos" { count += 1 } END { print count + 0 }')
   CONTROL_TEXT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item")
   CANCEL_CONTROL_COUNT=$(printf '%s\n' "$CONTROL_TEXT" | awk 'NF { count += 1 } END { print count + 0 }')
   RESUME_TEXT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Resume background work")
   RESUME_CONTROL_COUNT=$(printf '%s\n' "$RESUME_TEXT" | awk 'NF { count += 1 } END { print count + 0 }')
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
   PAUSE_TEXT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Pause background work")
   PAUSE_CONTROL_COUNT=$(printf '%s\n' "$PAUSE_TEXT" | awk 'NF { count += 1 } END { print count + 0 }')
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

### 3. Both lanes advance inside the same published-row window

8. Record paired baselines, then poll until pending previews fall and
   provider-filtered evaluation coverage rises while one snapshot still
   contains exactly one row of each kind:

   ```bash
   PENDING_BEFORE=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
   EVALUATED_ASSETS_BEFORE=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(DISTINCT asset_id) FROM evaluation_signals WHERE provider='local-image-metrics';")
   test "$PENDING_BEFORE" -gt 1

   attempt=0
   while [ "$attempt" -lt 60 ]; do
       PENDING_AFTER=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
       EVALUATED_ASSETS_AFTER=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(DISTINCT asset_id) FROM evaluation_signals WHERE provider='local-image-metrics';")
       ACTIVITY_TEXT=$(script/vm_scenario_run.sh ax find --role AXStaticText)
       PREVIEW_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Generate previews" { count += 1 } END { print count + 0 }')
       EVALUATION_ROW_COUNT=$(printf '%s\n' "$ACTIVITY_TEXT" | awk '$0 == "Evaluate photos" { count += 1 } END { print count + 0 }')
       test "$PENDING_AFTER" -lt "$PENDING_BEFORE" && test "$EVALUATED_ASSETS_AFTER" -gt "$EVALUATED_ASSETS_BEFORE" && test "$PREVIEW_ROW_COUNT" -eq 1 && test "$EVALUATION_ROW_COUNT" -eq 1 && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$PENDING_AFTER" -lt "$PENDING_BEFORE"
   test "$EVALUATED_ASSETS_AFTER" -gt "$EVALUATED_ASSETS_BEFORE"
   test "$PREVIEW_ROW_COUNT" -eq 1
   test "$EVALUATION_ROW_COUNT" -eq 1
   ```

   The row counts come from one AXStaticText dump per sample. The paired deltas
   are condition-based overlap evidence, not a host launch-window sample.

### 4. Cancel the finite published evaluation kind; preview continues

9. Capture one visible snapshot and catalog values at the action boundary.
   Then use the Tart VM's visible UI to click the `xmark.circle` on the
   **Evaluate photos** row. This is one explicit manual row-scoped gesture
   inside the VM.

   ```bash
   ACTIVITY_TEXT_AT_CANCEL=$(script/vm_scenario_run.sh ax find --role AXStaticText)
   PREVIEW_ROWS_AT_CANCEL=$(printf '%s\n' "$ACTIVITY_TEXT_AT_CANCEL" | awk '$0 == "Generate previews" { count += 1 } END { print count + 0 }')
   EVALUATION_ROWS_AT_CANCEL=$(printf '%s\n' "$ACTIVITY_TEXT_AT_CANCEL" | awk '$0 == "Evaluate photos" { count += 1 } END { print count + 0 }')
   CONTROL_TEXT_AT_CANCEL=$(script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item")
   CANCEL_CONTROLS_AT_CANCEL=$(printf '%s\n' "$CONTROL_TEXT_AT_CANCEL" | awk 'NF { count += 1 } END { print count + 0 }')
   PENDING_AT_CANCEL=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
   EVALUATED_ASSETS_AT_CANCEL=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(DISTINCT asset_id) FROM evaluation_signals WHERE provider='local-image-metrics';")
   test "$PREVIEW_ROWS_AT_CANCEL" -eq 1
   test "$EVALUATION_ROWS_AT_CANCEL" -eq 1
   test "$CANCEL_CONTROLS_AT_CANCEL" -eq 2
   test "$PENDING_AT_CANCEL" -gt 0
   test "$EVALUATED_ASSETS_AT_CANCEL" -gt 0
   ```

   **Do not** substitute
   `script/vm_scenario_run.sh ax press --help "Cancel this work item"`.
   `ax_drive.sh` can only press the first of two identically helped buttons and
   cannot bind it to the adjacent title. First-match order is not evidence.

   All recognition IDs were enqueued while frozen and published in the visible
   Evaluate row. `cancelWork(kind:)` therefore requests that finite represented
   set. Do not query `work_sessions` for preview/evaluation IDs; those queue
   items are not persisted ingest sessions.

10. A dispatched evaluation does not disappear at the request. It stays
    running until its natural completed/failed terminal, finalizes as
    `cancelled`, and retires on the next publication. Poll for the changed
    positive control set—one generic Cancel control—plus decreasing preview
    depth. Only then assert Evaluate is absent:

    ```bash
    attempt=0
    while [ "$attempt" -lt 60 ]; do
        CONTROL_TEXT=$(script/vm_scenario_run.sh ax find --role AXButton --help "Cancel this work item")
        CANCEL_CONTROL_COUNT=$(printf '%s\n' "$CONTROL_TEXT" | awk 'NF { count += 1 } END { print count + 0 }')
        PENDING_AFTER_CANCEL=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")
        test "$CANCEL_CONTROL_COUNT" -eq 1 && test "$PENDING_AFTER_CANCEL" -lt "$PENDING_AT_CANCEL" && break
        attempt=$((attempt + 1))
        sleep 1
    done
    test "$CANCEL_CONTROL_COUNT" -eq 1
    test "$PENDING_AFTER_CANCEL" -lt "$PENDING_AT_CANCEL"
    script/vm_scenario_run.sh ax find --role AXStaticText --label "Generate previews"
    ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Evaluate photos"
    ```

    The one remaining Cancel control now belongs unambiguously to Generate.
    Preview depth falling proves the sibling lane continued while evaluation
    cancellation waited for its natural terminal and next publication. The
    dispatched evaluation may write one final signal before that terminal; do
    not assert a flat signal count after the click.

### 5. Final publication exposes idle worker and safe durable output

11. Close the popover and poll the preview queue to zero. Then wait for exact
    `Activity` to replace working, reopen it, and require the postpublication
    idle row:

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
    ```

12. Assert durable output and the confirm-before-write invariant:

    ```bash
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets;")" -eq 130
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM preview_generation_queue;")" -eq 0
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(DISTINCT asset_id) FROM evaluation_signals WHERE provider='local-image-metrics';")" -gt 0
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM evaluation_failures;")" -eq 0
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM people;")" -eq 0
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM person_assets;")" -eq 0

    script/vm_scenario_run.sh shell '
    set -eu
    fixture="$HOME/teststrip-vm/fixtures/activity-007-smokebig"
    record="$HOME/teststrip-vm/fixtures/activity-007-smokebig.sha256"
    after=$(mktemp)
    find "$fixture" -type f -name "*.jpg" -exec shasum {} \; | sort > "$after"
    diff "$record" "$after"
    test "$(find "$fixture" -type f -name "*.xmp" | wc -l | tr -d " ")" -eq 0
    rm -f "$after"
    '
    ```

## Expected

- Publication fails unless exactly one Generate row and one Evaluate row are
  visible together, each determinate for this all-known-total snapshot.
- Concurrency fails unless pending previews decrease and provider-filtered
  evaluation coverage increases while one snapshot still contains both rows.
- Cancel fails if it is automated by first-match order, if Evaluate is expected
  to vanish before its natural terminal and next publication, if controls do
  not change two-to-one, or if preview depth does not continue falling.
- Idle fails unless exact `Activity` and `Worker idle` appear after preview
  backlog reaches zero and both active rows retire.
- Safety fails if no evaluation output lands, any evaluation failure or person
  assignment appears, any sidecar appears, or an original checksum changes.

## Cleanup

```bash
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
script/vm_scenario_run.sh shell '
rm -rf "$HOME/teststrip-vm/fixtures/activity-007-smokebig"
rm -f "$HOME/teststrip-vm/fixtures/activity-007-smokebig.sha256"
'
```

The fresh `empty` run is disposable. Do not delete or mutate the synced
`isolated/smokebig` seed originals.

## Sharp edges

- `ax_drive.sh` cannot associate the shared non-ingest Cancel AXHelp with a
  sibling row title. The visible manual gesture is intentional and must be
  reported as such in run evidence.
- Automatic import reads must be off. Otherwise preview completions can enqueue
  recognition IDs after the coalesced row was published, weakening its ID bind.
- The determinate rule applies to items in the published kind snapshot, not
  events waiting in the supervisor queue. A later nil-total item makes the next
  published aggregate indeterminate.
- A dispatched Cancel is soft. It does not interrupt the worker command, kill
  the process, or free the lane until the worker's natural terminal.
- `evaluation_signals` has multiple rows per asset/provider/signal kind. Use
  provider-filtered `COUNT(DISTINCT asset_id)` for evaluation motion/coverage.
- Synthetic smokebig JPEGs have no starting sidecars. That makes zero `.xmp`
  files plus stable original checksums the direct confirm-before-write proof.

## Run status

**Spec'd — NOT RUN (2026-08-10).** This 130-original, fresh-`empty`,
publication-barrier procedure has not been driven. It replaces the old host
`jesse-pictures` dependency, fixed-delay sampling, direct host commands,
automatic import evaluation, immediate-row-removal assumptions, and unsupported
preview/evaluation `work_sessions` assertions.

Historical dated partial evidence is preserved, not promoted:

- **2026-07-13 Tart VM partial**: a fresh smoke launch plus typed-path import of
  the synced 11-photo `faces` fixture produced 35 preview directories (24 smoke
  + 11 imported), 145 `evaluation_signals` covering all 11 imported assets, 11
  `face_observations`, and zero `people`/`person_assets` rows.
- That run did **not** catch both Activity rows advancing in one sampled instant;
  the 11-photo pipeline drained in roughly 1–2 seconds through SSH latency.
- Per-kind Cancel was **not run**. The lane drained before the gesture.
- `jesse-pictures` could not be synced because its RAW corpus filled the VM
  disk. This rewrite uses the already-supported 130 synthetic JPEG originals
  instead.
- The same dated run found and fixed apostrophes that broke the single-quoted
  Swift program in `submit_import_path.sh`; that harness repair remains valid.

The headless lane-overlap verifier and unit tests remain supporting evidence for
worker mechanics, not a substitute for this assembled Activity UI run.
