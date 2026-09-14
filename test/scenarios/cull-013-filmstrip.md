# cull-013-filmstrip: The Cull run strip is scope-filtered, shows stack position via the triple counter, and marks decided stops

**What this covers**: As a photographer scanning a burst I want the run strip
beneath the loupe to show only the stops in my current scope, tell me where I
am within the stack sequence, and let me jump to any stop while seeing at a
glance which stops are already fully decided. This card covers inventory
items 36 (scope-filtered, one stop per auto-grouped stack), 37 (the position
counter), and 38 (a stop's current/done marks and click-to-select) **as
re-scoped to the run-strip redesign**: the flat per-frame filmstrip those
items originally named — `cullingFilmstrip` as a live view,
`filmstripTile`/`filmstripDecisionBar` as tile renderers, and
`CullFilmstripPresentation.positionText` — was replaced by one stop per
auto-grouped stack. See Run status.

Source (re-verified against the working tree **2026-09-13**; every symbol
below was re-grepped fresh):
- **Container + scope filter**, `runStrip(isStackActive:)`
  (`Sources/TeststripApp/LibraryGridView.swift:4844-4880`): renders in place
  of `libraryLoupeNavBar` whenever `presentation.showsCullChrome`
  (`:4144-4148`). Scoped assets are
  `CullScopeOrdering.filteredAssets(model.assets, scope: model.cullScope)`
  (`Sources/TeststripApp/AppModel.swift:320-322`), then partitioned into
  stops by `model.allCullingStacks(for: scopedAssets)`
  (`AppModel.swift:7816-7824`). So the strip shows **one stop per
  auto-grouped stack *and* per standalone** in the active scope — never one
  tile per frame.
- **Stops + windowing**,
  `CullRunStripPresentation.stops(assets:stacks:selectedAssetID:visibleLimit:)`
  (`Sources/TeststripApp/CullRunStripPresentation.swift:25-52`),
  `defaultVisibleLimit = 12` (`:9`), windowing via
  `CullStripWindowing.centeredWindow(count:anchorIndex:limit:)` (`:60-68`).
  The full stop/windowing contract is owned by
  `cull-025-run-strip-completion.md`; this card does not re-derive it.
- **Position counter**, `CullFilmstripPresentation.tripleCounterText`
  (`Sources/TeststripApp/CullFilmstripPresentation.swift:11`, computed by the
  static `tripleCounterText(resolved:stacks:frameNumberOffset:fallback:)` at
  `:60-77`). Format:
  `"<frameNumberOffset+frameIndex+1> of <totalFrames> · stack <stackIndex+1> of <stacks.count>"`,
  **plus** `" · frame <withinStackIndex+1> of <stackAssetIDs.count>"` **only
  when** the selected asset's stack has more than one member (`:71-74`).
  With no selection (or an empty scope) it falls back to `"N frame(s)"`
  (`:55-58`). In the unscoped view (`model.cullScope == .all`) `runStrip`
  passes `totalFrameCount: model.totalAssetCount` (`:4851-4857`), so the
  first segment is catalog-wide and agrees with the header's "Frame X of Y";
  scoped views (picks/rejects/unrated) stay scope-local by design. This is
  the exact `"N of T · stack S of Σ · frame F of M"` format — **not** the old
  `"frame X / N"`.
- **Decision / current marks on a stop**, `runStripStop`
  (`LibraryGridView.swift:4919-4935`): a `Button` with
  `.accessibilityLabel("Stop \(stop.label)")` and
  `.accessibilityValue(runStripStopAccessibilityValue(stop))` (`:4947-4953`),
  whose value is `["Current" if isCurrent] + ["Done" if isDone] +
  "N frame(s)"` joined by `", "`. `isDone` requires **every** member's
  `metadata.confirmedProjection.flag != nil` — confirmed flags only, so a
  tentative AI flag does not mark a stop done
  (`CullRunStripPresentation.swift:37`; `CullRunStripPresentationTests
  .testTentativeAIFlagKeepsTheStopUndone` pins this). Visually
  `runStripThumbnailFace` (`:4961-4994`) draws a green checkmark overlay when
  `isDone` (`:4982-4988`) and an orange 2pt selection ring when `isCurrent`
  (`:4990-4993`); `runStripStackThumb` (`:5005-5039`) adds a bottom-trailing
  frame-count badge for a multi-frame stop. There is **no** per-stop decision
  bar or dim on the run strip — the `filmstripDecisionBar` helper now renders
  only on the stack-rail cell (`:5244`, defined `:5312`), not here.
- **Click-to-land**, `selectRunStripStopLanding(_:)` (`:4943-4945`) →
  `model.selectStackLanding(for: stop.assetIDs)`
  (`AppModel.swift:8131-8136`), the same preference-gated recommended-or-first
  landing `H`/`L`/`←`/`→` and Return's post-commit advance use — a click never
  disagrees with keyboard arrival.
- **Status bar**, `runStripStatusBar(tripleCounterText:isStackActive:)`
  (`:4882-4906`): the counter text (`:4889`), the auto-advance chip
  (`runStripAutoAdvanceChip`, `:4908-4917`, text "Auto-advance on"/"off"), the
  scope chip when `model.cullScope != .all` (`cullHUDScopeChip`, `:4893-4895`
  / `:4673-4680`, AX label `"Cull filter: \(scope.label)"`), the nav legend
  (`CullingNavLegendPresentation.legendText`, `:4897` / `:6605-6615`), and a
  `ProgressView` whose fraction comes from `model.cullingProgressSummary`
  (`:4883-4886`).

## Pre-state
```bash
# The `burst` variant guarantees multi-frame auto-stacks (4 groups of
# 3/4/3/4 frames with capture times ~1s apart, inside AssetStackBuilder's 2s
# gap) plus 4 singles = 8 stops over 18 assets. `--smoke`'s default 900s
# spacing (SmokeCatalogSeeder.swift:136) is far outside the adjacency window,
# so on `--smoke` every stop is a standalone and the multi-frame assertions
# below cannot run.
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
# (Host equivalent: swift run TeststripBench seed-burst-catalog <appsupport>.)
```
Then ⌘1 for Cull (lands in the loupe sub-mode, where `showsCullChrome`
renders the run strip in place of `libraryLoupeNavBar`).

## Steps
1. **Scope = All: total and stops.** Record the SQL total:
   ```bash
   TOTAL=$(script/vm_scenario_run.sh sql burst "SELECT count(*) FROM assets;")
   ```
   Assert the status bar's triple-counter first segment total equals `TOTAL`
   (the unscoped view passes `totalFrameCount: model.totalAssetCount`), and
   count the run strip's stops as the `AXButton`s whose accessibility label
   begins `"Stop "` (one per stack; 8 on pristine `burst`). Inspect the AX
   subtree first to scope the count to the strip's container — the loupe and
   rail also carry `AXButton`s (rating stars, rail cells, the auto-advance
   chip's static text is not a button but the scope chip is `Text`).
2. **Scope = Picks: the strip filters, the counter stays scope-local.** Cycle
   `S` to Picks and recompute:
   ```bash
   PICKS=$(script/vm_scenario_run.sh sql burst "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
   ```
   Assert the counter's first-segment total now equals `PICKS` (not `TOTAL` —
   scoped views are scope-local) and the scope chip reads "Picks"
   (`cullHUDScopeChip`). A stack partially filtered by scope yields a stop over
   only its in-scope members, so do not assume the Picks stop count equals the
   All stop count.
3. **Triple-counter format, multi-frame vs standalone.** With a frame in a
   multi-frame stack selected, read the counter
   (`script/ax_drive.sh find --role AXStaticText --contains "stack "`), read
   its full text, and assert it matches
   `"<i> of <T> · stack <S> of <Σ> · frame <F> of <M>"` — three `" of "`
   segments. Select a standalone stop's frame (e.g. `smoke-14`) and assert the
   text has **no** trailing `"frame …"` segment. **Fails if** the separator is
   `"/"`, the wording is `"frame X / N"`, or the third segment renders on a
   standalone.
4. **Click a stop lands the loupe on that stop.** Press a stop other than the
   current one:
   ```bash
   script/ax_drive.sh press --role AXButton --contains "Stop "
   ```
   Assert the focused asset changed to a member of that stop (cross-check the
   HUD filename text per `cull-011-hud.md`, or via `selectStackLanding`'s
   recommended-or-first rule). **Fails if** it is a no-op or lands outside the
   stop.
5. **Decision marking is per-stop and confirmed-only.** Decide every member of
   one stop (`P`/`X`) and assert that stop's accessibility value now contains
   `"Done"`; assert a stop with any undecided member does **not** contain
   `"Done"`. Read the value off the stop's AX element
   (`runStripStopAccessibilityValue`, `:4947-4953`) — this is the only reliable
   AX read of `isDone`/`isCurrent` (the checkmark glyph and orange ring are not
   independently AX-findable). **Fails if** a stop reads "Done" with an
   undecided member, or if the value never updates after a decision.

## Expected
- Steps 1/2: the counter's first-segment total equals the scope's SQL count
  exactly, and the strip re-renders on the scope change. **Fails if** the strip
  shows all frames regardless of scope, or the total lags a scope change.
- Step 3: the counter matches the `"N of T · stack S of Σ[ · frame F of M]"`
  shape; the third segment appears iff the selected stop is multi-frame.
  **Fails if** the format differs from source.
- Step 4: clicking a stop moves loupe focus to a member of that stop.
  **Fails if** it is a no-op or lands on an unrelated asset.
- Step 5: a stop's `"Done"` mark appears exactly when all its members carry a
  confirmed flag. **Fails if** an undecided member still yields "Done" (the
  strip is reading tentative/partial state), or the mark never propagates after
  a decision without a scope refresh.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **`--smoke`'s 900-second seed spacing makes multi-frame stops untestable on
  it** (`SmokeCatalogSeeder.swift:136`) — use `burst` (or `--faces`/
  `--real-corpus`) for Steps 3 and 5. Report honestly if no multi-frame stop
  forms rather than weakening the assertion.
- **Counting stops is AX-role-scoped, not frame-scoped.** Each stop is a plain
  `Button` (`runStripStop`), so a blind `--role AXButton` count over the whole
  window would also catch rating stars and rail cells; scope the count to the
  strip's container after inspecting the live tree.
- **A partial scope yields partial stops.** `filteredAssets` filters at the
  frame level *before* `allCullingStacks` re-partitions, so a stack with some
  members out of scope becomes a smaller stop. Derive expected stop counts from
  the scoped frame set, not from the unscoped cluster count.
- **`isDone` is confirmed-only by construction**; a tentative AI flag keeps a
  stop undone (`CullRunStripPresentation.swift:37`). Step 5 is the live mirror
  of the unit test that pins it.

## Run status
**Rewritten 2026-09-13 (scenario-card/LEDGER hygiene pass)** against the
current run-strip code. The card previously described a flat per-frame
filmstrip (`cullingFilmstrip` as a live view, `filmstripTile`,
`filmstripDecisionBar` as a tile element, and
`CullFilmstripPresentation.positionText` with a `"frame X / N"` format) that a
"run strip" redesign (`CullRunStripPresentation`,
`CullFilmstripPresentation.tripleCounterText`) had already replaced in
`Sources/`; none of those symbols describe the current UI. Supersedes prior
status: the LEDGER's old "Verified"/"final-verify run PASS" describes the flat
filmstrip this branch no longer implements, and already disagreed with the
card's own prior "UNRUN" line. **UNRUN** — needs human-present VM execution
per `test/scenarios/README.md`, after this rewrite, not before.

**LIVE RUN 2026-09-13, Tart VM `teststrip-e2e` (`script/vm_scenario_run.sh`,
run dir `burst-1789360814`, `launch burst`, 18 assets): Steps 1-5 all PASS**
against the current run-strip code the rewrite describes.
- Step 1 (scope All): SQL `TOTAL=18`; counter `1 of 18 · stack 1 of 8 ·
  frame 1 of 3` — first-segment total `18` == `TOTAL`; exactly **8** `AXButton`s
  whose label begins `Stop ` (4 multi-frame stops `smoke-0–2`(3) /
  `smoke-3–6`(4) / `smoke-7–9`(3) / `smoke-10–13`(4) + 4 standalones), which
  matches the pristine-burst expectation. PASS.
- Step 2 (scope Picks): SQL `PICKS=4`; after two `S` presses the chip reads
  `Cull filter: Picks` and the counter is `1 of 4 · stack 1 of 4` — the
  first-segment total is now the **scope-local** `4`, not `18`; the strip
  re-renders to 4 stops. PASS.
- Step 3 (format, both cases): multi-frame frame selected → `6 of 18 ·
  stack 2 of 8 · frame 3 of 4` (three `" of "` segments); standalone `smoke-14`
  → `15 of 18 · stack 5 of 8` (**no** trailing `frame …` segment); separator is
  `"·"`/`" of "`, never `"/"`. PASS.
- Step 4 (click-to-land): pressed `Stop smoke-7–9` → loupe focused `smoke-7`
  (a member of that stop), counter `8 of 18 · stack 3 of 8 · frame 1 of 3`. Not
  a no-op, landed inside the stop. PASS.
- Step 5 (confirmed-only Done marking): initial stop values (from
  `runStripStopAccessibilityValue`) — `Stop smoke-7–9` = `Current, 3 frames`
  (has undecided members, **no** `Done`); `Stop smoke-15` = `Done, 1 frame`
  (its only member was already decided). Decided every member of `smoke-7–9`
  (`P` on `smoke-7`, then `P` on `smoke-8`; `smoke-9` already `pick`) → SQL all
  three `pick`, and the stop value became `Done, 3 frames`. Every stop with an
  undecided member (`smoke-0–2`, `smoke-3–6`, `smoke-10–13`, `smoke-14`,
  `smoke-16`, `smoke-17`) still lacks `Done`. PASS.

Not separately driven: the tentative-AI-flag-keeps-a-stop-undone property
(`CullRunStripPresentationTests.testTentativeAIFlagKeepsTheStopUndone`) —
`burst` carries no tentative ghost flags, so there is no live fixture for it;
this card only mirrors the confirmed-flag case, which held.

Stale line numbers (rewrite re-grepped 2026-09-13 but the file has since grown
~34 lines; symbols alive, behaviour exactly as described): `runStrip`
`LibraryGridView.swift:4844-4880`→`:4878`; `runStripStatusBar`
`:4882-4906`→`:4916`; `selectRunStripStopLanding` `:4943-4945`→`:4977`;
`runStripStopAccessibilityValue` `:4947-4953`→`:4981`; `runStripStop`
`:4919-4935`→`:4953`; `runStripThumbnailFace` `:4961-4994`→`:4995`;
`runStripStackThumb` `:5005-5039`→`:5039`. Exact still:
`CullRunStripPresentation.swift:9`/`:25`, `CullFilmstripPresentation.swift:11`.
Supersedes prior status: fresh full VM run on the current build; all 5 steps
green.
