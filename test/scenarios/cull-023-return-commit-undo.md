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

Source (originally verified **2026-07-16**; the render-gate bullet and every
citation in this file were re-verified against the working tree at HEAD
`11cdf360` on **2026-07-30** — SP-C's blaze-through work replaced the plain
render-gate no-op with an armed, auto-firing commit and shifted most of
`AppModel.swift`'s line numbers in the process; see
`cull-027-blaze-through-prefetch.md` for the card that exercises the new
behavior live):
- **The gesture**: `AppModel.promoteCurrentFrameAndRejectSiblings()`
  (`Sources/TeststripApp/AppModel.swift:6370-6426`). Membership guard
  (`:6371-6373`): `selectedWorkStackAssetIDs` (a persisted stack) or
  `cullingStacks()` (the in-memory auto-grouped, multi-frame-only partition)
  must contain the selection, else it's the standalone no-op branch
  (`:6378-6382`): sets `lastCullingMetadataDecision` to
  `singleFrameStackFeedback(asset:)` (`:6476-6484`) — decisionText exactly
  `"No stack to promote — P picks this frame"`, `isInformational: true` — and
  returns with **no metadata write** at all.
- **The render gate now arms instead of just complaining** (SP-C,
  `937db96b`/`11cdf360`; re-verified at `:6386-6395`): before computing
  which siblings get protected, guards `previewURL(for:
  context.selectedAssetID, levels: [.large]) != nil`
  (`previewURL(for:levels:)`, now `:14118-14127` — checks the on-disk
  preview-cache file for that exact level, no fallback to a smaller cached
  level; logic unchanged, just moved). If the `.large` preview file doesn't
  exist yet, it no longer just complains and drops the gesture — it calls
  `armStackCommit(stagedAssetID:asset:)` (`:6394`, function at
  `:6428-6449`), which **arms** the commit (`armedStackCommitAssetID`,
  `:2149`) and fires it automatically — no second Return needed — the
  instant the staged frame's `.large` preview lands
  (`fireArmedStackCommitIfReady`, `:6455-6474`, wired into the worker-
  completion handler at `:10327-10332`). A repeat Return before then is
  still a harmless no-op re-arm of the same asset
  (`applyCullingShortcut`'s disarm guard, `:6622-6628`, only disarms for a
  *different* shortcut). The toast while armed reads exactly `"Rendering
  full preview… will keep when ready"` (`armedCommitFeedback`,
  `:6486-6494`, `isInformational: true` — no metadata write yet). Any other
  input before it fires — an arrow key, another flag/rating shortcut, a
  rail action — disarms it (`:4622-4628`, `:6082-6091`, `:6536-6555`,
  `:7339-7344`, `:7408-7411`), and the commit then never lands for that stack.
  `cull-027-blaze-through-prefetch.md` exercises this live; see Sharp edges
  below for why this card's own fixture still can't reach the leg.
- **Pick protection** (`:6397-6424`, Jesse's ruling 2026-07-11): every
  sibling whose **raw** `metadata.flag == .pick` — regardless of AI/user
  provenance, per the comment at `:6397-6402`: "Flag provenance isn't
  recorded (autopilot commits write plain picks), so ALL picked siblings are
  protected" — is collected into `protectedPickedSiblings` and added to
  `pickedAssetIDs` alongside the staged frame. Every other sibling (raw flag
  `nil` or `.reject`, tentative or not) gets `.reject`.
- **The write**, `applyCullingStackDecision` (`:6557-6606`): loops every
  asset in the stack, sets `.pick`/`.reject` per the set above, and
  unconditionally does `metadata.aiUnconfirmedFields.remove(.flag)`
  (`:6579`, comment at `:6575-6578`: "a stack decision is a direct user
  gesture too: it confirms the flag even when the decided value matches a
  tentative AI one already there") — **but** the per-asset write is skipped
  entirely (`guard metadata != originalAsset.metadata else { continue }`,
  `:6580`) when nothing actually changed, so a sibling that was *already* a
  plain confirmed pick (no tentative marker, same value) produces **no
  write, no `MetadataChange`, no undo-group membership, no
  `catalog_generation` bump** for that asset — a real no-op, not just an
  unchanged read. All effective changes land in **one**
  `MetadataChangeGroup` via `recordMetadataChangeGroup` (`:8057-8062`,
  label `"Flag"`/`"Flag · N photos"`).
- **The toast text**, `promoteDecisionFeedback` (`:6506-6534`): components
  joined by `" · "` —
  `"Kept \(filename)\(wasRejected ? " (was ✕)" : "")"`, then
  `"rejected \(siblingCount)"` only if `siblingCount > 0` (`siblingCount =
  stack.count - 1 - protectedPickedSiblings.count`), then `"kept your pick
  of \(name)"` (exactly one protected sibling) or `"kept your picks of N
  siblings"` (2+), then always `"⌘Z undoes"`. `wasRejected` (`:6418-6422`)
  is `originalAsset.metadata.confirmedProjection.flag == .reject` —
  **confirmed only**: a tentative AI reject on the staged frame itself would
  read `confirmedProjection.flag == nil`, so it would **not** trigger
  "(was ✕)" (out of this card's scope — the staged frame in every leg below
  is either confirmed-rejected or plain-undecided, never itself tentative).
  `rendersVerbatim: true` (`:6532`) means `CullDecisionToastPresentation`
  (`Sources/TeststripApp/CullFilmstripPresentation.swift:83-108`) renders
  `decisionText` as-is with no extra symbol/wrap (`:86-93`); for the
  informational (no-write) branches above, `isInformational` alone triggers
  the same as-is rendering, also with no symbol and no "⌘Z undoes" appended.
  The toast `Text` (`LibraryGridView.swift:4468-4477`, `decisionToast`)
  carries no `.accessibilityLabel` override, so its AXStaticText title is
  the literal string — matching `cull-022-flow-grammar-walk.md`'s citation
  of the same pattern for the `A`-toggle toast. It **fades after 2 real
  seconds** (`showDecisionToastThenFade`, `LibraryGridView.swift:4447-4462`,
  `Task.sleep(for: .seconds(2))`) — poll immediately after the keypress.
- **Sidecar writes**: `applyMetadataSnapshot` (`AppModel.swift:8504-8518`)
  calls `syncMetadataSidecar(for:)` (`:8520-8560`) for every asset in the
  change group. With a live worker supervisor (the real app), this
  **enqueues** the write (`recordMetadataSyncPending`,
  `:8533-8544`) rather than writing synchronously — poll
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
- **Undo**, `undoMetadataChange()` (`:8064-8071`): pops the last
  `MetadataChangeGroup` and reapplies each change's `before` snapshot via
  `applyMetadataSnapshot` — for a change whose `before` included a tentative
  AI marker, undo restores `aiUnconfirmedFields` exactly as it was, not just
  the flag value. Undo is a plain LIFO stack (`metadataUndoStack`,
  `:8057-8062`), so a single `⌘Z` after two independent Return commits pops
  only the most recent group, leaving the earlier commit's writes untouched
  — this card exercises two independent stack commits in one session and
  checks that isolation explicitly.
- **Keys**: `Return`/keypad-Enter map to `.promoteAndRejectSiblings`
  (`CullingShortcut.init(event:)`, `Sources/TeststripApp/
  CullingKeyCaptureView.swift:164-165`; keycode 36,
  `MacKeyCode.returnKey`, `:183`), dispatched at `AppModel.swift:6691-6693`.
  `Space` is `.nextPhoto` → `selectNextAssetForCulling()` — plain,
  decision-free catalog-order advance (`:6962-6975`), used here only to
  navigate between legs; sent as `key code 49` (`MacKeyCode.space`, `:185`),
  the same keycode-based form as Return's `key code 36` rather than a
  quoted-string `keystroke " "`. Undo's `⌘Z` is sent as
  `script/vm_scenario_run.sh key 'keystroke "z" using {command down}'`
  (pattern from `test/scenarios/lib-021-raw-jpeg-bonding.md:145`).
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
   `ax wait-vended`; ⌘1 for Cull. **No `S` press needed**: `cullScope`
   defaults to `.all` on every fresh `AppModel` (`AppModel.swift:2061`,
   `public private(set) var cullScope: CullScope = .all`) with no
   persistence across launches, so a freshly-launched instance is already
   scoped to "All frames" — pressing `S` here actually *cycles away* from
   `.all` (`CullScope.next()`, `:322-326`, cycles
   `unrated → picks → rejects → all`), landing on "Unrated" first, not "All
   frames" (confirmed live: one `S` press produced a `"Cull filter:
   Unrated"` chip). Just confirm scope is already `.all` via the HUD's
   scope chip being **absent** — `cullHUDScopeChip` only renders
   `scope != .all`, `CullHUDPresentation.swift:44` — so no `"Cull filter:"`
   element should match, with zero `S` presses. Confirm the initial
   selection is `smoke-0` (`ax find --role AXStaticText --contains
   "smoke-0.jpg"`); if it isn't, press `Space`/navigate until it is before
   Step 2.

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
     SIDECAR="${SRC}.xmp"
     script/vm_scenario_run.sh shell "grep -o 'ts:Pick=\"[^\"]*\"' '$SIDECAR'"
   done
   ```
   (Sidecar naming is `originalPath + ".xmp"`, i.e. `smoke-7.jpg.xmp` —
   `XMPSidecarStore.defaultSidecarURL`,
   `Sources/TeststripCore/Metadata/XMPSidecarStore.swift:21-22`,
   `originalURL.appendingPathExtension("xmp")`. The stripped-extension form
   `smoke-7.xmp` is the "Adobe-style" fallback the store only *reads* if it
   already exists on disk — a freshly-written sidecar always uses the
   append form; confirmed live, the extension-preserving path is the one
   that actually exists.)
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
   confirm via the rail's **title text**, not a cell-label probe: `ax find
   --role AXStaticText --contains "Standalone"` should match, and `ax find
   --role AXStaticText --contains "Stack 1 of"` should fail to match.
   `titleText` is set to exactly `"Standalone"` for a single-asset stack
   scope, vs. `"Stack \(stackIndex) of \(stackCount)"` otherwise
   (`LibraryGridView.swift:6461-6475`). Do **not** probe `ax find --role
   AXButton --contains "Stack frame"` — that matches the per-cell
   accessibility label (`.accessibilityLabel("Stack frame \(item.label)")`,
   `LibraryGridView.swift:4898`), which renders for *every* rail stop
   including a standalone one (confirmed live: it matched "Stack frame 1"
   on `smoke-16`'s own one-cell rail) — this is the same "Stack frame"
   probe defect `cull-021`/`cull-022` already found and documented).
   Record a whole-catalog write signal before:
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

7. **Armed-commit leg — still not executable against this card's
   fixtures, same root cause as before, now proven exercisable
   elsewhere.** See Sharp edges for the full investigation. In short: both
   `smoke` and `burst` seed **every** preview level, including `.large`
   (`SmokeCatalogSeeder.renderedLevels = [.micro, .grid, .medium, .large]`,
   `:63`), before the app ever launches — so `previewURL(for:levels:[.large])`
   is non-nil for every asset at Step 1, and the render-gate branch
   (`AppModel.swift:6393-6397`) can never trigger against this card's fixture
   as launched.
   `cull-027-blaze-through-prefetch.md` (SP-C) closes this gap without a
   new fixture generator: it deletes the specific `.large` file under test
   from the *live launched instance's* preview cache after seeding, which
   is enough to make `previewURL(...)` genuinely return `nil` again — this
   card is not updated to use that technique, since Step 7 was never this
   card's focus (force-flip/protection/sidecar/undo/standalone are).
   Falsification condition, unchanged in spirit: stand on a staged frame
   the instant before its `.large` preview exists on disk
   (`previewURL(for:levels:[.large]) == nil` at the moment of the
   keypress); press Return; this leg is falsified if the commit's catalog
   write happens immediately instead of deferring, or if the toast doesn't
   read exactly `"Rendering full preview… will keep when ready"` — see
   `cull-027-blaze-through-prefetch.md` for the full armed-commit
   assertions, including the automatic fire once the render lands (no
   second Return needed) and the disarm-on-any-other-input leg.

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
- Step 7: not a pass/fail leg for *this* card — report explicitly as "not
  executable against this fixture, see Sharp edges" rather than omitting it
  or forcing a substitute fixture. The armed-commit behavior itself is
  exercised (and can fail) in `cull-027-blaze-through-prefetch.md`.

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
  `SmokeCatalogSeeder.renderedLevels`) — it is not specific to `burst`. A
  fresh-import fixture that skips pre-populating the preview cache would
  close this gap the "natural" way (`cull-004-stack-promote-return.md`'s
  "Recommended next step": a burst-fixture generator with EXIF
  `DateTimeOriginal` <=2s apart, imported fresh) but none exists yet.
  `cull-027-blaze-through-prefetch.md` (SP-C) found a simpler workaround
  that needs no new fixture generator: delete the specific `.large` file
  from the *live launched instance's* preview cache after seeding
  (`previewURL(for:levels:)` is a live `FileManager.fileExists` check, not
  a cached DB flag, so this is enough to reopen the gate) — this card is
  not updated to use that technique since Step 7 was never its focus.
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
**PASS-WITH-CARD-FIXES** — run live 2026-07-28 against app build `878f1939`
in the `teststrip-e2e` Tart VM (`burst` fixture, patched per Pre-state).
Steps 1-6 all PASS on both the toast text and SQL/sidecar ground truth,
exactly as specified once three card bugs were fixed (below); Step 7
confirmed live as not executable — `.large` previews exist on disk for
every `burst` asset (`smoke-5`, `smoke-12`, etc.) before the app ever
launches, exactly as the Sharp Edges investigation predicted. No app bugs
found — every defect was in the card's own driving instructions, not the
app.

Card bugs found and fixed:
- **Step 1's `S`-to-cycle instruction was backwards.** `cullScope` defaults
  to `.all` on every fresh launch with no cross-launch persistence
  (`AppModel.swift:2189`); pressing `S` from that default state cycles
  *away* from `.all` (to "Unrated" — confirmed live), not toward it. Fixed
  to skip the `S` press entirely and just assert the chip is already
  absent. (Caught by actually driving it: the first live `S` press produced
  a `"Cull filter: Unrated"` chip instead of the expected absence, which
  also knocked the selection off `smoke-0`, requiring a fresh relaunch to
  recover a known-clean state rather than fighting stack-relative
  navigation back to it — there's no key bound to `.previousPhoto` in
  `CullingKeyCaptureView.swift`'s `init(event:)`.)
- **Step 4's sidecar path construction stripped the wrong thing.**
  `$(basename "$SRC" .jpg).xmp` produces `smoke-7.xmp`, but the sidecar
  store's default/write path is `originalPath + ".xmp"`
  (`XMPSidecarStore.swift:21-22`) — `smoke-7.jpg.xmp`. The stripped form is
  only the store's "Adobe-style" *read* fallback for a sidecar that already
  exists; a freshly-written one never uses it. Fixed to `"${SRC}.xmp"`.
- **Step 6's standalone probe matched the wrong AX element.** `ax find
  --role AXButton --contains "Stack frame"` was expected to fail to match
  on a standalone stop, but the per-cell accessibility label
  `"Stack frame N"` (`LibraryGridView.swift:4880`) renders for every rail
  stop, standalone included (confirmed live: it matched "Stack frame 1" on
  `smoke-16`'s own one-cell rail) — the same probe-can't-distinguish defect
  `cull-021`/`cull-022` already found for this exact AX pattern. Fixed to
  assert on the rail's title text instead (`"Standalone"` present /
  `"Stack N of "` absent), which does carry the distinction
  (`LibraryGridView.swift:6437-6450`).

Originally authored 2026-07-16, source-cited against the working tree by
directly reading `AppModel.swift` (`promoteCurrentFrameAndRejectSiblings`,
`promoteDecisionFeedback`, `applyCullingStackDecision`,
`recordMetadataChangeGroup`/`undoMetadataChange`, `previewURL`,
`applyMetadataSnapshot`/`syncMetadataSidecar`),
`CullFilmstripPresentation.swift` (`CullDecisionToastPresentation`),
`XMPPacket.swift`, `CatalogMigrations.swift`, `CullingKeyCaptureView.swift`,
and `SmokeCatalogSeeder.swift`/`BurstFixtureLayout`.
The render-gate leg (Step 7) was additionally cross-checked against
`cull-004-stack-promote-return.md`'s independent investigation of
`DuplicateFixtureSeeder`'s missing EXIF timestamps.

Reconciled 2026-07-16 → 2026-07-30 (SP-C blaze-through, `937db96b`/
`11cdf360`): the render gate stopped being a plain no-op-with-toast and
became an armed, auto-firing commit — every citation in this file was
re-read against HEAD `11cdf360` and corrected where `AppModel.swift`'s line
numbers had drifted (they had, for nearly every symbol past
`promoteCurrentFrameAndRejectSiblings`'s own start). Steps 1-6 and their
Expected/Sharp-edges prose describe behavior this branch did not touch and
are unaffected; only the render-gate bullet, Step 7, and the two Sharp-edges
bullets discussing it changed in substance. The dated Run status entry
above predates this reconciliation and describes a run against the
pre-armed-commit code — it is left as-is (a historical record of what that
run observed), not restated for the current behavior.

**2026-07-30 addendum**: `cull-027-blaze-through-prefetch.md`'s first live
run (same day) exercised the armed-commit/render-gate leg this card's own
Step 7 stays unable to reach (Sharp edges above) — confirmed live: the
force-flip toast text this card's own Step 2 expects
(`Kept smoke-0.jpg (was ✕) · rejected 2 · ⌘Z undoes`) was directly observed
firing automatically once a deliberately-deleted `.large` preview finished
re-rendering, with the write correctly deferred until then. See that card's
Run status for the full per-assertion account, including two tooling bugs
(one in the shared `vm_scenario_run.sh` harness, one in that card's own
Step 6 driving technique) found and fixed along the way — neither affects
this card, which was not re-run.

**Reconciled 2026-08-09 (Task 13, unified-shell preamble sweep)**: Step 1's
⌘1 preamble is unchanged in effect (⌘1 selects the Cull lens under
`LibraryLens`, same as it selected Cull under the old `Workspace` enum).
Preamble only; no other stale symbol found in this card (its
`CullingKeyCaptureView`/`AppModel` citations don't touch
`CullingKeyCaptureGate`). Supersedes prior status: no substantive change —
the PASS-WITH-CARD-FIXES evidence above is unaffected, noted for the record
per house style.
