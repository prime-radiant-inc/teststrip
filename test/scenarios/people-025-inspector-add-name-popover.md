# people-025-inspector-add-name-popover: inspector "Add name" popover presents reliably, without racing the loupe's face-box pill

**What this covers**: the Task 1 fix for a SwiftUI popover-presentation race.
`PhotoFacesSectionView`'s inspector "Add name" button and
`FaceBoxOverlayView`'s loupe face-box pill both bind `.popover(isPresented:)`
off the same `model.editingFaceID`. Before the fix, clicking "Add name" set
`editingFaceID`, and because the loupe box's `isEditing` is also keyed on
`editingFaceID` alone, the box switched to its pill (mounting *its* popover
binding too) in the same frame — both bindings read true at once, SwiftUI
presents only one, and which one wins is a race: sometimes the inspector's
popover never appears, sometimes a popover appears anchored to the loupe box
over the image instead. `FaceNamingPopover.isPresented` plus the new
`editingFaceSource` discriminator fix this: only the surface that set
`editingFaceSource` presents its own popover, while the other surface still
highlights (the loupe box's `isEditing` stays keyed on `editingFaceID` alone
on purpose, so it still lights up while naming from the inspector) without
contending for the presentation. This card drives the inspector leg: click
"Add name" with the loupe box in view but un-hovered (so the loupe surface
starts cold, the condition that used to race), confirm the popover reliably
appears anchored to the inspector column rather than over the image, confirm
the cross-surface highlight still lights the box, and confirm naming through
it writes `person_faces.origin='user'`.

Source read at authoring time (cite these, not anything else):
`Sources/TeststripApp/PhotoFacesSectionView.swift` (`addNameButton`
`:103-128`, `editingBinding` `:130-142`), `Sources/TeststripApp/FaceBoxOverlayView.swift`
(`faceBox` `:77-102`, `facePill` `:117-153`, `editingBinding` `:155-167`),
`Sources/TeststripApp/FaceNamingPopover.swift`, `Sources/TeststripApp/AppModel.swift`
(`editingFaceID`, `editingFaceSource`, `nameFace`,
`rankedPersonCandidates(forFace:)`), `Sources/TeststripApp/PersonAutocompleteField.swift`,
`script/ax_drive.sh`, `script/capture_app_window.sh`, `script/vm_scenario_run.sh`.

## Pre-state

A freshly built, isolated app instance seeded with real face photos, with
face detection run but **no person confirmed yet** — every detected face is
still genuinely `.unnamed` (no `person_faces` row at all). Construction
mirrors `people-024-face-autocompleter.md`'s Pre-state step 1 exactly; that
card's steps 2 onward (confirming "John Glenn" to build a ranking centroid)
are not needed here — this card only needs one unnamed face.

```bash
ROOT_DIR="$(git rev-parse --show-toplevel)"
./script/download_face_model.sh   # AuraFace-v1 — see Sharp edges: download may fail (dev-008 gap)
script/vm_scenario_run.sh sync faces
script/vm_scenario_run.sh launch faces   # prints "launched 'faces' fresh at $FRESH" — capture $FRESH
script/vm_scenario_run.sh ax wait-vended Teststrip
# vm_scenario_run.sh's own REMOTE_ROOT constant, reconstructed locally (its
# `shell` verb, unlike `ax`, does not cd there for you — see Steps 1.3/2.4):
REMOTE_ROOT="/Users/${TESTSTRIP_VM_USER:-admin}/teststrip-vm"
```

1. Evaluate everything so face detection runs before any person exists — no
   `person_faces` rows are created since nothing can be proposed against a
   centroid that doesn't exist yet:
   ```bash
   # ⌘2 Library — confirm all 11 thumbnails visible
   script/vm_scenario_run.sh ax press --role AXMenuItem --label "Evaluate Visible"
   for i in $(seq 1 60); do n=$(script/vm_scenario_run.sh sql faces "SELECT count(DISTINCT asset_id) FROM evaluation_signals;"); [ "$n" -ge 11 ] && break; sleep 2; done
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM face_observations;"   # >0 required — if 0, the AuraFace model didn't load; stop and flag, don't force the rest
   GLENN_OFFICIAL_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM assets WHERE original_path LIKE '%commons-glenn-official.jpg';")
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"  # 0 — genuinely unnamed
   ```

This leaves `$GLENN_OFFICIAL_ID` with one detected, genuinely unnamed face —
the fixture the Steps below exercise.

## Steps

### 1. Open the loupe with the inspector visible; leave the face box un-hovered

1. ⌘2 Library → select `commons-glenn-official.jpg`'s thumbnail →
   double-click → ⌘I. The People section renders one row in `.unnamed`
   state, showing the "Add name" button (`PhotoFacesSectionView.controls(for:)`,
   `:72-76`).
2. Do not hover the loupe's face box, so the loupe surface starts cold
   (`model.focusedFaceID` and `model.editingFaceID` both nil for this face
   — `isFocused || isEditing` both false, `FaceBoxOverlayView.faceBox`
   `:78-89`): the box shows its plain label, not the pill. This is the exact
   precondition of the pre-fix race — clicking "Add name" alone, with no
   prior hover, used to be enough to make both surfaces' popover bindings
   go true simultaneously.
3. Capture a baseline screenshot:
   ```bash
   script/vm_scenario_run.sh shell "cd '$REMOTE_ROOT' && ./script/capture_app_window.sh Teststrip /tmp/add-name-baseline.png"
   ```
   (`shell`, unlike `ax`, does not `cd` into `$REMOTE_ROOT` for you, so the
   card does it explicitly using the local `REMOTE_ROOT` set in Pre-state.
   See Sharp edges for pulling this file back to actually look at it.)

### 2. Click "Add name" in the inspector; confirm the popover opens anchored there, reliably

Repeat this sub-sequence 3 times (fresh open → assert → dismiss) — a single
pass cannot fully falsify a race; `FaceNamingPopoverTests` is the
deterministic half of this fix's verification, and this card's job is to
show the assembled UI agreeing with it every time, not just once.

For each of the 3 passes:

1. Click the inspector's button:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Add name"
   ```
   This sets `model.editingFaceID = row.faceID` and
   `model.editingFaceSource = .inspector` (`PhotoFacesSectionView.swift:104-107`).
2. Assert the autocompleter appears at all:
   ```bash
   script/vm_scenario_run.sh ax wait --role AXTextField --contains "Name"
   ```
3. Confirm exactly one such field exists — a second, differently-anchored
   "Name" field is exactly what the pre-fix race could produce (both
   bindings true, both popovers attempting to mount):
   ```bash
   script/vm_scenario_run.sh ax find --role AXTextField --contains "Name" | wc -l   # 1
   ```
4. Capture a screenshot (a distinct output path per pass, e.g.
   `add-name-pass-1.png`):
   ```bash
   script/vm_scenario_run.sh shell "cd '$REMOTE_ROOT' && ./script/capture_app_window.sh Teststrip /tmp/add-name-pass-1.png"
   ```
   and visually confirm: the popover is anchored below/near the "Add name"
   button in the right-hand inspector column, **not** floating over the
   image; and the loupe's face box is now outlined yellow
   (`isFocused || isEditing` → true via `isEditing`,
   `FaceBoxOverlayView.swift:80-82`) — the cross-surface highlight the fix
   deliberately preserves (`FaceNamingPopover.swift:15` docstring), showing
   the box still tracks the edit even though it isn't presenting anything.
   **This screenshot check is the falsifiable core of the card** — see
   Sharp edges for how the image gets off the VM to look at.
5. Dismiss without naming:
   ```bash
   script/vm_scenario_run.sh key 'key code 53'   # Escape
   script/vm_scenario_run.sh ax find --role AXTextField --contains "Name"   # exit 1 — popover gone
   ```

### 3. Name the face through the inspector's popover; assert the catalog write

1. Open once more and type + create:
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --label "Add name"
   script/vm_scenario_run.sh ax type --contains "Name" --text "John Glenn"
   script/vm_scenario_run.sh ax press --role AXButton --label 'Create "John Glenn"'
   ```
2. Assert the write, and that the popover is gone afterward:
   ```bash
   JOHN_GLENN_ID=$(script/vm_scenario_run.sh sql faces "SELECT id FROM people WHERE name='John Glenn';")
   script/vm_scenario_run.sh sql faces "SELECT origin FROM person_faces WHERE asset_id='$GLENN_OFFICIAL_ID';"   # user
   script/vm_scenario_run.sh sql faces "SELECT count(*) FROM person_assets WHERE person_id='$JOHN_GLENN_ID' AND asset_id='$GLENN_OFFICIAL_ID';"  # 1
   script/vm_scenario_run.sh ax find --role AXTextField --contains "Name"   # exit 1 — no popover left open
   ```

## Expected

- Step 1 (baseline): the loupe box shows its plain label (not the pill), no
  popover is open. **Fails if** the pill or a popover is already showing
  before any click — the fixture wasn't actually cold.
- Step 2 (the fix, 3 passes): every pass shows exactly one autocompleter
  `TextField`, screenshot-confirmed anchored to the inspector column, with
  the loupe box simultaneously highlighted yellow. **Fails if** any pass
  shows the popover missing entirely, anchored over the image instead of the
  inspector, or shows two "Name" fields at once — each is a symptom of the
  presentation race this task fixes.
- Step 3 (the write): naming through the inspector's popover creates
  `people.name='John Glenn'`, a `person_faces` row for `$GLENN_OFFICIAL_ID`
  with `origin='user'`, and a `person_assets` row; the popover is gone
  afterward. **Fails if** the person isn't created, `origin` isn't `user`, or
  the text field lingers after Create.

## Cleanup

Quit the launched instance; discard the VM run directory
(`~/teststrip-vm/run/faces-<timestamp>`, i.e. `$FRESH` from Pre-state), per
`test/scenarios/README.md`'s isolated-launch teardown. Touch no real catalog.

## Sharp edges

- **Getting a captured screenshot off the VM to actually look at it is not a
  first-class `vm_scenario_run.sh` verb.** `capture_app_window.sh` runs
  correctly over ssh inside the VM (the `setup` verb explicitly pre-grants
  Screen Recording to the ssh session binaries "for ssh-driven
  `screencapture` — see cull-006", i.e. this exact pattern is provisioned
  for), but the resulting PNG lands in the VM's own filesystem; nothing in
  `vm_scenario_run.sh` pulls a file back to the host. A live run needs an
  explicit pull composed from the script's own real primitives, e.g.:
  ```bash
  VM_IP=$(script/vm_scenario_run.sh ip)
  sshpass -p "${TESTSTRIP_VM_PASS:-admin}" scp -o StrictHostKeyChecking=no \
    "${TESTSTRIP_VM_USER:-admin}@$VM_IP:/tmp/add-name-baseline.png" /tmp/add-name-baseline.png
  ```
  (`VM_USER`/`VM_PASS` default to `admin`/`admin` in `vm_scenario_run.sh`,
  overridable via `TESTSTRIP_VM_USER`/`TESTSTRIP_VM_PASS`; `ip` is a
  documented verb.) This is a manual composition, not a documented verb —
  flagging it here rather than inventing a `vm_scenario_run.sh screenshot`
  verb that doesn't exist.
- **The screenshot check is a visual judgment call, not an AX assertion.**
  `ax_drive.sh find`/`wait` match on label/help/contains text, not screen
  position (`kAXPositionAttribute` is read only internally for the `press
  --button right` fallback, never exposed by `find`), so there is no
  scripted way to assert "this element's frame is inside the inspector
  column." Step 2.4's core claim rests on a human/agent reading the pulled
  screenshot, the same technique `inspect-010-photo-faces.md` and
  `cull-006-zoom-and-face-zoom.md` use for analogous placement claims.
- **A single pass cannot fully prove a race is fixed.** Repeating the
  open/dismiss cycle (Step 2) raises confidence but is not a formal proof;
  `Tests/TeststripAppTests/FaceNamingPopoverTests.swift` is the
  deterministic half of this fix's verification. If any of the 3 passes
  shows the wrong surface's popover, treat the fix as incomplete even if
  most passes look right.
- **The popover's `TextField` placeholder ("Name") is not unique app-wide**
  (culling-session-name and sidebar rename fields also use it, per
  `people-024-face-autocompleter.md`'s Sharp edges); neither should be
  mounted during this flow, but sanity-check with a plain `ax find --contains
  "Name"` first if `type`/`wait` ever seem to hit the wrong field.
- **AuraFace gating.** The Pre-state's evaluation pass needs the AuraFace
  embedder present (`download_face_model.sh`); if missing, `face_observations`
  stays empty and the whole card is blocked — stop and flag per
  `dev-008-sample-downloads.md`'s manifest-gap note, don't force it.
- **Idle-wedge / keep-warm.** The evaluation-completion poll and every
  screenshot pass need the app kept frontmost — re-assert via
  `script/vm_scenario_run.sh ax wait-vended Teststrip` on every poll, per
  CLAUDE.md and `script/verify_people_clustering.sh`'s reference pattern.

## Run status

NOT RUN — authored 2026-07-15 against `feat/face-naming-polish`, for Task 1
of the Face Naming Polish sub-project. Every label, AX role/help string, file
path, and method name above was re-verified by reading the actual
current-tree source listed under "Source" before writing this card. Pending
live execution in the Tart VM with the AuraFace model present
(`script/vm_scenario_run.sh`, per `test/scenarios/README.md`) — a
human-triggered step separate from authoring this card.
