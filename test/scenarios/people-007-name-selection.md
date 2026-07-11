# people-007-name-selection: Name Selection sheet writes only on submit; Dismiss writes nothing

**What this covers**: the People "Name selection" gesture — select photos in
the grid, open the "Name Selection" sheet, and submitting it calls
`confirmSelectedAssetsAsPerson`, which is the *only* thing in this flow that
writes `people`/`person_assets`. The button is disabled until
`canConfirmSelectedPerson` is true; its candidate asset IDs are the batch
selection if one exists, else the single `selectedAssetID`
(`AppModel.selectedPeopleCandidateAssetIDs`,
`Sources/TeststripApp/AppModel.swift:3183-3189`). Also covers "Dismiss face
review," which removes assets from the review queues
(`dismissed_face_assets`) without ever touching `people`/`person_assets`.

## Pre-state
```bash
./script/download_face_model.sh
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. **Baseline** (confirm-before-write negative):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # P0
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # L0
   sqlite3 "$DB" "SELECT count(*) FROM dismissed_face_assets;"  # D0
   ```
2. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library (or ⌘3
   People, whichever hosts the grid the "Name Selection" gesture reads from —
   confirm via `PeopleView`'s pendingPeoplePanel, which reads
   `model.canConfirmSelectedPerson` regardless of `selectedView`).
3. **Single-selection candidate path.** Click one grid thumbnail to select it
   (no batch/⌘-click). Assert `model.canConfirmSelectedPerson` is now true
   (button "Name selection" is enabled — `AXButton` with label "Name
   selection" is not `AXDisabled`).
4. **Confirm-before-write on select alone:**
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # still P0
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # still L0
   ```
   **Fails if** either rose from mere selection.
5. Press "Name selection" — opens the "Name Selection" sheet
   (`nameSelectionSheet`, `PeopleView.swift:261-282`). Assert the sheet's
   "Create Person" button is `AXDisabled` while its text field is empty
   (`isPrimaryEnabled`, SheetScaffold).
6. **Confirm-before-write on opening the sheet:** re-run step 4's queries —
   still `P0`/`L0`. Opening the sheet must not write.
7. Type a name into the field (`script/ax_drive.sh type --contains "Person
   name" --text "Test Person"`); press "Create Person" (or Return, which is
   bound to `.keyboardShortcut(.defaultAction)` on the same button).
8. Assert the write:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # P0 + 1
   sqlite3 "$DB" "SELECT * FROM people WHERE name='Test Person';"
   sqlite3 "$DB" "SELECT count(*) FROM person_assets WHERE person_id=(SELECT id FROM people WHERE name='Test Person');"
   ```
   The last count must equal the number of photos that were selected (1, in
   the single-selection case).
9. **Batch-selection candidate path.** Clear the selection, then ⌘-click (or
   shift-click) 2+ thumbnails to build a batch selection. Repeat steps 5-8
   with a distinct name ("Test Person Two"); assert the resulting
   `person_assets` row count equals the batch size, not 1 — proving
   `selectedPeopleCandidateAssetIDs` preferred the batch over any stale single
   selection (`AppModel.swift:3184-3188`: `selectedBatchAssetIDsInCatalogOrder`
   wins when non-empty).
10. **Dismiss face review, no write.** Select a photo that still carries an
    unnamed/undismissed face signal (not one just confirmed above). Press
    "Dismiss face review" (enabled per `canDismissSelectedFaceReviewAssets`,
    same candidate-ID logic). Assert:
    ```bash
    sqlite3 "$DB" "SELECT count(*) FROM people;"          # unchanged from step 9's end value
    sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # unchanged
    sqlite3 "$DB" "SELECT count(*) FROM dismissed_face_assets;"  # D0 + (assets dismissed)
    ```
    **Fails if** Dismiss wrote to `people`/`person_assets`, or failed to add
    the expected `dismissed_face_assets` rows.

## Expected
- Steps 4 & 6: zero writes from selection or sheet-opening alone — the
  confirm-before-write invariant's negative assertion.
- Step 5: "Create Person" disabled on empty name. **Fails if** it's press-able with
  an empty/whitespace-only name.
- Step 8: exactly one new `people` row and `person_assets` rows matching the
  selection's asset count. **Fails if** the count is off by any amount, or no
  row was written despite a non-empty name and non-empty selection.
- Step 9: batch selection's link count equals the batch size (not 1).
  **Fails if** only the last-clicked asset was linked — that would mean the
  view fell back to `selectedAssetID` instead of the batch.
- Step 10: `dismissed_face_assets` grows by exactly the dismissed set's size;
  `people`/`person_assets` are untouched. **Fails if** Dismiss silently wrote
  a person or over/under-dismissed.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `canConfirmSelectedPerson` and `canDismissSelectedFaceReviewAssets` share
  identical gating logic (`catalog != nil && !selectedPeopleCandidateAssetIDs.isEmpty`)
  — neither checks that the selection actually has unnamed face signals. A
  selection of already-confirmed photos can still open "Name Selection" and
  confirm again; this card doesn't probe that edge, but it's worth flagging
  if seen live.
- **Attach-to-existing ruling (2026-07-10, Jesse):** typing a name that
  exactly matches (trimmed, case-insensitive — same `COLLATE NOCASE`
  normalization `showPersonPhotos`'s `person:` filter uses) an existing
  `people.name` attaches the selection to that existing person instead of
  minting a new one — `confirmSelectedAssetsAsPerson` now resolves the
  target person ID via `existingPersonID(matchingName:)`
  (`AppModel.swift`) before falling back to the caller-supplied `id`. Step
  9's "distinct name" assumption still holds (new name -> new person), but a
  step reusing a name from step 8 would now grow `person_assets` for the
  *existing* row rather than adding a `people` row — covered at the unit
  level by
  `AppModelTests.testConfirmSelectedAssetsAsPersonWithExactNameMatchAttachesToExistingPerson`
  and `testConfirmClusterSuggestionWithExactNameMatchAttachesToExistingPerson`;
  not re-driven live here.
- `dismissFaceAssets` (the model call behind "Dismiss face review") also
  deletes matching `person_assets`/`person_faces` rows for the dismissed
  asset (`CatalogRepository.swift:904-917`) — so if step 10's selected photo
  happens to already be linked to a person, dismissing it will remove that
  link. Pick an asset with no prior person link for a clean negative
  assertion, or explicitly account for the deletion if not.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Confirm-before-write
wiring confirmed by static read of `Sources/TeststripApp/AppModel.swift:3175-3225`
(`canConfirmSelectedPerson`, `selectedPeopleCandidateAssetIDs`,
`confirmSelectedAssetsAsPerson`) and `PeopleView.swift:261-291` (sheet).
Needs a human-present re-run. All SQL in this card was run headlessly against
a seeded --faces catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift).
