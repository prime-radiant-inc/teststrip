# Person Autocompleter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One reusable, face-similarity-ranked person-name autocompleter that
replaces every "select-a-person + New person" flow, plus assign/remove-person on
the loupe face-box overlay.

**Architecture:** A pure Core ranker (`PersonCandidateRanker`) ranks people by
embedding distance to a target face (via the now-public `FaceSuggestionBuilder`
centroid/distance helpers + a `FaceSimilarity` distance→% mapping); `AppModel`
gathers the inputs and exposes `rankedPersonCandidates(forFace:)`. A pure
`PersonAutocompletePresentation` drives a reusable `PersonAutocompleteField`
SwiftUI view (text field + ranked list + "Create '…'" row + keyboard nav). The
face-box overlay's name label becomes an interactive pill opening that field in a
popover; the four existing naming sheets/menus adopt the same field.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, the AuraFace-v1 face-embedding
matcher.

## Global Constraints

- **Similarity ranking:** distance is Euclidean on L2-normalized AuraFace-v1
  vectors; convert to a "similarity %" with cosine `s = 1 − d²/2`, clamped to
  `0…1`, `Int((s*100).rounded())`. The nearest person ranks first.
- **Fallback order (no similarity score):** people with no centroid, and the
  whole-asset "Name selection" case (no target face), order **most-recently-used
  first** (a session-only in-memory list), then alphabetical. `similarityPercent`
  is `nil` for these.
- **Contacts included:** the candidate list unions `catalogPeople` with
  `contactReferenceNamesByPerson()`; not-yet-materialized contacts are rankable
  and selectable, and **picking one materializes it** (gated `upsertPerson`).
- **Provenance:** assigning a face is a user gesture → `origin='user'`
  (`assignFaces`), never tentative. Remove honors origin: confirmed →
  `removeFacePerson` (clean); AI → `rejectFaceSuggestion` (sticky). No sidecar/XMP
  (identity has no XMP field); no originals modified.
- **`SheetScaffold` primary label must be a verb+object** (it asserts; "Create
  Person" is the established value).
- DRY / YAGNI / TDD. Match surrounding style. Test output pristine.
- Branch: `feat/person-autocompleter`. Build: `swift build`. Focused test:
  `swift test --filter <SuiteName>`.

---

### Task 1: Expose ranking primitives + `FaceSimilarity`

**Files:**
- Modify: `Sources/TeststripCore/People/FaceSuggestionBuilder.swift` (three `private static` → `public static`, ~lines 142-171)
- Create: `Sources/TeststripCore/People/FaceSimilarity.swift`
- Test: `Tests/TeststripCoreTests/FaceSimilarityTests.swift` (new)

**Interfaces:**
- Produces:
  - `FaceSuggestionBuilder.normalized(_:) -> [Double]?`, `.centroid(of:) -> [Double]?`, `.distance(_:_:) -> Double?` all `public static` (bodies unchanged).
  - `enum FaceSimilarity { static func percent(distance: Double) -> Int }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/FaceSimilarityTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class FaceSimilarityTests: XCTestCase {
    func testPercentAtZeroDistanceIs100() {
        XCTAssertEqual(FaceSimilarity.percent(distance: 0), 100) // s = 1 − 0 = 1
    }

    func testPercentAtOrthogonalIsZero() {
        // d = √2 → s = 1 − 2/2 = 0
        XCTAssertEqual(FaceSimilarity.percent(distance: 2.0.squareRoot()), 0)
    }

    func testPercentAtMatchThreshold() {
        // d = 1.23 → s = 1 − 1.23²/2 = 0.24355 → 24%
        XCTAssertEqual(FaceSimilarity.percent(distance: 1.23), 24)
    }

    func testPercentClampsNegativeCosineToZero() {
        // d = 2 (antipodal) → s = 1 − 2 = −1 → clamped to 0
        XCTAssertEqual(FaceSimilarity.percent(distance: 2.0), 0)
    }

    func testCentroidAndDistanceArePublic() {
        // Compiles only if the helpers are public.
        let c = FaceSuggestionBuilder.centroid(of: [[1, 0, 0], [1, 0, 0]])
        XCTAssertEqual(c, [1, 0, 0])
        XCTAssertEqual(FaceSuggestionBuilder.distance([1, 0, 0], [1, 0, 0]), 0)
        XCTAssertEqual(FaceSuggestionBuilder.normalized([2, 0, 0]), [1, 0, 0])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FaceSimilarityTests`
Expected: FAIL — no `FaceSimilarity`; and `centroid`/`distance`/`normalized` are inaccessible (private).

- [ ] **Step 3: Write minimal implementation**

In `FaceSuggestionBuilder.swift`, change the three helper declarations from
`private static func` to `public static func` (bodies unchanged):
`public static func normalized(_ vector: [Double]) -> [Double]?`,
`public static func centroid(of vectors: [[Double]]) -> [Double]?`,
`public static func distance(_ lhs: [Double], _ rhs: [Double]) -> Double?`.

Create `Sources/TeststripCore/People/FaceSimilarity.swift`:

```swift
import Foundation

/// Maps a Euclidean distance between L2-normalized AuraFace-v1 face embeddings
/// to a 0–100 "similarity %". For unit vectors, cosine similarity
/// `s = 1 − d²/2`; negative cosine (distance > √2) clamps to 0.
public enum FaceSimilarity {
    public static func percent(distance: Double) -> Int {
        let cosine = 1.0 - (distance * distance) / 2.0
        let clamped = min(max(cosine, 0), 1)
        return Int((clamped * 100).rounded())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FaceSimilarityTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/People/FaceSuggestionBuilder.swift Sources/TeststripCore/People/FaceSimilarity.swift Tests/TeststripCoreTests/FaceSimilarityTests.swift
git commit -m "feat: public centroid/distance helpers + FaceSimilarity percent"
```

---

### Task 2: `PersonCandidateRanker` (pure ranking)

**Files:**
- Create: `Sources/TeststripCore/People/PersonCandidateRanker.swift` (`PersonCandidate` + `PersonCandidateRanker`)
- Test: `Tests/TeststripCoreTests/PersonCandidateRankerTests.swift` (new)

**Interfaces:**
- Consumes: `FaceSuggestionBuilder.normalized`/`distance` (Task 1), `FaceSimilarity.percent` (Task 1).
- Produces:
  - `public struct PersonCandidate: Equatable, Sendable { public let id: String; public let name: String; public let similarityPercent: Int? }`
  - `public enum PersonCandidateRanker { public static func rank(targetEmbedding: [Double]?, centroidsByPerson: [String: [Double]], namesByID: [String: String], recentPersonIDs: [String]) -> [PersonCandidate] }`

**Behavior:** With a `targetEmbedding`, people that have a centroid rank first by
ascending distance (nearest first), each carrying `similarityPercent`; ties break
by name then id. People with **no** centroid — and **all** people when
`targetEmbedding` is nil — come after, ordered by `recentPersonIDs` position
(earlier index = more recent = higher), then alphabetical by name;
`similarityPercent` is nil for them.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/PersonCandidateRankerTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class PersonCandidateRankerTests: XCTestCase {
    private let names = ["p1": "Ann", "p2": "Bob", "p3": "Cy"]

    func testRanksByDistanceNearestFirstWithPercent() {
        let centroids: [String: [Double]] = ["p1": [1, 0, 0], "p2": [0, 1, 0]]
        let result = PersonCandidateRanker.rank(
            targetEmbedding: [1, 0, 0], centroidsByPerson: centroids,
            namesByID: names, recentPersonIDs: [])
        // p1 (distance 0) first at 100%; p2 (distance √2) next at 0%; p3 (no centroid) tail nil.
        XCTAssertEqual(result.map(\.id), ["p1", "p2", "p3"])
        XCTAssertEqual(result[0].similarityPercent, 100)
        XCTAssertEqual(result[1].similarityPercent, 0)
        XCTAssertNil(result[2].similarityPercent)
    }

    func testNoTargetOrdersByRecencyThenAlpha() {
        let result = PersonCandidateRanker.rank(
            targetEmbedding: nil, centroidsByPerson: ["p1": [1, 0, 0]],
            namesByID: names, recentPersonIDs: ["p3"]) // p3 most-recent
        // No target → all tail: p3 (recent) first, then Ann, Bob alpha.
        XCTAssertEqual(result.map(\.id), ["p3", "p1", "p2"])
        XCTAssertTrue(result.allSatisfy { $0.similarityPercent == nil })
    }

    func testNoCentroidPeopleGoToRecencyTail() {
        let centroids: [String: [Double]] = ["p2": [0, 1, 0]]
        let result = PersonCandidateRanker.rank(
            targetEmbedding: [1, 0, 0], centroidsByPerson: centroids,
            namesByID: names, recentPersonIDs: ["p3", "p1"])
        // p2 has a centroid → first (with %); p3, p1 tail by recency order.
        XCTAssertEqual(result.map(\.id), ["p2", "p3", "p1"])
        XCTAssertNotNil(result[0].similarityPercent)
        XCTAssertNil(result[1].similarityPercent)
    }

    func testContactOnlyPersonIsIncludedAndRankable() {
        // A person present only via a contact reference (centroid + name) ranks like any other.
        let result = PersonCandidateRanker.rank(
            targetEmbedding: [1, 0, 0],
            centroidsByPerson: ["contact:C1": [0.99, 0.01, 0]],
            namesByID: ["contact:C1": "Dan"], recentPersonIDs: [])
        XCTAssertEqual(result.map(\.id), ["contact:C1"])
        XCTAssertNotNil(result[0].similarityPercent)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PersonCandidateRankerTests`
Expected: FAIL — no `PersonCandidateRanker`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TeststripCore/People/PersonCandidateRanker.swift`:

```swift
import Foundation

public struct PersonCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let similarityPercent: Int?

    public init(id: String, name: String, similarityPercent: Int?) {
        self.id = id
        self.name = name
        self.similarityPercent = similarityPercent
    }
}

/// Ranks people for the naming autocompleter: by face-similarity to a target
/// face when one is given, else by most-recently-used then alphabetical.
public enum PersonCandidateRanker {
    public static func rank(
        targetEmbedding: [Double]?,
        centroidsByPerson: [String: [Double]],
        namesByID: [String: String],
        recentPersonIDs: [String]
    ) -> [PersonCandidate] {
        let normalizedTarget = targetEmbedding.flatMap(FaceSuggestionBuilder.normalized)

        var scored: [(candidate: PersonCandidate, distance: Double)] = []
        var tailIDs: [String] = []
        for (id, name) in namesByID {
            if let normalizedTarget, let centroid = centroidsByPerson[id],
               let distance = FaceSuggestionBuilder.distance(normalizedTarget, centroid) {
                scored.append((PersonCandidate(id: id, name: name, similarityPercent: FaceSimilarity.percent(distance: distance)), distance))
            } else {
                tailIDs.append(id)
            }
        }

        let ranked = scored.sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.candidate.name != rhs.candidate.name { return lhs.candidate.name < rhs.candidate.name }
            return lhs.candidate.id < rhs.candidate.id
        }.map(\.candidate)

        let recencyIndex = Dictionary(uniqueKeysWithValues: recentPersonIDs.enumerated().map { ($1, $0) })
        let tail = tailIDs.sorted { lhs, rhs in
            let lr = recencyIndex[lhs], rr = recencyIndex[rhs]
            if lr != rr {
                // Present in the recent list sorts before absent; earlier index = more recent = first.
                switch (lr, rr) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            let ln = namesByID[lhs] ?? "", rn = namesByID[rhs] ?? ""
            if ln != rn { return ln < rn }
            return lhs < rhs
        }.map { PersonCandidate(id: $0, name: namesByID[$0] ?? "", similarityPercent: nil) }

        return ranked + tail
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PersonCandidateRankerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/People/PersonCandidateRanker.swift Tests/TeststripCoreTests/PersonCandidateRankerTests.swift
git commit -m "feat: PersonCandidateRanker — similarity + recency ranking"
```

---

### Task 3: AppModel ranking + latent-contact-safe assign

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `recentlyNamedPersonIDs` state + `rankedPersonCandidates(forFace:)`; make `nameFace(_:personID:)` materialize a latent contact; make `nameFace(_:newPersonName:)` dedupe by name; push recency on assign)
- Test: `Tests/TeststripAppTests/RankedPersonCandidatesTests.swift` (new)

**Interfaces:**
- Consumes: `FaceSuggestionBuilder.centroid` (Task 1), `PersonCandidateRanker.rank` (Task 2), `confirmedFaceEmbeddingsByPerson`, `contactReferenceEmbeddingsByPerson`, `contactReferenceNamesByPerson`, `contactReferenceFace(personID:)`, `faceObservations(assetID:)`, `existingPersonID(matchingName:)`.
- Produces: `AppModel.rankedPersonCandidates(forFace faceID: FaceID?) -> [PersonCandidate]`; recency-tracking behavior; latent-contact-safe `nameFace`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/RankedPersonCandidatesTests.swift`. Copy the
`makeModelWithCatalogAssets`/`makeTemporaryDirectory`/`observation`/`makeAsset`
harness from `Tests/TeststripAppTests/FaceGroupReviewTests.swift` (private per
file; the `configureRepository` closure seeds faces/people).

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class RankedPersonCandidatesTests: XCTestCase {
    private let provenance = AppleVisionEvaluationProvider.faceProvenance

    private func obs(_ id: AssetID, _ vec: [Double]) -> CatalogFaceObservation {
        CatalogFaceObservation(assetID: id, faceIndex: 0,
                               boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                               captureQuality: 0.9, embedding: vec, provenance: provenance)
    }

    func testRanksConfirmedPeopleBySimilarityToTargetFace() throws {
        // People + their confirmed faces are seeded BEFORE AppModel.load, which
        // populates catalogPeople via its loadCatalogPeople — so no test shim is
        // needed to refresh catalogPeople.
        let target = makeAsset(id: "t", path: "/p/t.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "rank-similarity", assets: [target]) { repo in
            try repo.replaceFaceObservations(assetID: target.id, provenance: self.provenance, with: [self.obs(target.id, [1, 0, 0])])
            try repo.upsertPerson(id: "p-near", name: "Near")
            try repo.replaceFaceObservations(assetID: AssetID(rawValue: "near"), provenance: self.provenance, with: [self.obs(AssetID(rawValue: "near"), [1, 0, 0])])
            try repo.assignFaces([FaceID(assetID: AssetID(rawValue: "near"), faceIndex: 0)], toPersonID: "p-near")
            try repo.upsertPerson(id: "p-far", name: "Far")
            try repo.replaceFaceObservations(assetID: AssetID(rawValue: "far"), provenance: self.provenance, with: [self.obs(AssetID(rawValue: "far"), [0, 1, 0])])
            try repo.assignFaces([FaceID(assetID: AssetID(rawValue: "far"), faceIndex: 0)], toPersonID: "p-far")
        }

        let ranked = model.rankedPersonCandidates(forFace: FaceID(assetID: target.id, faceIndex: 0))
        XCTAssertEqual(ranked.first?.id, "p-near")
        XCTAssertEqual(ranked.first?.similarityPercent, 100)
        XCTAssertTrue((ranked.first { $0.id == "p-far" }?.similarityPercent ?? 100) < 100)
    }

    func testNoTargetFaceOrdersByRecency() throws {
        // Drive a real assign so recency is exercised honestly (no shim).
        let a = makeAsset(id: "a", path: "/p/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "rank-recency", assets: [a]) { repo in
            try repo.upsertPerson(id: "p1", name: "Ann")
            try repo.upsertPerson(id: "p2", name: "Bob")
            try repo.replaceFaceObservations(assetID: a.id, provenance: self.provenance, with: [self.obs(a.id, [1, 0, 0])])
        }
        // Name a face as p2 (Bob) → p2 becomes most-recently-named.
        try model.nameFace(FaceID(assetID: a.id, faceIndex: 0), personID: "p2")

        let ranked = model.rankedPersonCandidates(forFace: nil)
        XCTAssertEqual(ranked.map(\.id), ["p2", "p1"]) // p2 recent first, then Ann alpha
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RankedPersonCandidatesTests`
Expected: FAIL — no `rankedPersonCandidates`.

- [ ] **Step 3: Write minimal implementation**

In `AppModel.swift`:

Add state near `catalogPeople` (~L2248):

```swift
/// Session-only most-recently-named person ids (most-recent first). Orders the
/// no-similarity tail and the whole-asset naming case in the autocompleter.
public private(set) var recentlyNamedPersonIDs: [String] = []

private func noteRecentlyNamedPerson(_ personID: String) {
    recentlyNamedPersonIDs = [personID] + recentlyNamedPersonIDs.filter { $0 != personID }
}
```

Add the ranker (near `refreshPeopleFaceSuggestions`):

```swift
/// Candidate people for naming a face, ranked by similarity to that face (or
/// most-recently-used when `faceID` is nil), including not-yet-materialized
/// contacts. Reuses the confirmed+contact embedding/name union the matcher uses.
public func rankedPersonCandidates(forFace faceID: FaceID?) -> [PersonCandidate] {
    guard let catalog else { return [] }
    do {
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        var embeddingsByPerson = try catalog.repository.confirmedFaceEmbeddingsByPerson(provenance: provenance)
        for (personID, vectors) in try catalog.repository.contactReferenceEmbeddingsByPerson() {
            embeddingsByPerson[personID, default: []].append(contentsOf: vectors)
        }
        let centroidsByPerson = embeddingsByPerson.compactMapValues(FaceSuggestionBuilder.centroid)

        var namesByID = Dictionary(uniqueKeysWithValues: catalogPeople.map { ($0.id, $0.name) })
        for (personID, name) in try catalog.repository.contactReferenceNamesByPerson() where namesByID[personID] == nil {
            namesByID[personID] = name
        }

        let targetEmbedding: [Double]?
        if let faceID {
            targetEmbedding = try catalog.repository.faceObservations(assetID: faceID.assetID)
                .first { $0.faceIndex == faceID.faceIndex }?.embedding
        } else {
            targetEmbedding = nil
        }

        return PersonCandidateRanker.rank(
            targetEmbedding: targetEmbedding,
            centroidsByPerson: centroidsByPerson,
            namesByID: namesByID,
            recentPersonIDs: recentlyNamedPersonIDs
        )
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}
```

Make `nameFace(_:personID:)` materialize a latent contact (mirror
`confirmPeopleFaceSuggestion(_:)`'s guard) and push recency:

```swift
    public func nameFace(_ faceID: FaceID, personID: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        // A contact-only candidate has no `people` row yet; assignFaces would
        // throw notFound. Materialize it first, exactly as confirmPeopleFaceSuggestion does.
        if catalogPeople.first(where: { $0.id == personID }) == nil,
           let reference = try catalog.repository.contactReferenceFace(personID: personID) {
            try catalog.repository.upsertPerson(id: personID, name: reference.name)
        }
        try catalog.repository.assignFaces([faceID], toPersonID: personID)
        try catalog.repository.clearRejectedFacePerson(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: personID)
        noteRecentlyNamedPerson(personID)
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }
```

Make `nameFace(_:newPersonName:)` dedupe by name (route an existing name to the
existing person id) and push recency:

```swift
    public func nameFace(_ faceID: FaceID, newPersonName: String) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("person name is required")
        }
        let personID = existingPersonID(matchingName: trimmedName) ?? "person-\(UUID().uuidString)"
        try catalog.repository.upsertPerson(id: personID, name: trimmedName)
        try catalog.repository.assignFaces([faceID], toPersonID: personID)
        noteRecentlyNamedPerson(personID)
        try loadCatalogPeople()
        refreshPeopleFaceSuggestions()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RankedPersonCandidatesTests`
Expected: PASS. Then `swift build`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/RankedPersonCandidatesTests.swift
git commit -m "feat: AppModel.rankedPersonCandidates + latent-contact-safe nameFace"
```

---

### Task 4: `PersonAutocompletePresentation` (pure filter/create/focus logic)

**Files:**
- Create: `Sources/TeststripApp/PersonAutocompletePresentation.swift`
- Test: `Tests/TeststripAppTests/PersonAutocompletePresentationTests.swift` (new)

**Interfaces:**
- Consumes: `PersonCandidate` (Task 2).
- Produces:
  - `struct PersonAutocompleteRow: Equatable { enum Kind: Equatable { case person(PersonCandidate); case create(name: String) }; let kind: Kind }`
  - `enum PersonAutocompletePresentation { static func rows(candidates: [PersonCandidate], query: String) -> [PersonAutocompleteRow]; static func clampedFocusIndex(_ index: Int, rowCount: Int) -> Int }`

**Behavior:** `rows` filters candidates by case-insensitive substring of `query`
(empty query → all, order preserved), then appends a `.create(name: trimmedQuery)`
row iff the trimmed query is non-empty AND no candidate name equals it
case-insensitively. `clampedFocusIndex` wraps an index into `0..<rowCount` (for
↑/↓ nav; returns 0 when empty).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import TeststripCore
@testable import TeststripApp

final class PersonAutocompletePresentationTests: XCTestCase {
    private let candidates = [
        PersonCandidate(id: "p1", name: "Ann Lee", similarityPercent: 90),
        PersonCandidate(id: "p2", name: "Bob", similarityPercent: 40),
    ]

    func testEmptyQueryReturnsAllPeopleInOrderNoCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "")
        XCTAssertEqual(rows.map(\.kind), [.person(candidates[0]), .person(candidates[1])])
    }

    func testSubstringFilterPreservesOrderAndAddsCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "an")
        // "an" matches "Ann Lee" only; "an" is not an exact name → a create row appears.
        XCTAssertEqual(rows, [
            PersonAutocompleteRow(kind: .person(candidates[0])),
            PersonAutocompleteRow(kind: .create(name: "an")),
        ])
    }

    func testExactExistingNameSuppressesCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "bob")
        XCTAssertEqual(rows, [PersonAutocompleteRow(kind: .person(candidates[1]))]) // no create row
    }

    func testFocusIndexWraps() {
        XCTAssertEqual(PersonAutocompletePresentation.clampedFocusIndex(-1, rowCount: 3), 2)
        XCTAssertEqual(PersonAutocompletePresentation.clampedFocusIndex(3, rowCount: 3), 0)
        XCTAssertEqual(PersonAutocompletePresentation.clampedFocusIndex(5, rowCount: 0), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PersonAutocompletePresentationTests`
Expected: FAIL — no `PersonAutocompletePresentation`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TeststripApp/PersonAutocompletePresentation.swift`:

```swift
import Foundation
import TeststripCore

struct PersonAutocompleteRow: Equatable {
    enum Kind: Equatable {
        case person(PersonCandidate)
        case create(name: String)
    }
    let kind: Kind
}

enum PersonAutocompletePresentation {
    static func rows(candidates: [PersonCandidate], query: String) -> [PersonAutocompleteRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? candidates
            : candidates.filter { $0.name.range(of: trimmed, options: .caseInsensitive) != nil }
        var rows = filtered.map { PersonAutocompleteRow(kind: .person($0)) }
        if !trimmed.isEmpty,
           !candidates.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            rows.append(PersonAutocompleteRow(kind: .create(name: trimmed)))
        }
        return rows
    }

    static func clampedFocusIndex(_ index: Int, rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        return ((index % rowCount) + rowCount) % rowCount
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PersonAutocompletePresentationTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/PersonAutocompletePresentation.swift Tests/TeststripAppTests/PersonAutocompletePresentationTests.swift
git commit -m "feat: PersonAutocompletePresentation — filter + create-row + focus"
```

---

### Task 5: `PersonAutocompleteField` (reusable SwiftUI view)

**Files:**
- Create: `Sources/TeststripApp/PersonAutocompleteField.swift`

**Interfaces:**
- Consumes: `PersonCandidate` (Task 2), `PersonAutocompletePresentation`/`PersonAutocompleteRow` (Task 4).
- Produces: `struct PersonAutocompleteField: View` with init
  `(candidates: [PersonCandidate], onPick: @escaping (String) -> Void, onCreate: @escaping (String) -> Void)`.

UI-only (build-verified; the logic is unit-tested in Task 4). A `@State private
var query` + `@State private var focusIndex` + `@FocusState private var
isFieldFocused`. Body: a `TextField("Name", text: $query)` (`.roundedBorder`,
`.focused($isFieldFocused)`, `.onAppear { isFieldFocused = true }`), followed by a
scrolling list of `PersonAutocompletePresentation.rows(candidates:query:)` — each
row a `Button` that on tap runs `activate(row)`; a `.person` row shows the name
plus, when `similarityPercent != nil`, a trailing `Text("\(percent)%")` in
`.caption2.foregroundStyle(.secondary)`; a `.create` row shows `Label("Create
\"\(name)\"", systemImage: "plus")`. The focused row (`focusIndex`) gets a subtle
`.background(Color.accentColor.opacity(0.15))`.

Keyboard (new pattern for this codebase — only `.onKeyPress(.escape)` exists
today; extend it): attach to the `TextField`:
```swift
.onKeyPress(.downArrow) { focusIndex = PersonAutocompletePresentation.clampedFocusIndex(focusIndex + 1, rowCount: rows.count); return .handled }
.onKeyPress(.upArrow)   { focusIndex = PersonAutocompletePresentation.clampedFocusIndex(focusIndex - 1, rowCount: rows.count); return .handled }
.onKeyPress(.return)    { if rows.indices.contains(focusIndex) { activate(rows[focusIndex]) }; return .handled }
```
where `activate(_ row:)` calls `onPick(candidate.id)` or `onCreate(name)`. Reset
`focusIndex = 0` whenever `query` changes (`.onChange(of: query)`).

- [ ] **Step 1: Implement the view**

Write `PersonAutocompleteField.swift` per the description above. Compute `rows`
once per body via `PersonAutocompletePresentation.rows(candidates: candidates,
query: query)`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`, no new warnings.

- [ ] **Step 3: Commit**

```bash
git add Sources/TeststripApp/PersonAutocompleteField.swift
git commit -m "feat: PersonAutocompleteField — ranked person picker with create row"
```

---

### Task 6: Face-box overlay — interactive name pill + popover

**Files:**
- Modify: `Sources/TeststripApp/FaceBoxOverlayView.swift`
- Modify: `Sources/TeststripApp/AppModel.swift` (add `editingFaceID: FaceID?`)
- Modify: `Sources/TeststripApp/PhotoFacesPresentation.swift` (add `origin` to `PhotoFaceState` so remove routes correctly — see below)

**Interfaces:**
- Consumes: `AppModel.rankedPersonCandidates(forFace:)`, `PersonAutocompleteField`, `nameFace`, `removeFacePerson`, `rejectFaceSuggestion`.
- Produces: an interactive pill on each face box that opens a popover autocompleter and a ✕ remove control.

**Design notes (from the anchors' flags):**
- `focusedFaceID` is hover-only and self-clearing; moving the pointer into the
  popover would clear it. Add a separate `AppModel.editingFaceID: FaceID?` that
  pins the active face while its popover is open. The pill is shown when
  `focusedFaceID == row.faceID || editingFaceID == row.faceID`; the popover is
  presented while `editingFaceID == row.faceID`.
- `PhotoFaceState` currently encodes origin implicitly (`.confirmed`/`.suggested`).
  Remove needs the origin: a `.confirmed` face → `removeFacePerson`; a
  `.suggested` face → `rejectFaceSuggestion(personID:)`. The state already carries
  the personID in both cases, so no schema change — just branch on the case.

- [ ] **Step 1: Add `editingFaceID`**

In `AppModel.swift`, near `focusedFaceID` (~L2264):
```swift
/// The face whose naming popover is open. Pinned independently of hover so the
/// box stays active while the pointer is inside the popover.
public var editingFaceID: FaceID?
```

- [ ] **Step 2: Make the pill interactive**

In `FaceBoxOverlayView.faceBox(rect:row:)`, replace the static `faceLabel(...)`
overlay with a pill that: shows when `isFocused || model.editingFaceID ==
row.faceID`; is a `Button` that sets `model.editingFaceID = row.faceID`; carries a
trailing ✕ `Button` (only when the face is named) that removes per origin; and
presents a `.popover(isPresented: editing binding)` hosting
`PersonAutocompleteField(candidates: model.rankedPersonCandidates(forFace:
row.faceID), onPick: { assign }, onCreate: { create })`. Keep the box's
`.onHover` and box-interior semantics unchanged. Concretely:

```swift
    private func faceBox(rect: CGRect, row: PhotoFaceRow) -> some View {
        let isFocused = model.focusedFaceID == row.faceID
        let isEditing = model.editingFaceID == row.faceID
        return RoundedRectangle(cornerRadius: 4)
            .stroke(isFocused || isEditing ? Color.yellow : Color.white.opacity(0.8),
                    lineWidth: isFocused || isEditing ? 2.5 : 1.25)
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .overlay(alignment: .topLeading) {
                if isFocused || isEditing {
                    facePill(row: row, isEditing: isEditing).padding(3)
                } else {
                    faceLabel(row.state.displayLabel, isFocused: false).padding(3)
                }
            }
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    model.focusedFaceID = row.faceID
                } else if model.focusedFaceID == row.faceID {
                    model.focusedFaceID = nil
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.state.displayLabel)
    }

    private func facePill(row: PhotoFaceRow, isEditing: Bool) -> some View {
        HStack(spacing: 2) {
            Button {
                model.editingFaceID = row.faceID
            } label: {
                faceLabel(pillTitle(row.state), isFocused: true)
            }
            .buttonStyle(.plain)
            .popover(isPresented: editingBinding(for: row.faceID), arrowEdge: .bottom) {
                PersonAutocompleteField(
                    candidates: model.rankedPersonCandidates(forFace: row.faceID),
                    onPick: { personID in
                        run { try model.nameFace(row.faceID, personID: personID) }
                        model.editingFaceID = nil
                    },
                    onCreate: { name in
                        run { try model.nameFace(row.faceID, newPersonName: name) }
                        model.editingFaceID = nil
                    }
                )
                .frame(width: 240)
                .padding(8)
            }
            if row.state.personID != nil {
                Button {
                    removePerson(row)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Remove this person")
            }
        }
    }

    private func editingBinding(for faceID: FaceID) -> Binding<Bool> {
        Binding(get: { model.editingFaceID == faceID },
                set: { if !$0, model.editingFaceID == faceID { model.editingFaceID = nil } })
    }

    private func pillTitle(_ state: PhotoFaceState) -> String {
        switch state {
        case .confirmed(_, let name): name
        case .suggested(_, let name): "guess: \(name)"
        case .unnamed: "Name\u{2026}"
        }
    }

    private func removePerson(_ row: PhotoFaceRow) {
        switch row.state {
        case .confirmed:
            run { try model.removeFacePerson(row.faceID) }
        case .suggested(let personID, _):
            run { try model.rejectFaceSuggestion(row.faceID, personID: personID) }
        case .unnamed:
            break
        }
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { model.errorMessage = error.localizedDescription }
    }
```

Add a `personID` accessor to `PhotoFaceState` (in `PhotoFacesPresentation.swift`):
```swift
    var personID: String? {
        switch self {
        case .confirmed(let personID, _), .suggested(let personID, _): personID
        case .unnamed: nil
        }
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`, no new warnings.

- [ ] **Step 4: Sanity-run the face suites**

Run: `swift test --filter PhotoFace`
Expected: PASS (existing PhotoFace* suites still green).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/FaceBoxOverlayView.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/PhotoFacesPresentation.swift
git commit -m "feat: face-box pill — assign/remove person via ranked popover"
```

---

### Task 7: Unify the four naming surfaces

**Files:**
- Modify: `Sources/TeststripApp/PhotoFacesSectionView.swift` (replace `addNameMenu` + `newPersonNameSheet`)
- Modify: `Sources/TeststripApp/PeopleView.swift` (`nameSelectionSheet`, `nameSuggestionSheet`)
- Modify: `Sources/TeststripApp/FaceGroupReviewView.swift` (`namingSheet`)

**Interfaces:**
- Consumes: `PersonAutocompleteField`, `AppModel.rankedPersonCandidates(forFace:)`, `nameFace`, `confirmSelectedAssetsAsPerson(named:)`, `confirmPeopleFaceSuggestion` overloads.

UI-only (build-verified). Each surface hosts `PersonAutocompleteField`; the
`onPick`/`onCreate` callbacks call that surface's existing assign op:

- **Inspector faces** (`PhotoFacesSectionView.controls`, `.unnamed` case):
  replace `addNameMenu(for:)` with an inline `PersonAutocompleteField(candidates:
  model.rankedPersonCandidates(forFace: row.faceID), onPick: { try
  model.nameFace(row.faceID, personID: $0) }, onCreate: { try
  model.nameFace(row.faceID, newPersonName: $0) })` (hosted in a small popover
  from an "Add name" button, matching the pill pattern from Task 6). Delete
  `newPersonNameSheet` + `newPersonNameDraft`/`newPersonFaceID` + the `.sheet`
  wiring (now unused).
- **People "Name selection"** (`nameSelectionSheet`): replace the `TextField`
  with `PersonAutocompleteField(candidates: model.rankedPersonCandidates(forFace:
  nil), onPick: { pick existing → confirmSelectedAssetsAsPerson(named:
  candidateName) }, onCreate: { confirmSelectedAssetsAsPerson(named: $0) })`.
  Because `confirmSelectedAssetsAsPerson(named:)` already dedupes by name
  (`existingPersonID(matchingName:)`), picking an existing candidate = passing
  its name; no new whole-asset-by-id method is needed. (Pass the candidate's
  `name` to `onPick`; keep the `PersonCandidate` in scope to read it.)
- **People "Name Face Group"** (`nameSuggestionSheet`) and **Face-group review**
  (`namingSheet`): replace the `TextField` with `PersonAutocompleteField`
  ranked for the suggestion's representative face
  (`rankedPersonCandidates(forFace: suggestion.representativeFace)`); `onCreate`
  → `confirmPeopleFaceSuggestion(suggestion, personName: $0)`; `onPick` →
  `confirmPeopleFaceSuggestion(suggestion, personName: candidateName)` (the
  name-keyed confirm dedupes to the existing person via `existingPersonID`).

> `onPick` gives you the picked candidate's `id`; to also get its `name` (needed
> by the whole-asset and group surfaces), have those call sites look the name up
> from the `candidates` array they passed in, or change those two call sites'
> `onPick` to capture the `PersonCandidate`. Keep `PersonAutocompleteField`'s
> `onPick` signature as `(String) -> Void` for the face surfaces (which need the
> id for `nameFace`); the whole-asset/group surfaces map id→name locally.

`SheetScaffold` still wraps the sheet surfaces; keep `primaryLabel: "Create
Person"`. Since the autocompleter now commits on pick/create (its own Return),
the sheet's primary button can remain as the create-current-text fallback, or the
surfaces can drop to a plain container — keep `SheetScaffold` for consistency and
wire its `primary` to create the typed name.

- [ ] **Step 1: Inspector faces**

Replace `addNameMenu`/`newPersonNameSheet` as above; delete the now-dead state and `.sheet`.

- [ ] **Step 2: People + review sheets**

Swap the three `TextField`s for `PersonAutocompleteField` as above.

- [ ] **Step 3: Build + sanity tests**

Run: `swift build` then `swift test --filter People` and `swift test --filter PhotoFace`
Expected: `Build complete!`; existing People*/PhotoFace* suites green.

- [ ] **Step 4: Commit**

```bash
git add Sources/TeststripApp/PhotoFacesSectionView.swift Sources/TeststripApp/PeopleView.swift Sources/TeststripApp/FaceGroupReviewView.swift
git commit -m "feat: unify the four naming surfaces on PersonAutocompleteField"
```

---

### Task 8: End-to-end scenario card

**Files:**
- Create: `test/scenarios/people-024-face-autocompleter.md`

Authored, not run (VM + AuraFace-bound). Follow `people-022`/`people-023` format
(Pre-state with a concrete construction path, `## Steps`, dedicated `## Expected`
with per-step "Fails if", `## Cleanup`, `## Sharp edges` incl. idle-wedge,
`## Run status`). Cover: on the loupe with the inspector visible, hover a face box
→ its name pill appears → click the pill → the popover autocompleter lists people
**ordered by similarity %** → pick one → assert (via `script/vm_scenario_run.sh
sql`) a `person_faces.origin='user'` row + `person_assets`; click the pill's ✕ →
assert the row is removed (confirmed → gone; a suggested face → `rejected_face_people`);
and drive the inspector's autocompleter for a second face, typing a new name →
`## Expected` a new `people` row. Do NOT invent script verbs or SQL columns
(`person_faces(person_id, asset_id, face_index, origin)`, `person_assets`,
`rejected_face_people`, `people`).

- [ ] **Step 1: Write the card**

Create `test/scenarios/people-024-face-autocompleter.md` per the above.

- [ ] **Step 2: Commit**

```bash
git add test/scenarios/people-024-face-autocompleter.md
git commit -m "test: scenario card — face-box autocompleter (people-024)"
```

---

## Notes for the executor

- Task order: 1→2 (Core primitives → ranker); 3 needs 1+2; 4 is independent of 3
  (pure presentation); 5 needs 2+4; 6 needs 3+5; 7 needs 3+5; 8 last.
- Run the full `swift test` once after Task 7 before the whole-branch review.
- Whole-branch review focus: the latent-contact-safe `nameFace` (materializes,
  no orphan/notFound), the name-dedupe in the create paths (no duplicate people),
  the `editingFaceID`-vs-hover interaction (pill/popover stays anchored), and the
  remove-by-origin split (confirmed→unassign, suggested→sticky reject).
