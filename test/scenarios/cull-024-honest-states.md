# cull-024-honest-states: the reads panel says "No read yet" before evaluation, and a genuine tie suppresses ✦ with a "too close to call" banner — never a fabricated read

**What this covers**: as a photographer relying on the AI reads to break
ties, I need the UI to be honest about what it doesn't know rather than
inventing a confident-looking answer. Before evaluation runs (zero scored
whole-photo kinds), the loupe's Reads panel must say so plainly ("No read
yet"), not show a stale or default verdict. Once evaluation has produced
exactly one scored whole-photo kind, the panel is honest in a different
way: it shows that lone signal plus an explicit "early read — 1 signal"
caveat instead of either fabricating a verdict or falling back to a blank
"No read yet" — one scored kind is real information, but not enough to
commit to Keep/Toss (Jesse's ruling, 2026-07-23; implemented
fix/cull-followups Task 2, 2026-07-28). When evaluation genuinely produces a
photo finish — two or more frames in a stack scoring within the ranking's
noise floor of each other — no single frame gets crowned: the rail
suppresses its ✦ marker entirely and shows a "too close to call" banner
instead of guessing. All of these states are reachable only by the *actual*
evaluation output of this run's fixture, so this card follows
`cull-021-stack-rail-nav.md`'s honest-branch discipline: assert whichever
state the live evaluation genuinely produces, never force a tie, a
one-signal read, or a clean winner that isn't really there.

Source (re-verified against the working tree on this branch, **2026-07-16**;
fresh grep, not carried over from any older card):
- **Reads panel gating**, `CullReadsCardPresentation.presentation(for:)`
  (`Sources/TeststripApp/CullReadsCardPresentation.swift:45-74`): three
  states, all keyed off `CullingStackRecommendation.normalizedQualityRead`'s
  `kindCount` (`LibraryGridView.swift:6610-6616`). **Zero rankable kinds**
  (the function returns `nil`) is the only "no read at all" state:
  `emptyState: "No read yet"`, no verdict, no rows
  (`CullReadsCardPresentation.swift:46-54`). **Exactly one scored kind** is
  a genuine PARTIAL read (`:55-65`) — reconciled here from this card's
  original (2026-07-16) claim that a single kind rendered "No read yet";
  Jesse's ruling (2026-07-23), implemented fix/cull-followups Task 2
  (2026-07-28), made the old `kindCount >= 2` whole-card gate the FULL-read
  threshold instead: the single row still renders (the same canonical-order
  `signalRows(for:)`, `:79-84`), but no verdict is ever computed —
  `CullingAssistPresentation.verdict` is not called in this branch — and
  `earlyReadCaveat` (`:43`) carries the exact copy `"early read — 1
  signal"`, which the view renders in place of the verdict line. **Two or
  more kinds** is the FULL read (`:66-74`): verdict
  (`CullingAssistPresentation.verdict`, unchanged) plus every scored row,
  `earlyReadCaveat` nil. The doc comment (`:15-26`) documents exactly these
  three states.
  This remains a genuinely different gate than the rail's own ✦
  recommendation (`CullingStackRecommendation.rankedCandidates` via
  `CullingQualityScore.qualityScore`, `LibraryGridView.swift:6564-6580` and
  `Sources/TeststripCore/Evaluation/CullingQualityScore.swift:35-44`), which
  only needs **1** rankable kind (`guard !scoreByKind.isEmpty`) — but the
  divergence it produces is narrower than this card originally described:
  because the Reads panel now also renders *something* for any 1-kind
  frame, a frame can carry the rail's ✦ (a "Recommended" accessibility
  value) while its *own* Reads panel shows a PARTIAL read with **no
  verdict** — not, as this card previously said, while it "still says 'No
  read yet'" (see Step 6, reconciled below, for the exact current
  assertion). Assert whichever state this run's fixture actually
  produces — don't force it.
- **AX surface for the Reads panel**, `cullFacesReadsPanel`
  (`LibraryGridView.swift:4051-4070`): the *whole* faces+reads right panel
  (the Reads card on the left, the Close-Ups rail of face crops on the
  right — reconciled 2026-07-17 from the old top/bottom stacked layout) is
  one `.accessibilityElement(children: .contain)` block carrying an explicit
  `.accessibilityLabel("Reads")` and a three-way fallback
  `.accessibilityValue(readsPresentation.emptyState ?? readsPresentation
  .verdictText ?? readsPresentation.earlyReadCaveat ?? "")` (`:4064-4069`)
  — extended from the old two-way `emptyState ?? verdictText ?? ""` by
  fix/cull-followups Task 2 (2026-07-28) so the container's value doesn't
  collapse to `""` for a PARTIAL read — set directly from the presentation
  struct, independent of which inner view branch actually renders. This
  mirrors `cull-021`'s own lesson about the rail's `✦` (assert the
  deliberate accessibility override, not an incidentally matching inner
  `Text`): for the pre-evaluation state match `--label "Reads" --contains
  "No read yet"`; for a PARTIAL read match `--label "Reads" --contains
  "early read — 1 signal"` (per `script/ax_drive.sh`'s matching rule, both
  `--label`'s exact title/description/value match and `--contains`'s
  substring search over title/description/value/placeholder are ANDed, so
  this pins the container whose title is exactly "Reads" AND whose value
  contains the target substring — `script/ax_drive.sh:169-187`). Because
  `.contain` (not `.combine`) is used, the inner `Text` for whichever branch
  is active — `emptyState` (`LibraryGridView.swift:4159-4162`, the
  `readsCard` empty-state branch) or the caveat (`:4169-4172`) — is *also*
  independently AX-findable as its own element; either match should agree.
  This card treats the container-level value as authoritative since it's
  the deliberate override, not an incidental match.
- **Rail tie suppression**, `CullingStackRailPresentation.init`
  (`LibraryGridView.swift:6137-6279`): computes `tiedLeaderIDs` via
  `CullingStackRecommendation.tiedLeaderIDs` (`:6222-6225`, defined at
  `:6457-6474` — leaders are every candidate whose `normalizedQualityRead`
  is within `tooCloseToCallMargin = 0.03` of the top read, `:6455`, `nil`
  when fewer than 2 candidates qualify). "A tie can't defend a single
  winner, so the ✦ is suppressed entirely rather than arbitrarily picking
  one tied leader to crown" (`:6226-6227`) —
  `recommendation = tiedLeaderIDs == nil ? rankedCandidates.first : nil`
  (`:6228`), so under a tie **no** rail chip's `isRecommended` is `true`
  and **no** chip's accessibility value contains `"Recommended"`
  (`stackChipAccessibilityValue`, `:4620-4624`: `isSelected ? "Selected" :
  (isRecommended ? "Recommended" : "Not selected")`). The banner:
  `tooCloseBanner = tiedLeaderIDs.map { "too close to call — <frame
  labels·joined by ·>" }` (`:6249-6254`), rendered as an orange
  `Text(tooCloseBanner)` directly under the rail's title/position text
  (`:4478-4483`) only when non-nil. The "Keep recommended N" secondary
  action is suppressed the same way (`:6322-6326`), leaving only "Keep
  selected", "Keep top 2" (if 3+ frames), and "Keep all" — a tie removes
  the machine's naming of a winner from every surface it would otherwise
  appear on, not just the ✦.
- **Fixture**: `burst` (`Sources/TeststripBench/SmokeCatalogSeeder.swift:
  33-54`) — 4 auto-groupable stacks (3/4/3/4 frames). A freshly-seeded
  `burst` catalog has **zero** `evaluation_signals` rows (confirm:
  `script/vm_scenario_run.sh sql burst "SELECT count(*) FROM evaluation_signals;"`
  reads 0) — this
  is the guaranteed pre-evaluation state for the first half of this card.
  Whether evaluation then produces a tie, a clean winner, or no rankable
  signal at all on this fixture's flat synthetic rectangles is **not**
  established ahead of time (`cull-021`'s Sharp edges) — this card's second
  half branches on whichever of those three the live run actually produces.

## Pre-state
```bash
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
```

## Steps
1. `ax wait-vended`; ⌘1 for Cull; `S` to cycle scope to "All frames". Select
   a frame that belongs to a multi-frame stack (`ax find --role AXButton
   --contains "Stack frame 1"` confirms one is visible; if none ever appears,
   stop and report this card untestable-without-fixture rather than
   fabricating a stack, per `cull-021`'s caution).
2. **Pre-evaluation: "No read yet" is honest, not a placeholder bug.**
   Confirm zero `evaluation_signals` rows (Source above). Assert the Reads
   panel's container reads exactly this empty state:
   ```bash
   script/vm_scenario_run.sh ax find --label "Reads" --contains "No read yet"
   ```
   and separately confirm no rail chip claims a read it doesn't have: `ax
   find --role AXButton --contains "Recommended"` must fail to match, and no
   chip shows a flaw badge (`EYES CLOSED`/`SOFT` — `ax find --contains "EYES
   CLOSED"` and `--contains "SOFT"` must both fail). Also confirm no
   too-close-to-call banner renders yet — there's nothing to be too close
   about: `ax find --contains "too close to call"` must fail to match.
3. **Trigger evaluation** so the rest of this card means something: Culling
   ▸ "Evaluate Visible" (⇧⌘E, `requestVisibleAssetEvaluations`,
   `AppModel.swift:9188`) — wait for cached previews first if needed, then
   poll (staying frontmost via `wait-vended` each poll, per
   `test/scenarios/README.md`'s idle-wedge caution):
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"
   ```
   until it covers the selected stack's asset ids.
4. **Post-evaluation reads-panel gate.** For the currently-selected frame,
   read its raw signals:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT kind, value_json, confidence FROM evaluation_signals WHERE asset_id = '<selected id>';"
   ```
   Count how many of the seven rankable kinds (`focus`, `eyesOpen`,
   `faceQuality`, `eyeSharpness`, `motionBlur`, `aesthetics`, `framing` —
   `CullingQualityScore.qualityComponent`, `CullingQualityScore.swift:9-31`)
   are present with a `.score` value — this count is exactly
   `normalizedQualityRead`'s `kindCount` (`LibraryGridView.swift:6610-6616`).
   Branch on the count — three honest outcomes, not two:
   - **Zero**: assert the Reads panel still reads "No read yet" (`ax find
     --label "Reads" --contains "No read yet"`) even though evaluation has
     run — the honest empty state, not a stale one — with no verdict and no
     rows.
   - **Exactly one (a PARTIAL read)**: assert `ax find --label "Reads"
     --contains "No read yet"` now fails to match — the card has left the
     empty state — and instead assert the exact early-read caveat renders in
     place of a verdict: `ax find --label "Reads" --contains "early read —
     1 signal"` (exact copy, `CullReadsCardPresentation.swift:63`). Assert
     **no** `AXStaticText` reads exactly `"Keep"` or `"Toss"` — a partial
     read never computes a verdict (`CullingAssistPresentation.verdict` is
     not consulted in this branch, `CullReadsCardPresentation.swift:55-65`)
     — and assert exactly one whole-photo signal row renders (`ax find
     --role AXStaticText --contains "%"` matches exactly one row, for
     whichever of the four canonical kinds — Focus, Motion blur, Framing,
     Aesthetics — actually has the signal).
   - **Two or more (a FULL read)**: assert `ax find --label "Reads"
     --contains "No read yet"` fails to match, then independently compute
     `normalizedQualityRead` (confidence-weighted mean of the best component
     per whole-photo/face kind) and compare it against
     `CullingAssistPresentation`'s thresholds (Keep >= 0.7, Toss <= 0.5) to
     predict which of three honest outcomes this fixture lands in: (a)
     **decisive Keep/Toss** — assert an `AXStaticText` reading exactly
     `"Keep"` or `"Toss"` (no "read" suffix, no percentage, no caveat text)
     matching the predicted verdict; (b) **Mixed** (between the two
     thresholds) — assert **no** `Keep`/`Toss` verdict text and no early-
     read caveat render at all, per the honest-states philosophy (a verdict
     that can't commit says nothing, not a "Mixed" label) — don't treat its
     absence as a bug in this branch. Either way, independently assert the
     whole-photo signal rows: `CullReadsCardPresentation.canonicalSignalOrder`
     (Focus, Motion blur, Framing, Aesthetics) renders as compact
     label+percentage rows — `ax find --role AXStaticText --contains "%"`
     should match at least one row for whichever of those four kinds
     actually has a signal.
   All three branches: confirm no face-specific kind (Face quality, Eye
   sharpness, Eyes open) ever contributes a row here (they render on the
   close-ups rail instead, per `cull-012-closeups-panel.md`).
5. **Tie honest branch.** Compute the stack's tie state independently:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT asset_id, kind, value_json, confidence FROM evaluation_signals WHERE asset_id IN (<stack ids>);"
   ```
   apply `CullingQualityScore.qualityComponent`'s per-kind formula
   (`CullingQualityScore.swift:9-31`) to get each frame's
   confidence-weighted mean (`normalizedQualityRead`,
   `LibraryGridView.swift:6610-6616`), and check whether 2+ frames land
   within `0.03` of the top score (`tooCloseToCallMargin`, `:6622`).
   **Branch on what's actually true**:
   - **If a genuine tie exists** (2+ frames within the margin): assert the
     rail shows the `"too close to call — <frame labels>"` banner (`ax find
     --contains "too close to call"`) naming exactly the tied frames'
     1-based labels, **no** chip's accessibility value contains
     "Recommended" (`ax find --role AXButton --contains "Recommended"`
     fails to match), and no chip renders the `✦` overlay (visually absent
     — cross-check via the accessibility value only, per `cull-021`'s
     caution that `✦` itself isn't independently AX-findable on the rail).
   - **If a single frame genuinely leads** (no tie): assert no
     too-close-to-call banner renders, and exactly one chip's accessibility
     value contains "Recommended", matching the independently-computed
     top scorer.
   - **If evaluation produced no rankable signal for this stack at all**
     (plausible on `burst`'s flat synthetic rectangles per `cull-021`'s
     Sharp edges): assert neither the banner nor any "Recommended" chip
     appears — this is the same honest no-recommendation branch `cull-021`
     documents, not a new failure mode.
   Do not force any of these three branches — assert only the one this run's
   fixture actually produced, cited against the independent computation
   above.
6. **Divergence check (only if the live data happens to produce it):** if
   the selected frame has exactly one scored kind — so its own Reads panel
   is in the PARTIAL-read branch (step 4: one row, the "early read — 1
   signal" caveat, no verdict) — while the rail's chip for that same frame
   reads "Recommended" (step 5's tie-free branch, with this frame as the
   winner), assert this is **not** a bug — it's the documented gate mismatch
   in Source above: the rail's ✦ needs only 1 kind for a *recommendation*,
   the Reads panel needs 2 kinds for a *verdict*. Both surfaces render some
   read for a 1-kind frame; they disagree only on whether it's decisive
   enough to name a winner. If the live data doesn't produce this
   combination, skip this step; don't manufacture it.

## Expected
- Step 2: **Fails if** the Reads panel shows anything other than "No read
  yet" before any evaluation has run, or if any rail chip shows
  "Recommended" or a flaw badge pre-evaluation — that would mean a surface
  is claiming an AI read that doesn't exist yet.
- Step 4: **Fails if** the Reads panel's state disagrees with the
  independently-counted scored-kind total: zero kinds must show "No read
  yet"; exactly one kind must show the single row plus the exact caveat
  "early read — 1 signal" and no `Keep`/`Toss` text; two or more kinds must
  show every scored row and, per the Keep/Toss/Mixed math, either a matching
  verdict or no verdict text at all — "No read yet" must never appear once
  there's at least one scored kind. Regardless of what the rail is doing.
- Step 5: **Fails if** the rail's tie/no-tie/no-signal state disagrees with
  the independently-computed `tooCloseToCallMargin` check, if a
  "Recommended" chip and the too-close-to-call banner ever both appear at
  once (they are mutually exclusive by construction), or if the banner
  names the wrong frames.
- Step 6: **Fails if** it treats the real verdict-vs-recommendation gate
  mismatch as an error, or if it fabricates the divergence — including by
  asserting a 1-kind frame's Reads panel says "No read yet" instead of
  rendering its PARTIAL read — when the live data didn't actually produce
  it.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **This card's honest-branch steps (5-6) may all be no-ops on a given
  run** if `burst`'s synthetic rectangles produce a clean winner every time,
  or never produce 2+ scored kinds on any frame — that is a legitimate
  outcome, not evidence the card is broken. Report which branch was
  observed; don't retry until a tie happens to appear.
- **The Reads panel and the rail read from different scoring functions**
  (`normalizedQualityRead`'s confidence-weighted mean vs. `qualityScore`'s
  summed defect-inversion) — but both now have the same effective 1-kind
  floor for "is there a read at all" (fix/cull-followups Task 2,
  2026-07-28: the Reads panel's old 2-kind floor on the *whole card* is
  gone; only `CullingAssistPresentation.verdict` still has a 2-kind floor).
  The two surfaces are deliberately allowed to disagree only on whether
  there's a **verdict/recommendation** for a single-kind frame — not on
  whether there's a read at all. Don't conflate the two or treat a
  disagreement as automatically wrong; check step 4's independent
  kind-count first.
- **`✦` itself is not independently AX-findable** on the rail (it's a
  `Text("✦")` nested inside a `Button` that already carries an explicit
  `.accessibilityLabel`/`.accessibilityValue`) — assert its absence under a
  tie via the chip's accessibility value never containing "Recommended",
  not by searching for the glyph. See `cull-021-stack-rail-nav.md`'s Sharp
  edges for the full explanation and the contrast with the Compare survey's
  independently-findable `"✦ BEST"` badge (a different, unrelated
  mechanism — `LibraryGridView.swift:5624`, `CompareSurveyPresentation`,
  out of scope for this card).
- **The Compare survey has its own, separate tie mechanism** — tied
  contenders render a `"tied"` rank badge instead of `"#N"`
  (`CompareSurveyPresentation.rankBadges(for:)`, `LibraryGridView.swift:
  5584-5602`) — this is a different surface (Compare's contenders-only
  mode) from the rail's `tooCloseBanner` this card exercises, and is not
  driven here.

## Run status
NOT RUN — authored 2026-07-16, source-cited against the working tree by
directly reading `CullReadsCardPresentation.swift`, `LibraryGridView.swift`
(`CullingStackRailPresentation`/`CullingStackRecommendation`/
`cullFacesReadsPanel`/`readsCard`), and
`Sources/TeststripCore/Evaluation/CullingQualityScore.swift`, not carried
over from any older card; pending live VM execution per
`test/scenarios/README.md`.

**Reconciled 2026-07-28** (fix/cull-followups Task 2, kata #3): the
kindCount==1 branch changed from "No read yet" to a genuine PARTIAL read
(one row + the exact "early read — 1 signal" caveat, no verdict) —
`CullReadsCardPresentation.swift` and the `readsCard`/`cullFacesReadsPanel`
views in `LibraryGridView.swift` were re-read against the working tree, and
every passage in this card (What this covers, Source, Steps 4/5/6,
Expected, Sharp edges) that described the old two-state (empty vs. full)
gate was rewritten to describe the current three-state gate, with line
citations re-verified against the current file. Still NOT RUN — this
reconciliation is a source-only re-verification, not a live VM execution.
