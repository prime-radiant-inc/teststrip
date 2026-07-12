# people-001-canvas-header: People canvas three-panel layout and the header count

**What this covers**: the People workspace's top-level canvas — the header
line "N people · M photos with face signals" and the three stacked panels it
sits above (face-suggestion/review strip, ALL PEOPLE grid, and the per-person
detail reachable by tapping a card) — render counts that match catalog ground
truth. `N` is `namedPeople.count` (confirmed `people` rows); `M` is
`photosWithFaceSignals`, which `PeoplePresentation.init` derives as
`max(faceCountSignals, faceQualitySignals)` — the larger of the two
per-evaluation-kind asset counts (`Sources/TeststripApp/PeopleView.swift:551-553`),
**not** a sum and **not** a distinct-asset union across both kinds.

## Pre-state
```bash
./script/download_face_model.sh
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. **Record ground truth** once face evaluation has drained (watch Activity;
   mirror `script/verify_people_clustering.sh`'s warm-poll loop):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"
   sqlite3 "$DB" "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE kind='faceCount';"
   sqlite3 "$DB" "SELECT count(DISTINCT asset_id) FROM evaluation_signals WHERE kind='faceQuality';"
   ```
   Call these `P`, `FC`, `FQ`. The header's expected `M` is `max(FC, FQ)`.
2. `script/ax_drive.sh wait-vended Teststrip`; press ⌘3 for People.
3. `script/ax_drive.sh wait --role AXStaticText --contains "photos with face signals"`
   (falls back to "· N photos" if `P == 0` and `M == 0`, per
   `headerSummary`'s third branch).
4. Read the header `AXStaticText`'s exact value via
   `script/ax_drive.sh find --role AXStaticText --contains "people ·"`
   (dump its title/value).
5. Confirm the three panels are present: the review/suggestion strip (top),
   the "ALL PEOPLE" named-person grid (middle), and — by tapping a named
   person card if one exists — the Library grid filtered to `person:<name>`
   (the per-person detail surface; covered in depth by
   `people-008-person-cards-merge.md`).

6. **Empty-catalog copy variant (persona-8 defect)**: relaunch with
   `./script/build_and_run.sh --isolated` (empty catalog), ⌘3 for People.
   Assert the review strip's empty-state detail reads
   "These photos haven’t been scanned for faces yet. Scan for faces to see
   who’s in your photos." and that NO empty-state text contains internal
   jargon — assert `ax_drive.sh find --contains` FAILS for each of:
   "evaluation", "review queues", "deferred", "face-box". The face-actions
   status line must read "Confirm a suggested group, name faces yourself,
   or merge people. Nothing is saved until you confirm."
   (Unit coverage: `PeoplePresentationTests.testEmptyStateCopySpeaksUserLanguage`.)

## Expected
- Step 6: empty-state copy is user language exactly as quoted; **fails if**
  any banned jargon term renders in the People empty state.
- Step 4: header text is exactly `"\(P) people · \(max(FC,FQ)) photos with face signals"`
  when `P > 0`, or `"0 people · \(max(FC,FQ)) photos with face signals"` when
  `P == 0` but `max(FC,FQ) > 0`, or `"0 people · \(total asset count) photos"`
  when both are 0 (`headerSummary`, `PeopleView.swift:566-574`). **Fails if**
  the rendered `M` is `FC + FQ` (a sum) or a `UNION` of asset IDs across both
  kinds rather than `max` of the two independent counts — that would indicate
  the view diverged from `PeoplePresentation.init`.
- Step 5: three panels are structurally present and the person-card tap
  navigates. **Fails if** any panel is entirely absent from the AX tree, or
  the tap navigates to the wrong scope/predicate.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `max(faceCount, faceQuality)` means a photo with only a `faceQuality`
  signal is counted once, and a photo with both is *also* counted once (not
  double-counted) as long as both kinds' per-kind totals are close — the
  metric is not "distinct assets with either signal," it's "the larger of the
  two per-kind totals," which are the same number only when one kind is a
  strict superset of asset IDs for the other. Don't assume they coincide;
  read both `FC` and `FQ` and compare against the rendered `M` directly.
- If the `--faces` corpus produces only `faceCount` signals and no
  `faceQuality` signals (or vice versa), `max` degenerates to whichever kind
  is present — still worth asserting, but note in the run which branch was
  actually exercised.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. The `max(faceCount,
faceQuality)` derivation is confirmed by static read of
`Sources/TeststripApp/PeopleView.swift:551-556` (`PeoplePresentation.init`)
and `566-574` (`headerSummary`). Needs a human-present re-run. All SQL in this
card was run headlessly against a seeded --faces catalog on 2026-07-10
(schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift).
