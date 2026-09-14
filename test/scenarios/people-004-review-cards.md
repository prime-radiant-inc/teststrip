# people-004-review-cards: "Unnamed faces" / "Face quality checks" review cards route and gate correctly

**What this covers**: the two `PeopleReviewCard`s in the People canvas'
review strip — "Unnamed faces" and "Face quality checks" — each carry a
count matching catalog ground truth, route to the correct queue target when
tapped, and are disabled with an explanatory `AXHelp` string when their
backing count is zero (`PeoplePresentation.reviewCards`,
`Sources/TeststripApp/PeopleView.swift:762-789`).

## Pre-state
```bash
./script/download_face_model.sh
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. **Record ground truth** after face evaluation drains:
   ```bash
   sqlite3 "$DB" "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE kind='faceCount';"
   sqlite3 "$DB" "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE kind='faceQuality';"
   ```
   Call these `FC` and `FQ`. Per `reviewCards`, "Unnamed faces" only appears
   when `photosWithDetectedFaces > 0` (`= FC` if `FC > 0` else `FQ`, per
   `PeopleView.swift:618`), and "Face quality checks" only appears when
   `FQ > 0`.
2. `script/ax_drive.sh wait-vended Teststrip`; press ⌘6 for the People lens
   (People is one of the six top-level `LibraryLens` cases, reached directly
   by ⌘6 or the toolbar lens switcher's "People" segment — not ⌘3, and not a
   Library sub-view toggle).
3. `script/ax_drive.sh find --role AXStaticText --contains "Unnamed faces"`
   and `--contains "Face quality checks"` — assert each card's presence
   matches step 1's gating (present iff its backing count is `> 0`).
4. For each present card, read its count text (`AXStaticText` sibling) and
   compare to ground truth: "Unnamed faces" shows
   `Self.photoCountDescription(photosWithDetectedFaces)` (e.g. "N photos");
   "Face quality checks" shows `photoCountDescription(FQ)`.
5. `script/ax_drive.sh press --role AXButton --help "Review faces"` (or the
   card's button, matched by its `suggestedActionTitle` help text) — assert
   the app navigates via `applyConfirmAction(card.reviewAction)`
   (`PeopleView.swift:190-196`) → `PeopleQueueConfirmAction.selectReview`
   (`PeopleQueuePresentation.swift:108`) → `model.selectPeopleSignal(_:)`
   (`AppModel.swift:12068`), which appends `.evaluationKind(kind)` to the
   current People scope predicates, calls `selectSource(.search(...))`, then
   `selectLens(.grid)`. Each card's `filterKind` (`PeopleView.swift:767-789`)
   is `faceSignalKind` for "Unnamed faces" and `.faceQuality` for "Face
   quality checks". Confirm post-navigation the grid is scoped to that
   evaluation kind.
6. **Disabled/empty-state check.** This fixture is expected to produce both
   `FC > 0` and `FQ > 0` (both providers run over the same 11-photo corpus),
   so neither card is reachable in a disabled state from `--faces` alone. To
   exercise the disabled path, use a corpus where only one kind has signals
   (e.g. run only `apple-vision` — which yields `faceCount` — never
   `core-image-faces`/`faceQuality`, by scanning with `Scan for Faces` alone
   on a fresh `--isolated` catalog with zero prior evaluation). If reachable,
   assert the card is grayed (`isActionEnabled == false` → title uses
   `.secondary` foreground, no trailing arrow glyph) and its `AXHelp` reads
   "Face naming is not built yet" (the generic disabled string applied to
   *all* review cards, per `PeopleView.swift:195-197` (disabled/help) and
   `PeopleView.swift:534-543` (title/arrow) — not a per-card
   message).

## Expected
- Step 3: card presence exactly matches `FC > 0` / `FQ > 0`. **Fails if** a
  card renders with a zero backing count, or is missing despite a positive
  count.
- Step 4: count text matches ground truth exactly (singular "1 photo" vs
  plural "N photos"). **Fails if** it diverges from the `evaluation_signals`
  distinct-asset count.
- Step 5: tapping routes to the documented target and the resulting scope
  contains exactly the assets carrying that evaluation kind's signal.
  **Fails if** the tap navigates to the wrong queue/kind or a no-op.
- Step 6: disabled card shows `AXHelp == "Face naming is not built yet"` and
  is not AXPress-able (or AXPress is a no-op with no navigation). **Fails if**
  the help text is missing/wrong, or a disabled card is still actionable.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The disabled state's help string ("Face naming is not built yet") reads as
  a leftover from an earlier feature-flag era — it's generic across both
  cards and doesn't actually describe *why* the card is disabled (zero
  signals, not "not built"). Worth a product follow-up, not a scenario bug.
- `--faces` seeds both providers by default (`AppModel.defaultEvaluationProviderNames`
  includes `apple-vision` and `core-image-faces`), so both review cards are
  expected to be simultaneously populated in this fixture — the "only one
  card populated" disabled-state probe needs a more surgical single-provider
  scan, documented above as a fallback, not guaranteed runnable without a
  live console.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Card gating and
routing confirmed by static read of `Sources/TeststripApp/PeopleView.swift:765-790`
(`reviewCards`) and `:182-183`/`:496-503` (disabled state, tap handler,
`selectSidebarTarget`). Needs a human-present re-run. All SQL in this card
was run headlessly against a seeded --faces catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift).

**Reconciled 2026-08-09 (Task 13, unified-shell survivor sweep)**: Step 2's
preamble described an intermediate, pre-unified-shell era where People had
already left the top-level ⌘3 workspace slot but was reached as a Library
sub-view toggle rather than its own key — fixed to ⌘6 (or the toolbar lens
switcher's "People" segment). Also, `selectSidebarTarget` no longer exists
anywhere in `Sources/` (`grep -rn "selectSidebarTarget" Sources/` → nothing)
— and neither does the `selectPeopleReviewCard` handler this note first
cited (corrected 2026-09-13; `grep -rn "selectPeopleReviewCard" Sources/` →
nothing). The review card is now a `Button` whose action calls
`applyConfirmAction(card.reviewAction)` (`PeopleView.swift:190-196`);
`applyConfirmAction(_:)` (`PeopleView.swift:98`) routes
`.selectReview(let kind)` → `try model.selectPeopleSignal(kind)`
(`AppModel.swift:12068`), from `PeopleReviewCard.reviewAction`
(`PeopleView.swift:902`, `filterKind.map(PeopleQueueConfirmAction.selectReview)
?? .none`; `PeopleQueuePresentation.swift:108`). There is no
`selectSidebarTarget`, `selectPeopleReviewCard`, or `model.selectSource(_:)`
in this path. Rewrote Step 5 accordingly. Supersedes prior status: no prior
run evidence exists to
invalidate (still BLOCKED-CONSOLE); the citation/routing-mechanism fixes
only affect what a future runner would read as ground truth.


## Run status — 2026-09-14, Tart VM `teststrip-e2e` (batch 5): VERIFIED

`launch faces` run dir `faces-1789371392`, Scan for Faces drained
(FC=11, FQ=11). Steps 1-5 PASS; step 6 NOT exercised (see below).

- Step 3: both review cards present, matching `FC > 0` / `FQ > 0`.
- Step 4: each card's count text is `11 photos`, equal to its kind's
  distinct-asset count.
- Step 5: pressing the card (`--help "Review faces"`) selected the **Grid**
  lens with a `Remove filter Faces Found` chip; pressing
  `--help "Review quality"` added `Remove filter Face Quality`.

### Corrections found while driving

- **Step 3's role is stale.** The cards are not `AXStaticText`; each is an
  `AXButton` whose child texts are concatenated into one label:
  `"11 photos, Review faces, Unnamed faces"` and
  `"11 photos, Review quality, Face quality checks"`. The card's
  `--role AXStaticText --contains …` fails (exit 1); use role-less
  `--contains`.
- **Step 6's fallback is wrong as written.** It says a `Scan for Faces`-only
  run "yields `faceCount` — never `faceQuality`". Live, `Scan for Faces`
  (apple-vision only) emits `faceCount`, `faceQuality`, `object`, `ocrText`
  *and* `visualSimilarity` (`GROUP BY kind, provider` → all `apple-vision`),
  so the single-populated-card disabled state is not producible that way.
  Step 6 remains unexercised (the card itself calls it a fallback).
- Routing source citations: `reviewCards` is now `PeopleView.swift:799-822`
  (not `:762-789`); `selectPeopleSignal` is `AppModel.swift:12210-12216`.
- Observation: `selectPeopleSignal` appends to the current People-lens source
  scope, so driving both cards back-to-back stacks `Faces Found` +
  `Face Quality`. Harmless here (all 11 assets carry both signals) but the
  step-5 "exactly that kind's assets" assertion is non-discriminating on this
  fixture.
