# cull-026-tentative-never-commits: a tentative ✨ AI reject counts as undecided everywhere, is never relocated/trashed, and an explicit gesture — confirming it or overriding it — is what actually commits it

**What this covers**: the culling-flow-shell's central invariant (CLAUDE.md's
"Auto-apply with provenance" rule) applied end-to-end: a machine-proposed
reject flag lands in the catalog immediately but tagged `origin=ai`
(`aiUnconfirmedFields` contains `flag`), and until an explicit user gesture
touches it, it must be indistinguishable from "undecided" on every
confirmed-facing surface — the HUD's pick/reject/undecided counts, the
progress bar, and the Move Rejects to Trash preflight — even though its raw
`metadata_json.flag` already reads `reject`. This card seeds two such
tentative rejects, proves both are inert everywhere a real decision would
matter, then resolves them the two ways a user actually can: re-asserting
the same decision (confirms it) and choosing the opposite decision
(overrides it) — asserting both land as `origin=user` with no ghost
tentative state left behind, and only the confirmed one becomes
relocation-eligible.

Source (re-verified against the working tree on this branch, **2026-07-16**):
- **Provenance model**: `AssetMetadata.aiUnconfirmedFields`
  (`Sources/TeststripCore/Domain/Metadata.swift:36`) and
  `confirmedProjection` (`:55-65`) — a field listed in
  `aiUnconfirmedFields` reads as absent (`flag: nil`) in the confirmed
  projection regardless of its raw value. `MetadataField.flag.rawValue`
  is `"flag"` (`:16-21`).
- **Undecided-everywhere**: `AppModel.cullUndecidedCount`
  (`AppModel.swift:6549-6562`) filters on `confirmedProjection.flag == nil`
  explicitly (doc comment: "A tentative AI flag ... counts as undecided
  too — it isn't a user decision yet"). The HUD's pick/reject counts come
  from `cullingProgressSummary` → `cullingDecisionCounts()` →
  `cullingDecisionCount(flag:repository:)` (`:2701-2736`), which queries
  **`assetCount(ids:confirmedFlag:)`**
  (`Sources/TeststripCore/Catalog/CatalogRepository.swift:563-582`) — SQL
  `json_extract(metadata_json,'$.flag') = ? AND NOT EXISTS (SELECT 1 FROM
  json_each(metadata_json,'$.aiUnconfirmedFields') WHERE json_each.value =
  ?)` (the `confirmedFieldClauseSQL`, `CatalogRepository.swift:3017-3024`) —
  a tentative reject is structurally excluded from `rejectCount`. The HUD
  renders this as `sessionClusterText`
  (`CullHUDPresentation.swift:54-56`, "✓ N · ✕ M · K left") with an explicit
  `.accessibilityLabel("\(pickCount) picks, \(rejectCount) rejects,
  \(undecidedCount) left")` (`LibraryGridView.swift:4176-4182`). The
  progress bar's fill fraction is `reviewedCount / totalCount` where
  `reviewedCount = pickCount + rejectCount`
  (`AppModel.swift:126-128`) — so a tentative reject also doesn't move the
  progress bar, only `undecidedCount` (`= totalCount - pickCount -
  rejectCount`, `CullHUDPresentation.swift:34`) absorbs it.
- **Move-rejects exclusion**: `rejectRelocationScope(destinationFolder:)`
  (`AppModel.swift:11690-11734`) first queries raw `flag(.reject)` matches
  (`:11695-11698`, which **does** include tentative rejects — the raw SQL
  predicate doesn't know about provenance), then explicitly skips any match
  whose `aiUnconfirmedFields.contains(.flag)` inside the per-asset loop
  (`:11712-11714`: "A tentative AI reject ... is excluded outright — it
  must never be moved or trashed. This is the safety-critical guard.").
  Critically, this skip is **silent** — it increments none of
  `unavailableCount`/`alreadyInDestinationCount`/`outsideScopeCount`, so the
  sheet's own count reconciliation gives no visible hint that N rejects
  were excluded for being tentative (contrast with `outsideScopeCount`,
  which the sheet **does** disclose, per its own doc comment,
  `AppModel.swift:1501-1505`). `RejectRelocationPreflight.moveCount`
  (`:1533`, `= plans.count`) and the trash-mode sheet's primary button title
  `"Move \(preflight.moveCount) to Trash"`
  (`RejectRelocationSheetPresentation.init`, `LibraryGridView.swift:5248-
  5273`, trash branch at `:5259-5264`) both derive from this
  already-filtered `scope`. Note the confirm-toggle's own label is a
  *different*, mode-agnostic string —
  `Toggle(preflight.confirmationText, isOn: $isRejectRelocationConfirmed)`
  (`LibraryGridView.swift:3442`) always reads `"Move \(moveCount) reject
  \(moveCount == 1 ? "photo" : "photos") to Trash"` (`RejectRelocationPreflight
  .confirmationText`, `AppModel.swift:1537-1539`, using `trashDisplayFolder`'s
  last path component "Trash") even in trash mode — it does **not** say
  "Move N to Trash" the way the primary button does. `moveRejectsToTrash(_:)`
  (`AppModel.swift:11963`) iterates **only** `zip(preflight.assetIDs,
  preflight.plans)` (mirrors the folder-mode loop at `:11887`) — it never
  re-queries the catalog, so an asset that never made it into the preflight
  structurally cannot be moved by this call, independent of catalog state
  at call time. Trash mode `deleteAsset`s the catalog row for whatever it
  *does* move (per `app-017-move-rejects-to-trash.md`'s citation of the
  same mechanism) — a row surviving after the move is itself proof it was
  never touched.
- **Confirm/override provenance rule**: `setFlagForSelectedAsset(_ flag:)`
  (`AppModel.swift:7027-7040`) unconditionally does
  `metadata.aiUnconfirmedFields.remove(.flag)` regardless of whether the new
  value matches the old one — comment at `:7031-7033`: "agreeing with (or
  overriding) a tentative AI flag must confirm it, not just possibly change
  its value." The write isn't skipped as a no-op even when the flag value
  is unchanged, because `aiUnconfirmedFields` itself changed
  (`updateSelectedAssetMetadata`'s `updatedMetadata != originalAsset
  .metadata` guard, `:7751`, compares the whole struct). A confirmed flag
  is sidecar-eligible: `syncMetadataSidecar`
  (`AppModel.swift:8171-` ff.) queues (worker present) or writes
  synchronously the `.xmp` sidecar's `ts:Pick` attribute
  (`Sources/TeststripCore/Metadata/XMPPacket.swift:73`) from
  `metadata.confirmedProjection`.
- **The separate "remove/decline" gesture exists in the model but has no
  wired UI for flags.** `AppModel.removeAIField(_:for:)`
  (`AppModel.swift:8034-8058`) is the literal CLAUDE.md "or removes it"
  path — clears the field and records `removed_ai_labels`
  (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:247-255`) keyed
  by the rejected value (`"pick"`/`"reject"` for a flag,
  `AppModel.swift:8060-8071`) "so a future promoter (autopilot) can
  recognize and skip re-proposing that same value." Grepping every call
  site: the **only** UI wiring is for `.caption`
  (`InspectorView.swift:1169`) — nothing in the shipped culling-flow-shell
  calls `removeAIField(.flag, for:)`. This card therefore tests the two
  gestures that **are** wired for a pick/reject flag — re-asserting the
  same decision (`P`/`X` again) and choosing the opposite one — both of
  which go through `setFlagForSelectedAsset`, not `removeAIField`, and so
  neither writes a `removed_ai_labels` row. See Sharp edges.
- **Fixture and seeding gap**: no existing `TeststripBench` seed command
  produces a pre-flagged tentative-AI asset (`SmokeCatalogSeeder`'s formula,
  `Sources/TeststripBench/SmokeCatalogSeeder.swift:145-147`:
  `flag: index.isMultiple(of: 5) ? .reject : (index.isMultiple(of: 3) ?
  .pick : nil)` — always a confirmed flag, `aiUnconfirmedFields` never
  set). Per `test/scenarios/README.md`'s Fixture-status convention
  ("Where no seed command produces that fixture yet, the card says so
  explicitly"), this card patches the local `smoke` seed template directly
  before launch (Pre-state below) rather than fabricating a live-Autopilot
  round trip that `cull-017-autopilot-review.md` already owns end-to-end.

## Pre-state
```bash
# Force a pristine local 'smoke' template, then seed it as usual.
rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/smoke/Teststrip"
script/vm_scenario_run.sh sync smoke

# Patch the LOCAL template (host-side, pre-launch — avoids any question of
# whether a live in-memory `assets` snapshot would need a reload() to see an
# out-of-band write): pick the first two catalog-order assets that launched
# unflagged (per the formula above, smoke-1 and smoke-2 are expected, but
# this is computed live, not hardcoded) and mark both a tentative AI reject.
TEMPLATE_DB="${TMPDIR:-/tmp}/teststrip-vm-seeds/smoke/Teststrip/catalog.sqlite"
read -r CONFIRM_ID OVERRIDE_ID < <(sqlite3 -separator ' ' "$TEMPLATE_DB" \
  "SELECT id FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL ORDER BY rowid LIMIT 2;" | tr '\n' ' ')
sqlite3 "$TEMPLATE_DB" "
  UPDATE assets SET metadata_json = json_set(metadata_json, '\$.flag','reject','\$.aiUnconfirmedFields',json('[\"flag\"]'))
  WHERE id IN ('$CONFIRM_ID','$OVERRIDE_ID');"

# Re-sync so the VM gets the patched template (seeding itself is a no-op
# since the template file already exists; the rsync steps in cmd_sync run
# unconditionally on every call).
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql smoke "..."
```
**Note**: this mutates the shared local `smoke` seed template for the rest
of the session. A card run afterward that depends on the pristine
"11/24 flagged, 0 tentative" `--smoke` baseline should `rm -rf
"${TMPDIR:-/tmp}/teststrip-vm-seeds/smoke/Teststrip"` first.

## Steps
1. **Confirm the seed landed as a genuine tentative AI reject** (live VM
   catalog, not just the template):
   ```bash
   script/vm_scenario_run.sh sql smoke \
     "SELECT id, json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag')
      FROM assets WHERE id IN ('$CONFIRM_ID','$OVERRIDE_ID');"
   ```
   Expect both rows: `reject|1`. Compute the raw-vs-confirmed reject split
   live:
   ```bash
   RAW_REJECT=$(script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject';")
   CONFIRMED_REJECT=$(script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject' AND NOT EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');")
   ```
   Assert `RAW_REJECT = CONFIRMED_REJECT + 2` (our two tentative rejects are
   the entire delta).
2. **HUD/progress counts it as undecided.** `ax wait-vended`; ⌘1 for Cull;
   `S` to "All frames". Assert the HUD's session-cluster text shows
   `CONFIRMED_REJECT`, not `RAW_REJECT`:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "$CONFIRMED_REJECT rejects"
   ```
   and that no rendering shows `RAW_REJECT` rejects anywhere in the HUD
   (`ax find --contains "$RAW_REJECT rejects"` must fail to match, unless
   `RAW_REJECT` and `CONFIRMED_REJECT` happen to coincide with some other
   unrelated count — sanity-check the two numbers actually differ before
   relying on this negative). Note both tentative ids are reflected only in
   `undecidedCount` (`totalCount - pickCount - rejectCount`), not visible as
   a distinct "N pending AI" figure — this card's job is to prove they're
   inert, not that they're separately surfaced.
3. **Locate each tentative asset in the loupe.** From the deck's start
   (press `Space` / `.nextPhoto` as needed, reading the HUD's filename
   `Text` each time — `ax find --role AXStaticText --contains
   "$CONFIRM_ID.jpg"` — smoke filenames are exactly `<id>.jpg`,
   `SmokeCatalogSeeder.swift:92-93`), confirm the loupe can reach
   `$CONFIRM_ID` and separately `$OVERRIDE_ID`. Do not assume a fixed
   starting position; poll for the filename match instead.
4. **Move Rejects to Trash preflight excludes both, silently.** With the
   loupe on any frame, open the Culling menu (`ax press --role
   AXMenuBarItem --label "Culling"`) and press "Move Rejects to Trash…"
   (`ax press --role AXMenuItem --contains "Move Rejects to Trash"`).
   Assert the confirmation sheet's primary button title is exactly `"Move
   $CONFIRMED_REJECT to Trash"` (`ax find --contains "Move $CONFIRMED_REJECT to Trash"`)
   — **not** `RAW_REJECT` — proving the preflight already excluded both
   tentative ids before any move happened. Assert the primary is disabled
   (AXEnabled false, per `app-010`/`app-017`'s confirm-gate pattern) until
   the checkbox is toggled — the checkbox's own label is the *other*,
   mode-agnostic phrasing (`"Move $CONFIRMED_REJECT reject
   \($CONFIRMED_REJECT == 1 ? "photo" : "photos") to Trash"`, per Source
   above — do not expect it to match "to Trash" with no leading text, and
   do not confuse it with the primary button's shorter title when matching):
   `ax press --role AXCheckBox --contains "to Trash"`. Then press the
   now-enabled primary button (`ax press --role AXButton --contains "Move
   $CONFIRMED_REJECT to Trash"`). `waitFor` the **"Move back"** button
   (`app-010`/`app-017`'s reliable completion marker — the banner's own
   text is a container label, not independently AX-findable).
5. **Ground truth after the move: both tentative originals are untouched,
   no relocation row.**
   ```bash
   script/vm_scenario_run.sh sql smoke \
     "SELECT id FROM assets WHERE id IN ('$CONFIRM_ID','$OVERRIDE_ID');"        # both still present (trash mode deletes rows it DOES move)
   script/vm_scenario_run.sh sql smoke \
     "SELECT count(*) FROM relocation_manifest_entries WHERE asset_id IN ('$CONFIRM_ID','$OVERRIDE_ID');"  # expect 0
   CONFIRM_SRC=$(script/vm_scenario_run.sh sql smoke "SELECT original_path FROM assets WHERE id='$CONFIRM_ID';")
   OVERRIDE_SRC=$(script/vm_scenario_run.sh sql smoke "SELECT original_path FROM assets WHERE id='$OVERRIDE_ID';")
   script/vm_scenario_run.sh shell "test -f '$CONFIRM_SRC' && echo present"
   script/vm_scenario_run.sh shell "test -f '$OVERRIDE_SRC' && echo present"
   ```
   Both files must still exist at their original recorded paths.
6. **Confirming leg**: navigate to `$CONFIRM_ID`'s frame (per step 3) and
   press `X` (reject) — re-asserting the *same* decision the AI already
   proposed. Assert (SQL, poll if the worker queues the write):
   ```bash
   script/vm_scenario_run.sh sql smoke \
     "SELECT json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag')
      FROM assets WHERE id='$CONFIRM_ID';"
   ```
   Expect `reject|0` — same value, now confirmed. Wait for the pending sync
   to clear for this asset (poll
   `SELECT status FROM metadata_sync_state WHERE asset_id='$CONFIRM_ID';`
   until it's no longer `pending` — note the column is `status`, not
   `state`; `CatalogMigrations.swift:30-37`, `cull-021`'s own citation of
   this table uses `state` and is stale on this point), then assert the
   `.xmp` sidecar carries `ts:Pick="reject"`:
   ```bash
   SIDECAR=$(dirname "$CONFIRM_SRC")/"$(basename "$CONFIRM_SRC" .jpg).xmp"
   grep -o 'ts:Pick="[^"]*"' "$SIDECAR"
   ```
7. **Overriding leg**: navigate to `$OVERRIDE_ID`'s frame and press `P`
   (pick) — declining the AI's reject proposal by choosing the opposite
   value. Assert:
   ```bash
   script/vm_scenario_run.sh sql smoke \
     "SELECT json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag')
      FROM assets WHERE id='$OVERRIDE_ID';"
   ```
   Expect `pick|0` — the AI's tentative reject is gone, replaced by a
   confirmed pick, no lingering tentative marker. Once synced, assert the
   `.xmp` sidecar carries `ts:Pick="pick"`.
8. **Re-open the preflight: only the confirmed reject is now eligible.**
   Repeat step 4's menu path. Assert the primary button now reads exactly
   `"Move 1 to Trash"` (`$CONFIRM_ID` is the only reject in the whole
   catalog at this point — the original confirmed rejects were trashed in
   step 4, `$OVERRIDE_ID` is now a pick, not a reject at all). This proves
   the confirm gesture in step 6 flipped `$CONFIRM_ID` from
   tentative-excluded to genuinely relocation-eligible, and that
   `$OVERRIDE_ID` stays excluded — now trivially, by flag value rather than
   by the tentative guard. Do not actually execute this second move (avoid
   double-trashing across the card); dismiss the sheet.

## Expected
- Step 1: **Fails if** either seeded asset doesn't read `reject|1`, or if
  `RAW_REJECT` doesn't exceed `CONFIRMED_REJECT` by exactly 2.
- Step 2: **Fails if** the HUD's rendered reject count is `RAW_REJECT`
  instead of `CONFIRMED_REJECT` — that would mean a tentative AI reject is
  being counted as a real decision, the core invariant this card exists to
  catch.
- Step 4: **Fails if** the preflight's button title names `RAW_REJECT`
  instead of `CONFIRMED_REJECT` — a tentative reject silently swept into a
  destructive/committing operation is the safety-critical regression this
  step guards.
- Step 5: **Fails if** either tentative asset's row is gone, if either
  original file is missing from its recorded path, or if any
  `relocation_manifest_entries` row references either id — any of these
  means a tentative-only flag drove a committing operation, which
  CLAUDE.md's invariants explicitly forbid.
- Step 6: **Fails if** the confirm gesture doesn't clear
  `aiUnconfirmedFields`, if the sidecar isn't eventually written, or if the
  sidecar's `ts:Pick` disagrees with the confirmed flag value.
- Step 7: **Fails if** overriding doesn't clear `aiUnconfirmedFields`, if
  the flag isn't `pick`, or if the sidecar disagrees.
- Step 8: **Fails if** the post-confirm preflight count is anything other
  than exactly 1, or if it still excludes `$CONFIRM_ID` (the confirm
  gesture didn't actually flip its eligibility) or wrongly includes
  `$OVERRIDE_ID`.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
# Also reset the mutated local seed template so later smoke-fixture cards
# in the same session get the pristine baseline back:
rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/smoke/Teststrip"
```

## Sharp edges
- **This card cannot exercise the "remove/decline" gesture
  (`removeAIField(.flag,...)` / `removed_ai_labels`) for a pick/reject
  flag** — grepped every call site and only `.caption` is wired to any
  control in the shipped UI (`InspectorView.swift:1169`). "Confirming then
  rejecting" per this card's brief is interpreted as the two gestures that
  *are* reachable: re-asserting the same decision (confirms) and choosing
  the opposite decision (also confirms, to a different value) — both go
  through `setFlagForSelectedAsset`, not `removeAIField`, so neither
  records a `removed_ai_labels` row. If a future task wires a "decline the
  AI's suggestion, stay undecided" control for flags, this card's steps
  6-7 should grow a third leg exercising `removeAIField(.flag,...)`
  directly and asserting the `removed_ai_labels` row exists (so a future
  autopilot re-proposal is suppressed) — flagging this as a real gap, not
  a card-authoring shortcut.
- **The preflight's tentative-exclusion is silent** — unlike
  `outsideScopeCount`, which the sheet discloses in its summary text, the
  aiUnconfirmedFields skip in `rejectRelocationScope` produces no visible
  "N excluded" anywhere. A driver comparing the sheet's count against a
  hasty `SELECT count(*) FROM assets WHERE flag='reject'` (i.e.
  `RAW_REJECT`, not `CONFIRMED_REJECT`) will see a mismatch and might
  mistake it for a bug — it isn't; that's exactly what step 4 is proving.
- **Trash mode deletes the catalog row of whatever it *does* move** (per
  `app-017-move-rejects-to-trash.md`), which is why step 5's "still
  present" check is meaningful proof of non-relocation rather than a
  no-op observation.
- **This card intentionally mutates the shared local `smoke` seed
  template** (Pre-state) rather than driving a live Autopilot round trip —
  `cull-017-autopilot-review.md` already owns that mechanism end-to-end
  (banner → review → commit → undo); duplicating it here would test the
  same write path twice while adding VM-fragile import/evaluation wait
  time this card doesn't need. See Cleanup for resetting the template.

## Run status
NOT RUN — authored 2026-07-16, source-cited against the working tree by
directly reading `Metadata.swift`, `AppModel.swift` (`cullUndecidedCount`,
`cullingProgressSummary`, `rejectRelocationScope`, `moveRejectsToTrash`,
`setFlagForSelectedAsset`, `removeAIField`), `CatalogRepository.swift`
(`assetCount(ids:confirmedFlag:)`, `confirmedFieldClauseSQL`),
`CullHUDPresentation.swift`, `LibraryGridView.swift`
(`RejectRelocationSheetPresentation`), `XMPPacket.swift`, and
`SmokeCatalogSeeder.swift`, not carried over from any older card; pending
live VM execution per `test/scenarios/README.md`.
