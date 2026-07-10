# people-005-queue-keyboard: arrow to a card, Return confirms — person_assets appears only after

**What this covers**: inventory items 12-16, 27 — the People workspace's
unified suggestions+review queue keyboard model and its confirm-before-write
invariant (Task 21): clamped `focusedIndex` with an accent border, ←→ wrap
navigation, Return confirms only the focused card (nameable cards open the
naming sheet without writing), Esc dismisses a suggestion / is a no-op on a
review card, Space does nothing, and the key monitor guards on key-window +
not-an-NSTextView + no-modifiers so a sheet's own Return (Create) isn't
double-fired. Focus is requested on appear. `person_assets` must not exist
for a focused card until Return is pressed on it, and all writes happen only
inside confirm/dismiss model methods (item 27, confirm-before-write).

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
6. Press Return on the focused card. Two card kinds are possible and both are
   in scope (a fresh `--faces` launch only ever produces name-routing
   "Who is this?" cards on the first pass — a one-tap "Is this X?" card can
   only exist once a person has already been named, per
   `PeopleView.suggestionCards`/`isOneTapConfirm`
   (`Sources/TeststripApp/PeopleView.swift:637-663`) — so don't assume one
   kind is reachable; branch on what's actually focused):
   - **Name-routing card** ("Who is this?"): Return opens the naming sheet.
     Assert `person_assets` is *still* 0 here — opening the sheet is routing,
     not writing. Type a name into the sheet's field and press Return again
     (confirms via the sheet, per `people-naming-sheet-return-routing.md`).
   - **One-tap-confirm card** ("Is this X?"): Return confirms directly.
7. Assert `person_assets` now has exactly one new `people` row and the
   expected new `person_assets` rows for that card's group only (matching its
   "N faces · N photos" count), and no other suggestion card was confirmed as
   a side effect (their rows are still absent).

## Expected
- Step 3 and 5: 0 rows. **Fails if** anything is written before the Return
  gesture — that's a confirm-before-write violation, assert it as the
  negative, don't excuse it.
- Step 6 (name-routing branch): opening the naming sheet must not write
  `person_assets` — routing is not confirming. **Fails if** the sheet's
  appearance alone writes anything.
- Step 7: exactly the focused card's rows appear, matching its face/photo
  count, and no other card's rows appear. **Fails if** Return confirms the
  wrong card, multiple cards, or none.

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
needed. Needs a human-present re-run. All SQL in this card was run headlessly against a seeded --smoke catalog on 2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift).
