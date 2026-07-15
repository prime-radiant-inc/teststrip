# People Surfacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface already-captured person data — show a person's AI-proposed
(unconfirmed) photos in a separate, actionable "Proposed" section, and draw the
person's best confirmed face as the key photo on People-page cards.

**Architecture:** Two new read-only `CatalogRepository` queries (proposed
faces for a person name; best confirmed face per person), surfaced on
`AppModel` as `proposedPhotos` and `personKeyFaces`, and rendered by adding a
Proposed section to the flat `.grid` view and swapping the gradient circle on
`namedPersonCard` for a face crop. Confirm/reject reuse sub-project 1's existing
`confirmAIFace` / `rejectFaceSuggestion`. No worker, capture, or schema changes.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, SQLite via the project's
`CatalogDatabase`/`CatalogRepository`.

## Global Constraints

- **Auto-apply with provenance.** Proposed (AI-unconfirmed) matches must never
  reach Picks/export/destructive ops. They live in their own `proposedPhotos`
  array, never in `model.assets`. ✓ is an explicit confirm (→ `origin='user'`);
  ✗ is an explicit sticky reject (`rejected_face_people`).
- **Reuse, don't reinvent, the confirm/reject paths.** ✓ calls the existing
  `AppModel.confirmAIFace(assetID:faceIndex:)`; ✗ calls the existing
  `AppModel.rejectFaceSuggestion(_ faceID: FaceID, personID: String)`.
- **Provenance for face reads** is `AppleVisionEvaluationProvider.faceProvenance`
  (`provider:"face-recognition", model:"auraface-v1", version:"1",
  settingsHash:"default"`). Face reads that touch `face_observations` are
  provenance-scoped exactly as `confirmedFaceEmbeddingsByPerson` is.
- **DRY / YAGNI / TDD / frequent commits.** No key-photo schema column (derive
  at read time). No user-pickable key photo. No per-cell ✨ badge.
- All work is on branch `feat/people-surfacing`. Build: `swift build`. Test a
  file: `swift test --filter <SuiteName>`.

---

### Task 1: Repository read — best confirmed face per person

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add near
  `confirmedFaceEmbeddingsByPerson`, ~line 1234; the private
  `FaceObservationPayload` struct at ~line 3306 and `decode(_:from:)` are in the
  same file and reusable)
- Test: `Tests/TeststripCoreTests/PersonSurfacingQueriesTests.swift` (new)

**Interfaces:**
- Produces:
  - `public struct PersonKeyFace: Equatable, Sendable { let assetID: AssetID; let faceIndex: Int; let boundingBox: FaceBoundingBox; let captureQuality: Double? }`
  - `public func keyFacesByPerson(provenance: ProviderProvenance) throws -> [String: PersonKeyFace]` (personID → highest-captureQuality confirmed face)

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/PersonSurfacingQueriesTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class PersonSurfacingQueriesTests: XCTestCase {
    private func repo() throws -> (CatalogRepository, CatalogDatabase) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("psq-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url); try db.migrate()
        return (CatalogRepository(database: db), db)
    }

    private let prov = AppleVisionEvaluationProvider.faceProvenance

    private func box(_ v: Double) -> FaceBoundingBox {
        FaceBoundingBox(x: v, y: v, width: 0.1, height: 0.1)
    }

    private func obs(_ asset: String, _ index: Int, quality: Double?, box boxV: Double) -> CatalogFaceObservation {
        CatalogFaceObservation(assetID: AssetID(rawValue: asset), faceIndex: index,
                               boundingBox: box(boxV), captureQuality: quality,
                               embedding: [0.1, 0.2], provenance: prov)
    }

    func testKeyFacePicksHighestCaptureQualityConfirmedFace() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        try r.replaceFaceObservations(assetID: AssetID(rawValue: "a1"), provenance: prov,
                                      with: [obs("a1", 0, quality: 0.4, box: 0.1)])
        try r.replaceFaceObservations(assetID: AssetID(rawValue: "a2"), provenance: prov,
                                      with: [obs("a2", 0, quality: 0.9, box: 0.2)])
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a1"), faceIndex: 0)], toPersonID: "p1")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a2"), faceIndex: 0)], toPersonID: "p1")

        let key = try XCTUnwrap(r.keyFacesByPerson(provenance: prov)["p1"])
        XCTAssertEqual(key.assetID, AssetID(rawValue: "a2"))
        XCTAssertEqual(key.captureQuality, 0.9)
        XCTAssertEqual(key.boundingBox, box(0.2))
    }

    func testKeyFaceHandlesNilCaptureQualityAndIsDeterministic() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        try r.replaceFaceObservations(assetID: AssetID(rawValue: "a1"), provenance: prov,
                                      with: [obs("a1", 0, quality: nil, box: 0.1)])
        try r.replaceFaceObservations(assetID: AssetID(rawValue: "a2"), provenance: prov,
                                      with: [obs("a2", 0, quality: nil, box: 0.2)])
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a1"), faceIndex: 0)], toPersonID: "p1")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a2"), faceIndex: 0)], toPersonID: "p1")

        // Deterministic: with equal (nil) quality, the first by (asset,face) order wins.
        let key = try XCTUnwrap(r.keyFacesByPerson(provenance: prov)["p1"])
        XCTAssertEqual(key.assetID, AssetID(rawValue: "a1"))
    }

    func testKeyFaceAbsentForWholeAssetConfirmedPerson() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        // Whole-asset confirm: person_assets row, no person_faces.
        try r.assignAssets([AssetID(rawValue: "a1")], toPersonID: "p1")
        XCTAssertNil(try r.keyFacesByPerson(provenance: prov)["p1"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PersonSurfacingQueriesTests`
Expected: FAIL — `value of type 'CatalogRepository' has no member 'keyFacesByPerson'` (compile error).

- [ ] **Step 3: Write minimal implementation**

Add to `CatalogRepository.swift` (immediately after `confirmedFaceEmbeddingsByPerson`, ~line 1258). `PersonKeyFace` can go near the other public catalog value types (e.g. next to `CatalogPerson`) or just above this method:

```swift
public struct PersonKeyFace: Equatable, Sendable {
    public let assetID: AssetID
    public let faceIndex: Int
    public let boundingBox: FaceBoundingBox
    public let captureQuality: Double?

    public init(assetID: AssetID, faceIndex: Int, boundingBox: FaceBoundingBox, captureQuality: Double?) {
        self.assetID = assetID
        self.faceIndex = faceIndex
        self.boundingBox = boundingBox
        self.captureQuality = captureQuality
    }
}

/// The person's single best (highest `captureQuality`) CONFIRMED face, keyed
/// by person id — the People-card key photo. Clones the join/provenance scope
/// of `confirmedFaceEmbeddingsByPerson`, but returns the box/quality/face id
/// rather than only the embedding. `captureQuality` lives inside `face_json`
/// (not a column), so the max is taken in Swift; `nil` ranks lowest, and the
/// stable SQL order makes ties deterministic (first by asset then face index).
public func keyFacesByPerson(provenance: ProviderProvenance) throws -> [String: PersonKeyFace] {
    let rows = try database.rows(
        """
        SELECT person_faces.person_id AS person_id,
               person_faces.asset_id AS asset_id,
               person_faces.face_index AS face_index,
               face_observations.face_json AS face_json
        FROM person_faces
        JOIN face_observations
          ON face_observations.asset_id = person_faces.asset_id
         AND face_observations.face_index = person_faces.face_index
        WHERE face_observations.provider = ? AND face_observations.model = ?
          AND face_observations.version = ? AND face_observations.settings_hash = ?
          AND person_faces.origin = 'user'
        ORDER BY person_faces.person_id ASC, person_faces.asset_id ASC, person_faces.face_index ASC
        """,
        bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
    )
    var best: [String: PersonKeyFace] = [:]
    for row in rows {
        guard let personID = row["person_id"],
              let assetID = row["asset_id"],
              let faceIndexValue = row["face_index"], let faceIndex = Int(faceIndexValue),
              let faceJSON = row["face_json"] else {
            throw CatalogError.sqlite("key face row is missing required columns")
        }
        let payload = try decode(FaceObservationPayload.self, from: faceJSON)
        let candidate = PersonKeyFace(
            assetID: AssetID(rawValue: assetID),
            faceIndex: faceIndex,
            boundingBox: payload.boundingBox,
            captureQuality: payload.captureQuality
        )
        if let existing = best[personID] {
            if (candidate.captureQuality ?? -1) > (existing.captureQuality ?? -1) {
                best[personID] = candidate
            }
        } else {
            best[personID] = candidate
        }
    }
    return best
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PersonSurfacingQueriesTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/PersonSurfacingQueriesTests.swift
git commit -m "feat: keyFacesByPerson — best confirmed face per person"
```

---

### Task 2: Repository read — a person's proposed (AI-unconfirmed) faces

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add next to Task 1's method)
- Test: `Tests/TeststripCoreTests/PersonSurfacingQueriesTests.swift` (extend)

**Interfaces:**
- Consumes: `insertAIFace(assetID:faceIndex:personID:)`, `confirmFace(assetID:faceIndex:)`, `unassignFaces(_:)` (existing).
- Produces:
  - `public struct ProposedPersonFace: Equatable, Sendable { let personID: String; let assetID: AssetID; let faceIndex: Int }`
  - `public func proposedPersonFaces(personName: String) throws -> [ProposedPersonFace]`

- [ ] **Step 1: Write the failing test**

Append to `PersonSurfacingQueriesTests.swift`:

```swift
extension PersonSurfacingQueriesTests {
    func testProposedFacesReturnsAIFacesNotYetConfirmed() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        try r.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")

        let proposed = try r.proposedPersonFaces(personName: "Dan Shapiro")
        XCTAssertEqual(proposed, [ProposedPersonFace(personID: "p1", assetID: AssetID(rawValue: "a1"), faceIndex: 0)])
    }

    func testProposedFacesExcludesConfirmedAsset() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        try r.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        try r.confirmFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0) // now in person_assets
        XCTAssertTrue(try r.proposedPersonFaces(personName: "Dan Shapiro").isEmpty)
    }

    func testProposedFacesExcludesRejectedFace() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        try r.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        // Reject = unassign the person_faces row + record the sticky negative.
        try r.unassignFaces([FaceID(assetID: AssetID(rawValue: "a1"), faceIndex: 0)])
        try r.recordRejectedFacePerson(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        XCTAssertTrue(try r.proposedPersonFaces(personName: "Dan Shapiro").isEmpty)
    }

    func testProposedFacesMatchesNameCaseInsensitively() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        try r.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        XCTAssertEqual(try r.proposedPersonFaces(personName: "dan shapiro").count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PersonSurfacingQueriesTests`
Expected: FAIL — `has no member 'proposedPersonFaces'`.

- [ ] **Step 3: Write minimal implementation**

Add to `CatalogRepository.swift` next to `keyFacesByPerson`:

```swift
public struct ProposedPersonFace: Equatable, Sendable {
    public let personID: String
    public let assetID: AssetID
    public let faceIndex: Int

    public init(personID: String, assetID: AssetID, faceIndex: Int) {
        self.personID = personID
        self.assetID = assetID
        self.faceIndex = faceIndex
    }
}

/// A named person's PROPOSED faces: `person_faces.origin='ai'` rows for a
/// person whose asset is not already in that person's confirmed
/// `person_assets`. Matched by name (case-insensitive), like the `.person`
/// filter, and returns `person_id` too so the reject action (keyed by person)
/// targets the right person when two people share a name. Rejected faces are
/// absent by construction: rejecting deletes the `origin='ai'` row.
public func proposedPersonFaces(personName: String) throws -> [ProposedPersonFace] {
    let rows = try database.rows(
        """
        SELECT pf.person_id AS person_id, pf.asset_id AS asset_id, pf.face_index AS face_index
        FROM person_faces pf
        JOIN people ON people.id = pf.person_id AND people.name = ? COLLATE NOCASE
        WHERE pf.origin = 'ai'
          AND NOT EXISTS (
              SELECT 1 FROM person_assets pa
              WHERE pa.person_id = pf.person_id AND pa.asset_id = pf.asset_id
          )
        ORDER BY pf.asset_id ASC, pf.face_index ASC
        """,
        bindings: [personName]
    )
    return try rows.map { row in
        guard let personID = row["person_id"], let assetID = row["asset_id"],
              let faceIndexValue = row["face_index"], let faceIndex = Int(faceIndexValue) else {
            throw CatalogError.sqlite("proposed person face row is missing required columns")
        }
        return ProposedPersonFace(personID: personID, assetID: AssetID(rawValue: assetID), faceIndex: faceIndex)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PersonSurfacingQueriesTests`
Expected: PASS (7 tests total in the suite).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/PersonSurfacingQueriesTests.swift
git commit -m "feat: proposedPersonFaces — a person's AI-unconfirmed faces"
```

---

### Task 3: Person cards show the best confirmed face

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `personKeyFaces` state +
  `loadCatalogPeople()`; route the existing `catalogPeople = try
  catalog.repository.people()` sites — at ~3559, 3582, 3595, 3678, 3700, 3804 —
  through it)
- Modify: `Sources/TeststripApp/PeopleView.swift` (`NamedPersonPresentation`
  ~819-833; `PeoplePresentation.init` ~574-585; `namedPersonCard` ~421-464; the
  `PeoplePresentation(...)` construction ~line 20-30)
- Test: `Tests/TeststripAppTests/PersonKeyFacePresentationTests.swift` (new)

**Interfaces:**
- Consumes: `CatalogRepository.keyFacesByPerson(provenance:)` (Task 1),
  `AppleVisionEvaluationProvider.faceProvenance`,
  `FaceCropAvatar(previewURL:boundingBox:)`,
  `AppModel.previewURL(for:levels:)`.
- Produces: `AppModel.personKeyFaces: [String: PersonKeyFace]`;
  `NamedPersonPresentation.keyFace: PersonKeyFace?`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/PersonKeyFacePresentationTests.swift`:

```swift
import XCTest
import TeststripCore
@testable import TeststripApp

final class PersonKeyFacePresentationTests: XCTestCase {
    private func person(_ id: String, _ name: String, count: Int) -> CatalogPerson {
        CatalogPerson(id: id, name: name, assetCount: count)
    }

    func testNamedPersonPresentationCarriesKeyFaceWhenPresent() {
        let key = PersonKeyFace(assetID: AssetID(rawValue: "a2"), faceIndex: 0,
                                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                                captureQuality: 0.9)
        let presentation = PeoplePresentation(
            totalAssetCount: 0,
            namedPeople: [person("p1", "Ann", count: 3)],
            evaluationSummaries: [],
            keyFaces: ["p1": key]
        )
        XCTAssertEqual(presentation.namedPeople.first?.keyFace, key)
    }

    func testNamedPersonPresentationKeyFaceNilWhenAbsent() {
        let presentation = PeoplePresentation(
            totalAssetCount: 0,
            namedPeople: [person("p1", "Ann", count: 3)],
            evaluationSummaries: [],
            keyFaces: [:]
        )
        XCTAssertNil(presentation.namedPeople.first?.keyFace)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PersonKeyFacePresentationTests`
Expected: FAIL — `PeoplePresentation` has no `keyFaces:` parameter / `NamedPersonPresentation` has no `keyFace`.

- [ ] **Step 3: Write minimal implementation**

In `PeopleView.swift`, extend `NamedPersonPresentation` (~819):

```swift
struct NamedPersonPresentation: Equatable, Identifiable {
    var id: String
    var name: String
    var assetCount: Int
    var keyFace: PersonKeyFace?

    init(person: CatalogPerson, keyFace: PersonKeyFace? = nil) {
        self.id = person.id
        self.name = person.name
        self.assetCount = person.assetCount
        self.keyFace = keyFace
    }

    var countText: String {
        assetCount == 1 ? "1 confirmed photo" : "\(assetCount) confirmed photos"
    }
}
```

Add a `keyFaces` parameter to `PeoplePresentation.init` (~574) and thread it into the map (~585):

```swift
    init(
        totalAssetCount: Int,
        namedPeople: [CatalogPerson] = [],
        evaluationSummaries: [CatalogEvaluationKindSummary],
        canRequestCurrentScopeFaceScan: Bool = false,
        faceSuggestions: [PeopleFaceSuggestion] = [],
        faceObservationAssetCount: Int = 0,
        hasUnavailableSources: Bool = false,
        keyFaces: [String: PersonKeyFace] = [:]
    ) {
        self.hasUnavailableSources = hasUnavailableSources
        self.totalAssetCount = totalAssetCount
        self.namedPeople = namedPeople.map { NamedPersonPresentation(person: $0, keyFace: keyFaces[$0.id]) }
        // …rest unchanged…
```

In `AppModel.swift`, add the state (near `catalogPeople`, ~2242) and a loader; add `import`/reference to `AppleVisionEvaluationProvider` is already available in this module:

```swift
public var personKeyFaces: [String: PersonKeyFace] = [:]

/// Loads confirmed-people + their key faces together so People cards never
/// show a face for a stale person set. Replaces bare
/// `catalogPeople = try catalog.repository.people()` assignments.
private func loadCatalogPeople() throws {
    guard let catalog else { return }
    catalogPeople = try catalog.repository.people()
    personKeyFaces = try catalog.repository.keyFacesByPerson(provenance: AppleVisionEvaluationProvider.faceProvenance)
}
```

Replace each `catalogPeople = try catalog.repository.people()` occurrence (the 6 assignment sites listed in **Files**) with `try loadCatalogPeople()`.

Where `PeoplePresentation(...)` is built for the People view (the computed
`presentation` near the top of `PeopleView.swift`, ~line 20-30), pass
`keyFaces: model.personKeyFaces`.

Finally, in `namedPersonCard` (~421), replace the gradient `Circle` block
(lines 423-429) with a key-face-or-gradient choice:

```swift
        if let keyFace = person.keyFace {
            FaceCropAvatar(
                previewURL: model.previewURL(for: keyFace.assetID, levels: [.grid, .medium, .micro]),
                boundingBox: keyFace.boundingBox
            )
        } else {
            Circle()
                .fill(avatarGradient(seed: person.id, colors: [.orange, .pink]))
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12))
                }
        }
```

(`FaceCropAvatar` already renders a neutral `.quaternary` circle while a preview
is uncached and fills in the face when it loads, so a `keyFace` with no cached
preview degrades gracefully — no blank card.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PersonKeyFacePresentationTests`
Expected: PASS (2 tests). Then `swift build` to confirm the card + call-site
edits compile.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/PeopleView.swift Tests/TeststripAppTests/PersonKeyFacePresentationTests.swift
git commit -m "feat: People cards show the person's best confirmed face"
```

---

### Task 4: Proposed-photos model + confirm/reject actions

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `proposedPhotos` state +
  `ProposedPersonPhoto`; call `refreshProposedAssets()` in `reload()` ~10080;
  add `confirmProposedPhoto`/`rejectProposedPhoto`)
- Test: `Tests/TeststripAppTests/ProposedAssetsPresentationTests.swift` (new)

**Interfaces:**
- Consumes: `CatalogRepository.proposedPersonFaces(personName:)` (Task 2),
  `currentLibraryQuery()`, `catalog.repository.assets(ids:flag:limit:)`,
  `confirmAIFace(assetID:faceIndex:)`, `rejectFaceSuggestion(_:personID:)`,
  `reload()`.
- Produces:
  - `public struct ProposedPersonPhoto: Identifiable, Equatable { let asset: Asset; let faces: [ProposedPersonFace]; var id: String { asset.id.rawValue } }`
  - `AppModel.proposedPhotos: [ProposedPersonPhoto]`
  - `AppModel.confirmProposedPhoto(_:) throws`, `AppModel.rejectProposedPhoto(_:) throws`

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/ProposedAssetsPresentationTests.swift`. The
`makeAsset` / `makeModelWithCatalogAssets` / `makeTemporaryDirectory` helpers
are `private` per test file (see `AppModelFilterPersistenceTests.swift:221-267`),
so copy them into this file. `makeModelWithCatalogAssets` returns
`(AppModel, CatalogRepository)` — seed the repository directly:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class ProposedAssetsPresentationTests: XCTestCase {
    func testLonePersonQueryPopulatesProposedPhotos() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let a2 = makeAsset(id: "a2", path: "/Photos/a2.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-lone-person", assets: [a1, a2])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        // a1 confirmed for the person; a2 only AI-proposed.
        try repository.assignAssets([AssetID(rawValue: "a1")], toPersonID: "p1")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a2"), faceIndex: 0, personID: "p1")

        try model.showPersonPhotos(named: "Dan Shapiro")

        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "a1")])
        XCTAssertEqual(model.proposedPhotos.map(\.asset.id), [AssetID(rawValue: "a2")])
        XCTAssertEqual(model.proposedPhotos.first?.faces.map(\.faceIndex), [0])
    }

    func testNonPersonQueryClearsProposedPhotos() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-cleared", assets: [a1])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")

        try model.showPersonPhotos(named: "Dan Shapiro")
        XCTAssertEqual(model.proposedPhotos.count, 1)

        model.librarySearchText = "" // no predicate
        try model.reload()
        XCTAssertTrue(model.proposedPhotos.isEmpty)
    }

    func testConfirmProposedPhotoMovesItToConfirmed() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-confirm", assets: [a1])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        try model.showPersonPhotos(named: "Dan Shapiro")

        let photo = try XCTUnwrap(model.proposedPhotos.first)
        try model.confirmProposedPhoto(photo)

        XCTAssertTrue(model.proposedPhotos.isEmpty)
        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "a1")]) // now confirmed
    }

    func testRejectProposedPhotoRemovesItStickily() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-reject", assets: [a1])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        try model.showPersonPhotos(named: "Dan Shapiro")

        let photo = try XCTUnwrap(model.proposedPhotos.first)
        try model.rejectProposedPhoto(photo)

        XCTAssertTrue(model.proposedPhotos.isEmpty)
        XCTAssertTrue(try repository.rejectedFacePeople().contains(
            RejectedFacePerson(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")))
    }

    // MARK: - Test helpers (copied from AppModelFilterPersistenceTests.swift:221-267)

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 0, colorLabel: nil, flag: nil, keywords: [])
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProposedAssetsPresentationTests`
Expected: FAIL — `AppModel` has no `proposedPhotos` / `confirmProposedPhoto`.

- [ ] **Step 3: Write minimal implementation**

In `AppModel.swift`, add the UI model type (near other public presentation
structs) and state (near `catalogPeople`):

```swift
public struct ProposedPersonPhoto: Identifiable, Equatable {
    public let asset: Asset
    public let faces: [ProposedPersonFace]
    public var id: String { asset.id.rawValue }
}

public var proposedPhotos: [ProposedPersonPhoto] = []
```

Add the refresh, gated on a lone `.person` predicate (and no explicit-set mode):

```swift
/// A person's PROPOSED photos — shown as a separate section below the
/// confirmed grid — are computed only when the active query is exactly one
/// `.person(name)` predicate; otherwise cleared. Proposed assets are kept in
/// their own array (never `model.assets`) so tentative matches never reach
/// Picks/export/destructive ops.
private func refreshProposedAssets() throws {
    guard let catalog,
          selectedExplicitAssetIDs == nil,
          let query = currentLibraryQuery(),
          query.predicates.count == 1,
          case .person(let name) = query.predicates[0] else {
        proposedPhotos = []
        return
    }
    let proposed = try catalog.repository.proposedPersonFaces(personName: name)
    guard !proposed.isEmpty else {
        proposedPhotos = []
        return
    }
    var order: [AssetID] = []
    var byAsset: [AssetID: [ProposedPersonFace]] = [:]
    for face in proposed {
        if byAsset[face.assetID] == nil { order.append(face.assetID) }
        byAsset[face.assetID, default: []].append(face)
    }
    let assets = try catalog.repository.assets(ids: order, flag: nil, limit: order.count)
    let assetByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    proposedPhotos = order.compactMap { id in
        guard let asset = assetByID[id] else { return nil }
        return ProposedPersonPhoto(asset: asset, faces: byAsset[id] ?? [])
    }
}
```

Call it in `reload()` — add right after `isAutopilotReviewActive = false`
(line 10084), so both the explicit-set early-return path and the normal path
run it:

```swift
        isAutopilotReviewActive = false
        try refreshProposedAssets()
```

Add the actions (near `confirmAIFace`, ~3799). Each acts on all of the
photo's proposed faces, then reloads to refresh both sections:

```swift
/// ✓ on a proposed cell: confirm the person's proposed face(s) on this asset
/// (promote `origin='ai'→'user'` + link into the confirmed set), then reload
/// so the photo leaves Proposed and joins the confirmed grid.
public func confirmProposedPhoto(_ photo: ProposedPersonPhoto) throws {
    for face in photo.faces {
        try confirmAIFace(assetID: face.assetID, faceIndex: face.faceIndex)
    }
    try reload()
}

/// ✗ on a proposed cell: sticky-reject the person's suggested face(s) on this
/// asset (deletes the `origin='ai'` row + records `rejected_face_people`), then
/// reload so the photo leaves Proposed for good.
public func rejectProposedPhoto(_ photo: ProposedPersonPhoto) throws {
    for face in photo.faces {
        try rejectFaceSuggestion(FaceID(assetID: face.assetID, faceIndex: face.faceIndex), personID: face.personID)
    }
    try reload()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProposedAssetsPresentationTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/ProposedAssetsPresentationTests.swift
git commit -m "feat: proposed-photos model with confirm/reject actions"
```

---

### Task 5: Proposed section in the library grid

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`assetGrid` ~2347-2428;
  reuse the private `AssetGridCell` ~9245 and the Timeline `daySection` header
  pattern ~7460)

**Interfaces:**
- Consumes: `AppModel.proposedPhotos`, `AppModel.confirmProposedPhoto(_:)`,
  `AppModel.rejectProposedPhoto(_:)`; `AssetGridCell`; `model.gridPreviewURL`,
  `model.previewCacheGeneration`, `model.gridPreviewStatus`.
- Produces: a rendered "✨ Proposed" section below the confirmed grid, present
  only when `proposedPhotos` is non-empty.

This task is UI rendering; verify with `swift build` and the e2e card (Task 6)
rather than a unit test (SwiftUI body assembly is not unit-testable here, and
the model logic is already covered by Task 4).

- [ ] **Step 1: Add the Proposed section to `assetGrid`**

In `assetGrid` (`LibraryGridView.swift`), after the confirmed `LazyVGrid`'s
closing `}` and its `.padding(12)` (line 2426), still inside the outer
`VStack`, append:

```swift
            if !model.proposedPhotos.isEmpty {
                proposedSection
            }
```

- [ ] **Step 2: Implement `proposedSection` and the proposed cell**

Add these as private members of the view (near `assetGrid`), following the
Timeline `daySection` header idiom (title + count) and mirroring the confirmed
grid's `AssetGridCell` construction:

```swift
    private var proposedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Proposed")
                    .font(.subheadline.weight(.semibold))
                Text("\(model.proposedPhotos.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            LazyVGrid(columns: columns, spacing: gridLayout.gridSpacing) {
                ForEach(model.proposedPhotos) { photo in
                    proposedCell(photo)
                }
            }
            .padding(12)
        }
    }

    private func proposedCell(_ photo: ProposedPersonPhoto) -> some View {
        AssetGridCell(
            asset: photo.asset,
            previewURL: model.gridPreviewURL(for: photo.asset.id),
            previewCacheGeneration: model.previewCacheGeneration(for: photo.asset.id),
            previewStatus: model.gridPreviewStatus(for: photo.asset.id),
            isSelected: false
        )
        .overlay(alignment: .topLeading) {
            proposedActionButton(systemImage: "xmark", help: "Not this person") {
                runProposedAction { try model.rejectProposedPhoto(photo) }
            }
            .padding(6)
        }
        .overlay(alignment: .bottomTrailing) {
            proposedActionButton(systemImage: "checkmark", help: "Confirm this person") {
                runProposedAction { try model.confirmProposedPhoto(photo) }
            }
            .padding(6)
        }
        .id(photo.asset.id.rawValue)
        .task(id: photo.asset.id.rawValue) {
            do { try model.requestVisibleGridPreview(assetID: photo.asset.id) }
            catch { model.errorMessage = error.localizedDescription }
        }
    }

    private func proposedActionButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func runProposedAction(_ body: () throws -> Void) {
        do { try body() } catch { model.errorMessage = error.localizedDescription }
    }
```

> If `columns`, `gridLayout`, and `requestVisibleGridPreview` are not in scope
> exactly as named where you place these, use the same references the confirmed
> `assetGrid` uses a few lines above (it reads `columns`,
> `gridLayout.gridSpacing`, and calls `model.requestVisibleGridPreview`).

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!` with no new warnings.

- [ ] **Step 4: Sanity-run the existing app test suites touched by the file**

Run: `swift test --filter LibraryGrid`
Expected: PASS (existing LibraryGrid* suites still green — no regression from
the `assetGrid` edit).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: Proposed section with inline confirm/reject in a person's grid"
```

---

### Task 6: End-to-end scenario card

**Files:**
- Create: `test/scenarios/people-022-proposed-and-key-photo.md`

This is a scenario card for the AX/VM harness (VM + AuraFace-bound; authored
here, run later per `test/scenarios/README.md`). No code.

- [ ] **Step 1: Write the card**

Create `test/scenarios/people-022-proposed-and-key-photo.md`, following the
format of `test/scenarios/people-021-face-group-review.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add test/scenarios/people-022-proposed-and-key-photo.md
git commit -m "test: scenario card — Proposed section + key-photo (people-022)"
```

---

## Notes for the executor

- After Task 5, run the **full** `swift test` once to confirm no cross-suite
  regressions before the whole-branch review.
- Tasks 1→2 and 3 are independent; 4 depends on 2; 5 depends on 4; 6 depends on
  all. Keep the plan order.
- Whole-branch review focus: the invariant (proposed never in `model.assets`),
  the lone-`.person` gate (cleared on every non-matching `reload()`), and that
  the 6 `catalogPeople` assignment sites were all routed through
  `loadCatalogPeople()` (no stale key faces).
