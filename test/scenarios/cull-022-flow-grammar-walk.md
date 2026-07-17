# cull-022-flow-grammar-walk: H/L/J/K (+ arrows) walk burst and no-burst batches with identical grammar, ✦-or-first landing, and the `A` auto-advance toggle

**What this covers**: as a photographer culling a mixed take, I want the same
four keys — `H`/`L` (across stacks) and `J`/`K` (within a stack), plus their
arrow-key twins — to mean the same thing whether the current batch has real
multi-frame bursts or is all standalone singles. On a burst batch `J`/`K`
step within the current stack and `H`/`L` jump across stacks, landing on the
stack's AI-recommended frame when one exists. On a batch with **no**
multi-frame stacks at all, `J`/`K` degrade gracefully to plain deck advance
(the fixed dead-key case — they used to go dead with no stack to navigate
within) while `H`/`L` correctly have nothing to cross into and are true
no-ops. This card also proves the `A` auto-advance toggle is observable
through the AX tree, not just inferred from behavior.

Source (re-verified against the working tree on this branch, **2026-07-16**;
cull-021's own citations for this machinery were already stale after 3 days,
so every symbol below was re-grepped fresh, not carried over):
- **Key → shortcut mapping**, `CullingShortcut` — two independent encoders
  that must agree: the live NSEvent monitor's `init?(event:)`
  (`Sources/TeststripApp/CullingKeyCaptureView.swift:130-180`, arrow keycodes
  in `MacKeyCode`, `:182-193` — left `123`, right `124`, down `125`, up
  `126`) and the character-based `init?(key:)` used by both that monitor's
  fallback branch and the `?`/menu advertisement
  (`Sources/TeststripApp/AppModel.swift:240-294`). Both agree: `h`/`leftArrow`
  → `.previousStack`; `l`/`rightArrow` → `.nextStack`; `j`/`downArrow` →
  `.nextCandidateInStack`; `k`/`upArrow` → `.previousCandidateInStack`
  (`AppModel.swift:191-239` for the `CullingShortcut` enum itself — note the
  vim-style aliases are h/l for the *arrow* pair, j/k for the *arrow* pair,
  not a literal remap of vim's own left/right-vs-up/down convention, since
  h/l here mirror the arrow-key stack-crossing role and j/k mirror the
  arrow-key within-stack role). The monitor only fires with no
  command/control/option modifier held
  (`CullingKeyCaptureView.swift:132-133`) and only while
  `CullingKeyCaptureGate.isActive` — `workspace == .cull && selectedView !=
  .cullGrid` (`:11-15`) — i.e. the Cull workspace's loupe/compare/A-B views,
  not the grid.
- **Within-stack step**, `AppModel.selectNextCandidateInStack()` /
  `selectPreviousCandidateInStack()` (`AppModel.swift:6877-6883`) →
  `moveSelectionWithinCurrentCullingStack(by:)` (`:6885-6904`): when the
  selection has a real multi-frame stack (`selectedCullingStackScope` is
  non-nil, which requires membership in a stack with `assetIDs.count > 1` —
  `cullingStacks()` filters to `.count > 1`, `:6735-6737`), this steps one
  frame at a time within `stackAssetIDs`, no wrap, stopping dead at either
  end (`:6899-6903`). **When the selection has no such stack** (a standalone
  frame — `selectedCullingStackScope` is `nil`, or its `assetIDs` don't
  contain the selection), the guard at `:6886-6888` fails and it falls back
  to `selectNextAssetForCulling()`/`selectPreviousAssetForCulling()` — plain
  stop-to-stop advance through the deck in `cullScope`-filtered catalog
  order, the same helpers `Space`/`.nextPhoto` use (`:6686-6721`) — per the
  comment at `:6889-6891`: "fall back to stop-to-stop advance through the
  deck rather than going dead." This fallback is unit-tested directly:
  `Tests/TeststripAppTests/CullStackNavigationTests.swift:38-76`
  (`testNextCandidateFallsBackToStopToStopAdvanceWhenSelectedAssetHasNoStack`
  / the `Previous` twin) seeds two singles 30s apart (outside
  `AssetStackBuilder`'s 2s gap, `Sources/TeststripCore/Search/
  AssetStackBuilder.swift:14`) and asserts `.nextCandidateInStack`/
  `.previousCandidateInStack` still move the selection between them.
- **Across-stack jump**, `selectNextStackForCulling()`/
  `selectPreviousStackForCulling()` (`AppModel.swift:6859-6871`): tries a
  persisted `work-stack-` session first, else `selectCullingStack(_:)`
  (`:6947-6989`), which builds `indexedStacks` **only from
  `cullingStacks()`** (the same `>1`-frame filter above) and returns
  immediately, doing nothing, if that list is empty
  (`guard !indexedStacks.isEmpty else { return }`, `:6956`) — on a batch with
  **zero** multi-frame stacks, `H`/`L` are true no-ops regardless of how many
  times pressed or which frame is selected, because there is structurally
  nothing to cross into. This is the asymmetry with `J`/`K`'s dead-key fix
  above: `J`/`K`'s job (step within a stack) degrades to a sane fallback when
  there's no stack; `H`/`L`'s job (cross into a different stack) has no
  fallback because "a different stack" doesn't exist on an all-singles
  batch — assert the no-op explicitly, don't mistake it for a bug. When a
  target stack does exist, `selectCullingStack` lands on
  `recommendedStackLandingAssetID(for:)` (`:6994-6996`:
  `recommendedCullingStackAssetID(in:) ?? indexedStack.firstAssetID`) — the
  ranked winner if evaluation produced one (or, under a too-close-to-call
  tie, the first tied leader in capture order — `:6812-6827`), otherwise the
  stack's first frame. See `cull-021-stack-rail-nav.md` steps 5/10-11 for the
  full independent-ranking cross-check methodology; this card only needs to
  confirm the *landing rule* holds for whichever branch this run's
  evaluation state actually produces, not re-derive it.
- **`A` auto-advance toggle**, `cullAutoAdvanceEnabled` (`AppModel.swift:2165`,
  default `true`) / `toggleCullAutoAdvance()` (`:6521-6533`): flips the flag
  and sets `lastCullingMetadataDecision` to an *informational* toast reading
  exactly `"Auto-advance on"` or `"Auto-advance off"` (no ✓/✕ symbol, no
  "⌘Z undoes" — `CullDecisionToastPresentation.init(feedback:)`,
  `Sources/TeststripApp/CullFilmstripPresentation.swift:64-77`, the
  `isInformational` branch at `:68-72`). The toast renders as a bare
  SwiftUI `Text` with no accessibility override
  (`Sources/TeststripApp/LibraryGridView.swift:4348-4358`,
  `decisionToast`), so its AXStaticText title/value is the literal string —
  but it is **transient**: `showDecisionToastThenFade()`
  (`:4327-4342`) shows it, sleeps 2 real seconds, then fades it out. There is
  no persistent AX-exposed indicator of `cullAutoAdvanceEnabled` elsewhere
  (grepped `main.swift` for a menu checkbox — none exists); the toast is the
  *only* direct AX read of the toggle, so it must be polled for immediately
  after pressing `A`, not after some other setup delay. Behaviorally, when
  the decision that follows has no stack context (`stackAssetIDs` is `nil`
  — the standalone-frame arm), `applyCullingCommandAndAdvance`
  (`:6622-6652`) advances via `selectNextAssetForCulling()` only when
  `cullAutoAdvanceEnabled` is `true` and the command didn't itself already
  move the selection (`:6630`) — this is the behavioral cross-check this
  card uses to corroborate the toast.
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
   member). Confirm a multi-frame stack is selected: `ax find --role
   AXButton --contains "Stack frame 1"`. If it never appears, stop and report
   this leg untestable-without-fixture rather than fabricating a stack (per
   `cull-021`'s own caution).
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
   `AppModel.swift:9188`, `requestVisibleAssetEvaluations`) and wait for
   `evaluation_signals` to cover the stack. Assert the `L`/`H` landing chip's
   accessibility value contains `"Recommended"` when a real ranked winner (or
   first tied leader) exists, else assert it landed on frame 1 — assert
   whichever branch this run's evaluation genuinely produces (synthetic
   `burst` frames may score no signals at all — see `cull-021`'s Sharp
   edges); do not force a specific branch.

## Steps — Leg B: no-burst batch (zero multi-frame stacks)
7. Launch `smoke` fresh (Pre-state above); `ax wait-vended`; ⌘1 for Cull; `S`
   to "All frames". Confirm no stack rail renders for the current selection
   (`ax find --role AXButton --contains "Stack frame"` should fail to
   match) — the smoke fixture has zero multi-frame stacks by construction.
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
9. **`H`/`L` are true no-ops on an all-singles batch.** From any selected
   asset, press `L` (`keystroke "l"`) 3 times, then `H` 3 times: assert the
   selection never changes across any of these 6 presses (still the same
   asset id each time). This is the asymmetry documented in Source above —
   `J`/`K` degrade to a working fallback, `H`/`L` correctly do nothing
   because there is no stack to cross into. **Do not** expect `H`/`L` to
   also fall back to linear advance; that would contradict the source
   (`selectCullingStack`'s `indexedStacks.isEmpty` guard returns
   unconditionally, with no fallback branch).
10. **`A` toggle, observable via AX value.** Note `cullAutoAdvanceEnabled`
    defaults to `true` (`AppModel.swift:2165`). Press `P` (pick) on an
    unrated frame: with auto-advance on by default, assert the selection
    already advanced to the next frame (behavioral baseline). Press `A`
    (`keystroke "a"`) and *immediately* poll
    `script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Auto-advance off"`
    (poll promptly — the toast fades after 2 real seconds,
    `LibraryGridView.swift:4333`). Then press `X` (reject) on the
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
- Step 6: **Fails if** the landing chip's "Recommended"/frame-1 state
  disagrees with the independently-computed ranking for the actual
  evaluation state — but not a failure if evaluation genuinely produced no
  ranking (see Source's honest-branch note).
- Step 8: **Fails if** `J`/`K` do not move the selection on the no-burst
  batch (a regression back to "going dead"), if they move by other than one
  asset per keypress, or if the letter and arrow forms disagree.
- Step 9: **Fails if** `H`/`L` move the selection at all on the no-burst
  batch — silently falling back to linear advance would be a regression
  disagreeing with the cited source, not a bugfix.
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
- **`J`/`K` and `H`/`L` are not symmetric on a no-stack batch, and that is
  correct.** `J`/`K`'s within-stack job has a documented, unit-tested
  fallback to deck-wide advance; `H`/`L`'s cross-stack job has no such
  fallback because "the next stack" is not a meaningful target when no
  stack exists at all. Do not read step 9's no-op as evidence of a bug
  mirroring step 8's fix — they are different code paths
  (`moveSelectionWithinCurrentCullingStack` vs. `selectCullingStack`) with
  deliberately different failure behavior.
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
  (recommended-if-any, else frame 1) holds, using whatever ranking state
  that card's methodology would independently confirm.
- **Both legs require a fresh launch** — a `burst` catalog and a `smoke`
  catalog cannot share one running instance, since the whole point of Leg B
  is that *zero* multi-frame stacks exist in it. Driving both in the same
  card run means two full VM launch cycles.

## Run status
NOT RUN — authored 2026-07-16, source-cited against the working tree by
directly reading `CullingKeyCaptureView.swift`, `AppModel.swift`,
`CullFilmstripPresentation.swift`, `LibraryGridView.swift`, and
`CullStackNavigationTests.swift`, not carried over from any older card;
pending live VM execution per `test/scenarios/README.md`.
