# cull-014-stack-rail: Stack rail's primary Keep button and its secondary-actions ellipsis menu

**Reconciled 2026-07-13 (cull-stack-rail branch)**: this card previously
described the rail as a row of small text **chips** with "the ✦ marker...
and a small red dot on any chip whose asset has flaw badges." The rail was
reorganized into a **vertical thumbnail rail on the left of the loupe
stage** — each cell is now a preview-image thumbnail (not a text chip), the
single red dot became **one badge per AI read** (`EYES CLOSED`/`SOFT`, each
its own small pill), and the Keep button + ellipsis menu are unchanged in
*behavior* but now sit in the rail's own footer (they were never a
top-of-stage row — the "chip" language was about the individual stack-
member cells, not the actions). Line numbers throughout are also
re-verified against the current working tree, which has grown
substantially since this card was first written — several old citations
(`:5648`, `:5641-5646`, `:5557-5577`, `:5538-5546`, `:5521`, `:4313-4318`,
`:4334-4345`, `:5555-5556`) no longer point at the described code; all
citations below are fresh. This revision does **not** re-test navigation
(within/across-stack ↓↑←→, click-to-loupe, Return promote/reject) — that is
`cull-021-stack-rail-nav.md`'s job; this card stays focused on the rail's
**Keep button and ellipsis-menu actions**, now reconciled to the vertical-
rail visual.

**What this covers**: As a photographer working a burst I want the stack
rail's big "Keep" button (in the rail's footer) to keep the frame I'm
looking at (and reject its siblings) in one gesture, plus secondary
actions — collapsed into an ellipsis (`⋯`) menu so Keep is the rail's one
prominent verb — for keeping the recommended/top-ranked frame(s) or the
whole stack when none should be cut. Covered inventory items 39 (rail:
primary Keep + secondary actions in an ellipsis menu + per-frame
thumbnails) and 40 (guidance text/action set — resolved below by reading
`CullingStackActionPresentation` directly).

Source (re-verified against the working tree on this branch):
- **Rail placement and structure**: `cullingStackRail(presentation:)`,
  `Sources/TeststripApp/LibraryGridView.swift:4399-4471` — a vertical
  `VStack` (title/position/rationale text, then a `ScrollView`/`LazyVStack`
  of per-frame thumbnail cells, then a footer `HStack` holding the primary
  Keep `Button` (`:4427-4440`) and, when
  `presentation.actions.dropFirst()` is non-empty, an `ellipsis.circle`
  `Menu` labeled "More stack actions" (`:4441-4459`) wrapping the secondary
  actions. Placed leftmost in the loupe's middle `HStack`, shown only when
  `presentation.showsCullChrome` — `:3842-3845`.
- **Per-frame cells** (the "chips" of the old description; now thumbnail
  cells): `cullStackRailCell(_:)`, `LibraryGridView.swift:4473-4524` — each
  cell renders a `CachedPreviewImage` thumbnail, a decision overlay
  (`cullStackRailDecisionOverlay`, `:4530-4547`), the `✦` recommended
  marker (`:4495-4503`), a selection-highlight stroke, and — **one mark
  per AI-read flaw**, not a single red dot —
  `compareDecisionBadges(item.flawBadges)` (`:4515-4517`) (only two kinds
  exist today: `EYES CLOSED`/`SOFT`, see `cull-021-stack-rail-nav.md`'s
  source notes on `CompareSurveyPresentation.flawBadges`,
  `LibraryGridView.swift:5535-5546`). **Reconciled 2026-07-17 (dogfood-r1
  panel pass)**: a flaw's `CompareDecisionBadge.tone` is now `.flaw`, not
  `.destructive`, and `compareDecisionBadge(_:)` (`LibraryGridView.swift:5855`)
  renders `.flaw` as quiet, secondary-colored caption text — no filled
  background, no bold — instead of the old bold red pill; the text content
  itself is unchanged (still "SOFT"/"EYES CLOSED", not lowercased, so
  existing AX `--contains` queries for it keep working); red
  (`.destructive`) is now reserved for genuinely destructive states
  (REJECTED). The text content (`EYES CLOSED`/`SOFT`) and the "one mark per
  flaw kind" structure are unchanged — only the visual weight.
- **`CullingStackRailPresentation.init`**, `LibraryGridView.swift:6054-6161`
  — the multi-frame-stack guard is at `:6102` (`stackScope.assetIDs.count >
  1`). It always builds exactly three action entries in this order
  (`:6140-6160`):
  1. `.keepSelectedAndRejectAlternates` — title `"Keep frame N · cut M"`,
     always enabled, help `"Keep selected frame and reject stack
     alternates"`.
  2. `Self.rankedAction(...)` (`:6186-6221`) — **`.keepTopRanked([top2])`**
     titled `"Keep top 2"` if the stack has >2 frames and 2+ ranked
     candidates exist; otherwise **`.keepRecommended(assetID)`** titled
     `"Keep recommended N"`, or `nil` (omitted) if there's no ranked
     candidate at all (see `cull-021-stack-rail-nav.md` for when that's
     the case).
  3. `.keepAll` — title `"Keep all N"`, always enabled.
  `CullingStackAction`, the real action enum, is exactly four cases
  (`:6224-6229`): `keepSelectedAndRejectAlternates`, `keepTopRanked([AssetID])`,
  `keepRecommended(AssetID)`, `keepAll`. `CullingStackActionPresentation`
  is the view-layer presentation wrapper (`:6231-6253`), not a
  `TeststripCore` model.
- **The rail's primary "Keep" button does not follow keepRecommended/
  topRanked guidance** — its handler `keepSelectedStackFrame()`
  (`LibraryGridView.swift:4785-4791`) calls
  `model.promoteCurrentFrameAndRejectSiblings()` unconditionally on whatever
  frame is currently *selected*, regardless of which frame the ranking
  recommends. The recommended/top-ranked guidance only surfaces via (a) the
  secondary action button, dispatched through `performCullingStackAction`
  (`:4806-4817`: `.keepRecommended` → `keepRecommendedStackFrame(_:)`
  (`:4793-4796`, selects the recommended asset first, then calls the same
  `keepSelectedStackFrame()`) and `.keepTopRanked` →
  `keepTopRankedStackFrames(_:)`, `:4798-4804`) and (b) the `✦` marker on
  the recommended cell and the HUD's stack-guidance verdict text
  (`cullingStackGuidanceAction`, `cull-011-hud.md` item 33). So the
  secondary "Keep recommended N" button, not the primary button, is the
  "keep the guidance pick" gesture.
- **Fixture prerequisite**: the rail requires a stack with 2+ frames
  (`stackScope.assetIDs.count > 1`, `LibraryGridView.swift:6102`) resolved
  either from an explicit persisted `CullingStackScope` (the `work-stack-`
  `asset_sets` rows) or the same in-memory `AssetStackBuilder` auto-grouping
  the filmstrip uses (`cull-013-filmstrip.md`). `--smoke`'s 900-second seed
  spacing (`SmokeCatalogSeeder.swift:105`) is outside the 2-second
  `candidateStackMaximumCaptureGap` (`AppModel.swift:2458`), so `--smoke`
  produces **no auto-stacks and no persisted `work-stack-` sets** — this
  card uses the `burst` seed variant (`TeststripBench seed-burst-catalog`),
  whose capture times are 1s apart within each group, guaranteeing 4
  multi-frame auto-stacks (3/4/3/4 frames) plus 4 singles — the same
  fixture `cull-004-stack-promote-return.md` and `cull-021-stack-rail-nav.md`
  use.

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
   script/ax_drive.sh find --role AXButton --contains "Stack frame 1"
   ```
   If it never appears across the `burst` set, stop and report this card as
   untestable-without-fixture — do not fabricate a stack.
2. Select a non-recommended frame within the stack. `burst`'s
   `SmokeCatalogSeeder`-based synthetic images carry **no evaluation
   signals until an Evaluate pass runs** (see
   `cull-021-stack-rail-nav.md`'s Sharp edges) — trigger Culling ▸ "Evaluate
   Visible" (⇧⌘E) and wait for `evaluation_signals` to cover the stack's
   asset ids before relying on any `✦`/recommendation read:
   ```bash
   sqlite3 "$DB" "SELECT asset_id, kind, value_json, confidence FROM evaluation_signals WHERE asset_id IN (<stack member ids>);"
   ```
   (schema: `Sources/TeststripCore/Catalog/CatalogMigrations.swift:63-76` —
   column is `kind`, not `signal_kind`.) Cross-check which frame is
   actually recommended against the `✦` marker (via the cell's
   accessibility value containing "Recommended" — the `✦` glyph itself is
   not independently AX-findable, see `cull-021-stack-rail-nav.md`'s Sharp
   edges), not just eyeballing the render. If no frame in the stack ends up
   with a rankable score, there is no recommended frame and no secondary
   "Keep recommended"/"Keep top 2" action will appear — note this
   honestly rather than forcing step 5 to pass.
3. Click the rail's **primary** "Keep" button
   (`script/ax_drive.sh press --role AXButton --contains "Keep frame"`).
   Assert it kept the **selected** frame (from step 2), not the recommended
   one — i.e. it applied `keepSelectedAndRejectAlternates` semantics on the
   currently-focused asset. **A silent no-op is a hard failure** — the
   rail renders `model.selectedCullingStackScope`'s own resolved stack
   (`AppModel.swift:6234-6256`), the same membership
   `promoteCurrentFrameAndRejectSiblings` writes, so a visible Keep button
   must always write. Also assert the frames written are exactly the
   rail's displayed membership — the button title's "cut M" count must
   equal the number of siblings whose flags changed to reject plus
   protected picks left alone:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE id IN (<stack member ids>);"
   ```
4. Undo (⌘Z) to revert the stack promote from step 3 — cross-check against
   `cull-pass-scope-and-undo.md`'s established Return-gesture undo semantics
   (one ⌘Z reverts the whole pick+reject-siblings transaction as a unit).
5. Re-select a frame in the stack, then open the rail's ellipsis menu
   (`script/ax_drive.sh press --role AXButton --help "More stack actions"`)
   and click the **secondary** "Keep recommended N" / "Keep top 2" menu item
   (`script/ax_drive.sh press --role AXMenuItem --contains "Keep recommended"`
   or `"Keep top 2"`, whichever `rankedAction` produced — see step 2's
   honest gap if neither exists for this fixture). Assert it kept the
   ranked/recommended frame(s) specifically, matching what step 2's
   evaluation-signal read predicted, regardless of which frame was selected
   beforehand.
6. Assert each stack member has its own thumbnail cell
   (`presentation.items`, `LibraryGridView.swift:6120-6129`) with the `✦`
   marker (via accessibility value, not a raw AX-findable glyph — see
   above) on exactly the recommended one, and — the reorg's actual change
   from a single red dot — **one mark per AI-read flaw** on any cell whose
   asset has `flawBadges`:
   ```bash
   script/ax_drive.sh find --role AXButton --label "Stack frame 1"
   ```
   (cell accessibility label is `"Stack frame \(label)"`,
   `LibraryGridView.swift:4522`; value carries Selected/Recommended + each
   flaw badge's text per `stackChipAccessibilityValue`, `:4554-4558`; the
   flaw marks themselves are separate `AXStaticText` children below the
   thumbnail, `:4515-4517` — independently AX-findable by their text, e.g.
   `find --role AXStaticText --contains "SOFT"`, unlike the `✦` marker. As
   of 2026-07-17 the flaw mark itself renders as quiet, secondary-colored
   caption text — not a filled pill — but its text ("SOFT"/"EYES CLOSED",
   not lowercased) and AX-findability are unchanged, so this assertion
   still holds).

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
- Step 6: **Fails if** the cell count != stack member count, the `✦`
  (accessibility "Recommended") is on the wrong cell, or a cell with known
  flaws (per `evaluation_signals`) shows no flaw mark — or shows the old
  single-red-dot rendering, or a bold filled-red pill (pre-2026-07-17),
  instead of one quiet mark per flaw kind.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **This card shares the evaluation-signal fixture gap** documented in
  `cull-021-stack-rail-nav.md`: `burst`'s synthetic frames are flat colored
  rectangles with no faces, so `.eyesOpen`-derived flaw badges can
  structurally never fire, and whether `.focus`-derived `SOFT` fires on
  synthetic content, or whether any frame gets a rankable score at all
  (making a recommendation/secondary-action possible), is not established
  here — steps 2/5/6 must assert whichever branch the live evaluation
  actually produces, not a forced outcome.
- **This card does not re-test rail navigation** (↓↑ within-stack, ←→
  across-stack, click-to-loupe) — see `cull-021-stack-rail-nav.md` for
  that; duplicating it here would drift the two cards apart again.
- The primary/secondary button distinction (item 40's real resolution) is a
  meaningfully different behavior than "guidance text = keepRecommended
  falling back to topRanked" as originally assumed — that fallback logic
  (`rankedAction`) governs only the *secondary* button's label/target and
  the HUD's stack-guidance verdict text, never the primary Keep button's
  actual write. Do not conflate the two in the runner.
- `evaluation_signals` schema was re-verified this pass
  (`CatalogMigrations.swift:63-76`): the kind column is named `kind`, not
  `signal_kind` as an earlier draft of this card had it — use `kind` in any
  live query.

## Run status
NOT RUN AGAINST THE RECONCILED CONTENT — reconciled 2026-07-13 to the
vertical thumbnail rail (per-frame thumbnails, footer Keep/ellipsis menu,
per-badge AI reads replacing the single red dot); every line-number
citation above was re-verified against the current working tree, several
having moved substantially since this card was last driven. The LEDGER's
prior "Verified" status ("Task-12 re-run PASS (ellipsis menu, Keep=selection,
⌘Z atomic)") predates both this visual reorg and the line-number drift, and
must not be read as covering this revision; needs a fresh human-present/VM
execution per `test/scenarios/README.md`.
