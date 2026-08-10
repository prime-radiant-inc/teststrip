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
isImporting:)` `:40-58`, `headline(for:isExistingOnly:)` `:71-84`,
`ImportReceiptRow` `:90-131`), `Sources/TeststripApp/LibraryGridView.swift`
(toast overlay + `.task(id:)` re-show guard `:247-260`, `importCompletionToast`
view `:771-824`, `dismissToast`/`showToastThenFade` `:826-844`),
`Sources/TeststripApp/ActivityCenterView.swift` (`receiptsSection` `:272-299`),
`Sources/TeststripApp/UnifiedSidebarPresentation.swift` (`ImportSidebarSummary`
`:14-49`, `ImportChildCounts` `:61-79`, `importSectionRows`/`runningImportRow`/
`childRows` `:248-320`), `Sources/TeststripApp/LibrarySource.swift`
(`ImportChildKind` `:5-39`), `Sources/TeststripApp/AppModel.swift`
(`isCurrentSessionActivity` `:13888-13894`, `applyImportChild` `:4939-4983`,
`requestImportIssueReview` `:2543-2546`, `sidebarContextActions(for:)`
`:5161-5233`, with the work-session star toggle
at `:5202-5207` and import verbs at `:5212-5227`, `beginStackCulling`
`:5019-5041`), `Sources/TeststripApp/
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
(`Sources/TeststripCore/Ingest/LibraryImportService.swift:466-473`
— not `Sources/TeststripApp/`, per the surrounding citations' path; verified
against source). Drop two into CARD1 before the first
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
   script/ax_drive.sh find --role AXLink --label "Start culling"
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
    sqlite3 "$DB" "SELECT COUNT(*) FROM asset_sets WHERE id LIKE 'work-stack-%';"
    ```
    If the count is 0, confirm (before reporting a defect) that
    `beginStackCulling`'s no-stacks fallback fired instead — a plain culling
    session over CARD1 with `statusMessage` reading `"...; no time-adjacent
    stacks found"` (`AppModel.swift:5037-5041`) — and record that as the
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
    `AppModel.swift:4698-4708,4852-4917`; `applyWorkSession` sets
    `selectedAssetSetID = nil` at `:4919-4936`),
    then press the result-header **"Cull these"** button (exact-case label,
    same disambiguation `app-019-lens-shell.md` documents against the grid's
    "Cull These" context-menu item — do not batch-select assets first and
    use the context-menu item instead, which takes a different, `.manual`-
    membership code path and would invalidate this step's SQL). Assert the
    run's input set matches CARD1's assets, not CARD2's:
    ```bash
    sqlite3 "$DB" "SELECT id FROM work_sessions WHERE kind='culling' ORDER BY created_at DESC LIMIT 1;" # get RUN_ID
    sqlite3 "$DB" "SELECT json_extract(input_set_ids_json,'\$[0]') FROM work_sessions WHERE id='<RUN_ID>';" # SET_ID
    sqlite3 "$DB" "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.snapshot._0') FROM asset_sets WHERE id='<SET_ID>')) m, assets a WHERE a.id = json_extract(m.value,'\$.rawValue') AND a.original_path LIKE '%/card2/%';"
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
- Step 10: **fails if** the context menu does not contain exactly the current
  star toggle plus the three import verbs (four items total), offers any
  extras, or if pressing `Cull stacks` neither creates
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
  skipped)` / `2 files skipped` / `Start culling`.
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
  executable Step 4 above now uses the live-proven `AXLink` role.
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
