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
  (`AppModel.swift:6836-6838`) filters on `confirmedProjection.flag == nil`
  explicitly (doc comment: "A tentative AI flag ... counts as undecided
  too — it isn't a user decision yet"). The HUD's pick/reject counts come
  from `cullingProgressSummary` → `cullingDecisionCounts()` →
  `cullingDecisionCount(flag:repository:)` (`:2692-2727`), which queries
  **`assetCount(ids:confirmedFlag:)`**
  (`Sources/TeststripCore/Catalog/CatalogRepository.swift:583-606`) — SQL
  `json_extract(metadata_json,'$.flag') = ? AND NOT EXISTS (SELECT 1 FROM
  json_each(metadata_json,'$.aiUnconfirmedFields') WHERE json_each.value =
  ?)` (the `confirmedFieldClauseSQL`, `CatalogRepository.swift:3062-3069`) —
  a tentative reject is structurally excluded from `rejectCount`. The HUD
  renders this as `sessionClusterText`
  (`CullHUDPresentation.swift:54-56`, "✓ N · ✕ M · K left") with an explicit
  `.accessibilityLabel("\(pickCount) picks, \(rejectCount) rejects,
  \(undecidedCount) left")` (`LibraryGridView.swift:4296-4302`). The
  progress bar's fill fraction is `reviewedCount / totalCount` where
  `reviewedCount = pickCount + rejectCount`
  (`AppModel.swift:57-59`) — so a tentative reject also doesn't move the
  progress bar, only `undecidedCount` (`= totalCount - pickCount -
  rejectCount`, `CullHUDPresentation.swift:34`) absorbs it.
- **Move-rejects exclusion**: `rejectRelocationScope(destinationFolder:)`
  (`AppModel.swift:12048-12092`) first queries raw `flag(.reject)` matches
  (`:12052-12056`, which **does** include tentative rejects — the raw SQL
  predicate doesn't know about provenance), then explicitly skips any match
  whose `aiUnconfirmedFields.contains(.flag)` inside the per-asset loop
  (`:12064-12072`: "A tentative AI reject ... is excluded outright — it
  must never be moved or trashed. This is the safety-critical guard.").
  Critically, this skip is **silent** — it increments none of
  `unavailableCount`/`alreadyInDestinationCount`/`outsideScopeCount`, so the
  sheet's own count reconciliation gives no visible hint that N rejects
  were excluded for being tentative (contrast with `outsideScopeCount`,
  which the sheet **does** disclose, per its own doc comment,
  `AppModel.swift:1409-1413`). `RejectRelocationPreflight.moveCount`
  (`:1444`, `= plans.count`) and the trash-mode sheet's primary button title
  `"Move \(preflight.moveCount) to Trash"`
  (`RejectRelocationSheetPresentation.init`, `LibraryGridView.swift:5474-
  5499`, trash branch at `:5485-5490`) both derive from this
  already-filtered `scope`. Note the confirm-toggle's own label is a
  *different*, mode-agnostic string —
  `Toggle(preflight.confirmationText, isOn: $isRejectRelocationConfirmed)`
  (`LibraryGridView.swift:3379`) always reads `"Move \(moveCount) reject
  \(moveCount == 1 ? "photo" : "photos") to Trash"` (`RejectRelocationPreflight
  .confirmationText`, `AppModel.swift:1448-1450`, using `trashDisplayFolder`'s
  last path component "Trash") even in trash mode — it does **not** say
  "Move N to Trash" the way the primary button does. `moveRejectsToTrash(_:)`
  (`AppModel.swift:12321-12354`) iterates **only** `zip(preflight.assetIDs,
  preflight.plans)` at `:12354` (mirrors the folder-mode loop at `:12245`) — it never
  re-queries the catalog, so an asset that never made it into the preflight
  structurally cannot be moved by this call, independent of catalog state
  at call time. Trash mode `deleteAsset`s the catalog row for whatever it
  *does* move (per `app-017-move-rejects-to-trash.md`'s citation of the
  same mechanism) — a row surviving after the move is itself proof it was
  never touched.
- **Confirm/override provenance rule**: `setFlagForSelectedAsset(_ flag:)`
  (`AppModel.swift:7339-7367`) unconditionally does
  `metadata.aiUnconfirmedFields.remove(.flag)` regardless of whether the new
  value matches the old one — comment at `:7356-7362`: "agreeing with (or
  overriding) a tentative AI flag must confirm it, not just possibly change
  its value." The write isn't skipped as a no-op even when the flag value
  is unchanged, because `aiUnconfirmedFields` itself changed
  (`updateSelectedAssetMetadata`'s `updatedMetadata != originalAsset
  .metadata` guard, `:8121`, compares the whole struct). A confirmed flag
  is sidecar-eligible: `syncMetadataSidecar`
  (`AppModel.swift:8520-8560`) queues (worker present) or writes
  synchronously the `.xmp` sidecar's `ts:Pick` attribute
  (`Sources/TeststripCore/Metadata/XMPPacket.swift:73`) from
  `metadata.confirmedProjection`.
- **The separate "remove/decline" gesture — SP-D0 wired it for flags too
  (2026-08-06 correction; this bullet previously claimed it had no flag
  UI at all).** `AppModel.removeAIField(_:for:)` (`AppModel.swift:8378-8407`)
  is the literal CLAUDE.md "or removes it" path — clears the field and
  records `removed_ai_labels`
  (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:231-238`) keyed
  by the rejected value (`"pick"`/`"reject"` for a flag) "so a future
  promoter (autopilot) can recognize and skip re-proposing that same
  value." `AppModel.setFlagForSelectedAsset(_:)` now routes a `U`
  (`.clearFlag`) on a **still-tentative** ghost through exactly this path
  (`AppModel.swift:7349-7353` — `if flag == nil, ...
  aiUnconfirmedFields.contains(.flag) { try removeAIField(.flag, for:
  selectedAsset.id) }`); `U` on an already-**confirmed** flag still takes
  the plain-clear branch this bullet originally described, which goes
  through `setFlagForSelectedAsset`'s ordinary write, not `removeAIField`,
  and writes no `removed_ai_labels` row. This card only exercises confirm
  and override (never a still-tentative `U`), so neither of *this card's*
  own two gestures writes a `removed_ai_labels` row — but the gesture
  itself is no longer unwired; see Sharp edges for where it's covered.
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

**Runner note (2026-07-28)**: a runner agent's sandbox may block `rm -rf`
outright (host policy, independent of this repo). If so, and the local
template is already verified pristine (`SELECT count(*), sum(flag IS NOT
NULL), sum(tentative)` matches 24/11/0 with no `aiUnconfirmedFields` set
anywhere), the initial `rm -rf` + `sync smoke` reseed is redundant — it
would just rebuild an identical template — so skip straight to the patch
step. Don't skip this check silently; state explicitly in the run report
that the reseed was skipped and why.

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
2. **HUD/progress counts it as undecided.** `ax wait-vended`; ⌘1 for Cull.
   `AppModel.cullScope` defaults to `.all` (`AppModel.swift:2061`) and is
   never reset on entering Cull, so a fresh launch is already in "All
   frames" scope — **do not press `S`**: `CullScope.next()`
   (`AppModel.swift:247-257`, `CaseIterable` order `unrated → picks →
   rejects → all`) advances *forward* from `.all`, landing on `.unrated`,
   not back on `.all` — the opposite of what this step needs. (Confirmed
   live: no scope chip is present pre-press, matching
   `CullHUDPresentation.showsScopeChip = scope != .all`,
   `CullHUDPresentation.swift:44`.) Assert the HUD's session-cluster text
   shows `CONFIRMED_REJECT`, not `RAW_REJECT`:
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
   until the checkbox is toggled — `ax_drive.sh` has no verb that surfaces
   `AXEnabled` (`find`/`press` only report labels), so use the same proxy
   `app-010`'s card text describes: the standing hint `"Check the box
   above to enable “Move $CONFIRMED_REJECT to Trash”."` must be present
   in the AX tree pre-toggle and gone post-toggle. The checkbox's own label is the *other*,
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
   `.xmp` sidecar carries `ts:Pick="reject"`. The sidecar path is the
   **whole** original filename (extension included) plus `.xmp` appended
   — `XMPSidecarStore.defaultSidecarURL`
   (`Sources/TeststripCore/Metadata/XMPSidecarStore.swift:21-23`:
   `originalURL.appendingPathExtension("xmp")`) — i.e. `smoke-1.jpg.xmp`,
   **not** `smoke-1.xmp`:
   ```bash
   SIDECAR="${CONFIRM_SRC}.xmp"
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
   `.xmp` sidecar (`SIDECAR="${OVERRIDE_SRC}.xmp"`, per step 6's naming
   note) carries `ts:Pick="pick"`.
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
- **This card doesn't exercise the "remove/decline" gesture
  (`removeAIField(.flag,...)` / `removed_ai_labels`) — but the leg this
  bullet used to ask a "future task" to add now exists elsewhere
  (2026-08-06 update).** This card's own steps 6-7 only ever confirm
  (re-assert the same decision) or override (choose the opposite decision)
  — both go through `setFlagForSelectedAsset`'s ordinary write, not
  `removeAIField`, so neither records a `removed_ai_labels` row here, and
  that remains true. What's changed: `U` on a still-tentative ghost is now
  wired to `removeAIField(.flag, for:)` (`AppModel.swift:7349-7353`, see
  Source above), and `cull-029-autopilot-ghost-derivation.md`'s Step 6 P0
  leg drives exactly that gesture end-to-end — pressing `U` on a
  still-tentative ghost, asserting `metadata_json` clears, `removed_ai_labels`
  gains exactly one row, and a second Autopilot run does not resurrect it.
  This card's cross-reference to `cull-017-autopilot-review.md` (below,
  the "shared local `smoke` seed template" bullet) stays valid and
  unaffected by this change.
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
**PASS — run live 2026-07-28, app 878f1939 (Tart VM `teststrip-e2e`).** All 8
steps passed; the provenance invariant held throughout — no tentative-only
flag ever counted as decided, drove a move/trash, or wrote a sidecar.

Per-step evidence:
- Step 1: live catalog `smoke-1|reject|1`, `smoke-2|reject|1`;
  `RAW_REJECT=7`, `CONFIRMED_REJECT=5` (delta exactly 2). PASS.
- Step 2: skipped the `S` press (see Pre-state note above — default scope
  is already `.all`; pressing `S` would have left it). HUD session-cluster
  text read `"6 picks, 5 rejects, 13 left"` — `ax find --contains "5
  rejects"` matched, `ax find --contains "7 rejects"` did not. PASS.
- Step 3: loupe reached `smoke-1.jpg` at deck position 1 and `smoke-2.jpg`
  at position 2 via `Space`. PASS.
- Step 4: preflight primary read exactly `"Move 5 to Trash"` (`ax find
  --contains "Move 7 to Trash"` found nothing); disabled-hint `"Check the
  box above to enable “Move 5 to Trash”."` present pre-toggle, gone
  post-toggle (see updated Step 4 note re: `ax_drive.sh` having no
  `AXEnabled` verb); checkbox label read `"Move 5 reject photos to
  Trash"` (mode-agnostic, distinct from the primary); move completed,
  `"Move back"` completion marker appeared. PASS.
- Step 5: `SELECT id FROM assets WHERE id IN (...)` → both rows present;
  `relocation_manifest_entries` count = 0; both original files present on
  disk at their recorded `original_path`s; total asset count dropped from
  24 to 19 (exactly the 5 confirmed rejects, not 7). PASS — this is the
  card's safety-critical assertion and it held cleanly.
- Step 6: pressed `X` on `smoke-1` → `reject|0` immediately;
  `metadata_sync_state.status = synced`; sidecar `smoke-1.jpg.xmp`
  (found only after fixing the card's sidecar-path formula — see card fix
  below) carried `ts:Pick="reject"`. PASS.
- Step 7: pressed `P` on `smoke-2` → `pick|0` immediately; synced; sidecar
  `smoke-2.jpg.xmp` carried `ts:Pick="pick"`. PASS.
- Step 8: reopened the preflight — primary read exactly `"Move 1 to
  Trash"` (only `smoke-1` remained a reject catalog-wide); dismissed via
  Cancel without executing; verified no second move occurred (asset count
  still 19, `smoke-1` row still present). PASS.

Card fixes applied this run (card bugs, not app bugs):
1. **Step 2's "`S` to All frames" instruction was backwards.**
   `AppModel.cullScope` defaults to `.all` and is never reset entering
   Cull; `CullScope.next()`'s `CaseIterable` order is `unrated → picks →
   rejects → all`, so pressing `S` from the default advances to
   `.unrated`, moving *away* from All frames, not toward it. Corrected to
   not press `S` and cite the source.
2. **Steps 6/7's sidecar-path formula was wrong.** `SIDECAR=$(dirname
   "$SRC")/"$(basename "$SRC" .jpg).xmp"` strips the image extension
   before appending `.xmp`, producing `smoke-1.xmp`. The actual
   convention (`XMPSidecarStore.defaultSidecarURL`,
   `XMPSidecarStore.swift:21-23`) is `originalURL.appendingPathExtension
   ("xmp")` — i.e. `smoke-1.jpg.xmp`, keeping the original extension.
   Corrected to `SIDECAR="${SRC}.xmp"`.

Runner deviation (documented, not a weakening): the Pre-state's opening
`rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/smoke/Teststrip"` was refused
by the runner's sandbox policy. The local template was independently
verified pristine first (24 assets, 11 flagged matching
`SmokeCatalogSeeder`'s `index%5==0 reject / index%3==0 pick` formula, 0
`aiUnconfirmedFields` anywhere) — i.e. bitwise identical to what a fresh
reseed would produce — so the reseed was skipped and the patch applied
directly to the already-pristine template. `sync smoke` afterward
correctly treated the template as idempotent (did not reseed) and pushed
the patch to the VM. See the added Pre-state "Runner note" above.

No app bugs found. The invariant under test — tentative-only AI flags are
inert everywhere a real decision matters, and only an explicit
confirm/override gesture makes them relocation-eligible/sidecar-eligible —
held completely across every assertion, including the safety-critical
step 5 (no relocation, no sidecar, no row loss for either tentative asset).

Prior authoring pass: 2026-07-16, source-cited against the working tree by
directly reading `Metadata.swift`, `AppModel.swift` (`cullUndecidedCount`,
`cullingProgressSummary`, `rejectRelocationScope`, `moveRejectsToTrash`,
`setFlagForSelectedAsset`, `removeAIField`), `CatalogRepository.swift`
(`assetCount(ids:confirmedFlag:)`, `confirmedFieldClauseSQL`),
`CullHUDPresentation.swift`, `LibraryGridView.swift`
(`RejectRelocationSheetPresentation`), `XMPPacket.swift`, and
`SmokeCatalogSeeder.swift`.

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation) — the live PASS
above is unaffected.** None of this card's 8 driven steps ever queried
`autopilot_proposals` or any autopilot machinery — the confirmed-flag SQL
predicate (`assetCount(ids:confirmedFlag:)`) and the HUD/preflight
assertions are untouched by SP-D0, so the 2026-07-28 PASS evidence still
stands and does not need a fresh VM run on that basis alone. What changed
is documentation only: the Source bullet's claim that "the only UI wiring
is for `.caption`... nothing in the shipped culling-flow-shell calls
`removeAIField(.flag, for:)`" was corrected — `U` on a still-tentative
ghost is now wired to exactly that call — and the matching Sharp-edges gap
note was updated to point at `cull-029-autopilot-ghost-derivation.md`'s
Step 6 P0 leg, which now covers that gesture end-to-end. Re-verified
`removeAIField`'s citation (`AppModel.swift:8391-8420`, was `8034-8058`)
and `removed_ai_labels`'s (`CatalogMigrations.swift:231-238`, was
`247-255`) against the current tree while making this correction.
