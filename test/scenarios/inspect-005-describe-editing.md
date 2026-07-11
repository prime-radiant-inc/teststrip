# inspect-005-describe-editing: Describe tab editing controls, draft protection, and batch text-field apply

**What this covers**: the Describe tab's authoring surface — rating/flag/
label buttons (with the multi-select batch note), keyword chip
add/remove/dedupe via comma-split text, caption/creator/copyright
commit-on-submit-to-nil semantics, the unsaved-draft protection against a
concurrent catalog refresh clobbering in-progress keystrokes, and — per
Jesse's ruling (2026-07-10) — keywords/caption/creator/copyright now
batch-apply across a multi-select exactly like rating/flag/label: keyword
edits (the Keywords field, chip removal, and "accept suggestion") APPEND
per asset with per-asset dedup so unrelated existing keywords on other
selected assets survive; caption/creator/copyright OVERWRITE across the
whole batch. One undo group covers the whole batch per gesture, following
`updateSelectedAssetsMetadata`'s existing pattern. Prior to this ruling the
text fields silently single-asset-applied during a multi-select — that
asymmetry is now fixed, not merely documented.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
SRC_A=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
SRC_B=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1 OFFSET 1;")
```

## Steps

### Rating/flag/label buttons (single selection)
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 Library; select `$SRC_A`;
   ⌥⌘2 for Describe.
2. Press "Rate 3" (`ax_drive.sh press --role AXButton --help "Rate 3"`).
   Assert `metadata_json` for `$SRC_A` now shows `"rating":3`.
3. Press "Pick" flag button (`--help "Pick"`). Assert `"flag":"pick"`.
4. Press the green label swatch (`--help "Green"`). Assert
   `"colorLabel":"green"`.
5. With a single asset selected, assert the "Rating, flag, and label apply to
   all N selected photos" note (`metadataControls`, `InspectorView.swift:899-903`)
   is **absent** (`model.selectedBatchAssetCount == 1`).

### Keyword chips
6. Type `"sunset, beach,sunset"` into the Keywords field and submit (Return).
   Assert the chip list shows exactly `sunset` and `beach` — comma-split
   (`Self.keywords(from:)`) and deduped (case/whitespace-insensitive per
   `keywordKey`, verify exact dedup key logic against
   `AppModel.swift` around `Self.keywords`/`Self.keywordKey`). Confirm on
   disk: `sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE
   original_path='$SRC_A';"` shows `"keywords":["sunset","beach"]` (order
   per the split, not alphabetized).
7. Click the X on the `beach` chip (`ax_drive.sh press --role AXButton --help
   "Remove beach"`, `InspectorView.swift:1032-1056`). Assert the chip is gone
   and `metadata_json` keywords now shows only `["sunset"]`.

### Caption/creator/copyright: commit-on-submit, empty → nil
8. Type "A quiet dock at dusk" into the Caption field and press Return
   (`onSubmit`, `InspectorView.swift:1156-1177`). Assert
   `metadata_json.caption == "A quiet dock at dusk"`.
9. Clear the Caption field entirely (select-all, delete) and press Return.
   Assert `metadata_json` has **no** `"caption"` key (nil, not `""`) —
   `Self.portableText(from:)` (`AppModel.swift:6306-6310`,
   `setCaptionForSelectedAsset`) is expected to map empty string to nil;
   confirm the exact nil-vs-empty-string serialization in the JSON dump.
10. Repeat for Creator and Copyright: type a value, submit, confirm it's
    stored; clear and submit, confirm the key is absent/null rather than
    `""`.
11. Also test commit-on-blur (not just Return): type a new caption, then
    click elsewhere in the panel (e.g. the Creator field) without pressing
    Return first. Assert the caption still commits — or, if it does *not*
    commit on blur and only the explicit checkmark button
    (`InspectorView.swift:1167-1175`) or Return commits, document that as
    the actual behavior (don't assume commit-on-blur without observing it;
    the `TextField.onSubmit` wiring shown in the source only fires on
    Return/checkmark-click, not on focus loss — flag this in Sharp edges if
    confirmed).

### Draft protection against concurrent catalog refresh
12. Type a partial, uncommitted edit into the Caption field (do **not**
    press Return) — e.g. append " — draft edit" to the existing caption.
13. From a second terminal, trigger a catalog-external metadata change to
    the same asset's *other* fields while the draft is pending, e.g.:
    ```bash
    sqlite3 "$DB" "UPDATE assets SET metadata_json = json_set(metadata_json, '\$.rating', 4), updated_at = strftime('%s','now') WHERE original_path = '$SRC_A';"
    ```
    (A worker write is the realistic trigger in production; a direct SQL
    UPDATE simulates the same "catalog changed underneath the open draft"
    condition without needing a live worker task.) Trigger a UI refresh path
    if one exists (switch tabs and back, or wait for the app's normal
    refresh timer) so the model observes the external change.
14. Assert the uncommitted Caption text is **not** clobbered — the draft
    ("— draft edit" still present, uncommitted) survives the external
    refresh, per `InspectorMetadataDraft.sync(to:)`'s `guard
    !hasUnsavedChanges else { return }` (`InspectorView.swift:1357-1369`):
    the draft only re-syncs from the catalog when the current draft *matches*
    the last-synced metadata; a draft the user is still editing is left
    alone even though the catalog changed. Confirm the rating change (4) is
    still visible elsewhere in the UI (e.g. Info tab summary) even though
    the caption draft was preserved — the protection is field-independent to
    the whole draft struct, not per-field (`InspectorMetadataDraft` bundles
    keywords/caption/creator/copyright as one struct that either fully
    resyncs or fully doesn't, `InspectorView.swift:1340-1382`).
15. Now press Return to commit the draft caption. Assert it writes
    successfully and the resulting `metadata_json` has both the committed
    caption (with "— draft edit") and the externally-set rating of 4 (the
    commit only touches the caption field via `updateSelectedAssetMetadata`'s
    targeted mutation, not a wholesale overwrite of the asset).

### Batch text-field apply (rating parity probe)
16. In the Library grid, multi-select `$SRC_A` and `$SRC_B` (⌘-click both
    thumbnails). Confirm `model.selectedBatchAssetCount == 2` (indirectly:
    both the rating/flag/label note and the new keywords/caption/creator/
    copyright note should now read "2").
17. **Rating (unchanged reference case)**: press "Rate 4" on the Describe
    tab. Assert **both** `$SRC_A` and `$SRC_B` now show `"rating":4` in
    `metadata_json` — `setRatingForSelectedAssets` iterates
    `currentManualSelectionAssetIDs` (`AppModel.swift`,
    `updateSelectedAssetsMetadata`), recording one change group labeled
    `"Rating · 2 photos"` (`photoCountDescription` — see inspect-009 for the
    undo-label assertion in detail).
18. **Caption/creator/copyright now batch-apply too**: with the same
    two-asset multi-select still active, type a caption into the Caption
    field and submit. Assert **both** `$SRC_A` and `$SRC_B` now carry the
    same caption in `metadata_json` — `setCaptionForSelectedAssets`
    (`AppModel.swift`) now calls `updateSelectedAssetsMetadata` (plural),
    overwriting the caption across the whole batch in one undo group.
    Repeat for Creator and Copyright.
19. **Keywords now batch-apply with per-asset append+dedup, not overwrite**:
    ensure `$SRC_A` and `$SRC_B` start with different existing keywords
    (e.g. seed one with `unique-a`, the other with `unique-b`, via the
    single-selection Keywords field before re-selecting both). With both
    selected, type a new keyword (e.g. `both`) into the Keywords field and
    submit. Assert **both** assets now include `both` in their keyword
    list, and each asset's prior distinct keyword (`unique-a` / `unique-b`)
    is still present — `setKeywordTextForSelectedAssets` appends+dedupes
    per asset when a batch is active rather than overwriting each asset's
    list with the typed text (that overwrite-on-batch behavior only kicks
    in for a single-asset selection, matching the field's pre-existing
    single-asset semantics — see
    `AppModelTests.testBatchKeywordTextAppendsPerAssetDedupedWithoutClobberingOtherAssetsKeywords`
    for the exact unit-level assertion). Also confirm: removing a keyword
    chip while both are selected (`removeKeywordFromSelectedAssets`) removes
    that keyword from **both** assets.

## Expected
- Steps 2-4: rating/flag/label writes land in `metadata_json` exactly as
  pressed. **Fails if** any button is a no-op or writes the wrong value.
- Step 5: no batch note for a single selection. **Fails if** the note
  renders regardless of selection count.
- Step 6-7: comma-split + dedup on submit; chip removal writes a shortened
  keyword list. **Fails if** duplicates survive, or the split doesn't
  trim/dedupe, or chip-removal doesn't hit the catalog.
- Step 9-10: cleared fields serialize to nil (absent from `metadata_json`
  JSON), not `""`. **Fails if** an empty string is written instead of the
  field being omitted — this matters for XMP round-tripping too.
- Step 11: document the actual commit trigger (Return/checkmark vs. also
  blur) — **Fails if** the card asserts blur-commits without having actually
  observed it; report the real behavior either way.
- Step 14: an in-progress, uncommitted caption edit survives a concurrent
  external catalog write to a different field. **Fails if** the draft is
  silently overwritten (data loss for the user's unsaved keystrokes) — this
  is the point of `InspectorMetadataDraft`'s dirty-tracking and a regression
  here is a real bug, not a cosmetic one.
- Step 15: the eventual commit only touches the caption field; the
  externally-set rating survives. **Fails if** committing the draft
  reverts the rating (implies the draft's commit path does a full-metadata
  overwrite instead of a targeted field mutation).
- Step 17: rating batch-applies to both selected assets (unchanged reference
  case). **Fails if** it doesn't.
- Step 18: caption/creator/copyright now batch-apply (overwrite) to both
  selected assets in one undo group each. **Fails if** only the single
  inspected asset is updated — that would mean the ruling's overwrite path
  regressed back to the old single-asset scoping.
- Step 19: a batch keyword edit appends the new keyword to every selected
  asset while leaving each asset's other, distinct keywords untouched — not
  a wholesale replace of every asset's keyword list with the typed text.
  **Fails if** either asset loses its pre-existing distinct keyword, or if
  only one asset receives the new keyword.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Batch-vs-single asymmetry resolved (2026-07-10 ruling)**: keywords/
  caption/creator/copyright now batch-apply via new plural
  `AppModel` methods (`setKeywordTextForSelectedAssets`,
  `removeKeywordFromSelectedAssets`, `acceptSuggestedKeywordForSelectedAssets`,
  `acceptSuggestedCaptionForSelectedAssets`, `setCaptionForSelectedAssets`,
  `setCreatorForSelectedAssets`, `setCopyrightForSelectedAssets`), mirroring
  the pre-existing `setRatingForSelectedAssets`/`setFlagForSelectedAssets`/
  `setColorLabelForSelectedAssets` family. The old singular
  `...ForSelectedAsset` methods still exist unchanged (still used by other
  callers outside the Describe panel) — only `InspectorView.swift`'s
  `portableTextControls` was repointed to the plural family. The
  "Keywords, caption, creator, and copyright apply to all N selected
  photos" note (`portableTextControls`) now makes the batch behavior
  visible, closing the UI gap the previous version of this card flagged.
- Keyword batch semantics are asymmetric by field intent, not a bug: the
  free-text Keywords field OVERWRITES for a single-asset selection (typing
  an empty string clears keywords — this is unchanged, existing behavior)
  but APPENDS+dedupes per asset once 2+ assets are selected
  (`setKeywordTextForSelectedAssets` branches on
  `currentManualSelectionAssetIDs.count > 1`). This avoids the far worse
  failure mode of a batch edit silently wiping every other selected asset's
  unrelated keywords down to whatever the currently-inspected asset had
  typed into its field.
- Step 13's direct-SQL simulation of a concurrent catalog write is a stand-in
  for a real worker write; if a live worker-driven write (e.g. evaluation
  completing and updating suggested keywords) is available as a faster
  trigger during a real run, prefer it — but the SQL approach is a valid
  probe of the same code path (`InspectorMetadataDraft.sync(to:)` is called
  from `.onChange(of: asset.metadata)`, which fires regardless of what
  produced the change, `InspectorView.swift:1027-1029`).
- Step 11's blur-commit behavior is genuinely unconfirmed from static
  reading — SwiftUI's plain `TextField` with `.onSubmit` does not fire on
  focus loss by default, so the card's default expectation should be "does
  NOT commit on blur" unless live driving shows otherwise; don't let a
  cached assumption from other apps' text fields leak in here.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed
statically: `Sources/TeststripApp/InspectorView.swift`
(`metadataControls`, `ratingButtons`, `flagButtons`, `labelButtons`, the
rating/flag/label batch note; `portableTextControls`, `keywordChips`,
`metadataTextField` commit wiring, the new keywords/caption/creator/
copyright batch note), `InspectorMetadataDraft.sync(to:)` (the
dirty-tracking guard), `Sources/TeststripApp/AppModel.swift`
(`setRatingForSelectedAssets`/`setFlagForSelectedAssets`/
`setColorLabelForSelectedAssets` and the new
`setKeywordTextForSelectedAssets`/`removeKeywordFromSelectedAssets`/
`acceptSuggestedKeywordForSelectedAssets`/
`acceptSuggestedCaptionForSelectedAssets`/`setCaptionForSelectedAssets`/
`setCreatorForSelectedAssets`/`setCopyrightForSelectedAssets`, all now
plural/batch, sharing `updateSelectedAssetsMetadata`'s one-undo-group
scoping). Unit-level coverage:
`AppModelTests.testBatchKeywordTextAppendsPerAssetDedupedWithoutClobberingOtherAssetsKeywords`,
`testBatchKeywordTextStillReplacesForASingleFocusedAsset`,
`testBatchRemoveKeywordRemovesFromEverySelectedAsset`,
`testBatchCaptionCreatorCopyrightOverwriteWholeSelectionInOneUndoGroup`,
`testBatchAcceptSuggestedKeywordAppendsToEverySelectedAssetDeduped`. Needs a
human-present live re-run to confirm the AX-level steps above. All SQL in
this card was run headlessly against a seeded --smoke
catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift).
