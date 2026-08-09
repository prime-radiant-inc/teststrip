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
same-session non-resurrection, the import row's children and their counts,
zero-count-child omission, the skipped-files child opening the issue-review
sheet instead of an (empty) grid, the row's context menu, and culling an
older (not just the newest) import.

Source: `Sources/TeststripApp/ImportCompletionToastPresentation.swift`
(`ImportCompletionToastPresentation.toast(for:isCurrentSessionActivity:
isImporting:)` `:40-58`, `headline(for:isExistingOnly:)` `:63-71`,
`ImportReceiptRow` `:77-119`), `Sources/TeststripApp/LibraryGridView.swift`
(toast overlay + `.task(id:)` re-show guard `:246-260`, `importCompletionToast`
view `:770-814`, `dismissToast`/`showToastThenFade` `:826-844`),
`Sources/TeststripApp/ActivityCenterView.swift` (`receiptsSection` `:272-300`),
`Sources/TeststripApp/UnifiedSidebarPresentation.swift` (`ImportSidebarSummary`
`:14-49`, `ImportChildCounts` `:61-79`, `importSectionRows`/`runningImportRow`/
`childRows` `:248-320`), `Sources/TeststripApp/LibrarySource.swift`
(`ImportChildKind` `:5-39`), `Sources/TeststripApp/AppModel.swift`
(`isCurrentSessionActivity` `:13750-13752`, `applyImportChild` `:4913-`,
`requestImportIssueReview` `:2543`, sidebar context menu's import-row actions
`:5170-5199`, `beginStackCulling` `:4992-5022`), `Sources/TeststripApp/
LibraryGridView.swift` (`ImportIssueReview` `:8802`, `importIssueReviewSheet`
`:1904`, `presentRequestedImportIssueReview` `:3117`),
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
./script/build_and_run.sh --isolated
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--isolated` alone is an empty catalog (per `test/scenarios/README.md`) — the
right baseline here, since every count in this card must be attributable to
imports this card performs, not `--smoke`'s pre-seeded 24 photos.

Two fixture folders, reusing the bench seeder already proven in
`import-004-new-only-dedupe.md`/`import-008-auto-cull-toggle.md`:
```bash
DUP_FIXTURES=$(mktemp -d)/dup
swift run TeststripBench seed-dup-fixtures "$DUP_FIXTURES"
CARD1="$DUP_FIXTURES/card1"   # N=4 distinct JPEGs
CARD2="$DUP_FIXTURES/card2"   # the same 4 frames byte-identical + M=2 brand-new
```
A skipped-file fixture — one real, producible skip, not a placeholder. Any
file extension outside the supported image set and outside
`FolderScanner.videoExtensions` reports `.unrecognizedFile`
(`FolderScanner.swift:90-98`), which the importer surfaces as a
`skippedSourceFile` issue with message "file type not supported"
(`LibraryImportService.swift:466-473`). Drop two into CARD1 before the first
import:
```bash
echo "not a photo" > "$CARD1/notes.txt"
echo "not a photo either" > "$CARD1/readme.md"
```
This makes CARD1's first import produce exactly 2 skipped files (unlike
`activity-002-popover-import.md`'s still-open gap, which is about
preview/backup *failures*, a different and not-yet-producible fixture — this
card only needs the importer's own file-type filter, which is trivially
reproducible).

## Steps

### Part A — the toast, on a fresh import
1. `script/ax_drive.sh wait-vended Teststrip`. Import CARD1 through the
   typed-path sheet (`script/submit_import_path.sh Teststrip "$CARD1"`,
   per `test/scenarios/README.md`'s recommended driver for the multi-field
   Import Path sheet). Wait for completion.
2. On completion, assert the toast:
   ```bash
   script/ax_drive.sh find --contains "Import complete"   # accessibilityLabel on the toast container
   script/ax_drive.sh find --role AXButton --label "Start culling"
   script/ax_drive.sh find --contains "2 files skipped"
   ```
   (`ImportCompletionToastPresentation.toast`'s `warningText`, `:52-54`: the
   plural branch fires because CARD1 has exactly 2 skipped files.)
3. Assert **no banner chrome exists** anywhere on the canvas — the deleted
   nine-action panel and its headline (neither string appears anywhere in
   current `Sources/`, confirming both really were deleted rather than
   renamed):
   ```bash
   script/ax_drive.sh find --contains "Review imported frames"   # expect not-found
   script/ax_drive.sh find --contains "Cull stacks"               # expect not-found
   ```
   The second check is a **canvas** absence only — no context menu is open
   at this point in the flow, so it cannot collide with the identical-text
   `Cull stacks` sidebar **context-menu item** (`AppModel.swift:5185`,
   exercised in Step 10) that legitimately exists but only renders inside an
   open `AXMenu`, never as loose canvas text.
4. Let ~10s elapse (`ImportCompletionToastPresentation.visibleDuration`,
   `:11`). Assert the toast is gone:
   ```bash
   script/ax_drive.sh find --contains "Import complete"   # expect not-found
   ```
   Open the bell (Activity Center) and assert its popover holds a
   `"Recent Imports"` receipt (`ActivityCenterView.swift:274`) with the same
   counts and its own `Start culling`:
   ```bash
   script/ax_drive.sh press --role AXButton --help "Activity"
   script/ax_drive.sh find --contains "Recent Imports"
   script/ax_drive.sh find --contains "2 files skipped"
   script/ax_drive.sh find --role AXButton --label "Start culling"
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
   script/ax_drive.sh find --contains "Import complete"   # expect not-found, after every probe above
   ```
   This is a distinct guarantee from Step 6's relaunch case — nothing at the
   unit layer can pin either, so this card is the only gate for both.
6. Quit and relaunch. Assert the toast does **not** reappear (the
   `isCurrentSessionActivity` guard, `AppModel.swift:13750-13752` —
   persona-7's zombie panel, which `app-006-session-restore.md` also tests
   for a different surface) while the receipt and the sidebar's Imports row
   survive:
   ```bash
   script/ax_drive.sh find --contains "Import complete"   # expect not-found
   script/ax_drive.sh press --role AXButton --help "Activity"
   script/ax_drive.sh find --contains "Recent Imports"
   ```
   Assert the sidebar's Imports section still shows CARD1's row (title is
   the import's date + detail, `ImportSidebarSummary.title`,
   `UnifiedSidebarPresentation.swift:44-49`):
   ```bash
   script/ax_drive.sh find --contains "Imports"
   ```

### Part B — the import row's children
7. Expand the newest import row (CARD1's): click its disclosure triangle
   (`toggleSidebarExpansion`, `AppModel.swift:4722-4734`,
   accessibility label `"Expand <row title>"`, `SidebarView.swift:287`).
   Assert its children and their counts against the catalog. Get CARD1's
   session ID first:
   ```bash
   SESSION_ID=$(sqlite3 "$DB" "SELECT id FROM work_sessions WHERE kind='ingest' ORDER BY created_at ASC LIMIT 1;")
   sqlite3 "$DB" "SELECT COUNT(*) FROM work_sessions, json_each(work_sessions.issues_json) WHERE work_sessions.id='$SESSION_ID' AND json_extract(value,'\$.kind')='skippedSourceFile';"
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
   `:54-59`; `AppModel.swift:5440,5443`) — cross-check via the app's own
   `Likely Issues`/`Faces Found` smart-collection predicates
   (`SmartCollection.likelyIssues`/`.facesFound`, `AppModel.swift`) scoped to
   CARD1's asset IDs:
   ```bash
   sqlite3 "$DB" "SELECT id FROM assets WHERE original_path LIKE '%/card1/%' ORDER BY id;"
   ```
   Assert the AX-rendered child titles match `ImportChildKind.title`
   (`LibrarySource.swift:12-20`) exactly: `"Stacks"`, `"⚠ Skipped files"`,
   `"⚠ Preview failed"`, `"⚠ Likely issues"`, `"Faces found"` — for whichever
   are nonzero on this fixture (CARD1's `.skippedFiles` is guaranteed
   nonzero at 2; the rest depend on evaluation state, which `--isolated`
   does not auto-run — see Sharp edges).
8. Assert a zero-count child is **absent**, not disabled (`childRows`
   filters `guard count > 0 else { return nil }`,
   `UnifiedSidebarPresentation.swift:314-315`). For any of the five children
   with a zero count on this fixture:
   ```bash
   script/ax_drive.sh find --contains "<child title>"   # expect not-found, not a disabled row
   ```
9. Click `⚠ Skipped files`. Assert it opens the issue-review sheet
   (`ImportIssueReview`, `LibraryGridView.swift:8802`, presented via
   `requestImportIssueReview`, `AppModel.swift:2543`) rather than an empty
   grid — skipped files are not in the catalog at all
   (`ImportChildKind.isDiagnostic`'s doc comment, `LibrarySource.swift:32-38`):
   ```bash
   script/ax_drive.sh press --contains "⚠ Skipped files"
   script/ax_drive.sh find --contains "notes.txt"
   script/ax_drive.sh find --contains "readme.md"
   ```
   Dismiss the sheet, then assert the Cull lens disables while this child's
   source is selected (`ImportChildKind.isDiagnostic == true` for
   `.skippedFiles`, `LensRules.availability`'s diagnostic branch,
   `LibraryLens.swift:118-120`):
   ```bash
   script/ax_drive.sh find --role AXButton --label "Cull" --help "Nothing here is cullable"
   ```

### Part C — the row's context menu, and an older import
10. Right-click CARD1's import row
    (`ax_drive.sh press --contains "<CARD1 row title>" --button right`, the
    SwiftUI-`.contextMenu` idiom `test/scenarios/README.md` documents).
    Assert the menu offers exactly `Cull stacks`, `Evaluate import`,
    `Manual Compare over the import` (`AppModel.swift:5184-5199`). Press
    `Cull stacks` (`beginStackCulling`, `:4992-5022`) and assert per-stack
    `work-stack-` sets exist if CARD1's frames landed within the stack
    builder's time-adjacency threshold, per Sharp edges below:
    ```bash
    sqlite3 "$DB" "SELECT COUNT(*) FROM asset_sets WHERE id LIKE 'work-stack-%';"
    ```
    If the count is 0, confirm (before reporting a defect) that
    `beginStackCulling`'s no-stacks fallback fired instead — a plain culling
    session over CARD1 with `statusMessage` reading `"...; no time-adjacent
    stacks found"` (`AppModel.swift:5007-5011`) — and record that as the
    honest, source-grounded outcome for this fixture rather than a failure.
11. Import CARD2 (same route: `submit_import_path.sh Teststrip "$CARD2"`) —
    the same 4 frames as CARD1 plus 2 new ones, so this is **not** the "same
    files" case yet; wait for completion, then re-import CARD2 a second
    time (identical path, identical files this time — genuinely the same
    set). Assert the second CARD2 import's toast reads exactly
    `"No new photos imported — N already in catalog"`
    (`ImportCompletionToastPresentation.headline`'s `isExistingOnly` branch,
    `:67-68`, distinct from the unrelated zero-photo string `"No photos
    imported"` at `:65`, which fires only when nothing in the folder scanned
    as importable at all — do not conflate the two) and carries **no**
    `Start culling` button (`showsStartCulling = !isExistingOnly &&
    summary.newPhotoCount > 0`, `:55` — both conjuncts are false here):
    ```bash
    script/ax_drive.sh find --contains "already in catalog"
    script/ax_drive.sh find --role AXButton --label "Start culling"   # expect not-found on this toast
    ```
12. Cull the **older** import (CARD1) from its sidebar row rather than the
    newest (CARD2): click CARD1's row to select it as the source
    (`selectSidebarRow`/`applySource`'s `.workSession` case,
    `AppModel.swift:4870,4888-4907` — this sets `selectedAssetSetID = nil`),
    then press the result-header **"Cull these"** button (exact-case label,
    same disambiguation `app-019-lens-shell.md` documents against the grid's
    "Cull These" context-menu item — do not batch-select assets first and
    use the context-menu item instead, which takes a different, `.manual`-
    membership code path and would invalidate this step's SQL). Assert the
    run's input set matches CARD1's assets, not CARD2's:
    ```bash
    sqlite3 "$DB" "SELECT id FROM work_sessions WHERE kind='culling' ORDER BY created_at DESC LIMIT 1;" # get RUN_ID
    sqlite3 "$DB" "SELECT json_extract(input_set_ids_json,'\$[0]') FROM work_sessions WHERE id='<RUN_ID>';" # SET_ID
    sqlite3 "$DB" "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='<SET_ID>')) m, assets a WHERE a.id = m.value AND a.original_path LIKE '%/card2/%';"
    ```
    The last query's count must be **0** — none of CARD1's run's input
    assets should be CARD2-only frames. (CARD1∩CARD2's 4 shared frames will
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
- Step 4: **fails if** the toast is still visible past ~10s, or the bell's
  receipt is missing/mismatched.
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
  grid instead of the named issue-review sheet, or if the two skipped
  filenames aren't both listed.
- Step 10: **fails if** the context menu is missing any of the three items
  or offers extras, or if pressing `Cull stacks` neither creates
  `work-stack-` sets NOR falls back to the documented no-stacks path.
- Step 11: **fails if** the second identical-files import's toast doesn't
  read the exact existing-only string, or if it shows a `Start culling`
  button it has no business showing.
- Step 12: **fails if** the older import's run pulls in any CARD2-only
  asset — that would mean "cull an older import" silently scoped to the
  newest one instead.

## Cleanup
```bash
rm -rf "$DUP_FIXTURES"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- **The Stacks/Likely-issues/Faces-found children depend on evaluation
  state that `--isolated` does not auto-run.** CARD1's `.skippedFiles` child
  is guaranteed nonzero (2, from the hand-added non-image files); the other
  four children may all be legitimately absent on a fresh isolated import
  with no evaluation pass triggered, in which case Step 7's assertion
  degenerates to "only `⚠ Skipped files` renders, and the app is honest
  about the rest being zero" — note that as the actual (not a fallback)
  outcome rather than forcing an evaluation pass this card doesn't
  otherwise need.
- **`Cull stacks`' `work-stack-` sets depend on CARD1's frames landing
  within `AssetStackBuilder`'s time-adjacency threshold** — the same
  structural gap `cull-013-filmstrip.md`/`cull-014-stack-rail.md`/
  `cull-015-sidebar-sources.md`/`cull-029-autopilot-ghost-derivation.md`
  document for their own stack-dependent assertions (smoke's capture
  spacing is far wider than the 2s threshold; the dup-fixture seeder's
  timestamp spacing was not independently verified in this pass). Step 10
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
  sets `selectedAssetSetID = nil` (`applyWorkSession`, `AppModel.swift:4894`),
  so `cullingInputSetID` (`:13001-13026`) takes its `else` branch and writes
  a **fresh `work-input-<sessionID>` set with `.snapshot(inputAssetIDs)`
  membership** (`:13014-13020`), not `.manual`. The `.manual._0`/`.snapshot
  ._0` JSON-path pattern itself is the same synthesized-Codable shape
  already verified live in `cull-020-pass-scope-and-undo.md:58`
  (`.manual._0`, for a stack-rail set) and `cull-025-run-strip-completion.md:
  385` (`.snapshot._0`, for exactly this kind of input-set snapshot) — only
  the case name changes per membership kind. If a future edit changes which
  route Step 12 drives (e.g. via `cullCurrentSelection()` instead of
  selecting the workSession source directly), re-check
  `cullingInputSetID`'s branch before trusting this JSON path.

## Run status
UNRUN — authored 2026-08-08 for the unified-shell push (Task 12), source-cited
against `feat/unified-shell` @ `496abf1e`. Pending a live VM run per
`script/vm_scenario_run.sh`.
