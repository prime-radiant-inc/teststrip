# people-009-scan: "Scan for Faces" is menu-only, gated on worker+catalog+cached previews, and surfaces in Activity

**What this covers**: the People workspace's face-scan trigger lives only in
the **People ▸ Scan for Faces** menu item (no canvas button — deliberately
removed so the review queue owns the Return keystroke, per the comment at
`Sources/TeststripApp/main.swift:335-339`); the menu item is disabled unless
`canRequestPeopleFaceScan` (== `canRequestCurrentScopeAssetEvaluations`) is
true; triggering it calls `requestCurrentScopeAssetEvaluations(providers:
["apple-vision"])`, and the resulting work is visible via the Activity
icon/queue and new `evaluation_signals`/`face_observations` rows.

## Pre-state
```bash
./script/download_face_model.sh
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. **No canvas button.** With People open (⌘3), scan the AX tree for any
   `AXButton` whose title/help mentions "Scan" — assert none exists in the
   canvas (only the review-strip's static `scanAction.detail` caption text
   remains, per the comment at `PeopleView.swift:147-156`: the trigger moved
   to the menu in Task 21).
2. **Menu presence and gating.** Open the **People** menu
   (`script/ax_drive.sh find --role AXMenuItem --label "Scan for Faces"`)
   before any evaluation has run (fresh `--faces` launch, before cached
   previews exist for the current scope — or immediately after launch while
   previews are still generating). If reachable in that window, assert the
   item is `AXDisabled` per `canRequestPeopleFaceScan`
   (`AppModel.swift:2635-2637`) delegating to
   `canRequestCurrentScopeAssetEvaluations` (`AppModel.swift:2626-2633`),
   which requires **all three**: `workerSupervisor != nil` (worker
   supervised/alive), `catalog != nil`, and at least one asset in the current
   scope with a cached preview (`currentScopeCachedPreviewAssetIDs(...,
   limit: 1)` non-empty).
3. **Wait for previews to cache**, then re-check the menu item — it should
   now be enabled (`AXEnabled`, not grayed).
4. **Record ground truth before the scan**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals WHERE kind='faceCount';"  # E0
   sqlite3 "$DB" "SELECT count(*) FROM face_observations;"                           # F0
   sqlite3 "$DB" "SELECT count(*) FROM work_sessions;"                               # W0
   ```
5. Press **People ▸ Scan for Faces**
   (`script/ax_drive.sh press --role AXMenuItem --label "Scan for Faces"`).
6. **Activity surfaces the work.** Immediately after, check the toolbar
   Activity icon for a working/busy state (mirror
   `activity-icon-states.md`'s pattern — badge or spinner appears while the
   evaluation batch is in flight).
7. **Wait for the pass to drain** (poll `evaluation_signals`/`face_observations`
   growth, re-asserting frontmost per the idle-wedge warning in
   `test/scenarios/README.md`).
8. **Record ground truth after**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals WHERE kind='faceCount';"  # E1
   sqlite3 "$DB" "SELECT count(*) FROM face_observations;"                           # F1
   sqlite3 "$DB" "SELECT provider, count(*) FROM evaluation_signals WHERE kind='faceCount' GROUP BY provider;"
   ```

## Expected
- Step 1: zero scan buttons in the People canvas itself. **Fails if** a
  clickable scan control exists outside the menu bar.
- Step 2: item disabled when the worker/catalog/cached-preview precondition
  isn't met. **Fails if** the item is enabled with no cached previews in
  scope, or if it's reachable/pressable before the worker supervisor exists.
- Step 3: item enabled once a cached preview exists in scope. **Fails if** it
  stays disabled despite satisfied preconditions.
- Step 5-6: pressing the menu item visibly starts work (Activity state
  changes). **Fails if** nothing observably happens.
- Step 8: `E1 > E0` and/or `F1 > F0` (per-provider — confirm the `provider`
  column includes `apple-vision`, matching `requestPeopleFaceScan`'s
  hardcoded `providers: ["apple-vision"]`, `AppModel.swift:7969-7971`), and
  the provider breakdown shows only `apple-vision` grew from this action
  (other providers' evaluation counts unchanged since step 4, since the scan
  intentionally scopes to that one provider). **Fails if** counts don't grow,
  or if other providers' signals also grew from this specific action (scope
  leak).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `canRequestPeopleFaceScan` is a pure delegate to
  `canRequestCurrentScopeAssetEvaluations` — it does not check whether the
  current scope actually has any *unscanned* assets, so the menu item stays
  enabled even after every asset in scope has already been scanned (a no-op
  re-scan). Not a bug per the current spec, but worth noting if step 8's
  counts look flat because the fixture was already fully scanned by an
  earlier automatic pass — check `E0`/`F0` aren't already saturated before
  concluding the scan failed.
- `work_sessions` (`W0` in step 4) may or may not grow from this action —
  `requestCurrentScopeAssetEvaluations` calls `requestEvaluation` per asset
  per provider directly; whether that creates a `work_sessions` row depends
  on internals not traced in this read. Treat the `evaluation_signals`/
  `face_observations` counts as the authoritative assertion; use
  `work_sessions` only as a secondary signal if it does grow.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Menu-only placement
confirmed by static read of `Sources/TeststripApp/main.swift:335-352`
(`PeopleCommands`); gating confirmed by
`Sources/TeststripApp/AppModel.swift:2626-2637`
(`canRequestCurrentScopeAssetEvaluations`, `canRequestPeopleFaceScan`); the
apple-vision-only provider scoping confirmed by `AppModel.swift:7969-7971`
(`requestPeopleFaceScan`). Needs a human-present re-run. All SQL in this card
was run headlessly against a seeded --faces catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift).
