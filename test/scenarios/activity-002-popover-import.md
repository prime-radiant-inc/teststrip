# activity-002-popover-import: Activity exposes an ingest Cancel request and durable import receipts

**What this covers**: the Activity Center's two import lifecycles. While an
ingest is active, it appears as one `ActivityKindRow` with a Cancel request.
Once that session reaches a terminal state, it leaves the active-work section. A
completed import instead survives as a retained receipt with issue review and
Start culling actions.

Source: `Sources/TeststripApp/AppModel.swift` (`activeWorkKindRows`
`:2978-2981`, `cancelImportWork()` `:9398-9414`, cancellation persistence
`:14321-14336`, completed-import projection `:14201-14232`),
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
inside the VM. **The cancellable folder must contain byte-distinct files, not
hard links**: hard links share one inode, so the importer's content-hash dedup
collapses them to a single asset; the ingest session then drains in ~1s and no
Cancel can be driven (measured live 2026-09-14). Each cancellable file is a
full-size JPEG copy with a unique trailing byte run — ImageIO ignores bytes
after the EOI marker, so all 8000 remain decodable and distinct. Each receipt
folder has one distinct supported JPEG and one reproducible skipped file:

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
while [ "$index" -le 8000 ]; do
    cp "$source_photo" "$fixture/cancellable/frame-$index.jpg"
    printf "TR%08d" "$index" >> "$fixture/cancellable/frame-$index.jpg"
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
   script/vm_scenario_run.sh ax press --help "Activity - working"
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
   script/vm_scenario_run.sh ax press --help "Activity - working" \
     || script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Import photos"
   ! script/vm_scenario_run.sh ax find --role AXButton --help "Cancel import"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Recent Imports"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "1 file skipped"
   script/vm_scenario_run.sh ax find --role AXButton --label "Review issues"
   script/vm_scenario_run.sh ax find --role AXButton --label "Start culling"
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
   REVIEW_LINK_COUNT=$(script/vm_scenario_run.sh ax find --role AXButton --label "Review issues" | awk '$0 == "Review issues" { count += 1 } END { print count + 0 }')
   START_LINK_COUNT=$(script/vm_scenario_run.sh ax find --role AXButton --label "Start culling" | awk '$0 == "Start culling" { count += 1 } END { print count + 0 }')
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
   script/vm_scenario_run.sh ax press --role AXButton --label "Review issues"
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
    script/vm_scenario_run.sh ax press --role AXButton --label "Start culling"

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
    script/vm_scenario_run.sh ax find --label "Scope" --contains "Imported 1 photo from receipt-6 (1 file skipped) Cull Input, 1 photo · ✓ 0 · ✕ 0 · 0 left"
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

- The cancellation fixture is 8,000 byte-distinct full-size JPEG copies
  (~3.3 GB). It must be distinct files: hard links (the former fixture) share an
  inode, so dedup collapses them and the ingest session drains in ~1s
  (measured live 2026-09-14). 1,000 distinct copies still drained in ~1.1s;
  8,000 gave a ~4s window in which the ingest row, its `Running` label, and its
  Cancel control were all caught and driven. Increase the count and restart
  Part A from a fresh `launch empty` if the bound session still reaches terminal
  first — a fixture adjustment, not evidence of a paused or cancellable row.
  Do not shrink the files to widen the window: a 20,000-file tiny-JPEG fixture
  failed the import outright with `IOServiceMatchingfailed for:
  AppleM2ScalerParavirtDriver`.
- A cancelled session is persisted history but is not a completed-import
  receipt. For dispatched work, the request waits for the worker's natural
  terminal; the active row disappears on the following coalesced publication.
- The `.txt` file is a supported scanner test fixture for the
  `skippedSourceFile` path. Preview or backup failures are outside this card.
- The Cull-input scope line for the Start-culling handoff reads
  `Imported 1 photo from receipt-6 (1 file skipped) Cull Input, 1 photo · ✓ 0 ·
  ✕ 0 · 0 left` while the same frame's HUD cluster reads `0 picks, 0 rejects,
  1 left` — the two "left" values disagree for the identical 1-photo input.
  Recorded as observed 2026-09-14; the card asserts the scope line verbatim.
- **Both receipt actions render as `AXButton`, not `AXLink`.** Live-verified
  2026-09-14: `Review issues` and `Start culling` (`ActivityCenterView`'s
  `.buttonStyle(.bordered)`) both vend role `AXButton` with the label as their
  accessibility description; `--role AXLink` matches neither. `import-011`'s
  earlier `AXLink` reading does not hold on the current build. The sheet's Done
  control is an `AXButton`. The ingest kind row's Cancel control is `AXButton`
  help `Cancel import` (label/desc `Close`, the SF Symbol default — match on
  `--help`).

## Run status

**Verified — 2026-09-14, Tart VM `teststrip-e2e` (`script/vm_scenario_run.sh`;
Part A run dir `empty-1789382800`, Part B `empty-1789382877`, both `launch
empty`).** All steps PASS as driven, with fixture/role corrections below.

- Part A (live ingest Cancel): with the corrected 8,000-distinct-file fixture,
  the working popover showed the `Import photos` row + `Running` label and the
  `AXButton` help `Cancel import`; pressing it finalized the bound session as
  `cancelled` (4.1s), the status stayed `cancelled` on re-read, and both the
  `Import photos` row and the Cancel control were absent after the next
  publication. PASS.
- Part B (receipts): six imports, each persisted `1:1` counts and exactly one
  `skippedSourceFile` issue; the popover then showed `Recent Imports`, the
  `1 file skipped` detail, and 5 `Review issues` + 5 `Start culling` controls
  (receipt-1 dropped, receipt-2..6 present); pressing the newest `Review issues`
  closed the popover and opened `1 Import Issue` / `Skipped notes-6.txt`, and
  `Done` dismissed it; `Start culling` created exactly one new `culling`
  session and the window became `Teststrip – Loupe`. PASS.

Corrections applied live: (1) the cancellable fixture must be byte-distinct
files (hard links dedup to one asset and drain in ~1s); (2) the working
toolbar control is matched on `--help` alone (it vends as `AXBusyIndicator`, not
`AXButton`); (3) `Review issues`/`Start culling` are `AXButton`, not `AXLink`;
(4) the Cull-input scope line's verbatim text. No `sync` was run (VM
pre-synced; parent forbade it) — the already-synced `faces` photos and
`isolated/empty` seed were used. Part A's cancelled run was discarded by a
fresh `launch empty` for Part B.

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
