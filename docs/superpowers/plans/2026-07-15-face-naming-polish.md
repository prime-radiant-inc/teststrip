# Face Naming Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the loupe "Add name" popover so it opens reliably, and let the
face-group review card ("Is this X?") name individual faces — not just confirm
the whole group or remove faces.

**Architecture:** Two independent changes on the face-naming surfaces. Task 1
de-conflicts a shared popover-presentation flag. Task 2 adds the existing
`PersonAutocompleteField` to each review tile, wired to the already-tested
`AppModel.nameFace`.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM. App code in `Sources/TeststripApp`,
tests in `Tests/TeststripAppTests` (`@testable import TeststripApp`).

## Global Constraints

- Match the style of surrounding code; make the smallest reasonable change.
- **Provenance invariant:** naming a face is a *user* gesture — `AppModel.nameFace`
  already writes `person_faces.origin='user'`. Identity has no XMP field, so no
  sidecar is written. Do not change this; both tasks route through `nameFace`.
- No vacuous tests, no tests of trivial/mocked behavior. Where a task's only new
  behavior is SwiftUI view wiring over already-tested model methods, the
  deliverable verification is the end-to-end scenario card — do **not** fabricate
  a unit test to hit a coverage target.
- Every user-facing change gets a scenario card under `test/scenarios/`
  (authored, not run — these are VM + AuraFace bound). Next free number is
  `people-025`.
- The whole test suite must stay green (`swift test`). The final gate is
  `make verify`; the controller runs it, not the task implementers.

---

### Task 1: Fix the naming-popover presentation race

**Problem (root cause):** In the loupe, two surfaces are on screen together and
both bind a `.popover(isPresented:)` to the *same* `model.editingFaceID`:
`PhotoFacesSectionView` (the People inspector "Add name" button,
`InspectorView.swift:678`) and `FaceBoxOverlayView` (the image's face pill,
`LoupeZoomView.swift:276`, gated to when the inspector is visible). Clicking
"Add name" sets `editingFaceID`, so *both* popovers try to present in the same
frame. SwiftUI reliably presents only one; which one wins is a race — hence
"doesn't reliably pop up." The fix: a surface discriminator so only the surface
that initiated editing presents its popover. The other surface still highlights
the face (cross-surface feedback) but does not contend for the presentation.

**Files:**
- Create: `Sources/TeststripApp/FaceNamingPopover.swift`
- Modify: `Sources/TeststripApp/AppModel.swift` (add `editingFaceSource`, next to
  `editingFaceID` at `AppModel.swift:2297`)
- Modify: `Sources/TeststripApp/PhotoFacesSectionView.swift` (`:104`–`:132`)
- Modify: `Sources/TeststripApp/FaceBoxOverlayView.swift` (`:117`–`:155`)
- Create: `Tests/TeststripAppTests/FaceNamingPopoverTests.swift`
- Create: `test/scenarios/people-025-inspector-add-name-popover.md`

**Interfaces:**
- Produces: `enum FaceEditSurface { case inspector, loupe }` and
  `enum FaceNamingPopover { static func isPresented(editingFaceID: FaceID?, editingSource: FaceEditSurface?, rowFaceID: FaceID, surface: FaceEditSurface) -> Bool }`
  (both `public`, mirroring the existing `public var editingFaceID`).
- Consumes: existing `AppModel.editingFaceID: FaceID?`, `FaceID` (Equatable, from
  TeststripCore).

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/FaceNamingPopoverTests.swift`:

```swift
import XCTest
import TeststripCore
@testable import TeststripApp

final class FaceNamingPopoverTests: XCTestCase {
    private let faceA = FaceID(assetID: AssetID("asset-a"), faceIndex: 0)
    private let faceB = FaceID(assetID: AssetID("asset-b"), faceIndex: 1)

    func testPresentsOnlyForTheInitiatingSurface() {
        // Editing face A from the inspector: the inspector presents, the loupe does not —
        // this is the regression: two surfaces no longer present the same popover at once.
        XCTAssertTrue(FaceNamingPopover.isPresented(
            editingFaceID: faceA, editingSource: .inspector, rowFaceID: faceA, surface: .inspector))
        XCTAssertFalse(FaceNamingPopover.isPresented(
            editingFaceID: faceA, editingSource: .inspector, rowFaceID: faceA, surface: .loupe))
    }

    func testDoesNotPresentForADifferentFace() {
        XCTAssertFalse(FaceNamingPopover.isPresented(
            editingFaceID: faceA, editingSource: .loupe, rowFaceID: faceB, surface: .loupe))
    }

    func testDoesNotPresentWhenNothingIsBeingEdited() {
        XCTAssertFalse(FaceNamingPopover.isPresented(
            editingFaceID: nil, editingSource: nil, rowFaceID: faceA, surface: .inspector))
    }
}
```

- [ ] **Step 2: Run the test, verify it fails to compile**

Run: `swift test --filter FaceNamingPopoverTests`
Expected: FAIL — `FaceNamingPopover` / `FaceEditSurface` not defined.

- [ ] **Step 3: Create the predicate and surface enum**

Create `Sources/TeststripApp/FaceNamingPopover.swift`:

```swift
import TeststripCore

/// Which surface is currently editing a face's name. The loupe face-box overlay
/// (`FaceBoxOverlayView`) and the People inspector rows (`PhotoFacesSectionView`)
/// are on screen together and both offer a naming popover for the same face;
/// this tag lets only the surface the user actually clicked present its popover,
/// so the two never contend for a single presentation.
public enum FaceEditSurface {
    case inspector
    case loupe
}

/// Whether a given surface should present its naming popover for a given row.
/// True only when that surface both owns the current edit and is editing this
/// face — so `AppModel.editingFaceID` can still drive cross-surface highlight
/// (the loupe box lights up while you name from the inspector) without a second
/// popover fighting to appear.
public enum FaceNamingPopover {
    public static func isPresented(
        editingFaceID: FaceID?,
        editingSource: FaceEditSurface?,
        rowFaceID: FaceID,
        surface: FaceEditSurface
    ) -> Bool {
        editingFaceID == rowFaceID && editingSource == surface
    }
}
```

- [ ] **Step 4: Add `editingFaceSource` to AppModel**

In `Sources/TeststripApp/AppModel.swift`, right after the `editingFaceID`
declaration (`:2297`), add:

```swift
    /// Which surface owns the current face-name edit, so the inspector and the
    /// loupe overlay never present the naming popover for the same face at once
    /// (`FaceNamingPopover`).
    public var editingFaceSource: FaceEditSurface?
```

- [ ] **Step 5: Route the inspector button through the discriminator**

In `Sources/TeststripApp/PhotoFacesSectionView.swift`:

Set the source when opening (the `Button("Add name")` action, `:104`):

```swift
        Button("Add name") {
            model.editingFaceID = row.faceID
            model.editingFaceSource = .inspector
        }
```

Change `editingBinding(for:)` (`:127`) to present only for the inspector, and to
clear both fields on dismiss:

```swift
    private func editingBinding(for faceID: FaceID) -> Binding<Bool> {
        Binding(
            get: {
                FaceNamingPopover.isPresented(
                    editingFaceID: model.editingFaceID,
                    editingSource: model.editingFaceSource,
                    rowFaceID: faceID,
                    surface: .inspector
                )
            },
            set: { if !$0 { model.editingFaceID = nil; model.editingFaceSource = nil } }
        )
    }
```

In the popover's `onPick`/`onCreate` (`:113`–`:120`), also clear the source
where `model.editingFaceID = nil` is set:

```swift
                onPick: { personID in
                    apply { try model.nameFace(row.faceID, personID: personID) }
                    model.editingFaceID = nil
                    model.editingFaceSource = nil
                },
                onCreate: { name in
                    apply { try model.nameFace(row.faceID, newPersonName: name) }
                    model.editingFaceID = nil
                    model.editingFaceSource = nil
                }
```

- [ ] **Step 6: Route the loupe pill through the discriminator**

In `Sources/TeststripApp/FaceBoxOverlayView.swift`, the pill's naming button
(`:119`) sets the source:

```swift
            Button {
                model.editingFaceID = row.faceID
                model.editingFaceSource = .loupe
            } label: {
```

Change `editingBinding(for:)` (`:152`) to present only for the loupe and clear
both on dismiss:

```swift
    private func editingBinding(for faceID: FaceID) -> Binding<Bool> {
        Binding(
            get: {
                FaceNamingPopover.isPresented(
                    editingFaceID: model.editingFaceID,
                    editingSource: model.editingFaceSource,
                    rowFaceID: faceID,
                    surface: .loupe
                )
            },
            set: { if !$0 { model.editingFaceID = nil; model.editingFaceSource = nil } }
        )
    }
```

In the popover's `onPick`/`onCreate` (`:129`–`:134`), also clear the source
alongside `model.editingFaceID = nil`.

Leave the box's `isEditing` (`:79`, `model.editingFaceID == row.faceID`)
**unchanged** — the box highlight/pill mount must still track `editingFaceID`
alone so the box lights up when you name the face from the inspector.

- [ ] **Step 7: Run the test, verify it passes**

Run: `swift test --filter FaceNamingPopoverTests`
Expected: PASS (3 tests).

- [ ] **Step 8: Author the scenario card**

Create `test/scenarios/people-025-inspector-add-name-popover.md` covering:
from an isolated seeded launch with faces, open the loupe with the inspector
visible on a photo that has an **unnamed** face, click "Add name" in the People
inspector row, and assert the autocompleter popover opens **reliably** anchored
to the inspector (not over the image), typing + picking names the face
(`person_faces.origin='user'` for that face in the catalog). Falsification: if
the popover fails to appear, or appears over the image instead of the inspector,
the test fails. Match the format of a sibling card (e.g. `people-024`), reference
only real UI (`PhotoFacesSectionView` "Add name", `PersonAutocompleteField`), and
note the AX-driving realities from `test/scenarios/README.md`.

- [ ] **Step 9: Commit**

```bash
git add Sources/TeststripApp/FaceNamingPopover.swift \
        Sources/TeststripApp/AppModel.swift \
        Sources/TeststripApp/PhotoFacesSectionView.swift \
        Sources/TeststripApp/FaceBoxOverlayView.swift \
        Tests/TeststripAppTests/FaceNamingPopoverTests.swift \
        test/scenarios/people-025-inspector-add-name-popover.md
git commit -m "fix: name-face popover no longer races between inspector and loupe"
```

---

### Task 2: Name individual faces on the face-group review card

**Goal:** On the "Is this X?" review card (`FaceGroupReviewView`), each face tile
can be named to a *specific* person (existing or new), not just confirmed with
the group or removed. Naming a tile confirms that one face to the chosen person
and drops it from the group (the card is a pure projection and already recomputes
after each mutation).

**Files:**
- Modify: `Sources/TeststripApp/FaceGroupReviewView.swift` (`FaceReviewTileView`
  `:176`–`:254`, and its call site in `tileGrid` `:66`–`:84`)
- Create: `test/scenarios/people-026-review-card-name-face.md`

**Interfaces:**
- Consumes: `AppModel.rankedPersonCandidates(forFace:)` (returns
  `[PersonCandidate]`, similarity-ordered — already tested), `AppModel.nameFace(_:personID:)`
  and `AppModel.nameFace(_:newPersonName:)` (both write `origin='user'` and call
  `refreshPeopleFaceSuggestions()` — already tested), `PersonAutocompleteField`.
- Produces: no new model logic. Task 2 is view wiring over the above; its
  verification is the scenario card, not a unit test. Do **not** add a vacuous
  unit test.

- [ ] **Step 1: Thread candidates + naming closures into the tile**

In `Sources/TeststripApp/FaceGroupReviewView.swift`, give `FaceReviewTileView`
three new stored properties and a per-tile popover state:

```swift
struct FaceReviewTileView: View {
    var previewURL: URL?
    var boundingBox: FaceBoundingBox
    var candidates: [PersonCandidate]
    var name: (_ pick: PersonCandidateSelection) -> Void
    var remove: () -> Void

    @State private var faceCrop: NSImage?
    @State private var loadedKey: FaceCropAvatar.CropKey?
    @State private var isRevealingPhoto = false
    @State private var isNaming = false
    // ...
```

Define the small selection type at file scope (a face is named to an existing
person by id or a new person by name):

```swift
enum PersonCandidateSelection {
    case existing(String)   // personID
    case new(String)        // typed name
}
```

Add a name pill at `.bottomLeading` of the tile's `ZStack` (mirror the existing
`removeButton` at `.topTrailing`), opening the shared autocompleter:

```swift
    private var namePill: some View {
        Button {
            isNaming = true
        } label: {
            Label("Name", systemImage: "person.crop.circle.badge.plus")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Name this face as a specific person")
        .popover(isPresented: $isNaming, arrowEdge: .bottom) {
            PersonAutocompleteField(
                candidates: candidates,
                onPick: { personID in
                    name(.existing(personID))
                    isNaming = false
                },
                onCreate: { newName in
                    name(.new(newName))
                    isNaming = false
                }
            )
            .frame(width: 240)
            .padding(8)
        }
    }
```

Because each tile is its own `View` with its own `@State private var isNaming`,
there is no shared-flag race here (unlike Task 1's loupe/inspector case).

- [ ] **Step 2: Wire the call site**

In `tileGrid` (`:73`–`:79`), pass the candidates and naming closure from the
model, alongside the existing `remove`:

```swift
                    ForEach(review.tiles) { tile in
                        FaceReviewTileView(
                            previewURL: model.previewURL(for: tile.assetID, levels: [.large, .medium, .grid, .micro]),
                            boundingBox: tile.boundingBox,
                            candidates: model.rankedPersonCandidates(forFace: tile.faceID),
                            name: { selection in name(suggestion, tile, selection) },
                            remove: { remove(suggestion, tile) }
                        )
                    }
```

Add the `name` helper next to the existing `remove` helper (`:164`):

```swift
    private func name(_ suggestion: PeopleFaceSuggestion, _ tile: FaceReviewTile, _ selection: PersonCandidateSelection) {
        do {
            switch selection {
            case .existing(let personID):
                try model.nameFace(tile.faceID, personID: personID)
            case .new(let newName):
                try model.nameFace(tile.faceID, newPersonName: newName)
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
```

Naming routes through `nameFace`, which calls `refreshPeopleFaceSuggestions()`;
the card re-reads `model.peopleFaceSuggestions` and recomputes its tiles, so the
named face drops out of the group exactly as a removal does.

- [ ] **Step 3: Build and run the full app test suite**

Run: `swift build && swift test --filter FaceGroupReview`
Expected: builds; existing `FaceGroupReviewPresentationTests` /
`FaceGroupReviewTests` still PASS (the presentation type is unchanged).

- [ ] **Step 4: Author the scenario card**

Create `test/scenarios/people-026-review-card-name-face.md`: open a matched
review card ("Is this <name>?") with ≥2 faces, use a tile's **Name** pill to
assign one face to a *different* existing person (via the autocompleter), and
assert against catalog ground truth that (a) that face is now
`person_faces.origin='user'` for the chosen person, (b) it no longer appears in
the original group's suggestion, and (c) the remaining faces still confirm to the
card's person on Confirm. Also cover naming to a brand-new typed person. Match a
sibling card's format; reference only real UI (`FaceReviewTileView` Name pill,
`PersonAutocompleteField`); note AX-driving realities.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/FaceGroupReviewView.swift \
        test/scenarios/people-026-review-card-name-face.md
git commit -m "feat: name individual faces on the face-group review card"
```

---

## Self-Review

- **Spec coverage:** B (popover race) → Task 1; A (per-face naming on the review
  card) → Task 2. Both covered.
- **Placeholders:** none — every code step shows the code.
- **Type consistency:** `FaceEditSurface`/`FaceNamingPopover` defined in Task 1,
  used in Steps 5–6. `PersonCandidateSelection` defined in Task 2 Step 1, used in
  Steps 1–2. `PersonCandidate`, `FaceID`, `nameFace`, `rankedPersonCandidates`
  all pre-exist (verified in AppModel).
