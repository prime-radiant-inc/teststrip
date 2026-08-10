# activity-002-popover-import: Activity exposes an ingest Cancel request and durable import receipts

**What this covers**: the Activity Center's two import lifecycles. While an
ingest is active, it appears as one `ActivityKindRow` with a Cancel request.
Once that session reaches a terminal state, it leaves the active-work section. A
completed import instead survives as a retained receipt with issue review and
Start culling actions.

Source: `Sources/TeststripApp/AppModel.swift` (`activeWorkKindRows`
`:2898-2905`, `cancelImportWork()` `:9010-9027`, cancellation persistence
`:13838-13853`, completed-import projection `:5444-5473`),
`Sources/TeststripApp/ActivityCenterPresentation.swift` (`ActivityKindRow`
`:70-138`, `ActivityCenterPresentation` `:142-190`),
`Sources/TeststripApp/ActivityCenterView.swift` (active rows and cancel
`:67-140`, receipts and actions `:272-322`),
`Sources/TeststripApp/ImportCompletionToastPresentation.swift`
(`ImportReceiptRow` `:90-135`), and
`Sources/TeststripApp/LibraryGridView.swift` (Activity-button help
`:445-492`, issue-review sheet `:1904-1963`, `ImportIssueReview`
`:8801-8810`).

## Pre-state

Run every UI, filesystem, and catalog operation through the Tart wrapper:

```bash
script/vm_scenario_run.sh sync empty faces
script/vm_scenario_run.sh launch empty
script/vm_scenario_run.sh ax wait-vended Teststrip
```

Create one adjustable cancellation fixture and six distinct receipt fixtures
inside the VM. The large folder uses hard links so it is cheap to grow. Each
receipt folder has one distinct supported JPEG and one reproducible skipped
file:

```bash
script/vm_scenario_run.sh shell '
set -eu
fixture="$HOME/teststrip-vm/fixtures/activity-002"
rm -rf "$fixture"
mkdir -p "$fixture/cancellable"
set -- "$HOME"/teststrip-vm/sample-data/photos/faces/*.jpg
test "$#" -ge 7

source_photo=$1
index=1
while [ "$index" -le 5000 ]; do
    ln "$source_photo" "$fixture/cancellable/frame-$index.jpg"
    index=$((index + 1))
done

shift
receipt=1
while [ "$receipt" -le 6 ]; do
    mkdir -p "$fixture/receipt-$receipt"
    ln "$1" "$fixture/receipt-$receipt/photo-$receipt.jpg"
    printf "%s\n" "not a photo" > "$fixture/receipt-$receipt/notes-$receipt.txt"
    shift
    receipt=$((receipt + 1))
done
'
```

The empty catalog makes every receipt count attributable to this card. The
`.txt` files follow the importer's real `unrecognizedFile` path and persist as
`skippedSourceFile` issues; no synthetic failure row is inserted.

## Steps

### Part A: bind, inspect, and request cancellation for one live ingest

1. Record the ingest high-water mark, submit the large folder, and bind this
   action to the one new persisted session by `rowid`:

   ```bash
   BEFORE_INGEST_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='ingest';")
   script/vm_scenario_run.sh shell '$HOME/teststrip-vm/script/submit_import_path.sh Teststrip $HOME/teststrip-vm/fixtures/activity-002/cancellable'

   attempt=0
   INGEST_SESSION_ID=
   while [ "$attempt" -lt 40 ]; do
       INGEST_SESSION_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='ingest' AND rowid > $BEFORE_INGEST_ROWID ORDER BY rowid LIMIT 1;")
       test -n "$INGEST_SESSION_ID" && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test -n "$INGEST_SESSION_ID"
   test "$(script/vm_scenario_run.sh sql empty "SELECT status FROM work_sessions WHERE id='$INGEST_SESSION_ID';")" = running
   ```

   If the exact session is already terminal, grow `5000` and restart Part A
   from a fresh `launch empty`. The fixture size is a test parameter. Do not
   claim a pause or weaken the running-state assertion.

2. Open the working Activity popover. Assert the real active row and action:

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - working"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Activity"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Import photos"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Running"
   script/vm_scenario_run.sh ax find --role AXButton --help "Cancel import"
   ```

3. Press Cancel and poll the exact session to its persisted terminal state.
   A dispatched import remains in flight until its natural worker terminal; the
   supervisor then finalizes it as `cancelled`. After SQL observes that terminal,
   wait through the coupled Activity/progress publication cadence and re-query
   before asserting that the active row retired:

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Cancel import"
   attempt=0
   INGEST_STATUS=
   while [ "$attempt" -lt 40 ]; do
       INGEST_STATUS=$(script/vm_scenario_run.sh sql empty "SELECT status FROM work_sessions WHERE id='$INGEST_SESSION_ID';")
       test "$INGEST_STATUS" = cancelled && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$INGEST_STATUS" = cancelled
   sleep 1
   test "$(script/vm_scenario_run.sh sql empty "SELECT status FROM work_sessions WHERE id='$INGEST_SESSION_ID';")" = cancelled
   ! script/vm_scenario_run.sh ax find --role AXButton --help "Cancel import"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Import photos"
   ```

   The terminal row is deliberately absent. Worker-backed Cancel is a request
   plus terminal relabel, not prompt interruption: an in-flight command may keep
   its lane occupied until its natural terminal. Terminal persistence is
   authoritative; the next coalesced publication retires the row and must not
   replay prior running progress over `cancelled`. A visible `Cancelled` row is
   not part of this contract.

4. Close the popover before starting another import:

   ```bash
   script/vm_scenario_run.sh key 'key code 53'
   ```

### Part B: complete six imports and prove receipt behavior

5. Import `receipt-1`, bind it by `rowid`, and prove its exact terminal
   counts and persisted issue:

   ```bash
   RECEIPT_BASE_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='ingest';")
   BEFORE_RECEIPT_ROWID=$RECEIPT_BASE_ROWID
   script/vm_scenario_run.sh shell '$HOME/teststrip-vm/script/submit_import_path.sh Teststrip $HOME/teststrip-vm/fixtures/activity-002/receipt-1'

   attempt=0
   FIRST_RECEIPT_ID=
   while [ "$attempt" -lt 60 ]; do
       FIRST_RECEIPT_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='ingest' AND rowid > $BEFORE_RECEIPT_ROWID AND status='completed' ORDER BY rowid LIMIT 1;")
       test -n "$FIRST_RECEIPT_ID" && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test -n "$FIRST_RECEIPT_ID"
   test "$(script/vm_scenario_run.sh sql empty "SELECT completed_unit_count || ':' || total_unit_count FROM work_sessions WHERE id='$FIRST_RECEIPT_ID';")" = 1:1
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions, json_each(work_sessions.issues_json) WHERE work_sessions.id='$FIRST_RECEIPT_ID' AND json_extract(value,'\$.kind')='skippedSourceFile';")" -eq 1
   ```

6. Open the popover in whichever non-problem toolbar state is current while
   preview work drains. The terminal ingest row/action must be absent, while
   its receipt must expose all current actions:

   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity - working" \
     || script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Import photos"
   ! script/vm_scenario_run.sh ax find --role AXButton --help "Cancel import"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Recent Imports"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "1 file skipped"
   script/vm_scenario_run.sh ax find --role AXLink --label "Review issues"
   script/vm_scenario_run.sh ax find --role AXLink --label "Start culling"
   script/vm_scenario_run.sh key 'key code 53'
   ```

7. Import the other five distinct folders. For each action, bind the one new
   session and verify one catalogued file plus one persisted skipped-file
   issue:

   ```bash
   for receipt in 2 3 4 5 6; do
       BEFORE_RECEIPT_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='ingest';")
       script/vm_scenario_run.sh shell "/Users/admin/teststrip-vm/script/submit_import_path.sh Teststrip /Users/admin/teststrip-vm/fixtures/activity-002/receipt-$receipt"

       attempt=0
       RECEIPT_SESSION_ID=
       while [ "$attempt" -lt 60 ]; do
           RECEIPT_SESSION_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='ingest' AND rowid > $BEFORE_RECEIPT_ROWID AND status='completed' ORDER BY rowid LIMIT 1;")
           test -n "$RECEIPT_SESSION_ID" && break
           attempt=$((attempt + 1))
           sleep 1
       done
       test -n "$RECEIPT_SESSION_ID"
       test "$(script/vm_scenario_run.sh sql empty "SELECT completed_unit_count || ':' || total_unit_count FROM work_sessions WHERE id='$RECEIPT_SESSION_ID';")" = 1:1
       test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions, json_each(work_sessions.issues_json) WHERE work_sessions.id='$RECEIPT_SESSION_ID' AND json_extract(value,'\$.kind')='skippedSourceFile';")" -eq 1
   done
   test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind='ingest' AND status='completed' AND rowid > $RECEIPT_BASE_ROWID;")" -eq 6
   ```

8. Before starting any culling session, wait conditionally for active work to
   drain and establish a no-problem catalog. Then prove the receipt-only,
   no-problem toolbar help and the five-newest receipt cap:

   ```bash
   attempt=0
   while [ "$attempt" -lt 180 ]; do
       ACTIVE_NON_CULL=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind!='culling' AND status IN ('queued','running','paused');")
       UNAVAILABLE=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets WHERE availability!='online';")
       CONFLICTS=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM metadata_sync_state WHERE status='conflict';")
       PROVIDER_FAILURES=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(DISTINCT asset_id) FROM evaluation_failures;")
       test "$ACTIVE_NON_CULL" -eq 0 && test "$UNAVAILABLE" -eq 0 && test "$CONFLICTS" -eq 0 && test "$PROVIDER_FAILURES" -eq 0 && break
       attempt=$((attempt + 1))
       sleep 1
   done
   test "$ACTIVE_NON_CULL" -eq 0
   test "$UNAVAILABLE" -eq 0
   test "$CONFLICTS" -eq 0
   test "$PROVIDER_FAILURES" -eq 0

   script/vm_scenario_run.sh ax find --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   REVIEW_LINK_COUNT=$(script/vm_scenario_run.sh ax find --role AXLink --label "Review issues" | awk '$0 == "Review issues" { count += 1 } END { print count + 0 }')
   START_LINK_COUNT=$(script/vm_scenario_run.sh ax find --role AXLink --label "Start culling" | awk '$0 == "Start culling" { count += 1 } END { print count + 0 }')
   test "$REVIEW_LINK_COUNT" -eq 5
   test "$START_LINK_COUNT" -eq 5
   ! script/vm_scenario_run.sh ax find --role AXStaticText --contains "receipt-1"
   for receipt in 2 3 4 5 6; do
       script/vm_scenario_run.sh ax find --role AXStaticText --contains "receipt-$receipt"
   done
   ```

   This badge assertion precedes Start culling so a newly active culling
   session cannot contaminate the result.

9. Drive the newest retained receipt's issue link. It closes the popover and
   opens the exact one-issue sheet. Dismiss it through the exact Done button:

   ```bash
   script/vm_scenario_run.sh ax press --role AXLink --label "Review issues"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Recent Imports"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "1 Import Issue"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Skipped notes-6.txt"
   script/vm_scenario_run.sh ax press --role AXButton --label "Done"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "1 Import Issue"
   ```

10. Reopen the closed popover, bind the next culling row by `rowid`, press the
    exact receipt link, and prove both a genuinely new culling session and the
    Cull lens:

    ```bash
    BEFORE_CULL_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='culling';")
    script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
    script/vm_scenario_run.sh ax press --role AXLink --label "Start culling"

    attempt=0
    NEW_CULL_ID=
    while [ "$attempt" -lt 40 ]; do
        NEW_CULL_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='culling' AND rowid > $BEFORE_CULL_ROWID ORDER BY rowid LIMIT 1;")
        test -n "$NEW_CULL_ID" && break
        attempt=$((attempt + 1))
        sleep 1
    done
    test -n "$NEW_CULL_ID"
    test "$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind='culling' AND rowid > $BEFORE_CULL_ROWID;")" -eq 1
    script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – Loupe"
    script/vm_scenario_run.sh ax find --label "Scope" --contains "✓ 0 · ✕ 0 · 1 left"
    ```

## Expected

- Part A fails if the bound session cannot be observed in `running`, the
  shared import row lacks a Cancel request, the exact session does not persist
  as `cancelled`, a later progress publication revives it, or its active
  row/action remains after the next publication.
- Part B fails if any receipt session does not persist `1:1` counts and one
  `skippedSourceFile`, if a terminal `Import photos` active row remains, or if
  the receipt lacks Recent Imports, `1 file skipped`, Review issues, or Start
  culling.
- Retention fails unless SQL proves six completed imports while the popover
  keeps exactly five newest action pairs and drops `receipt-1`.
- The badge fails unless the toolbar help is exactly `Activity` with receipts
  present and the catalog precondition quiet.
- Receipt navigation fails unless Review issues opens `1 Import Issue` for
  `notes-6.txt`, Done dismisses it, and Start culling creates one new session
  and lands in Cull.

## Cleanup

```bash
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
script/vm_scenario_run.sh shell '
fixture="$HOME/teststrip-vm/fixtures/activity-002"
rm -rf "$fixture"
'
```

The catalog is a disposable `launch empty` run. Cleanup removes only the
fixture this card owns.

## Sharp edges

- The cancellation fixture starts at 5,000 hard links because the import row
  can drain before an AX walk. Increase that number and restart Part A if the
  bound session reaches terminal first. That is a fixture adjustment, not
  evidence of a paused or cancellable row.
- A cancelled session is persisted history but is not a completed-import
  receipt. For dispatched work, the request waits for the worker's natural
  terminal; the active row disappears on the following coalesced publication.
- The `.txt` file is a supported scanner test fixture for the
  `skippedSourceFile` path. Preview or backup failures are outside this card.
- `Start culling` was live-proven as `AXLink` by `import-011`. `Review issues`
  uses the same SwiftUI `.buttonStyle(.link)`, so this procedure specifies
  `AXLink`, but its rendered role and action remain pending this card's fresh
  VM run. The sheet's Done control is source-backed as an `AXButton`.

## Run status

**Spec'd — NOT RUN (2026-08-10).** This repair
replaces two non-executable premises: a completed or cancelled ingest is not
an active kind row, and unsupported `.txt` files are a proven import issue
fixture. The procedure now binds every action to a new persisted row and
separates cancellation, receipt retention, issue review, badge, and culling
proofs. No Activity UI leg has ever been driven; no VM leg was driven during
this docs repair.

Historical evidence is preserved:

- 2026-07-10: the smoke catalog schema and idle baseline were checked
  headlessly. No Activity UI leg ran.
- 2026-07-13: the per-kind-lanes source reconciliation identified the shared
  `.ingest` row and Cancel control. It remained AX-unrun.
- 2026-08-09: the unified-shell reconciliation added durable receipt coverage.
  It was not driven.
- 2026-08-10: `import-011` separately proved the receipt's Start culling role
  as `AXLink`. That is cross-card evidence only; `activity-002` remains
  unverified until this repaired procedure runs in the VM.
