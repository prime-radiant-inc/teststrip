# people-020-ai-label-provenance: AI labels auto-apply as `origin=ai` (✨), confirm writes the sidecar, and a tentative autopilot reject stays unrelocated until confirmed

**What this covers**: Task 17 of the machine-label-provenance feature
(`docs/superpowers/specs/2026-07-14-machine-label-provenance.md`,
`docs/superpowers/plans/2026-07-14-machine-label-provenance.md`) — the model
inversion from confirm-before-write to **auto-apply with provenance**: scene
keywords, face/person matches, and autopilot pick/reject flags now write to
the catalog immediately, tagged `origin = ai` (unconfirmed, shown ✨), and stay
catalog-only until an explicit confirm gesture flips them to `origin = user`
and (for sidecar-eligible fields) writes the `.xmp`. This is the end-to-end
counterpart to the unit suite (`Tests/TeststripAppTests/AppModelTests.swift`,
`Tests/TeststripCoreTests/*`) — it drives the same mechanics through the
assembled AppKit UI and asserts against the live catalog/filesystem, not a
mock.

Source (current working tree, `feat/unified-shell`):
- **Promotion** (auto-apply): `AppModel.promoteMetadataLabels(for:)`
  (`Sources/TeststripApp/AppModel.swift:8678-8705`, floor
  `objectKeywordConfidenceFloor = 0.5` at `:8285` — an `.object` evaluation
  signal at/above this confidence adds each label to `keywords` +
  `aiUnconfirmedKeywords`) and `AppModel.promoteFaceMatches(for:)` (`:3772-3795`,
  with centroid provenance at `:3611-3617` —
  matches unassigned faces against **confirmed-only** (`origin='user'`)
  person centroids and inserts a face-level `origin='ai'` `person_faces` row,
  **never** a `person_assets` row). Both are wired into the post-evaluation
  path by `promoteEvaluationResults(for:)` (`:10499-10509`), called once per
  `(asset, provider)` evaluation completion — **not** by any UI
  navigation/refresh gesture (see Sharp edges).
- **Confirm/remove**: `confirmAIKeyword`/`removeAIKeyword` (`:8328`/`:8343`),
  `confirmAIField`/`removeAIField` (`:8358`/`:8378` — `.caption`/`.flag`/
  `.rating`), `confirmAIFace`/`rejectFaceSuggestion` (`:3948`/`:3962`).
  Confirming a keyword/caption/field writes the `.xmp` (via the existing
  `applyMetadataSnapshot` sidecar-sync path); confirming a face flips
  `person_faces.origin` to `user` and upserts `person_assets`, and writes
  **no** sidecar (identity has no XMP field).
- **Sidecar confirmed-only projection**: `AssetMetadata.confirmedProjection`
  (`Sources/TeststripCore/Domain/Metadata.swift:55-64`) is applied at the
  `XMPPacket` write layer (`Sources/TeststripCore/Metadata/XMPPacket.swift:62`)
  — keywords in `aiUnconfirmedKeywords` and fields in `aiUnconfirmedFields`
  are dropped before anything reaches disk, regardless of which write path
  fires.
- **Autopilot fold-in**: `AppModel.runAutopilotOnCurrentScope()`
  (`AppModel.swift:10146-10158`, on-demand — Culling ▸ **Run Autopilot**, item 39 of
  `app-012-autopilot-evaluate-commands.md`) → `runAutopilot(scope:)` →
  `applyTentativeAutopilotProposals(_:)` (`AppModel.swift:10086-10133`) writes each
  `.pick`/`.reject` proposal into `metadata.flag` **immediately**, marked
  `aiUnconfirmedFields = [.flag]`, unless the asset already carries a
  **confirmed** flag (`hasConfirmedFlag` guard, `AppModel.swift:10102-10105`) — this is the
  headline behavior change from the pre-provenance model: the tentative
  write itself (the "ghost," `AutopilotGhost.kind(in:)`) lands in
  `metadata_json` immediately; SP-D0 later dropped the `autopilot_proposals`
  table outright, so there is no separate proposal row at all any more —
  the ghost sitting in the asset's own metadata is the whole record, and the
  catalog write never waited for a Commit in the first place.
- **Tentative-flag exclusion (safety-critical)**: `rejectRelocationScope`
  (`AppModel.swift:12561-12605`) skips any candidate whose `aiUnconfirmedFields.contains(.flag)`
  (`AppModel.swift:12583-12585`) before it can ever reach a `RejectRelocationPlan` — a tentative
  AI reject can never be included in Move Rejects (folder) or Move Rejects to
  Trash, which share this one scope function. `RejectRelocationPreflight.moveCount`
  (`Sources/TeststripApp/AppModel.swift:1444`) and `confirmationText`
  (`AppModel.swift:1448-1450`) reflect
  the same confirmed-only count, so the sheet's own button label ("Move N
  reject photo(s) to `<folder>`") is a live, AX-visible witness of the
  exclusion.
- **UI affordances** (Task 14): `InspectorView.swift` keyword chips render a
  ✨ (`DesignGlyph.ai` = SF Symbol `sparkles`) plus a `Confirm keyword <kw>` /
  `Remove keyword <kw>` accessibility-labeled icon button pair for an
  unconfirmed chip (`:1098-1150`); an unconfirmed caption gets its own
  "AI-suggested caption" row with plain `Confirm`/`Remove` buttons
  (`:1152-1176`). `PhotoFacesSectionView.swift` marks a `.suggested` face row
  with the same ✨ glyph and `Confirm`/`Remove` buttons (`:74-104`) — Remove on
  a suggested face calls `rejectFaceSuggestion` (records `rejected_face_people`
  so the match never resurrects, per the `9e7b6101` fix), not a plain
  unassign.
- **Known-stale cross-references**: `cull-017-autopilot-review.md` and
  `app-012-autopilot-evaluate-commands.md` predate this branch and describe
  the *old* "nothing in `metadata_json` until Commit" semantics for autopilot
  — their UI-surface assertions (banner text, KEEP/CUT badges, Commit/Commit
  all/Undo all button labels) are still accurate, since none of that wiring
  changed (Task 12's report: "none of their signatures changed, so no
  UI-side edits were needed"), but their "confirm-before-write: nothing
  commits without Review" framing for `metadata_json` is now wrong for
  pick/reject/keyword — this card supersedes that specific claim.

## Pre-state

Two independent legs need different fixtures/gating:
- **Keyword/caption promotion and autopilot** need only real photo content
  (any real JPEG triggers Apple Vision's `VNClassifyImageRequest` scene
  classifier) — no model download required.
- **Face-match promotion** additionally needs the AuraFace embedder present
  (`AppleVisionEvaluationProvider.faceObservations` returns `[]` outright
  without it, per `inspect-010-photo-faces.md`'s Sharp edges — that gating is
  unchanged by this feature).

```bash
ROOT_DIR="$(git rev-parse --show-toplevel)"
./script/download_face_model.sh   # AuraFace-v1 — see Sharp edges: download may fail (dev-008 gap)
script/vm_scenario_run.sh sync faces
script/vm_scenario_run.sh launch faces   # prints "launched 'faces' fresh at $FRESH" — capture $FRESH, needed again before step 16
script/vm_scenario_run.sh ax wait-vended Teststrip
# ground truth via: script/vm_scenario_run.sh sql faces "..."
```
(Host equivalent: `./script/download_face_model.sh && REJECTS_DIR=$(mktemp -d)/rejects TESTSTRIP_REJECT_DESTINATION_DIR="$REJECTS_DIR" ./script/build_and_run.sh --faces` —
the reject-destination override must be set at **launch**, not mid-run.)

**VM note — `vm_scenario_run.sh launch` has no env-var passthrough beyond
`TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY`** (`cmd_launch`,
`script/vm_scenario_run.sh:246-271`, hardcodes exactly one `--env`). There is
no built-in way to set `TESTSTRIP_REJECT_DESTINATION_DIR` through `launch`.
Work around it right before step 16 (not at initial launch, so evaluation/
promotion/autopilot above run against the normal launch first) via the
`shell` verb, relaunching the **same** already-populated `$FRESH` app-support
directory with the extra env var (the catalog is on disk and survives a
process restart):
```bash
REJECTS_DIR=/tmp/vm-rejects   # any remote path the VM user can create
script/vm_scenario_run.sh shell "pkill -x Teststrip; sleep 1; open -n '$REMOTE_ROOT/dist/Teststrip.app' --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY='$FRESH' --env TESTSTRIP_REJECT_DESTINATION_DIR='$REJECTS_DIR'"
script/vm_scenario_run.sh ax wait-vended Teststrip
```
(`$REMOTE_ROOT` is whatever `vm_scenario_run.sh`'s own remote root is — check
`script/vm_scenario_run.sh shell 'echo $HOME'`/its `REMOTE_ROOT` constant if
unsure. This relaunch-with-extra-env-var workaround is itself unproven live;
flag if `open -n` behaves differently under `shell` than under `launch`.)

`--faces` seeds `sample-data/photos/faces` (11 real JPEGs of Glenn/Ride/
Armstrong/Aldrin, per `sample-data/faces.tsv`) via a plain folder import —
unlike `--smoke`, nothing is pre-flagged/pre-rated. **One file ships with a
pre-existing sidecar**: `commons-aldrin-portrait.jpg.xmp` (checked into the
repo) — never use Aldrin's photo for a "no sidecar yet" assertion; this card
uses Glenn/Ride/Armstrong photos throughout, per `inspect-010`'s precedent.

There is no shared filesystem between host and VM — `vm_scenario_run.sh`
only moves bytes over `rsync`/`ssh` — so a host `ps`/`sqlite3` scan against
the VM's isolated dir finds nothing. Every catalog read in this card is
`script/vm_scenario_run.sh sql faces "<SQL>"` instead, which resolves the
freshest `faces-*` run directory itself (no need to plumb `$FRESH` through
a `$DB` variable) — the same substitution `cull-002-loupe-navigation.md`
documents for its own VM fallback ("`sql smoke ...` in place of the direct
calls below").

**Baseline (confirm-before-write / auto-apply-with-provenance, pre-evaluation)**:
```bash
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM assets;"                                              # 11
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.aiUnconfirmedKeywords') IS NOT NULL;"  # 0 (key is omitted when empty)
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE origin='ai';"                      # 0
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM removed_ai_labels;"                                   # 0
script/vm_scenario_run.sh sql faces "SELECT count(*) FROM evaluation_signals;"                                  # 0 (unevaluated)
find "$ROOT_DIR/sample-data/photos/faces" -name '*.xmp'                                    # only commons-aldrin-portrait.jpg.xmp — host-side fixture check, unaffected by the VM run
```

## Steps

### 1. Evaluate everything — the one trigger that covers keywords, faces, and autopilot's signal inputs
1. `ax wait-vended`; ⌘2 for Library; confirm all 11 thumbnails are present
   (scroll if needed — the grid is lazily virtualized).
2. Wait for cached previews (`worker-001-preview-lifecycle.md`'s pattern),
   then **Culling ▸ Evaluate Visible** (⇧⌘E):
   `ax press --role AXMenuItem --label "Evaluate Visible"` (menu items are
   just another AX element `ax_drive.sh`'s walker reaches — no need to open
   the Culling menu bar title first, per `people-009-scan.md`'s identical
   `--role AXMenuItem` usage for "Scan for Faces"). This calls
   `requestVisibleAssetEvaluations(providers: defaultEvaluationProviderNames)`
   = `["local-image-metrics", "apple-vision", "core-image-faces"]`
   (`AppModel.swift:2683`) — **apple-vision is in this list**, so this
   one pass also produces `face_observations` (the same code path
   `People ▸ Scan for Faces` uses, per `people-009-scan.md`) and gives
   autopilot richer signals than a face-only scan would. Keep the app warm
   (re-assert frontmost every poll) while it drains:
   ```bash
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required for the face leg — if 0, the AuraFace model didn't load (stop and flag, don't force the face leg)
   ```

### 2. Keyword promotion (✨), confirm-before-write, then confirm it
3. **Find what actually promoted** (don't assume a specific label — Vision's
   confidence on this corpus isn't established by this card):
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT id, original_path, json_extract(metadata_json,'\$.aiUnconfirmedKeywords') FROM assets WHERE json_extract(metadata_json,'\$.aiUnconfirmedKeywords') IS NOT NULL;"
   ```
   If **no** asset has a non-null `aiUnconfirmedKeywords`, no `.object` signal
   cleared the 0.5 floor on this 11-photo corpus — note it as a fixture gap
   (mirroring `cull-021-stack-rail-nav.md`'s honesty pattern) and retry
   against a larger real corpus (`sample-data/photos/jesse-pictures`, 79
   photos, per `activity-007-per-kind-lanes.md`'s fixture) before concluding
   the promotion path is broken. Otherwise pick one asset/keyword
   (`KW_ID`/`KEYWORD`) and cross-check the raw signal:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT value_json, confidence FROM evaluation_signals WHERE asset_id='$KW_ID' AND kind='object';"
   ```
   Confirm `confidence >= 0.5` and `KEYWORD` appears in `value_json`.
4. **Confirm-before-write checkpoint**:
   ```bash
   SRC=$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$KW_ID';")
   ORIG_SUM=$(shasum "$SRC" | awk '{print $1}')
   test ! -e "$SRC.xmp" && echo "no sidecar yet: OK"
   ```
5. **Drive to it and see the ✨.** ⌘2 Library → double-click `$SRC`'s grid
   cell (opens Cull loupe) → ⌘I. Assert the keyword chip's Confirm button
   exists — this is the AX-drivable proxy for `isUnconfirmed`, since the ✨
   glyph itself is a plain `Image` beside the chip text with no independent
   accessibility label (same "the ✦/✨ marker isn't independently AX-findable"
   trap `cull-021-stack-rail-nav.md` documents for its own rail chip — assert
   via the Confirm button's presence, not by searching for the glyph):
   ```bash
   ax find --role AXButton --label "Confirm keyword $KEYWORD"
   ax find --role AXButton --label "Remove keyword $KEYWORD"
   ```
6. **Confirm it.** `ax press --role AXButton --label "Confirm keyword $KEYWORD"`.
   Assert:
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT json_extract(metadata_json,'\$.keywords'), json_extract(metadata_json,'\$.aiUnconfirmedKeywords') FROM assets WHERE id='$KW_ID';"
   # keywords still contains KEYWORD; aiUnconfirmedKeywords no longer does (or the whole key is gone if it was the only one)
   test -f "$SRC.xmp" && echo "sidecar written"
   grep -qF "$KEYWORD" "$SRC.xmp" && echo "keyword in xmp"   # dc:subject/rdf:Bag/rdf:li — coarse check per inspect-008's doctrine; dump the file if it fails
   ax find --role AXButton --label "Confirm keyword $KEYWORD"   # now fails — button is gone once confirmed
   NOW_SUM=$(shasum "$SRC" | awk '{print $1}'); [ "$NOW_SUM" = "$ORIG_SUM" ] && echo "original untouched"
   ```

### 3. Face-match promotion (✨, AuraFace-gated): confirmed-only centroid, face-level insert, no `person_assets`
7. **Confirm a face to build a centroid** — `commons-glenn-official.jpg`
   (⌘2 → select → double-click → ⌘I; scroll to the People section, a plain
   `VStack` so no scroll is actually required per `inspect-010`). This is a
   normal, direct **user** gesture (not AI), establishing ground truth to
   match against. Capture baselines for the final non-destructive check
   (step 21) before touching anything:
   ```bash
   GLENN_OFFICIAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg';")
   GLENN_1962_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-1962.jpg';")
   GLENN_OFFICIAL_SRC=$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$GLENN_OFFICIAL_ID';")
   GLENN_1962_SRC=$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$GLENN_1962_ID';")
   GLENN_OFFICIAL_SUM=$(shasum "$GLENN_OFFICIAL_SRC" | awk '{print $1}')
   GLENN_1962_SUM=$(shasum "$GLENN_1962_SRC" | awk '{print $1}')
   ```
   The inspector's People section renders off-screen until the inspector pane
   is scrolled to it (`/tmp/scrollw` warped-scroll at the pane's x). The live
   "Add name" control is a **popover** (`PhotoFacesSectionView`'s
   `addNameButton` → `PersonAutocompleteField`), not the "New person…"/"Create
   Person" sheet the pre-2026-09 card described: `Add name` opens a popover with
   an auto-focused `Name` text field; typing a name that matches no candidate
   yields a `Create "<name>"` row, and **Return** activates it (creating the
   person). The live sequence driven:
   ```bash
   ax press --role AXButton --label "Add name"     # opens the popover (field auto-focused)
   key 'keystroke "John Glenn"'                    # typed into the focused field
   key 'key code 36'                               # Return -> activates Create "John Glenn"
   ```
   ```bash
   JOHN_GLENN_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='John Glenn';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"    # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_OFFICIAL_ID';"  # 1
   ```
8. **Re-evaluate to fire promotion against the new centroid.** Promotion only
   runs from `promoteEvaluationResults`, which fires on a genuine
   evaluation-*completion* event (`invalidateEvaluationSignalsIfNeeded`) — it
   is **not** re-triggered by `nameFace`, by navigating away and back, or by
   any other UI refresh (unlike the old in-memory `peopleFaceSuggestions`
   mechanism `inspect-010-photo-faces.md`'s step 15 relies on, which is a
   *different* code path still used only by the separate multi-asset People
   lens review UI). Select `commons-glenn-1962.jpg` (`$GLENN_1962_ID`,
   captured in step 7; ⌘2 Grid, click its thumbnail) then
   `ax press --role AXMenuItem --label "Evaluate Photo"` (single-asset;
   `requestEvaluation` has no "already evaluated" gate, only an "already
   *active*" one — a second call re-enqueues and re-completes it, re-firing
   the hook). Wait for the single item to drain (poll `work_sessions`/
   Activity, per README's keep-warm pattern).
9. **Assert the AI match landed face-level only:**
   ```bash
   script/vm_scenario_run.sh sql faces "SELECT face_index, origin, person_id FROM person_faces WHERE asset_id='$GLENN_1962_ID';"   # origin='ai', person_id=$JOHN_GLENN_ID
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_1962_ID';"  # 0 — no whole-asset link from an AI match
   test ! -e "$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$GLENN_1962_ID';").xmp" && echo "no sidecar for identity"
   ```
   If `person_faces` has no `origin='ai'` row here, this specific two-photo
   pair didn't cluster within `FaceSuggestionBuilder.defaultMaximumMatchDistance`
   (1.23) on this run — retry with another same-person pair from
   `sample-data/faces.tsv` (e.g. a Ride pair) before concluding face
   promotion is broken, per `inspect-010`'s own caution that only *some* pair
   is guaranteed to cluster.
10. **UI shows the ✨ suggestion** — open `commons-glenn-1962.jpg` in the
    loupe/inspector. The projection (`photoFacesPresentation`) does read the
    persisted `person_faces` row directly (`AppModel.swift:4339-4367`), but the
    SwiftUI body only re-renders when an *observed* state changes: live, the
    row still read `Unnamed` immediately after the async `Evaluate Photo`
    completed, and only showed `guess: John Glenn` after the selection was
    changed and restored (a re-render). This is a view-refresh gap, not a
    projection bug — assert the end state after one select-away/select-back
    rather than expecting the row to update in place.
    Assert the People row reads **"guess: John Glenn"** with a ✨ marker and
    `Confirm`/`Remove` buttons (`ax find --role AXButton --label "Confirm"`
    scoped to the People section — see Sharp edges on ambiguous plain-text
    "Confirm"/"Remove" labels if this corpus also has an unconfirmed caption
    open at the same time).
11. **Confirm the face**, closing this leg's loop: `ax press --role AXButton
    --label "Confirm"` (People section). Assert:
    ```bash
    script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_1962_ID';"          # user
    script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_1962_ID';"  # 1 now
    test ! -e "$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$GLENN_1962_ID';").xmp" && echo "still no sidecar — identity never syncs to XMP"
    ```

### 4. A real (confirmed) reject as the control, before autopilot runs
12. Pick a control asset not otherwise touched above — `commons-armstrong-eva-training.jpg`
    (if this happens to be the asset promoted a keyword in step 3, substitute
    `commons-ride-sts7.jpg`). Select it (⌘2 Grid, click its thumbnail),
    ⌘I, then `ax press --role AXButton --label "Reject"`
    (`InspectorView.swift:992`, `model.setFlagForSelectedAssets(.reject)`
    — a direct user gesture, `origin` is never `ai` for this path). Assert:
    ```bash
    MANUAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-armstrong-eva-training.jpg';")
    SRC_MANUAL=$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$MANUAL_ID';")
    MANUAL_SUM=$(shasum "$SRC_MANUAL" | awk '{print $1}')   # baseline for step 21's post-relocation content check
    script/vm_scenario_run.sh sql faces "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id='$MANUAL_ID';"  # reject
    # The direct gesture must never tag *this field* (flag) AI-origin. Assert the
    # flag is absent from aiUnconfirmedFields rather than the whole key being
    # NULL: the control asset may independently carry an unconfirmed AI caption
    # from the same Evaluate Visible pass (it did live: ["caption"]).
    script/vm_scenario_run.sh sql faces "SELECT count(*) FROM assets WHERE id='$MANUAL_ID' AND EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"  # 0
    grep -q 'ts:Pick="reject"' "$SRC_MANUAL.xmp" && echo "confirmed reject synced"
    ```

### 5. Autopilot: tentative reject lands immediately, is excluded from Move Rejects, moves only once confirmed
13. **Culling ▸ Run Autopilot**: `ax press --role AXMenuItem --label "Run Autopilot"`
    (`runAutopilotOnCurrentScope`, on-demand — no import needed; contrast
    `cull-017-autopilot-review.md`'s stale claim that autopilot only runs
    post-import). Record the ghosts this run produced — there is no `run_id`
    to key on any more (`autopilot_proposals` no longer exists as a table,
    SP-D0 dropped it forward-only); the ghost query selects them directly:
    ```bash
    script/vm_scenario_run.sh sql faces "SELECT id, json_extract(metadata_json,'\$.flag') FROM assets WHERE EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
    ```
14. **Find a genuinely tentative reject, distinct from the manual control:**
    ```bash
    script/vm_scenario_run.sh sql faces "SELECT id, original_path FROM assets
      WHERE id != '$MANUAL_ID'
        AND json_extract(metadata_json,'\$.flag')='reject'
        AND EXISTS (SELECT 1 FROM json_each(metadata_json,'\$.aiUnconfirmedFields') WHERE value='flag');"
    ```
    If this returns nothing, the planner didn't propose a cut on this
    11-photo batch — note the fixture gap (real-photo quality variance isn't
    guaranteed here) and retry against a larger/more varied real corpus
    (`jesse-pictures`, or `wordpress-photo-directory` + `loc-free-to-use`
    combined, per `activity-007`'s fallback) before concluding autopilot is
    broken. Otherwise call the match `TENT_ID`. Also confirm the manual
    control was **not** silently turned tentative:
    ```bash
    script/vm_scenario_run.sh sql faces "SELECT json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id='$MANUAL_ID';"  # still NULL — hasConfirmedFlag guard skipped it
    ```
15. **No sidecar for the tentative reject yet:**
    ```bash
    TENT_SRC=$(script/vm_scenario_run.sh sql faces "SELECT original_path FROM assets WHERE id='$TENT_ID';")
    TENT_SUM=$(shasum "$TENT_SRC" | awk '{print $1}')   # baseline for step 21's post-relocation content check
    test ! -e "$TENT_SRC.xmp" && echo "no sidecar for tentative reject"
    ```
16. **Move Rejects — the exclusion, live.** (Relaunch with
    `TESTSTRIP_REJECT_DESTINATION_DIR` set per Pre-state's VM workaround if
    not already done.) `ax press --role AXMenuItem --label "Move Rejects…"`.
    The preflight sheet's primary button text is
    `RejectRelocationPreflight.confirmationText` ("Move N reject photo(s) to
    `<folder>`"), where N = `rejectRelocationScope`'s confirmed-only count —
    assert **N = 1** (the manual control only; `$TESTSTRIP_REJECT_DESTINATION_DIR`
    from Pre-state bypasses the folder panel). Check the confirm-checkbox
    gate (disabled primary + standing hint while unchecked, per
    `app-010-move-rejects.md`'s step 4): the toggle's accessible label is
    `preflight.confirmationText` — the *same* string as the primary button
    ("Move N reject photo(s) to `<folder>`", `LibraryGridView.swift:3379`),
    so a `--contains "confirm"` filter matches nothing; it's the only
    checkbox in the sheet, so `ax find --role AXCheckBox` (bare, no label
    filter) is the reliable match. `ax press --role AXCheckBox` it, then
    `ax press --role AXButton --contains "Move 1 reject"` (the button's exact
    title is `confirmationText`, "Move 1 reject photo to `<folder>`").
17. **Assert the split outcome:**
    ```bash
    test ! -f "$SRC_MANUAL" && echo "manual reject moved"          # gone from source (SRC_MANUAL = armstrong-eva-training's original path, captured in step 12)
    ls "$REJECTS_DIR" | grep -q "$(basename "$SRC_MANUAL")" && echo "present at destination"
    script/vm_scenario_run.sh sql faces "SELECT count(*) FROM relocation_manifest_entries WHERE asset_id='$MANUAL_ID';"   # 1
    test -f "$TENT_SRC" && echo "tentative reject NOT moved — still at its original path"
    ls "$REJECTS_DIR" | grep -q "$(basename "$TENT_SRC")" && echo "FAIL: should not be present" || echo "correctly absent from destination"
    script/vm_scenario_run.sh sql faces "SELECT count(*) FROM relocation_manifest_entries WHERE asset_id='$TENT_ID';"      # 0
    ```
18. **Close the loop: confirm the tentative reject, then it becomes movable.**
    Open the Autopilot review banner's **Review**
    (`ax press --role AXButton --contains "Review"`; then
    `ax wait --role AXStaticText --contains "Reviewing"`). Click only
    `TENT_SRC`'s grid tile to select it (scroll it into view first — the
    grid is lazily virtualized), then
    `ax press --role AXButton --label "Commit 1"` (`commitAutopilotProposals`,
    repurposed under this branch to *confirm* rather than first-write — it
    clears `aiUnconfirmedFields`/`aiUnconfirmedKeywords` for the targeted
    proposal and writes the sidecar via the existing sync path; per
    `cull-017-autopilot-review.md`'s Sharp edges, "Commit N"/"Dismiss
    selected" are disabled with an empty selection — confirm the tile is
    actually selected first). Assert:
    ```bash
    script/vm_scenario_run.sh sql faces "SELECT json_extract(metadata_json,'\$.aiUnconfirmedFields') FROM assets WHERE id='$TENT_ID';"   # NULL now
    grep -q 'ts:Pick="reject"' "$TENT_SRC.xmp" && echo "confirmed reject now synced"
    ```
19. **Re-run Move Rejects** (`ax press --role AXMenuItem --label "Move Rejects…"`,
    same destination, same checkbox-then-primary flow as step 16). Assert
    `TENT_ID` is now included and physically relocated the same way the
    manual control was in step 17 (gone from `$TENT_SRC`, present at the
    destination, a new `relocation_manifest_entries` row) — the *only* thing
    that changed between steps 16-17 and this step is the confirm gesture in
    step 18.

### 6. The "exported Picks set" leg — fixture gap, not skipped silently
20. The spec's other tentative-exclusion target — a tentative AI **pick**
    must not appear in a completed culling session's persisted Picks
    `AssetSet` or its Export (`pickedAssetIDs`/`completedUnitCount`,
    `AppModel.swift`, fixed in the `d3529b70` follow-up, unit-tested by
    `testTentativeAIPickIsNotInPersistedPicksSetOrExport`) — is **not**
    independently live-driven by this card. `openCullingSessionPicks`/
    `cullingSessionCompletion` only populate from a completed **stack-cull
    work session**, which requires a persisted stack; `--faces` (like
    `--smoke`) has no persisted stacks, the same fixture gap
    `cull-016-completion-stage.md`/`cull-004-stack-promote-return.md`/
    `cull-014-stack-rail.md` already document. Until that gap is closed with
    a burst/persisted-stack fixture, treat the unit test as the authoritative
    coverage for this specific leg — noted here rather than fabricated into
    an untestable step.

### 7. Non-destructive, restated
21. Across every step above, re-checksum every original that was **not**
    relocated against its earlier baseline — all identical:
    ```bash
    [ "$(shasum "$SRC" | awk '{print $1}')" = "$ORIG_SUM" ] && echo "keyword asset untouched"
    [ "$(shasum "$GLENN_OFFICIAL_SRC" | awk '{print $1}')" = "$GLENN_OFFICIAL_SUM" ] && echo "glenn-official untouched"
    [ "$(shasum "$GLENN_1962_SRC" | awk '{print $1}')" = "$GLENN_1962_SUM" ] && echo "glenn-1962 untouched"
    ```
    For the two relocated originals, checksum them **at their new
    destination path** and confirm it matches the pre-move baseline
    captured earlier:
    ```bash
    [ "$(shasum "$REJECTS_DIR/$(basename "$SRC_MANUAL")" | awk '{print $1}')" = "$MANUAL_SUM" ] && echo "manual reject: moved, not re-encoded"
    [ "$(shasum "$REJECTS_DIR/$(basename "$TENT_SRC")" | awk '{print $1}')" = "$TENT_SUM" ] && echo "confirmed-then-moved tentative reject: moved, not re-encoded"
    ```

## Expected
- Step 1: `evaluation_signals` covers all 11 assets; `face_observations` > 0.
  **Fails if** evaluation never completes, or `face_observations` stays 0
  with the model actually downloaded (report as a real face-pipeline
  regression, not a fixture gap, once the model presence is confirmed).
- Steps 3-4: some asset promotes a ✨ keyword with no `.xmp` written. **Fails
  if** a keyword is promoted without landing in **both** `keywords` and
  `aiUnconfirmedKeywords`, or if any sidecar exists before step 6's confirm.
- Step 5: the Confirm/Remove buttons for the unconfirmed chip both exist pre-
  confirm. **Fails if** either is missing, or a confirmed chip elsewhere also
  shows a spurious Confirm button.
- Step 6: post-confirm, `aiUnconfirmedKeywords` drops the keyword,
  `keywords` keeps it, the `.xmp` now exists and contains it, the Confirm
  button disappears, and the original is byte-identical. **Fails if** the
  keyword vanishes from `keywords` too (over-deletion), the sidecar is
  missing/wrong, or the original changed.
- Steps 7-9: a confirmed face (origin=user, `person_assets` row) followed by
  a re-evaluation produces an `origin='ai'` face-level row for the *second*
  photo of the same person, with **no** `person_assets` row and **no**
  sidecar. **Fails if** the AI match writes a `person_assets` row (violates
  the face-level-only design), if it fires without a genuine re-evaluation
  event, or if it self-reinforces off an unconfirmed centroid (not directly
  observable here, but any AI-original centroid contamination would be a
  serious regression — flag immediately if suspected).
- Step 10-11: the ✨ "guess: John Glenn" row appears with no extra refresh
  trick, and confirming it flips origin to user + creates the `person_assets`
  link + still writes no sidecar. **Fails if** the suggestion never renders,
  or confirming it writes an `.xmp`.
- Step 12: a direct Reject gesture writes `flag=reject` with **`.flag` absent
  from** `aiUnconfirmedFields` and a synced sidecar immediately (this is the
  pre-existing, unchanged user-gesture path — a control, not new behavior
  under test). **Fails if** `.flag` appears in this asset's
  `aiUnconfirmedFields` (a direct gesture must never be tagged AI-origin for
  the field it wrote), or if the `.xmp` isn't written immediately with
  `ts:Pick="reject"`. (The whole `aiUnconfirmedFields` key may legitimately be
  non-null from an unrelated unconfirmed AI caption.)
- Steps 13-15: Run Autopilot applies at least one tentative `.reject`
  in-catalog with **no** sidecar, and leaves the manual control's confirmed
  reject untouched (not re-marked tentative). **Fails if** autopilot writes a
  sidecar for a tentative flag, or overwrites/re-tags the manual control's
  confirmed flag.
- Steps 16-17: the preflight's move count is exactly the confirmed-reject
  count (excludes the tentative one); after confirming and pressing Move,
  the manual control relocates and the tentative reject's original stays
  exactly where it was, absent from the destination, with zero
  `relocation_manifest_entries` rows for it. **This is the safety-critical
  assertion — fails if the tentative reject is moved, trashed, or partially
  touched (e.g. sidecar created at the destination with no original).**
- Steps 18-19: confirming the tentative reject clears its unconfirmed marker,
  writes its sidecar, and makes it eligible for the *next* Move Rejects pass,
  which now relocates it identically to the earlier confirmed reject.
  **Fails if** it becomes movable without an explicit confirm, or if
  confirming it doesn't write the sidecar.
- Step 21: every untouched original is byte-identical; every relocated
  original's content is unchanged at its new path. **Fails if** any original
  byte changed anywhere in this run — report immediately, don't soften it.

## Cleanup
```bash
rm -rf "$REJECTS_DIR"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance. Never delete `sample-data/photos/faces` or its
one pre-existing `.xmp` — it's a checked-in fixture.

## Sharp edges
- **AuraFace gating is scoped to the face leg only.** Keyword/caption
  promotion and autopilot need no model — don't block the whole card on a
  failed `download_face_model.sh`; skip only Section 3 and its dependent
  parts of Sections 5-7 if the model genuinely isn't available, per
  `dev-008-sample-downloads.md`'s manifest-gap note.
- **VM model delivery is unverified.** `download_face_model.sh`'s comment
  says the model is copied into the `.app` bundle by `build_and_run.sh` at
  build time, which (if true) means running the download once on the host
  before `vm_scenario_run.sh sync` should carry the model into the VM inside
  the rsynced bundle with no separate step — but no existing card
  (`inspect-010-photo-faces.md`/`people-009-scan.md` were both authored
  against a host-launch Pre-state, never `vm_scenario_run.sh`) has proven
  this live. Before trusting a "no faces detected" result as a product
  finding rather than a VM-sync gap, check the bundle actually contains
  `auraface-v1.mlpackage` inside the VM.
- **Promotion fires on evaluation completion only.** `nameFace`,
  `refreshPeopleFaceSuggestions`, and plain navigation do **not** re-run
  `promoteFaceMatches` — only a genuine `.completed` `WorkerEvent` for a
  `(asset, provider)` evaluation does (`invalidateEvaluationSignalsIfNeeded`
  → `promoteEvaluationResults`). Step 8's explicit re-evaluation exists
  because of this; don't substitute a UI-only refresh and expect the same
  result.
- **The ✨ glyph is not independently AX-findable** (same trap
  `cull-021-stack-rail-nav.md` documents for its rail's `✦`) — assert
  unconfirmed state via the Confirm/Remove button's presence and exact label
  text, not by searching for the sparkle glyph.
- **Ambiguous plain-text "Confirm"/"Remove" buttons.** The caption's
  unconfirmed-AI-caption row and a suggested face row both use bare
  `Button("Confirm")`/`Button("Remove")` with no distinguishing
  accessibility label (unlike the keyword chip's `"Confirm keyword <kw>"`).
  If an asset happens to have an unconfirmed caption *and* a suggested face
  simultaneously, `ax find --label "Confirm"` may match either — this
  corpus is unlikely to produce an OCR caption (no readable text in the
  astronaut portraits), but if it does, scope by section or use a different
  asset for the two legs.
- **`cull-017-autopilot-review.md`/`app-012-autopilot-evaluate-commands.md`
  are stale on one specific claim** (see "What this covers" above): their
  "proposals must leave zero writes in `metadata_json` until Commit"
  framing no longer holds. Their menu-composition, banner, and badge
  assertions are unaffected and still trustworthy.
- **Object-classification and autopilot-ranking outcomes are not
  guaranteed on this corpus.** Both floors/thresholds are documented as
  "guesses... tune against real dogfood, not synthetic budgets" in the
  spec's Risks section — if either the keyword-promotion or the
  autopilot-reject leg comes up empty on a live run, retry with a larger
  real-photo corpus per the inline fallback notes before concluding a
  regression; do not fabricate a result to force the card to pass.
- **Idle-wedge / keep-warm**: every wait in Sections 1, 2, and 5 involves the
  worker draining real evaluation/autopilot work — re-assert frontmost via
  `wait-vended` on every poll iteration, per `verify_people_clustering.sh`'s
  reference pattern.
- **Locked console in the VM**: if the auto-login GUI session ever locks,
  every AX/window step in this card is impossible until unlock — check
  `ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked` first if a step behaves
  like a silent no-op.

## Run status
NOT RUN — authored 2026-07-14 against the `feat/machine-label-provenance`
branch, source-cited directly against the current working tree (line numbers
above re-verified by reading `AppModel.swift`, `Metadata.swift`,
`XMPPacket.swift`, `InspectorView.swift`, and `PhotoFacesSectionView.swift`
at authoring time, not carried over from the implementation task reports).
Pending live execution in the Tart VM per `test/scenarios/README.md`
(`script/vm_scenario_run.sh`) — a human-triggered step separate from
authoring this card.

**Reconciled 2026-08-06 (Task 9, SP-D0 ghost derivation)**: `autopilot_proposals`
no longer exists as a table (SP-D0 dropped it forward-only) — Steps 13-14's
`run_id` lookup and `JOIN` against it became a direct ghost query against
`metadata_json`/`aiUnconfirmedFields`; the Autopilot-fold-in Source bullet's
"proposals are still written for run tracking" claim was corrected (there
is no separate proposal row of any kind now, just the ghost in the asset's
own metadata). Step 18's Commit gesture is unaffected — it still calls
`commitAutopilotProposals`. Supersedes prior status: this card was already
NOT RUN, so there is no prior PASS to invalidate — noted for the record per
house style. Needs a fresh VM run.

**Note added 2026-09-14 (live VM run):** on the `faces` fixture Run Autopilot
produced **0 flag ghosts** (only keyword ghosts) — the corpus has no persisted
stacks, so `AutopilotProposalPlanner.cullProposals` never fires a pick/cut. The
live run hand-seeded one tentative reject directly into `metadata_json`
(`flag=reject`, `aiUnconfirmedFields=["flag"]`) per `cull-025`/`cull-029`'s
accepted technique, then drove Steps 15-19 against it. The Autopilot **review
banner** is run-time-only (it survives no relaunch, and none was generated), so
Step 18's banner/`Commit 1` route was unavailable; the equivalent explicit
confirm gesture (**`X`** on the selected tile — `setFlagForSelectedAssets`, a
direct user gesture) was used instead and confirmed the same catalog outcome.

## Run status — 2026-09-14 (live VM run, batch 7)

**VERIFIED** (with two disclosed deviations and three corrected stale
assertions). Tart VM `teststrip-e2e`, `script/vm_scenario_run.sh launch faces`,
run dir `faces-1789385527` (11 assets). All executed legs passed.

- **Section 1 PASS** — ⇧⌘E (`Evaluate Visible` menu item) drained
  `evaluation_signals` to 11/11 distinct assets; `face_observations` = 11 (>0).
- **Section 2 PASS** — 9/11 assets promoted keywords; picked
  `commons-glenn-senator-portrait.jpg` (`392F3333…`), keyword `necktie`; raw
  `.object` signal confidence **0.970 ≥ 0.5** with `necktie` in `value_json`.
  Pre-confirm: no sidecar. The inspector showed `Confirm keyword necktie` /
  `Remove keyword necktie`. After `Confirm keyword necktie`: `keywords` kept it,
  `aiUnconfirmedKeywords` dropped it, `commons-glenn-senator-portrait.jpg.xmp`
  appeared with `dc:subject/rdf:Bag/rdf:li=necktie` (only the confirmed
  keyword — the confirmed-only projection), the Confirm button vanished, and the
  original was byte-identical (`8f2f06d8…` before and after).
- **Section 3 PASS** — named a face on `commons-glenn-official.jpg` as
  `John Glenn` (popover: `Add name` → field → Return) → `person_faces.origin=user`,
  `person_assets` = 1, no sidecar (identity never syncs). Re-ran `Evaluate Photo`
  on `commons-glenn-1962.jpg` → a face-level `person_faces` row
  `origin='ai'`, `person_id=John Glenn`, **`person_assets` = 0**, **no sidecar**.
  The inspector People row then read `guess: John Glenn` with the ✨
  (`AXImage desc="AI-suggested, unconfirmed"`) and `Confirm`/`Remove`
  (`Remove` help `Remove this suggested match`). Pressing `Confirm` →
  `origin=user`, `person_assets` = 1, still no sidecar.
- **Section 4 PASS (assertion corrected)** — direct `Reject` on
  `commons-armstrong-eva-training.jpg` → `flag=reject`, synced sidecar with
  `ts:Pick="reject"`, and `.flag` **not** in `aiUnconfirmedFields`. The asset's
  `aiUnconfirmedFields` was `["caption"]` (an unrelated unconfirmed AI caption
  from the same evaluation), so the card's original "must be NULL" wording was
  over-strict and is corrected above.
- **Section 5 PASS (safety-critical)** — `rejectRelocationScope` split proven
  live: with RAW_REJECT=2 (manual control + hand-seeded tentative ghost) and
  CONFIRMED_REJECT=1, the Move Rejects preflight rendered exactly
  `Move 1 reject photo to vm-rejects` (the tentative reject excluded). After the
  move: the manual control relocated (gone from source, present at
  `TESTSTRIP_REJECT_DESTINATION_DIR`, `relocation_manifest_entries` = 1) while
  the tentative reject stayed at its original path, was absent from the
  destination, and had `relocation_manifest_entries` = 0 — **zero
  relocation/trash for the tentative asset**. Confirming it (`X`) cleared its
  tentative marker (`aiUnconfirmedFields` → empty), wrote its sidecar
  (`ts:Pick="reject"`), and the next Move Rejects pass relocated it identically
  (manifest = 1). The `TESTSTRIP_REJECT_DESTINATION_DIR` relaunch workaround
  (`open -n --env`) is **now proven live**.
- **Step 21 PASS** — every untouched original byte-identical
  (`glenn-senator-portrait` shasum pre==post; `glenn-official` and
  `glenn-1962` md5s match `sample-data/faces.tsv`); both relocated originals
  match their pre-move shasum **at the destination** (moved, not re-encoded).

**Deviations (disclosed):** (1) no `sync` this batch (VM pre-synced) — the
fixture used the existing `faces` seed, and the stray pre-existing `.xmp`
sidecars in the VM's shared `sample-data/photos/faces/` (10 files left by an
earlier batch; only `commons-aldrin-portrait.jpg.xmp` is repo-shipped) were moved
aside so the card's "no sidecar yet" precondition held; they are **not** repo
files. (2) Run Autopilot produced no flag ghost on `faces` (structural fixture
gap — no stacks), so one tentative reject was hand-seeded as noted at Step 13.

**Product finding (open, minor):** the inspector's People row does not refresh
in place when an async `Evaluate Photo` lands an `origin='ai'` face match while
that photo is already displayed; it requires a selection change to re-render
(see the corrected Step 10). The projection itself reads the persisted row
correctly. Not asserted as a failure here, but the card's former "no extra
refresh gesture needed" claim is false as written.

**Fixture gap (unchanged, not driven):** Step 20's exported/Picks-`AssetSet`
tentative-pick exclusion still needs a persisted-stack fixture; the unit test
remains the authoritative coverage.

**Supersedes prior status:** first live run of this card (was NOT RUN).

**Citation drift (symbols alive, behavior as described; corrected 2026-09-14):**
the "Source" section's `AppModel.swift` line numbers are stale — `promoteMetadataLabels`
`:8678-8705`→`:9401` (floor `objectKeywordConfidenceFloor` `:8285`→`:9392`);
`promoteFaceMatches` `:3772-3795`→`:4246`; `confirmAIKeyword`/`removeAIKeyword`
`:8328`/`:8343`→`:9435`/`~9449`; `confirmAIField`/`removeAIField`
`:8358`/`:8378`→`:9465`/`:9485`; `confirmAIFace`/`rejectFaceSuggestion`
`:3948`/`:3962`→`:4422`/`:4436`; `rejectRelocationScope` `:12561-12605`→`:13422`;
`runAutopilotOnCurrentScope` `:10146-10158`→`:10901`; `applyTentativeAutopilotProposals`
`:10086-10133`→`:10841`; `promoteEvaluationResults` `:10499-10509`→`:11680`;
`photoFacesPresentation` (Step 10) `:4339-4367` (verified exact);
`XMPPacket.swift` `confirmedProjection` apply `:62`→`:64`. UI affordances hold:
`InspectorView` keyword chips at `:1123`/`:1140` (labels exact), AI caption row
`:1167`; `PhotoFacesSectionView` `confirmAIFace` `:83`, Remove help
`Remove this suggested match` `:91`.
