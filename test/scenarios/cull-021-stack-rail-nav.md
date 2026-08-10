# cull-021-stack-rail-nav: The vertical current-stack rail — within-stack ↓/↑, across-stack ←/→ landing on the recommended frame, click-to-loupe, and Return promote/reject

**What this covers**: as a photographer working a burst in the Cull loupe, I
want the **left vertical rail** to show my current stack's frames as
thumbnails (with the recommended frame marked and any AI-read flaws
badged), **↓/↑** to step *within* that stack without ever leaving it,
**←/→** to jump to the *next/previous stack*, landing on whichever frame the
ranking recommends, a **click** on any rail cell to loupe it, and **Return**
to promote the selected frame and reject its siblings — with the rail's
pick/reject glyphs reflecting the write immediately, and nothing written
just from browsing.

Source (re-verified against the working tree on this branch, not carried
over from any older card):
- **Rail placement**: leftmost in the loupe's middle `HStack`, shown only
  when `presentation.showsCullChrome` —
  `Sources/TeststripApp/LibraryGridView.swift:3786-3789`
  (`cullingStackRail(presentation: stackPresentation)`).
- **Rail view**: `cullingStackRail(presentation:)`,
  `LibraryGridView.swift:4697-4796` — title (`Label` + `rectangle.stack`
  glyph, orange), `positionText` ("Frame X of Y"), optional
  `rationaleText`, a `LazyVStack` of cells in a `ScrollView`, then a footer
  `HStack` with the primary "Keep" button and (if any secondary actions
  exist) an `ellipsis.circle` `Menu` labeled "More stack actions" —
  Keep/menu are footer controls, not a top-of-stage chip row.
- **Rail cell**: `cullStackRailCell(_:)`, `LibraryGridView.swift:4830-4900` —
  thumbnail (`CachedPreviewImage`), a pick/reject decision overlay
  (`cullStackRailDecisionOverlay`, `:4905-4922`: `.picked` →
  `DesignGlyph.pick.symbolName` ("flag.fill", green); `.rejected` → literal
  SF Symbol `"xmark.circle.fill"` (red) plus 0.45 opacity dim
  (`CullingFilmstripPresentation.DecisionState.isDimmed`,
  `:6343`, true only for `.rejected`); a `✦` recommended marker
  (top-trailing overlay, orange-on-black, `:4857-4865`) rendered when
  `item.isRecommended`; a selection-highlight stroke (orange, 2pt) when
  `item.isSelected`; and, **below** the thumbnail (a sibling in the outer
  `VStack`, not inside the button's `ZStack`), one mark per AI read via
  `compareDecisionBadges(item.flawBadges)` (`:4891-4893`) — each flaw
  (`EYES CLOSED` / `SOFT`), replacing the old single red dot. **Reconciled
  2026-07-17**: each flaw's `CompareDecisionBadge.tone` is `.flaw` (not
  `.destructive`), rendered as quiet, secondary-colored caption text (no
  filled pill, no bold) — the text itself is unchanged, only the visual
  weight; red stays reserved for the decision overlay's genuinely
  destructive `.rejected` state above. Tap dispatches
  `model.select(item.assetID)` (`:4836-4837`).
- **`CullingStackRailPresentation`**, `LibraryGridView.swift:6288-6536`
  (corrected 2026-07-28; see Run status for the general citation-drift
  note) — `Item.flawBadges` comes from
  `CompareSurveyPresentation.flawBadges(for:)` (`:5828-5839`, corrected
  2026-07-28; **exactly two** kinds exist today — `EYES CLOSED` when the
  highest-confidence `.eyesOpen` score is `<= 0.0`, `SOFT` when the highest-
  confidence `.focus` score is `<= 0.4` — there is **no third "duplicate"
  badge kind** in this codebase; don't assert one). `Item.isRecommended`
  (`:6411`) is `assetID == recommendation?.assetID`, where `recommendation`
  (`:6403`) is `tiedLeaderIDs == nil ? rankedCandidates.first : nil` —
  **not** simply `rankedCandidates.first` (corrected 2026-07-28: the
  previous revision of this bullet omitted the tie suppression entirely,
  which reads as "always shows the top-ranked frame" and is wrong on a
  too-close-to-call tie). `rankedCandidates` (`:6587-6603`) is driven by
  `CullingQualityScore.qualityScore`
  (`Sources/TeststripCore/Evaluation/CullingQualityScore.swift:9-44`, which
  scores off `.focus`/`.eyesOpen`/`.faceQuality`/`.eyeSharpness`/
  `.motionBlur`/`.aesthetics`/`.framing` signals) — **nil when no frame
  carries a rankable score**, in which case no chip is `isRecommended` and no
  `✦` renders at all (see Sharp edges: the fixture must actually be
  evaluated for this leg to mean anything). Note this ✦-suppression-on-tie
  is a *different* mechanism from the stack-*landing* fallback in the
  Dispatch bullet below (`CullingStackRecommendation.landingAssetID`, which
  does NOT suppress on a tie — it lands on the first tied leader instead):
  the two can legitimately disagree on which frame gets attention (✦ shows
  none, landing still picks one).
- **Accessibility surface** (the actual AX-drivable proxy for "✦" —
  `stackChipAccessibilityValue`, `:4897-4901`, corrected 2026-07-28): each
  cell is one `AXButton`
  labeled `"Stack frame \(label)"` (1-based index *within the stack*, not a
  global asset id) whose accessibility **value** is
  `"Selected"`/`"Recommended"`/`"Not selected"` followed by any flaw-badge
  text. Because the cell is a SwiftUI `Button` with explicit
  `.accessibilityLabel`/`.accessibilityValue`, its child `Text("✦")` is not
  independently exposed — assert "recommended" via the button's value
  string, not by searching for a literal `✦` glyph (contrast with the
  compare survey's `"✦ BEST"`, which **is** its own `Text` badge,
  `LibraryGridView.swift:5523`, and thus independently AX-findable; the rail
  chip is not the same mechanism).
- **Keyboard remap**, `CullingShortcut` — the live monitor's event-based
  mapping (`Sources/TeststripApp/CullingKeyCaptureView.swift:153-165`) and
  the static key-based mapping used for the `?`/menu advertisement
  (`Sources/TeststripApp/AppModel.swift:187-241`) agree:
  `upArrow`/`downArrow` → `.previousCandidateInStack`/`.nextCandidateInStack`
  (moves **within** the current stack); `leftArrow`/`rightArrow` →
  `.previousStack`/`.nextStack` (moves **across** stacks); `space` →
  `.nextPhoto` (plain linear advance); `returnKey`/`keypadEnter` →
  `.promoteAndRejectSiblings`. **⌥←/⌥→ no longer do anything**: the event
  initializer guards `relevantModifiers.isEmpty` first
  (`CullingKeyCaptureView.swift:128-129`, `relevantModifiers =
  event.modifierFlags.intersection([.command, .control, .option])`) — with
  Option held this is non-empty, so `CullingShortcut(event:)` returns `nil`
  and `handleLocalKeyDown` passes the raw event through unhandled
  (`:94-96`); there is no special-cased Option-arrow branch anywhere in this
  file anymore (the old monitor-only mechanism cited by prior cards is
  gone).
- **Dispatch**: `applyCullingShortcut`, `AppModel.swift:6538-6632` (stale
  line numbers from an earlier verification pass corrected 2026-07-28 —
  ~700-800 lines were added to this file above this point since; see Run
  status) — `.previousCandidateInStack`/`.nextCandidateInStack` call
  `selectPreviousCandidateInStack()`/`selectNextCandidateInStack()`
  (`:7073-7079`, → `moveSelectionWithinCurrentCullingStack(by:)`,
  `:7081-7100`: moves within `selectedCullingStackScope.assetIDs`, **no
  wrap** — a target index outside `stackAssetIDs.indices` is a no-op, guard
  at `:7096-7098`). `.previousStack`/`.nextStack` call
  `selectPreviousStackForCulling()`/`selectNextStackForCulling()`
  (`:7055-7067`, preferring a persisted `work-stack-` session, else
  `selectCullingStack(_:)`, `:7149-7191`), which lands on
  `recommendedStackLandingAssetID(for:)` (`:7202-7205`:
  `recommendedCullingStackAssetID(in:) ?? stack.assetIDs.first`). **This is
  a three-way branch, not the two-way "winner-or-first" the previous
  revision of this card described** — reconciled 2026-07-28 after a live
  run landed on frame 2, not frame 1, of a stack whose top two reads were
  tied: `recommendedCullingStackAssetID` delegates to
  `CullingStackRecommendation.landingAssetID`
  (`LibraryGridView.swift:6675-6683`), which returns (1) the clear ranked
  winner when one exists, (2) **the first tied leader in capture order**
  (not necessarily frame 1) when `tiedLeaderIDs` is non-nil — a
  too-close-to-call tie still lands somewhere, just not on an arbitrarily
  "recommended" chip — per that function's own doc comment, and only (3)
  `stack.assetIDs.first` when literally no frame in the stack carries any
  rankable score at all (`rankedCandidates` empty). Branch (2) is easy to
  conflate with (3) because both are "no ✦ shown" states, but they land on
  different frames whenever the tied leaders don't happen to start at index
  0 — assert against `CullingStackRecommendation.tiedLeaderIDs`
  (`LibraryGridView.swift:6647-6664`, margin `tooCloseToCallMargin = 0.03`
  at `:6645`, computed from `normalizedQualityRead`'s confidence-weighted
  **mean**, `:6633-6639` — a different metric from `rankedCandidates`'
  summed `qualityScore` used for the ✦ chip itself, `:6587-6603`), not by
  assuming "first tied leader" always equals "stack's first frame."
- **`?` overlay scroll**: while `isKeyMapOverlayVisible`,
  `.previousCandidateInStack`/`.nextCandidateInStack` (↑/↓) are intercepted
  first and scroll the overlay instead (`AppModel.swift:6543-6558`,
  `scrollKeyMapOverlay(.up)`/`.down`) — not exercised by this card (see
  `cull-009-keymap-overlay.md`), noted here only so a driver doesn't confuse
  ↑/↓'s dual role if the overlay happens to be open.
- **Fixture**: `burst` seed variant (`TeststripBench seed-burst-catalog`,
  `Sources/TeststripBench/SmokeCatalogSeeder.swift:33-54`,
  `main.swift:424-444`) — 4 auto-groupable stacks (3/4/3/4 frames, capture
  times 1s apart, inside `AssetStackBuilder`'s 2s gap) plus 4 singles, same
  fixture `cull-004-stack-promote-return.md`/`cull-014-stack-rail.md` use.

## Pre-state
```bash
# burst guarantees multi-frame auto-stacks without a real camera burst:
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
```
(Host equivalent: `swift run TeststripBench seed-burst-catalog <appsupport>`,
then launch against it — `--smoke`'s 900s-apart seed never auto-stacks.)

## Steps
1. `ax wait-vended`; ⌘1 for Cull; cycle scope to "All" with `S`
   (`CullScope.displayName == "All frames"`) so scope filtering can't hide a
   stack member. Confirm the rail is visible on some multi-frame stack:
   `ax find --role AXButton --contains "Stack frame 1"`. If it never appears
   on any selection, stop and report this card as untestable-without-fixture
   — do not fabricate a stack (per `cull-014-stack-rail.md`'s own caution).
2. Record the current stack's title/position text:
   `ax find --role AXStaticText --contains "Stack "` (titleText, "Stack N of
   M") and `ax find --role AXStaticText --contains "Frame "` (positionText,
   "Frame X of Y"). Record the loaded stack's asset ids in catalog order via
   SQL for cross-checking the moves below (adjust the WHERE clause to the
   actual selected stack once step 1's asset is known):
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT id FROM assets ORDER BY rowid LIMIT 4;"  # first burst group (3 frames) + 1
   ```
3. **Pre-evaluation baseline (honest fixture gap)**: a freshly-seeded
   `burst` catalog has **zero** `evaluation_signals` rows (`SmokeCatalogSeeder`
   never writes any — confirm: `script/vm_scenario_run.sh sql burst "SELECT
   count(*) FROM evaluation_signals;"` should read 0). At this point no chip is
   `isRecommended` (no `✦`, no "Recommended" in any cell's accessibility
   value) and `flawBadges` is empty on every chip — this is the designed
   "no read yet" state, not a bug. Confirm no cell's value contains
   "Recommended": `ax find --role AXButton --contains "Recommended"` should
   fail to match.
4. **Trigger evaluation** so the recommendation/badge legs mean something:
   Culling ▸ "Evaluate Visible" (⇧⌘E) evaluates every loaded asset with a
   cached preview (`requestVisibleAssetEvaluations`,
   `AppModel.swift:8420-8433`) — wait for previews first if needed
   (`worker-001-preview-lifecycle.md`'s pattern), then poll:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"
   ```
   until it covers the stack's asset ids (staying frontmost via `wait-vended`
   each poll — keep the app warm per README).
5. **Recommended marker, post-evaluation**: independently compute which
   frame the ranking should pick by reading the raw signals for the stack's
   asset ids:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT asset_id, kind, value_json, confidence FROM evaluation_signals WHERE asset_id IN (<stack ids>);"
   ```
   (schema: `Sources/TeststripCore/Catalog/CatalogMigrations.swift:63-76` —
   column is `kind`, not `signal_kind`; `value_json` encodes
   `EvaluationValue`, e.g. `{"score":0.x}` for a `.score` case — confirm the
   exact JSON shape live before trusting an exact-value assertion, per
   `CullingQualityScore.qualityComponent`'s kind list above). Cross-check:
   the chip whose accessibility value contains "Recommended" should be the
   one with the highest confidence-weighted score by that formula (ties
   broken by lower frame label). **If no frame in the stack carries any of
   the seven scorable kinds** (plausible: burst frames are flat synthetic
   rectangles with no faces, so `.eyesOpen`/`.faceQuality`/`.eyeSharpness`
   can never fire, and `.focus`/`.motionBlur`/`.aesthetics`/`.framing` may
   or may not fire on synthetic content — not established here), no chip
   will be `isRecommended` even post-evaluation; that is the honest no-
   recommendation branch, not a failure — assert whichever branch is real,
   don't force one.
6. **Flaw badges**: for any chip whose flaw badge text is non-empty, cross-
   check against the same `evaluation_signals` read (`EYES CLOSED` requires
   an `.eyesOpen` score `<= 0.0`; `SOFT` requires a `.focus` score `<=
   0.4`). If none qualify, assert zero chips show a flaw badge — do not
   assert a specific badge appears if the signal read doesn't actually
   cross the threshold.
7. **↓ moves within the stack**: note the selected chip's `"Stack frame
   N"` label, press `Down`. Assert the *previously second* chip (`N+1`) is
   now `"Selected"` in its accessibility value, `positionText` reads "Frame
   N+1 of ...", and **`titleText`'s "Stack X of Y" is unchanged** — the move
   stayed inside the same stack. Cross-check the selected asset id
   transitioned to `stackAssetIDs[index+1]` (from step 2's ordered ids), not
   a jump to a different stack's member.
8. **↓ at the last frame is a no-op**: repeat `Down` until on the stack's
   last frame, then press `Down` once more. Assert the selection does not
   move (`moveSelectionWithinCurrentCullingStack`'s target-index guard,
   `AppModel.swift:7096-7098` — no wrap to frame 1, no crossing into the
   next stack).
9. **↑ mirrors ↓**: press `Up` from the last frame; assert it steps back one
   frame at a time, also stopping (no wrap) at frame 1.
10. **→ moves to the next stack, landing per the three-way rule**: from
    frame 1 of the current stack, press `Right`. Assert `titleText`'s stack
    index advances by one (a different stack), and the newly-selected chip
    is: the one whose accessibility value contains "Recommended" if step 5
    found a real ranked winner for that stack; else, if the target stack has
    a `tiedLeaderIDs` tie (compute independently per the Source section's
    formula before asserting), the **first tied leader in capture order**
    — which may or may not be frame 1, don't assume; else (no rankable
    score at all in that stack) the stack's actual first frame. Cite which
    of the three branches applies against the SQL-computed reads before
    asserting a specific landing frame.
11. **← mirrors →**: press `Left`; assert it returns to the previous stack,
    landing by the same three-way rule (recompute independently for that
    stack — it need not match the same branch step 10 hit).
12. **Click loupes a cell**: within the current stack, click a rail cell
    for a frame that is not currently selected (`ax press --role AXButton
    --label "Stack frame <N>"`). Assert that cell becomes `"Selected"` in
    its accessibility value and the main loupe stage now shows that same
    asset (filename/preview changes to match) — `model.select(_:)` only
    changes selection (`LibraryGridView.swift:4475`,
    `AppModel.swift:4786-4790`, corrected 2026-07-28); assert it did **not**
    write any *new* flag/rating/keyword/caption value (the clicked frame's
    decision overlay stays absent/undecided) — see step 13's caveat below
    for why "did a sidecar appear" is not, by itself, a usable proxy for
    "did this click write something."
13. **Confirm-before-write, pre-Return**: **`burst` is not a clean slate for
    this check** (reconciled 2026-07-28, after a live run found `.xmp`
    files appearing from pure arrow-key/click navigation with zero pick/
    reject/rating gestures — traced to source, not a guess): every
    `selectAssetID(_:)` call unconditionally enqueues a metadata-sync check
    for the newly-selected asset (`AppModel.swift:4836-4864`, trigger at
    `:4860`), and `MetadataSyncPlanner.decision`
    (`Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift:20-26`)
    writes an `.xmp` for any asset whose `confirmedProjection` already has a
    non-nil rating/flag/keyword/caption/colorLabel — gated purely on
    presence (`Metadata.swift:55-65`,`:125-134`), with **no check of how
    that value got there**. `SmokeCatalogSeeder` writes rating/keywords/
    caption/colorLabel/flag directly into `metadata_json` for every asset
    (some also get a `flag`) without ever setting the `aiUnconfirmedFields`
    marker, so those seeded values are indistinguishable from a real user
    gesture and sync to `.xmp` the first time each asset is *selected* —
    not on a timer, not for the whole catalog at once (confirmed live: a
    15s idle wait produced zero additional syncs). This does **not** violate
    the origin-tracking invariant itself (no `aiUnconfirmedFields`-marked
    value is ever synced by this path — only already-"confirmed" baseline
    data), but it means a literal "0 `.xmp` files" assertion is fixture noise,
    not signal, for `burst` — same class of caveat `test/scenarios/README.md`
    already documents for `smoke`'s pre-seeded flags. Assert the invariant
    that actually matters instead: no flag/rating/keyword/caption **value**
    changed from what the catalog already held at launch, and no
    `aiUnconfirmedFields`/`aiUnconfirmedKeywords` marker got resolved by mere
    browsing.
    ```bash
    # Baseline immediately after launch (before step 7's navigation) —
    # capture once and diff against, rather than asserting a hardcoded 0:
    script/vm_scenario_run.sh sql burst "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets;"  # snapshot A
    # ... steps 1-12 ...
    script/vm_scenario_run.sh sql burst "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets;"  # snapshot B — must equal snapshot A verbatim
    script/vm_scenario_run.sh sql burst "SELECT count(*) FROM metadata_sync_state WHERE status='pending';"  # must be 0 (column is status, not state) — unaffected by the caveat above
    script/vm_scenario_run.sh sql burst "SELECT count(*) FROM people;"                             # must be 0 — unaffected
    script/vm_scenario_run.sh sql burst "SELECT count(*) FROM person_assets;"                      # must be 0 — unaffected
    # Any newly-appeared .xmp is only legitimate if every touched asset's
    # sidecar content matches metadata_json's pre-existing value verbatim —
    # spot-check at least one (see the live run report for a worked example).
    ```
    (evaluation itself writes only `evaluation_signals`/`autopilot`-adjacent
    tables, never asset metadata/flags/people — that part of the invariant
    this step re-asserts is unaffected by the sync-on-selection caveat.)
14. **Return promotes and the rail shows the write**: with a frame selected
    inside a multi-frame stack, press `Return`
    (`promoteCurrentFrameAndRejectSiblings`, same path the rail's Keep
    button uses — `cull-004-stack-promote-return.md`). Assert:
    - The selected chip's decision overlay is now the pick glyph (green
      `flag.fill`) and every other chip in the stack shows the reject glyph
      (red `xmark.circle.fill`, dimmed 0.45 opacity) — except any sibling
      that was already `pick` before this step (protected, per
      `cull-004`'s pick-protection ruling).
    - Catalog ground truth agrees:
      ```bash
      script/vm_scenario_run.sh sql burst "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN (<stack ids>);"
      ```
      the promoted id reads `pick`, every non-protected sibling reads
      `reject`.
    - Undo (⌘Z) reverts this one gesture's writes as a single group
      (cross-check against `cull-pass-scope-and-undo.md`'s undo-grouping
      pattern) — do this last so cleanup starts from a clean slate.

## Expected
- Step 3: **Fails if** any chip shows "Recommended" or a flaw badge before
  any evaluation has run — that would mean a chip is claiming an AI read
  that doesn't exist yet.
- Steps 5-6: **Fails if** the "Recommended" chip disagrees with the
  independently-computed ranking, or a flaw badge renders/is-absent
  contrary to the threshold check — but **not** a failure if evaluation
  genuinely produces no qualifying signal (see step 5's honest branch).
- Steps 7-9: **Fails if** ↓/↑ ever cross into a different stack (title
  text's "Stack X of Y" changes), wrap around, or move more/less than one
  frame per keypress.
- Steps 10-11: **Fails if** ←/→ move within the same stack instead of
  switching stacks, or land on a frame other than the documented three-way
  rule (recommended winner / first tied leader on a too-close-to-call tie /
  stack's first frame only when no frame ranks at all) — do not treat "first
  tied leader" and "stack's first frame" as interchangeable; they coincide
  only when the tied leaders happen to include index 0.
- Step 12: **Fails if** clicking a cell does anything beyond changing
  selection (e.g. writes a flag) or the main stage doesn't follow the click.
- Step 13: **Fails if** any asset's `flag`/rating/keyword/caption/colorLabel
  *value* differs from its pre-navigation baseline, if any
  `aiUnconfirmedFields`/`aiUnconfirmedKeywords` marker got cleared by mere
  browsing, if one `metadata_sync_state` row is pending, or any
  `people`/`person_assets` row exists from pure browsing/evaluation — this
  is the confirm-before-write invariant re-scoped 2026-07-28 to what it can
  actually mean on the non-clean-slate `burst` fixture (see the step's
  caveat); do not weaken it further than this, and do not revert to a
  literal "0 `.xmp` files" check — that check is unsound on this fixture,
  not "the point of the step."
- Step 14: **Fails if** the rail's glyphs disagree with the catalog's
  `flag` column, if a previously-picked sibling gets reflagged, or if ⌘Z
  reverts more/less than this one promote gesture.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **The rail's `✦` is not independently AX-findable.** It is a `Text("✦")`
  nested inside a `Button` that already carries explicit
  `.accessibilityLabel`/`.accessibilityValue` — assert "Recommended" via the
  button's accessibility **value**, not by searching for the glyph itself.
  This mirrors `worker-002-evaluation-verdicts.md`'s correction of the
  inventory's "✦ glyph" framing, applied here to a different (but easily
  confusable) ✦ usage — the compare survey's `"✦ BEST"` badge (a standalone
  `Text`, independently AX-findable) is a genuinely different mechanism;
  don't conflate the two when writing driver code.
- **`burst`'s synthetic frames may never produce a flaw badge or even a
  recommendation.** `SmokeCatalogSeeder`'s images are flat colored
  rectangles with no faces (`writeSmokeJPEG`,
  `Sources/TeststripBench/SmokeCatalogSeeder.swift:183-223`) — `.eyesOpen`/
  `.faceQuality`/`.eyeSharpness` can structurally never fire (no face to
  detect), and whether `.focus`/`.motionBlur`/`.aesthetics`/`.framing` fire
  at all, or cross the `SOFT` threshold, on this synthetic content is not
  established by this pass. If evaluation genuinely produces zero
  rankable signals for a whole stack, steps 5/6/10/11 should assert the
  no-recommendation/no-badge branch rather than being forced to fail —
  that's a fixture-honesty note for the runner, not permission to skip the
  independent cross-check. **Confirmed live 2026-07-28**: all four
  `burst` stacks tie (every top-two normalized-read gap is inside the 0.03
  margin) — `SOFT` fires on every frame in every stack (`.focus` scores ran
  0.08-0.29, comfortably under the 0.4 threshold) but `✦`/"Recommended"
  never renders anywhere in this fixture. Treat that as the expected
  branch for this fixture, not evidence of a broken ranker.
- **The stack's too-close-to-call tie does not mean "lands on frame 1."**
  See the Dispatch bullet above for the three-way landing rule — a live run
  landed on frame 2 of a 3-frame stack (the first *tied leader* in capture
  order) after the stack's frame 1 fell outside the tie margin. Don't
  conflate "no ✦ shown" (which happens on any tie) with "falls back to the
  stack's literal first frame" (which only happens with zero rankable
  signals at all) — compute `tiedLeaderIDs` independently before asserting
  a landing frame.
- **The rail's pick/reject decision overlay has no independent AX text
  exposure at all** — unlike `✦` (which is at least readable through the
  cell button's accessibility *value*, see the Accessibility surface bullet
  above), `cullStackRailDecisionOverlay`'s `Image(systemName:)` glyphs
  (`LibraryGridView.swift:4873-4886`) carry no `.accessibilityLabel` of
  their own and `stackChipAccessibilityValue` doesn't encode decision state
  either (only Selected/Recommended/flaw-badge text) — confirmed live: `ax
  find --role AXImage --contains "flag"` (and `"xmark"`) matches nothing.
  Step 14's "rail shows the write" claim is only verifiable via catalog SQL
  (authoritative) or a pixel screenshot (`screencapture` on the VM, scp'd
  back) — there is no AX-textual shortcut for this leg.
- **Return's post-promote advance is unconditional, not gated by "Toggle
  Auto-Advance (a)".** `promoteCurrentFrameAndRejectSiblings` →
  `applyCullingStackDecision` (`AppModel.swift:6480-6529`) always calls
  `selectAssetID` on the next stop after committing (`:6516-6528`) — this is
  a separate code path from `applyCullingCommandAndAdvance` (which the `a`
  toggle actually governs, for plain P/X/rating commands). Confirmed live:
  toggling auto-advance off with `a` had no effect on where Return landed
  afterward. If a step needs a *stable* selection to inspect the rail right
  after Return, don't rely on the toggle — either accept the jump and
  re-navigate back (SQL ground truth is unaffected either way), or check
  via SQL immediately instead of via the render.
- **This card intentionally does not re-drive the rail's Keep button or
  its ellipsis "More stack actions" menu** — those are `cull-014-stack-
  rail.md`'s job. This card's Return-gesture leg (step 14) exists only to
  prove the rail's *display* (glyphs) tracks a real write, per the vertical-
  rail reorg's new decision-overlay-per-chip design.
- **No persisted `work-stack-` session exists on a fresh `burst` launch**
  (burst seeds directly into the catalog, bypassing `IngestService` — see
  `cull-004-stack-promote-return.md`'s investigation) — this card exercises
  the auto-grouped (`cullingStacks()`/`AssetStackBuilder`) path only, not
  `selectPersistedCullingStack`'s persisted-session branch.

## Run status
NOT RUN — source-cited against the working tree on 2026-07-13 (line numbers
and behavior re-verified by reading `LibraryGridView.swift`,
`AppModel.swift`, and `CullingKeyCaptureView.swift` directly, not carried
over from an older card); pending live VM execution per
`test/scenarios/README.md`. Reconciled 2026-07-16: every ground-truth query
used a raw `sqlite3 "$DB"` invocation with `$DB` never defined anywhere in
this card (the Pre-state only runs the `vm_scenario_run.sh sync`/`launch`
verbs and says "ground truth via: script/vm_scenario_run.sh sql burst
\"...\"" but the Steps never followed that convention) — replaced every
occurrence with the `script/vm_scenario_run.sh sql burst "..."` form the
newer cards (`cull-022`/`cull-024`/`cull-026`) use, and the filesystem
`find` in step 13 with `script/vm_scenario_run.sh shell "find ... | wc
-l"` (the source directory only exists on the VM). Also fixed step 13's
`metadata_sync_state WHERE state='pending'` to `status='pending'` — the
column is `status` (`CatalogMigrations.swift:30-37`); `state` never existed
on this table. No other content changed.

**2026-07-28 — PASS-WITH-CARD-FIXES, app 878f1939, live run in the
`teststrip-e2e` Tart VM against a fresh `burst` launch.** All 14 steps
executed; every assertion that could be checked against catalog/SQL ground
truth passed. No app bugs found — both discrepancies below turned out to be
this card's own documentation drifting from the (correctly-behaving)
source, not defects in the app.

Per-step tally:
- Steps 1-4: PASS as written.
- Step 5: honest no-recommendation branch on all four stacks (see Sharp
  edges) — not a failure, per the card's own allowance.
- Step 6: PASS — `SOFT` on every frame of the tested stack (focus 0.082/
  0.109/0.136, all ≤0.4), no `EYES CLOSED` anywhere (no `eyesOpen` signal
  at all — synthetic frames have no faces), cross-checked against raw
  `evaluation_signals`.
- Steps 7-9: PASS — ↓/↑ stayed within-stack, no wrap, one frame per press,
  cross-checked against `stackAssetIDs` order from SQL.
- Step 10: PASS — → landed on the next stack's frame 1, which (independently
  computed) is also that stack's first tied leader in a 4-way tie.
- Step 11: **card bug found, now fixed** — ← landed on frame 2, not frame 1,
  of the previous (3-frame) stack, because that stack's tie excluded frame
  1 (its normalized read was 0.0375 outside the 0.03 margin) while frames 2
  and 3 tied with each other. The app is correct (matches
  `CullingStackRecommendation.landingAssetID`'s own doc comment); the card's
  prior "otherwise the stack's first frame" framing of the fallback was an
  oversimplification that doesn't hold once a *partial* tie is in play — see
  the corrected Dispatch bullet and new Sharp Edges entry.
- Step 12: PASS — click selected the cell, stage followed (filename
  updated), no flag written (confirmed via SQL immediately after).
- Step 13: **card bug found, now fixed** — the literal "0 `.xmp` files"
  assertion failed (4 appeared) purely from arrow-key/click navigation, with
  zero pick/reject/rating gestures. Root-caused to source (not guessed):
  `AppModel.swift:4860`'s unconditional `enqueueMetadataSyncCheck` on every
  selection, syncing `burst`'s seeded (no-`aiUnconfirmedFields`-marker)
  baseline metadata the first time each asset is viewed. The actual
  origin-tracking invariant held throughout (verified: every touched
  asset's flag value was byte-identical before/after browsing; `.xmp`
  content matched `metadata_json` exactly; `metadata_sync_state` had zero
  `pending` rows; `people`/`person_assets` stayed at 0) — this was a
  fixture-noise/card-assertion bug, not an app bug. Step rewritten to assert
  value-stability instead of file-count-zero.
- Step 14: PASS, tested twice (stack 2 and stack 3, both with pre-existing
  `pick` siblings to exercise protection): promoted frame → `pick`,
  non-protected siblings → `reject`, pre-existing `pick` siblings
  untouched, catalog matched a VM screenshot of the rail (green top bar +
  selection stroke on the promoted cell, red top bar + dim on a rejected
  sibling), and ⌘Z reverted exactly the one gesture both times (verified
  full before/after flag diff across all 10 touched assets after final
  cleanup — zero residue).

No app code was changed or needs to be; this run's fixes are entirely to
this card's Source citations and two assertion designs (steps 11 and 13).
