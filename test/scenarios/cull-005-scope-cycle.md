# cull-005-scope-cycle: S cycles Unrated→Picks→Rejects→All, narrowing the grid each time, with nearest-match reselection

**What this covers**: as a photographer working a shoot, I want `S` to cycle
the Cull loupe/grid through the four review scopes — Unrated, Picks,
Rejects, All — narrowing what I see each time, and when the currently-
focused photo falls outside the new scope, land me on the nearest in-scope
photo rather than a blank loupe. Covers:
- Cycle order and matching predicate: `CullScope`
  (`Sources/TeststripApp/AppModel.swift:270-299`) — `next()` walks
  `CaseIterable`'s declared order `unrated, picks, rejects, all` and wraps
  (`:276-280`); `matches(_:)` (`:282-289`) — `.unrated` matches `flag ==
  nil`, `.picks` matches `flag == .pick`, `.rejects` matches `flag ==
  .reject`, `.all` matches everything unconditionally.
- The `S` keystroke: `CullingShortcut.init(key:)` maps `"s"` to `.cycleScope`
  (`:257`), dispatched to `cycleCullScope()` (`:5449-5450`, `:5460-5467`),
  which advances `cullScope` and immediately reselects via
  `CullScopeOrdering.selectionAfterScopeChange`.
- Nearest-match reselection: `CullScopeOrdering.selectionAfterScopeChange`
  (`:315-342`) — if the current selection still matches the new scope, keep
  it; otherwise walk forward and backward from its old index in lockstep
  (`forward`/`backward` incrementing together, `:329-339`) and land on
  whichever in-scope asset is found first; if none exists in either
  direction, return `nil` (empty scope, no crash).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Fallback: `script/vm_scenario_run.sh setup && sync smoke && launch smoke`,
then `vm_scenario_run.sh ax ...` / `sql smoke ...`.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull, landing in
   the loupe. Confirm the scope chip initially reads "All" — `AppModel`'s
   `cullScope` property defaults to `.all`, not the enum's first
   `CaseIterable` case (`AppModel.swift:1846`: `public private(set) var
   cullScope: CullScope = .all`). So the very first `S` press cycles
   `All -> Unrated`, not `Unrated -> Picks`.
2. Ground truth per scope, from `--smoke`'s baseline (11/24 flagged, split
   unknown between pick/reject — determine the actual split live):
   ```bash
   sqlite3 "$DB" "SELECT
     (SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL) AS unrated,
     (SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick') AS picks,
     (SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject') AS rejects,
     (SELECT count(*) FROM assets) AS all_count;"
   ```
   Record these four counts (`N_UNRATED`, `N_PICKS`, `N_REJECTS`, `N_ALL` —
   `N_ALL` should be 24).
3. Note the currently-selected asset's flag state (`SELECTED0`).
4. Press `S`. Assert the scope chip now reads "Unrated"
   (`script/ax_drive.sh find --contains "Unrated"`) and the filmstrip/grid's
   visible frame count matches `N_UNRATED` (via the filmstrip position text
   `"frame X / N_UNRATED"` from `CullFilmstripPresentation.positionText`, or
   by counting visible tiles). Because the starting scope is `.all`, every
   asset (including `SELECTED0`) was in scope beforehand; if `SELECTED0`'s
   flag was NULL, assert selection stayed on it, otherwise assert
   reselection landed on some unrated asset (confirm its flag via SQL,
   don't assume a specific id).
5. Press `S` again. Assert the chip reads "Picks", the visible count
   matches `N_PICKS`, and reselection (if needed) landed on a `pick`-
   flagged asset.
6. Press `S` again. Assert the chip reads "Rejects", the visible count
   matches `N_REJECTS`, and reselection (if needed) landed on a `reject`-
   flagged asset.
7. Press `S` a fourth time. Assert the chip wraps back to "All" and the
   visible count is 24 (`N_ALL`). Since `.all` matches everything, the
   step-6 selection (a `reject`-flagged asset) must still be selected — no
   reselection should occur here, unlike steps 4-6.
8. Repeat step 4's `S` press once more (fifth total) and assert the chip and
   visible set match step 4 exactly — the cycle is a clean loop with no
   drift.

## Expected
- Steps 4-7: scope chip text cycles exactly `All -> Unrated -> Picks ->
  Rejects -> All`, and each step's visible/filmstrip count matches the SQL
  ground truth recorded in step 2. **Fails if** the order differs, or if a
  visible count is off by even one from the corresponding SQL count (scope
  filtering is exact, not approximate).
- Steps 4/5/6: when the focused asset falls out of scope, reselection lands
  on an in-scope asset — never a blank loupe, never an out-of-scope asset
  displayed, never a crash/error alert. **Fails if** the loupe goes blank,
  keeps showing the now-out-of-scope asset, or the app throws/shows an error.
- Step 7: the `.all` scope never needs to reselect (everything already
  matches) — selection is provably unchanged from step 6's landing asset.
  **Fails if** selection moved anyway (a spurious reselect on `.all` would
  indicate `selectionAfterScopeChange` isn't short-circuiting on the
  already-matches branch, `AppModel.swift:320-324`).
- Step 8: cycling a full loop back to the same scope reproduces the same
  visible set (assuming no writes happened in between, which this card
  doesn't perform). **Fails if** the counts drift between the two visits to
  "Unrated".

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `--smoke`'s exact pick/reject split within the 11 pre-flagged assets isn't
  known from source alone (the seeder's flag-assignment logic wasn't traced
  in this pass) — step 2's SQL query is the authoritative source, not a
  hardcoded number in this card.
- The reselection assertions in steps 4-6 only assert "landed on some
  correctly-scoped asset," not a specific expected id —
  `selectionAfterScopeChange`'s forward/backward lockstep walk
  (`AppModel.swift:329-339`) means the nearest match could be either side of
  the old index. If that proves too weak in practice (e.g. it'd pass even
  for a wrong-but-plausible reselect), tighten it by computing the expected
  id directly from the `assets` order via a parallel SQL `ORDER BY rowid`
  query and comparing ids exactly.

## Run status
UNRUN — SQL not yet dry-run against a live catalog; needs human-present
execution per test/scenarios/README.md.
