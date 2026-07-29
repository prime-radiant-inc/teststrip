# cull-025-run-strip-completion: the run strip's stops and windowing agree with the catalog; the completion summary's six counts (the cull view's only ✨ surface) and gated ceremony actions match the traversal

**What this covers**: as a photographer blazing through a whole batch, the
bottom run strip is my "how much is left" glance — one stop per stack or
standalone, the current stop highlighted, and a triple counter/progress bar
that only ever move on *my* decisions, never a machine's tentative guess.
The run strip itself carries no ✨ affordance (kata #13 dropped the old
per-stop suggestion chip — it was kind-blind and flag-blind and routinely
disagreed with the completion stage's count, so Jesse chose removal over
reconciling the two; see Source's "Rendering" bullet and the Sharp edges
note below). When every frame in scope carries a confirmed decision, the
completion summary replaces the stage with all six counts (picked /
rejected / undecided / skipped / never-viewed / ✨ awaiting review — the
cull view's only remaining ✨ surface) and a small set of ceremony actions
that only appear when they have real work to do.

Source (re-verified against the working tree on this branch, **2026-07-16**;
every symbol below was re-grepped fresh, not carried over from any older
card):
- **Stops**, `CullRunStripPresentation.stops(...)`
  (`Sources/TeststripApp/CullRunStripPresentation.swift:25-52`): one `Stop`
  per entry of `AppModel.allCullingStacks(for:)` (every stack **and** every
  standalone, capture order) — `isStandalone = assetIDs.count <= 1`,
  `isDone = stackAssets.allSatisfy { $0.metadata.confirmedProjection.flag !=
  nil }` (**confirmed only** — `CullRunStripPresentationTests
  .testTentativeAIFlagKeepsTheStopUndone` pins this),
  `label = CullStackLabelPresentation.label(for: stackAssets)`. **No
  `sparkleCount` field and no `pendingSparkleAssetIDs` parameter** — kata
  #13 removed both along with the run-strip chip they fed (see
  "Rendering" below); `stops(...)` now takes only
  `assets:stacks:selectedAssetID:visibleLimit:`. Windowing:
  `CullStripWindowing.centeredWindow(count:anchorIndex:limit:)`
  (`:60-68`) centers a `defaultVisibleLimit = 12`-wide window on the current
  stop, clamped to the sequence's bounds — unit-pinned by
  `CullStripWindowingTests` (`Tests/TeststripAppTests/
  CullRunStripPresentationTests.swift:189-225`): count=20/anchor=10/limit=6
  → window `7..<13`; anchor=0 → `0..<6`; anchor=19 → `14..<20`.
- **Rendering**, `runStrip`/`runStripStop`/`runStripStackThumb`/
  `runStripStandaloneThumb`/`runStripThumbnailFace`
  (`Sources/TeststripApp/LibraryGridView.swift:4507-4708`). **Reconciled
  2026-07-17 (dogfood-r1 panel pass)**: a multi-frame stop no longer renders
  as a wide text pill (`label` + count + sparkle chip in a `Capsule`) — it
  now renders `runStripStackThumb`, a small **photo stack**: the lead
  frame's thumbnail (`runStripThumbnailFace`, shared with the standalone
  thumb below) on top of 1-2 dimmer offset card layers behind it (a second
  layer only when the stack has 3+ frames), plus a frame-count `Text` badge
  at the bottom-trailing corner. The machine-fact label (file range · time)
  no longer renders as ambient chrome at all — it lives *only* in the
  stop's `.help(stop.label)` tooltip (unchanged from before; see below). A
  standalone stop still renders `runStripStandaloneThumb` — now just
  `runStripThumbnailFace(stop)`, unchanged visually except for the removal
  below.

  **Reconciled 2026-07-29 (kata #13, chip removed)**: `runStripThumbnailFace`
  no longer renders any sparkle badge at all — no icon-only form for a
  standalone, no numeric form for a stack, and the `sparkleShowsCount`
  parameter that used to select between them is gone from its signature
  entirely (both call sites, `runStripStandaloneThumb` and
  `runStripStackThumb`, now call `runStripThumbnailFace(stop)` with no
  second argument). The green `isDone` checkmark overlay and the
  current-stop selection ring are unaffected. Both button forms still carry
  `.help(stop.label)`, `.accessibilityLabel("Stop \(stop.label)")`, and
  `.accessibilityValue(runStripStopAccessibilityValue(stop))`
  (`:4602-4604`) — the value is now just `["Current"]/["Done"] + "N
  frame(s)"` joined by `", "`; the old trailing `["N suggestion(s)"]`
  segment is gone along with the field that fed it
  (`stop.sparkleCount`). This is the **only** reliable AX read of
  `isCurrent` (the orange selection ring isn't independently AX-findable,
  per `cull-021-stack-rail-nav.md`'s identical caution about the rail's
  `✦`) — every `find`/`--contains` assertion below that reads
  `isCurrent`/`isDone`/frame-count off this accessibility value (not the
  rendered `Text`) still holds unchanged; only assertions that read the
  now-gone suggestion segment (removed from this card below) are affected.
  A click routes through `AppModel.selectStackLanding(for:)`
  (`AppModel.swift:7213-7218`) — the same preference-gated
  recommended-or-first landing helper `←`/`→`/`H`/`L` use (see
  `cull-022-flow-grammar-walk.md`'s T7.5 citation) — so a stop click never
  disagrees with keyboard arrival.
- **Triple counter**, `CullFilmstripPresentation.tripleCounterText`
  (`Sources/TeststripApp/CullFilmstripPresentation.swift:59-76`):
  `"\(frameIndex+1) of \(totalFrames) · stack \(stackIndex+1) of
  \(stacks.count)"`, **plus** `" · frame \(withinStackIndex+1) of
  \(stackAssetIDs.count)"` **only when** the current stop has more than one
  member (`:71-74`). The word "stack" always appears in the second segment
  even for a standalone stop (every stop, size 1 or N, is one entry in
  `stacks`) — this is the tutorial's "stop" model wearing the label
  "stack"; don't read a standalone's "stack S of Σ" segment as a bug.
- **User-origin-only progress**: `runStripStatusBar`
  (`LibraryGridView.swift:4543-4567`) computes `progressFraction =
  reviewedCount / totalCount` from `model.cullingProgressSummary`
  (`AppModel.swift:2754-2763`), whose `pickCount`/`rejectCount` come from
  `cullingDecisionCount(flag:repository:)` →
  `CatalogRepository.assetCount(ids:confirmedFlag:)` — **confirmed flags
  only** (`cull-026-tentative-never-commits.md`'s citation of this exact
  SQL predicate: `json_extract(...,'$.flag') = ? AND NOT EXISTS (...
  aiUnconfirmedFields ...)`). A tentative AI flag moves neither the
  fraction nor the HUD's `"N picks, M rejects, K left"` accessibility
  label.
- **Completion summary**, `CullCompletionPresentation.summary`/
  `.presentation` (`Sources/TeststripApp/CullCompletionPresentation.swift:
  43-133`): classifies every asset in `model.assets` (the **full session
  array**, not scope-filtered — the doc comment at `:103-112` is explicit)
  by `confirmedProjection.flag`: `.pick`/`.reject` increment picks/rejects
  and insert into `decidedAssetIDs`; `nil` (raw-undecided **or**
  tentative-AI) increments `undecided`. `neverViewed = scope ∖ viewed`,
  `skipped = skippedAssetIDs ∩ scope ∖ decidedAssetIDs`. **Structural facts
  this card leans on**: whenever `presentation(...)` returns non-nil (gated
  on `undecided == 0`, `:121,130`), `decidedAssetIDs` is provably the
  *entire* scope (every asset fell into the `.pick`/`.reject` branch, none
  into `nil`) — so `skipped` is **always exactly 0** at completion,
  regardless of what was actually Space-skipped along the way, and this is
  a guaranteed invariant, not a fixture-specific observation.

  **`sparkleAwaiting`'s kind-aware contract (2026-07-28, supersedes the
  original Task 3 corollary below)**: `summary` takes two pending-proposal
  sets split by `AutopilotProposalKind` at the `LibraryGridView`
  `cullCompletion` call site — `pendingFlagProposalAssetIDs` (`.pick`/
  `.reject`) and `pendingKeywordProposalAssetIDs` (`.keyword`). A pending
  FLAG proposal is excluded once its asset's flag is user-confirmed (the
  original Task 3 filter, unchanged); since completion structurally
  guarantees every in-scope asset's flag IS confirmed (the same fact
  `skipped`'s guarantee above leans on), **no pending flag proposal ever
  contributes to `sparkleAwaiting` at completion, regardless of fixture**.
  A pending KEYWORD proposal, in contrast, counts **regardless of the
  asset's flag** — a keyword suggestion has nothing to do with the flag
  decision — so `sparkleAwaiting` at completion is exactly the count of
  in-scope assets still carrying a pending keyword proposal. It is **no
  longer structurally guaranteed to be 0**: this card's own Leg A fixture
  (Pre-state below) seeds only FLAG-kind proposals (`kind: 'reject'`/
  `'pick'` on `smoke-4`/`smoke-16`), so the *predicted* `sparkleAwaiting` at
  completion is still 0 for THIS fixture — but that is now a fixture fact,
  not an invariant. **What failure looks like**: a regression that reverts
  to kind-blind filtering (checking `confirmedProjection.flag == nil`
  against the union of both sets, or against a single unsplit set) would
  silently drop any pending keyword proposal on an already-decided asset,
  under-reporting `sparkleAwaiting` and hiding `.reviewAISuggestions` even
  though a genuine keyword suggestion sits unreviewed — the bug Finding 1
  (`fix/cull-followups`,
  `testSparkleAwaitingCountsPendingKeywordProposalEvenWithConfirmedFlag`,
  `Tests/TeststripAppTests/CullCompletionTests.swift:241-255`) fixed. The
  **mandatory negatives**
  (`Tests/TeststripAppTests/CullCompletionTests.swift:147-172`
  `testTentativeOnlyFlagCountsAsUndecidedAndSparkleAwaitingNeverPickedOrRejected`;
  `:182-198`
  `testSparkleAwaitingExcludesAssetWithPendingProposalAndConfirmedFlag`;
  `:257-271`
  `testSparkleAwaitingStillExcludesPendingFlagProposalWithConfirmedFlag`;
  `:273-290`
  `testSparkleAwaitingCountsMixedFlagAndKeywordProposalsExactly`):
  a tentative-only flag (either value) counts in `undecided` **and**
  `sparkleAwaiting`, **never** in `picks`/`rejects`, and its scope is not
  complete; a pending FLAG proposal whose asset already carries a confirmed
  flag is excluded from `sparkleAwaiting` even though the proposal row
  itself is left `pending`, untouched; a pending KEYWORD proposal is
  counted even when its asset's flag is confirmed; a mixed set of flag and
  keyword proposals counts exactly the genuinely-awaiting subset. Actions
  (`:82-91`): the core four (`export`/`moveRejects`/`moveRejectsToTrash`/
  `reviewPicks`) always; `.reviewAISuggestions` appended only if
  `sparkleAwaiting > 0`; `.savePicksAsSet` appended only if `picks > 0`.

  *Original Task 3 corollary (2026-07-28, superseded by the kind-aware
  contract above)*: this card previously claimed `sparkleAwaiting` was
  **always exactly 0** the instant the completion stage renders, on the
  theory that every asset in scope already has a confirmed flag by the
  `undecided == 0` fact. That reasoning only ever covered FLAG proposals —
  it never accounted for pending KEYWORD proposals, which Finding 1
  corrected `summary` to count independently of the flag. The corollary is
  false in general; see the kind-aware contract above for what actually
  holds.
- **Rendering the summary**, `cullCompletionStage`
  (`LibraryGridView.swift:3940-4020`): exact text —
  `Text("Nothing left to decide")`; `Text("\(picks) picks · \(rejects)
  rejects")`; a run-coverage line, `cullCompletionRunDetailText`
  (`:4015-4020`): `"\(skipped) skipped · \(neverViewed) never viewed ·
  \(sparkleAwaiting) AI \(sparkleAwaiting == 1 ? "suggestion" :
  "suggestions") awaiting review"`. `undecided` itself is **never rendered
  directly** here — the gate that reveals this whole stage already proves
  it's 0, so a direct display would be redundant; this card confirms 0 via
  the presentation math instead. Action button titles
  (`:3992-4009`): `"Export"`, `"Move Rejects…"`, `"Move Rejects to
  Trash…"`, `"Review Picks"`, `"Review AI Suggestions"`, `"Save Picks as
  Set"`. `"Review AI Suggestions"` calls `reviewAutopilotRun()` →
  `beginAutopilotReview()` (the same flow `cull-017-autopilot-review.md`
  drives end-to-end — not re-driven here). `"Save Picks as Set"` calls
  `model.saveCullingPicksAsSet()` (`AppModel.swift:5660-5686`): with **no**
  active persisted culling session (burst seeds directly, bypassing
  `IngestService` — same gap `cull-021-stack-rail-nav.md` documents), it
  takes the ad-hoc branch (`:5675-5686`) — snapshots
  `assets.filter { confirmedProjection.flag == .pick }.map(\.id)` into a
  **new** `AssetSet(membership: .snapshot(...))`, named via
  `suggestedPicksSetName` (`:5688-5696`: `"Catalog Picks"` absent an active
  set/search context). Persisted at `asset_sets.membership_json`; a
  `.snapshot([AssetID])` encodes at JSON path `$.snapshot._0`, each element
  `{"rawValue": "<id>"}` (`CatalogRepository
  .workSessionAssetMembershipSelector`, `Sources/TeststripCore/Catalog/
  CatalogRepository.swift:3405-3414`, the same path shape `cull-021`
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
  9944-9960`, called unconditionally from `AppModel.load(catalog:)` at
  `:4698`) reloads `pendingAutopilotProposals` from **any** pending rows at
  launch — hand-seeded or not — so this technique is picked up exactly like
  a real run's output. Side effect: since it also derives
  `autopilotRunSummary` from the newest `run_id`'s rows, the plain
  autopilot banner may render early (informational — not this card's
  concern, see Sharp edges).

## Pre-state — Leg A: `burst` (stacks, completion, six counts)
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
3. **Triple counter, multi-frame shape.** With `smoke-0` still selected
   (part of group1, a 3-frame stop — no navigation yet), read the triple
   counter text (`ax find --role AXStaticText --contains "stack 1 of 8"` —
   8 total stops, 4 stacks + 4 singles) and confirm it ends with `"frame 1
   of 3"` (the third segment, present only for a multi-frame stop).
4. **Isolated progress test — the load-bearing user-origin-only check.**
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
5. **View the whole scope, deterministically, before deciding anything
   else — and the standalone triple counter.** From `smoke-4`, continue
   pressing `Space` (decision-free) until `smoke-16.jpg` is selected,
   polling the HUD filename at each step and confirming strict catalog
   order (`smoke-5`, `smoke-6`, …, `smoke-16`) — **live correction (traced
   2026-07-28)**: this strict one-at-a-time order does not actually survive
   Step 4's `P` keypress; see the note below and the Sharp edges bullet.
   On arrival, confirm the triple counter now reads `"... · stack 7 of 8"`
   (**live correction**: the card originally said `"stack 6 of 8"` — a hand-
   counting error; `smoke-16` is the 7th stop in capture order — group1,
   group2, group3, group4, `smoke-14`, `smoke-15`, `smoke-16`, `smoke-17` —
   confirmed live via the full triple-counter text `"17 of 18 · stack 7 of
   8"`) with **no** trailing `"frame"` segment (a standalone stop — the
   mirror of Step 3's multi-frame check). Continue `Space` once more to
   `smoke-17.jpg` (the last catalog asset). **Live correction**: the
   original claim that this walk (Steps 1, 4, 5 together) "means every one
   of the 18 assets has been individually selected at least once" is false
   in general — Step 4's `P` on `smoke-4` triggers the same auto-advance
   this card's Hard-won context already flags, which does not land on the
   flat next asset (`smoke-5`) but jumps straight to the next asset that
   still needs a decision; when that next-undecided asset lives in a
   *different* stack (as here — `smoke-4` was the only undecided member
   left in its own 4-frame stack, so auto-advance jumped to the next
   stack's landing frame, `smoke-7`), the never-individually-selected
   remainder of the vacated stack (`smoke-5`, `smoke-6`, both already
   baseline-decided) is silently skipped. `neverViewed` counts exactly this
   — see Step 8's traced value and the Sharp edges bullet for the full
   mechanism (`AppModel.swift`'s `selectAssetID` records `recordViewed` on
   every selection, per `Sources/TeststripApp/CullRunTracker.swift`, and
   only the asset actually landed on is recorded — passing frames within a
   stack are not).
6. **Decide every remaining undecided frame.** The 9 still-undecided
   assets after Steps 4-5 are `smoke-1, smoke-2, smoke-7, smoke-8,
   smoke-11, smoke-13, smoke-14, smoke-16, smoke-17` (everything not
   already confirmed at seed time or decided in Step 4) — cross-check this
   list against `script/vm_scenario_run.sh sql burst "SELECT id FROM assets
   WHERE json_extract(metadata_json,'\$.flag') IS NULL OR EXISTS (SELECT 1
   FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE
   value='flag') ORDER BY id;"` before starting (**live correction**: the
   original bare `flag IS NULL` predicate under-reports by one — `smoke-16`
   carries a non-`NULL` raw `flag` value, 'pick', from the Pre-state seed,
   so it's excluded by a plain `IS NULL` check despite being logically
   undecided via its tentative marker; confirmed live, the bare query
   returns only 8 rows, missing `smoke-16`, while the corrected query above
   returns the full 9). For each: click its run-strip stop (`ax_drive.sh press
   --role AXButton --contains "<label substring>"`) if not already the
   current stop, step within a multi-frame stop with `J` to reach the
   specific undecided member (its chip shows no pick/reject overlay yet —
   `cull-021-stack-rail-nav.md`'s decision-overlay citation), and press `P`
   **only on that member** — do not press `P` while merely passing an
   already-decided member with `J` on the way, or it would silently flip a
   baseline-confirmed reject (e.g. `smoke-10`, `smoke-15`) to a pick and
   invalidate Step 7's predicted `14 picks · 4 rejects`. Poll the HUD's
   `"K left"` segment (`ax find --role AXStaticText --contains " left"` —
   read the number) after each decision until it reads `0`.
7. **Completion summary renders.** Poll:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Nothing left to decide"
   ```
   Assert the exact picks/rejects line — with all 10 originally-undecided
   assets picked (Steps 4+6), expect `14 picks · 4 rejects`:
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
8. **Run-coverage line — six counts in total.** First, the one piece that's
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
   **Live-traced result (2026-07-28, settling the prior predicted-not-traced
   status): the line reads exactly `"0 skipped · 2 never viewed · 0 AI
   suggestions awaiting review"`** — `neverViewed = 2`, not the originally
   hoped-for 0. This is not a fixture-independent guarantee (see Step 5's
   live correction and the Sharp edges bullet for the exact mechanism):
   `smoke-5` and `smoke-6` — both already baseline-decided, both siblings of
   `smoke-4` in group2 — are never individually selected in this run's
   navigation, because Step 4's `P` on `smoke-4` (the last undecided member
   of group2) triggers auto-advance straight to the next stack's landing
   frame (`smoke-7`) rather than the flat next asset (`smoke-5`), and no
   later step re-enters group2. Per the card's own Sharp edges caveat,
   `neverViewed` nonzero here is reportable, not a fail — the Steps 1/5 walk
   was not skipped, it simply doesn't achieve full coverage the way the
   original prose assumed. `sparkleAwaiting`
   not reading exactly `0` **is** a fail for THIS fixture — this is the live
   demonstration of the kind-aware filter's FLAG-proposal half (Source's
   kind-aware contract): deciding `smoke-4`/`smoke-16` directly (Steps 4/6)
   confirmed their **flags** but never touched the two seeded
   `autopilot_proposals` rows themselves (only `beginAutopilotReview()`'s
   commit/dismiss flow does that), so both rows should still read
   `status='pending'` even though `sparkleAwaiting` correctly reads `0` —
   both seeded proposals are FLAG kind (`kind='reject'` on `smoke-4`,
   `kind='pick'` on `smoke-16`, per Pre-state's seed SQL), so this fixture
   never exercises the KEYWORD half of the contract (a pending keyword
   proposal would instead keep `sparkleAwaiting` nonzero here, by design).
   Confirm the rows are untouched live:
   ```bash
   script/vm_scenario_run.sh sql burst "SELECT count(*) FROM autopilot_proposals WHERE status='pending';"   # still 2
   ```
9. **Ceremony actions, gated correctly.** Confirm "Save Picks as Set" is
   present (real work to do: `picks=14>0`) and "Review AI Suggestions" is
   **absent** — the kind-aware filter: `sparkleAwaiting=0` since both
   proposal-bearing assets (`smoke-4`/`smoke-16`) already carry confirmed
   flags and both proposals are FLAG kind (not keyword), even with their
   proposal rows still `pending` per Step 8:
   ```bash
   script/vm_scenario_run.sh ax find --role AXButton --contains "Save Picks as Set"
   script/vm_scenario_run.sh ax find --role AXButton --contains "Review AI Suggestions"   # expect not-found
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
   is confirmed by this point (Step 7's cross-check), this also trivially
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
10. `ax wait-vended`; ⌘1 for Cull; `S` to "All frames". Confirm `smoke-0` is
    selected.
11. **Start-clamped window.** Per `CullStripWindowingTests`
    (count=24, anchor=0, limit=12 → `0..<12`): confirm `smoke-0 ·` through
    `smoke-11 ·` are each findable (`ax find --role AXButton --contains
    "smoke-N ·"`, spot-check a few, e.g. 0, 6, 11) and `smoke-12 ·` /
    `smoke-23 ·` are **not** findable. (The trailing `" ·"` in every match
    pattern is load-bearing: `smoke-1` is a literal substring of
    `smoke-10`…`smoke-19`, so a bare `--contains "smoke-1"` would false-
    positive-match ten different stops.)
12. **Centered window.** Press `Space` 10 times from `smoke-0`, polling the
    HUD filename, to reach `smoke-10`. Per the math (anchor=10, limit=12 →
    `4..<16`): confirm `smoke-4 ·` through `smoke-15 ·` findable (spot-check
    4, 10, 15) and `smoke-0 ·`/`smoke-3 ·`/`smoke-16 ·`/`smoke-23 ·` not
    findable. Confirm current-stop marking: exactly one stop's
    accessibility value contains `"Current"`
    (`ax find --role AXButton --contains "Current"`).
13. **End-clamped window.** Continue `Space` 13 more times (10→23) to reach
    `smoke-23.jpg` (the last asset), polling the filename each step. Per
    the math (anchor=23, limit=12 → `12..<24`): confirm `smoke-12 ·`
    through `smoke-23 ·` findable (spot-check 12, 18, 23) and `smoke-0 ·`
    through `smoke-11 ·` not findable.
14. **Standalone-only triple counter.** With `smoke-23` selected, confirm
    the triple counter reads `"24 of 24 · stack 24 of 24"` with **no**
    trailing `"frame"` segment (every stop here has exactly 1 member).

## Expected
- Step 3: **Fails if** the multi-frame stop's counter omits the `"frame X
  of Y"` segment.
- Step 4: **Fails if** the picks count moved before the `P` keypress, or
  didn't move by exactly one immediately after it.
- Step 5: **Fails if** the standalone stop's counter wrongly includes a
  `"frame"` segment, or if the `Space` walk skips an asset (filename
  doesn't advance one at a time in strict catalog order).
- Step 7: **Fails if** the picks/rejects text disagrees with the SQL
  cross-check, or if any asset's raw flag disagrees with its confirmed
  projection (a lingering tentative marker at the completion stage would be
  a genuine invariant violation, not a fixture quirk).
- Step 8: **Fails if** `skipped` is nonzero (no exceptions — this is a
  structural guarantee, see Source), or if `sparkleAwaiting` isn't exactly
  0 for THIS fixture (the kind-aware filter's FLAG-proposal half — see
  Source's kind-aware contract; this is a fixture fact since both seeded
  proposals are FLAG kind, not a general invariant — a fixture seeding a
  pending KEYWORD proposal on an already-decided asset should instead show
  a nonzero `sparkleAwaiting`), or if the seeded `autopilot_proposals` rows
  are no longer `pending` (would mean something silently
  auto-committed/dismissed them — the filter must not touch the proposal
  rows). `neverViewed` nonzero is reportable-not-fatal (see Sharp edges)
  unless the Step 1/5 walk was skipped, in which case investigate before
  dismissing it. **Traced live (2026-07-28): `neverViewed = 2`** (`smoke-5`,
  `smoke-6` — see Step 5's live correction and Sharp edges for the exact
  auto-advance mechanism); the Step 1/5 walk was run in full, so this is the
  settled, reportable value for this exact navigation, not an investigation
  trigger.
- Step 9: **Fails if** "Save Picks as Set" is missing despite having real
  work to do, if "Review AI Suggestions" is present (it must not be, for
  THIS fixture — both proposal-bearing assets are already user-decided and
  both proposals are FLAG kind, per the kind-aware contract), if the saved
  set's membership disagrees with the confirmed-picks list, or if the set
  name isn't `"Catalog Picks"`.
- Steps 11-13: **Fails if** any in-window stop is missing, any out-of-window
  stop is present, or the window boundaries disagree with
  `CullStripWindowing.centeredWindow`'s documented formula for that
  count/anchor/limit triple.
- Step 14: **Fails if** the standalone-only batch's triple counter ever
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
  independent of driving). **Traced live 2026-07-28: even following Steps
  1, 4, 5, 6 exactly as originally written, `neverViewed` comes back `2`,
  not `0`** — the original "Steps 1+5 make it provably 0" theory was wrong,
  not just fragile. Root cause: `recordViewed` (`AppModel.swift`'s
  `selectAssetID`, the single choke point for every navigation path) only
  marks the *one* asset actually landed on — it does not mark every member
  of the stack currently on stage. Step 4's `P` on `smoke-4` is the last
  undecided member of its 4-frame stack (group2: `smoke-3..6`), so the
  post-decision auto-advance (already documented in this card's Hard-won
  context as "on by default") does not step to the flat next asset
  (`smoke-5`) — it jumps straight to the next asset anywhere in the catalog
  that still needs a decision, landing on the next stack's (group3's)
  landing frame, `smoke-7`. `smoke-4`'s two siblings that were already
  baseline-decided before this run even started, `smoke-5` and `smoke-6`,
  are never individually selected by anything in this card's sequence, so
  they're never recorded as viewed — hence `neverViewed = 2` at completion.
  This is deterministic for this exact fixture/sequence (not flaky), but it
  is still **path-dependent** in the sense the original bullet meant: a
  driver taking a different route (e.g., deciding `smoke-4` *last* in its
  stack instead of first, or visiting `smoke-5`/`smoke-6` directly via
  stop-clicks before Step 4) would get a different, possibly-zero count. Do
  not treat a nonzero `neverViewed` as a failure on its own; do treat `2` as
  this card's own settled, reproducible value for its documented sequence,
  not a fixture quirk to explain away.
- **A plain autopilot banner may appear early**, above the stage, once
  `reconstructAutopilotStateAfterLoad()` sees this card's hand-seeded
  `autopilot_proposals` rows at launch — it doesn't distinguish a real
  Autopilot run from a seeded one. This is expected, not a bug; it doesn't
  interfere with any assertion here, and its own "Review"/"Undo all"
  buttons are `cull-017-autopilot-review.md`'s territory, not re-driven.
  **Confirmed live**: the banner read "Autopilot reviewed 2 frames · 1
  keepers · 1 rejects · dupe…" and sat above the completion stage
  throughout, with no interference with any assertion.
- **`saveCullingPicksAsSet()`'s ad-hoc branch calls `saveAndSelect(...)`
  (`AppModel.swift:5681`), which immediately applies the new set as the
  active library scope/selection** — the very next render is that new set's
  *own* freshly-recomputed completion state (a different, smaller
  population), not the original session's. Confirmed live: a screenshot
  taken right after pressing "Save Picks as Set" showed `"14 of 14 · stack
  7 of 7"`, `"14 picks · 0 rejects"`, `"1 never viewed"` — all different
  from the original 18-asset session's numbers this card actually asserts
  on (which were captured via `ax find`/SQL *before* the press, per Step
  9, and are unaffected). Capture any completion-stage screenshot for this
  card *before* pressing "Save Picks as Set", not after, or you'll
  document the wrong session's numbers.
- **The run strip's stop labels embed a capture-time string** (`"HH:MM
  AM/PM"`) computed from `Date()` at seed time, not a fixed epoch — this
  card never matches on the time portion of a label, only on the filename
  stem plus a disambiguating separator (`" ·"` or `"–"`), per Step 11's
  note.
- **This card mutates the shared local `burst` seed template** (Pre-state,
  Leg A) — see Cleanup.
- **This card does not re-derive `AutopilotProposalPlanner`'s ranking
  logic** or drive a live Evaluate+Run Autopilot pass — `app-012-
  autopilot-evaluate-commands.md` and `cull-017-autopilot-review.md` own
  that path end-to-end; this card only needs *some* pending proposal rows
  to exist, and seeds them directly for determinism (Source above).
- **The run strip's per-stop ✨ chip was removed entirely (kata #13,
  2026-07-29), resolving the disagreement this bullet used to document.**
  The chip's source set (a kind-blind, flag-blind
  `pendingSparkleAssetIDs = Set(model.pendingAutopilotProposals.map(\.assetID))`
  meaning "this frame has *some* pending AI proposal, full stop")
  routinely disagreed with the completion stage's kind-aware
  `sparkleAwaiting` count — confirmed live in this very card's Leg A
  fixture: both `smoke-3–6` and `smoke-16` kept badging `"1 suggestion"`
  on the run strip straight through to completion while the completion
  line simultaneously read `"0 AI suggestions awaiting review"`. Rather
  than reconcile the two counts, Jesse chose to drop the chip outright —
  the completion stage's `sparkleAwaiting`
  (`CullCompletionPresentation.summary`, Source above) is now the cull
  view's only ✨ surface, so this disagreement can no longer occur and
  there is nothing left for a live runner to reconcile here.

## Run status
RUN 2026-07-28 (app 878f1939) — PASS-WITH-CARD-FIXES, no app bugs. See the
dated entry at the end of this section for the full live-run summary.

Original authoring note (superseded by the live run above, kept for
history) — authored 2026-07-16, source-cited against the working tree by
directly reading `CullRunStripPresentation.swift`, `CullCompletionPresentation.swift`,
`LibraryGridView.swift` (`runStrip`/`runStripStop`/`runStripStackThumb`/
`runStripStandaloneThumb`/`runStripThumbnailFace`/`cullCompletionStage`/`cullCompletionActionButton`),
`CullFilmstripPresentation.swift`, `AppModel.swift`
(`cullingProgressSummary`, `saveCullingPicksAsSet`,
`reconstructAutopilotStateAfterLoad`), `AutopilotProposalPlanner.swift`,
`CatalogMigrations.swift`, `CatalogRepository.swift`, and
`Tests/TeststripAppTests/CullRunStripPresentationTests.swift`/
`CullCompletionTests.swift`, not carried over from any older card; pending
live VM execution per `test/scenarios/README.md`.

**Reconciled 2026-07-28 (Task 3, ✨-awaiting display-time filter)**: Leg A's
Steps 9-10 and Expected bullets updated for
`CullCompletionPresentation.summary`'s corrected `sparkleAwaiting` math —
this card's own fixture (`smoke-4`/`smoke-16` decided directly via `P` while
their seeded proposals stay `pending`) is exactly the over-report scenario
the fix targets, so the predicted `sparkleAwaiting` at completion dropped
from `2` to `0` and "Review AI Suggestions" flipped from present to absent.
Still not carried over from a live run — pending live VM execution.

**Reconciled 2026-07-28 (Finding 1, kind-aware `sparkleAwaiting`)**: Task
3's original fix (above) was kind-blind — it excluded ANY pending proposal
once its asset's flag was confirmed, including a pending KEYWORD proposal,
which has nothing to do with the flag. `summary` now takes separate
`pendingFlagProposalAssetIDs`/`pendingKeywordProposalAssetIDs` sets; the
Source's "Completion summary" bullet and Task 3 corollary were rewritten in
place for the kind-aware contract (the corollary claiming `sparkleAwaiting`
is *always* 0 at completion is now false in general — only the FLAG half of
that claim still holds structurally). This card's fixture is unaffected
(both seeded proposals are FLAG kind), so Leg A's predicted numbers (`0`
sparkleAwaiting, "Review AI Suggestions" absent) are unchanged — Steps 9-10
and their Expected bullets gained a note that this is now a fixture fact,
not a structural guarantee, plus the FLAG-kind clarification. Source's
`CullCompletionPresentation.swift` line citations re-swept to the new
tree (`38-122` → `43-133`, `:94-103` → `:103-112`, `:111,119` → `:121,130`,
`:73-82` → `:82-91`); `CullCompletionTests.swift` citations re-swept
(`:140-163` → `:147-172`, `:173-188` → `:182-198`) and the two new
kind-aware tests cited (`:241-255`, `:257-271`, `:273-290`). Still not
carried over from a live run — pending live VM execution.

**Reconciled 2026-07-28 (fix/cull-followups exhaustive-switch citation
shift, plus a new Sharp-edges bullet)**: `LoupeView.cullCompletion`'s
proposal-kind partition was rewritten from two `filter` calls to an
exhaustive `switch` over `AutopilotProposalKind`, adding 7 lines ahead of
every `LibraryGridView.swift` citation in this card — every one shifted by
exactly +7 (e.g. `runStrip`'s citation `:4496-4705` → `:4503-4712`,
`cullCompletionStage` `:3933-4013` → `:3940-4020`), re-verified by directly
reading each cited symbol. `CullCompletionPresentation.swift`,
`CullFilmstripPresentation.swift`, `AppModel.swift`, and
`CullRunStripPresentation.swift` citations are untouched (none of those
files changed). Also added a Sharp-edges bullet documenting that the run
strip's ✨ chip (kind-blind, flag-blind) and the completion stage's
`sparkleAwaiting` (kind-aware) disagree by design on this card's own
fixture — not a new finding, just making explicit something this card's
Leg A already exercises without calling it out. No other prose or behavior
claims changed. Still NOT RUN.

**LIVE RUN — 2026-07-28, app `878f1939`, Tart VM `teststrip-e2e`: PASS-WITH-
CARD-FIXES, no app bugs.** Both legs driven end-to-end. Leg A (`burst`,
18 assets, hand-seeded tentative flags + `autopilot_proposals` rows per
Pre-state): Steps 1-5, 7-10 all passed exactly as documented (seed landed;
confirmed-only pick/reject split 4/4 with matching HUD; ✨ chips landed on
exactly `smoke-3–6` and `smoke-16` and no other stop; multi-frame triple
counter `"1 of 18 · stack 1 of 8 · frame 1 of 3"`; the isolated-progress
check moved the HUD from `4 picks, 4 rejects` to `5 picks, 4 rejects` by
exactly one, only after `P`; the 9-asset undecided sweep landed on `14
picks · 4 rejects` matching the SQL cross-check exactly, two rows only,
no `NULL`/tentative survivors; `0 skipped`/`0 sparkleAwaiting`/2 pending
`autopilot_proposals` rows untouched; "Save Picks as Set" present, "Review
AI Suggestions" absent, and the saved `"Catalog Picks"` set's 14-id
membership matched the confirmed-picks list exactly). Two things did not
match the card's predictions and are now fixed in place (not app bugs —
both traced to the app doing exactly what its own source says, the card's
prior text being wrong): (1) Step 6's `"stack 6 of 8"` was an off-by-one —
live is `"stack 7 of 8"` (`smoke-16` is the 7th of 8 stops in capture
order). (2) The card's central load-bearing claim that Steps 1+5+6+7
"means every one of the 18 assets has been individually selected" is false
in general and was false in this exact live run: `neverViewed` traced to
`2`, not `0`. Root cause fully traced to source: `AppModel.swift`'s
`selectAssetID` (`recordViewed`'s only call site besides session-start) is
a single-asset choke point, and Step 5's `P` decision on `smoke-4` (the
last undecided member of its own 4-frame stack) triggers the
already-documented auto-advance, which — with no undecided sibling left in
the current stack — jumps straight to the *next stack's* landing frame
(`smoke-7`) rather than the flat next asset (`smoke-5`). `smoke-4`'s two
already-baseline-decided siblings, `smoke-5`/`smoke-6`, are consequently
never individually selected by anything else in the documented sequence,
so `neverViewed = 2` at completion — settling the card's own
predicted-not-traced flag with a traced, reproducible value (see Step 6,
Step 9, and the rewritten Sharp edges bullet for the full mechanism and
citations). Leg B (`smoke`, 24 standalone assets, windowing): all of Steps
11-15 passed exactly as written with zero card fixes needed — start-
clamped (`0..<12`), centered (`4..<16`, single `"Current"` match), and
end-clamped (`12..<24`) windows all matched `CullStripWindowing`'s
documented formula exactly on live spot-checks, and the standalone-only
triple counter read exactly `"24 of 24 · stack 24 of 24"` with no trailing
`"frame"` segment. One incidental discovery worth a permanent Sharp-edges
entry (not a bug): `saveCullingPicksAsSet()`'s ad-hoc branch calls
`saveAndSelect(...)`, which immediately swaps the active scope to the new
set, so any post-press screenshot shows that set's own completion numbers,
not the original session's — confirmed live via a screenshot taken just
after the press. Card commit: see the commit introducing this Run status
update, branch `fix/scenario-card-runs`.

**Cleanup note**: the local `burst` seed template
(`$TMPDIR/teststrip-vm-seeds/burst/Teststrip`) and the VM's matching
`isolated/burst/Teststrip` remain in the Leg-A-mutated (tentative-flag-
seeded) state after this run — the card's own Cleanup step
(`rm -rf ".../burst/Teststrip"`) was blocked by this runner's sandbox
policy requiring explicit human authorization for `rm -rf`, and was not
force-run. Any later card in this VM session that needs a pristine `burst`
fixture must reset this local template (and re-push it, or re-run
`sync burst`) before relying on it.

**Reconciled 2026-07-29 (kata #13, run-strip chip removed)**: the run
strip's per-stop ✨ suggestion chip is gone from the app —
`CullRunStripPresentation.Stop.sparkleCount` and the `pendingSparkleAssetIDs`
parameter to `stops(...)` were deleted, along with the sparkle badge
rendering in `LibraryGridView`'s `runStripThumbnailFace` (and the
`sparkleShowsCount` parameter that split it into a numeric form for stacks
vs. a bare icon for standalones) and the `"N suggestion(s)"` segment of
`runStripStopAccessibilityValue`. This was a deliberate removal, not a
regression: the chip was kind-blind and flag-blind and routinely
disagreed with the completion stage's kind-aware `sparkleAwaiting` count
(this card's own Leg A fixture demonstrated the disagreement live, per the
prior Sharp-edges bullet), and Jesse chose dropping the chip over
reconciling the two counts — `sparkleAwaiting` is now the cull view's only
✨ surface. `CullCompletionPresentation`'s math and the
`autopilot_proposals`/review-queue persistence are untouched by this
change.

Card impact: this card's own Leg A Step 3 (the chip verification step)
is gone, so every later step renumbered down by one throughout Source,
Steps, Expected, and Sharp edges above (old Step 4 → new Step 3, … old
Step 10 → new Step 9; Leg B's old Steps 11-15 → new Steps 10-14); the
Source "Stops" and "Rendering" bullets and their `CullRunStripPresentation
.swift`/`LibraryGridView.swift`/`CullRunStripPresentationTests.swift`
citations were re-swept against the working tree at commit `df087188`;
the prior Sharp-edges bullet documenting the chip/completion disagreement
was replaced with a short note citing this decision, since the
disagreement can no longer occur. The Run status entries above this note
(the dated RUN summary, the Original authoring note, the three earlier
Reconciled notes, the detailed LIVE RUN paragraph, and its Cleanup note)
describe the app and this card's own step numbering as they stood on
2026-07-28, **before** this removal — they are kept unchanged for
history, per this card's own established convention, and their
step-number and chip mentions should be read against that older layout,
not the current one above.
