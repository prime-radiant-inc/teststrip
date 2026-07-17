# cull-025-run-strip-completion: the run strip's stops, windowing, and ✨ chips agree with the catalog; the completion summary's six counts and gated ceremony actions match the traversal

**What this covers**: as a photographer blazing through a whole batch, the
bottom run strip is my "how much is left" glance — one stop per stack or
standalone, the current stop highlighted, a ✨ chip on any stop still
carrying a tentative AI flag, and a triple counter/progress bar that only
ever move on *my* decisions, never a machine's tentative guess. When every
frame in scope carries a confirmed decision, the completion summary replaces
the stage with all six counts (picked / rejected / undecided / skipped /
never-viewed / ✨ awaiting review) and a small set of ceremony actions that
only appear when they have real work to do.

Source (re-verified against the working tree on this branch, **2026-07-16**;
every symbol below was re-grepped fresh, not carried over from any older
card):
- **Stops**, `CullRunStripPresentation.stops(...)`
  (`Sources/TeststripApp/CullRunStripPresentation.swift:26-56`): one `Stop`
  per entry of `AppModel.allCullingStacks(for:)` (every stack **and** every
  standalone, capture order) — `isStandalone = assetIDs.count <= 1`,
  `isDone = stackAssets.allSatisfy { $0.metadata.confirmedProjection.flag !=
  nil }` (**confirmed only** — `CullRunStripPresentationTests
  .testTentativeAIFlagKeepsTheStopUndone` pins this), `sparkleCount =
  stack.assetIDs.filter { pendingSparkleAssetIDs.contains($0) }.count`,
  `label = CullStackLabelPresentation.label(for: stackAssets)`. Windowing:
  `CullStripWindowing.centeredWindow(count:anchorIndex:limit:)`
  (`:64-72`) centers a `defaultVisibleLimit = 12`-wide window on the current
  stop, clamped to the sequence's bounds — unit-pinned by
  `CullStripWindowingTests` (`Tests/TeststripAppTests/
  CullRunStripPresentationTests.swift:218-254`): count=20/anchor=10/limit=6
  → window `7..<13`; anchor=0 → `0..<6`; anchor=19 → `14..<20`.
- **Rendering**, `runStrip`/`runStripStop`/`runStripPill`/
  `runStripStandaloneThumb` (`Sources/TeststripApp/LibraryGridView.swift:
  4392-4576`): a multi-frame stop renders `runStripPill` — label, a
  frame-count badge (`Text("\(stop.assetIDs.count)")`), and if
  `sparkleCount > 0` a **numeric** `Label("\(stop.sparkleCount)",
  systemImage: DesignGlyph.ai.symbolName)` chip (`:4517-4522`), orange, plus
  a green checkmark overlay if `isDone`. A standalone stop renders
  `runStripStandaloneThumb` — a thumbnail with, if `sparkleCount > 0`, an
  **icon-only** ✨ badge (no numeral — a standalone can only ever be 0 or 1,
  `:4553-4559`) and its own `isDone` checkmark overlay. Both button forms
  carry `.help(stop.label)`, `.accessibilityLabel("Stop \(stop.label)")`,
  and `.accessibilityValue(runStripStopAccessibilityValue(stop))`
  (`:4469-4504`) — the value is `["Current"]/["Done"] + "N frame(s)" +
  ["N suggestion(s)"]` joined by `", "` — the **only** reliable AX read of
  `isCurrent`/`sparkleCount` (the visual glyphs themselves aren't
  independently AX-findable, per `cull-021-stack-rail-nav.md`'s identical
  caution about the rail's `✦`). A click routes through
  `AppModel.selectStackLanding(for:)` (`AppModel.swift:7196-7201`) — the
  same preference-gated recommended-or-first landing helper `←`/`→`/`H`/`L`
  use (see `cull-022-flow-grammar-walk.md`'s T7.5 citation) — so a stop
  click never disagrees with keyboard arrival.
- **Triple counter**, `CullFilmstripPresentation.tripleCounterText`
  (`Sources/TeststripApp/CullFilmstripPresentation.swift:87-104`):
  `"\(frameIndex+1) of \(totalFrames) · stack \(stackIndex+1) of
  \(stacks.count)"`, **plus** `" · frame \(withinStackIndex+1) of
  \(stackAssetIDs.count)"` **only when** the current stop has more than one
  member (`:98-102`). The word "stack" always appears in the second segment
  even for a standalone stop (every stop, size 1 or N, is one entry in
  `stacks`) — this is the tutorial's "stop" model wearing the label
  "stack"; don't read a standalone's "stack S of Σ" segment as a bug.
- **User-origin-only progress**: `runStripStatusBar`
  (`LibraryGridView.swift:4432-4456`) computes `progressFraction =
  reviewedCount / totalCount` from `model.cullingProgressSummary`
  (`AppModel.swift:2741-2750`), whose `pickCount`/`rejectCount` come from
  `cullingDecisionCount(flag:repository:)` →
  `CatalogRepository.assetCount(ids:confirmedFlag:)` — **confirmed flags
  only** (`cull-026-tentative-never-commits.md`'s citation of this exact
  SQL predicate: `json_extract(...,'$.flag') = ? AND NOT EXISTS (...
  aiUnconfirmedFields ...)`). A tentative AI flag moves neither the
  fraction nor the HUD's `"N picks, M rejects, K left"` accessibility
  label.
- **Completion summary**, `CullCompletionPresentation.summary`/
  `.presentation` (`Sources/TeststripApp/CullCompletionPresentation.swift:
  34-118`): classifies every asset in `model.assets` (the **full session
  array**, not scope-filtered — the doc comment at `:90-99` is explicit)
  by `confirmedProjection.flag`: `.pick`/`.reject` increment picks/rejects
  and insert into `decidedAssetIDs`; `nil` (raw-undecided **or**
  tentative-AI) increments `undecided`. `neverViewed = scope ∖ viewed`,
  `sparkleAwaiting = pendingProposalAssetIDs ∩ scope`, `skipped =
  skippedAssetIDs ∩ scope ∖ decidedAssetIDs`. **Structural fact this card
  leans on**: whenever `presentation(...)` returns non-nil (gated on
  `undecided == 0`, `:107,115`), `decidedAssetIDs` is provably the *entire*
  scope (every asset fell into the `.pick`/`.reject` branch, none into
  `nil`) — so `skipped` is **always exactly 0** at completion, regardless
  of what was actually Space-skipped along the way; this is a guaranteed
  invariant, not a fixture-specific observation. The **mandatory negative**
  (`Tests/TeststripAppTests/CullCompletionTests.swift:124-147`,
  `testTentativeOnlyFlagCountsAsUndecidedAndSparkleAwaitingNeverPickedOrRejected`):
  a tentative-only flag (either value) counts in `undecided` **and**
  `sparkleAwaiting`, **never** in `picks`/`rejects`, and its scope is not
  complete. Actions (`:69-78`): the core four
  (`export`/`moveRejects`/`moveRejectsToTrash`/`reviewPicks`) always;
  `.reviewAISuggestions` appended only if `sparkleAwaiting > 0`;
  `.savePicksAsSet` appended only if `picks > 0`.
- **Rendering the summary**, `cullCompletionStage`
  (`LibraryGridView.swift:3883-3963`): exact text —
  `Text("Nothing left to decide")`; `Text("\(picks) picks · \(rejects)
  rejects")`; a run-coverage line, `cullCompletionRunDetailText`
  (`:3958-3963`): `"\(skipped) skipped · \(neverViewed) never viewed ·
  \(sparkleAwaiting) AI \(sparkleAwaiting == 1 ? "suggestion" :
  "suggestions") awaiting review"`. `undecided` itself is **never rendered
  directly** here — the gate that reveals this whole stage already proves
  it's 0, so a direct display would be redundant; this card confirms 0 via
  the presentation math instead. Action button titles
  (`:3932-3956`): `"Export"`, `"Move Rejects…"`, `"Move Rejects to
  Trash…"`, `"Review Picks"`, `"Review AI Suggestions"`, `"Save Picks as
  Set"`. `"Review AI Suggestions"` calls `reviewAutopilotRun()` →
  `beginAutopilotReview()` (the same flow `cull-017-autopilot-review.md`
  drives end-to-end — not re-driven here). `"Save Picks as Set"` calls
  `model.saveCullingPicksAsSet()` (`AppModel.swift:5644-5670`): with **no**
  active persisted culling session (burst seeds directly, bypassing
  `IngestService` — same gap `cull-021-stack-rail-nav.md` documents), it
  takes the ad-hoc branch (`:5659-5669`) — snapshots
  `assets.filter { confirmedProjection.flag == .pick }.map(\.id)` into a
  **new** `AssetSet(membership: .snapshot(...))`, named via
  `suggestedPicksSetName` (`:5672-5680`: `"Catalog Picks"` absent an active
  set/search context). Persisted at `asset_sets.membership_json`; a
  `.snapshot([AssetID])` encodes at JSON path `$.snapshot._0`, each element
  `{"rawValue": "<id>"}` (`CatalogRepository
  .workSessionAssetMembershipSelector`, `Sources/TeststripCore/Catalog/
  CatalogRepository.swift:3395-3414`, the same path shape `cull-021`
  documents for `work-stack-` sets, applied here to a plain saved set).
- **Fixture and seeding gap**: neither `autopilot_proposals` rows nor a
  tentative-AI flag are produced by any seed command (`cull-026`'s
  established finding for the flag half). `autopilot_proposals`
  (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:209-223`) has
  **no foreign-key constraint** on `run_id` — it's a plain `TEXT` column —
  so this card seeds it directly, mirroring `cull-026`'s local-template-patch
  technique one table further, rather than relying on a live Evaluate+Run
  Autopilot pass whose success on `burst`'s flat synthetic rectangles is
  **not established** (`AutopilotProposalPlanner.cullProposals`,
  `Sources/TeststripCore/Autopilot/AutopilotProposalPlanner.swift:60-73`,
  produces zero proposals for a stack with zero rankable signals — the same
  honest-branch risk `cull-021`/`cull-024` already flag for this exact
  fixture). `reconstructAutopilotStateAfterLoad()` (`AppModel.swift:
  9927-9943`, called unconditionally from `AppModel.load(catalog:)` at
  `:4685`) reloads `pendingAutopilotProposals` from **any** pending rows at
  launch — hand-seeded or not — so this technique is picked up exactly like
  a real run's output. Side effect: since it also derives
  `autopilotRunSummary` from the newest `run_id`'s rows, the plain
  autopilot banner may render early (informational — not this card's
  concern, see Sharp edges).

## Pre-state — Leg A: `burst` (stacks, sparkle chips, completion, six counts)
```bash
rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip"
script/vm_scenario_run.sh sync burst

# burst's shared flag formula (SmokeCatalogSeeder.swift:147) leaves smoke-4
# (group2: smoke-3,4,5,6) and smoke-16 (a standalone single) unflagged.
# Seed a tentative AI reject on smoke-4 and a tentative AI pick on smoke-16,
# each backed by a real pending autopilot_proposals row.
TEMPLATE_DB="${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip/catalog.sqlite"
sqlite3 "$TEMPLATE_DB" "
  UPDATE assets SET metadata_json = json_set(metadata_json, '\$.flag','reject','\$.aiUnconfirmedFields',json('[\"flag\"]')) WHERE id = 'smoke-4';
  UPDATE assets SET metadata_json = json_set(metadata_json, '\$.flag','pick','\$.aiUnconfirmedFields',json('[\"flag\"]')) WHERE id = 'smoke-16';
  INSERT INTO autopilot_proposals (id, run_id, asset_id, kind, keyword, rationale, confidence, status, created_at, updated_at) VALUES
    ('seeded-prop-4', 'seeded-run-1', 'smoke-4', 'reject', '', 'seeded fixture', 0.9, 'pending', strftime('%s','now'), strftime('%s','now')),
    ('seeded-prop-16', 'seeded-run-1', 'smoke-16', 'pick', '', 'seeded fixture', 0.9, 'pending', strftime('%s','now'), strftime('%s','now'));"

script/vm_scenario_run.sh sync burst
script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
```
**Note**: mutates the shared local `burst` template. Run
`rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip"` before any
later card in the same session that needs the pristine baseline.

## Steps — Leg A
1. **Confirm the seed landed, live.**
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT id, json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag')
      FROM assets WHERE id IN ('smoke-4','smoke-16') ORDER BY id;"   # expect reject|1 and pick|1
   script/vm_scenario_run.sh sql burst "SELECT count(*) FROM autopilot_proposals WHERE status='pending';"   # expect 2
   ```
   `ax wait-vended`; ⌘1 for Cull; `S` to "All frames". Confirm the initial
   selection is `smoke-0` (adjust the rest of this leg's navigation if not).
2. **Negative invariant, live**: confirm both tentative assets count as
   undecided and never as picked/rejected. Independently compute the
   confirmed split (mirrors `cull-026`'s `assetCount(ids:confirmedFlag:)`
   predicate):
   ```bash
   CONF_PICK=$(script/vm_scenario_run.sh sql burst "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick' AND NOT EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');")
   CONF_REJECT=$(script/vm_scenario_run.sh sql burst "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject' AND NOT EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');")
   ```
   Expect `CONF_PICK=4`, `CONF_REJECT=4` (burst's baseline confirmed
   counts — `smoke-16`/`smoke-4` excluded despite their raw `flag` values).
   Cross-check the HUD: `ax find --role AXStaticText --contains "$CONF_PICK
   picks, $CONF_REJECT rejects"` should match (10 left: 18 total - 8
   confirmed). This corroborates
   `CullCompletionTests.testTentativeOnlyFlagCountsAsUndecidedAndSparkleAwaitingNeverPickedOrRejected`
   live.
3. **✨ chips on the run strip.** Burst has only 8 total stops (well under
   `defaultVisibleLimit = 12`), so every stop renders regardless of current
   selection — no navigation needed for this step. Confirm group2's stop
   (a 4-frame pill containing `smoke-4`) shows the numeric sparkle chip:
   find its stop button (`ax find --role AXButton --contains "smoke-4"` —
   matches the `.help`/label text, which for a multi-frame stop is a
   file-range like `smoke-3–6`; if that substring doesn't match directly,
   use `--contains "smoke-3"` instead, since the pill's label collapses the
   range) and read its accessibility value: expect it to contain `"1
   suggestion"`. Confirm `smoke-16`'s standalone stop
   (`ax find --role AXButton --contains "smoke-16 ·"` — the trailing
   `" ·"` disambiguates from `smoke-1`, which is otherwise a substring of
   `smoke-16`'s label) also has accessibility value containing `"1
   suggestion"`. Confirm every OTHER stop's value contains no
   `"suggestion"` substring (spot-check group1's and group3's stops).
4. **Triple counter, multi-frame shape.** With `smoke-0` still selected
   (part of group1, a 3-frame stop — no navigation yet), read the triple
   counter text (`ax find --role AXStaticText --contains "stack 1 of 8"` —
   8 total stops, 4 stacks + 4 singles) and confirm it ends with `"frame 1
   of 3"` (the third segment, present only for a multi-frame stop).
5. **Isolated progress test — the load-bearing user-origin-only check.**
   Navigate **forward** to `smoke-4` (Space 4 times from `smoke-0`, polling
   the HUD filename each press — Space only ever moves forward in Cull
   chrome, so every leg from here on navigates strictly forward through the
   catalog, never backward). Record the HUD's reviewed count before
   deciding it:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "$CONF_PICK picks, $CONF_REJECT rejects"
   ```
   (still the Step 2 baseline — `smoke-4`'s tentative reject has not moved
   it.) Press `P` (`script/vm_scenario_run.sh key 'keystroke "p"'`) —
   overriding the tentative reject to a confirmed pick. Poll:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "$((CONF_PICK+1)) picks, $CONF_REJECT rejects"
   ```
   Confirms the progress bar/HUD advanced by exactly one **only** once a
   real user-origin decision landed, not when the tentative flag merely
   existed.
6. **View the whole scope, deterministically, before deciding anything
   else — and the standalone triple counter.** From `smoke-4`, continue
   pressing `Space` (decision-free) until `smoke-16.jpg` is selected,
   polling the HUD filename at each step and confirming strict catalog
   order (`smoke-5`, `smoke-6`, …, `smoke-16`). On arrival, confirm the
   triple counter now reads `"... · stack 6 of 8"` with **no** trailing
   `"frame"` segment (a standalone stop — the mirror of Step 4's
   multi-frame check). Continue `Space` once more to `smoke-17.jpg` (the
   last catalog asset). This forward walk from `smoke-0` through
   `smoke-17` (Steps 1, 5, 6 together) means every one of the 18 assets has
   been individually selected at least once in this run, which is what
   `neverViewed` counts (`AppModel.swift`'s `selectAssetID` records
   `recordViewed` on every selection, per `Sources/TeststripApp/
   CullRunTracker.swift`).
7. **Decide every remaining undecided frame.** The 9 still-undecided
   assets after Steps 5-6 are `smoke-1, smoke-2, smoke-7, smoke-8,
   smoke-11, smoke-13, smoke-14, smoke-16, smoke-17` (everything not
   already confirmed at seed time or decided in Step 5) — cross-check this
   list against `script/vm_scenario_run.sh sql burst "SELECT id FROM assets
   WHERE json_extract(metadata_json,'\$.flag') IS NULL ORDER BY id;"`
   before starting. For each: click its run-strip stop (`ax_drive.sh press
   --role AXButton --contains "<label substring>"`) if not already the
   current stop, step within a multi-frame stop with `J` to reach the
   specific undecided member (its chip shows no pick/reject overlay yet —
   `cull-021-stack-rail-nav.md`'s decision-overlay citation), and press `P`
   **only on that member** — do not press `P` while merely passing an
   already-decided member with `J` on the way, or it would silently flip a
   baseline-confirmed reject (e.g. `smoke-10`, `smoke-15`) to a pick and
   invalidate Step 8's predicted `14 picks · 4 rejects`. Poll the HUD's
   `"K left"` segment (`ax find --role AXStaticText --contains " left"` —
   read the number) after each decision until it reads `0`.
8. **Completion summary renders.** Poll:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Nothing left to decide"
   ```
   Assert the exact picks/rejects line — with all 10 originally-undecided
   assets picked (Steps 5+7), expect `14 picks · 4 rejects`:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "14 picks · 4 rejects"
   ```
   Cross-check against the catalog:
   ```bash
   script/vm_scenario_run.sh sql burst \
     "SELECT json_extract(metadata_json,'\$.flag'),
             EXISTS(SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag'), count(*)
      FROM assets GROUP BY 1,2;"
   ```
   Expect exactly two rows: `pick|0|14` and `reject|0|4` (no `NULL` row —
   session-wide undecided is genuinely 0; no row with
   `aiUnconfirmedFields` containing `flag` — nothing tentative survives to
   completion, by construction: the gate itself requires undecided==0 and
   a tentative flag always counts as undecided).
9. **Run-coverage line — six counts in total.** First, the one piece that's
   a hard guarantee regardless of navigation path:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "0 skipped ·"
   ```
   (Source's structural guarantee — any Space-skip along the way was later
   decided by definition of reaching this stage; **fails if this doesn't
   match**, no exceptions.) Then read the full line and record what it
   says for `neverViewed`/`sparkleAwaiting`:
   ```bash
   script/vm_scenario_run.sh ax find --role AXStaticText --contains "AI suggestions awaiting review"
   ```
   Expect it to read exactly `"0 skipped · 0 never viewed · 2 AI
   suggestions awaiting review"`. `neverViewed = 0` is Steps 1+6's
   deliberate full walk's *predicted* (not structurally guaranteed) outcome
   — if it comes back nonzero, report the observed number rather than
   treating it as an automatic fail (see Sharp edges). `sparkleAwaiting`
   not reading exactly `2` **is** a fail: both seeded proposals should
   still be `status='pending'` — deciding `smoke-4`/`smoke-16` directly
   (Steps 5/7) confirmed their **flags** but never touched the proposal
   rows themselves (only `beginAutopilotReview()`'s commit/dismiss flow
   does that) — confirm live:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT count(*) FROM autopilot_proposals WHERE status='pending';"   # still 2
   ```
10. **Ceremony actions, gated correctly.** Confirm both follow-up actions
    are present (both have real work: `sparkleAwaiting=2>0`,
    `picks=14>0`):
    ```bash
    script/vm_scenario_run.sh ax find --role AXButton --contains "Review AI Suggestions"
    script/vm_scenario_run.sh ax find --role AXButton --contains "Save Picks as Set"
    ```
    Press "Save Picks as Set". Ground truth — a new set exists, named
    "Catalog Picks" (no active session/search context), containing
    exactly the 14 confirmed-pick asset ids and nothing else:
    ```bash
    script/vm_scenario_run.sh sql burst \
      "SELECT json_extract(m.value,'\$.rawValue') FROM asset_sets s, json_each(s.membership_json,'\$.snapshot._0') m
       WHERE s.name = 'Catalog Picks' ORDER BY 1;"
    script/vm_scenario_run.sh sql burst \
      "SELECT id FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick' ORDER BY id;"
    ```
    Both lists must be identical (14 ids). Since every flag in the catalog
    is confirmed by this point (Step 8's cross-check), this also trivially
    proves "only user-origin picks" — the completion gate structurally
    forbids a tentative pick from ever surviving to this stage, so the ONLY
    way to exercise a tentative pick leaking into a saved set is the
    ad-hoc/mid-session path already covered by
    `CullCompletionTests.testSaveCullingPicksAsSetWithoutSessionSnapshotsConfirmedPicksOnly`/
    `testSaveCullingPicksAsSetThrowsWhenOnlyTentativePicksExist` at the
    unit level — not reachable live from this completion stage by
    construction.

## Pre-state — Leg B: `smoke` (windowing depth, standalone-only triple counter)
```bash
script/vm_scenario_run.sh sync smoke && script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql smoke "..."
```
`--smoke` seeds 24 assets 900s apart — zero multi-frame stacks, so all 24
stops are standalone (`cull-022`'s Leg B fixture) — the only variant with
more than `defaultVisibleLimit = 12` stops, needed to observe windowing at
all.

## Steps — Leg B
11. `ax wait-vended`; ⌘1 for Cull; `S` to "All frames". Confirm `smoke-0` is
    selected.
12. **Start-clamped window.** Per `CullStripWindowingTests`
    (count=24, anchor=0, limit=12 → `0..<12`): confirm `smoke-0 ·` through
    `smoke-11 ·` are each findable (`ax find --role AXButton --contains
    "smoke-N ·"`, spot-check a few, e.g. 0, 6, 11) and `smoke-12 ·` /
    `smoke-23 ·` are **not** findable. (The trailing `" ·"` in every match
    pattern is load-bearing: `smoke-1` is a literal substring of
    `smoke-10`…`smoke-19`, so a bare `--contains "smoke-1"` would false-
    positive-match ten different stops.)
13. **Centered window.** Press `Space` 10 times from `smoke-0`, polling the
    HUD filename, to reach `smoke-10`. Per the math (anchor=10, limit=12 →
    `4..<16`): confirm `smoke-4 ·` through `smoke-15 ·` findable (spot-check
    4, 10, 15) and `smoke-0 ·`/`smoke-3 ·`/`smoke-16 ·`/`smoke-23 ·` not
    findable. Confirm current-stop marking: exactly one stop's
    accessibility value contains `"Current"`
    (`ax find --role AXButton --contains "Current"`).
14. **End-clamped window.** Continue `Space` 13 more times (10→23) to reach
    `smoke-23.jpg` (the last asset), polling the filename each step. Per
    the math (anchor=23, limit=12 → `12..<24`): confirm `smoke-12 ·`
    through `smoke-23 ·` findable (spot-check 12, 18, 23) and `smoke-0 ·`
    through `smoke-11 ·` not findable.
15. **Standalone-only triple counter.** With `smoke-23` selected, confirm
    the triple counter reads `"24 of 24 · stack 24 of 24"` with **no**
    trailing `"frame"` segment (every stop here has exactly 1 member).

## Expected
- Step 3: **Fails if** either stop's accessibility value omits the
  suggestion count, or if any other stop wrongly shows one.
- Step 4: **Fails if** the multi-frame stop's counter omits the `"frame X
  of Y"` segment.
- Step 5: **Fails if** the picks count moved before the `P` keypress, or
  didn't move by exactly one immediately after it.
- Step 6: **Fails if** the standalone stop's counter wrongly includes a
  `"frame"` segment, or if the `Space` walk skips an asset (filename
  doesn't advance one at a time in strict catalog order).
- Step 8: **Fails if** the picks/rejects text disagrees with the SQL
  cross-check, or if any asset's raw flag disagrees with its confirmed
  projection (a lingering tentative marker at the completion stage would be
  a genuine invariant violation, not a fixture quirk).
- Step 9: **Fails if** `skipped` is nonzero (no exceptions — this is a
  structural guarantee, see Source), or if `sparkleAwaiting` isn't exactly
  2, or if the seeded `autopilot_proposals` rows are no longer `pending`
  (would mean something silently auto-committed/dismissed them).
  `neverViewed` nonzero is reportable-not-fatal (see Sharp edges) unless
  the Step 1/6 walk was skipped, in which case investigate before
  dismissing it.
- Step 10: **Fails if** either action is missing despite having work to do,
  if the saved set's membership disagrees with the confirmed-picks list, or
  if the set name isn't `"Catalog Picks"`.
- Steps 12-14: **Fails if** any in-window stop is missing, any out-of-window
  stop is present, or the window boundaries disagree with
  `CullStripWindowing.centeredWindow`'s documented formula for that
  count/anchor/limit triple.
- Step 15: **Fails if** the standalone-only batch's triple counter ever
  shows a "frame" segment.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
# Leg A only — reset the mutated local seed template:
rm -rf "${TMPDIR:-/tmp}/teststrip-vm-seeds/burst/Teststrip"
```
Run once per leg (separate launches); quit each instance before the next.

## Sharp edges
- **`neverViewed`'s exact value depends on this card's specific navigation
  path**, unlike `skipped` (which is a hard structural guarantee
  independent of driving). Steps 1+6's deliberate full forward walk is
  designed to make it provably 0, but if a driver deviates from that exact
  sequence (e.g., uses stop-clicks instead of `Space` for the initial
  walk-through, which *also* records a view — fine — or skips Step 6
  outright), a nonzero `neverViewed` is expected and should be reported as
  observed, not treated as a card failure on its own.
- **A plain autopilot banner may appear early**, above the stage, once
  `reconstructAutopilotStateAfterLoad()` sees this card's hand-seeded
  `autopilot_proposals` rows at launch — it doesn't distinguish a real
  Autopilot run from a seeded one. This is expected, not a bug; it doesn't
  interfere with any assertion here, and its own "Review"/"Undo all"
  buttons are `cull-017-autopilot-review.md`'s territory, not re-driven.
- **The run strip's stop labels embed a capture-time string** (`"HH:MM
  AM/PM"`) computed from `Date()` at seed time, not a fixed epoch — this
  card never matches on the time portion of a label, only on the filename
  stem plus a disambiguating separator (`" ·"` or `"–"`), per Step 12's
  note.
- **This card mutates the shared local `burst` seed template** (Pre-state,
  Leg A) — see Cleanup.
- **This card does not re-derive `AutopilotProposalPlanner`'s ranking
  logic** or drive a live Evaluate+Run Autopilot pass — `app-012-
  autopilot-evaluate-commands.md` and `cull-017-autopilot-review.md` own
  that path end-to-end; this card only needs *some* pending proposal rows
  to exist, and seeds them directly for determinism (Source above).

## Run status
NOT RUN — authored 2026-07-16, source-cited against the working tree by
directly reading `CullRunStripPresentation.swift`, `CullCompletionPresentation.swift`,
`LibraryGridView.swift` (`runStrip`/`runStripStop`/`runStripPill`/
`runStripStandaloneThumb`/`cullCompletionStage`/`cullCompletionActionButton`),
`CullFilmstripPresentation.swift`, `AppModel.swift`
(`cullingProgressSummary`, `saveCullingPicksAsSet`,
`reconstructAutopilotStateAfterLoad`), `AutopilotProposalPlanner.swift`,
`CatalogMigrations.swift`, `CatalogRepository.swift`, and
`Tests/TeststripAppTests/CullRunStripPresentationTests.swift`/
`CullCompletionTests.swift`, not carried over from any older card; pending
live VM execution per `test/scenarios/README.md`.
