# people-023-contacts-seeding: Import Faces from Contacts

**What this covers**: The Contacts-seeding feature sub-project — importing face reference images and embeddings from macOS Contacts and using them to drive face-match promotions and cross-person recall boosting. Exercises `importFacesFromContacts`, `contact_reference_faces` catalog writes, latent-contact matching against library faces, and name-based recall routing into confirmed persons' Proposed sections.

## Pre-state

```bash
ROOT_DIR="$(git rev-parse --show-toplevel)"
./script/download_face_model.sh   # AuraFace-v1 — see Sharp edges: download may fail (dev-008 gap)
script/vm_scenario_run.sh sync faces
script/vm_scenario_run.sh launch faces   # prints "launched 'faces' fresh at $FRESH" — capture $FRESH
script/vm_scenario_run.sh ax wait-vended Teststrip
```

`--faces` seeds `sample-data/photos/faces` (11 real JPEGs of Glenn/Ride/Armstrong/Aldrin, per `sample-data/faces.tsv`) via a plain folder import — nothing is pre-flagged/pre-rated/pre-confirmed. Armstrong has two photos: `commons-armstrong-eva-training.jpg` (confirmed as the person's initial library face in Step 2 below) and `commons-armstrong-gemini8.jpg` (the still-unassigned asset Step 7 uses to trigger the recall boost).

### Seed macOS Contacts in the VM (one-time manual setup prerequisite)

**Manual step**: This card assumes at least two macOS **Contacts** in the VM, each with a contact photo matching a library image:

1. **"John Glenn"** — contact photo = one of the Glenn library images (e.g., `commons-glenn-official.jpg`). Via the Contacts app in the VM: create the contact, then double-click its photo well and assign a JPEG from the library.
2. **"Neil Armstrong"** — contact photo = one of the Armstrong library images (e.g., `commons-armstrong-eva-training.jpg`). Used for the recall-boost leg (Leg 2 below).

Both contacts must be saved in the system's Contacts database before proceeding. This is a one-time setup; the contacts persist for the duration of this run.

### Baseline

```bash
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM contact_reference_faces;"                    # 0 — no import yet
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM assets;"                                     # 11 — library seeded
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"                          # 0 — unevaluated
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE id LIKE 'contact:%';"          # 0 — no contact-sourced people yet
```

## Steps

### Leg 1: Latent-contact matching — unconfirmed library face + contact photo → review card → confirm → people row

1. **Evaluate the library** so face observations exist before import:
   ```bash
   ax press --role AXMenuItem --label "Evaluate Visible"
   ```
   (⌘2 for Library, then Culling ▸ Evaluate Visible). Keep the app warm (re-assert frontmost every poll) while it drains:
   ```bash
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required — if 0, the AuraFace model didn't load
   ```

2. **(Leg 2 prerequisite — must run *before* Step 3's import, not merely before Leg 2's assertions.)** Confirm "Neil Armstrong" as a person from a library photo, a direct **user** gesture (mirrors `people-020-ai-label-provenance.md` step 7 / `people-022-proposed-and-key-photo.md` step 2):
   ```bash
   ARMSTRONG_EVA_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-armstrong-eva-training.jpg';")
   ARMSTRONG_GEMINI_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-armstrong-gemini8.jpg';")
   ```
   Open `commons-armstrong-eva-training.jpg` (⌘2 → select → double-click → ⌘I; scroll to the People section):
   ```bash
   ax press --role AXButton --label "Add name"
   ax press --role AXMenuItem --label "New person…"
   ax type --contains "Person name" --text "Neil Armstrong"
   ax press --role AXButton --label "Create Person"
   ```
   ```bash
   ARMSTRONG_PERSON_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='Neil Armstrong' AND id NOT LIKE 'contact:%';")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$ARMSTRONG_PERSON_ID' AND origin='user';"  # 1 — commons-armstrong-eva-training.jpg's confirmed face
   ```
   **Why this must happen first**: `ContactFaceSeeder.seed()` (`Sources/TeststripCore/People/ContactFaceSeeder.swift:47`) resolves a contact's `person_id` via `repository.personID(matchingName:)` — a one-time `SELECT id FROM people WHERE name = ?` snapshot taken *at import time* — falling back to a fresh `contact:<identifier>` if no same-named person exists yet. There is no later reconciliation: `upsertContactReferenceFace`'s `ON CONFLICT(contact_identifier)` only fires on a second `importFacesFromContacts()` call, and the seeder short-circuits any contact whose photo hash is unchanged (`summary.unchanged += 1; continue`, before the `personID(matchingName:)` lookup even runs) — so re-running the import after confirming Armstrong would **not** retroactively fix a wrong `contact:<id>` attachment. If Armstrong isn't already a real `people` row before Step 3's import runs, Leg 2 can never route to the right person.

3. **Run the import**:
   ```bash
   ax press --role AXMenuItem --label "Import Faces from Contacts…"
   ```
   (People ▸ **Import Faces from Contacts…** — note the trailing `…`, U+2026; `ax_drive.sh --label` is an exact match against `Button("Import Faces from Contacts…")` in `main.swift`). Grant the **Contacts access** TCC prompt when it appears (see Sharp edges — this card cannot AX-drive the system TCC dialog). The import runs on the main actor; a brief UI pause on large address books is expected. Assert:
   ```bash
   CONTACT_ROWS=$(script/vm_scenario_run.sh sql faces "SELECT count(*) FROM contact_reference_faces;")
   [ "$CONTACT_ROWS" -ge 2 ] || { echo "expected ≥2 seeded contacts, got $CONTACT_ROWS"; }
   GLENN_CONTACT=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier, name FROM contact_reference_faces WHERE name='John Glenn' LIMIT 1;")
   echo "Glenn contact: $GLENN_CONTACT"   # e.g., "ABC123|John Glenn"
   ARMSTRONG_CONTACT=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier, name FROM contact_reference_faces WHERE name='Neil Armstrong' LIMIT 1;")
   echo "Armstrong contact: $ARMSTRONG_CONTACT"
   script/vm_scenario_run.sh sql faces "SELECT person_id FROM contact_reference_faces WHERE name='Neil Armstrong';"  # = $ARMSTRONG_PERSON_ID (name-attached to the already-confirmed person, not a fresh contact:<id>)
   ```

4. **Find the Glenn contact's id and check for a review card**:
   ```bash
   GLENN_CONTACT_ID=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier FROM contact_reference_faces WHERE name='John Glenn' LIMIT 1;")
   # Baseline: no people row created yet (the contact is latent, awaiting a confirm gesture).
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE id='contact:$GLENN_CONTACT_ID';"  # 0 — not yet materialized
   ```

5. **Navigate to People and locate the "Is this John Glenn?" review card**:
   ```bash
   ax press --role AXButton --label "People"
   ```
   (or ⌘2 Library, then click the People view toggle). Look for a card or row reading **"Is this John Glenn?"** displaying the contact's reference photo (not a gradient fallback). This card only surfaces if the latent face matched a library face:
   ```bash
   ax find --role AXStaticText --contains "Is this John Glenn"
   ```
   If no card appears, the contact's embedding didn't match any library face within threshold — note this as a fixture gap (retry with a closer photo pair if testing negative cases) rather than a regression.

6. **Open the review sheet, then confirm the remainder.** Per `people-021-face-group-review.md`, the "Is this John Glenn?" card is a **link into `FaceGroupReviewView`**, not a one-tap confirm — press the card body (matched by its `AXHelp`, since the card has no single accessible label) to open the sheet:
   ```bash
   ax press --role AXButton --help "Review this group before confirming John Glenn"
   ```
   The sheet opens titled "Is this John Glenn?" with a grid of large face tiles:
   ```bash
   ax find --role AXStaticText --contains "Is this John Glenn"
   ```
   Press the confirm bar's button — it is labeled with the **person's name** (`review.confirmActionTitle == personName`, `FaceGroupReviewPresentation.swift:44`), **not** a button literally labeled "Confirm":
   ```bash
   ax press --role AXButton --label "John Glenn"
   ```
   Assert the materialized person and face link:
   ```bash
   CONTACT_PERSON_ID="contact:$GLENN_CONTACT_ID"
   script/vm_scenario_run.sh sql faces "SELECT id, name FROM people WHERE id='$CONTACT_PERSON_ID';"  # now exists, e.g., id="contact:ABC123", name="John Glenn"
   script/vm_scenario_run.sh sql faces "SELECT face_index, origin, person_id FROM person_faces WHERE person_id='$CONTACT_PERSON_ID';"  # origin='user', the matched library asset's face
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$CONTACT_PERSON_ID';"  # ≥1 (the library asset linked as a confirmed face)
   ```
   The contact_reference_faces row's person_id may also update to the new person's id:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT person_id FROM contact_reference_faces WHERE contact_identifier='$GLENN_CONTACT_ID';"  # may now be non-null, pointing to $CONTACT_PERSON_ID
   ```

### Leg 2: Name-attach recall-boost — contact name matches existing confirmed person → land AI face in Proposed

Neil Armstrong was already confirmed as a real person in Step 2 (before the import), and his contact was imported in Step 3 with `person_id` already name-attached to that real person (not a latent `contact:<id>`). This leg now exercises the actual recall-boost mechanism: an AI-origin face match against the combined confirmed-face + contact-reference embedding pool.

7. **Fire the trigger and verify the name-based recall boost.** `promoteFaceMatches` (`AppModel.swift:3716`, which merges `contact_reference_faces` embeddings into the confirmed-centroid pool at `:3726-3728`) only runs on a genuine evaluation-**completion** event — never from importing a contact or from confirming a different person (mirror `people-020` step 8 / `people-022` step 3's single-asset re-evaluation pattern). Baseline first:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$ARMSTRONG_PERSON_ID' AND origin='ai';"  # 0 — nothing has evaluated this asset against Armstrong's centroid yet
   ```
   Select the **second, still-unassigned** Armstrong asset (⌘2 Library, click `commons-armstrong-gemini8.jpg`'s thumbnail — `$ARMSTRONG_GEMINI_ID` from Step 2), then fire a single-asset evaluation:
   ```bash
   ax press --role AXMenuItem --label "Evaluate Photo"
   ```
   Keep the app warm (re-assert frontmost every poll, per Sharp edges) while it drains, then assert:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT person_id, origin FROM person_faces WHERE person_id='$ARMSTRONG_PERSON_ID' AND origin='ai';"  # one or more rows with origin='ai' — the recall boost
   ```
   Confirm no separate contact-sourced person row was created for Armstrong:
   ```bash
   ARMSTRONG_CONTACT_ID=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier FROM contact_reference_faces WHERE name='Neil Armstrong' LIMIT 1;")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE id='contact:$ARMSTRONG_CONTACT_ID';"  # 0 — no separate person materialized for this name match
   ```
   If no `origin='ai'` row appears, this specific asset didn't cluster within `FaceSuggestionBuilder.defaultMaximumMatchDistance` against the combined centroid — retry against the other Armstrong photo pairing before concluding the routing is broken, per `people-020` step 9's identical caution.

8. **Verify the recall-boost face appears in the UI** (Proposed section of the existing Armstrong person):
   ```bash
   ax find --role AXStaticText --contains "Neil Armstrong"
   ax press --role AXStaticText --contains "Neil Armstrong"
   ```
   (the person card's tap target is the whole row, not a distinct `Button` — see Sharp edges if `AXPress` fails on the static text itself). A "✨ Proposed" section should list `$ARMSTRONG_GEMINI_ID`'s face (if rendering logic supports it). This verifies the AI face landed in the Proposed surface, not as a top-level review card.

## Expected

- Step 1: `evaluation_signals` covers all 11 assets; `face_observations` > 0. **Fails if** evaluation never completes or `face_observations` stays 0 despite the model being downloaded (report as a face-pipeline regression, not a fixture gap).
- Step 2: Neil Armstrong exists as a real (non-`contact:`) `people` row with ≥1 confirmed (`origin='user'`) `person_faces` row, **before** Step 3's import runs. **Fails if** this step is skipped or reordered after the import — the name-attach in Step 3 can only resolve to a person that already exists at that moment.
- Step 3: The TCC prompt grants access; at least two `contact_reference_faces` rows exist (Glenn and Armstrong); Armstrong's row's `person_id` already equals `$ARMSTRONG_PERSON_ID` (name-attached, not a fresh `contact:<id>`). **Fails if** the TCC prompt is denied, the import completes with zero rows, the Contacts table remains empty, or Armstrong's `person_id` is a `contact:` id (name-attach didn't fire because Step 2 ran too late).
- Steps 4-5: A `people` row with `id='contact:$GLENN_CONTACT_ID'` does **not** exist until after the confirm gesture (Step 6). A review card reading "Is this John Glenn?" surfaces. **Fails if** a `contact:` person row appears before Step 6's confirm, or if no review card appears despite the contact_reference_faces row.
- Step 6: Opening the card presents the `FaceGroupReviewView` sheet (not an immediate write); pressing the confirm bar's person-named button materializes the person row, sets `person_faces.origin='user'` for the matched library face, and creates a `person_assets` row. **Fails if** origin stays 'ai', no `person_assets` row appears, the person row is absent, or the card confirms with a single tap with no intervening sheet.
- Step 7: A targeted re-evaluation of the second, still-unassigned Armstrong asset produces an `origin='ai'` `person_faces` row against `$ARMSTRONG_PERSON_ID`, and no separate `contact:$ARMSTRONG_CONTACT_ID` person row is created. **Fails if** no `origin='ai'` row ever appears despite the trigger (recall-boost routing broken), or if an extra person row appears (regression: latent contacts shouldn't materialize without a confirm gesture).
- Step 8: The recall-boosted face renders in Neil Armstrong's "✨ Proposed" section. **Fails if** the person card doesn't open, or the Proposed section doesn't list the newly-promoted face despite Step 7's `origin='ai'` row existing.

## Cleanup

Quit the launched instance; discard the VM run directory (`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state) created for this run, per `test/scenarios/README.md`'s isolated-launch teardown. Touch no real catalog or real Contacts database.

## Sharp edges

- **TCC access is required, and this card cannot script the grant.** `script/vm_scenario_run.sh setup` pre-grants only `kTCCServiceAccessibility`, `kTCCServiceAppleEvents`, and `kTCCServiceScreenCapture` (`script/vm_scenario_run.sh:119-134`) — there is **no** `kTCCServiceContacts` pre-grant line. Two options, neither currently automated: (a) add a new pre-grant row for `kTCCServiceContacts` keyed to the Teststrip app's TCC client identifier to `cmd_setup`'s SQL block, or (b) manually click "Allow" in the Tart viewer's System Settings (or the system consent dialog) the first time the prompt appears during Step 3. If denied, the import completes with zero `contact_reference_faces` rows and no error message — verify the TCC permission if import appears to silently fail.
- **Name-attach only works if the same-named person exists *before* the import runs** (see Step 2's rationale). `ContactFaceSeeder.personID(matchingName:)` is a one-time snapshot at import time, and a same-named contact whose photo hash hasn't changed short-circuits as "unchanged" on any later re-import (`ContactFaceSeeder.swift:34-36`) — so there is no way to retroactively fix a `contact:<id>` attachment by re-running the import after confirming the person. Get the ordering right the first time.
- **Latent contacts with no library match create no `people` row.** If a Contact's face embedding doesn't match any library face within the distance threshold (`FaceSuggestionBuilder.defaultMaximumMatchDistance`), no review card surfaces and no `contact:` person is materialized. This is expected — verify it deliberately if testing negative cases.
- **The "Is this X?" card is a link into a review sheet, not a one-tap confirm.** Press the card body (matched by its `AXHelp` text, since the card composes several `Text`/`Label` children with no single accessible title) to open `FaceGroupReviewView`, then press the confirm bar's button — its label is the **person's name**, not "Confirm". See `people-021-face-group-review.md` for the full review/prune/confirm flow this card only exercises the one-tap-confirm half of.
- **Import runs on the main actor.** The current implementation runs the full import (Contacts framework queries + embedding computations) on the main thread; a large address book (hundreds of contacts) may briefly freeze the UI. This is a known gap flagged in the task notes as "expected" for the current version (async refactor is a later task).
- **VM contact setup is manual.** Seeding the VM Contacts database has no built-in script verb in `vm_scenario_run.sh` — use the Contacts app UI or `.vcf` import to set up test contacts ahead of time. This is a one-time setup per VM.
- **Contact photo format requirements.** The Contacts framework on macOS accepts most common image formats (JPEG, PNG); verify the photo assignment in the VM's Contacts app UI before running the import. A contact with a missing/invalid photo may skip import.
- **The named-person card's tap target isn't a distinct `Button`.** `namedPersonCard` (`PeopleView.swift:445-495`) uses `.onTapGesture` + `.help(...)` over the whole row rather than a `Button`, so Step 8's `ax press --role AXStaticText --contains "Neil Armstrong"` presses the name text itself; if `AXPress` fails on that element, retry against the row's container (walk up one ancestor) rather than assuming the feature is broken.
- **Idle-wedge / keep-warm**: both Step 1's full-library evaluation and Step 7's single-asset re-evaluation wait on asynchronous face recognition — re-assert frontmost via `script/vm_scenario_run.sh ax wait-vended Teststrip` on every poll while waiting, per CLAUDE.md and `script/verify_people_clustering.sh`'s reference pattern.

## Run status

NOT RUN — authored 2026-07-15 against `feat/contacts-seeding`, not yet run live. Pending execution in the Tart VM with the AuraFace model present (`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a human-triggered step separate from authoring this card. Contact seeding is a one-time manual VM setup prerequisite (Contacts app UI or `.vcf` import in the VM).
