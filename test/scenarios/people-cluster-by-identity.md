# people-cluster-by-identity: Automatic grouping clusters by face identity

**What this covers**: automatic face grouping on a real multi-person corpus
clusters the same person's faces together and keeps different people apart,
using the bundled ArcFace face-identity embedding (not the old whole-image
feature print). This is the exact failure that existed before: the previous
embedding merged Buzz Aldrin into a John Glenn group because no distance
threshold could separate identities from a general image descriptor.

**Falsification**: two confirmed-different people appear in one suggested
group, OR one person's faces split across multiple un-mergeable groups, OR the
astronaut corpus still merges Aldrin into a Glenn group.

## Pre-state
- Download the face-identity model, then build against the face corpus:
  ```bash
  ./script/download_face_model.sh
  ./script/build_and_run.sh --faces
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
  `--faces` downloads `sample-data/faces.tsv` — public-domain Wikimedia Commons
  portraits: John Glenn ×4, Sally Ride ×4, Neil Armstrong, Buzz Aldrin. Glenn
  and Ride each recur, so same-person clusters must form; Aldrin and Armstrong
  are the different-person controls that must NOT be absorbed.
- If `./script/download_face_model.sh` cannot fetch the model (the artifact is
  not yet hosted — see `# TODO(host)` in `sample-data/face-recognition-model.tsv`),
  this card is **blocked on the model host**, not a code failure: say so and
  stop. Without the model, no identity embeddings are produced and grouping is
  disabled by design.

## Steps
1. **Open People and let grouping drain.** `script/ax_drive.sh wait-vended`;
   AX-press the top-bar **"People"** mode item. `ax_drive.sh wait --role
   AXStaticText --contains "photos with face signals"`. Face detection +
   embedding are async — wait for the face-work queue in Activity to drain
   before reading suggestions.
2. **Read the suggested groups from ground truth.** The suggestion cards render
   unconfirmed clusters. Cross-check against the catalog's face observations and
   the clustering result rather than trusting the render:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM face_observations WHERE provider='face-recognition';"
   ```
   Expect one row per detected face under the `face-recognition` provenance
   (old `apple-vision` feature-print rows, if any, are inert).
3. **Assert identity coherence.** For each suggested group, every face in it
   must belong to one person (map each face's asset back to its Glenn / Ride /
   Armstrong / Aldrin source filename). No group may contain two people.
4. **Assert same-person grouping.** Glenn's four photos form one group and
   Ride's four photos form one group (each a multi-face cluster). Aldrin and
   Armstrong, appearing once, stay ungrouped singletons — never folded into
   Glenn or Ride.

## Expected
- Step 2: face-recognition observations present (≥ 8 across the corpus).
  **Fails if** none — that's the model/fixture gap (model not downloaded), not
  a grouping bug; report which prerequisite is missing.
- Step 3: no suggested group mixes two people. **Fails if** any group contains
  faces from two different astronauts (the pre-fix behavior). Quote the
  offending group's members.
- Step 4: a Glenn multi-face group and a Ride multi-face group both exist, and
  Aldrin is not a member of any Glenn group. **Fails if** Glenn's or Ride's
  faces are scattered across un-mergeable groups, or Aldrin/Armstrong is
  absorbed into a same-person cluster.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Detection and embedding lag the view opening; don't conclude "no groups"
  until the face-work queue has drained.
- The unit-level guarantee is locked by `FaceCorpusGroupingTests
  .testAstronautCorpusClustersByIdentity`; this card proves the same behavior
  end-to-end through the assembled People UI. Both are needed.
- Grouping filters reads to the `face-recognition` provenance, so a catalog
  evaluated before this model existed needs a re-evaluate pass (the standard
  Evaluate path) to populate identity embeddings before groups appear.
