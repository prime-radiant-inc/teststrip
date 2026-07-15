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

`--faces` seeds `sample-data/photos/faces` (11 real JPEGs of Glenn/Ride/Armstrong/Aldrin, per `sample-data/faces.tsv`) via a plain folder import — nothing is pre-flagged/pre-rated/pre-confirmed.

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

2. **Run the import**:
   ```bash
   ax press --role AXMenuItem --label "Import Faces from Contacts"
   ```
   (People ▸ **Import Faces from Contacts**). Grant the **Contacts access** TCC prompt when it appears — this is the first (and only required) TCC permission the app requests in this run. The import runs on the main actor; a brief UI pause on large address books is expected. Assert:
   ```bash
   CONTACT_ROWS=$(script/vm_scenario_run.sh sql faces "SELECT count(*) FROM contact_reference_faces;")
   [ "$CONTACT_ROWS" -ge 2 ] || { echo "expected ≥2 seeded contacts, got $CONTACT_ROWS"; }
   GLENN_CONTACT=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier, name FROM contact_reference_faces WHERE name='John Glenn' LIMIT 1;")
   echo "Glenn contact: $GLENN_CONTACT"   # e.g., "ABC123|John Glenn"
   ARMSTRONG_CONTACT=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier, name FROM contact_reference_faces WHERE name='Neil Armstrong' LIMIT 1;")
   echo "Armstrong contact: $ARMSTRONG_CONTACT"
   ```

3. **Find the Glenn contact's id and check for a review card**:
   ```bash
   GLENN_CONTACT_ID=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier FROM contact_reference_faces WHERE name='John Glenn' LIMIT 1;")
   # Baseline: no people row created yet (the contact is latent, awaiting a confirm gesture).
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE id='contact:$GLENN_CONTACT_ID';"  # 0 — not yet materialized
   ```

4. **Navigate to People and locate the "Is this John Glenn?" review card**:
   ```bash
   ax press --role AXButton --label "People"
   ```
   (or ⌘2 Library, then click the People view toggle). Look for a card or row reading **"Is this John Glenn?"** displaying the contact's reference photo (not a gradient fallback). This card only surfaces if the latent face matched a library face:
   ```bash
   ax find --role AXStaticText --contains "Is this John Glenn"
   ```
   If no card appears, the contact's embedding didn't match any library face within threshold — note this as a fixture gap (retry with a closer photo pair if testing negative cases) rather than a regression.

5. **Confirm the latent-contact match**:
   ```bash
   ax press --role AXButton --label "Confirm"
   ```
   (or a button proximate to the review card — adapt the label if the UI renders it differently). Assert the materialized person and face link:
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

6. **(Prerequisite for this leg)** Confirm "Neil Armstrong" as a person from a library image first (outside the import flow), so the person row exists:
   ```bash
   # If not already done: navigate to a Neil Armstrong library photo, open inspector, "Add name" / "New person" / "Neil Armstrong".
   ARMSTRONG_PERSON_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='Neil Armstrong' AND id NOT LIKE 'contact:%';")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE person_id='$ARMSTRONG_PERSON_ID' AND origin='user';"  # ≥1 (confirmed face from library)
   ```

7. **Verify the name-based recall boost**: The "Neil Armstrong" Contact's face was imported with the same name as the existing person. It should land in that person's Proposed section as `origin='ai'` (not create a new `contact:` person):
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT person_id, origin FROM person_faces WHERE person_id='$ARMSTRONG_PERSON_ID' AND origin='ai';"  # one or more rows with origin='ai'
   # Confirm no separate contact-sourced person row was created for Armstrong:
   ARMSTRONG_CONTACT_ID=$(script/vm_scenario_run.sh sql faces "SELECT contact_identifier FROM contact_reference_faces WHERE name='Neil Armstrong' LIMIT 1;")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM people WHERE id='contact:$ARMSTRONG_CONTACT_ID';"  # 0 — no separate person materialized for this name match
   ```

8. **Verify the recall-boost face appears in the UI** (Proposed section of the existing Armstrong person):
   ```bash
   # Navigate to People, find Neil Armstrong's person card, open it.
   ax find --role AXStaticText --contains "Neil Armstrong"
   ax press  # click the Armstrong card
   ```
   A "✨ Proposed" section should list the contact's face (if rendering logic supports it). This verifies the AI face landed in the Proposed surface, not as a top-level review card.

## Expected

- Step 1: `evaluation_signals` covers all 11 assets; `face_observations` > 0. **Fails if** evaluation never completes or `face_observations` stays 0 despite the model being downloaded (report as a face-pipeline regression, not a fixture gap).
- Step 2: The TCC prompt grants access; at least two `contact_reference_faces` rows exist (Glenn and Armstrong). **Fails if** the TCC prompt is denied, the import completes with zero rows, or the Contacts table remains empty.
- Steps 3-4: A `people` row with `id='contact:$GLENN_CONTACT_ID'` does **not** exist until after the confirm gesture (Step 5). A review card reading "Is this John Glenn?" surfaces. **Fails if** a `contact:` person row appears before Step 5's confirm, or if no review card appears despite the contact_reference_faces row.
- Step 5: Confirming the review card materializes the person row, sets `person_faces.origin='user'` for the matched library face, and creates a `person_assets` row. **Fails if** origin stays 'ai', no `person_assets` row appears, or the person row is absent.
- Step 6: A pre-existing "Neil Armstrong" person (confirmed from a library image) has at least one `person_faces.origin='user'` row before Step 7. **Fails if** the person doesn't exist or has no confirmed face — prerequisite must be established first.
- Step 7: The Armstrong contact's face lands in the existing Armstrong person's Proposed section as `origin='ai'`; no separate `contact:$ARMSTRONG_CONTACT_ID` person row is created. **Fails if** an extra person row appears (regression: latent contacts shouldn't materialize without a confirm gesture), or if the AI face doesn't land in Proposed (recall-boost routing broken).

## Cleanup

Quit the launched instance; discard the VM run directory (`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state) created for this run, per `test/scenarios/README.md`'s isolated-launch teardown. Touch no real catalog or real Contacts database.

## Sharp edges

- **TCC access is required.** The Contacts access TCC prompt must be granted for the import to proceed. If denied, the import completes with zero `contact_reference_faces` rows and no error message — verify the TCC permission in System Preferences / Privacy if import appears to silently fail.
- **Latent contacts with no library match create no `people` row.** If a Contact's face embedding doesn't match any library face within the distance threshold (`FaceSuggestionBuilder.defaultMaximumMatchDistance`), no review card surfaces and no `contact:` person is materialized. This is expected — verify it deliberately if testing negative cases.
- **Import runs on the main actor.** The current implementation runs the full import (Contacts framework queries + embedding computations) on the main thread; a large address book (hundreds of contacts) may briefly freeze the UI. This is a known gap flagged in the task notes as "expected" for the current version (async refactor is a later task).
- **VM contact setup is manual.** Seeding the VM Contacts database has no built-in script verb in `vm_scenario_run.sh` — use the Contacts app UI or `.vcf` import to set up test contacts ahead of time. This is a one-time setup per VM.
- **Contact photo format requirements.** The Contacts framework on macOS accepts most common image formats (JPEG, PNG); verify the photo assignment in the VM's Contacts app UI before running the import. A contact with a missing/invalid photo may skip import.
- **Idle-wedge / keep-warm**: Step 1's evaluation pass waits on asynchronous face recognition — re-assert frontmost via `script/vm_scenario_run.sh ax wait-vended Teststrip` on every poll while waiting, per CLAUDE.md and `script/verify_people_clustering.sh`'s reference pattern.

## Run status

NOT RUN — authored 2026-07-15 against `feat/contacts-seeding`, not yet run live. Pending execution in the Tart VM with the AuraFace model present (`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a human-triggered step separate from authoring this card. Contact seeding is a one-time manual VM setup prerequisite (Contacts app UI or `.vcf` import in the VM).
