# cull-023-return-commit-undo: Return commits a stack — pick the staged frame, reject undecided siblings, protect prior picks, force-flip a rejected frame with disclosure, and undo the whole gesture in one step

**What this covers**: as a photographer blazing through a burst, I press
`Return` on the frame I want to keep and trust it to (a) pick that frame,
(b) reject every sibling that isn't already a pick — protecting a pick I
already made — (c) tell me honestly if I'm force-flipping a frame I
previously rejected, (d) write real XMP sidecars for the confirmed decisions
and nothing for what's still tentative, and (e) let one `⌘Z` put the whole
gesture back exactly as it was, including a tentative AI marker undo
restores. On a standalone frame, `Return` is a pure no-op with an
informational toast — never a silent write.

Source (re-verified against the working tree on this branch, **2026-07-16**;
every symbol below was re-grepped fresh, not carried over from any older
card):
- **The gesture**: `AppModel.promoteCurrentFrameAndRejectSiblings()`
  (`Sources/TeststripApp/AppModel.swift:6341-6397`). Membership guard
  (`:6343-6344`): `selectedWorkStackAssetIDs` (a persisted stack) or
  `cullingStacks()` (the in-memory auto-grouped, multi-frame-only partition)
  must contain the selection, else it's the standalone no-op branch
  (`:6349-6354`): sets `lastCullingMetadataDecision` to
  `singleFrameStackFeedback(asset:)` (`:6399-6407`) — decisionText exactly
  `"No stack to promote — P picks this frame"`, `isInformational: true` — and
  returns with **no metadata write** at all.
- **The render gate** (`:6357-6367`): before ever building the decision
  context, guards `previewURL(for: context.selectedAssetID, levels:
  [.large]) != nil` (`previewURL(for:levels:)`, `:13933-13942` — checks the
  on-disk preview-cache file for that exact level, no fallback to a smaller
  cached level). If the `.large` preview file doesn't exist yet, sets
  `renderPendingFeedback(asset:)` (`:6409-6417`) — decisionText exactly
  `"Rendering full preview…"`, `isInformational: true` — and returns with
  **no metadata write**. See Sharp edges: this leg is a confirmed fixture
  gap, not drivable today.
- **Pick protection** (`:6368-6383`, Jesse's ruling 2026-07-11): every
  sibling whose **raw** `metadata.flag == .pick` — regardless of AI/user
  provenance, per the comment at `:6370-6373`: "Flag provenance isn't
  recorded (autopilot commits write plain picks), so ALL picked siblings are
  protected" — is collected into `protectedPickedSiblings` and added to
  `pickedAssetIDs` alongside the staged frame. Every other sibling (raw flag
  `nil` or `.reject`, tentative or not) gets `.reject`.
- **The write**, `applyCullingStackDecision` (`:6464-6513`): loops every
  asset in the stack, sets `.pick`/`.reject` per the set above, and
  unconditionally does `metadata.aiUnconfirmedFields.remove(.flag)`
  (`:6486`, comment at `:6482-6485`: "a stack decision is a direct user
  gesture too: it confirms the flag even when the decided value matches a
  tentative AI one already there") — **but** the per-asset write is skipped
  entirely (`guard metadata != originalAsset.metadata else { continue }`,
  `:6487`) when nothing actually changed, so a sibling that was *already* a
  plain confirmed pick (no tentative marker, same value) produces **no
  write, no `MetadataChange`, no undo-group membership, no
  `catalog_generation` bump** for that asset — a real no-op, not just an
  unchanged read. All effective changes land in **one**
  `MetadataChangeGroup` via `recordMetadataChangeGroup` (`:7928-7933`,
  label `"Flag"`/`"Flag · N photos"`).
- **The toast text**, `promoteDecisionFeedback` (`:6419-6447`): components
  joined by `" · "` —
  `"Kept \(filename)\(wasRejected ? " (was ✕)" : "")"`, then
  `"rejected \(siblingCount)"` only if `siblingCount > 0` (`siblingCount =
  stack.count - 1 - protectedPickedSiblings.count`), then `"kept your pick
  of \(name)"` (exactly one protected sibling) or `"kept your picks of N
  siblings"` (2+), then always `"⌘Z undoes"`. `wasRejected` (`:6389-6393`)
  is `originalAsset.metadata.confirmedProjection.flag == .reject` —
  **confirmed only**: a tentative AI reject on the staged frame itself would
  read `confirmedProjection.flag == nil`, so it would **not** trigger
  "(was ✕)" (out of this card's scope — the staged frame in every leg below
  is either confirmed-rejected or plain-undecided, never itself tentative).
  `rendersVerbatim: true` (`:6445`) means `CullDecisionToastPresentation`
  (`Sources/TeststripApp/CullFilmstripPresentation.swift:110-135`) renders
  `decisionText` as-is with no extra symbol/wrap (`:114-121`); for the
  informational (no-write) branches above, `isInformational` alone triggers
  the same as-is rendering, also with no symbol and no "⌘Z undoes" appended.
  The toast `Text` (`LibraryGridView.swift:4374-4384`, `decisionToast`)
  carries no `.accessibilityLabel` override, so its AXStaticText title is
  the literal string — matching `cull-022-flow-grammar-walk.md`'s citation
  of the same pattern for the `A`-toggle toast. It **fades after 2 real
  seconds** (`showDecisionToastThenFade`, `LibraryGridView.swift:4353-4368`,
  `Task.sleep(for: .seconds(2))`) — poll immediately after the keypress.
- **Sidecar writes**: `applyMetadataSnapshot` (`AppModel.swift:8370-8384`)
  calls `syncMetadataSidecar(for:)` (`:8386-`ff.) for every asset in the
  change group. With a live worker supervisor (the real app), this
  **enqueues** the write (`recordMetadataSyncPending`,
  `:8398-8409`) rather than writing synchronously — poll
  `metadata_sync_state.status` (the column is `status`, not `state`;
  `Sources/TeststripCore/Catalog/CatalogMigrations.swift:30-37`) until it's
  no longer `pending` before checking the `.xmp` file.
  `XMPPacket.applyManagedMetadata` (`Sources/TeststripCore/Metadata/
  XMPPacket.swift:59-73`) projects through `metadata.confirmedProjection`
  first (`:62`) before writing `ts:Pick` (`:73`) — a tentative-only flag
  never reaches the sidecar (CLAUDE.md's non-negotiable invariant), and
  since `SmokeCatalogSeeder` writes `metadata_json` directly into SQLite,
  bypassing `AppModel`/`syncMetadataSidecar` entirely, **no `.xmp` exists
  for any seeded asset until the app itself writes one** — this card's own
  first live step re-confirms that baseline rather than assuming it.
- **Undo**, `undoMetadataChange()` (`:7935-7942`): pops the last
  `MetadataChangeGroup` and reapplies each change's `before` snapshot via
  `applyMetadataSnapshot` — for a change whose `before` included a tentative
  AI marker, undo restores `aiUnconfirmedFields` exactly as it was, not just
  the flag value. Undo is a plain LIFO stack (`metadataUndoStack`,
  `:7928-7933`), so a single `⌘Z` after two independent Return commits pops
  only the most recent group, leaving the earlier commit's writes untouched
  — this card exercises two independent stack commits in one session and
  checks that isolation explicitly.
- **Keys**: `Return`/keypad-Enter map to `.promoteAndRejectSiblings`
  (`CullingShortcut.init(event:)`, `Sources/TeststripApp/
  CullingKeyCaptureView.swift:159-161`; keycode 36,
  `MacKeyCode.returnKey`, `:183`), dispatched at `AppModel.swift:6585`.
  `Space` is `.nextPhoto` → `selectNextAssetForCulling()` — plain,
  decision-free catalog-order advance (`:6855-6868`), used here only to
  navigate between legs; sent as `key code 49` (`MacKeyCode.space`, `:185`),
  the same keycode-based form as Return's `key code 36` rather than a
  quoted-string `keystroke " "`. Undo's `⌘Z` is sent as
  `script/vm_scenario_run.sh key 'keystroke "z" using {command down}'`
  (pattern from `test/scenarios/lib-021-raw-jpeg-bonding.md:143`).
- **Fixture and seeding gap**: `burst` (`Sources/TeststripBench/
  SmokeCatalogSeeder.swift`, `BurstFixtureLayout`) seeds 4 auto-groupable
  stacks (3/4/3/4 frames, capture times 1s apart) + 4 singles as assets
  `smoke-0`…`smoke-17`, using the **same flag formula** as `--smoke`
  (`:147`): `index.isMultiple(of: 5) ? .reject : (index.isMultiple(of: 3) ?
  .pick : nil)`, **never** setting `aiUnconfirmedFields`. Group boundaries
  (`BurstFixtureLayout.burstFrameCounts = [3, 4, 3, 4]`,
  `singleCount = 4`): group1 = `smoke-0,1,2` (flags `reject,nil,nil`);
  group2 = `smoke-3,4,5,6` (`pick,nil,reject,pick`); group3 =
  `smoke-7,8,9` (`nil,nil,pick`); group4 = `smoke-10,11,12,13`
  (`reject,nil,pick,nil`); singles = `smoke-14,15,16,17`
  (`nil,reject,nil,nil`). No seed command produces a pre-flagged
  **tentative**-AI asset (confirmed by `cull-026-tentative-never-commits.md`'s
  own investigation of this identical formula) — this card patches the
  local `burst` seed template directly (Pre-state below), marking
  `smoke-7` (otherwise `nil`) a tentative AI reject, mirroring `cull-026`'s
  technique.

## Pre-state
```bash
# Force a pristine local 'burst' template, then seed it as usual.
rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip"
script/vm_scenario_run.sh sync burst

# Patch the LOCAL template (host-side, pre-launch): burst's shared flag
# formula leaves smoke-7 (group3's first frame) unflagged (index 7 is not a
# multiple of 3 or 5) -- mark it a tentative AI reject so the sidecar and
# non-picked-sibling legs below have real tentative-provenance material.
TEMPLATE_DB="${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip/catalog.sqlite"
sqlite3 "$TEMPLATE_DB" "
  UPDATE assets SET metadata_json = json_set(metadata_json, '\$.flag','reject','\$.aiUnconfirmedFields',json('[\"flag\"]'))
  WHERE id = 'smoke-7';"

# Re-sync so the VM gets the patched template (seeding is a no-op since the
# template file already exists; sync's rsync steps run unconditionally).
script/vm_scenario_run.sh sync burst
script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
```
**Note**: this mutates the shared local `burst` seed template for the rest
of the session. A card run afterward that depends on the pristine burst
baseline (zero tentative flags) should
`rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip"` first.

## Steps
1. **Confirm the seed baseline, live (not just the template).**
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag')
      FROM assets WHERE id IN ('smoke-0','smoke-1','smoke-2','smoke-7','smoke-8','smoke-9','smoke-16')
      ORDER BY id;"
   ```
   Expect: `smoke-0` = `reject|0` (confirmed), `smoke-1`/`smoke-2` = `NULL|0`,
   `smoke-7` = `reject|1` (tentative — the patch), `smoke-8` = `NULL|0`,
   `smoke-9` = `pick|0` (confirmed), `smoke-16` = `NULL|0`. **Universal
   sidecar baseline** (covers every leg's "before" state in one check, and
   self-verifies the Source claim that seeding never syncs a sidecar):
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT count(*) FROM metadata_sync_state;"   # expect 0
   SRC_DIR=$(script/vm_scenario_run.sh sql burst "SELECT original_path FROM assets WHERE id='smoke-0';" | xargs dirname)
   script/vm_scenario_run.sh shell "find '$SRC_DIR' -name '*.xmp' | wc -l"           # expect 0
   ```
   `ax wait-vended`; ⌘1 for Cull; `S` to cycle scope to "All frames"
   (confirm via the HUD's scope chip being **absent** — `cullHUDScopeChip`
   only renders `scope != .all`, `CullHUDPresentation.swift:44` — so no
   `"Cull filter:"` element should match). Confirm the initial selection is
   `smoke-0` (`ax find --role AXStaticText --contains "smoke-0.jpg"`); if it
   isn't, press `Space`/navigate until it is before Step 2.

2. **Force-flip leg (group1, standalone from group3 below).** With
   `smoke-0` selected, press Return
   (`script/vm_scenario_run.sh key 'key code 36'`). Immediately poll:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "Kept smoke-0.jpg (was ✕) · rejected 2 · ⌘Z undoes"
   ```
   Ground truth:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN ('smoke-0','smoke-1','smoke-2') ORDER BY id;"
   ```
   Expect `smoke-0|pick`, `smoke-1|reject`, `smoke-2|reject` — the force-flip
   promoted a previously **confirmed** reject to a pick, and the toast
   disclosed it.

3. **Navigate to the main-commit leg's staged frame.** Press `Space`
   repeatedly (`script/vm_scenario_run.sh key 'key code 49'`), polling the
   HUD filename after each press, until `smoke-8.jpg` is selected (Space is
   decision-free — passing through `smoke-3`…`smoke-7` writes nothing;
   spot-check `smoke-3`..`smoke-6`'s flags are still their Step 1 baseline
   afterward if convenient, not load-bearing). Record `smoke-9`'s
   generation before the commit:
   ```bash
   GEN9_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT catalog_generation FROM assets WHERE id='smoke-9';")
   ```

4. **Main commit: promote, protect the prior pick, confirm the tentative
   sibling, write sidecars.** Press Return. Poll immediately:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "Kept smoke-8.jpg · rejected 1 · kept your pick of smoke-9.jpg · ⌘Z undoes"
   ```
   (no "(was ✕)" — `smoke-8` was undecided, not a confirmed reject.) Ground
   truth:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag'),
             catalog_generation
      FROM assets WHERE id IN ('smoke-7','smoke-8','smoke-9') ORDER BY id;"
   ```
   Expect `smoke-7|reject|0|<bumped>` (tentative → confirmed, same value —
   the aiUnconfirmedFields removal alone counts as a real change),
   `smoke-8|pick|0|<bumped>` (the promoted frame), `smoke-9|pick|0|<==
   GEN9_BEFORE>` — **protected AND untouched**: assert
   `catalog_generation` for `smoke-9` is byte-identical to `GEN9_BEFORE`,
   proving the no-op guard (Source above) skipped the write entirely, not
   just left the value unchanged. Wait for sync to drain, then check
   sidecars:
   ```bash
   for id in smoke-7 smoke-8; do
     script/vm_scenario_run.sh sql burst "SELECT status FROM metadata_sync_state WHERE asset_id='$id';"
   done   # poll until neither reads 'pending'
   for id in smoke-7 smoke-8; do
     SRC=$(script/vm_scenario_run.sh sql burst "SELECT original_path FROM assets WHERE id='$id';")
     SIDECAR="$(dirname "$SRC")/$(basename "$SRC" .jpg).xmp"
     script/vm_scenario_run.sh shell "grep -o 'ts:Pick=\"[^\"]*\"' '$SIDECAR'"
   done
   ```
   Expect both read `ts:Pick="reject"` (smoke-7) / `ts:Pick="pick"`
   (smoke-8). Confirm **no** `metadata_sync_state` row (and no `.xmp`) for
   `smoke-9` — its write was skipped, so it was never even enqueued:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT count(*) FROM metadata_sync_state WHERE asset_id='smoke-9';"   # expect 0
   ```

5. **One-unit undo.** Press `⌘Z`
   (`script/vm_scenario_run.sh key 'keystroke "z" using {command down}'`)
   **once**. Ground truth — the entire group3 commit reverts, including the
   tentative marker:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag')
      FROM assets WHERE id IN ('smoke-7','smoke-8','smoke-9') ORDER BY id;"
   ```
   Expect `smoke-7|reject|1` (back to tentative — exactly its Step 1 state),
   `smoke-8|NULL|0` (back to undecided), `smoke-9|pick|0` (unchanged
   throughout — it was never part of the change group). **Isolation
   check**: confirm the *earlier*, independent group1 commit (Step 2) is
   untouched by this single `⌘Z` — it should NOT also have reverted:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN ('smoke-0','smoke-1','smoke-2') ORDER BY id;"
   ```
   Expect unchanged from Step 2: `smoke-0|pick`, `smoke-1|reject`,
   `smoke-2|reject`.

6. **Standalone no-op.** Press `Space` repeatedly, polling the HUD filename,
   until `smoke-16.jpg` is selected (a single, no multi-frame stack —
   confirm no stack rail renders: `ax find --role AXButton --contains
   "Stack frame"` should fail to match). Record a whole-catalog write
   signal before:
   ```bash
   SUMGEN_BEFORE=$(script/vm_scenario_run.sh sql burst "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;")
   ```
   Press Return. Poll immediately:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "No stack to promote — P picks this frame"
   ```
   (no ✓/✕ symbol, no "⌘Z undoes" — informational.) Ground truth: zero
   writes anywhere in the catalog:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id='smoke-16';"   # still NULL
   script/vm_scenario_run.sh sql burst "SELECT COALESCE(SUM(catalog_generation),0) FROM assets;"   # == SUMGEN_BEFORE, exactly
   ```

7. **Render-gate leg — documented as not executable with current
   fixtures, not skipped silently.** See Sharp edges for the full
   investigation. In short: both `smoke` and `burst` seed **every** preview
   level, including `.large` (`SmokeCatalogSeeder.renderedLevels =
   [.micro, .grid, .medium, .large]`, `:63`), before the app ever launches
   — so `previewURL(for:levels:[.large])` is non-nil for every asset at
   Step 1, and the render-gate branch (`:6362`) can never trigger on these
   fixtures. A freshly-imported multi-frame stack is the only theoretical
   way to catch a genuine "large not rendered yet" window (mirroring
   `worker-001-preview-lifecycle.md`'s queued/building race for thumbnails)
   — but no current seed/fixture generator produces a freshly-imported
   **multi-frame** stack: `DuplicateFixtureSeeder` (the only multi-file
   import fixture) writes JPEGs with no EXIF `DateTimeOriginal`, so
   `AssetStackBuilder.isCaptureTimeNeighbor` always returns false for them
   (confirmed by `cull-004-stack-promote-return.md`'s own investigation of
   this exact generator) — every freshly-imported asset from it is a
   standalone, which takes the no-op branch (Step 6), not the render-gate
   branch. **Do not attempt to fabricate this leg against `smoke`/`burst`**
   — report it as an honest fixture gap. Falsification condition for a
   future run against a fixture that closes this gap: stand on a
   multi-frame stack's staged frame the instant after import, before its
   `.large` preview exists on disk (`previewURL(for:levels:[.large]) ==
   nil` at the moment of the keypress); press Return; this leg is falsified
   if the commit's catalog write happens anyway, or if the toast doesn't
   read exactly `"Rendering full preview…"` with no ✓/✕/undo language.

## Expected
- Step 2: **Fails if** `smoke-0` doesn't become `pick`, if the toast omits
  `"(was ✕)"` for a genuinely confirmed prior reject, or if `smoke-1`/
  `smoke-2` aren't both `reject`.
- Step 4: **Fails if** `smoke-9`'s `catalog_generation` changed at all (the
  protection guard didn't actually skip the write), if `smoke-7` isn't
  confirmed (`aiUnconfirmedFields` still contains `flag`), if either
  sidecar is missing or disagrees with the confirmed flag, or if a
  `metadata_sync_state`/`.xmp` artifact exists for `smoke-9`.
- Step 5: **Fails if** any of the three group3 assets lands anywhere other
  than its exact Step-1/Step-4-pre-commit state — in particular if
  `smoke-7`'s `aiUnconfirmedFields` doesn't come back (undo restored only
  the flag value, not the provenance marker) — or if the unrelated group1
  commit from Step 2 is also reverted (undo grouping too coarse, spanning
  gestures).
- Step 6: **Fails if** the flag on `smoke-16` changed, if
  `SUM(catalog_generation)` changed by even one, or if the toast reads
  anything other than the exact informational string with no undo
  language.
- Step 7: not a pass/fail leg — report explicitly as "not executable, see
  Sharp edges" rather than omitting it or forcing a substitute fixture.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
# Also reset the mutated local seed template so later burst-fixture cards
# in the same session get the pristine baseline back:
rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip"
```
Quit the launched instance before deleting.

## Sharp edges
- **Both `smoke` and `burst` pre-render every level including `.large`.**
  This is the confirmed root cause of Step 7's gap (Source above,
  `SmokeCatalogSeeder.renderedLevels`) — it is not specific to `burst`.
  Any future card wanting to exercise the render gate needs a seed
  generator that writes a multi-frame stack's originals to disk *without*
  pre-populating the preview cache, imported fresh so the worker races to
  build `.large`. `cull-004-stack-promote-return.md`'s "Recommended next
  step" (a burst-fixture generator with EXIF `DateTimeOriginal` <=2s apart)
  would incidentally close this gap too, since it would also need to be a
  fresh import.
- **Pick protection checks the raw `flag`, not `confirmedProjection`.** A
  *tentative* AI pick sibling would also be protected (and, per
  `applyCullingStackDecision`'s unconditional `aiUnconfirmedFields.remove`,
  get confirmed by the same Return gesture) — this card's group3 fixture
  deliberately uses a tentative **reject** (not pick) on `smoke-7` so the
  "non-picked siblings get rejected" and "protection" legs stay visibly
  distinct; it does not exercise a tentative-pick-sibling getting swept
  into protection. Worth a follow-on card if that distinction ever needs
  its own assertion.
- **The toast fades in 2 real seconds** (`showDecisionToastThenFade`) —
  poll immediately after each Return/keystroke; don't interleave several
  other `find`/`sql` round-trips before checking it, per
  `cull-022-flow-grammar-walk.md`'s identical caution for the `A`-toggle
  toast.
- **This card mutates the shared local `burst` seed template** (Pre-state)
  — see Cleanup. Any other card in the same session that assumes the
  pristine `burst` baseline (no tentative flags) should reseed first.
- **Undo does not restore selection** — after Step 5's `⌘Z`, the selected
  asset stays wherever the Step 4 commit's post-commit advance left it
  (the next stop after group3); Step 6 navigates from there via `Space`
  rather than assuming a fixed starting position.

## Run status
NOT RUN — authored 2026-07-16, source-cited against the working tree by
directly reading `AppModel.swift` (`promoteCurrentFrameAndRejectSiblings`,
`promoteDecisionFeedback`, `applyCullingStackDecision`,
`recordMetadataChangeGroup`/`undoMetadataChange`, `previewURL`,
`applyMetadataSnapshot`/`syncMetadataSidecar`),
`CullFilmstripPresentation.swift` (`CullDecisionToastPresentation`),
`XMPPacket.swift`, `CatalogMigrations.swift`, `CullingKeyCaptureView.swift`,
and `SmokeCatalogSeeder.swift`/`BurstFixtureLayout`, not carried over from
any older card; pending live VM execution per `test/scenarios/README.md`.
The render-gate leg (Step 7) is additionally cross-checked against
`cull-004-stack-promote-return.md`'s independent investigation of
`DuplicateFixtureSeeder`'s missing EXIF timestamps.
