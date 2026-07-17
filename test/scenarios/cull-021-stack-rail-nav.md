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
  `Sources/TeststripApp/LibraryGridView.swift:3842-3845`
  (`cullingStackRail(presentation: stackPresentation)`).
- **Rail view**: `cullingStackRail(presentation:)`,
  `LibraryGridView.swift:4399-4471` — title (`Label` + `rectangle.stack`
  glyph, orange), `positionText` ("Frame X of Y"), optional
  `rationaleText`, a `LazyVStack` of cells in a `ScrollView`, then a footer
  `HStack` with the primary "Keep" button and (if any secondary actions
  exist) an `ellipsis.circle` `Menu` labeled "More stack actions" —
  Keep/menu are footer controls, not a top-of-stage chip row.
- **Rail cell**: `cullStackRailCell(_:)`, `LibraryGridView.swift:4473-4524` —
  thumbnail (`CachedPreviewImage`), a pick/reject decision overlay
  (`cullStackRailDecisionOverlay`, `:4530-4547`: `.picked` →
  `DesignGlyph.pick.symbolName` ("flag.fill", green); `.rejected` → literal
  SF Symbol `"xmark.circle.fill"` (red) plus 0.45 opacity dim
  (`CullingFilmstripPresentation.DecisionState.isDimmed`,
  `:5960`, true only for `.rejected`); a `✦` recommended marker
  (top-trailing overlay, orange-on-black, `:4495-4503`) rendered when
  `item.isRecommended`; a selection-highlight stroke (orange, 2pt) when
  `item.isSelected`; and, **below** the thumbnail (a sibling in the outer
  `VStack`, not inside the button's `ZStack`), one badge per AI read via
  `compareDecisionBadges(item.flawBadges)` (`:4515-4517`) — each flaw its
  own small pill (`EYES CLOSED` / `SOFT`), replacing the old single red dot.
  Tap dispatches `model.select(item.assetID)` (`:4475`).
- **`CullingStackRailPresentation`**, `LibraryGridView.swift:6036-6169` —
  `Item.flawBadges` comes from `CompareSurveyPresentation.flawBadges(for:)`
  (`:5535-5546`; **exactly two** kinds exist today — `EYES CLOSED` when the
  highest-confidence `.eyesOpen` score is `<= 0.0`, `SOFT` when the highest-
  confidence `.focus` score is `<= 0.4` — there is **no third "duplicate"
  badge kind** in this codebase; don't assert one). `Item.isRecommended`
  comes from `CullingStackRecommendation.rankedCandidates(...).first`
  (`:6274-6290`), itself driven by `CullingQualityScore.qualityScore`
  (`Sources/TeststripCore/Evaluation/CullingQualityScore.swift:9-44`, which
  scores off `.focus`/`.eyesOpen`/`.faceQuality`/`.eyeSharpness`/
  `.motionBlur`/`.aesthetics`/`.framing` signals) — **nil when no frame
  carries a rankable score**, in which case no chip is `isRecommended` and no
  `✦` renders at all (see Sharp edges: the fixture must actually be
  evaluated for this leg to mean anything).
- **Accessibility surface** (the actual AX-drivable proxy for "✦" —
  `stackChipAccessibilityValue`, `:4554-4558`): each cell is one `AXButton`
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
  mapping (`Sources/TeststripApp/CullingKeyCaptureView.swift:149-161`) and
  the static key-based mapping used for the `?`/menu advertisement
  (`Sources/TeststripApp/AppModel.swift:236-283`) agree:
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
- **Dispatch**: `applyCullingShortcut`, `AppModel.swift:5849-5867` —
  `.previousCandidateInStack`/`.nextCandidateInStack` call
  `selectPreviousCandidateInStack()`/`selectNextCandidateInStack()`
  (`:6276-6282`, → `moveSelectionWithinCurrentCullingStack(by:)`,
  `:6284-6295`: moves within `selectedCullingStackScope.assetIDs`, **no
  wrap** — a target index outside `stackAssetIDs.indices` is a no-op).
  `.previousStack`/`.nextStack` call `selectPreviousStackForCulling()`/
  `selectNextStackForCulling()` (`:6258-6270`, preferring a persisted
  `work-stack-` session, else `selectCullingStack(_:)`, `:6398-6440`), which
  lands on `recommendedStackLandingAssetID(for:)` (`:6442-6447`:
  `recommendedCullingStackAssetID(in:) ?? indexedStack.firstAssetID` — i.e.
  the ranked winner if one exists, otherwise the stack's first frame in
  catalog order, **not** an arbitrary frame).
- **`?` overlay scroll**: while `isKeyMapOverlayVisible`,
  `.previousCandidateInStack`/`.nextCandidateInStack` (↑/↓) are intercepted
  first and scroll the overlay instead (`AppModel.swift:5832-5847`,
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
   `AppModel.swift:6291-6293` — no wrap to frame 1, no crossing into the
   next stack).
9. **↑ mirrors ↓**: press `Up` from the last frame; assert it steps back one
   frame at a time, also stopping (no wrap) at frame 1.
10. **→ moves to the next stack, landing on its recommended frame**: from
    frame 1 of the current stack, press `Right`. Assert `titleText`'s stack
    index advances by one (a different stack), and the newly-selected chip
    is the one whose accessibility value contains "Recommended" **if** step
    5 found a real ranked winner for that stack, else the stack's first
    frame (`recommendedStackLandingAssetID`'s documented fallback) — assert
    whichever this catalog's evaluation state actually produces, cited
    against the source above, not an assumed one.
11. **← mirrors →**: press `Left`; assert it returns to the previous stack,
    landing the same way (recommended-or-first).
12. **Click loupes a cell**: within the current stack, click a rail cell
    for a frame that is not currently selected (`ax press --role AXButton
    --label "Stack frame <N>"`). Assert that cell becomes `"Selected"` in
    its accessibility value and the main loupe stage now shows that same
    asset (filename/preview changes to match) — `model.select(_:)` only
    changes selection (`LibraryGridView.swift:4475`,
    `AppModel.swift:4205-4209`); assert it did **not** write any flag (the
    clicked frame's decision overlay stays absent/undecided).
13. **Confirm-before-write, pre-Return**: after all of steps 1-12 (pure
    browsing — rendering the rail, evaluating, navigating, clicking — no
    decision gesture yet), assert **zero** writes:
    ```bash
    SRC_DIR=$(script/vm_scenario_run.sh sql burst "SELECT original_path FROM assets LIMIT 1;" | xargs dirname)
    script/vm_scenario_run.sh shell "find '$SRC_DIR' -name '*.xmp' | wc -l"                        # must be 0
    script/vm_scenario_run.sh sql burst "SELECT count(*) FROM metadata_sync_state WHERE status='pending';"  # must be 0 (column is status, not state)
    script/vm_scenario_run.sh sql burst "SELECT count(*) FROM people;"                             # must be 0
    script/vm_scenario_run.sh sql burst "SELECT count(*) FROM person_assets;"                      # must be 0
    ```
    (evaluation itself writes only `evaluation_signals`/`autopilot`-adjacent
    tables, never asset metadata/flags/sidecars/people — that's the
    invariant this step re-asserts.)
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
  switching stacks, or land on a frame other than the documented
  recommended-or-first rule.
- Step 12: **Fails if** clicking a cell does anything beyond changing
  selection (e.g. writes a flag) or the main stage doesn't follow the click.
- Step 13: **Fails if** even one `.xmp` appears, one `metadata_sync_state`
  row is pending, or any `people`/`person_assets` row exists from pure
  browsing/evaluation — the confirm-before-write invariant is the point of
  this step; do not weaken it.
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
  independent cross-check.
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
