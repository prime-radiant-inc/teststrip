# people-021-face-group-review: Review a face group large, prune it, then name

**What this covers**: the face-group review surface (sub-project 2,
`Sources/TeststripApp/FaceGroupReviewView.swift` +
`AppModel.faceGroupReview(for:)` / `removeFaceFromReviewGroup`). A suggestion
card ("Is this X?" / "Who is this?") is now a **link into a review sheet**, not
a one-tap confirm: the sheet shows every face in the group large and zoomed to
the face; hovering/clicking a tile reveals the whole photo; a per-tile ✕ removes
that face from the group (a sticky reject for a matched person, a dismiss for a
new cluster); a bottom bar confirms/names the person over the faces that remain.
Review-first: look, prune, then name. This card asserts (a) removing a face
before confirming writes **no** person assignment and shrinks the group, and
(b) confirming the remainder links only the kept faces.

## Pre-state
- Fresh build against a corpus that actually contains faces (the synthetic
  `--isolated` seed has none). Use the dedicated face corpus and download the
  identity model first so match/cluster suggestions are produced:
  ```bash
  ./script/download_face_model.sh
  ./script/build_and_run.sh --faces
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
  `--faces` seeds 11 Wikimedia portraits with same-person clusters (Glenn ×4,
  Ride ×4, Armstrong ×2, Aldrin ×1), so grouping has real groups to form.

## Steps
1. **Record the baseline** (ground truth):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM person_faces WHERE origin='user';"  # UF0 (confirmed faces)
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"                     # L0
   sqlite3 "$DB" "SELECT count(*) FROM rejected_face_people;"              # R0
   ```
2. **Open People from the Library view toggle.** `script/activate_app.sh
   Teststrip`; People is no longer ⌘3 — AX-press the Library sub-view toggle
   segment labeled **"People"** (the toggle beside Grid | Loupe | Timeline |
   Map). `waitFor` a suggestion card or the header `AXStaticText` matching
   **"N people · M photos with face signals"** (M ≥ 1). Face work is async;
   let the Activity queue drain.
3. **Open a group for review.** AX-press a suggestion card (its Review link;
   help text **"Review these faces before naming them"** or **"Review this
   group before confirming …"**). A review sheet opens titled **"Is this X?"**
   or **"Who is this?"** with a grid of large face tiles.
4. **Assert nothing is written just by reviewing** (invariant):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM person_faces WHERE origin='user';"  # must equal UF0
   sqlite3 "$DB" "SELECT count(*) FROM rejected_face_people;"              # must equal R0
   ```
5. **Remove a face from the group.** AX-press one tile's ✕ (AXHelp **"Remove
   this face from the group"** / label **"Remove face"**). The tile disappears
   and the header count drops by one.
6. **Assert the removal wrote a rejection / dismissal, not an assignment**
   (invariant):
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM person_faces WHERE origin='user';"  # still UF0 — no confirm happened
   sqlite3 "$DB" "SELECT count(*) FROM rejected_face_people;"              # R1: for an "Is this X?" group, R1 = R0 + 1
   ```
   For a "Who is this?" (new cluster) group the removed face is dismissed
   (`dismissed_faces` gains a row) and `rejected_face_people` stays at R0.
7. **Confirm the remainder.** For "Is this X?" press the confirm bar's button
   (labeled with the person's name); for "Who is this?" press **"Name…"**, type
   a name, and confirm the naming sheet.
8. **Assert the confirm linked only the kept faces**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM person_faces WHERE origin='user';"  # UF1 > UF0
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"                     # L1 > L0
   ```

## Expected
- Step 2: People opens from the toggle (not a workspace switch); M ≥ 1 and at
  least one suggestion card. **Fails if** People is still reachable only as a
  top-level ⌘3 workspace, or the corpus yields no face signals (fixture gap —
  report the corpus).
- Step 4: `person_faces(user)` and `rejected_face_people` unchanged — merely
  opening the review writes nothing. **Fails if** either rose; confirm-before-
  write violation.
- Step 6: `person_faces(user)` unchanged (no assignment on remove); an
  "Is this X?" removal adds exactly one `rejected_face_people` row. **Fails if**
  removing a face confirmed it, or wrote a person assignment.
- Step 8: `UF1 > UF0` and `L1 > L0`, and the linked faces exclude the one
  removed in step 5. **Fails if** the removed face was linked anyway (prune not
  honored) or nothing was written.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Face detection/matching is asynchronous; don't conclude "no suggestions"
  (step 2) until the face-work queue in Activity has drained.
- Two group kinds behave differently on remove: a matched "Is this X?" group's
  removal is a **sticky reject** (`rejected_face_people`) so the person is not
  re-proposed for that face; a "Who is this?" cluster's removal is a **dismiss**
  (`dismissed_faces`). Assert against the right table per the card title.
- The review sheet is a pure projection of the live suggestion — after a remove
  it rebuilds from the refreshed `peopleFaceSuggestions`; removing the last face
  shows a "Nothing left to review" completion state, not a stale grid.
- Assert against catalog ground truth, not the render: the grid can lag the
  SQL. Cross-check any named person against its `people` row (the view must not
  show a person the table doesn't back).

## Run status
NOT-RUN — authored alongside the implementation; VM-bound AX driving not
executed here. SQL columns match
`Sources/TeststripCore/Catalog/CatalogMigrations.swift`
(`person_faces.origin`, `rejected_face_people`, `dismissed_faces`).
