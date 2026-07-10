# worker-003-face-pipeline: Re-processed assets replace face observations, then batch into suggestions

**What this covers**: the face-detection provider **replaces** prior face
observations for a re-processed asset rather than appending duplicates
(`CatalogRepository` DELETE-then-INSERT under the same
provider/model/version/settings_hash, `Sources/TeststripCore/Catalog/CatalogRepository.swift:1001-1020`),
and `FaceSuggestionBuilder` batches up to 2000 unassigned observations into
face-group suggestions
(`AppModel.maximumFaceSuggestionInputCount`, `Sources/TeststripApp/AppModel.swift:3251`,
consumed at `AppModel.refreshPeopleFaceSuggestions`, `AppModel.swift:3253-3260`).

## Pre-state
```bash
./script/download_face_model.sh
./script/build_and_run.sh --faces
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--faces` is a confirmed `build_and_run.sh` mode (`./script/build_and_run.sh
--help` lists `--faces`/`--verify-faces`); it seeds the astronaut corpus per
`people-003-cluster-identity.md`'s Pre-state (Glenn ×4, Ride ×4, Armstrong ×1,
Aldrin ×1). If the face model cannot be downloaded, this card is **blocked on
the model host**, same as people-003 — say so and stop; no embeddings, no
suggestions, by design.

## Steps
1. `script/ax_drive.sh wait-vended`, open People, wait for the face-work
   queue to drain (as in `people-003-cluster-identity.md` Step 1).
2. **Record the observation baseline for one asset.**
   ```bash
   ASSET_ID=$(sqlite3 "$DB" "SELECT asset_id FROM face_observations WHERE provider='face-recognition' LIMIT 1;")
   sqlite3 "$DB" "SELECT face_index, provider, model, version, settings_hash FROM face_observations WHERE asset_id = '$ASSET_ID';"
   sqlite3 "$DB" "SELECT count(*) FROM face_observations WHERE asset_id = '$ASSET_ID';"   # call it O1
   ```
3. **Force a re-process of that asset.** Re-run evaluation for `$ASSET_ID`
   with the face provider (Evaluate action in the inspector, or the
   equivalent grid command — confirm the control's AXHelp against the
   running UI). Wait for it to complete
   (`sqlite3 "$DB" "SELECT status FROM work_sessions WHERE id LIKE 'evaluation-$ASSET_ID%' ORDER BY updated_at DESC LIMIT 1;"`
   until `completed`).
4. **Assert replace, not append.**
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM face_observations WHERE asset_id = '$ASSET_ID';"   # call it O2
   ```
   `O2` must equal `O1` (same face count re-detected on the same image), not
   `2 * O1` or greater. Cross-check `face_index` values are the original set,
   not a second interleaved set — `SELECT face_index FROM face_observations
   WHERE asset_id = '$ASSET_ID' ORDER BY face_index;` should show no
   duplicate indices.
5. **Assert the 2000-item batch cap is honored.** This corpus (10 photos) is
   far below the cap, so directly exercising 2000+ observations is
   impractical for a card — instead confirm the cap is wired by reading the
   call site: `AppModel.refreshPeopleFaceSuggestions` passes `limit:
   Self.maximumFaceSuggestionInputCount` (2000) to
   `catalog.repository.unassignedFaceObservations(provenance:limit:)`
   (`AppModel.swift:3253-3260`; repository query at
   `CatalogRepository.swift:1074`). Confirm the SQL actually applies a LIMIT:
   ```bash
   sqlite3 "$DB" "EXPLAIN QUERY PLAN SELECT * FROM face_observations LIMIT 2000;"
   ```
   Report this as source-grounded, not empirically exercised at 2000+ scale —
   name the gap rather than fabricate a large-corpus run.
6. **Re-run grouping and assert suggestions still make sense post-replace.**
   Re-open People (or trigger a suggestion refresh); the group containing
   `$ASSET_ID`'s person should be unchanged in membership (same person, same
   group), proving the replace didn't silently orphan the asset from its
   group. Cross-check via `people-003-cluster-identity.md`'s identity-coherence
   method (map faces back to source filenames).

## Expected
- Step 4: `O2 == O1` exactly. **Fails if** `O2 > O1` (observations appended
  instead of replaced — stale rows accumulate and would corrupt suggestion
  counts and `unassignedFaceObservations` over repeated re-evaluates) or
  `O2 < O1` (a real face silently dropped on re-detect).
- Step 6: **Fails if** `$ASSET_ID`'s faces vanish from every suggested group
  after the replace, or land in a group with a different person.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- `CatalogRepository`'s replace is scoped to the same
  `(provider, model, version, settings_hash)` tuple
  (`CatalogRepository.swift:1001-1010`) — re-processing with a *different*
  model/version does not replace, it adds a second provenance's rows
  alongside the first (by design, so an old provider's rows can be
  invalidated separately). Don't mistake a provenance change for a dedup
  failure.
- The DELETE also cascades to `person_faces`/`dismissed_faces` for the asset
  **only when the detected bounding boxes actually changed**
  (`previousBoxes != newBoxes` guard, `CatalogRepository.swift:994-997`) — a
  byte-identical re-detect on an unmodified source image will *not* clear an
  existing person assignment or dismissal, which is correct but easy to
  misread as "replace didn't happen."
- The 2000-cap Step 5 is source-grounded only; no fixture in this repo
  currently produces 2000+ face observations, so the cap's actual truncation
  behavior (which 2000 of N, sort order) is untested end-to-end. Flagged as
  an open question below.

## Run status
Source citations (replace logic, 2000 cap, call sites) were grep-confirmed
against `Sources/TeststripCore/Catalog/CatalogRepository.swift` and
`Sources/TeststripApp/AppModel.swift` on 2026-07-10; the `--faces` flag was
confirmed via `./script/build_and_run.sh --help`. No SQL was run against a
live `--faces` catalog in this session (requires the downloaded face model,
not fetched here) — Steps 1-4 and 6 need a human-present or console-unlocked
re-run with the model available.
