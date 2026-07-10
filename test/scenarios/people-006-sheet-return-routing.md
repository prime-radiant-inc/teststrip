# people-006-sheet-return-routing: Return with the naming sheet open triggers Create, not the queue confirm

**What this covers**: scenario 9 added during Task 21/23 — when the "Name
Face Group" sheet is presented and has keyboard focus, Return must reach the
sheet's default action (`Button("Create").keyboardShortcut(.defaultAction)`),
*not* `PeopleKeyCaptureView`'s queue-confirm handler. A static trace in
`task-21-report.md` confirmed the guard mechanism
(`eventTargetsWindow`/`firstResponder.isTextEditor`); this card is the live
verification.

## Pre-state
```bash
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘3 for People; wait for
   grouping suggestions (per `people-confirm-writes-on-return.md`).
2. Arrow-focus a *cluster* suggestion card (one that routes to naming, not a
   one-tap match) and open its naming sheet
   (`ax_drive.sh press --role AXButton --help "Name this face group"`).
3. Record the focused queue card's asset id before typing.
4. Type a name into the sheet's field (`--contains "Person name"`), then
   press Return **while the sheet is open and the field has focus**.
5. Assert:
   - the sheet's Create action ran (a `people` row now exists for the typed
     name, and `person_assets` links the sheet's group's assets — not
     necessarily the queue's currently-focused card if they differ);
   - critically, `person_assets` has **no row for the focused queue card**
     unless that card *is* the group being named — i.e. Return did not also
     fire the queue's `confirmAction()` on whatever card was focused behind
     the sheet.

## Expected
- Return while the sheet is open and its field is first responder reaches
  only the sheet's Create button. **Fails if** a `person_assets` row appears
  for the focused *queue* card that is unrelated to the sheet's own group —
  that would mean the keystroke double-fired both the sheet's default action
  and the queue's Return handler.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Mechanism confirmed by
static trace in `.superpowers/sdd/task-21-report.md` (guards:
`eventTargetsWindow` fails for the People window while the sheet is key;
`firstResponder.isTextEditor` is true while typing), mirroring
`CullingKeyCaptureView`'s existing pattern. Needs a human-present re-run to
confirm the static trace holds live. All SQL in this card was run headlessly against a seeded --smoke catalog on 2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift).
