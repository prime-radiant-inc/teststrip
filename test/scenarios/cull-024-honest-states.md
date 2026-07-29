# cull-024-honest-states: the reads panel says "No read yet" before evaluation, and a genuine tie suppresses ✦ with a "too close to call" banner — never a fabricated read

**What this covers**: as a photographer relying on the AI reads to break
ties, I need the UI to be honest about what it doesn't know rather than
inventing a confident-looking answer. Before evaluation runs (zero scored
rankable kinds of any type), the loupe's Reads panel must say so plainly
("No read yet"), not show a stale or default verdict. Once evaluation has
produced exactly one scored kind — whole-photo or face-specific, any of the
seven rankable kinds — the panel is honest in a different way: it shows
that lone signal's glyph plus an explicit "early read — 1 signal" caveat
instead of either fabricating a verdict or falling back to a blank "No read
yet" — one scored kind is real information, but not enough to commit to
Keep/Toss (Jesse's ruling, 2026-07-23; implemented fix/cull-followups Task
2, 2026-07-28; extended to cover a lone face-specific kind too by the
reads-card glyph-line change, 2026-07-29, which retired the 2026-07-28-era
"No read yet" special case for that one combination). When evaluation
genuinely produces a
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
  (`Sources/TeststripApp/CullReadsCardPresentation.swift:72-108`): three
  states, all keyed off `CullingStackRecommendation.normalizedQualityRead`'s
  `kindCount` (`LibraryGridView.swift:6635-6641`), which counts every
  rankable kind with a scored component — all seven, whole-photo and
  face-specific alike, no special-casing by kind. **Zero rankable kinds**
  (the function returns `nil`) is the only "no read at all" state:
  `emptyState: "No read yet"`, no verdict, no glyphs
  (`CullReadsCardPresentation.swift:73-82`). **Exactly one scored kind, of
  *any* rankable type** — whole-photo or face-specific, no distinction as
  of the 2026-07-29 reads-card glyph-line change — is a genuine PARTIAL
  read (`:84-96`): the one glyph for that kind renders (the same
  canonical-order `glyphEntries(for:)`, `:113-126`, which now emits all
  seven kinds instead of the old four-whole-photo-only `signalRows(for:)`),
  but no verdict is ever computed — `CullingAssistPresentation.verdict` is
  not called in this branch — and `earlyReadCaveat` (`:57-58`) carries the
  exact copy `"early read — 1 signal"`, which the view renders in place of
  the verdict line. **Two or more kinds** is the FULL read (`:97-107`):
  verdict (`CullingAssistPresentation.verdict`, unchanged) plus every
  scored kind's glyph, split across two lines by `wholePhotoGlyphEntries`
  (`:62-64`) and `faceGlyphEntries` (`:66-68`) — whole-photo glyphs first,
  face glyphs second when present — `earlyReadCaveat` nil. The doc comment
  (`:3-19`) documents exactly these three states.

  **Superseded history**: this card's original (2026-07-16) claim that any
  single kind rendered "No read yet" was reconciled (Jesse's ruling
  2026-07-23, fix/cull-followups Task 2, 2026-07-28) into a two-way split —
  a lone *whole-photo* kind became a genuine PARTIAL read, but a lone
  *face-specific* kind (`faceQuality`/`eyeSharpness`/`eyesOpen`) still fell
  back to "No read yet", because the then-current `signalRows(for:)` only
  ever rendered the four whole-photo kinds, and a reviewer-found gap fix
  (same-day, 2026-07-28) made that empty-state fallback explicit rather
  than showing a caveat with nothing to show for it. **That two-way split
  is itself now retired.** The 2026-07-29 reads-card glyph-line change
  replaced `signalRows(for:)` with `glyphEntries(for:)`, which renders a
  glyph for any of the seven rankable kinds — so a lone face-specific kind
  now has a renderable glyph too, and the PARTIAL-read branch no longer
  special-cases it: it is exactly as "genuine" as a lone whole-photo kind.
  The close-ups rail still separately shows its own per-face detail
  (eye/smile/sharpness marks, `cull-012-closeups-panel.md`) — the doc
  comment's note that the rail "keeps per-face detail" while this card's
  face glyphs are "the photo-level best component per kind, exactly what
  the composite consumes, so the line and the verdict can never disagree"
  (`CullReadsCardPresentation.swift:8-10`) is why both surfaces can show
  face information without disagreeing.

  This remains a genuinely different gate than the rail's own ✦
  recommendation (`CullingStackRecommendation.rankedCandidates` via
  `CullingQualityScore.qualityScore`, `LibraryGridView.swift:6589-6605` and
  `Sources/TeststripCore/Evaluation/CullingQualityScore.swift:35-44`), which
  only needs **1** rankable kind of *any* type (`guard !scoreByKind.isEmpty`)
  — the same floor this card's PARTIAL read now shares. The two surfaces no
  longer diverge on whether *something* renders for a 1-kind frame (they
  now agree, regardless of kind); they diverge only on whether it's
  decisive enough to *name a winner*: a 1-kind frame gets a PARTIAL read
  with **no verdict** on this card, while the rail's chip may still read
  "Recommended" off that same single kind. See Step 6, reconciled below,
  for the exact current assertion. Assert whichever state this run's
  fixture actually produces — don't force it.
- **AX surface for the Reads panel**, `cullFacesReadsPanel`
  (`LibraryGridView.swift:4085-4104`): the *whole* faces+reads right panel
  (the Reads card on the left, the Close-Ups rail of face crops on the
  right — reconciled 2026-07-17 from the old top/bottom stacked layout) is
  one `.accessibilityElement(children: .contain)` block carrying an explicit
  `.accessibilityLabel("Reads")` and a three-way fallback
  `.accessibilityValue(readsPresentation.emptyState ?? readsPresentation
  .verdictText ?? readsPresentation.earlyReadCaveat ?? "")` (`:4098-4103`)
  — extended from the old two-way `emptyState ?? verdictText ?? ""` by
  fix/cull-followups Task 2 (2026-07-28) so the *source-level* value doesn't
  collapse to `""` for a PARTIAL read — set directly from the presentation
  struct, independent of which inner view branch actually renders, at the
  Swift call-site. **This container-level chain is unchanged by the
  2026-07-29 glyph-line change** — only the FULL/PARTIAL branches' inner
  content (glyphs instead of text rows) changed shape, not this
  container-level accessibility value. **This card previously claimed
  (unverified against a live run) that `--label "Reads" --contains "..."`
  pins this container and should be treated as authoritative —
  live-driving this run disproved that claim.** A direct
  `AXUIElementCopyAttributeNames` dump of the container confirmed `AXValue`
  is entirely absent from its attribute list in every state
  (empty/partial/full); the string set via `.accessibilityValue(...)` is
  exposed only under `AXValueDescription`, an attribute
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
  (`LibraryGridView.swift:4195-4198`, the `readsCard` empty-state branch),
  or the caveat (`:4206-4210`) — is independently AX-findable as its own
  element, same as before; **treat the bare `ax find --contains "..."`
  match against that inner `Text` as authoritative, not the container-label
  match**, which this run showed is structurally dead as a test technique
  on this build (macOS 26 Tahoe). **The per-kind reads themselves are no
  longer `AXStaticText` rows at all** (the old `signalRows` `ForEach` is
  gone) — each is now its own `SignalGlyphView` carrying
  `.accessibilityElement(children: .ignore)` plus an explicit
  `.accessibilityLabel(entry.accessibilityText)`
  (`Sources/TeststripApp/SignalGlyphView.swift:31-32`, e.g. `"Focus 82%"`).
  Unlike the panel container, a SwiftUI `.accessibilityLabel` on a plain
  element *does* surface via `AXTitle`/`AXDescription`, which `ax find
  --contains` inspects directly — so `ax find --contains "Focus "`
  reliably matches the glyph itself, no container-match workaround needed
  for per-kind probes. This doesn't mean the presentation logic is wrong —
  the correct string is still genuinely computed: exposed to assistive
  tech via `AXValueDescription` for the container, and directly via
  `AXTitle`/`AXDescription` for each glyph; just not via the container's
  `AXValue`, which `ax_drive.sh`'s combined `--label`-plus-`--contains`
  check relies on.
- **Rail tie suppression**, `CullingStackRailPresentation.init`
  (`LibraryGridView.swift:6328-6464`): computes `tiedLeaderIDs` via
  `CullingStackRecommendation.tiedLeaderIDs` (call site `:6399-6402`,
  defined at `:6649-6666` — leaders are every candidate whose
  `normalizedQualityRead` is within `tooCloseToCallMargin = 0.03` of the top
  read, `:6647`, `nil` when fewer than 2 candidates qualify, `:6665`). "A
  tie can't defend a single winner, so the ✦ is suppressed entirely rather
  than arbitrarily picking one tied leader to crown" (`:6403-6404`) —
  `recommendation = tiedLeaderIDs == nil ? rankedCandidates.first : nil`
  (`:6405`), so under a tie **no** rail chip's `isRecommended` is `true`
  and **no** chip's accessibility value contains `"Recommended"`
  (`stackChipAccessibilityValue`, `:4899-4903`: `isSelected ? "Selected" :
  (isRecommended ? "Recommended" : "Not selected")`). The banner:
  `tooCloseBanner = tiedLeaderIDs.map { "too close to call — <frame
  labels·joined by ·>" }` (`:6419-6424`), rendered as an orange
  `Text(tooCloseBanner)` directly under the rail's title/position text
  (`:4758-4763`) only when non-nil. The "Keep recommended N" secondary
  action is suppressed the same way: the guard `tiedLeaderIDs == nil, let
  recommendation = rankedCandidates.first else { return nil }` inside
  `Self.rankedAction` (`:6514-6518`; call site passing `tiedLeaderIDs` at
  `:6450-6455`) — corrected from this card's stale `:6322-6326` citation,
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
   run) — the "Cull filter" chip only renders when
   `CullHUDPresentation.showsScopeChip` is true (`scope != .all`,
   `Sources/TeststripApp/CullHUDPresentation.swift:44`; that gate moved out
   of `LibraryGridView.swift` and into its own presentation struct since
   this card's citation was last checked, gating the `cullHUDScopeChip` call
   at `LibraryGridView.swift:4320-4322`), so its absence confirms scope
   without cycling. Pressing `S` on a fresh launch cycles *away* from "All
   frames" (confirmed live this run: one `S` press left the scope reading
   "Cull filter: Unrated," per `CullScope`'s cycle order,
   `AppModel.swift:301,316-356`) — this card's prior wording had the cycle
   direction backwards. Harmless to this card's own assertions
   (`requestVisibleAssetEvaluations`, `AppModel.swift:9463-9476`, iterates
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
   `AppModel.swift:9463`) — wait for cached previews first if needed, then
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
   `normalizedQualityRead`'s `kindCount` (`LibraryGridView.swift:6635-6641`).
   Branch on the count — three honest outcomes, not two. **Use the bare
   `ax find --contains "..."` form throughout this step, never `--label
   "Reads" --contains "..."`** — confirmed live this run that the combined
   container-label match never succeeds regardless of state (Sharp edges);
   the bare match against the inner `Text`/glyph is the one that actually
   tracks the branch. Each kind's inline word for the glyph probes below is
   `CullReadsCardPresentation.word(for:)`
   (`CullReadsCardPresentation.swift:37-48`): Focus/Motion/Framing/Looks for
   the four whole-photo kinds, Eyes/Face/Eye sharp for the three
   face-specific ones:
   - **Zero**: assert the Reads panel still reads "No read yet"
     (`ax find --contains "No read yet"`) even though evaluation has run —
     the honest empty state, not a stale one — with no verdict and no
     glyphs.
   - **Exactly one (a PARTIAL read, whichever kind it is)**: as of the
     2026-07-29 reads-card glyph-line change, this count no longer needs a
     further whole-photo-vs-face-specific split — a lone kind of *any*
     rankable type renders the identical PARTIAL shape
     (`CullReadsCardPresentation.swift:84-96`). Assert
     `ax find --contains "No read yet"` now fails to match — the card has
     left the empty state — and instead assert the exact early-read caveat
     renders in place of a verdict: `ax find --contains "early read — 1
     signal"` (exact copy, `CullReadsCardPresentation.swift:94`). Assert
     **no** `AXStaticText` reads exactly `"Keep"` or `"Toss"` — a partial
     read never computes a verdict (`CullingAssistPresentation.verdict` is
     not consulted in this branch) — and assert exactly one glyph renders,
     matching whichever of the seven canonical kinds actually has the
     signal: `ax find --contains "<Word> "` (e.g. `ax find --contains
     "Focus "` or `ax find --contains "Eye sharp "`) against that kind's
     word from the mapping above. If the lone kind is face-specific, that
     same glyph now also renders here (on the second, face-glyph line) —
     it is no longer exclusive to the close-ups rail; the rail's own
     per-face marks (`cull-012-closeups-panel.md`) are a separate, per-face
     presentation of related data, not a substitute for this card's
     photo-level glyph.
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
     absence as a bug in this branch. Either way, independently assert
     every scored kind's glyph renders: whole-photo kinds
     (`CullReadsCardPresentation.wholePhotoGlyphEntries`) on the first
     line, any scored face kind (`faceGlyphEntries`) on a second line
     beneath it — `ax find --contains "<Word> "` should match for each
     kind actually present in the SQL row above, on whichever line it
     belongs to.
   All three branches: the glyph's own accessibility label carries the
   word and the percentage together (e.g. `"Focus 82%"`,
   `EvaluationSignalPresentation.percentage`, `LibraryGridView.swift:
   6180-6183`) — there is no separate bare `"%"`-only probe anymore, that
   matched the old text-row layout, not `SignalGlyphView`'s combined
   label.
5. **Tie honest branch.** Compute the stack's tie state independently:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT asset_id, kind, value_json, confidence FROM evaluation_signals WHERE asset_id IN (<stack ids>);"
   ```
   apply `CullingQualityScore.qualityComponent`'s per-kind formula
   (`CullingQualityScore.swift:9-31`) to get each frame's
   confidence-weighted mean (`normalizedQualityRead`,
   `LibraryGridView.swift:6635-6641`), and check whether 2+ frames land
   within `0.03` of the top score (`tooCloseToCallMargin`, `:6647`).
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
6. **Divergence check (only if the live data happens to produce it):** If
   the selected frame has exactly one scored kind of *any* type — whole-
   photo or face-specific, no distinction as of the 2026-07-29 glyph-line
   change — so its own Reads panel is in the PARTIAL-read branch (step 4:
   one glyph, the "early read — 1 signal" caveat, no verdict) — while the
   rail's chip for that same frame reads "Recommended" (step 5's tie-free
   branch, with this frame as the winner), assert this is **not** a bug —
   it's the documented gate mismatch in Source above: the rail's ✦ needs
   only 1 kind of any type for a *recommendation*, the Reads panel needs 2
   kinds for a *verdict*. Both surfaces now render some read for a 1-kind
   frame regardless of which kind it is; they disagree only on whether it's
   decisive enough to name a winner. (There is no longer a second,
   face-specific-only variant to check here: before the glyph-line change,
   a lone face-specific kind's Reads panel showed "No read yet" instead of
   a PARTIAL read — a second, differently-shaped divergence — but that
   fallback is retired, so a lone kind of any type now produces the same
   one shape.) If the live data doesn't produce a `kindCount == 1` frame at
   all, skip this step; don't manufacture it.

## Expected
- Step 2: **Fails if** the Reads panel shows anything other than "No read
  yet" before any evaluation has run, or if any rail chip shows
  "Recommended" or a flaw badge pre-evaluation — that would mean a surface
  is claiming an AI read that doesn't exist yet.
- Step 4: **Fails if** the Reads panel's state disagrees with the
  independently-counted scored-kind total: zero kinds must show "No read
  yet"; exactly one kind of *any* type (whole-photo or face-specific) must
  show that kind's single glyph plus the exact caveat "early read — 1
  signal" and no `Keep`/`Toss` text — never "No read yet" for a lone
  face-specific kind, that fallback is retired as of the 2026-07-29
  glyph-line change; two or more kinds must show every scored kind's glyph
  (whole-photo glyphs on the first line, any face glyphs on a second) and,
  per the Keep/Toss/Mixed math, either a matching verdict or no verdict
  text at all. Regardless of what the rail is doing.
- Step 5: **Fails if** the rail's tie/no-tie/no-signal state disagrees with
  the independently-computed `tooCloseToCallMargin` check, if a
  "Recommended" chip and the too-close-to-call banner ever both appear at
  once (they are mutually exclusive by construction), or if the banner
  names the wrong frames.
- Step 6: **Fails if** it treats the real verdict-vs-recommendation gate
  mismatch as an error, or if it fabricates a divergence — including by
  asserting a 1-kind-of-any-type frame's Reads panel says "No read yet"
  instead of rendering its PARTIAL read — when the live data didn't
  actually produce a `kindCount == 1` frame.

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
  card's scope to change. **The per-kind glyphs (2026-07-29 glyph-line
  change) are not subject to this quirk at all**: each `SignalGlyphView`'s
  `.accessibilityLabel` surfaces via `AXTitle`/`AXDescription`, which `ax
  find --contains` *does* inspect — so `ax find --contains "Focus "`
  matches the glyph directly, no combined-match workaround needed (see the
  AX-surface Source bullet above for the full mechanism).
- **This card's honest-branch steps (5-6) may all be no-ops on a given
  run** if `burst`'s synthetic rectangles produce a clean winner every time,
  or never produce 2+ scored kinds on any frame — that is a legitimate
  outcome, not evidence the card is broken. Report which branch was
  observed; don't retry until a tie happens to appear.
- **The Reads panel and the rail read from different scoring functions**
  (`normalizedQualityRead`'s confidence-weighted mean vs. `qualityScore`'s
  summed defect-inversion), but as of the 2026-07-29 reads-card glyph-line
  change their "is there a read at all" floors are now the *same*: both
  render *something* for any 1 rankable kind of *any* type, whole-photo or
  face-specific. (The rail's `qualityScore` always did; the Reads panel's
  PARTIAL read used to special-case a lone face-specific kind back to "No
  read yet" — a same-day fix/cull-followups Task 2 follow-up, 2026-07-28,
  that closed a narrower gap where the first version rendered the
  early-read caveat with zero renderable rows for exactly that case — but
  that special case is itself now retired, since `glyphEntries(for:)`
  renders a glyph for every rankable kind.) So there are two floors left,
  not three: the shared 1-kind "something renders" floor (both surfaces),
  and `CullingAssistPresentation.verdict`'s clean, unconditional 2-kind
  floor (Reads panel only — the rail's ✦ has no verdict-shaped floor at
  all, just a ranked recommendation). Don't conflate these two, or treat a
  disagreement in *kind of read* (a recommendation vs. a verdict) as
  automatically wrong; check step 4's independent kind-count first — kind
  identity no longer matters for this card's gate, only the count does.
- **`✦` itself is not independently AX-findable** on the rail (it's a
  `Text("✦")` nested inside a `Button` that already carries an explicit
  `.accessibilityLabel`/`.accessibilityValue`) — assert its absence under a
  tie via the chip's accessibility value never containing "Recommended",
  not by searching for the glyph. See `cull-021-stack-rail-nav.md`'s Sharp
  edges for the full explanation and the contrast with the Compare survey's
  independently-findable `"✦ BEST"` badge (a different, unrelated
  mechanism — `LibraryGridView.swift:5816`, `CompareSurveyPresentation`,
  out of scope for this card).
- **The Compare survey has its own, separate tie mechanism** — tied
  contenders render a `"tied"` rank badge instead of `"#N"`
  (`CompareSurveyPresentation.rankBadges(for:)`, `LibraryGridView.swift:
  5781-5794`) — this is a different surface (Compare's contenders-only
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

**Reconciled 2026-07-29 (reads-card glyph-line, docs-only source
re-verification, not a live run)**: `CullReadsCardPresentation.swift` and
the `readsCard`/`signalGlyphLine` views in `LibraryGridView.swift` were
rewritten (commit `4b2c6db6`) to emit one micro-glyph per scored rankable
kind (all seven, face kinds included) instead of the old four-whole-photo-
kind text rows, and the PARTIAL-read branch no longer special-cases a lone
face-specific kind back to "No read yet" — that 2026-07-28 fallback is
retired, since every kind now has a renderable glyph. Every passage in this
card describing the old per-kind row/percentage-text probes, the
face-specific "No read yet" fallback, and the "three floors" divergence
between the Reads panel and the rail (What this covers, Source, Steps 4/6,
Expected, Sharp edges) was re-read against the working tree and rewritten
to describe the current glyph-line contract, with every touched citation
re-verified by directly reading the cited lines at this reconciliation's
HEAD. The container-level `.accessibilityValue` chain and the
`AXValueDescription` AX-bridging quirk (Sharp edges) are unchanged by this
commit — only the FULL/PARTIAL branches' inner content changed shape
(glyphs, not text rows). Still NOT RUN against this exact commit; the LIVE
RUN 2026-07-28 entry above predates the glyph-line change and remains a
valid historical record of the three-state *gating* logic (unaffected by
this commit) but not of the current glyph rendering — a future live run
should re-verify the per-glyph `ax find --contains "<Word> "` probes this
reconciliation introduces.

**LIVE RUN 2026-07-29, app `4b2c6db6` (reads-card glyph-line build),
`teststrip-e2e` VM, fresh `burst` launch. Verdict: PASS, no app bugs — plus
one width-truncation finding (the plan's own sanctioned 2+2-fallback
candidate, reported per instructions, not fixed here).** Mutated-template
guard (`autopilot_proposals` count) read 0 on the freshly-launched instance,
confirming an unpatched template. Selected Stack 1 of 4 (`smoke-0`, frame 1
of 3) — identical fixture data to the 2026-07-28 run (`burst`'s synthetic
evaluator is fully deterministic run to run).
- Step 2 (pre-eval): zero `evaluation_signals` rows confirmed; bare-`Text`
  match found "No read yet"; `--role AXButton --contains "Recommended"`,
  `--contains "EYES CLOSED"`, `--contains "SOFT"`, and `--contains "too
  close to call"` all correctly failed to match. **PASS.**
- Step 3: ⇧⌘E covered all 18 assets in one poll. **PASS.**
- Step 4: `smoke-0` scored the same 4 whole-photo kinds as the 2026-07-28
  run (focus 0.08236/motionBlur 0.91764/framing 0.80711/aesthetics 0.29131
  — byte-identical fixture) → FULL read, independently computed
  `normalizedQualityRead ≈ 0.2112` → predicted decisive **Toss**. Live:
  `ax find --contains "Toss"` matched, "Keep" and "No read yet" did not.
  All four glyphs found via the new per-kind `<Word> <NN>%` labels: `Focus
  8%`, `Motion 8%`, `Framing 81%`, `Looks 29%` — percentages match the
  independent computation exactly. **PASS.** `kindCount` is uniformly 4
  across all 18 assets (confirmed via `GROUP BY asset_id` over the 7
  rankable kinds) — `burst` still cannot produce a `kindCount == 1` frame,
  matching the 2026-07-28 run's finding. **See
  `cull-012-closeups-panel.md`'s LIVE RUN 2026-07-29 entry for a
  live-confirmed `kindCount == 1` face-specific PARTIAL read on a different
  fixture** (`faces`, via `People ▸ Scan for Faces`), which exercises
  exactly the branch this fixture structurally cannot reach.
- Step 5: independently computed all 3 frames' reads (`smoke-0`≈0.2112,
  `smoke-1`≈0.2325, `smoke-2`≈0.2487 — identical to 2026-07-28) → predicted
  tie `[smoke-1, smoke-2]`, banner "too close to call — 2·3", no
  "Recommended" chip. Live matched exactly. **PASS.**
- Step 6: structural no-op, confirmed via `GROUP BY asset_id` that no asset
  anywhere in this catalog reaches `kindCount == 1` (uniformly 4). Not a
  bug — matches the card's own caution and the 2026-07-28 run.

**Width-check finding:** captured a screenshot of Step 4's FULL read (4
whole-photo glyphs on one line: Focus/Motion/Framing/Looks). The rendered
line **is visually truncated** — each glyph's on-screen text is clipped to
an ellipsis (`Foc…`, `Mot…`, `Fra…`, `Loo…`) rather than the full `Focus
8%`/`Motion 8%`/`Framing 81%`/`Looks 29%` text. The accessibility layer is
unaffected (AX labels carry the full untruncated text, confirmed by the
`ax find --contains "<Word> "` matches above) — this is a visual/layout
clipping issue in the reads-card glyph line at this window width, not a
data or AX-contract defect. This reproduced again on `cull-012`'s FULL-read
screenshot (a different asset, whole-photo line truncated the same way).
Per the task brief this is the plan's own anticipated 2+2-fallback
scenario; reporting per instructions, no code change made here. Screenshot
evidence in `.superpowers/sdd/2026-07-29-reads-card-glyph-line/task-4-report.md`.
