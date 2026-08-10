# import-011-completion-toast-and-import-rows: The completion toast, its bell receipt, and the sidebar's import rows

**What this covers**: the unified-shell push
(`docs/superpowers/specs/2026-08-07-unified-shell-design.md`) replaces the
old post-import banner's headline/four-tile/nine-action panel with one thin
toast that fades after ~10s and docks into the Activity Center bell as a
durable receipt, plus a sidebar Imports section whose rows disclose
per-import children and expose a context menu for re-running work over that
import. No unit test can reach any of this — the repo has no SwiftUI
view-inspection library. This card is the **only gate** on: the toast's
content/dismissal, the "no banner chrome" negative, the toast's relaunch and
same-session non-resurrection, the retained receipt's issue-review and
Start-culling bindings, the import row's children and their counts,
zero-count-child omission, the skipped-files child opening the issue-review
sheet instead of an (empty) grid, the row's context menu, and culling an older
(not just the newest) import.

Source: `Sources/TeststripApp/ImportCompletionToastPresentation.swift`
(`ImportCompletionToastPresentation.toast(for:isCurrentSessionActivity:
isImporting:)` `:40-58`, `headline(for:isExistingOnly:)` `:71-84`,
`ImportReceiptRow` `:90-135`), `Sources/TeststripApp/LibraryGridView.swift`
(toast overlay + `.task(id:)` re-show guard `:247-260`, `importCompletionToast`
view `:771-824`, `dismissToast`/`showToastThenFade` `:826-844`),
`Sources/TeststripApp/ActivityCenterView.swift` (`receiptsSection` `:272-308`,
`reviewIssues` `:310-312`, `startCulling` `:315-322`),
`Sources/TeststripApp/UnifiedSidebarPresentation.swift` (`ImportSidebarSummary`
`:14-51`, `ImportChildCounts` `:61-87`, `importSectionRows`/`runningImportRow`/
`childRows` `:248-323`), `Sources/TeststripApp/LibrarySource.swift`
(`ImportChildKind` `:5-39`), `Sources/TeststripApp/AppModel.swift`
(`isCurrentSessionActivity` `:13888-13894`, `applyImportChild` `:4939-4983`,
`requestImportIssueReview` `:2543-2546`, `sidebarContextActions(for:)`
`:5161-5233`, with the work-session star toggle
at `:5202-5207` and import verbs at `:5212-5227`, `beginStackCulling`
`:5019-5041`, `startCullingImport` `:5011-5017`, `cullingInputSetID`
`:13135-13159`), `Sources/TeststripApp/LibraryGridView.swift`
(`ImportIssueReview` `:8801-8810`, `importIssueReviewSheet` `:1904-1955`,
`importIssueTitle` `:1957-1962`, `presentRequestedImportIssueReview`
`:3117-3126`),
`Sources/TeststripCore/Ingest/FolderScanner.swift` (`.unrecognizedFile` skip
reason `:90-98`), `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
(`work_sessions` schema `:94-110`, `asset_sets` schema `:53-61`).

**A correction to the plan, from Jesse's ruling recorded in the spec
(`ImportSidebarSummary`'s doc comment, `UnifiedSidebarPresentation.swift:
22-26`)**: do **not** assert any preview-generation progress on the import
row. The row shows nothing while previews drain — no in-flight child, no
inline count — because preview generation is background work the Activity
Center already surfaces, and sidebar sources mean "sets of photos," not
progress meters. `ImportChildKind` has exactly five cases — `.stacks`,
`.skippedFiles`, `.previewFailed`, `.likelyIssues`, `.facesFound`
(`LibrarySource.swift:5-39`) — and none of them is a preview counter; the
*in-flight* import row (`runningImportRow`, `UnifiedSidebarPresentation.swift:
289-299`) is a separate, non-disclosing, non-selectable row that exists only
while `runningImport` is non-nil, and is replaced by the ordinary completed
row (with its five possible children) the moment the ingest finishes. Do not
write a step asserting a progress child appears — that would pin behaviour
this push deliberately does not have.

## Pre-state
```bash
script/vm_scenario_run.sh sync empty faces
script/vm_scenario_run.sh launch empty
script/vm_scenario_run.sh ax wait-vended Teststrip
```
`empty` is the unseeded catalog (per `test/scenarios/README.md`) — the right
baseline here, since every count in this card must be attributable to imports
this card performs, not `smoke`'s pre-seeded photos. `sync` is the only
host-side build/seed step; every launch, AX action, keystroke, shell action,
and SQL query below goes through `script/vm_scenario_run.sh` into the Tart VM.

Create two fixture folders in the VM from six supported JPEGs shipped by the
`faces` sync. CARD1 has four distinct images; CARD2 contains byte-identical
copies of those four plus two genuinely new images:
```bash
script/vm_scenario_run.sh shell '
set -eu
fixture=/Users/admin/teststrip-vm/fixtures/import-011
rm -rf "$fixture"
mkdir -p "$fixture/card1" "$fixture/card2"
set -- /Users/admin/teststrip-vm/sample-data/photos/faces/*.jpg
test "$#" -ge 6
cp "$1" "$fixture/card1/shared-1.jpg"
cp "$2" "$fixture/card1/shared-2.jpg"
cp "$3" "$fixture/card1/shared-3.jpg"
cp "$4" "$fixture/card1/shared-4.jpg"
cp "$fixture/card1/shared-1.jpg" "$fixture/card2/shared-1.jpg"
cp "$fixture/card1/shared-2.jpg" "$fixture/card2/shared-2.jpg"
cp "$fixture/card1/shared-3.jpg" "$fixture/card2/shared-3.jpg"
cp "$fixture/card1/shared-4.jpg" "$fixture/card2/shared-4.jpg"
cp "$5" "$fixture/card2/card2-only-1.jpg"
cp "$6" "$fixture/card2/card2-only-2.jpg"
printf "%s\n" "not a photo" > "$fixture/card1/notes.txt"
printf "%s\n" "not a photo either" > "$fixture/card1/readme.md"
'
```
A skipped-file fixture — one real, producible skip, not a placeholder. Any
file extension outside the supported image set and outside
`FolderScanner.videoExtensions` reports `.unrecognizedFile`
(`FolderScanner.swift:90-98`), which the importer surfaces as a
`skippedSourceFile` issue with message "file type not supported"
(`Sources/TeststripCore/Ingest/LibraryImportService.swift:466-473`
— not `Sources/TeststripApp/`, per the surrounding citations' path; verified
against source). The fixture command above drops two into CARD1 before the
first import. This makes CARD1's first import produce exactly 2 skipped files
(unlike
`activity-002-popover-import.md`'s still-open gap, which is about
preview/backup *failures*, a different and not-yet-producible fixture — this
card only needs the importer's own file-type filter, which is trivially
reproducible).

## Steps

### Part A — the toast, on a fresh import
1. Import CARD1 through the typed-path sheet, using
   `test/scenarios/README.md`'s recommended driver for the multi-field Import
   Path sheet. Wait for completion.
   ```bash
   script/vm_scenario_run.sh shell '$HOME/teststrip-vm/script/submit_import_path.sh Teststrip /Users/admin/teststrip-vm/fixtures/import-011/card1'
   ```
2. On completion, assert the toast:
   ```bash
   script/vm_scenario_run.sh ax wait --contains "Import complete"   # accessibilityLabel on the toast container
   script/vm_scenario_run.sh ax find --role AXButton --label "Start culling"
   script/vm_scenario_run.sh ax find --contains "2 files skipped"
   ```
   (`ImportCompletionToastPresentation.toast`'s `warningText`, `:52-54`: the
   plural branch fires because CARD1 has exactly 2 skipped files.)
3. Assert **no banner chrome exists** anywhere on the canvas — the deleted
   nine-action panel and its headline (neither string appears anywhere in
   current `Sources/`, confirming both really were deleted rather than
   renamed):
   ```bash
   ! script/vm_scenario_run.sh ax find --contains "Review imported frames"
   ! script/vm_scenario_run.sh ax find --contains "Cull stacks"
   ```
   The second check is a **canvas** absence only — no context menu is open
   at this point in the flow, so it cannot collide with the identical-text
   `Cull stacks` sidebar **context-menu item** (`AppModel.swift:5212-5217`,
   exercised in Step 10) that legitimately exists but only renders inside an
   open `AXMenu`, never as loose canvas text.
4. Let ~10s elapse (`ImportCompletionToastPresentation.visibleDuration`,
   `:11`). Assert the toast is gone:
   ```bash
   ! script/vm_scenario_run.sh ax find --contains "Import complete"
   ```
   Open the bell (Activity Center) and assert its popover holds CARD1's
   retained `"Recent Imports"` receipt (`ActivityCenterView.swift:272-308`)
   with the same counts and both link-style actions. Drive `Review issues`
   first: it must close the popover, route this receipt's session into the
   existing issue-review sheet, show the exact two CARD1 issues, and dismiss
   through the sheet's exact `Done` action (`reviewIssues`,
   `ActivityCenterView.swift:310-312`; `importIssueReviewSheet`,
   `LibraryGridView.swift:1904-1955`; `importIssueTitle`, `:1957-1962`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Recent Imports"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "2 files skipped"
   script/vm_scenario_run.sh ax find --role AXLink --label "Review issues"
   script/vm_scenario_run.sh ax find --role AXLink --label "Start culling"
   script/vm_scenario_run.sh ax press --role AXLink --label "Review issues"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Recent Imports"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "2 Import Issues"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Skipped notes.txt"
   script/vm_scenario_run.sh ax find --role AXStaticText --label "Skipped readme.md"
   script/vm_scenario_run.sh ax press --role AXButton --label "Done"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "2 Import Issues"
   ```
   Now bind `Start culling` to one genuinely new post-action culling row. The
   action must close the reopened popover, land in the Cull lens on the new
   `work-input-<session>` snapshot source, and give that exact run all four
   CARD1 assets and nothing else (`startCullingImport`,
   `AppModel.swift:5011-5017`; `beginCullingSession`, `:5806-5859`;
   `cullingInputSetID`, `:13135-13159`; `applyAssetSet`, `:5389-5410`;
   `scopeLineBar`, `LibraryGridView.swift:748-768`). Return to Grid afterward
   so the same-session and relaunch probes can continue:
   ```bash
   BEFORE_RECEIPT_CULL_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='culling';")
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax find --role AXLink --label "Start culling"
   script/vm_scenario_run.sh ax press --role AXLink --label "Start culling"
   ! script/vm_scenario_run.sh ax find --role AXStaticText --label "Recent Imports"

   for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
     RECEIPT_CULL_RUN_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind='culling' AND rowid > $BEFORE_RECEIPT_CULL_ROWID;")
     test "$RECEIPT_CULL_RUN_COUNT" -eq 1 && break
     sleep 1
   done
   test "$RECEIPT_CULL_RUN_COUNT" -eq 1
   RECEIPT_CULL_RUN_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='culling' AND rowid > $BEFORE_RECEIPT_CULL_ROWID;")
   test -n "$RECEIPT_CULL_RUN_ID"
   RECEIPT_CULL_SET_ID=$(script/vm_scenario_run.sh sql empty "SELECT json_extract(input_set_ids_json,'\$[0]') FROM work_sessions WHERE id='$RECEIPT_CULL_RUN_ID';")
   test "$RECEIPT_CULL_SET_ID" = "work-input-$RECEIPT_CULL_RUN_ID"
   test "$(script/vm_scenario_run.sh sql empty "SELECT title FROM work_sessions WHERE id='$RECEIPT_CULL_RUN_ID';")" = "Imported 4 photos from card1 (2 files skipped)"
   test "$(script/vm_scenario_run.sh sql empty "SELECT name FROM asset_sets WHERE id='$RECEIPT_CULL_SET_ID';")" = "Imported 4 photos from card1 (2 files skipped) Input"

   RECEIPT_CULL_INPUT_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='$RECEIPT_CULL_SET_ID'));")
   RECEIPT_CULL_CARD1_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='$RECEIPT_CULL_SET_ID')) m JOIN assets a ON a.id=json_extract(m.value,'\$.rawValue') WHERE a.original_path LIKE '/Users/admin/teststrip-vm/fixtures/import-011/card1/%';")
   test "$RECEIPT_CULL_INPUT_COUNT" -eq 4
   test "$RECEIPT_CULL_CARD1_COUNT" -eq 4
   script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – Cull"
   script/vm_scenario_run.sh ax find --label "Scope" --contains "Imported 4 photos from card1 (2 files skipped) Input"

   script/vm_scenario_run.sh key 'keystroke "2" using {command down}'
   script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – Grid"
   script/vm_scenario_run.sh ax find --label "Scope" --contains "Imported 4 photos from card1 (2 files skipped) Input"
   ```
5. **Same-session non-resurrection** (a correction added for this push — the
   fade records the dismissal into `dismissedToastSummaryID`,
   `dismissToast`/`showToastThenFade`, `LibraryGridView.swift:826-844`,
   specifically so a `.task(id:)` re-entry doesn't restart the 10s clock and
   show the toast again). `dismissedToastSummaryID`/`isToastVisible` are
   `@State` on `LibraryGridView` itself (`:45-46`), and every lens's content
   renders from one internal `Group` inside that same struct
   (`bodyContent`, `:89-138`) — so a lens switch alone does not tear down
   and recreate the hosting view or its state. Exercise several plausible
   re-entry surfaces anyway, since the exact SwiftUI remount trigger the
   code comment describes was not independently traced in this pass:
   switch lenses (⌘4 then ⌘2), switch the selected sidebar source and back,
   and minimize/restore the window. After each, assert the toast has not
   reappeared:
   ```bash
   ! script/vm_scenario_run.sh ax find --contains "Import complete"   # after every probe above
   ```
   This is a distinct guarantee from Step 6's relaunch case — nothing at the
   unit layer can pin either, so this card is the only gate for both.
6. Quit and relaunch the **same VM catalog** (do not call `launch` again; that
   would create a new run directory). Assert the toast does **not** reappear
   (the `isCurrentSessionActivity` guard, `AppModel.swift:13888-13894` —
   persona-7's zombie panel, which `app-006-session-restore.md` also tests
   for a different surface) while the receipt and the sidebar's Imports row
   survive:
   ```bash
   script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
   script/vm_scenario_run.sh shell '
   latest=$(ls -dt "$HOME/teststrip-vm"/run/empty-* | head -1)
   open -n "$HOME/teststrip-vm/dist/Teststrip.app" --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$latest"
   '
   script/vm_scenario_run.sh ax wait-vended Teststrip
   ! script/vm_scenario_run.sh ax find --contains "Import complete"
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity"
   script/vm_scenario_run.sh ax find --contains "Recent Imports"
   ```
   Assert the sidebar's Imports section still shows CARD1's row (title is
   the import's date + detail, `ImportSidebarSummary.title`,
   `UnifiedSidebarPresentation.swift:44-50`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Activity" # close receipt popover
   CARD1_ROW_TITLE=$(script/vm_scenario_run.sh ax find --role AXButton --contains "Imported 4 photos from card1 (2 files skipped)" | awk 'index($0,"Imported 4 photos from card1 (2 files skipped)") && $0 !~ /^(Expand|Collapse) / {print; exit}')
   test -n "$CARD1_ROW_TITLE"
   script/vm_scenario_run.sh ax find --role AXButton --label "$CARD1_ROW_TITLE"
   ```

### Part B — the import row's children
7. Expand the newest import row (CARD1's): click its disclosure triangle
   (`toggleSidebarExpansion`, `AppModel.swift:4722-4739`,
   accessibility label `"Expand <row title>"`, `SidebarView.swift:287`).
   Assert its children and their counts against the catalog. Get CARD1's
   session ID first:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Expand $CARD1_ROW_TITLE"
   SESSION_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='ingest' ORDER BY created_at ASC LIMIT 1;")
   SKIPPED_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions, json_each(work_sessions.issues_json) WHERE work_sessions.id='$SESSION_ID' AND json_extract(value,'\$.kind')='skippedSourceFile';")
   test "$SKIPPED_COUNT" -eq 2
   ```
   (Verified against a scratch table with this exact shape before writing
   this card: `json_each` on a table column needs the table joined into the
   same `FROM` clause as the `json_each(...)` call — `work_sessions,
   json_each(work_sessions.issues_json)` — not a bare correlated subquery.
   `WorkSessionIssue`'s `kind` field serializes as the enum case name;
   confirm that against one live row's `issues_json` before trusting the
   literal `'skippedSourceFile'` string.)
   For `.likelyIssues`/`.facesFound`, the count is each smart source's own
   `SetQuery` ANDed with `.importBatch(sessionID)`
   (`UnifiedSidebarPresentation.swift`'s doc comment on `ImportChildCounts`,
   `:54-60`; `AppModel.swift:5511-5534`) — cross-check via the app's own
   `Likely Issues`/`Faces Found` smart-collection predicates
   (`SmartCollection.likelyIssues`/`.facesFound`, `AppModel.swift`) scoped to
   CARD1's asset IDs:
   ```bash
   script/vm_scenario_run.sh sql empty "SELECT id FROM assets WHERE original_path LIKE '/Users/admin/teststrip-vm/fixtures/import-011/card1/%' ORDER BY id;"
   ```
   Assert the AX-rendered child titles match `ImportChildKind.title`
   (`LibrarySource.swift:12-20`) exactly: `"Stacks"`, `"⚠ Skipped files"`,
   `"⚠ Preview failed"`, `"⚠ Likely issues"`, `"Faces found"` — for whichever
   are nonzero on this fixture (CARD1's `.skippedFiles` is guaranteed
   nonzero at 2; the rest depend on evaluation state, which the `empty` VM run
   does not auto-run — see Sharp edges).
8. Assert a zero-count child is **absent**, not disabled (`childRows`
   filters `guard count > 0 else { return nil }`,
   `UnifiedSidebarPresentation.swift:314-315`). For any of the five children
   with a zero count on this fixture:
   ```bash
   ! script/vm_scenario_run.sh ax find --contains "<child title>"   # not a disabled row
   ```
9. Click `⚠ Skipped files`. Assert it opens the issue-review sheet
   (`ImportIssueReview`, `LibraryGridView.swift:8801`, presented via
   `requestImportIssueReview`, `AppModel.swift:2543`) rather than an empty
   grid — skipped files are not in the catalog at all
   (`ImportChildKind.isDiagnostic`'s doc comment, `LibrarySource.swift:32-38`):
   ```bash
   script/vm_scenario_run.sh ax press --contains "⚠ Skipped files"
   script/vm_scenario_run.sh ax find --contains "notes.txt"
   script/vm_scenario_run.sh ax find --contains "readme.md"
   ```
   Press the sheet's exact `Done` button (`LibraryGridView.swift:1919-1922`)
   and assert the sheet is gone before checking or continuing. Then assert
   the Cull lens disables while this child's source is selected
   (`ImportChildKind.isDiagnostic == true` for
   `.skippedFiles`, `LensRules.availability`'s diagnostic branch,
   `LibraryLens.swift:118-120`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Done"
   ! script/vm_scenario_run.sh ax find --contains "2 Import Issues"
   script/vm_scenario_run.sh ax find --role AXButton --label "Cull" --help "Nothing here is cullable"
   ```

### Part C — the row's context menu, and an older import
10. Right-click CARD1's import row using the SwiftUI-`.contextMenu` idiom
    `test/scenarios/README.md` documents:
    ```bash
    script/vm_scenario_run.sh ax press --role AXButton --label "$CARD1_ROW_TITLE" --button right
    ```
    Assert the menu offers exactly four current items: the star toggle
    (`Star Work` when unstarred, `Remove Star` when starred), `Cull stacks`,
    `Evaluate import`, and `Manual Compare over the import` — with no extras
    (`AppModel.sidebarContextActions(for:)`, `AppModel.swift:5161-5233`,
    specifically the star toggle at `:5202-5207` and the three import verbs at
    `:5212-5227`). Press `Cull stacks` (`beginStackCulling`, `:5019-5041`) and
    assert per-stack
    `work-stack-` sets exist if CARD1's frames landed within the stack
    builder's time-adjacency threshold, per Sharp edges below:
    ```bash
    script/vm_scenario_run.sh ax press --role AXMenuItem --label "Cull stacks"
    script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM asset_sets WHERE id LIKE 'work-stack-%';"
    ```
    If the count is 0, confirm (before reporting a defect) that
    `beginStackCulling`'s no-stacks fallback fired instead — a plain culling
    session over CARD1 with `statusMessage` reading `"...; no time-adjacent
    stacks found"` (`AppModel.swift:5037-5041`) — and record that as the
    honest, source-grounded outcome for this fixture rather than a failure.
11. Import CARD2 (same typed-path route, through the VM wrapper) —
    the same 4 frames as CARD1 plus 2 new ones, so this is **not** the "same
    files" case yet; wait for completion, then re-import CARD2 a second
    time (identical path, identical files this time — genuinely the same
    set). Assert the second CARD2 import's toast reads exactly
    `"No new photos imported — 6 already in catalog"`
    (`ImportCompletionToastPresentation.headline`'s `isExistingOnly` branch,
    `:75-76`, distinct from the unrelated zero-photo string `"No photos
    imported"` at `:72-73`, which fires only when nothing in the folder scanned
    as importable at all — do not conflate the two) and carries **no**
    `Start culling` button (`showsStartCulling = !isExistingOnly &&
    summary.newPhotoCount > 0`, `:55` — both conjuncts are false here):
    ```bash
    script/vm_scenario_run.sh shell '$HOME/teststrip-vm/script/submit_import_path.sh Teststrip /Users/admin/teststrip-vm/fixtures/import-011/card2'
    script/vm_scenario_run.sh ax wait --contains "Imported 2 photos (4 photos already in catalog)"
    script/vm_scenario_run.sh shell '$HOME/teststrip-vm/script/submit_import_path.sh Teststrip /Users/admin/teststrip-vm/fixtures/import-011/card2'
    script/vm_scenario_run.sh ax wait --contains "No new photos imported — 6 already in catalog"
    ! script/vm_scenario_run.sh ax find --role AXButton --label "Start culling"
    ```
12. First prove the discriminator is non-vacuous: CARD1 contributed exactly
    four catalog rows and CARD2 contributed exactly two CARD2-only rows. Then
    record the culling-session count, latest row ID, and latest session ID
    **after Step 10** and before pressing `Cull these`. The receipt action in
    Step 4 created an earlier culling run, but this later boundary excludes it
    (and Step 10's run) from the one-new-run query below. Step 10 entered the
    Cull lens, which hides the query/result header; switch to Grid first so
    the browse-only header is vended (`LensChromePolicy.showsFilterTokens`,
    `LibraryGridView.swift:8276-8278`). Then cull the **older** import (CARD1)
    from its sidebar row rather than the
    newest (CARD2): click CARD1's row to select it as the source
    (`selectSidebarRow`/`applySource`'s `.workSession` case,
    `AppModel.swift:4698-4708,4852-4917`; `applyWorkSession` sets
    `selectedAssetSetID = nil` at `:4919-4936`),
    then press the result-header **"Cull these"** button (exact-case label,
    same disambiguation `app-019-lens-shell.md` documents against the grid's
    "Cull These" context-menu item — do not batch-select assets first and
    use the context-menu item instead, which takes a different, `.manual`-
    membership code path and would invalidate this step's SQL). Assert the
    new run's input set matches CARD1's assets, not CARD2's. The count must
    increase by exactly one and the new ID must differ from Step 10's latest
    culling run, so an old-run lookup cannot satisfy the membership checks:
    ```bash
    CARD1_BASELINE=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets WHERE original_path LIKE '/Users/admin/teststrip-vm/fixtures/import-011/card1/%';")
    CARD2_ONLY_BASELINE=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM assets WHERE original_path LIKE '/Users/admin/teststrip-vm/fixtures/import-011/card2/%';")
    test "$CARD1_BASELINE" -eq 4
    test "$CARD2_ONLY_BASELINE" -eq 2

    BEFORE_CULL_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind='culling';")
    BEFORE_CULL_ROWID=$(script/vm_scenario_run.sh sql empty "SELECT COALESCE(MAX(rowid), 0) FROM work_sessions WHERE kind='culling';")
    BEFORE_LATEST_RUN_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='culling' ORDER BY rowid DESC LIMIT 1;")
    test -n "$BEFORE_LATEST_RUN_ID" # Step 10 already created a culling run
    script/vm_scenario_run.sh key 'keystroke "2" using {command down}'
    script/vm_scenario_run.sh ax find --role AXWindow --contains "Teststrip – Grid"
    CARD1_ROW_TITLE=$(script/vm_scenario_run.sh ax find --role AXButton --contains "Imported 4 photos from card1 (2 files skipped)" | awk 'index($0,"Imported 4 photos from card1 (2 files skipped)") && $0 !~ /^(Expand|Collapse) / {print; exit}')
    test -n "$CARD1_ROW_TITLE"
    script/vm_scenario_run.sh ax press --role AXButton --label "$CARD1_ROW_TITLE"
    script/vm_scenario_run.sh ax press --role AXButton --label "Cull these"

    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      AFTER_CULL_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind='culling';")
      NEW_RUN_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM work_sessions WHERE kind='culling' AND rowid > $BEFORE_CULL_ROWID;")
      test "$AFTER_CULL_COUNT" -eq "$((BEFORE_CULL_COUNT + 1))" && test "$NEW_RUN_COUNT" -eq 1 && break
      sleep 1
    done
    test "$AFTER_CULL_COUNT" -eq "$((BEFORE_CULL_COUNT + 1))"
    test "$NEW_RUN_COUNT" -eq 1
    RUN_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM work_sessions WHERE kind='culling' AND rowid > $BEFORE_CULL_ROWID;")
    test -n "$RUN_ID"
    test "$RUN_ID" != "$BEFORE_LATEST_RUN_ID"
    SET_ID=$(script/vm_scenario_run.sh sql empty "SELECT json_extract(input_set_ids_json,'\$[0]') FROM work_sessions WHERE id='$RUN_ID';")
    test -n "$SET_ID"

    INPUT_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='$SET_ID'));")
    CARD1_INPUT_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='$SET_ID')) m JOIN assets a ON a.id=json_extract(m.value,'\$.rawValue') WHERE a.original_path LIKE '/Users/admin/teststrip-vm/fixtures/import-011/card1/%';")
    CARD2_ONLY_INPUT_COUNT=$(script/vm_scenario_run.sh sql empty "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='$SET_ID')) m JOIN assets a ON a.id=json_extract(m.value,'\$.rawValue') WHERE a.original_path LIKE '/Users/admin/teststrip-vm/fixtures/import-011/card2/%';")
    test "$INPUT_COUNT" -eq 4
    test "$CARD1_INPUT_COUNT" -eq 4
    test "$CARD2_ONLY_INPUT_COUNT" -eq 0
    ```
    `json_each` yields snapshot-member objects such as
    `{"rawValue":"<asset-id>"}`, so the join must extract each object's
    `rawValue`; joining `a.id` directly to `m.value` would never match and
    would make this required-zero assertion pass vacuously. The last query's
    count must be **0** — none of CARD1's run's input assets should be
    CARD2-only frames. (CARD1∩CARD2's 4 shared frames will
    still match `%/card1/%` too since dedup means only one row exists per
    original path — the discriminator is that zero rows in CARD1's input
    set have an `original_path` under `card2` exclusively, i.e. one of the
    2 brand-new CARD2 frames.)

## Expected
- Step 2: **fails if** any of the three toast elements is missing, or the
  skipped-count text doesn't read "2 files skipped" exactly.
- Step 3: **fails if** either banner-chrome string is found — that would
  mean the deleted panel (or new prose resembling it) leaked back onto the
  canvas.
- Step 4: **fails if** the toast is still visible past ~10s; CARD1's retained
  receipt is missing either exact AXLink; Review issues leaves the popover
  open, opens anything other than the exact two-issue CARD1 sheet, or cannot
  dismiss through exact Done; Start culling leaves the popover open, fails to
  create exactly one post-boundary run, lands outside Cull or on the wrong
  source, snapshots anything other than CARD1's four assets, or cannot return
  to Grid without changing that source.
- Step 5: **fails if** navigating away and back resurrects the toast within
  the same session — that is precisely the bug the dismissal-recording fix
  in this push closes.
- Step 6: **fails if** the toast reappears post-relaunch (the zombie-panel
  class of bug) or if the receipt/Imports row do NOT survive relaunch
  (those should be durable, unlike the toast).
- Step 7: **fails if** any nonzero child's count disagrees with its SQL
  ground truth by even one, or if a child's title doesn't match
  `ImportChildKind.title` verbatim.
- Step 8: **fails if** a zero-count child renders at all (disabled or not).
- Step 9: **fails if** clicking `⚠ Skipped files` opens an empty/generic
  grid instead of the named issue-review sheet, if the two skipped filenames
  aren't both listed, or if the exact sheet `Done` action does not close it
  before the diagnostic-source assertion and subsequent steps.
- Step 10: **fails if** the context menu does not contain exactly the current
  star toggle plus the three import verbs (four items total), offers any
  extras, or if pressing `Cull stacks` neither creates
  `work-stack-` sets NOR falls back to the documented no-stacks path.
- Step 11: **fails if** the second identical-files import's toast doesn't
  read the exact existing-only string, or if it shows a `Start culling`
  button it has no business showing.
- Step 12: **fails if** the positive CARD2-only baseline is not exactly 2,
  Grid is not selected before targeting the browse-only `Cull these` button,
  pressing that button does not create exactly one genuinely new run, the
  exact new run's input does not contain all 4 CARD1 members, its total input
  is not exactly 4, or it contains any CARD2-only asset. Those checks reject
  empty/subset/old-run mutants as well as accidental newest-import scoping.

## Cleanup
```bash
script/vm_scenario_run.sh key 'keystroke "q" using {command down}'
script/vm_scenario_run.sh shell 'rm -rf /Users/admin/teststrip-vm/fixtures/import-011'
```

## Sharp edges
- **The Stacks/Likely-issues/Faces-found children depend on evaluation
  state that an `empty` VM run does not auto-run.** CARD1's `.skippedFiles` child
  is guaranteed nonzero (2, from the hand-added non-image files); the other
  four children may all be legitimately absent on a fresh empty-catalog import
  with no evaluation pass triggered, in which case Step 7's assertion
  degenerates to "only `⚠ Skipped files` renders, and the app is honest
  about the rest being zero" — note that as the actual (not a fallback)
  outcome rather than forcing an evaluation pass this card doesn't
  otherwise need.
- **`Cull stacks`' `work-stack-` sets depend on CARD1's frames landing
  within `AssetStackBuilder`'s time-adjacency threshold** — the same
  structural gap `cull-013-filmstrip.md`/`cull-014-stack-rail.md`/
  `cull-015-sidebar-sources.md`/`cull-029-autopilot-ghost-derivation.md`
  document for their own stack-dependent assertions. The copied `faces`
  originals' capture spacing was not independently verified for this card, so
  Step 10
  is written to accept either outcome and calls out which one actually
  happened, per those cards' established pattern — don't let a 0-stacks
  result get reported as a defect without first checking the no-stacks
  fallback path fired correctly.
- Step 7's `issues_json`-filtered count was verified against a scratch
  SQLite table with the exact `work_sessions(id, issues_json)` shape before
  this card was written (join form, not a correlated subquery) — see the
  step for the verified query. What was **not** independently confirmed is
  `WorkSessionIssue.kind`'s serialized string on a real catalog row; a
  dry-run `SELECT issues_json FROM work_sessions WHERE id='$SESSION_ID'`
  before trusting the literal `'skippedSourceFile'` match is still cheap
  insurance.
- Step 12's discriminator query reads the `.snapshot` JSON path, not
  `.manual`. Traced directly: scoping to CARD1 via its `.workSession` source
  sets `selectedAssetSetID = nil` (`applyWorkSession`, `AppModel.swift:4919-4936`),
  so `cullingInputSetID` (`:13135-13159`) takes its `else` branch and writes
  a **fresh `work-input-<sessionID>` set with `.snapshot(inputAssetIDs)`
  membership** (`:13148-13154`), not `.manual`. The `.manual._0`/`.snapshot
  ._0` JSON-path pattern itself is the same synthesized-Codable shape
  already verified live in `cull-020-pass-scope-and-undo.md:58`
  (`.manual._0`, for a stack-rail set) and `cull-025-run-strip-completion.md:
  385` (`.snapshot._0`, for exactly this kind of input-set snapshot) — only
  the case name changes per membership kind. If a future edit changes which
  route Step 12 drives (e.g. via `cullCurrentSelection()` instead of
  selecting the workSession source directly), re-check
  `cullingInputSetID`'s branch before trusting this JSON path.

## Run status
CURRENT PROCEDURE: PENDING FRESH VM RUN. The reusable procedure above is
wrapper-only; Step 4's two-action receipt binding and Step 12's new-run
discriminator were hardened after the dated runs below. No fresh VM run was
performed for either repair, so neither revised leg inherits a historical
pass claim. In particular, no dated run below exercised `Review issues` from
the Activity receipt.

UNRUN — authored 2026-08-08 for the unified-shell push (Task 12), source-cited
against `feat/unified-shell` @ `496abf1e`. This is the original authoring state,
retained as historical evidence.

**Reconciled 2026-08-09 (Task 13, citation fix)**: the skipped-file citation
(`LibraryImportService.swift:466-473`) named no directory, which read as
`Sources/TeststripApp/` given every neighboring citation in this card uses
that prefix — the file actually lives at
`Sources/TeststripCore/Ingest/LibraryImportService.swift` (confirmed via
`find Sources -iname LibraryImportService.swift`); the line range itself
(466-473, `skippedSourceFileMessage`) was already correct. Every other
citation in this card's Source section was spot-checked directly against
source during this pass and found exact. No step or assertion changed.
Steps themselves not re-verified live.

**FAIL — two product defects; live VM run 2026-08-09**, `feat/unified-shell`
@ `8f598239`, `script/vm_scenario_run.sh launch empty` in the `teststrip-e2e`
Tart VM. **9 of 12 steps run**: Steps 1-6 and 10-12 run; **Steps 7, 8 and 9
NOT RUN — blocked by defect 1 below**, which makes the import row's children
unreachable through the UI at all.

Fixture substitution (recorded because it changes the numbers, not the
semantics): `swift run TeststripBench seed-dup-fixtures` needs a host build,
which this run was scoped out of, so CARD1/CARD2 were built on the VM from the
already-synced `sample-data/photos/faces` JPEGs with plain `cp` — CARD1 = 4
distinct JPEGs + `notes.txt` + `readme.md`, CARD2 = the same 4 byte-identical
+ 2 brand-new. That is exactly the card's N=4 / M=2 shape.

### Defect 1 (product) — the import row can never be expanded; its children are dead UI

The disclosure chevron never renders, so `Stacks / ⚠ Skipped files / ⚠ Preview
failed / ⚠ Likely issues / Faces found` are unreachable. It is a
chicken-and-egg deadlock in the model, not a rendering glitch:

- `importSectionRows` sets `disclosure: counts.isEmpty ? .none : …`
  (`UnifiedSidebarPresentation.swift:271`).
- `counts` comes from `importChildCountsBySessionID`, which is only ever
  written for session IDs already present in `expandedImportSessionIDs` —
  inside `toggleSidebarExpansion`'s expand branch (`AppModel.swift:4731-4733`)
  and in `refreshCatalogSidebarCounts`'s `for sessionID in
  expandedImportSessionIDs` loop (`:13093-13095`). Those are the only two
  writers (`grep expandedImportSessionIDs Sources/TeststripApp/*.swift`).
- `expandedImportSessionIDs` starts empty and is only ever inserted into by
  `toggleSidebarExpansion`, which is reachable **only** from
  `disclosureControl`'s Button — which is not rendered, because `disclosure`
  is `.none`, because the counts were never computed.

So a never-expanded import row always reports all-zero counts, always gets
`.none`, and can never be expanded.

Live evidence, CARD1's import (4 photos, 2 skipped, faces detected):
```
# catalog says the children should be non-empty
sqlite> SELECT issues_json FROM work_sessions WHERE kind='ingest';
[{"kind":"skippedSourceFile","message":"file type not supported","sourceURL":"file:///Users/admin/import011-fixtures/card1/notes.txt"},
 {"kind":"skippedSourceFile","message":"file type not supported","sourceURL":"file:///Users/admin/import011-fixtures/card1/readme.md"}]
sqlite> SELECT COUNT(*) FROM work_sessions, json_each(work_sessions.issues_json)
        WHERE kind='ingest' AND json_extract(value,'$.kind')='skippedSourceFile';
2
sqlite> SELECT COUNT(DISTINCT asset_id) FROM face_observations;
4                      -- and the sidebar's own "Faces Found" row reads 4
```
so `importChildCounts` would return `skippedFiles: 2, facesFound: 4` — clearly
non-empty. What the tree actually vends is a leaf:
```
AXRow
  AXCell enabled=true
    AXButton desc="Aug 9 · Imported 4 photos from card1 (2 files skipped)" value="4" enabled=true
```
No `Expand …` / `Collapse …` element, no child rows. A `screencapture` of the
sidebar confirms it visually: the import row has an icon, title and count
badge, and no disclosure triangle — its leading edge aligns exactly with
`All Photos`, which has no disclosure either. Coordinate clicks at four
offsets across the row's leading gutter (dx −6/−10/−16/−20 from the row
button's frame origin) changed nothing, as expected: there is no control
there to hit.

Consequence for this card: **Step 7 (children and their counts), Step 8
(zero-count child absent) and Step 9 (skipped-files child opens the
issue-review sheet; Cull disabled for that diagnostic source) could not be
run at all.** They are blocked, not passed and not failed.

### Defect 2 (product) — the existing-only toast headline is unreachable

Step 11's asserted string `"No new photos imported — N already in catalog"`
never renders. The second, genuinely-identical CARD2 import produced:
```
AXGroup AXDescription="Import complete" enabled=true
  AXImage AXDescription="Selected" enabled=true
  AXStaticText AXValue="No photos imported" enabled=true
  AXButton AXDescription="Dismiss import toast" AXHelp="Dismiss" enabled=true
```
i.e. the zero-photo string (`ImportCompletionToastPresentation.swift:65`),
which this card explicitly warns must not be conflated with the existing-only
string at `:67-68`.

Root cause: `isExistingOnly` is `newPhotoCount == 0 && existingPhotoCount > 0`
(`:47`), and `existingPhotoCount` is derived as
`max(importedPhotoCount - newPhotoCount, 0)` where
`importedPhotoCount = activity.totalUnitCount ?? activity.completedUnitCount`
and `newPhotoCount = activity.completedUnitCount`
(`AppModel.swift:3367-3376`). On every ingest session the catalog writes
`total_unit_count == completed_unit_count`, so `existingPhotoCount` is
**always 0** and `isExistingOnly` is **always false** — the branch is dead:
```
sqlite> SELECT detail, completed_unit_count, total_unit_count
        FROM work_sessions WHERE kind='ingest' ORDER BY created_at;
Imported 4 photos from card1 (2 files skipped)|4|4
Imported 2 photos (4 photos already in catalog) from card2|2|2
No supported photos found in card2|0|0
```
Note the third row: the session's own `detail` for the all-duplicate re-import
reads `"No supported photos found in card2"`, which is also wrong — six
supported photos were found, all already catalogued. The dedup count that the
second row *does* carry correctly ("4 photos already in catalog") comes from
the detail string, not from `existingPhotoCount`, which is 0 there too.

The other half of Step 11 **passed**: the existing-only toast carried **no**
`Start culling` button, correct for `showsStartCulling = !isExistingOnly &&
summary.newPhotoCount > 0` with `newPhotoCount == 0`.

### What passed

- **Step 1-2** — CARD1 imported through the typed-path sheet; the toast
  appeared as `AXGroup AXDescription="Import complete"` containing
  `AXStaticText AXValue="Imported 4 photos"`, `AXStaticText AXValue="2 files
  skipped"` (exact), `AXButton AXDescription="Start culling"`, and a
  `Dismiss import toast` button.
- **Step 3** — no banner chrome. A full-canvas snapshot taken while the toast
  was up contains zero occurrences of `Review imported frames` and zero of
  `Cull stacks`.
- **Step 4** — the toast auto-faded after **10.2s** (watcher timestamps
  `APPEAR t=27.6s` → `GONE t=37.9s`), matching `visibleDuration = 10`. The
  bell then held `Recent Imports` / `Imported 4 photos from card1 (2 files
  skipped)` / `2 files skipped` / `Start culling`. This historical run only
  found the Start-culling link; it pressed neither receipt action, and it
  predates the `Review issues` link entirely.
- **Step 5** — same-session non-resurrection holds. Under a continuous
  watcher: lens switch (⌘4 then ⌘2), source switch (import row → All Photos),
  and minimize/restore. Result `NEVER-APPEARED within 75.0s`.
- **Step 6** — relaunch non-resurrection holds. After ⌘Q and a relaunch
  against the same isolated dir, a 45s watch returned `NEVER-APPEARED`, while
  the Imports row (`Aug 9 · Imported 4 photos from card1 (2 files skipped)`)
  and the bell receipt (`Recent Imports`, `2 files skipped`, `Start culling`)
  both survived.
- **Step 10** — the context menu opened via `press --contains … --button
  right` and the `Cull stacks` fallback fired as the card allows: zero
  `work-stack-%` sets, and instead a plain culling session over the import
  (`culling|Aug 9 · Imported 4 photos from card1 (2 files skipped)|running`
  with a single `work-input-…` set of 4 photos, Cull lens in loupe reading
  `✓ 0 · ✕ 0 · 4 left`). Correct per `beginStackCulling`'s no-stacks guard
  (`AppModel.swift:5007-5011`) for a fixture with no time-adjacent frames.
- **Step 12** — culling the **older** import scoped correctly. CARD1's row
  selected as source, `Cull these` pressed; the run's `work-input-…` set holds
  exactly CARD1's 4 originals and **0** CARD2-only frames.

### Corrections this run found in the card (app is right, assertions stale)

- **Step 4's bell assertion had the wrong role in the version driven.** The
  receipt's `Start culling` vended as `AXLink`, not `AXButton`:
  `find --role AXButton --label "Start culling"` → not-found;
  `find --role AXLink --label "Start culling"` → found. (The toast's own
  `Start culling` was an `AXButton` — only the bell receipt differed.) The
  executable Step 4 above now uses the live-proven `AXLink` role. `Review
  issues` did not exist in that build, so its AXLink role, sheet routing, and
  session binding remain pending the fresh run required above.
- **Step 10's "exactly three items" assertion was wrong in the version
  driven.** The menu vended four: `Star Work`, `Cull stacks`, `Evaluate
  import`, `Manual Compare over the import`. `Star Work` was deliberate; the
  then-cited range simply started below the star branch. The executable step
  above now requires the current star toggle (`Star Work`/`Remove Star`) plus
  the three import verbs, and nothing else, anchored at the current
  `AppModel.sidebarContextActions(for:)` symbols.
- **Step 12's discriminator SQL was malformed in the version driven.**
  `json_each` over `.snapshot._0` yielded JSON *objects*
  (`{"rawValue":"…"}`), so `a.id = m.value` never joined and the query
  returned 0 for the wrong reason. The live-proven working form was
  `a.id = json_extract(m.value,'$.rawValue')`; the executable step above now
  uses that form, with the `$` escaped for the surrounding shell double
  quotes. The scoped run verdict is unchanged.

Environment: no Sparkle modal on this card's launches (suppressed in the VM
via `defaults write com.teststrip.app SUEnableAutomaticChecks -bool NO` after
it fired once during `app-019`), and no idle-wedge. Nothing here is
environment-blocked.

**RE-DRIVE 2026-08-09 — FAIL (one new diagnostic-source contract defect)**,
`feat/unified-shell` @ `47718d3c`, one fresh `script/vm_scenario_run.sh launch
empty` in `teststrip-e2e`. This targeted the six required checks only; it did
not re-run app-019 or the previously-passing import steps. CARD1 was four
face-bearing JPEGs plus `notes.txt`/`readme.md`; CARD2 reused those four exact
byte-identical JPEGs and added two new JPEGs. Full commands, SQL, AX output,
screenshots, and cleanup are in
`.superpowers/sdd/2026-08-07-unified-shell/task-vm-redrive-report.md`.

- **Steps 1-2 setup: PASS.** CARD1 session
  `import-F8641D6A-C759-4BF0-886B-1516DA4997E6` recorded 4 new photos and 2
  serialised `skippedSourceFile` issues; live toast vended `Import complete`,
  `Imported 4 photos`, `2 files skipped`, and `Start culling`.
- **Step 7 disclosure/counts: PASS.** AX vended and pressed
  `Expand Aug 10 · Imported 4 photos from card1 (2 files skipped)`. The
  expanded row showed `⚠ Skipped files` = 2 and `Faces found` = 4, matching
  nested-catalog SQL. The live `issues_json` kind was exactly
  `skippedSourceFile`.
- **Step 8 zero omissions: PASS.** `Stacks=0`, `⚠ Preview failed=0`, and
  `⚠ Likely issues=0` were each absent from AX, not disabled; the two nonzero
  children above were present. CARD1 had no multi-frame stack, no failed
  preview queue row, and no asset matching the app's scoped `likelyIssue`
  predicate.
- **Step 9: FAIL.** The skipped-files child correctly opened a `2 Import
  Issues` sheet listing both `notes.txt` and `readme.md` with their full paths,
  rather than a generic grid. After `Done`, however, the required disabled
  Cull control did not vend: `Cull` instead vended enabled with help `Cull`,
  and scope remained `All Photos`. Root cause: `selectSidebarRow` requests the
  issue sheet for `.skippedFiles` and returns before selecting the diagnostic
  `LibrarySource`, making the card's `Nothing here is cullable` contract
  unreachable. This is a new product defect; no fix was attempted.
- **Step 11 existing-only: PASS.** The second CARD2 session had 0 new, 6
  existing by the nested catalog and AX exactly read
  `No new photos imported — 6 already in catalog`; no `Start culling` button
  was present.
- **Mixed CARD2 import: PASS.** The first CARD2 session had 2 new plus 4
  existing (`completed_unit_count=2`, `total_unit_count=6`, two-member output
  set). AX exactly read `Imported 2 photos (4 photos already in catalog)`,
  never the old incorrect `Imported 6 photos`.

No Sparkle modal or idle wedge occurred. The two old product defects are now
verified fixed live; this re-drive supersedes their FAIL status while retaining
the historical record above. The card remains failed because Step 9's required
post-dismissal diagnostic-source Cull contract is not met.

**FIXED / VERIFIED 2026-08-09 — scoped Step 9 VM re-run**, `feat/unified-shell`
@ `d70a0f3e`, after RED pin `78688fa0` and an Approved independent review. One
fresh `script/vm_scenario_run.sh launch empty` re-created CARD1 only and did
not re-run the other five already-passing re-drive items or app-019. Starting
from Cull, the actual expanded import child `⚠ Skipped files` opened its
`2 Import Issues` sheet with both `notes.txt` and `readme.md`. After `Done`,
live AX vended:

```text
window title=Teststrip – Grid
Scope = ⚠ Skipped files, 4 photos · Import: import-DAAF0507-8797-439D-95D4-17FBCB78B56A
Cull = enabled=false, help="Nothing here is cullable"
```

Nested catalog SQL confirmed that the applied import output set contains the
four real CARD1 asset IDs while `issues_json` retains exactly two
`skippedSourceFile` records and neither text file has an `assets` row. The
sheet is therefore still the only skipped-file presentation, not a fake asset
grid. This fixes the prior post-dismissal source/lens failure. Together with
the preceding re-drive's five passes, **all six targeted re-drive items are
now verified live**; this statement does not claim the historical 12-step
card was wholly rerun. Full commands, AX/SQL output, inspected screenshots,
and cleanup: `.superpowers/sdd/2026-08-07-unified-shell/task-vm-diagnostic-source-rerun-report.md`.
