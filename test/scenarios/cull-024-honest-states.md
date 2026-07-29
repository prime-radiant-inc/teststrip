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
  (`Sources/TeststripApp/CullReadsCardPresentation.swift:51-97`): three
  states, all keyed off `CullingStackRecommendation.normalizedQualityRead`'s
  `kindCount` (`LibraryGridView.swift:6633-6639`). **Zero rankable kinds**
  (the function returns `nil`) is the only "no read at all" state:
  `emptyState: "No read yet"`, no verdict, no rows
  (`CullReadsCardPresentation.swift:52-60`). **Exactly one scored kind that
  is one of the four whole-photo canonical kinds** is a genuine PARTIAL
  read (`:81-87`) — reconciled here from this card's original (2026-07-16)
  claim that a single kind rendered "No read yet"; Jesse's ruling
  (2026-07-23), implemented fix/cull-followups Task 2 (2026-07-28), made
  the old `kindCount >= 2` whole-card gate the FULL-read threshold instead:
  the single row still renders (the same canonical-order `signalRows(for:)`,
  `:102-107`), but no verdict is ever computed —
  `CullingAssistPresentation.verdict` is not called in this branch — and
  `earlyReadCaveat` (`:49`) carries the exact copy `"early read — 1
  signal"`, which the view renders in place of the verdict line. **Exactly
  one scored kind that is face-specific instead** (`faceQuality`/
  `eyeSharpness`/`eyesOpen` — `kindCount` counts all seven rankable kinds,
  but `signalRows(for:)`, `:102-107`, only ever renders the four
  whole-photo ones) falls back to the *same* "No read yet" empty state
  (`:70-78`) rather than a caveat with nothing to show for it — a
  reviewer-found gap in this task's first pass (a lone face-specific
  signal originally rendered the caveat with an empty row list, an
  honest-states violation), fixed in a same-day fix/cull-followups Task 2
  follow-up commit, 2026-07-28; that signal's own home is the close-ups
  rail, not this card. **Two or more kinds** is the FULL read (`:89-97`):
  verdict (`CullingAssistPresentation.verdict`, unchanged) plus every
  scored row, `earlyReadCaveat` nil. The doc comment (`:15-32`) documents
  exactly these three states, including the face-specific exception.
  This remains a genuinely different gate than the rail's own ✦
  recommendation (`CullingStackRecommendation.rankedCandidates` via
  `CullingQualityScore.qualityScore`, `LibraryGridView.swift:6587-6603` and
  `Sources/TeststripCore/Evaluation/CullingQualityScore.swift:35-44`), which
  only needs **1** rankable kind of *any* type, including face-specific
  (`guard !scoreByKind.isEmpty`) — so the divergence this produces now
  takes two forms: a lone whole-photo kind gives a PARTIAL read with **no
  verdict** on this card while the rail's chip may read "Recommended" (not,
  as this card previously said, while it "still says 'No read yet'"); a
  lone face-specific kind gives a genuine "No read yet" on this card while
  the rail's chip may *still* read "Recommended" (the rail ranks
  face-specific kinds too). See Step 6, reconciled below, for the exact
  current assertions for both. Assert whichever state this run's fixture
  actually produces — don't force it.
- **AX surface for the Reads panel**, `cullFacesReadsPanel`
  (`LibraryGridView.swift:4074-4093`): the *whole* faces+reads right panel
  (the Reads card on the left, the Close-Ups rail of face crops on the
  right — reconciled 2026-07-17 from the old top/bottom stacked layout) is
  one `.accessibilityElement(children: .contain)` block carrying an explicit
  `.accessibilityLabel("Reads")` and a three-way fallback
  `.accessibilityValue(readsPresentation.emptyState ?? readsPresentation
  .verdictText ?? readsPresentation.earlyReadCaveat ?? "")` (`:4087-4092`)
  — extended from the old two-way `emptyState ?? verdictText ?? ""` by
  fix/cull-followups Task 2 (2026-07-28) so the *source-level* value doesn't
  collapse to `""` for a PARTIAL read — set directly from the presentation
  struct, independent of which inner view branch actually renders, at the
  Swift call-site. **This card previously claimed (unverified against a live
  run) that `--label "Reads" --contains "..."` pins this container and
  should be treated as authoritative — live-driving this run disproved that
  claim.** A direct `AXUIElementCopyAttributeNames` dump of the container
  confirmed `AXValue` is entirely absent from its attribute list in every
  state (empty/partial/full); the string set via `.accessibilityValue(...)`
  is exposed only under `AXValueDescription`, an attribute
  `script/ax_drive.sh`'s `--contains` search never inspects (it hays over
  title/description/value/placeholder only, `script/ax_drive.sh:169-187`).
  So `--label "Reads" --contains X` fails to match for *every* X, in every
  state — not just the already-known Mixed/full-read `""` hole. Contrast
  with a native `AXButton` (the rail chip): its `.accessibilityValue`
  (`"Selected"`/`"Recommended"`/`"Not selected"`) *does* map straight to
  `AXValue` (confirmed live), so this is a role-dependent SwiftUI→AX
  bridging quirk specific to a plain `.accessibilityElement(children:
  .contain)` view, not a universal one. Because `.contain` (not `.combine`)
  is used, the inner `Text` for whichever branch is active — `emptyState`
  (`LibraryGridView.swift:4182-4185`, the `readsCard` empty-state branch),
  the verdict, or the caveat (`:4192-4195`) — is independently AX-findable
  as its own element; **treat the bare `ax find --contains "..."` match
  against that inner `Text` as authoritative, not the container-label
  match**, which this run showed is structurally dead as a test technique
  on this build (macOS 26 Tahoe). This doesn't mean the presentation logic
  is wrong — the correct string is still genuinely computed and exposed to
  assistive tech via `AXValueDescription`, just not via the attribute
  `ax_drive.sh` checks.
- **Rail tie suppression**, `CullingStackRailPresentation.init`
  (`LibraryGridView.swift:6326-6462`): computes `tiedLeaderIDs` via
  `CullingStackRecommendation.tiedLeaderIDs` (call site `:6397-6400`,
  defined at `:6647-6664` — leaders are every candidate whose
  `normalizedQualityRead` is within `tooCloseToCallMargin = 0.03` of the top
  read, `:6645`, `nil` when fewer than 2 candidates qualify, `:6663`). "A
  tie can't defend a single winner, so the ✦ is suppressed entirely rather
  than arbitrarily picking one tied leader to crown" (`:6401-6402`) —
  `recommendation = tiedLeaderIDs == nil ? rankedCandidates.first : nil`
  (`:6403`), so under a tie **no** rail chip's `isRecommended` is `true`
  and **no** chip's accessibility value contains `"Recommended"`
  (`stackChipAccessibilityValue`, `:4897-4901`: `isSelected ? "Selected" :
  (isRecommended ? "Recommended" : "Not selected")`). The banner:
  `tooCloseBanner = tiedLeaderIDs.map { "too close to call — <frame
  labels·joined by ·>" }` (`:6417-6422`), rendered as an orange
  `Text(tooCloseBanner)` directly under the rail's title/position text
  (`:4756-4761`) only when non-nil. The "Keep recommended N" secondary
  action is suppressed the same way: the guard `tiedLeaderIDs == nil, let
  recommendation = rankedCandidates.first else { return nil }` inside
  `Self.rankedAction` (`:6512-6516`; call site passing `tiedLeaderIDs` at
  `:6448-6453`) — corrected from this card's stale `:6322-6326` citation,
  which had drifted onto unrelated `stackScope`-resolution code — leaving
  only "Keep selected", "Keep top 2" (if 3+ frames), and "Keep all" — a tie
  removes the machine's naming of a winner from every surface it would
  otherwise appear on, not just the ✦.
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
1. `ax wait-vended`; ⌘1 for Cull. **Do not press `S`.** A fresh `burst`
   launch's `cullScope` already defaults to `.all` (`AppModel.swift:2189`,
   the same finding `cull-021` established and confirmed live again this
   run) — the "Cull filter" chip only renders for `!= .all`
   (`LibraryGridView.swift:4554-4555`), so its absence confirms scope
   without cycling. Pressing `S` on a fresh launch cycles *away* from "All
   frames" (confirmed live this run: one `S` press left the scope reading
   "Cull filter: Unrated," per `CullScope`'s cycle order,
   `AppModel.swift:301,316-360`) — this card's prior wording had the cycle
   direction backwards. Harmless to this card's own assertions
   (`requestVisibleAssetEvaluations`, `AppModel.swift:9434-9447`, iterates
   the loaded `assets` list directly, not the cull-scope-filtered queue, so
   Step 3's 18/18 evaluation coverage was unaffected when this run hit the
   mistake) but confusing and unnecessary — leave scope alone. Select a
   frame that belongs to a multi-frame stack (`ax find --role AXButton
   --contains "Stack frame 1"` confirms one is visible; if none ever appears,
   stop and report this card untestable-without-fixture rather than
   fabricating a stack, per `cull-021`'s caution).
2. **Pre-evaluation: "No read yet" is honest, not a placeholder bug.**
   Confirm zero `evaluation_signals` rows (Source above). Assert the Reads
   panel shows exactly this empty state via its inner `Text`:
   ```bash
   script/vm_scenario_run.sh ax find --contains "No read yet"
   ```
   **Not** `--label "Reads" --contains "..."` — confirmed live this run
   (direct `AXUIElementCopyAttributeNames` dump) that the combined match
   never succeeds on the container, in any of the three states; see Sharp
   edges for the root cause. The bare `--contains` match against the inner
   `Text` is the reliable one. Separately confirm no rail chip claims a read
   it doesn't have: `ax find --role AXButton --contains "Recommended"` must
   fail to match, and no chip shows a flaw badge (`EYES CLOSED`/`SOFT` —
   `ax find --contains "EYES CLOSED"` and `--contains "SOFT"` must both
   fail). Also confirm no
   too-close-to-call banner renders yet — there's nothing to be too close
   about: `ax find --contains "too close to call"` must fail to match.
3. **Trigger evaluation** so the rest of this card means something: Culling
   ▸ "Evaluate Visible" (⇧⌘E, `requestVisibleAssetEvaluations`,
   `AppModel.swift:9434`) — wait for cached previews first if needed, then
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
   `normalizedQualityRead`'s `kindCount` (`LibraryGridView.swift:6633-6639`).
   Branch on the count — three honest outcomes, not two. **Use the bare
   `ax find --contains "..."` form throughout this step, never `--label
   "Reads" --contains "..."`** — confirmed live this run that the combined
   container-label match never succeeds regardless of state (Sharp edges);
   the bare match against the inner `Text` is the one that actually tracks
   the branch:
   - **Zero**: assert the Reads panel still reads "No read yet"
     (`ax find --contains "No read yet"`) even though evaluation has run —
     the honest empty state, not a stale one — with no verdict and no rows.
   - **Exactly one**: this count doesn't distinguish *which* kind — split
     further on whether that lone kind is one of the four whole-photo
     canonical kinds or one of the three face-specific ones
     (`faceQuality`/`eyeSharpness`/`eyesOpen`):
     - **Whole-photo kind (a PARTIAL read)**: assert
       `ax find --contains "No read yet"` now fails to match — the card has
       left the empty state — and instead assert the exact early-read
       caveat renders in place of a verdict:
       `ax find --contains "early read — 1 signal"` (exact copy,
       `CullReadsCardPresentation.swift:86`). Assert **no** `AXStaticText`
       reads exactly `"Keep"` or `"Toss"` — a partial read never computes a
       verdict (`CullingAssistPresentation.verdict` is not consulted in
       this branch, `CullReadsCardPresentation.swift:61-88`) — and assert
       exactly one whole-photo signal row renders (`ax find --role
       AXStaticText --contains "%"` matches exactly one row, for whichever
       of the four canonical kinds — Focus, Motion blur, Framing,
       Aesthetics — actually has the signal).
     - **Face-specific kind**: assert the Reads panel still reads "No read
       yet" (`ax find --contains "No read yet"`) — a lone face-specific
       signal has zero renderable whole-photo rows, so this card honestly
       falls back to the empty state rather than showing a caveat with
       nothing to show for it (`CullReadsCardPresentation.swift:70-78`);
       that signal's own read lives on the close-ups rail instead
       (`cull-012-closeups-panel.md`), not this card.
   - **Two or more (a FULL read)**: assert
     `ax find --contains "No read yet"` fails to match, then independently compute
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
   `LibraryGridView.swift:6633-6639`), and check whether 2+ frames land
   within `0.03` of the top score (`tooCloseToCallMargin`, `:6645`).
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
6. **Divergence check (only if the live data happens to produce it):** two
   independent variants, either or neither of which may appear on a given
   run:
   - If the selected frame has exactly one scored **whole-photo** kind — so
     its own Reads panel is in the PARTIAL-read branch (step 4: one row,
     the "early read — 1 signal" caveat, no verdict) — while the rail's
     chip for that same frame reads "Recommended" (step 5's tie-free
     branch, with this frame as the winner), assert this is **not** a bug
     — it's the documented gate mismatch in Source above: the rail's ✦
     needs only 1 kind for a *recommendation*, the Reads panel needs 2
     kinds for a *verdict*. Both surfaces render some read for a 1-kind
     frame; they disagree only on whether it's decisive enough to name a
     winner.
   - If instead the selected frame's *only* scored kind is face-specific
     (`faceQuality`/`eyeSharpness`/`eyesOpen`) — so its own Reads panel is
     back in the "No read yet" empty state (step 4's face-specific
     sub-branch) — while the rail's chip for that same frame still reads
     "Recommended" (the rail's `qualityScore` ranks face-specific kinds
     too, unlike this card's `signalRows`), assert this is **also not** a
     bug: same verdict-vs-recommendation gate mismatch, just landing on
     the empty state because this card has nothing whole-photo to show —
     not because the read doesn't exist.
   If the live data doesn't produce either combination, skip this step;
   don't manufacture it.

## Expected
- Step 2: **Fails if** the Reads panel shows anything other than "No read
  yet" before any evaluation has run, or if any rail chip shows
  "Recommended" or a flaw badge pre-evaluation — that would mean a surface
  is claiming an AI read that doesn't exist yet.
- Step 4: **Fails if** the Reads panel's state disagrees with the
  independently-counted scored-kind total and kind identity: zero kinds
  must show "No read yet"; exactly one kind must show either (a) the
  single row plus the exact caveat "early read — 1 signal" and no
  `Keep`/`Toss` text, if that kind is one of the four whole-photo canonical
  kinds, or (b) "No read yet" with no caveat and no rows, if that kind is
  face-specific instead; two or more kinds must show every scored row and,
  per the Keep/Toss/Mixed math, either a matching verdict or no verdict
  text at all. Regardless of what the rail is doing.
- Step 5: **Fails if** the rail's tie/no-tie/no-signal state disagrees with
  the independently-computed `tooCloseToCallMargin` check, if a
  "Recommended" chip and the too-close-to-call banner ever both appear at
  once (they are mutually exclusive by construction), or if the banner
  names the wrong frames.
- Step 6: **Fails if** it treats either real verdict-vs-recommendation gate
  mismatch as an error, or if it fabricates a divergence — including by
  asserting a 1-whole-photo-kind frame's Reads panel says "No read yet"
  instead of rendering its PARTIAL read, or by asserting a
  1-face-specific-kind frame's Reads panel shows a caveat instead of "No
  read yet" — when the live data didn't actually produce the combination
  being asserted.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **The Reads panel's container-level `.accessibilityValue` never surfaces
  via `AXValue`, in any of the three states — confirmed live 2026-07-28,
  not just theorized.** A direct `AXUIElementCopyAttributeNames` dump of the
  `cullFacesReadsPanel` `AXGroup` (`.accessibilityElement(children:
  .contain)`) shows `AXValue` entirely absent from its attribute list; the
  string passed to `.accessibilityValue(...)` lands only under
  `AXValueDescription`, which `script/ax_drive.sh`'s `--contains` search
  never inspects. This means `ax find --label "Reads" --contains "..."`
  fails to match *unconditionally* — a prior version of this card (and the
  fix/cull-followups Task 2 branch that touched this code) assumed it would
  work for the empty/partial states and only documented a narrower hole for
  the Mixed full-read case (source-level `?? ""` fallback); that narrower
  theory is now superseded — the mechanism is a role-dependent SwiftUI→AX
  bridging quirk (a plain accessibility-element `AXGroup`'s String value
  goes to `AXValueDescription`, not `AXValue`), not a per-state gap. A
  native `AXButton` (the rail's stack chips) does *not* have this problem —
  its `.accessibilityValue` maps straight to `AXValue`, confirmed live via
  the same dump technique (`"Stack frame 1"`'s chip: `AXValue = "Selected"`).
  **Use the bare `ax find --contains "..."` match against the inner `Text`
  for every Reads-panel assertion in this card**, never the
  `--label "Reads" --contains "..."` combined form. This is a
  `script/ax_drive.sh` / SwiftUI-AX-bridging limitation, not a
  `CullReadsCardPresentation` defect — the correct string is still genuinely
  computed and would reach VoiceOver via `AXValueDescription`; fixing
  `ax_drive.sh` to also hay over `AXValueDescription` would make the
  container-level match usable again, but that's shared infra outside this
  card's scope to change.
- **This card's honest-branch steps (5-6) may all be no-ops on a given
  run** if `burst`'s synthetic rectangles produce a clean winner every time,
  or never produce 2+ scored kinds on any frame — that is a legitimate
  outcome, not evidence the card is broken. Report which branch was
  observed; don't retry until a tie happens to appear.
- **The Reads panel and the rail read from different scoring functions**
  (`normalizedQualityRead`'s confidence-weighted mean vs. `qualityScore`'s
  summed defect-inversion), and their "is there a read at all" floors are
  *not* quite the same, even after fix/cull-followups Task 2 (2026-07-28)
  removed the Reads panel's old 2-kind floor on the *whole card*: the
  rail's `qualityScore` renders *something* for any 1 rankable kind of
  *any* type, whole-photo or face-specific. The Reads panel renders
  *something* (a PARTIAL read) for a 1-kind frame only when that kind is
  one of the four whole-photo canonical kinds — a lone face-specific kind
  still falls back to "No read yet" on this card (a same-day
  fix/cull-followups Task 2 follow-up, 2026-07-28, closed a gap where the
  first version rendered the early-read caveat with zero rows for exactly
  this case); that signal's own read lives on the close-ups rail instead.
  Only `CullingAssistPresentation.verdict` has a clean, unconditional
  2-kind floor. Don't conflate any of these three floors, or treat a
  disagreement as automatically wrong; check step 4's independent
  kind-count *and kind identity* first.
- **`✦` itself is not independently AX-findable** on the rail (it's a
  `Text("✦")` nested inside a `Button` that already carries an explicit
  `.accessibilityLabel`/`.accessibilityValue`) — assert its absence under a
  tie via the chip's accessibility value never containing "Recommended",
  not by searching for the glyph. See `cull-021-stack-rail-nav.md`'s Sharp
  edges for the full explanation and the contrast with the Compare survey's
  independently-findable `"✦ BEST"` badge (a different, unrelated
  mechanism — `LibraryGridView.swift:5814`, `CompareSurveyPresentation`,
  out of scope for this card).
- **The Compare survey has its own, separate tie mechanism** — tied
  contenders render a `"tied"` rank badge instead of `"#N"`
  (`CompareSurveyPresentation.rankBadges(for:)`, `LibraryGridView.swift:
  5779-5792`) — this is a different surface (Compare's contenders-only
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

**Reconciled again, same day (task-reviewer finding on the partial-read
change):** the first version of the PARTIAL-read branch didn't check
whether the lone scored kind actually had a renderable whole-photo row —
`kindCount` counts all seven rankable kinds (four whole-photo, three
face-specific: `faceQuality`/`eyeSharpness`/`eyesOpen`), so a frame whose
only signal was face-specific rendered the "early read — 1 signal" caveat
with an empty row list, an honest-states violation (a caveat claiming a
signal this card shows nothing for). Fixed in
`CullReadsCardPresentation.swift` (falls back to "No read yet" when
`signalRows(for:)` is empty) with a red-proofed unit test
(`testSingleFaceSpecificSignalFallsBackToNoReadYetNotAPhantomCaveat`), and
every passage in this card asserting "exactly one scored kind → PARTIAL
read" unqualified (Source, Step 4, Step 6, Expected, Sharp edges) was
re-qualified to distinguish the whole-photo case (PARTIAL read) from the
face-specific case ("No read yet"). Still NOT RUN.

**Reconciled 2026-07-28 (fix/cull-followups citation re-sweep)**: every
`LibraryGridView.swift` citation was re-verified by directly reading the
cited lines, not by assuming a fixed offset — this branch's
completion-summary fix (`CullCompletionPresentation`/`LibraryGridView.swift`)
added 16 lines ahead of everything in `CullingStackRailPresentation`/
`CullReadsCardPresentation`-adjacent code, and most citations shifted by
exactly that much (e.g. `normalizedQualityRead`'s `kindCount` moved
`6610-6616` → `6626-6632`). Two Sharp-edges citations, however, turned out
to already be badly stale independent of this branch's edits and needed
more than a uniform shift: `CompareSurveyPresentation.rankBadges(for:)`
(cited `5584-5602`, actually `5772-5785`) and the `"✦ BEST"` badge literal
(cited `5624`, actually `5807`) — both off by ~170 lines even against this
branch's own starting point, predating this reconciliation. Also fixed
`requestVisibleAssetEvaluations` (`AppModel.swift`, cited `9188`, actually
`9434` — untouched by this branch, so this drift is likewise pre-existing).
`CullReadsCardPresentation.swift` citations were re-verified and needed no
changes (that file is untouched on this branch). Still NOT RUN.

**Reconciled 2026-07-28 (fix/cull-followups exhaustive-switch citation
shift)**: `LoupeView.cullCompletion`'s proposal-kind partition was rewritten
from two `filter` calls to an exhaustive `switch` over
`AutopilotProposalKind`, adding 7 lines ahead of every `LibraryGridView.swift`
citation in this card — every one shifted by exactly +7 (e.g.
`normalizedQualityRead`'s `kindCount` `:6626-6632` → `:6633-6639`),
re-verified by directly reading each cited symbol. `AppModel.swift` and
`CullReadsCardPresentation.swift` citations are untouched (neither file
changed). No prose or behavior claims changed. Still NOT RUN.

**LIVE RUN 2026-07-28, app 878f1939 (merged main, includes the three-state
code), `teststrip-e2e` VM, fresh `burst` launch.** Verdict:
**PASS-WITH-CARD-FIXES, no app bugs.** Selected Stack 1 of 4 (`smoke-0`,
frame 1 of 3). This fixture's evaluator scores every one of the 18 assets
with exactly the same four whole-photo kinds (`focus`/`motionBlur`/
`framing`/`aesthetics`, confirmed via `SELECT kind, count(*) FROM
evaluation_signals GROUP BY kind` = 18 for all four) and zero face-specific
signals anywhere (`eyesOpen`/`faceQuality`/`eyeSharpness` = 0 rows total) —
every frame's `kindCount` is uniformly 4, never 1. Steps 1-5 exercised
against live data; Step 6 (the kindCount==1 divergence check) is a
structural no-op on this fixture — no frame anywhere ever reaches
`kindCount == 1`, so neither divergence variant is reachable, matching this
card's own "don't manufacture it" guidance. Not a bug.
  - Step 2 (pre-eval): zero `evaluation_signals` rows confirmed; Reads panel
    read "No read yet" (bare inner-`Text` match); no "Recommended" chip, no
    "EYES CLOSED"/"SOFT" badge, no "too close to call" banner. **PASS.**
  - Step 3: ⇧⌘E covered all 18 assets in one poll. **PASS.**
  - Step 4: `smoke-0` scored all 4 whole-photo kinds (a FULL read).
    Independently computed `normalizedQualityRead` = 41.4986/196.5 ≈ 0.2112
    (well under the 0.5 Toss threshold) → predicted decisive **Toss**; live
    AX showed exactly "Toss" (no "Keep", no "No read yet"), with 4 signal
    rows (8%/8%/81%/29% for Focus/Motion blur/Framing/Aesthetics). **PASS.**
  - Step 5: independently computed all 3 frames' `normalizedQualityRead`
    (`smoke-0`≈0.2112, `smoke-1`≈0.2325, `smoke-2`≈0.2487) — top is
    `smoke-2`; `smoke-1` is 0.0162 away (tied, within the 0.03 margin),
    `smoke-0` is 0.0375 away (excluded) → predicted `tiedLeaderIDs =
    [smoke-1, smoke-2]`, banner "too close to call — 2·3", no "Recommended"
    chip. Live matched exactly (`ax find --contains "too close to call"` →
    "too close to call — 2·3"; `--role AXButton --contains "Recommended"` →
    no match). Screenshot captured corroborating Reads card + rail banner
    simultaneously. **PASS.**
  - Step 6: skipped, no-op per above (no `kindCount == 1` frame exists in
    this fixture).

  **Card bugs found and fixed in this commit** (all documentation/procedure,
  no app-behavior claim was wrong):
  1. **Step 1's `S`-to-cycle-scope instruction was backwards.** A fresh
     `burst` launch already defaults to `cullScope = .all`
     (`AppModel.swift:2189`) — `cull-021` established this and it reproduced
     live again here: pressing `S` moved scope *to* "Unrated," not to "All
     frames." Confirmed harmless to this run's results
     (`requestVisibleAssetEvaluations` iterates the loaded `assets` list
     directly, not the scope-filtered queue — Step 3's 18/18 coverage was
     identical either way) but the instruction itself was wrong and is now
     fixed to tell the runner to leave scope alone.
  2. **The container-level `--label "Reads" --contains "..."` assertion
     methodology never works, in any state — a bigger hole than the single
     previously-known "Mixed full-read → `""`" gap.** Verified via a direct
     `AXUIElementCopyAttributeNames` dump of the `cullFacesReadsPanel`
     `AXGroup`: `AXValue` is absent from its attribute list entirely in
     every state; the accessibilityValue string lands only under
     `AXValueDescription`, which `ax_drive.sh` never inspects. This is a
     role-dependent SwiftUI→AX bridging behavior (confirmed a native
     `AXButton`'s `.accessibilityValue`, e.g. the rail chip's "Selected",
     *does* map to `AXValue` correctly) — not a `CullReadsCardPresentation`
     defect; the right string is still genuinely computed and set. Every
     Reads-panel assertion in Steps 2 and 4, plus the Source section's
     claim that the container match is authoritative, rewritten to use the
     bare `ax find --contains "..."` match against the inner `Text`
     instead, with the mechanism documented in Sharp edges. This affects
     any future card driving this same panel, not just this run.

  **No app bugs.** The three-state contract itself — "No read yet" pre-eval,
  a FULL read's verdict math (Keep/Toss thresholds against
  `normalizedQualityRead`), and the rail's tie suppression — all matched
  independent hand computation exactly, live. The only divergences found
  were in this card's own AX-driving methodology and a stale scope-cycling
  instruction, both fixed above.
