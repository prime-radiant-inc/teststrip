# Contacts Seeding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seed person recognition from the macOS address book — embed each
contact's photo into a new assetless reference store, union those embeddings into
the existing face matcher, and surface matches (recall boost for named people;
review-first "Is this [name]?" cards for not-yet-seen contacts).

**Architecture:** A new `contact_reference_faces` table + a `ContactPhotoCache`
hold each contact's AuraFace-v1 embedding, name, face box, and photo. A
`ContactsProviding` seam yields `(identifier, name, imageData)` records (live
`CNContactStore` conformer in the app; stubbed in tests). A pure `ContactFaceSeeder`
detects + embeds + dedups + upserts. Reference embeddings union into the
`confirmedFacesByPerson` centroid dict the matcher already consumes — no matcher
change. A match to a person with a `people` row auto-applies (`origin='ai'`); a
match to a latent `contact:<id>` (no row) surfaces as a review suggestion and
materializes the person only on confirm.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, Contacts framework, Vision +
Core ML (AuraFace-v1), SQLite via `CatalogDatabase`/`CatalogRepository`.

## Global Constraints

- **Embedding compatibility is load-bearing.** Reference vectors MUST be the
  same 512-d L2-normalized AuraFace-v1 embeddings produced by
  `FaceRecognitionEmbedder(model: CoreMLFaceEmbeddingModel.auraFace())`; the
  match threshold `FaceSuggestionBuilder.defaultMaximumMatchDistance = 1.23` is
  calibrated to that exact model. Never embed with any other model.
- **Latent contacts never auto-apply and never pollute the confirmed People
  list.** A match whose `person_id` has NO `people` row must be surfaced as a
  review suggestion, NOT auto-applied — `promoteFaceMatches` skips person ids
  absent from `catalogPeople`. `insertAIFace` does not validate the person id, so
  auto-applying a latent match would write an invisible orphan row.
- **Provenance (auto-apply with provenance):** contact matches to an existing
  person auto-apply as `person_faces.origin='ai'` (tentative — never
  destructive/export/Picks until confirmed). A latent-contact confirm
  materializes the person and writes `origin='user'` via `assignFaces`. Reference
  embeddings and cached contact photos are recognition inputs only — never
  written to `.xmp` (identity has no XMP field) and never modify originals.
- **Seeding is idempotent** by `contact_identifier` + `photo_hash` (re-embed only
  when the photo changed).
- **New required fields break call sites.** Any new parameter on `AppCatalog`,
  `AppCatalogPaths`, or `AppModel.load` MUST have a default value — the
  positional `AppCatalog(...)` initializer is called across ~30 test harnesses.
- **Contacts access is behind the `ContactsProviding` seam** — unit-tested with
  a stub; the live `CNContactStore` conformer is one thin file. Embedding is
  gated on model availability (`auraFace()` returns `nil` when absent). Contact
  photo bytes are decoded with correct EXIF orientation before embedding.
- Perf: the reference-augmented `confirmedFacesByPerson` centroid dict is
  uncapped; at dogfood scale this is fine (per the project's perf-restraint) —
  do NOT add caps/caches speculatively.
- Branch: `feat/contacts-seeding`. Build: `swift build`. Focused test:
  `swift test --filter <SuiteName>`.

---

### Task 1: Migration — `contact_reference_faces` table (schema v21)

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (append DDL to `statements`; bump `version`)
- Test: `Tests/TeststripCoreTests/ContactReferenceFacesTests.swift` (new)

**Interfaces:**
- Produces: the `contact_reference_faces` table + `idx_contact_reference_faces_person` index; `CatalogMigrations.version == 21`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/ContactReferenceFacesTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class ContactReferenceFacesTests: XCTestCase {
    private func repo() throws -> (CatalogRepository, CatalogDatabase) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crf-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url); try db.migrate()
        return (CatalogRepository(database: db), db)
    }

    func testSchemaVersionIs21() {
        XCTAssertEqual(CatalogMigrations.version, 21)
    }

    func testContactReferenceFacesTableExists() throws {
        let (_, db) = try repo()
        let rows = try db.rows("SELECT name FROM sqlite_master WHERE type='table' AND name='contact_reference_faces'")
        XCTAssertEqual(rows.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContactReferenceFacesTests`
Expected: FAIL — `testSchemaVersionIs21` (still 20) and no such table.

- [ ] **Step 3: Write minimal implementation**

In `CatalogMigrations.swift`, append to the `statements` array (mirror the
`person_faces` / `rejected_face_people` block at lines 163-182):

```swift
        """
        CREATE TABLE IF NOT EXISTS contact_reference_faces (
            contact_identifier TEXT PRIMARY KEY NOT NULL,
            person_id TEXT NOT NULL,
            name TEXT NOT NULL,
            embedding_json TEXT NOT NULL,
            bounding_box_json TEXT NOT NULL,
            photo_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_contact_reference_faces_person ON contact_reference_faces(person_id)",
```

Change `static let version = 20` → `static let version = 21`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContactReferenceFacesTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogMigrations.swift Tests/TeststripCoreTests/ContactReferenceFacesTests.swift
git commit -m "feat: contact_reference_faces table (schema v21)"
```

---

### Task 2: Repository — reference face type, writes, and reads

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add near the other face methods, e.g. after `confirmedFaceEmbeddingsByPerson`, ~line 1286)
- Test: `Tests/TeststripCoreTests/ContactReferenceFacesTests.swift` (extend)

**Interfaces:**
- Consumes: the table (Task 1); `upsertPerson`, `FaceBoundingBox`, the private `encode`/`decode` helpers (same file).
- Produces:
  - `public struct ContactReferenceFace: Equatable, Sendable { let contactIdentifier: String; let personID: String; let name: String; let boundingBox: FaceBoundingBox }`
  - `func upsertContactReferenceFace(contactIdentifier: String, personID: String, name: String, embedding: [Double], boundingBox: FaceBoundingBox, photoHash: String) throws`
  - `func contactReferencePhotoHash(contactIdentifier: String) throws -> String?`
  - `func contactReferenceEmbeddingsByPerson() throws -> [String: [[Double]]]`
  - `func contactReferenceNamesByPerson() throws -> [String: String]`
  - `func contactReferenceFace(personID: String) throws -> ContactReferenceFace?`
  - `func personID(matchingName name: String) throws -> String?`

- [ ] **Step 1: Write the failing test**

Append to `ContactReferenceFacesTests.swift`:

```swift
extension ContactReferenceFacesTests {
    private func box() -> FaceBoundingBox { FaceBoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.3) }

    func testUpsertAndReadReferenceByPerson() throws {
        let (r, _) = try repo()
        try r.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                         embedding: [0.1, 0.2], boundingBox: box(), photoHash: "h1")
        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson(), ["contact:C1": [[0.1, 0.2]]])
        XCTAssertEqual(try r.contactReferenceNamesByPerson(), ["contact:C1": "Dan Shapiro"])
        XCTAssertEqual(try r.contactReferencePhotoHash(contactIdentifier: "C1"), "h1")
        XCTAssertEqual(try r.contactReferenceFace(personID: "contact:C1")?.name, "Dan Shapiro")
    }

    func testUpsertIsIdempotentByIdentifier() throws {
        let (r, _) = try repo()
        try r.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan",
                                         embedding: [0.1], boundingBox: box(), photoHash: "h1")
        try r.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                         embedding: [0.9], boundingBox: box(), photoHash: "h2")
        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson(), ["contact:C1": [[0.9]]]) // replaced, not duplicated
        XCTAssertEqual(try r.contactReferencePhotoHash(contactIdentifier: "C1"), "h2")
    }

    func testPersonIDMatchingNameFindsExistingPerson() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        XCTAssertEqual(try r.personID(matchingName: "dan shapiro"), "p1") // case-insensitive
        XCTAssertNil(try r.personID(matchingName: "Nobody"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContactReferenceFacesTests`
Expected: FAIL — missing members.

- [ ] **Step 3: Write minimal implementation**

Add to `CatalogRepository.swift` (the `encode`/`decode` helpers and the `[[Double]]`
JSON idiom mirror `confirmedFaceEmbeddingsByPerson`, lines 1262-1286; the
upsert idiom mirrors `upsertPerson`, lines 952-972):

```swift
public struct ContactReferenceFace: Equatable, Sendable {
    public let contactIdentifier: String
    public let personID: String
    public let name: String
    public let boundingBox: FaceBoundingBox

    public init(contactIdentifier: String, personID: String, name: String, boundingBox: FaceBoundingBox) {
        self.contactIdentifier = contactIdentifier
        self.personID = personID
        self.name = name
        self.boundingBox = boundingBox
    }
}

public func upsertContactReferenceFace(
    contactIdentifier: String, personID: String, name: String,
    embedding: [Double], boundingBox: FaceBoundingBox, photoHash: String
) throws {
    let now = "\(Date().timeIntervalSince1970)"
    try database.execute(
        """
        INSERT INTO contact_reference_faces
            (contact_identifier, person_id, name, embedding_json, bounding_box_json, photo_hash, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(contact_identifier) DO UPDATE SET
            person_id = excluded.person_id,
            name = excluded.name,
            embedding_json = excluded.embedding_json,
            bounding_box_json = excluded.bounding_box_json,
            photo_hash = excluded.photo_hash,
            updated_at = excluded.updated_at
        """,
        bindings: [contactIdentifier, personID, name, try encode(embedding), try encode(boundingBox), photoHash, now, now]
    )
}

public func contactReferencePhotoHash(contactIdentifier: String) throws -> String? {
    try database.rows(
        "SELECT photo_hash FROM contact_reference_faces WHERE contact_identifier = ?",
        bindings: [contactIdentifier]
    ).first?["photo_hash"]
}

public func contactReferenceEmbeddingsByPerson() throws -> [String: [[Double]]] {
    let rows = try database.rows("SELECT person_id, embedding_json FROM contact_reference_faces")
    var result: [String: [[Double]]] = [:]
    for row in rows {
        guard let personID = row["person_id"], let embeddingJSON = row["embedding_json"] else {
            throw CatalogError.sqlite("contact reference row is missing required columns")
        }
        result[personID, default: []].append(try decode([Double].self, from: embeddingJSON))
    }
    return result
}

public func contactReferenceNamesByPerson() throws -> [String: String] {
    let rows = try database.rows("SELECT person_id, name FROM contact_reference_faces")
    var result: [String: String] = [:]
    for row in rows {
        guard let personID = row["person_id"], let name = row["name"] else {
            throw CatalogError.sqlite("contact reference row is missing required columns")
        }
        result[personID] = name
    }
    return result
}

public func contactReferenceFace(personID: String) throws -> ContactReferenceFace? {
    guard let row = try database.rows(
        "SELECT contact_identifier, person_id, name, bounding_box_json FROM contact_reference_faces WHERE person_id = ? LIMIT 1",
        bindings: [personID]
    ).first else { return nil }
    guard let contactIdentifier = row["contact_identifier"], let pid = row["person_id"],
          let name = row["name"], let boxJSON = row["bounding_box_json"] else {
        throw CatalogError.sqlite("contact reference row is missing required columns")
    }
    return ContactReferenceFace(contactIdentifier: contactIdentifier, personID: pid, name: name,
                                boundingBox: try decode(FaceBoundingBox.self, from: boxJSON))
}

public func personID(matchingName name: String) throws -> String? {
    try database.rows(
        "SELECT id FROM people WHERE name = ? COLLATE NOCASE LIMIT 1",
        bindings: [name]
    ).first?["id"]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContactReferenceFacesTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/ContactReferenceFacesTests.swift
git commit -m "feat: contact reference face reads/writes on CatalogRepository"
```

---

### Task 3: `ContactPhotoCache`

**Files:**
- Create: `Sources/TeststripCore/Preview/ContactPhotoCache.swift`
- Test: `Tests/TeststripCoreTests/ContactPhotoCacheTests.swift` (new)

**Interfaces:**
- Produces: `public struct ContactPhotoCache: Sendable { var root: URL; init(root: URL); func url(for contactIdentifier: String) -> URL }` — the on-disk location for a contact's cached photo (JPEG). Escapes unsafe characters in the identifier (contact ids contain `:`/`/`), mirroring `PreviewCache.safeAssetDirectoryName`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/ContactPhotoCacheTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class ContactPhotoCacheTests: XCTestCase {
    func testURLIsStableAndUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/contacts")
        let cache = ContactPhotoCache(root: root)
        let a = cache.url(for: "ABC:123/xyz")
        XCTAssertEqual(a, cache.url(for: "ABC:123/xyz"))       // stable
        XCTAssertTrue(a.path.hasPrefix(root.path))             // under root
        XCTAssertTrue(a.pathExtension == "jpg")
    }

    func testDistinctIdentifiersDistinctURLs() {
        let cache = ContactPhotoCache(root: URL(fileURLWithPath: "/tmp/contacts"))
        XCTAssertNotEqual(cache.url(for: "A"), cache.url(for: "B"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContactPhotoCacheTests`
Expected: FAIL — no `ContactPhotoCache`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TeststripCore/Preview/ContactPhotoCache.swift` (the escaping
mirrors `PreviewCache.safeAssetDirectoryName` — hex-escape any character
outside `[A-Za-z0-9_-]`):

```swift
import Foundation

/// On-disk cache for contact reference photos, keyed by contact identifier.
/// The stored photo is the review-card reference image for a seeded contact.
public struct ContactPhotoCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for contactIdentifier: String) -> URL {
        root.appendingPathComponent("\(Self.safeName(for: contactIdentifier)).jpg")
    }

    private static func safeName(for rawValue: String) -> String {
        var result = ""
        for scalar in rawValue.unicodeScalars {
            if (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z")
                || (scalar >= "0" && scalar <= "9") || scalar == "_" || scalar == "-" {
                result.unicodeScalars.append(scalar)
            } else {
                result += String(format: "~%04x", scalar.value)
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContactPhotoCacheTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Preview/ContactPhotoCache.swift Tests/TeststripCoreTests/ContactPhotoCacheTests.swift
git commit -m "feat: ContactPhotoCache — on-disk contact reference photos"
```

---

### Task 4: `ContactsProviding` seam + `ContactFaceSeeder` orchestration

**Files:**
- Create: `Sources/TeststripCore/People/ContactsProviding.swift` (protocol + `ContactRecord`)
- Create: `Sources/TeststripCore/People/ContactFaceSeeder.swift` (orchestration)
- Test: `Tests/TeststripCoreTests/ContactFaceSeederTests.swift` (new)

**Interfaces:**
- Consumes: `FaceRecognitionEmbedder` (`.faceObservations(in: CGImage)`), `CatalogRepository` (Task 2), `ContactPhotoCache` (Task 3), `AppleVisionFaceObservation`.
- Produces:
  - `public struct ContactRecord: Equatable, Sendable { let identifier: String; let name: String; let imageData: Data }`
  - `public protocol ContactsProviding: Sendable { func contactsWithPhotos() throws -> [ContactRecord] }`
  - `public struct ContactSeedSummary: Equatable, Sendable { var seeded: Int; var unchanged: Int; var skippedNoFace: Int }`
  - `public struct ContactFaceSeeder: Sendable { init(embedder: FaceRecognitionEmbedder, repository: CatalogRepository, photoCache: ContactPhotoCache); func seed(records: [ContactRecord]) throws -> ContactSeedSummary }`

`ContactFaceSeeder.seed` is the pure orchestration: for each record → skip if the
row's `photo_hash` already equals `sha256(imageData)` (unchanged) → decode the
image (`CGImageSourceCreateWithData`, applying EXIF orientation) → embed via
`embedder.faceObservations(in:)`, take the highest-`captureQuality` face, skip if
none → resolve `person_id` (`repository.personID(matchingName: name)` ?? `"contact:\(identifier)"`)
→ write the cached photo → `repository.upsertContactReferenceFace(...)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripCoreTests/ContactFaceSeederTests.swift`. Use a stub
embedding model (mirror `StubEmbeddingModel` at
`Tests/TeststripCoreTests/EvaluationProviderTests.swift:8-13`) and generate a
real 1-face test image so Vision detects a face. To keep the test deterministic
and avoid depending on Vision detecting a synthetic face, inject a **stub
`FaceRecognitionEmbedder` seam** is not possible (it's a concrete struct); instead
generate a JPEG of a simple face-like image is unreliable. **Therefore make
`ContactFaceSeeder` take a `faceDetector` closure seam** so the test supplies the
detected observations directly:

Redefine the seeder init to accept a detector closure:
`init(detectFaces: @escaping @Sendable (CGImage) throws -> [AppleVisionFaceObservation], repository:, photoCache:)`.
The production caller passes `{ try embedder.faceObservations(in: $0) }`. The test
passes a closure returning a fixed `[AppleVisionFaceObservation]`.

```swift
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import TeststripCore

final class ContactFaceSeederTests: XCTestCase {
    private func repo() throws -> (CatalogRepository, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try CatalogDatabase.open(at: dir.appendingPathComponent("c.sqlite")); try db.migrate()
        return (CatalogRepository(database: db), dir)
    }

    // A tiny valid JPEG so decoding succeeds; face detection is stubbed via the seam.
    private func jpeg() -> Data {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
        return data as Data
    }

    private func face(_ quality: Double) -> AppleVisionFaceObservation {
        AppleVisionFaceObservation(boundingBox: FaceBoundingBox(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                                   captureQuality: quality, featurePrintVector: [0.5, 0.5])
    }

    func testSeedsLatentContactWhenNoNameMatch() throws {
        let (r, dir) = try repo()
        let seeder = ContactFaceSeeder(
            detectFaces: { _ in [self.face(0.9)] },
            repository: r, photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        let summary = try seeder.seed(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg())])

        XCTAssertEqual(summary.seeded, 1)
        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson(), ["contact:C1": [[0.5, 0.5]]])
        XCTAssertEqual(try r.contactReferenceNamesByPerson()["contact:C1"], "Dan Shapiro")
    }

    func testSeedAttachesToExistingPersonByName() throws {
        let (r, dir) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        let seeder = ContactFaceSeeder(detectFaces: { _ in [self.face(0.9)] }, repository: r,
                                       photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        _ = try seeder.seed(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg())])
        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson().keys.sorted(), ["p1"]) // attached, not latent
    }

    func testSkipsContactWithNoDetectableFace() throws {
        let (r, dir) = try repo()
        let seeder = ContactFaceSeeder(detectFaces: { _ in [] }, repository: r,
                                       photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        let summary = try seeder.seed(records: [ContactRecord(identifier: "C1", name: "Dan", imageData: jpeg())])
        XCTAssertEqual(summary.skippedNoFace, 1)
        XCTAssertTrue(try r.contactReferenceEmbeddingsByPerson().isEmpty)
    }

    func testUnchangedPhotoIsSkippedOnReseed() throws {
        let (r, dir) = try repo()
        let seeder = ContactFaceSeeder(detectFaces: { _ in [self.face(0.9)] }, repository: r,
                                       photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        let record = ContactRecord(identifier: "C1", name: "Dan", imageData: jpeg())
        _ = try seeder.seed(records: [record])
        let second = try seeder.seed(records: [record])
        XCTAssertEqual(second.unchanged, 1)
        XCTAssertEqual(second.seeded, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContactFaceSeederTests`
Expected: FAIL — no `ContactRecord`/`ContactFaceSeeder`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/TeststripCore/People/ContactsProviding.swift`:

```swift
import Foundation

/// One address-book contact that has a photo. `imageData` is the raw
/// `CNContact.imageData` (or thumbnail) bytes.
public struct ContactRecord: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let imageData: Data

    public init(identifier: String, name: String, imageData: Data) {
        self.identifier = identifier
        self.name = name
        self.imageData = imageData
    }
}

/// The seam over the address book. The live conformer wraps `CNContactStore`
/// (app target); tests supply a stub.
public protocol ContactsProviding: Sendable {
    func contactsWithPhotos() throws -> [ContactRecord]
}
```

Create `Sources/TeststripCore/People/ContactFaceSeeder.swift`:

```swift
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public struct ContactSeedSummary: Equatable, Sendable {
    public var seeded: Int = 0
    public var unchanged: Int = 0
    public var skippedNoFace: Int = 0
}

/// Turns address-book contact records into reference faces: embed the contact
/// photo's primary face and upsert a `contact_reference_faces` row, attaching to
/// an existing same-named person or minting a latent `contact:<id>` person id.
public struct ContactFaceSeeder: Sendable {
    private let detectFaces: @Sendable (CGImage) throws -> [AppleVisionFaceObservation]
    private let repository: CatalogRepository
    private let photoCache: ContactPhotoCache

    public init(
        detectFaces: @escaping @Sendable (CGImage) throws -> [AppleVisionFaceObservation],
        repository: CatalogRepository,
        photoCache: ContactPhotoCache
    ) {
        self.detectFaces = detectFaces
        self.repository = repository
        self.photoCache = photoCache
    }

    public func seed(records: [ContactRecord]) throws -> ContactSeedSummary {
        var summary = ContactSeedSummary()
        for record in records {
            let hash = Self.hash(record.imageData)
            if try repository.contactReferencePhotoHash(contactIdentifier: record.identifier) == hash {
                summary.unchanged += 1
                continue
            }
            guard let image = Self.decodeImage(record.imageData) else {
                summary.skippedNoFace += 1
                continue
            }
            let faces = try detectFaces(image)
            guard let best = faces.max(by: { ($0.captureQuality ?? -1) < ($1.captureQuality ?? -1) }) else {
                summary.skippedNoFace += 1
                continue
            }
            let personID = try repository.personID(matchingName: record.name) ?? "contact:\(record.identifier)"
            try Self.writePhoto(record.imageData, to: photoCache.url(for: record.identifier))
            try repository.upsertContactReferenceFace(
                contactIdentifier: record.identifier, personID: personID, name: record.name,
                embedding: best.featurePrintVector, boundingBox: best.boundingBox, photoHash: hash
            )
            summary.seeded += 1
        }
        return summary
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes with EXIF orientation applied (contact photos can be rotated;
    /// `CGImageSourceCreateImageAtIndex` does not auto-apply orientation).
    private static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1024]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func writePhoto(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
```

> Note: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform`
> applies the EXIF orientation transform, normalizing the pixel buffer before
> Vision sees it (the orientation flag the anchors' Flag 3 warns about). The
> `1024` cap keeps a large contact photo cheap to embed.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContactFaceSeederTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/People/ContactsProviding.swift Sources/TeststripCore/People/ContactFaceSeeder.swift Tests/TeststripCoreTests/ContactFaceSeederTests.swift
git commit -m "feat: ContactsProviding seam + ContactFaceSeeder orchestration"
```

---

### Task 5: Matcher union — surface contact references as suggestions

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`refreshPeopleFaceSuggestions` ~3626; `promoteFaceMatches` ~3670)
- Test: `Tests/TeststripAppTests/ContactReferenceMatchingTests.swift` (new)

**Interfaces:**
- Consumes: `contactReferenceEmbeddingsByPerson()`, `contactReferenceNamesByPerson()` (Task 2); `confirmedFaceEmbeddingsByPerson`, `FaceSuggestionBuilder`, `catalogPeople`.
- Produces: after this task, a catalog face near a latent contact reference appears in `model.peopleFaceSuggestions` as `.matchExisting(personID: "contact:<id>", personName: <contact name>)`; a face near a name-attached reference auto-applies (`origin='ai'`); a latent match is NOT auto-applied.

**Design:** In BOTH `refreshPeopleFaceSuggestions` and `promoteFaceMatches`, build
the centroid dict as `confirmedFacesByPerson` **merged with**
`contactReferenceEmbeddingsByPerson()` (append reference vectors under their
`person_id`). In `refreshPeopleFaceSuggestions`, build the names map as
`personNamesByID` (from `catalogPeople`) **merged with** `contactReferenceNamesByPerson()`
so latent-contact matches survive the `personNamesByID[match.personID]` guard in
`peopleFaceSuggestions(from:)`. In `promoteFaceMatches`, **skip** any match whose
`match.personID` is not a real person — gate on `catalog.repository.people()`
membership (a `Set` of ids) so latent contacts are never `insertAIFace`d (which
would orphan them).

- [ ] **Step 1: Write the failing test**

Create `Tests/TeststripAppTests/ContactReferenceMatchingTests.swift`. Copy the
`makeModelWithCatalogAssets`/`makeTemporaryDirectory`/`observation` helpers from
`Tests/TeststripAppTests/PeopleFaceSuggestionRejectionTests.swift:60-123` (they
are `private` per file). Seed an unassigned catalog face and a contact reference
with a near-identical embedding.

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class ContactReferenceMatchingTests: XCTestCase {
    private let provenance = AppleVisionEvaluationProvider.faceProvenance

    private func obs(_ id: AssetID, _ vec: [Double]) -> CatalogFaceObservation {
        CatalogFaceObservation(assetID: id, faceIndex: 0,
                               boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                               captureQuality: 0.9, embedding: vec, provenance: provenance)
    }

    func testLatentContactMatchSurfacesAsSuggestion() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-latent-suggest", assets: [a])
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")

        model.refreshPeopleFaceSuggestions()

        let s = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-contact:C1" })
        XCTAssertEqual(s.kind, .matchExisting(personID: "contact:C1", personName: "Dan Shapiro"))
    }

    func testLatentContactMatchIsNotAutoApplied() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-latent-noautoapply", assets: [a])
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")

        try model.promoteFaceMatches(for: a.id)

        // No orphan person_faces row for the latent contact.
        // personFaces(assetID:) -> [Int: PersonFaceAssignment] (keyed by face index).
        XCTAssertTrue(try repo.personFaces(assetID: a.id).isEmpty)
    }

    func testNameAttachedContactMatchAutoApplies() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-attached-autoapply", assets: [a])
        try repo.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "p1", name: "Dan Shapiro",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")

        try model.promoteFaceMatches(for: a.id)

        let assignment = try XCTUnwrap(try repo.personFaces(assetID: a.id)[0])
        XCTAssertEqual(assignment.personID, "p1")   // auto-applied…
        XCTAssertEqual(assignment.origin, "ai")     // …as a tentative proposal
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContactReferenceMatchingTests`
Expected: FAIL — latent match dropped (no suggestion) / auto-applied (orphan row).

- [ ] **Step 3: Write minimal implementation**

In `refreshPeopleFaceSuggestions` (AppModel.swift:3626), after building
`confirmedFacesByPerson` and before `FaceSuggestionBuilder().suggestions(...)`,
merge references; and merge names before building `personNamesByID`:

```swift
            var confirmedFacesByPerson = try catalog.repository.confirmedFaceEmbeddingsByPerson(provenance: provenance)
            for (personID, vectors) in try catalog.repository.contactReferenceEmbeddingsByPerson() {
                confirmedFacesByPerson[personID, default: []].append(contentsOf: vectors)
            }
            let suggestions = FaceSuggestionBuilder().suggestions(
                unassignedFaces: unassigned.map { FaceEmbedding(faceID: $0.faceID, vector: $0.embedding) },
                confirmedFacesByPerson: confirmedFacesByPerson
            )
            let observationsByFaceID = Dictionary(uniqueKeysWithValues: unassigned.map { ($0.faceID, $0) })
            var personNamesByID = Dictionary(uniqueKeysWithValues: catalogPeople.map { ($0.id, $0.name) })
            for (personID, name) in try catalog.repository.contactReferenceNamesByPerson() where personNamesByID[personID] == nil {
                personNamesByID[personID] = name
            }
```

In `promoteFaceMatches` (AppModel.swift:3670), merge references into the centroid
dict the same way, and skip matches to person ids that have no `people` row:

```swift
        var confirmedFacesByPerson = try catalog.repository.confirmedFaceEmbeddingsByPerson(provenance: provenance)
        for (personID, vectors) in try catalog.repository.contactReferenceEmbeddingsByPerson() {
            confirmedFacesByPerson[personID, default: []].append(contentsOf: vectors)
        }
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: unassigned.map { FaceEmbedding(faceID: $0.faceID, vector: $0.embedding) },
            confirmedFacesByPerson: confirmedFacesByPerson
        )
        let materializedPersonIDs = Set(try catalog.repository.people().map(\.id))
        let rejectedPairs = try catalog.repository.rejectedFacePeople()
        for match in suggestions.matches where materializedPersonIDs.contains(match.personID) {
            for faceID in match.faceIDs where faceID.assetID == assetID {
                guard !rejectedPairs.contains(
                    RejectedFacePerson(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: match.personID)
                ) else { continue }
                try catalog.repository.insertAIFace(assetID: faceID.assetID, faceIndex: faceID.faceIndex, personID: match.personID)
            }
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContactReferenceMatchingTests`
Expected: PASS (3 tests). Then `swift build`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/ContactReferenceMatchingTests.swift
git commit -m "feat: union contact references into the matcher; latent matches review-only"
```

---

### Task 6: Confirm a latent-contact suggestion materializes the person

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`confirmPeopleFaceSuggestion(_:)` ~3695)
- Test: `Tests/TeststripAppTests/ContactReferenceMatchingTests.swift` (extend)

**Interfaces:**
- Consumes: `upsertPerson`, `assignFaces`, `recordRejectedFacePerson` (via existing reject path).
- Produces: confirming a `.matchExisting` suggestion whose `personID` has no
  `people` row creates it (`upsertPerson`) then confirms (`assignFaces`,
  `origin='user'` + `person_assets`). Existing-person confirms are unchanged.

**Design:** The single-arg `confirmPeopleFaceSuggestion(_:)` currently calls only
`assignFaces(...)`, which throws `CatalogError.notFound` for a latent contact
(no `people` row — `assignFaces` calls `requirePerson`). Make it `upsertPerson`
first, using the name carried in `.matchExisting(personID, personName)`. This is
idempotent for existing people (ON CONFLICT updates name) and materializes latent
contacts.

- [ ] **Step 1: Write the failing test**

Append to `ContactReferenceMatchingTests.swift`:

```swift
extension ContactReferenceMatchingTests {
    func testConfirmingLatentContactSuggestionCreatesConfirmedPerson() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-confirm-materialize", assets: [a])
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")
        model.refreshPeopleFaceSuggestions()
        let s = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-contact:C1" })

        try model.confirmPeopleFaceSuggestion(s)

        XCTAssertEqual(model.catalogPeople.first { $0.id == "contact:C1" }?.name, "Dan Shapiro")
        XCTAssertEqual(try repo.assetIDs(personID: "contact:C1"), [a.id]) // confirmed person_assets
    }

    func testLatentContactWithNoMatchCreatesNoPerson() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-nomatch-noperson", assets: [a])
        // Catalog face is FAR from the reference embedding → no match.
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [0, 1, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")
        model.refreshPeopleFaceSuggestions()
        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-contact:C1" })
        XCTAssertTrue(model.catalogPeople.isEmpty) // no phantom person
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContactReferenceMatchingTests`
Expected: FAIL — confirm throws `notFound` (no `upsertPerson`).

- [ ] **Step 3: Write minimal implementation**

In `confirmPeopleFaceSuggestion(_ suggestion:)` (AppModel.swift:3695), add the
`upsertPerson` before `assignFaces`:

```swift
    public func confirmPeopleFaceSuggestion(_ suggestion: PeopleFaceSuggestion) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard case .matchExisting(let personID, let personName) = suggestion.kind else {
            throw TeststripError.invalidState("face suggestion has no matched person; name it instead")
        }
        // Materialize a latent contact person on first confirm (idempotent for
        // an already-real person: ON CONFLICT refreshes the name).
        try catalog.repository.upsertPerson(id: personID, name: personName)
        try catalog.repository.assignFaces(suggestion.faceIDs, toPersonID: personID)
        try loadCatalogPeople()
        refreshCatalogEvaluationKindSummaries()
        refreshPeopleFaceSuggestions()
        try loadCatalogPage(preferredSelection: nil)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContactReferenceMatchingTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/ContactReferenceMatchingTests.swift
git commit -m "feat: confirming a latent-contact suggestion materializes the person"
```

---

### Task 7: Show the contact photo as the review-card reference image

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (expose a `contactReferencePhotoURL(forPersonID:)` accessor)
- Modify: `Sources/TeststripApp/PeopleView.swift` (`PeopleFaceSuggestionCard` ~846; `suggestionCards` ~699; `faceSuggestionCard` ~312)

**Interfaces:**
- Consumes: `catalog.repository.contactReferenceFace(personID:)` (Task 2); the
  `AppCatalog.contactPhotoCache` property this task introduces.
- Produces: `AppCatalog.contactPhotoCache` (used again in Task 8);
  `AppModel.contactReferencePhoto(forPersonID:)`.

**Design:** This task introduces `AppCatalog.contactPhotoCache` (its first
consumer), then adds an optional `referencePhotoURL: URL?` +
`referenceBoundingBox: FaceBoundingBox?` to `PeopleFaceSuggestionCard`, populates
them at the view layer via `model.contactReferencePhoto(forPersonID:)`, and
renders a second small `FaceCropAvatar` in `faceSuggestionCard`.

This task is UI + a thin accessor + the cache wiring; verify with `swift build`
(SwiftUI body assembly is not unit-testable here). The accessor's behavior is
covered by Task 8's import test + the e2e card.

- [ ] **Step 1: Add `AppCatalog.contactPhotoCache` (defaulted)**

In `AppCatalog.swift`: add `contactPhotoRoot: URL` to `AppCatalogPaths` and set it
in `defaultPaths` to `root.appendingPathComponent("ContactPhotos", isDirectory:
true)`; add `public var contactPhotoCache: ContactPhotoCache` to `AppCatalog`;
give the init param a **default** so the ~30 positional `AppCatalog(...)` test
call sites keep compiling:
`contactPhotoCache: ContactPhotoCache = ContactPhotoCache(root: FileManager.default.temporaryDirectory)`.
In `open(paths:)`, create the directory (like `previewCacheRoot`) and pass
`ContactPhotoCache(root: paths.contactPhotoRoot)`.

- [ ] **Step 2: Add the accessor**

In `AppModel.swift`, near `previewURL(for:levels:)` (~13118):

```swift
    /// The cached address-book photo (+ its face box) for a person that was
    /// seeded from Contacts, or nil if this person has no contact reference.
    public func contactReferencePhoto(forPersonID personID: String) -> (url: URL, box: FaceBoundingBox)? {
        guard let catalog,
              let reference = try? catalog.repository.contactReferenceFace(personID: personID) else { return nil }
        let url = catalog.contactPhotoCache.url(for: reference.contactIdentifier)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, reference.boundingBox)
    }
```

- [ ] **Step 3: Add the card fields + populate**

In `PeopleView.swift`, extend `PeopleFaceSuggestionCard` (~846):

```swift
struct PeopleFaceSuggestionCard: Equatable, Identifiable {
    var id: String
    var title: String
    var countText: String
    var confirmActionTitle: String
    var isOneTapConfirm: Bool
    var suggestion: PeopleFaceSuggestion
    var referencePhotoURL: URL? = nil
    var referenceBoundingBox: FaceBoundingBox? = nil
}
```

`PeoplePresentation` builds these cards, but the contact-photo lookup needs the
`model`. In `PeopleView.suggestionCards` construction, after building each
`.matchExisting` card, set its reference fields from
`model.contactReferencePhoto(forPersonID: personID)`. (If `suggestionCards` is a
pure `PeoplePresentation` member with no `model`, populate the reference fields at
the view layer where the cards are consumed — in `faceSuggestionCard`'s caller —
by mapping over the cards with `model.contactReferencePhoto(...)`. Choose the
site that already has `model` in scope; do not thread `model` into
`PeoplePresentation`.)

- [ ] **Step 4: Render the reference image**

In `faceSuggestionCard` (~312), inside the label `HStack`, before the existing
`FaceCropAvatar`, add:

```swift
                    if let referenceURL = card.referencePhotoURL {
                        VStack(spacing: 2) {
                            FaceCropAvatar(previewURL: referenceURL,
                                           boundingBox: card.referenceBoundingBox ?? FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                           diameter: 44)
                            Text("Contacts").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!`, no new warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/PeopleView.swift Sources/TeststripApp/AppCatalog.swift
git commit -m "feat: show the address-book photo as the review-card reference"
```

---

### Task 8: Live Contacts provider, import action, menu, entitlement, Info.plist

**Files:**
- Create: `Sources/TeststripApp/LiveContactsProvider.swift`
- Modify: `Sources/TeststripApp/AppCatalog.swift` (`contactPhotoCache` + path, if not already added in Task 7)
- Modify: `Sources/TeststripApp/AppModel.swift` (`importFacesFromContacts()`; hold an injected `ContactsProviding?`)
- Modify: `Sources/TeststripApp/main.swift` (People menu command; inject provider via `load`)
- Modify: `config/macos/Teststrip.entitlements`; `script/lib/app_bundle.sh`
- Test: `Tests/TeststripAppTests/ImportFacesFromContactsTests.swift` (new — drives `importFacesFromContacts` with a stub provider)

**Interfaces:**
- Consumes: `ContactsProviding`, `ContactFaceSeeder`, `CoreMLFaceEmbeddingModel.auraFace()`, `FaceRecognitionEmbedder`, `ContactPhotoCache`.
- Produces: `AppModel.importFacesFromContacts() async` → seeds via the injected
  provider + seeder, then `refreshPeopleFaceSuggestions()`; reports a summary or a
  clear error (permission denied / model unavailable).

`AppCatalog.contactPhotoCache` was already introduced in Task 7 — this task only
adds the provider injection and the import action.

- [ ] **Step 1: Write the failing test (stub provider drives seeding)**

Create `Tests/TeststripAppTests/ImportFacesFromContactsTests.swift`. Inject a stub
`ContactsProviding` returning fixed records, and a `detectFaces` stub so no real
model is needed. Because `importFacesFromContacts` constructs the seeder
internally, expose a testable seam: `AppModel.load(..., contactsProvider:
(any ContactsProviding)? = nil, contactFaceDetector: (@Sendable (CGImage) throws ->
[AppleVisionFaceObservation])? = nil)` — when `contactFaceDetector` is nil the
model builds the real embedder; tests pass a stub detector.

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

private struct StubContacts: ContactsProviding {
    let records: [ContactRecord]
    func contactsWithPhotos() throws -> [ContactRecord] { records }
}

final class ImportFacesFromContactsTests: XCTestCase {
    func testImportSeedsReferenceAndRefreshes() async throws {
        // Build a model whose load injects the stub provider + a stub detector.
        // (Harness mirrors PeopleFaceSuggestionRejectionTests.makeModelWithCatalogAssets,
        // but calls AppModel.load with contactsProvider:/contactFaceDetector:.)
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let jpeg = tinyJPEG()
        let (model, repo) = try makeModelWithContacts(
            named: "import-contacts", assets: [a],
            provider: StubContacts(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg)]),
            detectFaces: { _ in [AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                captureQuality: 0.9, featurePrintVector: [1, 0, 0])] })

        try await model.importFacesFromContacts()

        XCTAssertEqual(try repo.contactReferenceNamesByPerson()["contact:C1"], "Dan Shapiro")
    }
}
```

> `makeModelWithContacts` + `tinyJPEG` mirror the Task-4 test's JPEG generator and
> the rejection-test harness, but call `AppModel.load(catalog:, contactsProvider:,
> contactFaceDetector:)`. Keep them private in this file.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImportFacesFromContactsTests`
Expected: FAIL — no `importFacesFromContacts` / no injection params.

- [ ] **Step 3: Implement**

Add the injection params to `AppModel.load` (defaulted — Global Constraints), store
them, and implement the import. The embedder-availability gate returns a clear
error when `auraFace()` is nil:

```swift
    public func importFacesFromContacts() async throws {
        guard let catalog else { throw TeststripError.invalidState("app model has no catalog") }
        guard let provider = contactsProvider else {
            throw TeststripError.invalidState("Contacts access is not available")
        }
        let detector: @Sendable (CGImage) throws -> [AppleVisionFaceObservation]
        if let injected = contactFaceDetector {
            detector = injected
        } else {
            guard let model = CoreMLFaceEmbeddingModel.auraFace() else {
                throw TeststripError.invalidState("The face model is unavailable; cannot import from Contacts")
            }
            let embedder = FaceRecognitionEmbedder(model: model)
            detector = { try embedder.faceObservations(in: $0) }
        }
        let records = try provider.contactsWithPhotos()
        let seeder = ContactFaceSeeder(detectFaces: detector, repository: catalog.repository,
                                       photoCache: catalog.contactPhotoCache)
        let summary = try seeder.seed(records: records)
        contactSeedSummaryText = "Contacts: \(summary.seeded) seeded, \(summary.unchanged) unchanged, \(summary.skippedNoFace) without a face"
        refreshPeopleFaceSuggestions()
    }
```

(Store `contactsProvider`, `contactFaceDetector`, and a
`contactSeedSummaryText: String?` on the model; thread the two injected values
from `load`.)

Create `Sources/TeststripApp/LiveContactsProvider.swift` (the thin live conformer;
the permission request happens here or in the import action — see Step 6):

```swift
import Contacts
import Foundation
import TeststripCore

/// Live `CNContactStore`-backed contacts. `contactsWithPhotos()` fetches every
/// contact that has image data and returns `(identifier, name, imageData)`.
public struct LiveContactsProvider: ContactsProviding {
    public init() {}

    public func contactsWithPhotos() throws -> [ContactRecord] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
        ]
        var records: [ContactRecord] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: request) { contact, _ in
            guard contact.imageDataAvailable, let data = contact.imageData else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            records.append(ContactRecord(identifier: contact.identifier, name: name, imageData: data))
        }
        return records
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ImportFacesFromContactsTests`
Expected: PASS. Then `swift build`.

- [ ] **Step 5: Menu command + permission request + injection**

In `main.swift`, inside `CommandMenu("People")` (PeopleCommands, ~384) add:

```swift
            Button("Import Faces from Contacts…") {
                importFacesFromContacts()
            }
```

and a helper that requests access (the first TCC prompt, from a user gesture)
then runs the import on a detached task, hopping back to `@MainActor`:

```swift
    private func importFacesFromContacts() {
        Task {
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                CNContactStore().requestAccess(for: .contacts) { ok, _ in cont.resume(returning: ok) }
            }
            guard granted else {
                await MainActor.run { model.errorMessage = "Teststrip needs Contacts access to import faces. Enable it in System Settings ▸ Privacy & Security ▸ Contacts." }
                return
            }
            do {
                try await model.importFacesFromContacts()
            } catch {
                await MainActor.run { model.errorMessage = error.localizedDescription }
            }
        }
    }
```

Inject the live provider at launch: in `AppCatalog.loadModel` (`AppCatalog.swift:120`),
pass `contactsProvider: LiveContactsProvider()` into `AppModel.load`. (Add
`import Contacts` to `main.swift`.)

- [ ] **Step 6: Entitlement + Info.plist**

In `config/macos/Teststrip.entitlements`, add before `</dict>`:

```xml
  <key>com.apple.security.personal-information.addressbook</key>
  <true/>
```

In `script/lib/app_bundle.sh`, in the `teststrip_write_info_plist` heredoc,
before the closing `</dict>` (~line 168):

```xml
  <key>NSContactsUsageDescription</key>
  <string>Teststrip matches faces in your photos against your contacts to suggest who's who. Your contacts never leave your Mac.</string>
```

- [ ] **Step 7: Build + full suite**

Run: `swift build` then `swift test`
Expected: `Build complete!`; `Executed N tests … 0 failures`.

- [ ] **Step 8: Commit**

```bash
git add Sources/TeststripApp/LiveContactsProvider.swift Sources/TeststripApp/AppCatalog.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/main.swift config/macos/Teststrip.entitlements script/lib/app_bundle.sh Tests/TeststripAppTests/ImportFacesFromContactsTests.swift
git commit -m "feat: Import Faces from Contacts — live provider, menu, entitlement"
```

---

### Task 9: End-to-end scenario card

**Files:**
- Create: `test/scenarios/people-023-contacts-seeding.md`

Authored, not run (VM + AuraFace + seeded VM Contacts required). Follow the
format of `test/scenarios/people-021-face-group-review.md` and
`people-022-proposed-and-key-photo.md` (dedicated `## Expected` with per-step
"Fails if", `## Run status`, idle-wedge caution).

- [ ] **Step 1: Write the card**

Create `test/scenarios/people-023-contacts-seeding.md` covering: seed a VM
contact whose photo is a known person also present (unconfirmed) in the seeded
library; run **People ▸ Import Faces from Contacts**; grant access; assert a
`contact_reference_faces` row exists (`script/vm_scenario_run.sh sql`); assert
that a catalog face of that person surfaces as an "Is this [name]?" review card
showing the **Contacts** reference image; confirm it → assert `people` row +
`person_faces.origin='user'` + `person_assets` for that `contact:<id>` person;
and a second leg: a contact whose name matches an already-confirmed person routes
the recall boost into that person's Proposed section (`person_faces.origin='ai'`).
Include a "Fails if" for each and a Sharp-edges note that the import fires the
first TCC prompt and that latent contacts with no library match create no
`people` row.

- [ ] **Step 2: Commit**

```bash
git add test/scenarios/people-023-contacts-seeding.md
git commit -m "test: scenario card — Contacts seeding (people-023)"
```

---

## Notes for the executor

- Task order matters: 1→2 (table→reads); 3 (cache, independent); 4 needs 2+3;
  5 needs 2; 6 needs 5; 7 needs 2 (+ the `AppCatalog.contactPhotoCache` field,
  which 7 or 8 introduces — introduce it once, defaulted); 8 needs 4+5+6+7; 9 last.
- Run the full `swift test` once after Task 8 before the whole-branch review.
- Whole-branch review focus: the latent-vs-materialized gate (no orphan
  `insertAIFace`, no phantom people, latent matches surface only via the names
  merge), embedding-model compatibility (AuraFace-v1 only), the defaulted new
  `AppCatalog`/`load` params (no broken call sites), Contacts main-thread/async
  correctness, and the invariant (contact matches are proposals until confirmed).
