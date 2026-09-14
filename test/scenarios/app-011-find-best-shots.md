# app-011-find-best-shots: Find Best Shots routes to Potential Picks, Picks, or a plain-language status

**What this covers**: Jesse's one-button "show me the keepers". Inventory
item 38: `Culling ▸ Find Best Shots` (⇧⌘B) is read-only and routes via
`FindBestShotsRouter.plan` (`Sources/TeststripApp/AppModel.swift:697-725`):
(a) potential picks exist → Potential Picks queue; (b) none but
committed picks exist → Picks queue; (c) nothing ranks and nothing left to
evaluate → status message "These look too distinct to auto-rank — rate a few
to rank" — never a bare zero. When unevaluated frames remain it also triggers
a scope evaluation and lands on Potential Picks to fill in. Gated by
`canFindBestShots` (catalog non-nil, assets non-empty).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Keep the app warm during the evaluation wait (re-assert frontmost each poll).

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 (Grid lens).
2. **Read-only baseline.** Snapshot the catalog's user-visible metadata:
   ```bash
   sqlite3 "$DB" ".dump assets" | shasum > /tmp/before.sha
   ```
3. **Outcome A/its evaluate-first variant.** Press ⇧⌘B on the fresh smoke
   seed (frames likely unevaluated). Expect a route to **Potential Picks**
   (breadcrumb/queue header) with an evaluation pass visibly running via the
   Activity item, the queue filling as the worker reports. Wait (warm!) for
   the evaluation to finish; record the final queue count and cross-check:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"   # grew from 0
   ```
4. **Outcome B (Picks).** Commit at least one pick (press P on a frame in
   Cull — a user gesture, allowed to write), then empty the potential-picks
   queue if needed (decide the proposals). Press ⇧⌘B again: with no
   potential picks but ≥1 pick, it must land on the **Picks** queue.
5. **Outcome C (nothing ranked).** Hard to force on a ranked seed; run this
   branch on an `--isolated` + import of 2-3 deliberately dissimilar photos
   (or a smoke state where all proposals were rejected and no picks exist).
   Press ⇧⌘B with the scope fully evaluated and nothing ranking: assert the
   status line "These look too distinct to auto-rank — rate a few to rank"
   appears and the view does NOT navigate to an empty queue.
6. **Read-only invariant.** Re-hash as in step 2 after step 3's route (before
   step 4's deliberate pick): apart from evaluation-signal/queue tables, no
   user metadata changed — `metadata_json` diffs are a failure. (Compare
   with `sqlite3 "$DB" "SELECT id, metadata_json FROM assets"` before/after
   rather than the whole-dump hash if evaluation rows pollute it.)

## Expected
- Step 3: routes to Potential Picks and triggers evaluation exactly when
  unevaluated frames + a live worker exist. **Fails if** it lands on an
  empty view with no activity, or shows a bare "0".
- Step 4: routes to Picks when only picks exist. **Fails if** it re-routes
  to an empty Potential Picks.
- Step 5: the exact plain-language string renders as a status, no
  navigation. **Fails if** any zero-count dead end appears.
- Step 6: no `metadata_json` changed by any ⇧⌘B press. **Fails if** the
  "reads only; writes nothing" contract broke.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Which of the three outcomes fires depends on live queue counts — assert
  the *mapping* (state → route), not a fixed sequence. Before each press,
  capture the app's own counts (review-queue badge numbers or the catalog's
  proposal/pick state) so the expected route is derivable, then check it.
- Outcome C needs a scope that genuinely evaluates to nothing ranked;
  document the fixture you used. If you cannot produce it, mark the branch
  NOT-RUN explicitly — do not substitute a weaker assertion.
- Evaluation needs the worker and cached previews (`canRequestCurrentScope…`);
  on a cold catalog wait for preview generation first or the evaluate-first
  branch silently degrades to outcome C.

## Run status
**Reviewed 2026-08-06 (Task 9, SP-D0 ghost derivation sweep) — no rename
applied, deviating from the task brief.** The brief called for this card's
three uses of "proposals" (Steps 4/5, Sharp edges) to become "ghosts", on
the assumption they referred to autopilot's proposal mechanism. Source
check: `SmartCollection.potentialPicks.query` compiles to `SetQuery(predicates:
[.likelyPick])` (`Sources/TeststripApp/AppModel.swift:709-714`)
— a quality-score threshold query (`json_extract(metadata_json,'$.flag')
IS NULL AND EXISTS (... evaluation_signals ...)`) with no reference to
`AutopilotProposal`, `autopilot_proposals`, or `AutopilotGhost` anywhere.
This card's "proposals" is generic English for "the candidates sitting in
the Potential Picks queue," an entirely different, unrelated ranking
feature — renaming it to "ghosts" would assert a relationship to the
autopilot mechanism that does not exist in source. Left unchanged; flagging
for Jesse rather than silently complying with an instruction the source
doesn't support. Otherwise no `autopilot_proposals` table reference exists
anywhere in this card. Needs a fresh VM run (unrelated to this review).

**Reconciled 2026-08-09 (Task 13, unified-shell preamble sweep)**: Step 1's
preamble pressed ⌘2 for "Library" — the two-workspace `Workspace` enum's ⌘2;
that enum is gone and ⌘2 now selects the Grid lens (`LibraryLens.
keyEquivalent`, `LibraryLens.swift:44-51`). Retitled to "Grid lens." Preamble
only; the assertions were not affected — `FindBestShotsRouter.plan` and the
three outcomes it routes to don't care which lens was active before ⇧⌘B was
pressed. Supersedes prior status: the 2026-08-06 review above covered
terminology only and is still valid on its own terms, but neither it nor any
earlier evidence was gathered against a build where ⌘2 meant anything other
than the deleted Library workspace — needs a fresh VM run.

## Run status
**LIVE RUN 2026-09-14, Tart VM `teststrip-e2e`** (`script/vm_scenario_run.sh`): `smoke` run
dir `smoke-1789375314` (Outcomes B + step 6), `empty` run dir `empty-1789375380` with 3 photos
imported from `/tmp/imp2` (Outcomes A + C). **Steps 2, 3(A/B), 4, 5 PASS; step 6 FAILS as written**
(see below) — recorded `Tested-Fail` / Documentation in the ledger.

All three router outcomes were reached live (the mapping was asserted against the app's own counts,
not a fixed sequence, per the Sharp edges):

- **Step 2 (read-only baseline)**: captured `metadata_json` shasum `e5909119…` and
  `evaluation_signals` = 0.
- **Step 3, Outcome B (Picks)**: on fresh `smoke` (potentialPicks = 0, picks = 6, needsEvaluation =
  24) `⇧⌘B` routed to **`Picks, 6 photos · Pick`** and the Activity button went to
  `help="Activity - working"` — i.e. evaluation was triggered. `evaluation_signals` grew 0 → **191**.
  (The card's Step 3 expectation of Potential Picks does not hold on `smoke`: potentialPicks is 0 —
  max `aesthetics` 0.536 < 0.65, max `focus` 0.188 < 0.8, no `faceQuality` — so the router's
  `pickCount > 0` branch fires. This is the documented smoke fixture gap, not a defect.)
- **Step 3/Outcome A (Potential Picks) — reached live** on the `empty`+import catalog: after
  importing 3 real portraits, 1 asset had a strong read (`faceQuality` 0.566 ≥ 0.45). `⇧⌘B` routed
  to **`Potential Picks, 1 photo · Potential Picks`** and triggered evaluation — the evaluate-first
  branch, confirmed by the sidebar `Potential Picks` row count = 1 and the router precedence.
- **Step 5, Outcome C (nothing ranked) — reached live**: after the scope was fully evaluated
  (needsEvaluation = 0) and the sole potential pick was rejected (picks = 0), `⇧⌘B` rendered the exact
  footer status **"These look too distinct to auto-rank — rate a few to rank"** and did **not**
  navigate (scope stayed put). No bare "0" dead-end.

**Step 6 (read-only invariant) — FAILS as written.** Baseline `SELECT id, metadata_json` shasum
`e5909119…`; after only two `⇧⌘B` presses it is `b6175fc0…`. The delta is *not* flags/ratings: diffing
the run catalog against the pristine `isolated/smoke` seed shows every `flag`, `rating`, `caption`,
and `colorLabel` row unchanged, but 20/24 assets gained `aiUnconfirmedKeywords` and had AI
object-label keywords **appended to the confirmed `keywords` array** (e.g. `smoke-2`:
`["smoke","batch-0"]` → `["smoke","batch-0","document","sticky_note"]`). Root cause is by design, not a
`⇧⌘B` bug: `⇧⌘B` triggers a scope evaluation, and each finished asset flows through
`promoteEvaluationResults` → `promoteMetadataLabels` (`AppModel.swift:11678`/`:11683` (caller) → `promoteMetadataLabels` `:9401`), which
auto-applies machine labels with provenance (`metadata.keywords.append(label)` +
`aiUnconfirmedKeywords.insert(label)`, `:9410-9421`; caption via `aiUnconfirmedFields.caption`).
This is the same auto-apply-with-provenance model the import/autopilot cards document. So the card's
literal "**metadata_json diffs are a failure**" is stale: the *user-visible* contract still holds
(no `flag`/`rating`/`colorLabel`/`caption` changes; `keywords` minus `aiUnconfirmedKeywords` is
byte-identical to the seed), but `metadata_json` is not literally untouched because provisional AI
labels are promoted on evaluation completion. Suggested card fix: assert no change to
`flag`/`rating`/`colorLabel`/`caption` and to the **confirmed** keyword projection
(`keywords` minus `aiUnconfirmedKeywords`), rather than a whole-`metadata_json` hash.

**Separate observed defect (not asserted by this card; reproduced twice)**: while the
`Potential Picks` filter is active (set by `⇧⌘B`), rejecting the displayed asset in place (`X`) writes
`flag=reject` to the catalog but the queue does **not** drop it — the grid keeps rendering
`Potential Picks, 1 photo` with the now-rejected tile, while the sidebar's `Potential Picks` count
correctly goes to 0 (the row disappears). Repro: clear the flag (`U`) → `⇧⌘B` → `Potential Picks, 1
photo` → `X` → catalog `flag=reject` yet the view still shows `Potential Picks, 1 photo` and the tile
(`Selected, Flagged Reject`), with the `Remove filter Potential Picks` chip still present. This is the
"count and list drift apart" class the README warns about; it needs its own card (the app's
`potentialPicksFilter` result set is not re-queried after an in-place metadata write).

**Stale citations**: `FindBestShotsRouter.plan` `AppModel.swift:697-725` → `:777-806`;
`SmartCollection.potentialPicks.query` `:709-714` → `:744`; `canFindBestShots` `:10942`,
`findBestShots()` call site `:10924-10940`.
