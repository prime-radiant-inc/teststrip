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
  `Sources/TeststripApp/LibraryGridView.swift:4697-4796` — a vertical
  `VStack` (title/position/rationale text, then a `ScrollView`/`LazyVStack`
  of per-frame thumbnail cells, then a footer `HStack` holding the primary
  Keep `Button` (`:4739-4752`) and, when
  `presentation.actions.dropFirst()` is non-empty, an `ellipsis.circle`
  `Menu` labeled "More stack actions" (`:4754-4771`) wrapping the secondary
  actions. Placed leftmost in the loupe's middle `HStack`, shown only when
  `presentation.showsCullChrome` — `:3786-3789`. **AX role note (verified
  live 2026-07-28):** the primary Keep `Button` is `AXButton` as expected,
  but SwiftUI's `Menu` control AX-exposes as **`AXMenuButton`**, not
  `AXButton` — `--role AXButton --help "More stack actions"` matches
  nothing live; drive it with `--role AXMenuButton` (label `"More"`, the
  `ellipsis.circle` SF Symbol's default accessibility label, or `--help
  "More stack actions"`).
- **Per-frame cells** (the "chips" of the old description; now thumbnail
  cells): `cullStackRailCell(_:)`, `LibraryGridView.swift:4830-4900` — each
  cell renders a `CachedPreviewImage` thumbnail, a decision overlay
  (`cullStackRailDecisionOverlay`, `:4905-4922`), the `✦` recommended
  marker (`:4857-4865`), a selection-highlight stroke, and — **one mark
  per AI-read flaw**, not a single red dot —
  `compareDecisionBadges(item.flawBadges)` (`:4891-4893`) (only two kinds
  exist today: `EYES CLOSED`/`SOFT`, see `cull-021-stack-rail-nav.md`'s
  source notes on `CompareSurveyPresentation.flawBadges`,
  `LibraryGridView.swift:5860-5876`). **Reconciled 2026-07-17 (dogfood-r1
  panel pass)**: a flaw's `CompareDecisionBadge.tone` is now `.flaw`, not
  `.destructive`, and `compareDecisionBadge(_:)` (`LibraryGridView.swift:5980-5990`)
  renders `.flaw` as quiet, secondary-colored caption text — no filled
  background, no bold — instead of the old bold red pill; the text content
  itself is unchanged (still "SOFT"/"EYES CLOSED", not lowercased, so
  existing AX `--contains` queries for it keep working); red
  (`.destructive`) is now reserved for genuinely destructive states
  (REJECTED). The text content (`EYES CLOSED`/`SOFT`) and the "one mark per
  flaw kind" structure are unchanged — only the visual weight.
- **`CullingStackRailPresentation.init`**, `LibraryGridView.swift:6326-6500`
  — the standalone-vs-stack guard is `isStandalone = stackScope.assetIDs.count
  == 1` (`:6430`); when true, `init` returns early before building actions or
  position text (`:6461-6467`). Otherwise it always builds exactly three
  action entries in this order (`:6478-6499`):
  1. `.keepSelectedAndRejectAlternates` — title `"Keep frame N · cut M"`,
     always enabled, help `"Keep selected frame and reject stack
     alternates"`.
  2. `Self.rankedAction(...)` (`:6532-6572`) — **`.keepTopRanked([top2])`**
     titled `"Keep top 2"` if the stack has >2 frames and 2+ ranked
     candidates exist; otherwise **`.keepRecommended(assetID)`** titled
     `"Keep recommended N"`, or `nil` (omitted) if there's no ranked
     candidate at all (see `cull-021-stack-rail-nav.md` for when that's
     the case).
  3. `.keepAll` — title `"Keep all N"`, always enabled.
  `CullingStackAction`, the real action enum, is exactly four cases
  (`:6575-6580`): `keepSelectedAndRejectAlternates`, `keepTopRanked([AssetID])`,
  `keepRecommended(AssetID)`, `keepAll`. `CullingStackActionPresentation`
  is the view-layer presentation wrapper (`:6582-6618`), not a
  `TeststripCore` model.
- **The rail's primary "Keep" button does not follow keepRecommended/
  topRanked guidance** — its handler `keepSelectedStackFrame()`
  (`LibraryGridView.swift:5065-5070`) calls
  `model.promoteCurrentFrameAndRejectSiblings()` unconditionally on whatever
  frame is currently *selected*, regardless of which frame the ranking
  recommends. The recommended/top-ranked guidance only surfaces via (a) the
  secondary action button, dispatched through `performCullingStackAction`
  (`:5086-5096`: `.keepRecommended` → `keepRecommendedStackFrame(_:)`
  (`:5073-5075`, selects the recommended asset first, then calls the same
  `keepSelectedStackFrame()`) and `.keepTopRanked` →
  `keepTopRankedStackFrames(_:)`, `:5078-5083`) and (b) the `✦` marker on
  the recommended cell (`:4857-4865`). There is no third surface: the HUD
  carries no verdict at all (`CullHUDPresentation`'s doc comment — "the
  assist verdict is deliberately absent... the right panel's reads card owns
  it" — see `cull-011-hud.md`), and the reads card's `verdictText`
  (`CullReadsCardPresentation.swift`) is a per-frame Keep/Toss/Mixed read
  over whole-photo quality signals, unrelated to which stack member is
  recommended. So the secondary "Keep recommended N" button, not the primary
  button, is the "keep the guidance pick" gesture.
- **Fixture prerequisite**: this card's multi-frame assertions (rank/✦,
  "Frame N of M", keep/cut actions) require a stack with 2+ frames, resolved
  either from an explicit persisted `CullingStackScope` (the `work-stack-`
  `asset_sets` rows) or the same in-memory `AssetStackBuilder` auto-grouping
  the filmstrip uses (`cull-013-filmstrip.md`) — a standalone still gets a
  one-thumb rail entry (dogfood fix), just none of that multi-frame chrome.
  `--smoke`'s 900-second seed spacing (`SmokeCatalogSeeder.swift:136`) is
  outside the default 2-second `model.burstIntervalSeconds` (a persisted
  Settings preference, `AppModel.swift:2447`), so `--smoke` produces **no
  auto-stacks and no persisted `work-stack-` sets** — this card uses the
  `burst` seed variant (`TeststripBench seed-burst-catalog`), whose capture
  times are 1s apart within each group, guaranteeing 4 multi-frame
  auto-stacks (3/4/3/4 frames) plus 4 singles — the same fixture
  `cull-004-stack-promote-return.md` and `cull-021-stack-rail-nav.md` use.

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
   (`AppModel.swift:7121-7143`), the same membership
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
   (`script/ax_drive.sh press --role AXMenuButton --help "More stack actions"`
   — verified live 2026-07-28 that the SwiftUI `Menu` control AX-exposes as
   `AXMenuButton`, not `AXButton`; `--role AXButton` matches nothing)
   and click the **secondary** "Keep recommended N" / "Keep top 2" menu item
   (`script/ax_drive.sh press --role AXMenuItem --contains "Keep recommended"`
   or `"Keep top 2"`, whichever `rankedAction` produced — see step 2's
   honest gap if neither exists for this fixture). Assert it kept the
   ranked/recommended frame(s) specifically, matching what step 2's
   evaluation-signal read predicted, regardless of which frame was selected
   beforehand.
6. Assert each stack member has its own thumbnail cell
   (`presentation.items`, `LibraryGridView.swift:6444-6453`) with the `✦`
   marker (via accessibility value, not a raw AX-findable glyph — see
   above) on exactly the recommended one, and — the reorg's actual change
   from a single red dot — **one mark per AI-read flaw** on any cell whose
   asset has `flawBadges`:
   ```bash
   script/ax_drive.sh find --role AXButton --label "Stack frame 1"
   ```
   (cell accessibility label is `"Stack frame \(label)"`,
   `LibraryGridView.swift:4898`; value carries Selected/Recommended + each
   flaw badge's text per `stackChipAccessibilityValue`, `:4929-4938`).
   **Correction (verified live 2026-07-28): the flaw marks are NOT
   separate `AXStaticText` children.** The `Text(badge.text)` built by
   `compareDecisionBadge(_:)` (`:4891-4893` calls `compareDecisionBadges`,
   which renders each badge via `compareDecisionBadge` at `:5980-5997`) lives
   inside the `cullStackRailCell` `Button`'s label closure, and SwiftUI
   collapses a `Button`'s label subtree into the single accessibility
   element carrying `.accessibilityLabel`/`.accessibilityValue` — exactly
   the same conflation the card already correctly documents for the `✦`
   marker. Live probing confirmed `find --role AXStaticText --contains
   "SOFT"` matches **nothing**, while `find --contains "SOFT"` (any role)
   and `find --role AXButton --label "Stack frame N" --contains "SOFT"`
   both match the cell's `AXButton`, same as the `Recommended`/`Selected`
   check. Drive flaw-badge assertions the same way as the `✦` check, not
   via a standalone `AXStaticText` query. (The badge's visual rendering —
   quiet, secondary-colored caption text, no filled pill, text unchanged
   since 2026-07-17 — is otherwise as previously documented and still
   holds.)

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
  (accessibility "Recommended") is on the wrong cell (when a fixture
  actually produces one — `burst` doesn't, see Sharp edges), or a cell
  with known flaws (per `evaluation_signals`) shows no flaw mark — or shows
  the old single-red-dot rendering, or a bold filled-red pill
  (pre-2026-07-17), instead of one quiet mark per flaw kind.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **This card shares the evaluation-signal fixture gap** documented in
  `cull-021-stack-rail-nav.md`: `burst`'s synthetic frames are flat colored
  rectangles with no faces, so `.eyesOpen`-derived flaw badges can
  structurally never fire. **Resolved live 2026-07-28 (no longer
  hypothetical):** every frame in all 4 `burst` stacks scores focus in the
  0.08–0.18 range — always under the `.4` `softFocusBadgeThreshold` — so
  **every single cell in every stack carries the `SOFT` badge**; there is
  no fixture asset that lacks it, so the negative case ("a cell with no
  flaws shows no mark") has no live counter-example to check against
  (the positive case is fully covered instead: 18/18 assets confirmed
  `SOFT`).
- **All four `burst` auto-stacks hit `tiedLeaderIDs` (confirmed
  exhaustively 2026-07-28), so `isRecommended` is never true anywhere in
  this fixture and the `✦` marker never renders.** Exact tie banners
  observed: stack 1 (`smoke-0..2`) "too close to call — 2·3", stack 2
  (`smoke-3..6`) "too close to call — 1·2·3·4", stack 3 (`smoke-7..9`)
  "too close to call — 2·3", stack 4 (`smoke-10..13`) "too close to call —
  2·3·4". Probed every frame in every stack via `find --role AXButton
  --label "Stack frame N" --contains "Recommended"` — zero matches
  anywhere. Step 6's `✦`-placement assertion is untestable with this
  fixture as constituted; report it as a confirmed fixture gap, not a
  forced pass.
- **"Keep recommended N" is structurally unreachable with this fixture
  regardless of the tie finding above.** `rankedAction`
  (`LibraryGridView.swift:6532-6572`)
  checks `stackAssetIDs.count > 2 && topTwo.count >= 2` *before* it looks
  at `tiedLeaderIDs`, and returns `"Keep top 2"` whenever that holds. Every
  `burst` stack has 3 or 4 frames (never exactly 2), and every asset gets a
  rankable `qualityScore` once evaluated, so `topTwo.count` is always 2 —
  the `.keepRecommended` branch can never fire here even on a hypothetical
  future fixture revision that resolves the tie. Live-confirmed on stack 3
  (3 frames): ellipsis menu showed exactly `"Keep top 2"` / `"Keep all 3"`,
  never a `"Keep recommended"` item. Step 5 must always drive `"Keep top
  2"` against `burst`; a card or fixture that wants to exercise
  `"Keep recommended N"` needs a 2-frame stack, which no current seed
  variant produces.
- **Escape at the Loupe's top level exits the whole Cull workspace to
  Library, not just the frontmost menu/sheet** (verified live 2026-07-28:
  `key code 53` with no menu open switched the toolbar segment back to
  "Library" and returned to Grid). Check whether a menu is actually open
  before sending Escape to dismiss it, or use a targeted click instead.
  Recovery is clean, though: clicking the session's entry under Library's
  "Collections" sidebar (labeled with the cull session's name, e.g.
  "Catalog Cull") resumes the Cull workspace at the exact frame/stack
  position it was on before the Escape, with all catalog writes intact —
  confirmed by resuming mid-run and finding both the pre-Escape asset
  selection and the flags written in step 3 unchanged. Re-entering via the
  toolbar's "Cull" segment instead pops a fresh "Start Culling" sheet
  offering a new session — `Cancel` that and use the sidebar entry to
  resume instead of starting a duplicate session.
- **This card does not re-test rail navigation** (↓↑ within-stack, ←→
  across-stack, click-to-loupe) — see `cull-021-stack-rail-nav.md` for
  that; duplicating it here would drift the two cards apart again.
- The primary/secondary button distinction (item 40's real resolution) is a
  meaningfully different behavior than "guidance text = keepRecommended
  falling back to topRanked" as originally assumed — that fallback logic
  (`rankedAction`) governs only the *secondary* button's label/target, never
  the primary Keep button's actual write. The `✦` marker is computed from
  the same ranked-candidate/tied-leader data via a separate `recommendation`
  local in `CullingStackRailPresentation.init`, not via `rankedAction`
  itself. Neither the HUD nor the reads card carries any stack-guidance
  verdict text — see the Source section above. Do not conflate the two in
  the runner.
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

**Reconciled 2026-07-28 (fix/cull-followups citation re-sweep)**: every
`LibraryGridView.swift` line citation above had drifted 11 lines stale
(e.g. `cullingStackRail` cited `4694`, actual `4705`) before this branch's
completion-summary fix (`CullCompletionPresentation`/`LibraryGridView.swift`
changes) added a further 16 lines ahead of all of them — re-swept every
citation against the final tree by reading the cited symbol directly, not
by assuming a uniform offset (the drift is not uniform across the whole
file: the `cullingStackRail` call site at old `:3846-3849` had *no*
pre-existing drift and is now `:3862-3865`, a +16 shift, while everything
from `cullingStackRail`'s own declaration onward — through
`CullingStackActionPresentation` — carries the full +27). No prose or
behavior claims changed, only line numbers.

**Reconciled 2026-07-28 (fix/cull-followups exhaustive-switch citation
shift)**: `LoupeView.cullCompletion`'s proposal-kind partition (well before
`cullingStackRail` in the file) was rewritten from two `filter` calls to an
exhaustive `switch` over `AutopilotProposalKind`, adding 7 lines ahead of
every citation in this card — every `LibraryGridView.swift` line number
above shifted by exactly +7 (e.g. `cullingStackRail` `:4721-4808` →
`:4728-4815`), re-verified by directly reading each cited symbol, not by
assuming the offset. No prose or behavior claims changed.

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: the
`AutopilotProposalKind` partition this note describes **no longer exists at
all**. `CullCompletionPresentation.summary`/`.presentation`
(`Sources/TeststripApp/CullCompletionPresentation.swift:32,88`) now take
only `assets:viewedAssetIDs:skippedAssetIDs:(scope:)` — no proposal-ID
parameters of any kind — so `LibraryGridView`'s call site
(`:3844`, verified 2026-08-06) has no partition to build any more; the
`switch` this note's "+7 lines" refers to is gone from the source, not
merely refactored again. This almost certainly shifts every
`LibraryGridView.swift` citation in this card by some further amount (the
removed switch was 7 lines, but other unrelated edits on this branch may
also have moved code before `cullingStackRail`) — **not independently
re-verified in this reconciliation pass**, which was scoped to this one
historical note per the task brief, not a full citation re-sweep. A future
pass should re-read every `LibraryGridView.swift` citation in this card
directly, the same way the 2026-07-28 notes above did, rather than trust
any offset math.

**Run 2026-07-28 (live VM, app 878f1939): PASS-WITH-CARD-FIXES for steps
1-5; step 6 PASS on cell-count/flaw-badge, fixture-gap on `✦`.** All
source citations re-verified accurate before driving. No app bugs found —
`keepSelectedStackFrame()`'s selection-based write, the protected-pick
guard in `promoteCurrentFrameAndRejectSiblings`, `⌘Z`'s atomic revert, and
`keepTopRankedFramesInSelectedCullingStack`'s ranking-based write (verified
against a hand-computed `CullingQualityScore` from live `evaluation_signals`)
all matched the source reading exactly. Card fixes: (1) step 5's ellipsis
menu role corrected `AXButton` → `AXMenuButton`; (2) step 6's flaw-badge
AX-findability claim corrected — flaw marks are embedded in the cell's
single `AXButton` value/help, not a separate `AXStaticText`; (3) Sharp
edges expanded with the exhaustively-confirmed all-four-stacks-tied
finding, the structural (tie-independent) unreachability of "Keep
recommended N" against any `burst`-shaped stack, the Escape-exits-workspace
gotcha, and the session-resume recovery path. Full run report:
`.superpowers/card-runs/cull-014-run.md`.
