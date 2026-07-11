# cull-014-stack-rail: Stack rail's primary Keep button and its secondary action set

**What this covers**: As a photographer working a burst I want the stack
rail's big "Keep" button to keep the frame I'm looking at (and reject its
siblings) in one gesture, plus secondary shortcuts for keeping the
recommended/top-ranked frame(s) or the whole stack when none should be cut.
Covered inventory items 39 (rail: primary Keep + secondary actions + frame
chips) and 40 (guidance text/action set — resolved below by reading
`CullingStackActionPresentation` directly, per assignment). Source:
`cullingStackRail` at `Sources/TeststripApp/LibraryGridView.swift:3992-4075`,
`CullingStackRailPresentation` (action list construction) at `:5456-5639`,
`CullingStackAction` enum at `:5641-5646`, action dispatch
(`performCullingStackAction`/`keepSelectedStackFrame`) at `:4313-4353`.

**Resolving the "Action set in Core unread" ambiguity**: `grep -n "struct
CullingStackActionPresentation"` finds it in
`Sources/TeststripApp/LibraryGridView.swift:5648`, **not** in
`TeststripCore` — it's a view-layer presentation type, not a Core model.
The real action set (`CullingStackAction`, `:5641-5646`) is exactly four
cases: `keepSelectedAndRejectAlternates`, `keepTopRanked([AssetID])`,
`keepRecommended(AssetID)`, `keepAll`. `CullingStackRailPresentation.init`
(`:5557-5577`) always builds exactly three action entries in this order:
1. `.keepSelectedAndRejectAlternates` — title `"Keep frame N · cut M"`, always
   enabled, help `"Keep selected frame and reject stack alternates"`.
2. `Self.rankedAction(...)` (`:5603-5638`) — **`.keepTopRanked([top2])`**
   titled `"Keep top 2"` if the stack has >2 frames and 2+ ranked candidates
   exist; otherwise **`.keepRecommended(assetID)`** titled `"Keep recommended
   N"`, or `nil` (omitted) if there's no ranked candidate at all.
3. `.keepAll` — title `"Keep all N"`, always enabled.

**Correction to the assumed guidance semantics**: the rail's **primary**
"Keep" button (`presentation.actions.first`, always
`.keepSelectedAndRejectAlternates`) does **not** follow keepRecommended/
topRanked guidance — its handler `keepSelectedStackFrame()` calls
`model.promoteCurrentFrameAndRejectSiblings()` unconditionally on whatever
frame is currently *selected* in the loupe, regardless of which frame the
ranking recommends. The recommended/top-ranked guidance only surfaces via
(a) the secondary action button (item 2 above) and (b) the `✦` marker on the
recommended chip/filmstrip tile and the HUD's stack-guidance verdict text
(`cullingStackGuidanceAction`, `cull-011-hud.md` item 33). Clicking the
*secondary* "Keep recommended N" button does select the recommended asset
first, then applies the same `keepSelectedStackFrame()` promote (`:4321-4324`)
— so it, not the primary button, is the "keep the guidance pick" gesture.

**Fixture prerequisite**: the rail requires a stack with 2+ frames
(`stackScope.assetIDs.count > 1`, `:5521`) resolved either from an explicit
persisted `CullingStackScope` (the `work-stack-` `asset_sets` rows) or the
same in-memory `AssetStackBuilder` auto-grouping the filmstrip uses
(`cull-013-filmstrip.md`). Independently re-derived here (not borrowed from
another card's run): `--smoke`'s 900-second seed spacing
(`SmokeCatalogSeeder.swift:105`) is outside the 2-second
`candidateStackMaximumCaptureGap` (`AppModel.swift:2184`), so `--smoke`
produces **no auto-stacks and no persisted `work-stack-` sets** — this card
uses the `burst` seed variant (`TeststripBench seed-burst-catalog`), whose
capture times are 1s apart within each group, guaranteeing 4 multi-frame
auto-stacks (3/4/3/4 frames) plus 4 singles.

## Pre-state
```bash
# The `burst` variant guarantees multi-frame auto-stacks (4 groups of
# 3/4/3/4 frames with capture times 1s apart, inside AssetStackBuilder's
# 2s gap) plus 4 singles:
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
# (Host equivalent: swift run TeststripBench seed-burst-catalog <appsupport>.)
```

## Steps
1. Confirm a 2+-frame auto-stack exists by watching for the rail
   (`presentation.isVisible == !items.isEmpty`) to render on some selection:
   ```bash
   script/ax_drive.sh find --contains "rectangle.stack" # or find the "Stack N of M" label text
   ```
   If it never appears across the `--faces` set, stop and report this card
   as untestable-without-fixture — do not fabricate a stack.
2. Select a non-recommended frame within the stack. Read the evaluation
   signals to independently confirm which frame is actually recommended
   (cross-check against the `✦` marker, not just eyeballing the UI):
   ```bash
   sqlite3 "$DB" "SELECT asset_id, signal_kind, value_json FROM evaluation_signals WHERE asset_id IN (<stack member ids>);"
   ```
   (confirm the real table/column names against `CatalogMigrations.swift`
   before running — not independently re-verified in this pass beyond the
   `EvaluationSignal` Swift type name.)
3. Click the rail's **primary** "Keep" button
   (`script/ax_drive.sh press --role AXButton --contains "Keep frame"`).
   Assert it kept the **selected** frame (from step 2), not the recommended
   one — i.e. it applied `keepSelectedAndRejectAlternates` semantics on the
   currently-focused asset:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN (<stack member ids>);"
   ```
4. Undo (⌘Z) to revert the stack promote from step 3 — cross-check against
   `cull-pass-scope-and-undo.md`'s established Return-gesture undo semantics
   (one ⌘Z reverts the whole pick+reject-siblings transaction as a unit).
5. Re-select a frame in the stack, then click the **secondary** "Keep
   recommended N" / "Keep top 2" button
   (`script/ax_drive.sh press --role AXButton --contains "Keep recommended"`
   or `"Keep top 2"`, whichever `rankedAction` produced). Assert it kept the
   ranked/recommended frame(s) specifically, matching what step 2's
   evaluation-signal read predicted, regardless of which frame was selected
   beforehand.
6. Assert the frame chips render one per stack member
   (`presentation.items`, `:5538-5546`) with the `✦` marker on exactly the
   recommended one and a small red dot on any chip whose asset has
   `flawBadges` (`CompareSurveyPresentation.flawBadges`):
   ```bash
   script/ax_drive.sh find --role AXButton --label "Stack frame 1"
   ```
   (chip accessibility label is `"Stack frame \(label)"` per
   `:accessibilityLabel("Stack frame \(item.label)")`, value carries
   Selected/Recommended + flaw text per `stackChipAccessibilityValue`).

## Expected
- Step 3: **Fails if** the primary button kept the recommended frame instead
  of the selected one — that would mean the source changed since this card
  was written and the "primary Keep = keep selection" reading above is
  stale; re-verify against `keepSelectedStackFrame()` before assuming the
  test is wrong.
- Step 4: **Fails if** ⌘Z doesn't cleanly revert all flags the step-3 gesture
  set, or reverts more/less than that one gesture (see
  `cull-pass-scope-and-undo.md`'s undo-grouping assertions for the pattern).
- Step 5: **Fails if** the secondary button's kept frame(s) don't match the
  ranking read in step 2, or if it also affects frames outside the current
  stack.
- Step 6: **Fails if** the chip count != stack member count, the `✦` is on
  the wrong chip, or a chip with known flaws (per `evaluation_signals`) shows
  no flaw dot.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **This card shares the persisted/auto-grouped stack fixture gap** noted in
  `cull-013-filmstrip.md` and (for the persisted `work-stack-` variant)
  `cull-pass-scope-and-undo.md`. No independent evidence was gathered in
  this pass that `--faces` actually produces a qualifying auto-stack — step
  1 is a real gate, not a formality.
- The primary/secondary button distinction (item 40's real resolution) is a
  meaningfully different behavior than "guidance text = keepRecommended
  falling back to topRanked" as originally assumed — that fallback logic
  (`rankedAction`) governs only the *secondary* button's label/target and
  the HUD's stack-guidance verdict text, never the primary Keep button's
  actual write. Do not conflate the two in the runner.
- `evaluation_signals` table/column names used in steps 2/3 were not
  independently re-verified against `CatalogMigrations.swift` in this pass —
  confirm before running; get the schema wrong and step 2's cross-check will
  silently return nothing rather than fail loudly.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md
