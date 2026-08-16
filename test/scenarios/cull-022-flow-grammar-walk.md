# cull-022-flow-grammar-walk: H/L/J/K (+ arrows) walk burst and no-burst batches with identical grammar, ✦-or-first landing, and the `A` auto-advance toggle

**What this covers**: as a photographer culling a mixed take, I want the same
four keys — `H`/`L` (across stops) and `J`/`K` (within a stack), plus their
arrow-key twins — to mean the same thing whether the current batch has real
multi-frame bursts or is all standalone singles. On a burst batch `J`/`K`
step within the current stack and `H`/`L` jump across stops, landing on the
stack's AI-recommended frame when the target stop is a multi-frame stack, or
on the frame itself when it's a standalone. On a batch with **no**
multi-frame stacks at all, `H`/`L` now walk the same stop-to-stop grammar as
everywhere else — every standalone photo is its own stop
(`AppModel.allCullingStacks(for:)`'s full partition, not the multi-frame-only
`cullingStacks()`) — so on this fixture `H`/`L` degrade to plain deck advance
identically to `J`/`K`'s own dead-key fix (both were previously dead-key
regressions on an all-singles batch; both are now fixed the same way, via
different code paths that happen to converge on this fixture). This card
also proves the `A` auto-advance toggle is observable through the AX tree,
not just inferred from behavior.

Source (re-verified against the working tree on this branch, **2026-07-16**;
cull-021's own citations for this machinery were already stale after 3 days,
so every symbol below was re-grepped fresh, not carried over):
- **Key → shortcut mapping**, `CullingShortcut` — two independent encoders
  that must agree: the live NSEvent monitor's `init?(event:)`
  (`Sources/TeststripApp/CullingKeyCaptureView.swift:130-180`, arrow keycodes
  in `MacKeyCode`, `:182-193` — left `123`, right `124`, down `125`, up
  `126`) and the character-based `init?(key:)` used by both that monitor's
  fallback branch and the `?`/menu advertisement
  (`Sources/TeststripApp/AppModel.swift:187-241`). Both agree: `h`/`leftArrow`
  → `.previousStack`; `l`/`rightArrow` → `.nextStack`; `j`/`downArrow` →
  `.nextCandidateInStack`; `k`/`upArrow` → `.previousCandidateInStack`
  (`AppModel.swift:122-242` for the `CullingShortcut` enum itself — note the
  vim-style aliases are h/l for the *arrow* pair, j/k for the *arrow* pair,
  not a literal remap of vim's own left/right-vs-up/down convention, since
  h/l here mirror the arrow-key stack-crossing role and j/k mirror the
  arrow-key within-stack role). The monitor only fires with no
  command/control/option modifier held
  (`CullingKeyCaptureView.swift:132-133`) and only while
  `CullingKeyCaptureGate.isActive` — `lens == .cull && selectedView !=
  .cullGrid` (`:12-14`) — i.e. the Cull lens's loupe/compare/A-B views,
  not the grid.
- **Within-stack step**, `AppModel.selectNextCandidateInStack()` /
  `selectPreviousCandidateInStack()` (`AppModel.swift:7547-7553`) →
  `moveSelectionWithinCurrentCullingStack(by:)` (`:7555-7574`): when the
  selection has a real multi-frame stack (`selectedCullingStackScope` is
  non-nil, which requires membership in a stack with `assetIDs.count > 1` —
  `cullingStacks()` filters to `.count > 1`, `:7395-7397`), this steps one
  frame at a time within `stackAssetIDs`, no wrap, stopping dead at either
  end (`:7570-7572`). **When the selection has no such stack** (a standalone
  frame — `selectedCullingStackScope` is `nil`, or its `assetIDs` don't
  contain the selection), the guard at `:7556-7558` fails and it falls back
  to `selectNextAssetForCulling()`/`selectPreviousAssetForCulling()` — plain
  stop-to-stop advance through the deck in `cullScope`-filtered catalog
  order, the same helpers `Space`/`.nextPhoto` use (`:7346-7359` and
  `:7694-7707` respectively — no longer adjacent; the T7.5 stack-navigation
  machinery below now sits between them) — per the comment at `:7559-7561`:
  "fall back to stop-to-stop advance through the deck rather than going
  dead." This fallback is unit-tested directly:
  `Tests/TeststripAppTests/CullStackNavigationTests.swift:38-76`
  (`testNextCandidateFallsBackToStopToStopAdvanceWhenSelectedAssetHasNoStack`
  / the `Previous` twin) seeds two singles 30s apart (outside
  `AssetStackBuilder`'s 2s gap, `Sources/TeststripCore/Search/
  AssetStackBuilder.swift:14`) and asserts `.nextCandidateInStack`/
  `.previousCandidateInStack` still move the selection between them.
- **Across-stop jump**, `selectNextStackForCulling()`/
  `selectPreviousStackForCulling()` (`AppModel.swift:7529-7541`): tries a
  persisted `work-stack-` session first, else `selectCullingStack(_:)`
  (`:7623-7665`), which — since T7.5 — builds `indexedStacks` from
  `cullingStopSequence()` (`:7419-7421`: `allCullingStacks(for: assets)`,
  the **full** partition, every multi-frame stack *and* every standalone
  photo as its own stop), not the multi-frame-only `cullingStacks()` a
  prior revision of this card (and this line's own citation) assumed.
  `guard !indexedStacks.isEmpty else { return }` (`:7632`) is now the true
  empty-catalog guard, not an all-singles-batch guard — a batch with zero
  multi-frame stacks still produces one `indexedStack` per photo, so `H`/`L`
  walk it one stop at a time, stopping dead (no wrap) at either end, exactly
  mirroring `J`/`K`'s own fallback. When the target stop **is** a
  multi-frame stack, `selectCullingStack` lands on
  `recommendedStackLandingAssetID(for:)` (`:7676-7679`:
  `guard cullLandOnRecommendedFrame else { return stack.assetIDs.first }`,
  then `recommendedCullingStackAssetID(in:) ?? stack.assetIDs.first`) — the
  ranked winner if evaluation produced one (or, under a too-close-to-call
  tie, the first tied leader in capture order), otherwise the stack's first
  frame; a standalone stop resolves to its one asset either way (the doc
  comment at `:7667-7675` is explicit, and also names the
  `cullLandOnRecommendedFrame` toggle — default `true`, Culling-menu-only,
  no keyboard shortcut — that this card never touches, so every landing
  below is the "land on recommended" branch, not its "land on frame 1
  unconditionally" off-state). See `cull-021-stack-rail-nav.md` steps 5/10-11
  for the full independent-ranking cross-check methodology; this card only
  needs to confirm the *landing rule* holds for whichever branch this run's
  evaluation state actually produces, not re-derive it.
- **`A` auto-advance toggle**, `cullAutoAdvanceEnabled` (`AppModel.swift:2113`,
  default `true`) / `toggleCullAutoAdvance()` (`:7166-7178`): flips the flag
  and sets `lastCullingMetadataDecision` to an *informational* toast reading
  exactly `"Auto-advance on"` or `"Auto-advance off"` (no ✓/✕ symbol, no
  "⌘Z undoes" — `CullDecisionToastPresentation.init(feedback:)`,
  `Sources/TeststripApp/CullFilmstripPresentation.swift:86-99`, the
  `isInformational` branch at `:86-93`). The toast renders as a bare
  SwiftUI `Text` with no accessibility override
  (`Sources/TeststripApp/LibraryGridView.swift:4468-4477`,
  `decisionToast`), so its AXStaticText title/value is the literal string —
  but it is **transient**: `showDecisionToastThenFade()`
  (`:4447-4462`) shows it, sleeps 2 real seconds, then fades it out. There is
  no persistent AX-exposed indicator of `cullAutoAdvanceEnabled` elsewhere
  (grepped `main.swift` for a menu checkbox — none exists); the toast is the
  *only* direct AX read of the toggle, so it must be polled for immediately
  after pressing `A`, not after some other setup delay. Behaviorally, when
  the decision that follows has no stack context (`stackAssetIDs` is `nil`
  — the standalone-frame arm, the only one this card's `smoke` fixture ever
  exercises), `applyCullingCommandAndAdvance` (`:7282-7312`) advances via
  `selectNextAssetForCulling()` only when `cullAutoAdvanceEnabled` is `true`
  and the command didn't itself already move the selection (`:7290`) — this
  is the behavioral cross-check this card uses to corroborate the toast.
  (The function also has a stack-context arm — hop to the next undecided
  sibling within the current stack, wrapping to the next stop's landing
  frame once every sibling is decided — that this card's `smoke`-only Step
  10 never reaches; a card covering `A` on a `burst` stack would need to
  account for it separately.)
- **Fixtures**: `burst` (`TeststripBench seed-burst-catalog`,
  `Sources/TeststripBench/SmokeCatalogSeeder.swift:33-54` — 4 auto-groupable
  stacks of 3/4/3/4 frames 1s apart, plus 4 trailing singles) for the burst
  leg; `smoke` (`TeststripBench seed-app-catalog`, default capture spacing
  `TimeInterval(index * 900)` — 15 minutes — `SmokeCatalogSeeder.swift:136`,
  well outside `AssetStackBuilder`'s 2s gap) for the no-burst leg, where
  **every** one of the 24 seeded assets is a singleton with respect to
  `cullingStacks()` (no pair is ever `<=2s` apart).

## Pre-state
Two independent launches, one per leg — run Leg A's steps to completion,
quit that instance, then launch Leg B. Do not conflate their state; `smoke`
has zero multi-frame stacks by construction, so it must never inherit a
`burst` instance's selection/rail state.
```bash
# Leg A (burst): multi-frame stacks exist. Run before Steps 1-6.
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth: script/vm_scenario_run.sh sql burst "..."
```
```bash
# Leg B (no-burst): run after Leg A's instance is quit, before Steps 7-10.
script/vm_scenario_run.sh sync smoke && script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended
# ground truth: script/vm_scenario_run.sh sql smoke "..."
```
Key-sends below go through `script/vm_scenario_run.sh key '...'`: a letter is
`keystroke "h"`; an arrow is `key code N` using the codes cited above (left
123, right 124, down 125, up 126) — both encoders are asserted to agree, so
either form should exercise the same code path.

## Steps — Leg A: burst batch (multi-frame stacks exist)
1. `ax wait-vended`; ⌘1 for Cull; `S` to cycle scope to "All frames"
   (`CullScope.displayName == "All frames"`, avoids scope hiding a stack
   member). Confirm a **multi-frame** stack is selected: the rail's title
   reads `"Stack N of M"`, not `"Standalone"` (`ax find --role AXStaticText
   --contains "Stack "`), AND a second frame chip exists (`ax find --role
   AXButton --contains "Stack frame 2"`). Do **not** rely on `"Stack frame
   1"` alone — `CullingStackRailPresentation` renders a one-cell rail entry
   labeled `"Stack frame 1"` for every selection, standalone or not
   (`LibraryGridView.swift:6426-6430`'s doc comment: "A standalone
   (single-photo stop) still gets a rail entry... but none of the
   stack-only chrome"), so that check alone would pass on an all-singles
   batch too (see Step 7 and Sharp edges). If no multi-frame stack is ever
   selected, stop and report this leg untestable-without-fixture rather
   than fabricating a stack (per `cull-021`'s own caution).
2. Record the stack's asset ids in catalog order via SQL
   (`script/vm_scenario_run.sh sql burst "SELECT id FROM assets ORDER BY rowid LIMIT 4;"`,
   adjusted to the actual selected stack) and its frame count from the rail's
   `positionText` (`ax find --role AXStaticText --contains "Frame "`).
3. **`J`/`K` step within the stack, identical to ↓/↑.** From frame 1, press
   `J` (`keystroke "j"`): assert the selection moves to frame 2
   (`stackAssetIDs[1]`), the rail's `"Stack N of M"` title text is
   unchanged (still the same stack), and the newly-selected chip's
   accessibility value contains `"Selected"`. Press `K`
   (`keystroke "k"`): assert it steps back to frame 1. Repeat with the raw
   arrow keys (`key code 125` for Down, `key code 126` for Up) from the same
   starting position and assert byte-identical results (same target asset
   id, same title-unchanged invariant) — this is the "identical grammar"
   claim for the letter vs. arrow encoders.
4. **`J` stops dead at the stack's last frame** (no wrap, no crossing into
   the next stack): advance to the last frame, press `J` once more, assert
   the selection does not move and the rail's title text still names the
   same stack (mirrors `cull-021` step 8, re-asserted here for the letter
   key specifically).
5. **`H`/`L` cross stacks, identical to ←/→.** From frame 1 of the current
   stack, press `L` (`keystroke "l"`): assert the rail's `"Stack X of Y"`
   index advances by one and the newly-selected frame is a member of the
   *different* stack. Press `H` (`keystroke "h"`): assert it returns to the
   previous stack. Repeat with `key code 124`/`key code 123` (Right/Left)
   and assert identical targets.
6. **Landing rule on the crossed-into stack**: independently compute which
   frame the new stack's ranking should pick, per `cull-021-stack-rail-nav.md`
   steps 5-6's methodology (`evaluation_signals` for the stack's ids,
   `CullingStackRecommendation`'s formula) — if evaluation hasn't run yet on
   this fresh launch, trigger it first (Culling ▸ "Evaluate Visible", ⇧⌘E,
   `AppModel.swift:9998-10011`, `requestVisibleAssetEvaluations`) and wait for
   `evaluation_signals` to cover the stack. The landing frame and the
   `"Recommended"` chip are governed by two *different* rules that only
   coincide on a clear, untied winner (per `cull-021`'s own step-11 finding
   for this same fixture) — compute `tiedLeaderIDs` independently
   (`CullingStackRecommendation.tiedLeaderIDs`,
   `LibraryGridView.swift:6685-6701`) before asserting either:
   - **Clear winner** (`tiedLeaderIDs` nil, a read exists): lands on
     `rankedCandidates.first`, and that frame's chip **does** show
     `"Recommended"`.
   - **Too-close-to-call tie** (`tiedLeaderIDs` has ≥2 members): lands on
     `tiedLeaderIDs.first` (capture order) — a real, non-frame-1 landing in
     general — but **no** chip shows `"Recommended"` (`recommendation =
     tiedLeaderIDs == nil ? rankedCandidates.first : nil`,
     `LibraryGridView.swift:6441` — a tie can't defend a single winner, so
     the marker is suppressed even though a landing frame was still picked).
   - **Zero rankable signals** (no `evaluation_signals` cover the stack at
     all): lands on the stack's first frame (capture order), also with no
     `"Recommended"` chip — but for a different reason than the tie case
     (no ranking data exists at all, vs. ranking data existing but being
     too close to call).
   Assert whichever of these three branches this run's evaluation genuinely
   produces (synthetic `burst` frames may score no signals at all, or may
   tie — see `cull-021`'s Sharp edges); do not force a specific branch, and
   do not conflate "landed on a non-recommended frame" with "landed on
   frame 1" — the tie branch is neither.

## Steps — Leg B: no-burst batch (zero multi-frame stacks)
7. Launch `smoke` fresh (Pre-state above); `ax wait-vended`; ⌘1 for Cull; `S`
   to "All frames". Confirm no **multi-frame** stack renders for the current
   selection: the rail's title reads `"Standalone"` (`ax find --role
   AXStaticText --contains "Standalone"`) and no `"Stack frame 2"` (or
   higher) chip exists (`ax find --role AXButton --contains "Stack frame 2"`
   fails to match) — the smoke fixture has zero multi-frame stacks by
   construction. **Do not** assert bare `"Stack frame"` fails to match: a
   standalone stop still gets its own one-cell rail entry labeled `"Stack
   frame 1"` (`LibraryGridView.swift:6426-6430`), so that check matches on
   every launch, `smoke` included, and would make this step spuriously fail.
   Record the selected asset id and the catalog-order id sequence:
   `script/vm_scenario_run.sh sql smoke "SELECT id FROM assets ORDER BY rowid LIMIT 5;"`.
8. **Headline assertion — the fixed dead-key case.** Press `J`
   (`keystroke "j"`) repeatedly (3-4 times) from the first asset: assert the
   selection advances one asset per keypress, in the exact order the SQL
   query above returned (the same order `Space`/`.nextPhoto` walks) — it
   does **not** stay put. This is the behavior
   `CullStackNavigationTests.testNextCandidateFallsBackToStopToStopAdvanceWhenSelectedAssetHasNoStack`
   encodes at the unit level; this step is its live-UI counterpart. Press
   `K` the same number of times and assert it walks back to the start, one
   asset per keypress. Repeat with `key code 125`/`key code 126` (Down/Up)
   from the same starting position and assert identical targets — same
   "identical grammar" claim as Leg A step 3, now for the fallback path.
9. **`H`/`L` now walk stop-to-stop on an all-singles batch too — the T7.5
   fix, formerly the mirror-image dead-key case.** From the first asset,
   press `L` (`keystroke "l"`) repeatedly (3-4 times): assert the selection
   advances one asset per keypress, in the exact order Step 7's SQL query
   returned — identical to `J`'s fallback in Step 8, just a different key.
   Press `H` the same number of times and assert it walks back to the
   start, one asset per keypress. Repeat with the raw arrow keys (`key code
   124`/`key code 123` for Right/Left) from the same starting position and
   assert identical targets — same "identical grammar" claim as Step 8, now
   for `H`/`L`. Then confirm the stop-at-the-end behavior mirrors `J`/`K`'s
   no-wrap guard: advance to the last asset (`L` repeatedly), press `L`
   once more, and assert the selection does not move.
10. **`A` toggle, observable via AX value.** Note `cullAutoAdvanceEnabled`
    defaults to `true` (`AppModel.swift:2113`). Press `P` (pick) on an
    unrated frame: with auto-advance on by default, assert the selection
    already advanced to the next frame (behavioral baseline). Press `A`
    (`keystroke "a"`) and *immediately* poll
    `script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Auto-advance off"`
    (poll promptly — the toast fades after 2 real seconds,
    `LibraryGridView.swift:4469`). Then press `X` (reject) on the
    now-current frame: assert the selection does **not** advance this time
    (behavioral cross-check that the toggle actually took effect, not just
    that a toast happened to say so). Press `A` again; assert the toast now
    reads `"Auto-advance on"` (same prompt-polling caveat); press `P` on the
    next frame and assert the selection advances again.

## Expected
- Step 3: **Fails if** `J`/`K` ever cross into a different stack (title text
  changes), wrap, move more than one frame, or if the letter and arrow forms
  disagree on the resulting selection.
- Step 4: **Fails if** `J` at the last frame moves the selection at all.
- Step 5: **Fails if** `H`/`L` move within the same stack instead of
  switching stacks, or if the letter and arrow forms disagree.
- Step 6: **Fails if** the landing frame disagrees with the
  independently-computed three-way branch (clear winner / first tied leader
  during a too-close-to-call tie / stack's first frame on zero rankable
  signals) for the actual evaluation state, or if the `"Recommended"` chip
  renders on anything but a clear, untied winner — it must be absent during
  a tie even though the landing frame itself is real ranked data in that
  case, per `CullingStackRecommendation`'s tie-suppression rule — but not a
  failure if evaluation genuinely produced no ranking at all (see Source's
  honest-branch note).
- Step 8: **Fails if** `J`/`K` do not move the selection on the no-burst
  batch (a regression back to "going dead"), if they move by other than one
  asset per keypress, or if the letter and arrow forms disagree.
- Step 9: **Fails if** `H`/`L` do not move the selection on the no-burst
  batch (a regression back to the pre-T7.5 no-op), if they move by other
  than one asset per keypress, if the letter and arrow forms disagree, or
  if `L` at the last asset wraps or moves the selection at all.
- Step 10: **Fails if** the toast text is absent, wrong, or the auto-advance
  behavior (selection moves/doesn't move after a decision) disagrees with
  the toggle's last-announced state.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Run for both legs (burst launch, then smoke launch) — quit each app instance
before the next leg's launch.

## Sharp edges
- **`J`/`K` and `H`/`L` converge to the same behavior on a no-stack batch,
  via two different code paths — this used to be the opposite.** Before
  T7.5, `J`/`K`'s within-stack job had a documented fallback to deck-wide
  advance while `H`/`L`'s cross-stack job had none (there was structurally
  no "different stack" to cross into on an all-singles batch), so step 9
  asserted a true no-op. T7.5 gave `H`/`L` their own full-partition stop
  sequence (`cullingStopSequence()`, every standalone included), so on this
  fixture both keys now walk one asset at a time — but they still reach
  that result via genuinely different functions
  (`moveSelectionWithinCurrentCullingStack`'s no-stack fallback vs.
  `selectCullingStack`'s stop-sequence walk), and only agree because every
  "stop" on this specific fixture happens to be a single asset. On a
  **mixed** batch (Leg A) they remain deliberately different: `J`/`K` never
  leave the current stack, `H`/`L` always cross to the next stop.
- **The `A` toast is the only AX-exposed read of `cullAutoAdvanceEnabled`,
  and it fades in 2 real seconds.** A driver that presses `A` and then does
  several other `find`/`sql` round-trips before polling for the toast will
  likely miss it — poll immediately, and lean on the behavioral cross-check
  (step 10's pick/reject-then-check-selection) as the load-bearing evidence
  if the timing proves too tight to drive reliably.
- **This card does not re-derive the ranking math** for step 6's landing
  rule — `cull-021-stack-rail-nav.md` owns that derivation in full (raw
  `evaluation_signals` reads, the confidence-weighted formula, the
  too-close-to-call margin). This card only asserts the landing *rule*
  (the three-way clear-winner / first-tied-leader / first-frame branch —
  see step 6) holds, using whatever ranking state that card's methodology
  would independently confirm. Watch for the trap step 6 itself now warns
  about: a too-close-to-call tie still lands on a specific, real frame (the
  first tied leader in capture order), which is neither "recommended" nor
  "frame 1 because nothing ranked" — conflating it with the latter is
  exactly the bug this run found and fixed.
- **Both legs require a fresh launch** — a `burst` catalog and a `smoke`
  catalog cannot share one running instance, since the whole point of Leg B
  is that *zero* multi-frame stacks exist in it. Driving both in the same
  card run means two full VM launch cycles.
- **A rail cell renders even for a standalone (single-photo) stop — a bare
  `"Stack frame"` probe can never distinguish a multi-frame stack from an
  all-singles batch.** `CullingStackRailPresentation.init` always emits at
  least one `Item` for the current selection, labeled `"Stack frame 1"`,
  whether or not it belongs to a real multi-frame stack — only the
  stack-only chrome (title `"Stack N of M"` vs. `"Standalone"`, the
  `"Frame N of M"` positionText, the ✦ marker, keep/cut actions) is gated on
  `!isStandalone` (`LibraryGridView.swift:6426-6430`'s doc comment: "A
  standalone (single-photo stop) still gets a rail entry... but none of the
  stack-only chrome"). Confirmed live on both legs
  of this run: `smoke`'s first asset (`smoke-0`, no sibling within 2s of
  anything) renders a `"Stack frame 1"` chip with title `"Standalone"` and
  an empty `"Frame N of M"` positionText — structurally identical to what a
  real multi-frame stack's frame-1 chip looks like by that one probe alone.
  This card's original steps 1 and 7 both keyed their multi-frame-vs-not
  confirmation off a bare `"Stack frame"`/`"Stack frame 1"` match, which
  cannot actually tell the two cases apart; fixed to check the title text
  (`"Stack N of M"` vs. `"Standalone"`) plus a `"Stack frame 2"` probe
  instead.

## Run status
NOT RUN — authored 2026-07-16, source-cited against the working tree by
directly reading `CullingKeyCaptureView.swift`, `AppModel.swift`,
`CullFilmstripPresentation.swift`, `LibraryGridView.swift`, and
`CullStackNavigationTests.swift`, not carried over from any older card;
pending live VM execution per `test/scenarios/README.md`. Reconciled
2026-07-16 (same day, later pass): the original authoring predated a T7.5
behavior fix (`AppModel.swift:7618-7622`'s doc comment: "Before T7.5 this
used `cullingStacks()` directly, so standalone stops were skipped on mixed
batches and every key was a dead no-op on all-singles batches") — `H`/`L`
now walk the full stop sequence (every standalone included), not just
multi-frame stacks. The headline, the "Across-stop jump" Source bullet,
step 9, its Expected bullet, and the first Sharp edges bullet were rewritten
to match; steps 1-8 and 10 and the rest of the card are unchanged.

**RUN 2026-07-28, app 878f1939 (merged main): PASS-WITH-CARD-FIXES.** Both
legs executed against fresh VM launches (`burst-1785288094`,
`smoke-1785288670`). Every assertion checkable against the AX tree/SQL
passed on both legs; all 10 steps' letter-vs-arrow-key pairs produced
byte-identical results throughout. Two classes of card bugs found and fixed
above, both documentation drift, **no app bugs**:
1. **Steps 1 and 7's multi-frame-vs-standalone probe was unsound.** A bare
   `ax find --role AXButton --contains "Stack frame"`/`"Stack frame 1"`
   match cannot distinguish a real multi-frame stack from a standalone —
   `CullingStackRailPresentation` renders a one-cell rail entry for every
   selection regardless (see the new Sharp edges bullet). Caught live: Leg
   B's very first `ax find --role AXButton --contains "Stack frame 1"`
   matched on `smoke-0`, a guaranteed-standalone asset, which would have
   made step 7's literal "should fail to match" assertion FAIL against
   correct app behavior. Fixed both steps to key off the rail's title text
   (`"Stack N of M"` vs. `"Standalone"`) plus a `"Stack frame 2"` probe.
2. **Step 6 (and its Expected bullet) described a two-way
   "Recommended-or-frame-1" landing branch; the app's actual
   `CullingStackRecommendation` machinery is a three-way branch** — clear
   winner, first tied leader during a too-close-to-call tie (a real,
   non-frame-1 landing that still suppresses the `"Recommended"` chip), or
   the stack's first frame on zero rankable signals. Confirmed live and
   independently computed (same methodology and, on this fixture, the exact
   same numbers as `cull-021`'s step 5/10-11): stack 1 (`smoke-0/1/2`) ties
   between `smoke-1`/`smoke-2` (`smoke-0` excluded, 0.0375 outside the 0.03
   margin) → `H` from stack 2 landed on `smoke-1` (frame 2, not frame 1),
   no `"Recommended"` chip anywhere; stack 2 (`smoke-3..6`) ties across all
   4 members → `L` landed on `smoke-3` (frame 1, coincidentally, as the
   first tied leader), also no `"Recommended"` chip. Rewrote step 6 and its
   Expected bullet to describe the three-way branch explicitly.

Also did a full citation sweep of every `AppModel.swift`/
`LibraryGridView.swift`/`CullFilmstripPresentation.swift` line number in the
Source and Steps sections while investigating the above (systematic drift
of 28-250 lines in several bullets, evidently from real feature work landing
in `AppModel.swift` between this card's 2026-07-16 authoring and this run —
`applyCullingCommandAndAdvance`'s stack-context arm, noted inline in the `A`
auto-advance bullet, wasn't even present in the card's original
description). The `CullingShortcut`/key-capture citations near the top of
Source checked out within 1-16 lines (not worth touching); every citation
past `cullAutoAdvanceEnabled` onward needed correcting and now does.

Full run report: `.superpowers/card-runs/cull-022-run.md`.

**Reconciled 2026-08-09 (Task 13, unified-shell preamble sweep)**: Steps 1's
and 7's ⌘1 presses are unchanged in effect. Preamble only — but while
verifying it, found and fixed a stale symbol citation in the Source section:
`CullingKeyCaptureGate.isActive`'s predicate was cited with the pre-rename
parameter name (`workspace == .cull && ...`); corrected to `lens ==` and the
line range to `:12-14`, re-verified directly against
`CullingKeyCaptureView.swift`. Supersedes prior status: the 2026-07-28
PASS-WITH-CARD-FIXES run above is unaffected — it never depended on this
citation's parameter name — but the citation itself was wrong at the time
of that run and is fixed now, not retroactively re-verified against that
run's build.
