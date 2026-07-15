# people-022-proposed-and-key-photo: a person's Proposed section + key-photo card

**What this covers**: the People-surfacing sub-project — the per-person
Proposed section (inline ✓ confirm / ✗ reject) and the best-confirmed-face key
photo on People cards. Exercises `proposedPersonFaces`, `keyFacesByPerson`,
`confirmProposedPhoto`, `rejectProposedPhoto`.

## Pre-state
A freshly built, isolated app instance seeded with real face photos (VM +
AuraFace). At least one person confirmed with a face-level assignment (so a key
face exists) and at least one un-confirmed AI face proposal for that same
person on a different asset. Follow `script/vm_scenario_run.sh` setup/sync.

## Steps
1. Open the People view; find the confirmed person's card. → **Expected:** the
   card shows a cropped face photo, not a colored gradient circle. Falsification:
   if it still shows a gradient circle for a person who has a confirmed face,
   FAIL.
2. Click the person to open their photos (the `person:"Name"` grid). →
   **Expected:** confirmed photos in the main grid, and a separate "✨ Proposed"
   section below with the AI-proposed photo(s). Falsification: no Proposed
   section when a proposal exists, or the proposed photo appears in the main
   confirmed grid, FAIL.
3. Click ✓ (bottom-trailing) on a proposed cell. → **Expected:** the photo
   leaves Proposed and appears in the confirmed grid. Assert catalog ground
   truth: `SELECT origin FROM person_faces WHERE asset_id=<that asset>` is
   `user`, and a `person_assets` row exists for (person, asset). Falsification:
   the row stays `ai` or no `person_assets` row, FAIL.
4. Reopen the person; click ✗ (top-leading) on another proposed cell. →
   **Expected:** the photo leaves Proposed. Assert `SELECT 1 FROM
   rejected_face_people WHERE asset_id=<that asset> AND person_id=<person>`
   returns a row, and the `origin='ai'` `person_faces` row is gone.
   Falsification: a `rejected_face_people` row is absent, FAIL.
5. Re-run a face scan/recognition. → **Expected:** the rejected photo does NOT
   reappear in Proposed. Falsification: it reappears, FAIL.

## Cleanup
Discard the isolated app-support dir created for this run (per
`test/scenarios/README.md` isolated-launch teardown). Touch no real catalog.

## Sharp edges
- Proposed cells only render for a lone `person:` filter; adding any other
  token clears the section.
- Key photo requires a face-level confirmation; a whole-asset-confirmed person
  correctly shows the gradient fallback — don't read that as a bug.
