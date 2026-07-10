# cull-003-rating-label-flag-keys: The full keyboard decision vocabulary — ratings, color labels, flags — each its own undo step and toast

**What this covers**: as a photographer culling a shoot, I want every
decision keystroke (1-5 rate, 0 clear rating, 6/7/8/9/v color labels, `-`
clear label, P/X/U pick/reject/clear-flag) to write immediately, auto-advance
to the next photo, show a toast confirming what happened, and be individually
undoable with ⌘Z — not batched with neighboring keystrokes. Covers:
- Shortcut-to-key mapping: `Sources/TeststripApp/AppModel.swift:237-262`
  (`CullingShortcut.init(key:)` — `0`-`5` rate, `6`=red, `7`=yellow,
  `8`=green, `9`=blue, `v`=purple, `-`=clear label, `p`=pick, `x`=reject,
  `u`=clearFlag).
- Dispatch + auto-advance: `applyCullingShortcut` (`:5414-5458`) routes each
  through `applyCullingCommandAndAdvance` (`:5542-5552`), which snapshots
  `lastCullingMetadataDecision` from the *pre-change* asset, applies the
  change, and advances to the next asset only if the selection didn't already
  move (it doesn't, for rating/label/flag commands).
- Per-keystroke writes and undo grouping: `setRatingForSelectedAsset`
  (`:5921-5928`, label `"Rating"`), `setColorLabelForSelectedAsset`
  (`:5961-5965`, label `"Color label"`), `setFlagForSelectedAsset`
  (`:5930-5939`, label `"Flag"`) — each calls `updateSelectedAssetMetadata`
  for a *single* asset, so each keystroke is its own one-asset undo group
  (distinct from the multi-asset `setFlagForSelectedAssets`/stack-decision
  paths used elsewhere).
- Toast text and decay: `CullDecisionToastPresentation.init`
  (`Sources/TeststripApp/CullFilmstripPresentation.swift:42-58`) builds
  `"<symbol> <filename> <lowercased decision> — ⌘Z undoes"`; the view fades
  it after a 2s `Task.sleep` (`Sources/TeststripApp/
  LibraryGridView.swift:3887-3902`, `showDecisionToastThenFade`).
  Decision text strings: `cullingMetadataDecisionText`
  (`AppModel.swift:5569-5583`) — `"Rated N"`/`"Cleared rating"`,
  `"<Color> label"`/`"Cleared label"`, `"Picked"`/`"Rejected"`/`"Cleared
  flag"`.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Fallback: `script/vm_scenario_run.sh setup && sync smoke && launch smoke`,
then `vm_scenario_run.sh ax ...` / `sql smoke ...`.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull (lands in
   the Cull loupe). Cycle scope to "All" with `S` so auto-advance always has
   a next photo available regardless of flag/rating state.
2. Record the currently-selected asset id (`ID1`):
   ```bash
   ID1=$(sqlite3 "$DB" "SELECT id FROM assets ORDER BY rowid LIMIT 1;")   # cross-check against the loupe filename
   ```
3. Press `3`. Assert `ID1`'s rating becomes 3 and the loupe advances to a
   new asset (`ID2`):
   ```bash
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.rating') FROM assets WHERE id = '$ID1';"
   ```
   Assert the toast (`script/ax_drive.sh wait --contains "Rated 3"`) reads
   `★ <ID1's filename> rated 3 — ⌘Z undoes` — note the toast lowercases only
   the decision fragment ("Rated 3" -> "rated 3"), not the filename.
4. Press `0` on `ID2`. Assert rating clears to NULL/0 and toast reads
   `○ <ID2 filename> cleared rating — ⌘Z undoes`.
5. On the next four assets (`ID3`-`ID6`, one per keystroke, each auto-
   advancing), press `6`, `7`, `8`, `9` in turn. Assert:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.colorLabel') FROM assets WHERE id IN ('$ID3','$ID4','$ID5','$ID6');"
   ```
   reads `red`/`yellow`/`green`/`blue` respectively (confirm the actual
   `ColorLabel.rawValue` casing/spelling against a live catalog — the source
   only guarantees the enum case names `red`/`yellow`/`green`/`blue`/
   `purple`, not the JSON string verbatim).
6. Press `v` on `ID7`. Assert its color label is `purple`.
7. Press `-` on `ID7` again is wrong (it already advanced) — instead press
   `-` on the *next* asset (`ID8`, freshly labeled by nothing). Since `ID8`
   has no label yet, clearing is a no-op write (metadata unchanged) — instead
   re-select `ID7` (⌘⇧[ or click its tile) and press `-` there. Assert
   `ID7`'s color label clears to NULL and the toast reads `○ <ID7 filename>
   cleared label — ⌘Z undoes`.
8. Select three still-undecided assets (`ID9`, `ID10`, `ID11`) and press
   `P`, `X`, `U` respectively (one keystroke per asset, auto-advancing
   between). Assert:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN ('$ID9','$ID10','$ID11');"
   ```
   `ID9` -> `pick`, `ID10` -> `reject`. For `ID11`, first give it a flag
   (e.g. click it and press `P` first, confirm `pick`), *then* press `U` on
   it and assert the flag clears to NULL — `U` is `clearFlag`, only
   meaningful as a follow-up to an existing flag. Toast for the `U` press
   reads `○ <ID11 filename> cleared flag — ⌘Z undoes`.
9. Confirm toast auto-fade: immediately after step 8's last keystroke,
   `script/ax_drive.sh wait --contains "cleared flag"` should succeed; wait
   3+ real seconds (past the 2s `Task.sleep` fade delay) and confirm
   `script/ax_drive.sh find --contains "cleared flag"` now fails (no longer
   present in the AX tree).
10. **Undo, one keystroke at a time.** Starting from the last write (the `U`
    on `ID11`) and working backward through every keystroke in steps 3-8 (10
    total decisions: rating x2, color label x5, flag x3), press ⌘Z once per
    keystroke and assert after each press that exactly that one asset's
    field reverts to its pre-keystroke value while every other already-
    undone-or-not-yet-undone asset is unaffected:
    ```bash
    sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.rating'), json_extract(metadata_json,'\$.colorLabel'), json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN ('$ID1','$ID2','$ID3','$ID4','$ID5','$ID6','$ID7','$ID9','$ID10','$ID11');"
    ```
    after each ⌘Z, confirming a strict one-field-at-a-time reversal in
    exact reverse chronological order.

## Expected
- Steps 3-8: every keystroke writes the correct field on exactly the asset
  that was selected when it was pressed, and auto-advances. **Fails if** a
  write lands on the wrong asset (stale selection) or auto-advance skips more
  than one asset.
- Toast text matches `"<symbol> <filename> <lowercased decision> — ⌘Z
  undoes"` verbatim for every keystroke type exercised (rating, clear
  rating, color label, clear label, pick, reject, clear flag). **Fails if**
  any decision text or symbol (★/○/✓/✕/●) doesn't match
  `CullDecisionToastPresentation.symbol(for:)`'s prefix rules.
- Step 9: toast is present within the 2s window and gone after it (the
  `easeOut(duration: 0.3)` fade should have completed well before the 3s
  check). **Fails if** the toast is still in the AX tree after 3+ seconds,
  or vanishes immediately (fade duration regression either direction).
- Step 10: each ⌘Z reverts exactly one keystroke's field on exactly one
  asset, in exact reverse order. **Fails if** any two keystrokes share an
  undo group (one ⌘Z reverts more than one asset/field), or if the order is
  wrong.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `ColorLabel` (`Sources/TeststripCore/Domain/Metadata.swift:3-9`) is a plain
  `String`-backed enum with cases `red`/`yellow`/`green`/`blue`/`purple` and
  no custom `Codable` remapping, so the JSON value should equal the rawValue
  verbatim (`"red"`, not `"Red"`) — confirmed by reading the enum, not dry-run
  against a live catalog.
- Step 7 is written around a real trap: pressing `-` on an asset with no
  existing label is a legitimate no-op write (same before/after metadata),
  which `updateSelectedAssetMetadata` may or may not still record as an undo
  step depending on whether it diffs before recording — worth confirming
  live rather than assuming either way; this card sidesteps it by only
  asserting the clear-after-a-real-label case.
- `--smoke`'s 11/24 pre-flagged baseline means some of `ID3`-`ID11` may
  already carry a flag/rating from the seed; the live run must pick asset ids
  that are actually in the desired starting state (verify with a `SELECT`
  before committing to specific ids in the script), not assume row order
  lines up with flag state.
- This card doesn't test the multi-select batch paths (`setRatingForSelectedAssets`
  etc.) — those are grid-only, exercised implicitly by
  `cull-pass-scope-and-undo.md`'s stack Return-promote path, and out of scope
  here (single Cull-loupe-focused keystroke coverage only).

## Run status
UNRUN — SQL not yet dry-run against a live catalog; needs human-present
execution per test/scenarios/README.md.
