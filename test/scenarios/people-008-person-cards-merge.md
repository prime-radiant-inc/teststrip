# people-008-person-cards-merge: confirmed person cards, merge, navigation, and the duplicate-name probe

**What this covers**: confirmed person cards in the "ALL PEOPLE" grid show
"N confirmed photos"; the merge context-menu action appears only when 2+
named people exist and `mergePerson` folds one person's `person_assets`/
`person_faces` into another and deletes the source `people` row; tapping a
person card navigates the Library grid to a `person:<name>` predicate. Also
runs the duplicate-name **probe** documented as an open question in
LEDGER.md's people-008 row: what happens when two different `people` rows
are confirmed with the identical name string.

## Pre-state
```bash
./script/download_face_model.sh
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. **Seed two named people** via the Name Selection sheet
   (`people-007-name-selection.md`'s steps 2-8): confirm one photo as "Alpha
   Person," a different photo as "Beta Person." Record:
   ```bash
   sqlite3 "$DB" "SELECT id, name FROM people ORDER BY name;"
   sqlite3 "$DB" "SELECT person_id, count(*) FROM person_assets GROUP BY person_id;"
   ```
2. **Person-card count text.** `script/ax_drive.sh wait-vended Teststrip`;
   press ⌘3 People. For each named person card, read its count `AXStaticText`
   and assert it equals `NamedPersonPresentation.countText`: "1 confirmed
   photo" for a single asset, "N confirmed photos" otherwise
   (`PeopleView.swift:777-779`).
3. **Merge menu gating — one person.** With only one named person (undo step
   1's second confirm for this sub-check, or test on a fresh single-person
   catalog), assert no merge `AXMenu`/`arrow.triangle.merge` control exists on
   that card (`presentation.namedPeople.count > 1` gate,
   `PeopleView.swift:417-430`).
4. **Merge menu gating — two+ people.** With both "Alpha Person" and "Beta
   Person" present, assert the merge menu control now exists on each card,
   and its menu items read "Merge into Beta Person" / "Merge into Alpha
   Person" (every *other* named person, not self).
5. **Merge.** Record ground truth before:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"                      # P_before
   sqlite3 "$DB" "SELECT count(*) FROM person_assets WHERE person_id=(SELECT id FROM people WHERE name='Alpha Person');"  # A_before
   sqlite3 "$DB" "SELECT count(*) FROM person_assets WHERE person_id=(SELECT id FROM people WHERE name='Beta Person');"   # B_before
   ```
   Press "Merge into Beta Person" on the Alpha Person card. Then:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"                      # must be P_before - 1
   sqlite3 "$DB" "SELECT * FROM people WHERE name='Alpha Person';"   # must be empty (source row deleted)
   sqlite3 "$DB" "SELECT count(*) FROM person_assets WHERE person_id=(SELECT id FROM people WHERE name='Beta Person');"  # must be A_before + B_before
   ```
6. **Person-card tap navigation.** Tap "Beta Person"'s card (not the merge
   menu — the card body). Assert the app switches to the Library grid scoped
   to `person:Beta Person` (`showPersonPhotos`, `AppModel.swift:3331-3337`,
   which sets `librarySearchText` to a `.person(name)` predicate and
   `selectedView = .grid`). Cross-check the grid's visible asset IDs against
   `SELECT asset_id FROM person_assets WHERE person_id=(SELECT id FROM people WHERE name='Beta Person');`.
7. **Duplicate-name probe.** Reset to a fresh `--faces` catalog (relaunch).
   Confirm one photo as "Same Name" via the Name Selection sheet. Then select
   a *different* photo and confirm it as "Same Name" again (a second, separate
   confirm gesture — two distinct `confirmSelectedAssetsAsPerson` calls with
   the same trimmed name string but a fresh `person-\(UUID())` id each time,
   since the sheet always calls the default-id overload). Record:
   ```bash
   sqlite3 "$DB" "SELECT id, name FROM people WHERE name='Same Name';"
   sqlite3 "$DB" "SELECT count(*) FROM person_assets WHERE person_id IN (SELECT id FROM people WHERE name='Same Name');"
   ```
   Observe whether the People canvas renders one "Same Name" card or two.

## Expected
- Step 2: count text matches `person_assets` row count per person, singular
  vs plural exactly. **Fails if** off-by-one or wrong pluralization.
- Step 3: no merge control when `namedPeople.count == 1`. **Fails if** a
  merge menu is reachable with only one confirmed person (nothing to merge
  into).
- Step 4: merge control present, and its items list every *other* named
  person by name. **Fails if** a person can "merge into" itself, or the menu
  is missing/mislabeled.
- Step 5: source `people` row deleted, target's `person_assets` count is the
  sum of both sides' pre-merge counts, total `people` count drops by exactly
  1. **Fails if** the source row survives, asset links are dropped or
  duplicated, or `person_faces` rows aren't repointed (spot-check
  `SELECT count(*) FROM person_faces WHERE person_id=(SELECT id FROM people WHERE name='Alpha Person');`
  reads 0 after merge).
- Step 6: grid scope and rendered assets match `person_assets` ground truth
  for the tapped person. **Fails if** the predicate targets the wrong person
  or the grid shows assets outside that person's linked set.
- Step 7: **this step only records what is observed — there is no
  pass/fail bar**, since the schema does not declare a `UNIQUE` constraint on
  `people.name` (see Sharp edges). Document the actual row count and
  UI-rendering behavior seen.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges — duplicate-name open question (LEDGER.md people-008)
Read directly from schema and model code, **not observed live** (this run has
no console access):
- `CatalogMigrations.swift:124-131` declares `people` as
  `CREATE TABLE ... (id TEXT PRIMARY KEY, name TEXT NOT NULL, ...)` with only
  a **non-unique** index `idx_people_name ON people(name COLLATE NOCASE)` — no
  `UNIQUE` constraint on `name`, case-insensitive or otherwise.
- `confirmSelectedAssetsAsPerson` (`AppModel.swift:3202-3225`) always mints a
  fresh `id: "person-\(UUID().uuidString)"` unless the caller overrides it
  (the sheet never does), and calls `catalog.repository.upsertPerson(id:name:)`
  — an upsert **keyed on `id`**, not `name`. Two separate confirm gestures
  with the same name string therefore produce **two distinct `people` rows**
  with distinct ids and the identical `name` value; nothing in the write path
  detects or merges them.
- Consequence inferred from code: the People canvas would very likely render
  **two separate "Same Name" cards**, each with its own confirmed-photo count
  and its own merge-menu entry (itself excluded, the other "Same Name"
  included) — `NamedPersonPresentation` keys off `person.id`, not `name`, so
  SwiftUI's `ForEach(presentation.namedPeople)` has no reason to collapse
  them. This is inferred, not observed; step 7 exists to confirm or refute it
  live. If confirmed, the product gap is that Name Selection offers no
  "match an existing person by name" step — every confirm gesture is a fresh
  identity, and only the manual Merge action reconciles duplicates after the
  fact.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step, including the
duplicate-name probe (step 7), whose outcome above is inferred from static
code reading of `CatalogMigrations.swift:124-131` and
`AppModel.swift:3202-3225`, not observed. `mergePerson`'s SQL confirmed by
read of `CatalogRepository.swift:878-902`. Needs a human-present re-run. All
SQL in this card was run headlessly against a seeded --faces catalog on
2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift).
