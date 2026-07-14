# Unified Single-Image Inspector + Per-Photo Face Naming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the inspector available on the single-image view as vertically stacked sections (Info/Describe/AI/People), and add a per-photo People section that shows detected faces as boxes-on-image + a crop list where you add / remove / confirm / reject names — with rejections that stop re-suggestion.

**Architecture:** The loupe is already one shared view (`loupeStage`, gated by `showsCullChrome`); this allows the inspector column to coexist and restructures `InspectorView` from tabs to stacked sections. Faces reuse the existing repo layer (`faceObservations`, `assignFaces`, `dismissFaces`, `person_faces`, suggestions); the one new data piece is a `rejected_face_people` negative store the suggestion computation consults. All writes are gesture-gated (confirm-before-write).

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, SQLite (C API). App code in `Sources/TeststripApp/`; catalog in `Sources/TeststripCore/Catalog/`; tests in `Tests/`.

## Global Constraints

- **Confirm-before-write:** viewing a photo, showing face boxes, and displaying guesses write nothing. Assert the negative — nothing in `person_faces` or `rejected_face_people` before the explicit gesture.
- **Non-destructive:** face edits are catalog-only; no original bytes, no XMP sidecar changes in this feature's scope.
- **TDD** for data/presentation/gesture tasks; the SwiftUI view tasks are verified by the Phase-D scenario card.
- **macOS 14+ / Swift 6.** `make build`, `make test`; interactive verification via `script/vm_scenario_run.sh`.
- **Reuse existing patterns:** person create/name = `upsertPerson(id:name:)` + `assignFaces`; suggestions = `PeopleFaceSuggestion` / `peopleFaceSuggestions(...)`; boxes = `FaceBoundingBox {x,y,w,h}` (normalized).

---

## Phasing

- **Phase B — data:** the `rejected_face_people` store + `unassignFaces` + suggestion exclusion (unit-tested, no UI).
- **Phase C-model — presentation + gestures:** `PhotoFacesPresentation` + AppModel face-edit methods (unit-tested).
- **Phase A — inspector shell:** allow the inspector on the single-image view; restructure to stacked sections.
- **Phase C-view — faces UI:** the People section list + the box overlay (verified by scenario).
- **Phase D — e2e scenario card.**

Build B → C-model → A → C-view → D. Each task ends at a green commit.

---

### Task 1: `rejected_face_people` store + `unassignFaces` (repo)

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (add the table alongside `person_faces` ~line 165)
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/RejectedFacePeopleTests.swift` (create)

**Interfaces:**
- Consumes: `FaceID` (`{assetID, faceIndex}`), the `database.execute`/`rows` helpers.
- Produces:
  - `CatalogRepository.recordRejectedFacePerson(assetID: AssetID, faceIndex: Int, personID: String) throws`
  - `CatalogRepository.rejectedFacePeople() throws -> [(assetID: AssetID, faceIndex: Int, personID: String)]` (or a `Set<RejectedFaceKey>` — pick a shape the suggestion filter can query cheaply)
  - `CatalogRepository.clearRejectedFacePerson(assetID: AssetID, faceIndex: Int, personID: String) throws`
  - `CatalogRepository.unassignFaces(_ faceIDs: [FaceID]) throws` (delete matching `person_faces` rows)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TeststripCore

final class RejectedFacePeopleTests: XCTestCase {
    private func repo() throws -> CatalogRepository {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rfp-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url); try db.migrate()
        return CatalogRepository(database: db)
    }

    func testRecordAndReadRejection() throws {
        let r = try repo()
        try r.recordRejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        let all = try r.rejectedFacePeople()
        XCTAssertTrue(all.contains { $0.assetID.rawValue == "a" && $0.faceIndex == 0 && $0.personID == "p1" })
    }

    func testUnassignFacesRemovesOnlyTargetedPersonFaces() throws {
        let r = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)], toPersonID: "p1")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 1)], toPersonID: "p1")
        try r.unassignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)])
        // face 0 unassigned, face 1 still assigned:
        XCTAssertEqual(try r.assetIDs(personID: "p1").count, 1)
    }
}
```

> Implementer: confirm the real `FaceID`/`AssetID` initializers and the `assignFaces`/`assetIDs(personID:)` signatures (`CatalogRepository.swift:1166,960`) and adapt the test to them. If `rejectedFacePeople()` returns a different shape, assert against that.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RejectedFacePeopleTests`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Add the migration + repo methods**

In `CatalogMigrations.swift`, add (idempotent `CREATE TABLE IF NOT EXISTS`, appended to the statements list so existing catalogs upgrade):

```sql
CREATE TABLE IF NOT EXISTS rejected_face_people (
    asset_id TEXT NOT NULL,
    face_index INTEGER NOT NULL,
    person_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    PRIMARY KEY (asset_id, face_index, person_id)
)
```
```sql
CREATE INDEX IF NOT EXISTS idx_rejected_face_people_asset ON rejected_face_people(asset_id)
```

In `CatalogRepository.swift`, implement the four methods, mirroring the style of the existing `person_faces` methods (`assignFaces` ~1166, `dismissFaces` ~1202): `recordRejectedFacePerson` = `INSERT OR IGNORE`; `clearRejectedFacePerson` = `DELETE ... WHERE`; `rejectedFacePeople` = `SELECT` all; `unassignFaces` = `DELETE FROM person_faces WHERE asset_id=? AND face_index=?` per face id.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter RejectedFacePeopleTests` then `make test`
Expected: PASS; no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogMigrations.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/RejectedFacePeopleTests.swift
git commit -m "feat: rejected_face_people negative store + unassignFaces"
```

---

### Task 2: Suggestion computation excludes rejected (face, person) pairs

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`refreshPeopleFaceSuggestions` ~3579 and the static `peopleFaceSuggestions(...)` ~3675)
- Test: `Tests/TeststripAppTests/PeopleFaceSuggestionRejectionTests.swift` (create, or extend an existing suggestion test)

**Interfaces:**
- Consumes: `rejectedFacePeople()` (Task 1), the existing `FaceSuggestions` (matches/clusters) input.
- Produces: `peopleFaceSuggestions(...)` gains a `rejectedPairs` input (a `Set` keyed by `(assetID, faceIndex, personID)`); a `.matchExisting` suggestion drops any `faceID` whose `(assetID, faceIndex, personID)` is rejected, and is omitted entirely if no faces remain. `refreshPeopleFaceSuggestions()` loads rejections from the repo and passes them in.

- [ ] **Step 1: Write the failing test**

```swift
func testRejectedFaceIsNotSuggestedForThatPerson() {
    // Build a FaceSuggestions with a match: person p1 <- faces [a#0].
    // With rejectedPairs containing (a,0,p1), peopleFaceSuggestions must NOT
    // include a suggestion proposing p1 for a#0.
    let result = AppModel.peopleFaceSuggestionsForTest(
        matchesPersonID: "p1", faceAsset: "a", faceIndex: 0,
        rejectedPairs: [RejectedFaceKey(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")]
    )
    XCTAssertFalse(result.contains { if case .matchExisting(let pid, _) = $0.kind { return pid == "p1" } else { return false } })
}
```

> Implementer: the static `peopleFaceSuggestions` is `private`. Either make it (or a thin test seam) accessible to `@testable` tests, or test through `refreshPeopleFaceSuggestions()` against a seeded model. Match the real `FaceSuggestions`/`PeopleFaceSuggestion` shapes (`AppModel.swift:883,3675`).

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PeopleFaceSuggestionRejectionTests`
Expected: FAIL — rejected pair still suggested.

- [ ] **Step 3: Implement the exclusion**

Add a `rejectedPairs: Set<RejectedFaceKey>` parameter to the static `peopleFaceSuggestions(...)`. In the `.matches` loop, filter `match.faceIDs` to those NOT in `rejectedPairs` for `match.personID`; skip the suggestion if the filtered set is empty. (Cluster/`.newPerson` suggestions are person-less, so rejections don't apply.) In `refreshPeopleFaceSuggestions()`, `let rejected = try catalog.repository.rejectedFacePeople()` → build the `Set` → pass it in.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PeopleFaceSuggestionRejectionTests` then `make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/PeopleFaceSuggestionRejectionTests.swift
git commit -m "feat: face suggestions skip rejected face/person pairs"
```

---

### Task 3: `PhotoFacesPresentation` (per-photo face rows)

**Files:**
- Create: `Sources/TeststripApp/PhotoFacesPresentation.swift`
- Test: `Tests/TeststripAppTests/PhotoFacesPresentationTests.swift` (create)

**Interfaces:**
- Consumes: `CatalogFaceObservation` (`boundingBox: FaceBoundingBox`, `faceIndex`), `person_faces` for the asset, the asset's `PeopleFaceSuggestion`s, `people` names.
- Produces:
  - `enum PhotoFaceState: Equatable { case confirmed(personID: String, name: String); case suggested(personID: String, name: String); case unnamed }`
  - `struct PhotoFaceRow: Equatable, Identifiable { var faceID: FaceID; var boundingBox: FaceBoundingBox; var state: PhotoFaceState }`
  - `struct PhotoFacesPresentation: Equatable { var rows: [PhotoFaceRow]; init(assetID:, observations: [CatalogFaceObservation], confirmedByFaceIndex: [Int: (personID: String, name: String)], suggestionsByFaceIndex: [Int: (personID: String, name: String)]) }`

- [ ] **Step 1: Write the failing test**

```swift
func testRowsReflectConfirmedSuggestedUnnamed() {
    let obs = [face(0), face(1), face(2)]
    let p = PhotoFacesPresentation(
        assetID: AssetID(rawValue: "a"),
        observations: obs,
        confirmedByFaceIndex: [0: ("p1", "Jesse")],
        suggestionsByFaceIndex: [1: ("p2", "Ann")]
    )
    XCTAssertEqual(p.rows.map(\.state), [
        .confirmed(personID: "p1", name: "Jesse"),
        .suggested(personID: "p2", name: "Ann"),
        .unnamed
    ])
}
```

> Implementer: `confirmed` wins over `suggested` if both exist for a face. Provide the `face(_:)` helper building a `CatalogFaceObservation` with a bbox (match its real init).

- [ ] **Step 2–4: RED → implement (pure mapping) → GREEN + `make test`.**

`init` maps each observation, in `faceIndex` order, to a row: confirmed if in `confirmedByFaceIndex`, else suggested if in `suggestionsByFaceIndex`, else unnamed.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/PhotoFacesPresentation.swift Tests/TeststripAppTests/PhotoFacesPresentationTests.swift
git commit -m "feat: PhotoFacesPresentation maps a photo's faces to editable rows"
```

---

### Task 4: AppModel per-face edit gestures

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/PhotoFaceEditTests.swift` (create)

**Interfaces:**
- Consumes: `assignFaces`, `unassignFaces`, `recordRejectedFacePerson`, `clearRejectedFacePerson`, `upsertPerson`, `refreshPeopleFaceSuggestions`, the `people` list.
- Produces (all write ONLY on the call, then refresh suggestions):
  - `nameFace(_ faceID: FaceID, personID: String) throws` → `assignFaces` + `clearRejectedFacePerson` (a positive overrides a prior negative).
  - `nameFace(_ faceID: FaceID, newPersonName: String) throws` → create person (`upsertPerson` with a fresh id, mirroring `confirmPeopleFaceSuggestion`'s id scheme) then `assignFaces`.
  - `removeFacePerson(_ faceID: FaceID) throws` → `unassignFaces([faceID])`.
  - `rejectFaceSuggestion(_ faceID: FaceID, personID: String) throws` → `recordRejectedFacePerson` + `refreshPeopleFaceSuggestions`.

- [ ] **Step 1: Write the failing test** (confirm-before-write is the load-bearing assertion)

```swift
func testNameFaceWritesPersonFaceOnlyOnGesture() throws {
    let model = try PhotoFaceFixture.assetWithOneFace(assetID: "a") // no person_faces yet
    XCTAssertTrue(try model.catalogPersonFaces(assetID: "a").isEmpty)   // negative before gesture
    try model.nameFace(FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0), newPersonName: "Jesse")
    XCTAssertEqual(try model.catalogPersonFaces(assetID: "a").count, 1) // written only now
}

func testRejectRecordsNegativeAndRemoveClearsPerson() throws {
    let model = try PhotoFaceFixture.assetWithOneFace(assetID: "a")
    try model.rejectFaceSuggestion(FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0), personID: "p1")
    XCTAssertTrue(try model.catalog!.repository.rejectedFacePeople().contains { $0.assetID.rawValue == "a" && $0.personID == "p1" })
    try model.nameFace(FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0), personID: "p1")
    try model.removeFacePerson(FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0))
    XCTAssertTrue(try model.catalogPersonFaces(assetID: "a").isEmpty)
}
```

> Implementer: build the fixture the way existing People/face tests seed a model with faces (search `Tests/TeststripAppTests` for face/`assignFaces`/`PeopleFaceSuggestion` tests and mirror them). Add tiny `@testable` read helpers if none exist. Match real `FaceID` init.

- [ ] **Step 2–4: RED → implement → GREEN + `make test`.**

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/PhotoFaceEditTests.swift
git commit -m "feat: per-face name/remove/reject gestures (confirm-before-write)"
```

---

### Task 5: Allow the inspector on the single-image view

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`WorkspaceChromePolicy.showsInspector` ~7766) and the app-level inspector gate (`main.swift:50-52`) / loupe stage placement
- Test: `Tests/TeststripAppTests/` — extend `WorkspaceChromePolicy` / chrome tests

**Interfaces:**
- Consumes: `WorkspaceChromePolicy`, the loupe stage `HStack` (`LibraryGridView.swift:3842`).

> Layout is verified by the Phase-D scenario; the policy change is unit-testable.

- [ ] **Step 1: Write/adjust the failing test** — `showsInspector` should be true for the single-image/cull context.

Today `showsInspector(_ workspace:) -> Bool` returns `workspace != .cull`. Decide the exact predicate: the inspector should be available whenever a single photo is up (Library loupe OR Cull loupe), not the Library grid necessarily. If the policy is workspace-only, extend it to consider the single-image view mode. Write a test asserting the inspector is available in the Cull single-image context and update any test asserting the old `!= .cull` rule.

- [ ] **Step 2–4:** implement the policy change; place the `InspectorView` column as the RIGHT element of the loupe stage `HStack` (`[stack rail | loupe | inspector]`) — or keep the app-level `.inspector(isPresented:)` and just widen the gate, whichever matches how the Library loupe already shows it (the Library loupe uses the app-level inspector at `main.swift:50`; reuse that path so Cull single-image gets the same inspector). Build + `make test`.

- [ ] **Step 5: Commit** `"feat: inspector available on the single-image (cull) view"`.

---

### Task 6: Inspector as stacked sections (retire tabs)

**Files:**
- Modify: `Sources/TeststripApp/InspectorView.swift` (`body` ~556; the `tabBinding`/`InspectorTab` switch)
- Modify: `Sources/TeststripApp/AppModel.swift` (`inspectorTab`, `selectInspectorTab`), `main.swift` (tab menu items → scroll-to-section), and `MenuCoveragePresentation`/its tests
- Test: extend `InspectorTabsPresentationTests` / add a stacked-section presentation test

**Interfaces:**
- Consumes: the existing `infoTabBody`/`describeTabBody`/`aiTabBody` (become section bodies) + the new `peopleSectionBody` (Task 7).

> UI restructure — verified by the Phase-D scenario. Keep each section's existing content; only the container changes from tabbed to stacked.

- [ ] **Step 1:** Replace the segmented `Picker` + `switch` with a single `ScrollView { VStack { section("Info"){ infoTabBody }; section("Describe"){ describeTabBody }; section("AI"){ aiTabBody }; section("People"){ peopleSectionBody } } }`, each under a section header. Retire `model.inspectorTab` selection; convert the `1/2/3` tab key-equivalents + menu items to scroll-to-section (or drop them if scroll-to-section is out of scope — decide and update `MenuCoveragePresentation` + its coverage test accordingly).
- [ ] **Step 2:** `make build`; fix every reference to the removed tab switching.
- [ ] **Step 3:** `make test`; update `InspectorTabsPresentationTests`/menu-coverage tests to the stacked model.
- [ ] **Step 4: Commit** `"feat: inspector renders Info/Describe/AI/People as stacked sections"`.

---

### Task 7: People inspector section — face-crop list

**Files:**
- Modify: `Sources/TeststripApp/InspectorView.swift` (add `peopleSectionBody(for:)`)
- Create: `Sources/TeststripApp/PhotoFacesSectionView.swift` (the list + per-row controls), if it keeps InspectorView from growing

**Interfaces:**
- Consumes: `PhotoFacesPresentation` (Task 3) built from the selected asset; the Task-4 gestures; the face-crop image source (reuse the preview source + `FaceBoundingBox` to crop, or the recognition thumbnail if one exists).

> UI — verified by the Phase-D scenario.

- [ ] **Step 1:** Render one row per `PhotoFaceRow`: a face crop, the state (`confirmed` name ✓ / `suggested` "guess: <name>" / `unnamed`), and controls — **Add name** (person picker: existing people list + "New person…" → `nameFace(personID:)` / `nameFace(newPersonName:)`), **Confirm** (on a `suggested` row → `nameFace(personID:)`), **Remove** (on a `confirmed` row → `removeFacePerson`), **Not <name>** (on a `suggested` row → `rejectFaceSuggestion`). Hovering/selecting a row publishes the focused `faceID` for the overlay (Task 8) to highlight.
- [ ] **Step 2–3:** `make build` clean; `make test` passes.
- [ ] **Step 4: Commit** `"feat: per-photo People inspector section with face naming controls"`.

---

### Task 8: Face bounding-box overlay on the loupe image

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (the `loupeStage` image; add a boxes overlay)

**Interfaces:**
- Consumes: `PhotoFacesPresentation.rows` (bbox + state), the focused `faceID` from the People section (Task 7).

> UI — verified by the Phase-D scenario.

- [ ] **Step 1:** Overlay each `FaceBoundingBox` (normalized `x/y/w/h`) as a rectangle mapped to the **displayed** (aspect-fit) image frame within the loupe — account for letterboxing/orientation, not raw view bounds. Label each with the name/guess; highlight the box matching the People-section focused face and vice-versa (hover a box → focus the list row). A gate (e.g. only when the People section is visible / a "show faces" toggle) so boxes don't clutter normal culling — decide and note it.
- [ ] **Step 2–3:** `make build`; `make test`.
- [ ] **Step 4: Commit** `"feat: face bounding-box overlay on the loupe, linked to the People section"`.

---

### Task 9: E2E scenario card (VM)

**Files:**
- Create: `test/scenarios/inspector-<nnn>-photo-faces.md`

**Interfaces:**
- Consumes: `script/vm_scenario_run.sh`, `script/ax_drive.sh`.

- [ ] **Step 1:** Author the card. Launch a seeded catalog with faces (the `faces` fixture); open a photo → single-image view shows the inspector with **Info / Describe / AI / People stacked**; the People section lists the faces and boxes appear on the image; **add a name** to an unnamed face and assert (via `sql`) a `person_faces` row appears ONLY after the gesture; **reject a guess** ("Not <name>") and assert the guess clears, a `rejected_face_people` row appears, and re-running suggestions no longer proposes that person for that face; **remove** a confirmed name and assert the row is gone. Re-assert **confirm-before-write** (no `person_faces`/`rejected_face_people` writes before gestures) and non-destructive (no sidecar changes). Mark `## Run status: NOT RUN` (source-cited; controller drives the live run).
- [ ] **Step 2:** Commit the card (+ LEDGER row).

```bash
git add test/scenarios/
git commit -m "test: e2e scenario — single-image inspector + per-photo face naming"
```

---

## Self-Review

**Spec coverage:**
- Container (inspector on single-image view) → Task 5. ✅
- Inspector stacked sections → Task 6. ✅
- People section face-crop list + gestures → Tasks 3 (presentation), 4 (gestures), 7 (list). ✅
- Box overlay on the image → Task 8. ✅
- Negative store + suggestion exclusion → Tasks 1 (store + `unassignFaces`), 2 (exclusion). ✅
- Confirm-before-write → asserted in Tasks 4 and 9. ✅
- Testing: unit (1–4), UI-by-scenario (5–8), e2e (9). ✅
- Spec open items: inspector-coexist width → Task 5/8 notes; box coordinate mapping → Task 8 Step 1; new-person path → Task 4 (reuse `upsertPerson`+`assignFaces`); suggestion scoping → Task 2. ✅

**Placeholder scan:** No "TBD/handle edge cases". Test-fixture/seam references are directed to existing patterns the implementer must locate, not blanks. Two conscious decisions are delegated to implementation with explicit "decide and note it" (tab key-equivalents in Task 6; boxes visibility gate in Task 8) — flag either to the controller if they turn out to be product calls.

**Type consistency:** `FaceID`, `PhotoFaceRow`/`PhotoFaceState`/`PhotoFacesPresentation` (Task 3) consumed by Tasks 7/8; `nameFace`/`removeFacePerson`/`rejectFaceSuggestion` (Task 4) consumed by Task 7; `rejectedFacePeople`/`unassignFaces`/`recordRejectedFacePerson` (Task 1) consumed by Tasks 2/4; the `rejectedPairs` param (Task 2) matches the Task-1 store shape.
