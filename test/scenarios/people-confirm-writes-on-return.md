# people-confirm-writes-on-return: arrow to a card, Return confirms — person_assets appears only after

**What this covers**: the People workspace's confirm-before-write invariant
for the arrow/Return queue (Task 21): `person_assets` must not exist for a
focused card until Return is pressed on it.

## Pre-state
```bash
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘3 for People.
2. Wait for the worker to embed faces and grouping suggestions to appear
   (mirror `script/verify_people_clustering.sh`'s warm-poll loop on
   `face_observations`).
3. Assert `SELECT count(*) FROM person_assets;` reads 0 — nothing confirmed
   yet.
4. Press → to move focus onto the first suggestion card (or confirm it's
   already focused at index 0).
5. **Before** pressing Return, re-assert `person_assets` count is still 0 —
   arrowing to focus a card must not write anything.
6. Press Return on the focused (one-tap-confirm, not name-routing) card.
7. Assert `person_assets` now has exactly one new row for that card's asset,
   and no other suggestion card was confirmed as a side effect.

## Expected
- Step 3 and 5: 0 rows. **Fails if** anything is written before the Return
  gesture — that's a confirm-before-write violation, assert it as the
  negative, don't excuse it.
- Step 7: exactly one row, for the focused card only. **Fails if** Return
  confirms the wrong card, multiple cards, or none.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Confirm-before-write
routing already covered by a unit test per task-21-report.md
(`testReturnAppliedThroughTheQueueWritesOnlyTheFocusedSuggestion` in
`Tests/TeststripAppTests/PeopleQueuePresentationTests.swift`, full suite
green); this card is the live-AX counterpart the report calls out as still
needed. Needs a human-present re-run.
