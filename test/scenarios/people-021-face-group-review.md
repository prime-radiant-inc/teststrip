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
2. **Open the People lens.** `script/activate_app.sh
   Teststrip`; press ⌘6, or AX-press the toolbar lens switcher's segment
   labeled **"People"** (the switcher's six segments: Cull | Grid | Loupe |
   Timeline | Map | People). `waitFor` a suggestion card or the header `AXStaticText` matching
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
- Step 2: People opens as its own lens (⌘6 or the switcher segment); M ≥ 1 and
  at least one suggestion card. **Fails if** People is reachable only via ⌘3
  or a Library sub-view toggle (both stale, pre-unified-shell routes), or the
  corpus yields no face signals (fixture gap — report the corpus).
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

**Reconciled 2026-08-09 (Task 13, unified-shell survivor sweep)**: Step 2
described an intermediate, pre-unified-shell era where People had already
left the top-level ⌘3 workspace slot but was reached as a Library sub-view
toggle rather than its own key. Under the unified shell People is one of
the six top-level `LibraryLens` cases again, reached directly by ⌘6 or the
toolbar lens switcher's "People" segment — there is no Library sub-view
toggle any more (`LibraryLens.keyEquivalent`, `LibraryLens.swift:35-43`).
Rewrote Step 2 and its Expected bullet accordingly. Preamble only; the
review/prune/confirm assertions don't depend on how People was reached.
Supersedes prior status: no prior run evidence exists to invalidate (still
NOT-RUN).

## Run status — 2026-09-14 (live VM run, batch 7)

**VERIFIED** — first live run of this card. Tart VM `teststrip-e2e`,
`script/vm_scenario_run.sh launch faces`, run dir `faces-1789385338` (11 assets;
baseline `person_faces(user)`/`person_assets`/`rejected_face_people`/`dismissed_faces`
= 0/0/0/0). Steps 1-8 driven live; all assertions passed.

- **Step 2 PASS** — ⌘6 opens the People lens (`Teststrip – People`). The header
  read `0 people · 11 photos with face signals` (M = 11 ≥ 1). **A fresh `--faces`
  launch seeds the catalog without scanning** (`face_observations` = 0, no
  suggestion card rendered); an explicit People ▸ **Scan for Faces**
  (`ax press --role AXMenuItem --label "Scan for Faces"`) produced 11
  `face_observations` in ~2 s, then two suggestion cards:
  `Who is this?, 4 faces · 4 photos, group 1 of 2` and `… group 2 of 2`, both with
  help `Review these faces before naming them`. (Card-drift note: Step 2's
  "let the Activity queue drain" implies an implicit scan; on this seeded
  fixture the Scan for Faces trigger is required first.)
- **Step 3 PASS** — pressing the group-1 card opened the review sheet
  (title `Who is this?`, header `4 faces · 4 photos`, four large face tiles each
  with a `Remove face` ✕ and a `Name` button, bottom-bar `Name…`).
- **Step 4 PASS (invariant)** — merely opening the sheet left
  `person_faces(user)` = 0 and `rejected_face_people` = 0 (unchanged from baseline).
- **Step 5 PASS** — `Remove face` on the first tile shrank the sheet header
  `4 faces · 4 photos` → `3 faces · 3 photos` and the tile disappeared.
- **Step 6 PASS** — `person_faces(user)` stayed 0, `person_assets` stayed 0,
  `rejected_face_people` stayed 0, and `dismissed_faces` gained exactly one row
  (`17A2FF33-… | 0`) — the documented **"Who is this?" new-cluster dismissal**
  branch, not an assignment. (Removal never confirmed the face.)
- **Steps 7-8 PASS** — `Name…` → `Name Face Group` sheet → typed `Glenn Group` →
  `Create Person`. Result: `person_faces(user)` 0 → **3**, `person_assets` 0 → **3**,
  one `people` row `Glenn Group`; the view rendered `Glenn Group` / `3 confirmed
  photos`. The removed face (`commons-ride-1984-portrait.jpg`) is **not** linked
  (`SELECT count(*) FROM person_faces WHERE asset_id='17A2FF33-…'` = 0); the three
  linked faces are the other Ride portraits (`commons-ride-astronautin`,
  `commons-ride-sts7`, `commons-ride-sts7-cockpit`) — **the prune was honored**.
- Confirm-before-write held throughout: no `person_faces(user)` row and no
  `person_assets` row existed until `Create Person`.

**Branch coverage note (honest cap):** only the "Who is this?" cluster branch of
Step 6 was reachable on this corpus. The two suggestion groups are both unnamed
clusters; a People-lens suggestion card can only read `Is this X?` when
`FaceSuggestionBuilder` returns a `matchExisting` against a *confirmed* person
centroid (`AppModel.swift:4593-4609`), and re-running Scan for Faces after naming
`Glenn Group` produced no `matchExisting` card (still `Who is this?, 4 faces ·
4 photos, group 1 of 1`) — the named centroid is a Ride cluster, which the
remaining Glenn cluster does not match. So the `Is this X?` →
`rejected_face_people` half of Step 6 remains structurally unexercised here.

**Citation corrected live:** the 2026-08-09 reconciled note's
`LibraryLens.keyEquivalent` citation `LibraryLens.swift:44-51` was stale; the
property is at `LibraryLens.swift:35-43` (enum `:10-17`, `.title` `:20-28`,
`defaultViewMode` `:47-55`). No step or assertion changed.
