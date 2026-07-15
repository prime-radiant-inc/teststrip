# Contacts Seeding — Design Spec

**Date:** 2026-07-15
**Sub-project:** B (of the People/identity follow-ups; sub-project A —
People surfacing — is merged).

## Goal

Seed person recognition from the macOS address book. An explicit "Import faces
from Contacts" action embeds each contact's photo and stores it as a **reference
face** so recognition can match catalog faces to that contact — even before the
person has any confirmed photo in the library. A match to a contact you've
already named boosts that person's recall; a match to a not-yet-seen contact
surfaces as a review-first suggestion ("Is this [name]?") showing the contact's
own photo, and confirming it creates the person.

## Background (grounded)

- **The matcher needs no changes.** `FaceSuggestionBuilder.suggestions(unassignedFaces:confirmedFacesByPerson:)`
  (`Sources/TeststripCore/People/FaceSuggestionBuilder.swift`) matches each
  unassigned catalog face to the nearest **person-keyed centroid** within
  `defaultMaximumMatchDistance = 1.23`, and returns per-person matches +
  unmatched clusters. `AppModel.refreshPeopleFaceSuggestions`
  (`AppModel.swift:3617`) builds its `confirmedFacesByPerson: [String: [[Double]]]`
  from `CatalogRepository.confirmedFaceEmbeddingsByPerson` (`origin='user'`
  faces), and `promoteFaceMatches` auto-applies matches as `origin='ai'` via
  `insertAIFace`. Contact references become match targets simply by being
  **unioned into that centroid dict** under a person id.
- **The embedder is reusable in-app.** `FaceRecognitionEmbedder.faceObservations(in image: CGImage) throws -> [AppleVisionFaceObservation]`
  (`Sources/TeststripCore/People/FaceRecognitionEmbedder.swift:16`) runs
  detect→landmarks→align→embed and returns one `AppleVisionFaceObservation`
  (`{boundingBox: FaceBoundingBox, captureQuality: Double?, featurePrintVector:
  [Double]}`, `AppleVisionEvaluationProvider.swift:15`) per successfully
  embedded face, silently skipping faces it can't embed.
  `CoreMLFaceEmbeddingModel.auraFace()` resolves the AuraFace-v1 model from
  `Bundle.main` → the app's `Contents/Resources` → the repo
  `sample-data/models/auraface-v1.mlpackage` (present in-repo), so the **app
  process** can embed contact photos directly — no worker round-trip.
- **All existing embedding storage is asset-keyed** — `face_observations` PK
  includes `asset_id`; `person_faces`/`person_assets` are keyed by asset. There
  is no store for an embedding not tied to a catalog asset. This sub-project
  adds one.
- **The app is sandboxed and has no runtime permission prompts today** —
  file access is via security-scoped bookmarks, not TCC. Contacts access is the
  app's first `requestAccess` prompt: it needs `NSContactsUsageDescription` in
  the generated Info.plist (`script/lib/app_bundle.sh` heredoc) and the
  `com.apple.security.personal-information.addressbook` entitlement
  (`config/macos/Teststrip.entitlements`).
- **Provenance model (from sub-project 1):** machine face matches auto-apply as
  `person_faces.origin='ai'` (tentative, never destructive/export until
  confirmed); an explicit user gesture confirms (`confirmFace` → `origin='user'`
  + `person_assets`) or rejects (`rejected_face_people`, sticky). Identity has
  no XMP field.

## Data model — the reference store

New table `contact_reference_faces`, keyed by contact identity for idempotent
re-seed:

| column | meaning |
|---|---|
| `contact_identifier` TEXT (PK) | `CNContact.identifier` |
| `person_id` TEXT | the person this reference maps to (see below) |
| `name` TEXT | contact display name at seed time |
| `embedding_json` TEXT | the 512-d AuraFace embedding of the contact photo's primary face |
| `bounding_box_json` TEXT | the detected face box within the contact photo (for cropping the reference image) |
| `photo_hash` TEXT | hash of the contact photo bytes — re-embed only when it changes |
| `created_at`, `updated_at` REAL | timestamps |

Schema version bumps to the next value via the existing `addColumnIfMissing` /
`CREATE TABLE IF NOT EXISTS` migration pattern (`CatalogMigrations.swift` +
`CatalogDatabase.swift`).

The **contact photo bytes** are cached to a dedicated directory (a sibling of
the preview cache under app-support), keyed by `contact_identifier`, so the
review card can render the contact's own face as the reference image via the
existing `FaceCropAvatar`/`FaceCropLoader` with the stored `bounding_box_json`.

**`person_id` — the latent-vs-attached decision (at seed time):**
- If a `people` row already exists whose `name` matches the contact's
  (case-insensitive) → `person_id` = that existing person's id. The reference
  **boosts an existing person's** recall; no new person is created.
- Otherwise → `person_id` = a latent id `contact:<contact_identifier>`, and
  **no `people` row is created yet.** The person materializes only on match +
  confirm (below).

## Seeding — "Import faces from Contacts"

An explicit menu command (no automatic/background seeding). Flow:

1. `CNContactStore().requestAccess(for: .contacts)` — the app's first TCC
   prompt. On denial, surface a clear message and stop (no crash, no partial
   state).
2. Enumerate contacts that have image data (`CNContactFetchRequest` with the
   identifier, name, and image-data keys; `imageDataAvailable` gate).
3. For each contact photo, decode to `CGImage` and run
   `FaceRecognitionEmbedder.faceObservations(in:)`. Take the **largest** face
   (a contact photo is a headshot; largest = the contact). Skip contacts whose
   photo yields no embeddable face.
4. Compute `photo_hash`; if the `contact_identifier` already has a row with the
   same hash, skip (idempotent). Otherwise embed, resolve `person_id` (attach
   vs latent, per the data model), cache the photo, and upsert the row.
5. After the run, trigger the match/suggestion refresh so the new references
   take effect immediately, and report a summary (seeded / skipped-no-face /
   unchanged).

Re-runnable and idempotent by `contact_identifier` + `photo_hash`. Deleted
contacts are **not** auto-pruned (a later enhancement).

## Matching & surfacing — reuse the existing paths

A new read `CatalogRepository.contactReferenceEmbeddingsByPerson() -> [String:
[[Double]]]` returns reference embeddings keyed by `person_id`. It is **unioned
into** the centroid dict wherever `confirmedFaceEmbeddingsByPerson` is consumed
(`refreshPeopleFaceSuggestions`, `promoteFaceMatches`). With that union and no
matcher change, two behaviors emerge:

The gate between the two behaviors is **whether a `people` row exists for the
matched `person_id`** — not the id's spelling. (`promoteFaceMatches` must skip
any matched `person_id` that has no `people` row; `refreshPeopleFaceSuggestions`
surfaces those instead. After a latent contact is confirmed and materialized, it
keeps its `contact:<id>` id but now *has* a `people` row, so subsequent matches
auto-apply like any real person.)

- **Match to an existing person** (`person_id` has a `people` row — a
  name-attached contact, an embedding match to a confirmed person, or a
  previously-materialized contact): auto-applies as `origin='ai'` exactly as
  today → appears in that person's **Proposed section** (sub-project A).
  Contacts purely improve recall.
- **Match to a latent contact** (`person_id = contact:<id>` with no `people`
  row yet): surfaces as a **review suggestion "Is this [contact name]?"**,
  rendering the cached contact photo (cropped to `bounding_box_json`) as the
  reference beside the candidate catalog face. It is **not** auto-applied — you
  can't attach a tentative face to a person who doesn't exist yet, and this
  honors the "prominent, review-first for people" invariant.
  - **Confirm** → `upsertPerson(id: "contact:<id>", name:)` + `assignFaces`
    (`origin='user'`): the person becomes real and confirmed.
  - **Reject** → `rejected_face_people` (sticky), so it isn't re-suggested.

Latent-contact suggestions need their name and reference image threaded into the
review surface: the suggestion builder's name lookup (`personNamesByID`, built
from `catalogPeople`) is unioned with the reference names for `contact:` ids,
and the review card gains an optional reference-image slot fed by the cached
contact photo + box.

## Provenance & invariant compliance

- The **name** comes from the user's own address book (trustworthy), but "this
  catalog photo *is* this person" is always a **proposal** — never
  auto-confirmed. Existing-person matches land `origin='ai'` (tentative, never
  destructive/export/Picks until confirmed); latent-contact matches create no
  person at all until confirmed.
- No unconfirmed-only "phantom" contact people ever appear in the confirmed
  People list — latent contacts have no `people` row until a match is
  confirmed.
- Reference embeddings and the contact photo cache are recognition inputs; they
  are never written to `.xmp` sidecars (identity has no XMP field) and never
  modify original image bytes.

## Entitlements & permissions (the plumbing)

- Add `com.apple.security.personal-information.addressbook` (true) to
  `config/macos/Teststrip.entitlements` (the worker keeps `.inherit` only — it
  does not touch Contacts).
- Add `NSContactsUsageDescription` to the Info.plist heredoc in
  `script/lib/app_bundle.sh` (and the dev-build plist in `build_and_run.sh` if
  it emits a separate one), with a clear purpose string.
- Signing already applies entitlements (`script/package_release.sh`,
  `build_and_run.sh`) — no signing change beyond the added key.

## Non-goals (YAGNI)

- No automatic/background seeding — explicit action only.
- No contact picker — seed all contacts with a photo.
- No auto-prune of references for contacts later deleted from the address book.
- No caching of contacts without a detectable face.
- No new "proposed people" gallery surface beyond the existing face-suggestion
  review (the full prominent-people surface remains a later sub-project).
- No changes to the worker, the embedding model, or catalog capture.

## Testing

- **Repository tests.** The reference table round-trips (upsert by
  `contact_identifier`, `photo_hash` idempotency); `contactReferenceEmbeddingsByPerson`
  groups by `person_id`; name-attach resolves to an existing person's id while a
  no-match contact gets a `contact:<id>` id.
- **Matching/seeding logic tests** (no live Contacts — inject contact records
  and CGImages through a seam so the test provides the data): a reference for a
  latent contact makes a matching catalog face surface as an "Is this [name]?"
  suggestion carrying that name; confirming it creates the person
  (`upsertPerson` + `person_faces.origin='user'` + `person_assets`); rejecting
  records `rejected_face_people`; a reference name-attached to an existing
  person routes matches to that person as `origin='ai'` (its Proposed section),
  creating no duplicate. Assert the negative: a latent contact with **no**
  catalog match creates **no** `people` row.
- **Contacts access is abstracted behind a protocol** (a `ContactsProvider`
  seam returning `(identifier, name, imageData)` records) so seeding is unit
  testable with fixed inputs and the live `CNContactStore` is one small
  conformer — never mocked in a way that tests the mock.
- **End-to-end scenario card** (VM-bound, authored not run): run "Import faces
  from Contacts" against seeded VM contacts, confirm a latent-contact suggestion
  shows the contact photo and creates a confirmed person on accept, and that an
  existing-person recall boost lands in that person's Proposed section. Assert
  against catalog ground truth (`contact_reference_faces`, `people`,
  `person_faces.origin`, `person_assets`, `rejected_face_people`).

## Open decisions (resolved)

- **When contacts become people:** latent pool — a person materializes only on a
  confirmed match; unmatched contacts leave no visible person.
- **Trigger/scope:** explicit "Import faces from Contacts", all contacts with a
  photo, idempotent by `contact_identifier`.
- **Storage:** the derived embedding + name + the cached contact photo (the
  photo is the reference image shown in the review card).
- **Dedup:** attach a contact reference to an existing same-named person by
  case-insensitive name; otherwise latent.
- **Latent-contact matches are review-first**, not auto-applied.
