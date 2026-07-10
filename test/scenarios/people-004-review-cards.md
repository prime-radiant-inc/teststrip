# people-004-review-cards: "Unnamed faces" / "Face quality checks" review cards route and gate correctly

**What this covers**: the two `PeopleReviewCard`s in the People canvas'
review strip — "Unnamed faces" and "Face quality checks" — each carry a
count matching catalog ground truth, route to the correct queue target when
tapped, and are disabled with an explanatory `AXHelp` string when their
backing count is zero (`PeoplePresentation.reviewCards`,
`Sources/TeststripApp/PeopleView.swift:665-690`).

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
   `PeoplePresentation.init:554`), and "Face quality checks" only appears when
   `FQ > 0`.
2. `script/ax_drive.sh wait-vended Teststrip`; press ⌘3 for People.
3. `script/ax_drive.sh find --role AXStaticText --contains "Unnamed faces"`
   and `--contains "Face quality checks"` — assert each card's presence
   matches step 1's gating (present iff its backing count is `> 0`).
4. For each present card, read its count text (`AXStaticText` sibling) and
   compare to ground truth: "Unnamed faces" shows
   `Self.photoCountDescription(photosWithDetectedFaces)` (e.g. "N photos");
   "Face quality checks" shows `photoCountDescription(FQ)`.
5. `script/ax_drive.sh press --role AXButton --help "Review faces"` (or the
   card's button, matched by its `suggestedActionTitle` help text) — assert
   the app navigates via `selectSidebarTarget` to the card's `target`:
   "Unnamed faces" routes to `.reviewQueue(.facesFound)` when
   `faceSignalKind == .faceCount`, else `.evaluationKind(.faceCount)`; "Face
   quality checks" routes to `.evaluationKind(.faceQuality)`
   (`PeopleView.swift:667-687`). Confirm post-navigation the Library/queue
   view is scoped to the matching evaluation kind or queue.
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
   *all* review cards, per `PeopleView.swift:182-183` — not a per-card
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
routing confirmed by static read of `Sources/TeststripApp/PeopleView.swift:665-690`
(`reviewCards`) and `:182-183`/`:496-503` (disabled state, tap handler,
`selectSidebarTarget`). Needs a human-present re-run. All SQL in this card
was run headlessly against a seeded --faces catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift).
