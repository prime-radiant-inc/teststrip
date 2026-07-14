# Machine-label Provenance & Auto-apply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Machine-derived labels (scene keywords, captions, face/person identity, autopilot flags/ratings) auto-apply to the catalog tagged `origin = ai` (unconfirmed); a user gesture confirms them (`origin → user`, sidecar written) or removes them; unconfirmed labels are never written to `.xmp` sidecars and never drive destructive/committing operations.

**Architecture:** A provenance flag is added to the label stores (`origin` column on `person_faces`/`person_assets`; `aiUnconfirmedKeywords`/`aiUnconfirmedFields` in `AssetMetadata`; a new `removed_ai_labels` table). A post-evaluation *promotion* step writes flagged labels. Sidecar confirmed-only filtering lives at the `XMPPacket`/`XMPSidecarStore` write layer; the metadata-sync watermark keys on the *confirmed projection* so AI-only writes never queue a sidecar. Autopilot flags become tentative and are excluded from the reject-relocation/culling-commit paths.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, SQLite (hand-rolled `CatalogDatabase`), XCTest. Spec: `docs/superpowers/specs/2026-07-14-machine-label-provenance.md`.

## Global Constraints

- **Provenance values:** `origin` is the string `'user'` (default) or `'ai'`. Columns are `origin TEXT NOT NULL DEFAULT 'user'`.
- **Sidecar rule (hard):** a `.xmp` sidecar is written only for **confirmed** labels; unconfirmed AI labels are catalog-only. Confirmed projection = `keywords` minus `aiUnconfirmedKeywords`, and `flag`/`caption`/`rating` only when NOT in `aiUnconfirmedFields`.
- **Tentative-flag rule (hard, safety-critical):** an unconfirmed AI `flag`/`rating` never drives destructive or committing operations — specifically it must be excluded from the reject-relocation scope (`rejectRelocationScope`) that moves/trashes originals, and it counts as *undecided* in culling counts/triage.
- **Non-clobbering:** promotion never overwrites a `user` label/field, never re-adds anything in `removed_ai_labels`, and never re-suggests a `(person, face)` in `rejected_face_people`.
- **Confirmed-only centroids:** the face-match centroid query uses `person_faces.origin = 'user'` only.
- **`MetadataField` set:** `aiUnconfirmedFields` holds only `.flag`, `.caption`, `.rating`.
- **Codable:** `AssetMetadata` has a custom `init(from:)`; new fields decode with `decodeIfPresent(...) ?? []` (Swift throws on a missing key).
- **Confidence floors (constants, tunable):** object-keyword floor `0.5` (per *signal*, applied to all labels in that signal); face-match distance `1.23` (`FaceSuggestionBuilder.defaultMaximumMatchDistance`).
- **Test hygiene:** every behavior test asserts against catalog ground truth and on-disk sidecar presence/absence, never a mocked value. Test output must be pristine.
- **Commit style:** `feat:` / `refactor:` / `test:` / `docs:` conventional prefixes; commit at each task boundary.

---

## File Map

**Data model / Core (`Sources/TeststripCore`)**
- `Catalog/CatalogMigrations.swift` — bump version, add `removed_ai_labels` CREATE, no column ALTERs here.
- `Catalog/CatalogDatabase.swift:35-61` (`migrate()`) — add `addColumnIfMissing` for the two `origin` columns.
- `Domain/Metadata.swift` — `AssetMetadata` provenance fields + `MetadataField` enum + Codable + confirmed projection + `hasWrittenPortableMetadata`.
- `Catalog/CatalogRepository.swift` — origin-aware `person_faces`/`person_assets` writes; confirmed-only centroid query; face-level unassigned query; `removed_ai_labels` CRUD; confirm/promote helpers.
- `Metadata/XMPPacket.swift`, `Metadata/XMPSidecarStore.swift` — write the confirmed projection.
- `Metadata/MetadataSyncPlanner.swift` — key the sidecar decision on the confirmed projection.
- `Worker/WorkerCommandExecutor.swift:492,519` — write confirmed projection; merge on `.importSidecar`.
- `People/FaceSuggestionBuilder.swift` — unchanged logic; consumed by promotion.

**App (`Sources/TeststripApp`)**
- `AppModel.swift` — promotion step; confirm/remove gestures; autopilot fold-in; tentative-flag exclusions; wire promotion into the post-eval path.
- `LibraryGridView.swift` — remove the inline suggestion pills; ✨ affordances (inspector).
- `InspectorView.swift` / `PhotoFacesSectionView.swift` — ✨ confirm/remove affordances.

**Docs / tests**
- `CLAUDE.md` — invariant rewrite.
- `Tests/TeststripCoreTests/*`, `Tests/TeststripAppTests/*` — unit tests per task.
- `test/scenarios/` — E2E scenario card.

---

## Phase 1 — Data model & types

### Task 1: Schema — `origin` columns + `removed_ai_labels` table

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (version + new CREATE)
- Modify: `Sources/TeststripCore/Catalog/CatalogDatabase.swift:39-56` (add two `addColumnIfMissing`)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces: tables `person_faces`/`person_assets` gain `origin TEXT NOT NULL DEFAULT 'user'`; new table `removed_ai_labels(asset_id TEXT, field TEXT, value TEXT, created_at REAL, PRIMARY KEY(asset_id, field, value))`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
func testMigrationAddsProvenanceColumnsAndRemovedLabelsTable() throws {
    let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-provenance-migration")
    let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
    try database.migrate()

    let personFaces = try database.rows("PRAGMA table_info(person_faces)")
    XCTAssertTrue(personFaces.contains { $0["name"] == "origin" })
    let personAssets = try database.rows("PRAGMA table_info(person_assets)")
    XCTAssertTrue(personAssets.contains { $0["name"] == "origin" })
    let removed = try database.rows("PRAGMA table_info(removed_ai_labels)")
    XCTAssertEqual(Set(removed.compactMap { $0["name"] }), ["asset_id", "field", "value", "created_at"])
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'CatalogDatabaseTests/testMigrationAddsProvenanceColumnsAndRemovedLabelsTable'`
Expected: FAIL — no `origin` column / no `removed_ai_labels` table.

- [ ] **Step 3: Add the CREATE and version bump**

In `CatalogMigrations.swift`: change `static let version = 19` to `static let version = 20`. Append to the `statements` array (before the closing `]`):

```swift
        ,
        """
        CREATE TABLE IF NOT EXISTS removed_ai_labels (
            asset_id TEXT NOT NULL,
            field TEXT NOT NULL,
            value TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (asset_id, field, value)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_removed_ai_labels_asset ON removed_ai_labels(asset_id)"
```

In `CatalogDatabase.swift` `migrate()`, after line 55 (`person_ids_json`) and before `coordinateIndexStatement`:

```swift
        try addColumnIfMissing(table: "person_faces", column: "origin", definition: "TEXT NOT NULL DEFAULT 'user'")
        try addColumnIfMissing(table: "person_assets", column: "origin", definition: "TEXT NOT NULL DEFAULT 'user'")
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'CatalogDatabaseTests/testMigrationAddsProvenanceColumnsAndRemovedLabelsTable'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogMigrations.swift Sources/TeststripCore/Catalog/CatalogDatabase.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: schema v20 — person origin columns + removed_ai_labels table"
```

### Task 2: `AssetMetadata` provenance fields + confirmed projection

**Files:**
- Modify: `Sources/TeststripCore/Domain/Metadata.swift`
- Test: `Tests/TeststripCoreTests/MetadataTests.swift` (create if absent)

**Interfaces:**
- Produces:
  - `public enum MetadataField: String, Codable, Sendable, CaseIterable { case flag, caption, rating }`
  - `AssetMetadata.aiUnconfirmedKeywords: Set<String>` (default `[]`)
  - `AssetMetadata.aiUnconfirmedFields: Set<MetadataField>` (default `[]`)
  - `AssetMetadata.confirmedProjection: AssetMetadata` — a copy with all AI-unconfirmed labels dropped (keywords minus `aiUnconfirmedKeywords`; `flag`/`caption`/`rating` cleared if in `aiUnconfirmedFields`; both provenance sets empty).
  - `hasWrittenPortableMetadata` reflects the **confirmed** projection.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/MetadataTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class MetadataTests: XCTestCase {
    func testDecodesLegacyBlobWithoutProvenanceFields() throws {
        let json = #"{"rating":3,"keywords":["beach"]}"#
        let meta = try JSONDecoder().decode(AssetMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(meta.keywords, ["beach"])
        XCTAssertTrue(meta.aiUnconfirmedKeywords.isEmpty)
        XCTAssertTrue(meta.aiUnconfirmedFields.isEmpty)
    }

    func testProvenanceRoundTrips() throws {
        var meta = AssetMetadata(rating: 0, keywords: ["beach", "people"])
        meta.aiUnconfirmedKeywords = ["people"]
        meta.aiUnconfirmedFields = [.flag]
        meta.flag = .reject
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(AssetMetadata.self, from: data)
        XCTAssertEqual(decoded, meta)
    }

    func testConfirmedProjectionDropsUnconfirmed() throws {
        var meta = AssetMetadata(rating: 4, keywords: ["beach", "people"], caption: "a caption")
        meta.aiUnconfirmedKeywords = ["people"]
        meta.aiUnconfirmedFields = [.caption, .rating]
        meta.flag = .pick // confirmed (not in aiUnconfirmedFields)
        let confirmed = meta.confirmedProjection
        XCTAssertEqual(confirmed.keywords, ["beach"])
        XCTAssertNil(confirmed.caption)
        XCTAssertEqual(confirmed.rating, 0)
        XCTAssertEqual(confirmed.flag, .pick)
        XCTAssertTrue(confirmed.aiUnconfirmedKeywords.isEmpty)
        XCTAssertTrue(confirmed.aiUnconfirmedFields.isEmpty)
    }

    func testHasWrittenPortableMetadataIgnoresUnconfirmed() throws {
        var meta = AssetMetadata(rating: 0, keywords: ["people"])
        meta.aiUnconfirmedKeywords = ["people"]
        XCTAssertFalse(meta.hasWrittenPortableMetadata)
        meta.aiUnconfirmedKeywords = []
        XCTAssertTrue(meta.hasWrittenPortableMetadata)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'MetadataTests'`
Expected: FAIL to compile (`aiUnconfirmedKeywords` unknown).

- [ ] **Step 3: Implement**

In `Metadata.swift`, add the enum above `AssetMetadata`:

```swift
public enum MetadataField: String, Codable, Sendable, CaseIterable {
    case flag
    case caption
    case rating
}
```

Add stored properties after `copyright` (line 27):

```swift
    public var aiUnconfirmedKeywords: Set<String>
    public var aiUnconfirmedFields: Set<MetadataField>
```

Add init params (with defaults) and assignments in the memberwise `init` (lines 46-64):

```swift
        aiUnconfirmedKeywords: Set<String> = [],
        aiUnconfirmedFields: Set<MetadataField> = []
```
```swift
        self.aiUnconfirmedKeywords = aiUnconfirmedKeywords
        self.aiUnconfirmedFields = aiUnconfirmedFields
```

In `init(from:)` (after line 83, `copyright`):

```swift
        self.aiUnconfirmedKeywords = try container.decodeIfPresent(Set<String>.self, forKey: .aiUnconfirmedKeywords) ?? []
        self.aiUnconfirmedFields = try container.decodeIfPresent(Set<MetadataField>.self, forKey: .aiUnconfirmedFields) ?? []
```

Add `confirmedProjection` and rewrite `hasWrittenPortableMetadata`:

```swift
    /// A copy with every AI-unconfirmed label dropped — what is exported to the
    /// XMP sidecar and what "portable metadata exists" is judged against.
    public var confirmedProjection: AssetMetadata {
        AssetMetadata(
            rating: aiUnconfirmedFields.contains(.rating) ? 0 : rating,
            colorLabel: colorLabel,
            flag: aiUnconfirmedFields.contains(.flag) ? nil : flag,
            keywords: keywords.filter { !aiUnconfirmedKeywords.contains($0) },
            caption: aiUnconfirmedFields.contains(.caption) ? nil : caption,
            creator: creator,
            copyright: copyright
        )
    }

    public var hasWrittenPortableMetadata: Bool {
        let c = confirmedProjection
        return c.rating > 0
            || c.flag != nil
            || c.colorLabel != nil
            || !c.keywords.isEmpty
            || !(c.caption ?? "").isEmpty
            || !(c.creator ?? "").isEmpty
            || !(c.copyright ?? "").isEmpty
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'MetadataTests'`
Expected: PASS.

- [ ] **Step 5: Full build (metadata is widely used)**

Run: `swift build`
Expected: `Build complete!` (fix any call sites that used the memberwise init positionally — all new params have defaults, so none should break).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Domain/Metadata.swift Tests/TeststripCoreTests/MetadataTests.swift
git commit -m "feat: AssetMetadata provenance fields + confirmed projection"
```

---

## Phase 2 — Repository provenance API

### Task 3: Origin-aware person writes + confirmed-only centroids + face-level unassigned

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (`assignFaces` ~1205-1239; centroid query ~1168-1191; `unassignedFaceObservations` ~1136-1166; add confirm/promote + ai-insert helpers)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `func insertAIFace(assetID: AssetID, faceIndex: Int, personID: PersonID) throws` — guarded insert of an `origin='ai'` `person_faces` row; **no-op if a row already exists** for `(asset_id, face_index)` (never overwrites a user assignment); writes **no** `person_assets` row.
  - `func confirmFace(assetID: AssetID, faceIndex: Int) throws` — sets `person_faces.origin='user'` for that face and upserts the `person_assets` link `origin='user'`.
  - `assignFaces(_:toPersonID:)` writes `person_faces` with `origin='user'` and upserts `person_assets` origin via `ON CONFLICT(person_id, asset_id) DO UPDATE SET origin='user'` (replacing the current `INSERT OR IGNORE`).
  - `confirmedFaceEmbeddingsByPerson` filters `person_faces.origin='user'`.
  - `unassignedFaceObservations` excludes assigned **faces** (`NOT EXISTS person_faces same (asset_id, face_index)`), not whole assets.

- [ ] **Step 1: Write the failing tests**

```swift
func testInsertAIFaceIsGuardedAndAssetLinkFree() throws {
    let (repo, _) = try Self.makePeopleRepo(named: "ai-face-guard")
    let person = try repo.upsertPerson(named: "Ada")
    // First insert an ai face
    try repo.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: person.id)
    // person_faces has an ai row, person_assets has none
    XCTAssertEqual(try repo.personFaceOrigin(assetID: AssetID(rawValue: "a1"), faceIndex: 0), "ai")
    XCTAssertFalse(try repo.hasPersonAsset(personID: person.id, assetID: AssetID(rawValue: "a1")))
    // A user assignment for the same face must NOT be clobbered by a later ai insert
    try repo.assignFaces([FaceRef(assetID: AssetID(rawValue: "a1"), faceIndex: 0)], toPersonID: person.id)
    XCTAssertEqual(try repo.personFaceOrigin(assetID: AssetID(rawValue: "a1"), faceIndex: 0), "user")
    try repo.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: person.id)
    XCTAssertEqual(try repo.personFaceOrigin(assetID: AssetID(rawValue: "a1"), faceIndex: 0), "user")
}

func testConfirmFacePromotesOriginAndAssetLink() throws {
    let (repo, _) = try Self.makePeopleRepo(named: "confirm-face")
    let person = try repo.upsertPerson(named: "Ada")
    try repo.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: person.id)
    try repo.confirmFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0)
    XCTAssertEqual(try repo.personFaceOrigin(assetID: AssetID(rawValue: "a1"), faceIndex: 0), "user")
    XCTAssertTrue(try repo.hasPersonAsset(personID: person.id, assetID: AssetID(rawValue: "a1")))
}
```

(Provide `makePeopleRepo`, `personFaceOrigin`, `hasPersonAsset`, `FaceRef` test helpers if not present — small `rows(...)` queries. The exact `PersonID`/face-ref types are those already used by `assignFaces`; read `CatalogRepository.swift:1205` to match signatures.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'CatalogDatabaseTests/testInsertAIFace'`
Expected: FAIL to compile (`insertAIFace` unknown).

- [ ] **Step 3: Implement**

Add `insertAIFace` (guarded — `INSERT ... SELECT ... WHERE NOT EXISTS` so an existing `(asset_id, face_index)` row is untouched):

```swift
public func insertAIFace(assetID: AssetID, faceIndex: Int, personID: PersonID) throws {
    try database.execute(
        """
        INSERT INTO person_faces (person_id, asset_id, face_index, created_at, origin)
        SELECT ?, ?, ?, ?, 'ai'
        WHERE NOT EXISTS (
            SELECT 1 FROM person_faces WHERE asset_id = ? AND face_index = ?
        )
        """,
        bindings: [personID.rawValue, assetID.rawValue, "\(faceIndex)", "\(Date().timeIntervalSince1970)",
                   assetID.rawValue, "\(faceIndex)"]
    )
}
```
(Use the project's timestamp source; check how existing writes get `created_at` — reuse that, do not hand-roll `Date()` if a clock is injected.)

Add `confirmFace`:

```swift
public func confirmFace(assetID: AssetID, faceIndex: Int) throws {
    try database.transaction {
        try database.execute(
            "UPDATE person_faces SET origin = 'user' WHERE asset_id = ? AND face_index = ?",
            bindings: [assetID.rawValue, "\(faceIndex)"]
        )
        try database.execute(
            """
            INSERT INTO person_assets (person_id, asset_id, created_at, origin)
            SELECT person_id, asset_id, ?, 'user' FROM person_faces
            WHERE asset_id = ? AND face_index = ?
            ON CONFLICT(person_id, asset_id) DO UPDATE SET origin = 'user'
            """,
            bindings: ["\(Date().timeIntervalSince1970)", assetID.rawValue, "\(faceIndex)"]
        )
    }
}
```

Change `assignFaces`'s `person_assets` write (`CatalogRepository.swift:1229-1236`) from `INSERT OR IGNORE` to the `ON CONFLICT(person_id, asset_id) DO UPDATE SET origin='user'` form above, and set `person_faces.origin='user'` explicitly in its `person_faces` upsert.

Change the centroid query (`confirmedFaceEmbeddingsByPerson`, ~1168-1191): add `AND person_faces.origin = 'user'` to its WHERE.

Change `unassignedFaceObservations` (~1136-1166): replace the whole-asset exclusion
`AND NOT EXISTS (SELECT 1 FROM person_assets WHERE person_assets.asset_id = face_observations.asset_id)`
with a face-level exclusion
`AND NOT EXISTS (SELECT 1 FROM person_faces WHERE person_faces.asset_id = face_observations.asset_id AND person_faces.face_index = face_observations.face_index)`.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'CatalogDatabaseTests/testInsertAIFace|CatalogDatabaseTests/testConfirmFace'`
Expected: PASS. Also run the existing people tests: `swift test --filter 'CatalogDatabaseTests'` — no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: origin-aware person writes, confirmed-only centroids, face-level unassigned"
```

### Task 4: `removed_ai_labels` CRUD

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `func recordRemovedAILabel(assetID: AssetID, field: MetadataField, value: String) throws` (`value` = the keyword for `.keyword`-style; empty string `""` for single-valued `flag`/`caption`/`rating`).
  - `func removedAILabels(assetID: AssetID) throws -> Set<RemovedAILabel>` where `RemovedAILabel = (field: MetadataField, value: String)` (define a small `Hashable` struct `RemovedAILabel`).
  - **Note:** `MetadataField` currently has `flag/caption/rating`. Add a `.keyword` case for use as the `field` here (keywords are per-value). Update Task 2's enum to `{flag, caption, rating, keyword}` — but `aiUnconfirmedFields` in `AssetMetadata` still only ever contains `flag/caption/rating` (keywords use `aiUnconfirmedKeywords`).

- [ ] **Step 1: Write the failing test**

```swift
func testRecordAndReadRemovedAILabels() throws {
    let (repo, _) = try Self.makePeopleRepo(named: "removed-labels")
    try repo.recordRemovedAILabel(assetID: AssetID(rawValue: "a1"), field: .keyword, value: "people")
    try repo.recordRemovedAILabel(assetID: AssetID(rawValue: "a1"), field: .caption, value: "")
    let removed = try repo.removedAILabels(assetID: AssetID(rawValue: "a1"))
    XCTAssertTrue(removed.contains(RemovedAILabel(field: .keyword, value: "people")))
    XCTAssertTrue(removed.contains(RemovedAILabel(field: .caption, value: "")))
    XCTAssertTrue(try repo.removedAILabels(assetID: AssetID(rawValue: "a2")).isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'CatalogDatabaseTests/testRecordAndReadRemovedAILabels'`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

Add `.keyword` to `MetadataField` (Task 2 file). Add the struct + methods to `CatalogRepository.swift`:

```swift
public struct RemovedAILabel: Hashable, Sendable {
    public let field: MetadataField
    public let value: String
    public init(field: MetadataField, value: String) { self.field = field; self.value = value }
}

public func recordRemovedAILabel(assetID: AssetID, field: MetadataField, value: String) throws {
    try database.execute(
        """
        INSERT OR IGNORE INTO removed_ai_labels (asset_id, field, value, created_at)
        VALUES (?, ?, ?, ?)
        """,
        bindings: [assetID.rawValue, field.rawValue, value, "\(Date().timeIntervalSince1970)"]
    )
}

public func removedAILabels(assetID: AssetID) throws -> Set<RemovedAILabel> {
    let rows = try database.rows(
        "SELECT field, value FROM removed_ai_labels WHERE asset_id = ?",
        bindings: [assetID.rawValue]
    )
    return Set(rows.compactMap { row in
        guard let f = row["field"], let field = MetadataField(rawValue: f), let value = row["value"] else { return nil }
        return RemovedAILabel(field: field, value: value)
    })
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'CatalogDatabaseTests/testRecordAndReadRemovedAILabels'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: removed_ai_labels repository CRUD"
```

---

## Phase 3 — Sidecar write-layer (confirm-gated)

### Task 5: XMP writes the confirmed projection

**Files:**
- Modify: `Sources/TeststripCore/Metadata/XMPSidecarStore.swift:50` and/or `Sources/TeststripCore/Metadata/XMPPacket.swift:68-93`
- Test: `Tests/TeststripCoreTests/` (XMP tests — find the existing XMP test file; e.g. `XMPPacketTests.swift`)

**Interfaces:**
- Consumes: `AssetMetadata.confirmedProjection` (Task 2).
- Produces: `XMPPacket`/`XMPSidecarStore.write(metadata:...)` emit only confirmed labels. Simplest: at the single `XMPPacket` construction site, build from `metadata.confirmedProjection` rather than `metadata`.

- [ ] **Step 1: Write the failing test**

```swift
func testXMPPacketExcludesUnconfirmedLabels() throws {
    var meta = AssetMetadata(rating: 0, keywords: ["beach", "people"], caption: "cap")
    meta.aiUnconfirmedKeywords = ["people"]
    meta.aiUnconfirmedFields = [.caption]
    let packet = XMPPacket(metadata: meta) // or the actual constructor
    let xml = packet.serialized() // match the real API
    XCTAssertTrue(xml.contains("beach"))
    XCTAssertFalse(xml.contains("people"))
    XCTAssertFalse(xml.contains("cap"))
}
```
(Match the real `XMPPacket` constructor/serialization API — read `XMPPacket.swift`.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter 'testXMPPacketExcludesUnconfirmedLabels'`
Expected: FAIL — "people"/"cap" present.

- [ ] **Step 3: Implement**

At the `XMPPacket` construction (the one place packets are built from `AssetMetadata`), pass `metadata.confirmedProjection`. If `XMPPacket` takes an `AssetMetadata`, change its initializer body's first line to `let metadata = metadata.confirmedProjection` (or filter each field). Keep it at this single layer so all callers inherit it.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter 'testXMPPacketExcludesUnconfirmedLabels'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Metadata Tests/TeststripCoreTests
git commit -m "feat: XMP sidecar exports the confirmed projection only"
```

### Task 6: Sync watermark keyed on confirmed change + `.importSidecar` merges

**Files:**
- Modify: `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift` (decision keyed on confirmed projection / `hasWrittenPortableMetadata`)
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift:519` (`.importSidecar` merge) and `Sources/TeststripCore/Ingest/IngestService.swift:168` if it also replaces
- Test: `Tests/TeststripCoreTests/` (planner + worker executor tests)

**Interfaces:**
- Produces: promoting an AI keyword onto an already-sidecar'd asset does NOT queue/write a sidecar; importing a sidecar preserves catalog-only AI labels.

- [ ] **Step 1: Write the failing tests**

```swift
func testAIOnlyMetadataChangeQueuesNoSidecarWrite() throws {
    // Seed an asset with a confirmed keyword and a synced sidecar, then add an
    // AI-unconfirmed keyword; the planner must NOT return a sidecar write.
    // (Construct via MetadataSyncPlanner with before/after metadata + prior sync state.)
    // Assert the planner action is .none / .noChange for an AI-only delta.
}

func testImportSidecarPreservesCatalogAILabels() throws {
    // catalogMetadata has keywords ["beach","people"], aiUnconfirmedKeywords ["people"].
    // sidecarMetadata (parsed) has keywords ["beach"] (confirmed only).
    // After the merge, catalog keeps "people" in keywords AND in aiUnconfirmedKeywords.
}
```
(Fill in with the planner's real API — read `MetadataSyncPlanner.swift` for its decision inputs/outputs; read `WorkerCommandExecutor.swift:515-521` for the `.importSidecar` handler shape.)

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter 'testAIOnlyMetadataChangeQueuesNoSidecarWrite|testImportSidecarPreservesCatalogAILabels'`
Expected: FAIL.

- [ ] **Step 3: Implement**

- Planner: change the "did local metadata change?" comparison to compare `confirmedProjection` (or use `hasWrittenPortableMetadata` + a confirmed-projection equality) rather than raw `metadata_json`/`catalog_generation`, so an AI-only delta is `.noChange`.
- `.importSidecar` in `WorkerCommandExecutor.swift:519`: replace `catalogMetadata = metadata` with a merge that keeps catalog AI state:

```swift
var merged = metadata // parsed sidecar (confirmed labels only)
merged.keywords = Array(Set(merged.keywords).union(catalogMetadata.aiUnconfirmedKeywords))
merged.aiUnconfirmedKeywords = catalogMetadata.aiUnconfirmedKeywords
merged.aiUnconfirmedFields = catalogMetadata.aiUnconfirmedFields
if catalogMetadata.aiUnconfirmedFields.contains(.caption) { merged.caption = catalogMetadata.caption }
if catalogMetadata.aiUnconfirmedFields.contains(.flag) { merged.flag = catalogMetadata.flag }
if catalogMetadata.aiUnconfirmedFields.contains(.rating) { merged.rating = catalogMetadata.rating }
catalogMetadata = merged
```

Apply the same merge in `IngestService.swift:168` if it replaces on ingest.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter 'testAIOnlyMetadataChangeQueuesNoSidecarWrite|testImportSidecarPreservesCatalogAILabels'`
Expected: PASS. Run the full metadata-sync suite: `swift test --filter 'MetadataSync'` — no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore Tests/TeststripCoreTests
git commit -m "feat: sidecar sync keyed on confirmed projection; importSidecar merges AI labels"
```

---

## Phase 4 — Promotion (auto-apply)

### Task 7: Keyword & caption promotion

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `promoteMetadataLabels(for:)`; reuse `objectLabels(from:)` ~7308; caption signal read)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces: `func promoteMetadataLabels(for assetID: AssetID) throws` — for each `.object` signal with `confidence >= 0.5`, add each label not already present and not in `removed_ai_labels(.keyword)` to `keywords` + `aiUnconfirmedKeywords`; if an AI caption signal exists, the asset has no user caption, and the caption is not removed, set `caption` + add `.caption` to `aiUnconfirmedFields`. Writes catalog only (no sidecar — Task 6 guarantees the AI-only delta doesn't sync).

- [ ] **Step 1: Write the failing test**

```swift
func testKeywordPromotionAddsUnconfirmedAndRespectsRemovals() throws {
    // Seed an asset + an .object signal {labels:["People"], confidence:0.9}. Promote.
    // keywords contains "People" AND aiUnconfirmedKeywords contains "People". No sidecar on disk.
    // Record removed_ai_labels(.keyword, "People"); re-promote; "People" is NOT re-added.
    // A signal with confidence 0.4 does not add its labels.
}
```

- [ ] **Step 2–5:** Fail → implement `promoteMetadataLabels` (per the interface, using `catalog.repository.evaluationSignals(assetID:)`, `objectLabels(from:)`, `removedAILabels(assetID:)`, and `updateMetadata`) → pass → commit `feat: keyword & caption promotion`.

Const: add `static let objectKeywordConfidenceFloor = 0.5` to `AppModel`.

### Task 8: Face promotion

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add `promoteFaceMatches(for:)`; reuse `FaceSuggestionBuilder` + `confirmedFaceEmbeddingsByPerson` (now origin-filtered) + `rejected_face_people`)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces: `func promoteFaceMatches(for assetID: AssetID) throws` — build match suggestions from confirmed centroids via `FaceSuggestionBuilder` (distance `1.23`); for each matched face NOT in `rejected_face_people` and NOT already assigned, call `repository.insertAIFace(...)`. No `person_assets` write; unmatched faces untouched.

- [ ] **Step 1: Write the failing test**

```swift
func testFacePromotionCreatesGuardedAIFacesRespectingRejections() throws {
    // Seed a confirmed person with faces; seed a new asset with a face near that centroid
    // and a second unmatched face. Promote.
    // - person_faces has an origin='ai' row for the matched face.
    // - no person_assets row exists.
    // - the unmatched face remains in unassignedFaceObservations.
    // Record rejected_face_people for the matched pair; re-promote; no ai row is (re)created.
}
```

- [ ] **Step 2–5:** Fail → implement → pass → commit `feat: face-match promotion (guarded, confirmed centroids, rejection-aware)`.

### Task 9: Wire promotion into the post-evaluation path

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (the code that runs after a `runEvaluation` result lands / after face observations are recorded — find where evaluation results are applied to the model)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `promoteMetadataLabels(for:)`, `promoteFaceMatches(for:)`.
- Produces: after an asset's evaluation/face-detection completes, both promotions run for that asset (bounded to it — no full-catalog scan).

- [ ] **Steps:** Write a test that drives an evaluation completion for one asset and asserts ✨ keywords + ai faces appear; run-fail; call both promoters at the post-eval hook; run-pass; commit `feat: run label/face promotion after evaluation`.

---

## Phase 5 — Confirm / remove gestures

### Task 10: Confirm / remove keywords & fields

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (new gesture methods)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  - `func confirmAIKeyword(_ keyword: String, for assetID: AssetID) throws` — remove from `aiUnconfirmedKeywords`; then the metadata is confirmed so the sidecar write path fires (Task 6 lets it sync now).
  - `func removeAIKeyword(_ keyword: String, for assetID: AssetID) throws` — drop from `keywords` + `aiUnconfirmedKeywords`; `recordRemovedAILabel(.keyword, keyword)`.
  - Analogous `confirmAIField(_:for:)` / `removeAIField(_:for:)` for `.caption`/`.flag`/`.rating`.

- [ ] **Steps:** failing test (confirm clears the set and writes the sidecar containing the keyword; remove drops it, records removal, writes no sidecar) → implement → pass → commit `feat: confirm/remove gestures for AI keywords & fields`.

### Task 11: Confirm / remove / reject faces

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`nameFace`/`rejectFaceSuggestion`/new confirm-remove); `Sources/TeststripApp/PhotoFacesSectionView.swift` if the presentation reads suggested vs confirmed
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  - `func confirmAIFace(assetID:faceIndex:) throws` → `repository.confirmFace(...)`.
  - `func removeAIFace(assetID:faceIndex:) throws` → delete `person_faces` row (+ `person_assets` reconciliation via existing `unassignFaces`).
  - "Not <name>": existing `rejectFaceSuggestion` path → delete + `recordRejectedFacePerson`. Ensure it now targets the persisted `origin='ai'` face row.
  - `PhotoFacesPresentation` derives `suggested` from `origin='ai'` `person_faces` (persisted) rather than in-memory `peopleFaceSuggestions`.

- [ ] **Steps:** failing tests (confirm → origin user + person_assets; remove → row gone; reject → rejection recorded) → implement → pass → commit `feat: confirm/remove/reject gestures for AI faces`.

---

## Phase 6 — Autopilot fold-in

### Task 12: Autopilot applies tentative flags/ratings; keyword proposals routed; undo repointed

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`runAutopilot` ~8429; remove/repurpose `commitAutopilotProposals` ~8579; `undoAutopilotRun` ~8677)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces: an autopilot run writes each `.pick`/`.reject` into `metadata.flag` (+ `.flag` in `aiUnconfirmedFields`) and each score into `metadata.rating` (+ `.rating`), skipping user-set/removed fields, recording a run-time metadata undo group; `.keyword` proposals go through `promoteMetadataLabels`-style append to `aiUnconfirmedKeywords`; `undoAutopilotRun` reverts the run-time group.

- [ ] **Steps:** failing test (run applies tentative flag with `.flag` unconfirmed; no sidecar; undo reverts) → implement → pass → commit `feat: autopilot applies tentative flags/ratings under provenance model`.

### Task 13: Tentative flags never drive destructive/committing operations

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` — `rejectRelocationScope` (~10664) confirmed-only; culling counts (~2574-2575) and undecided predicate (~6496) treat tentative flags as undecided; scope filters (~315-316) may keep showing them
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `aiUnconfirmedFields`.
- Produces: an asset whose only flag is a tentative AI `.reject` is excluded from the reject-relocation scope and is treated as undecided in counts.

- [ ] **Step 1: Write the failing test (safety-critical)**

```swift
func testTentativeAIRejectIsNotRelocatable() throws {
    // Seed asset with metadata.flag = .reject and aiUnconfirmedFields = [.flag].
    // rejectRelocationScope must NOT include it; moveRejectsToFolder must not touch it.
    // A confirmed .reject (aiUnconfirmedFields empty) IS included.
    // The tentative-reject asset counts as undecided.
}
```

- [ ] **Steps:** fail → implement the exclusions (add an `aiUnconfirmedFields.contains(.flag)` guard to each flag consumer; the reject-relocation scope query filters to confirmed rejects) → pass → commit `feat: tentative AI flags excluded from destructive/committing paths`.

---

## Phase 7 — UI, cleanup & docs

### Task 14: ✨ markers + confirm/remove affordances on unconfirmed tags

**Files:**
- Modify: `Sources/TeststripApp/InspectorView.swift` (keyword/caption chips), `Sources/TeststripApp/PhotoFacesSectionView.swift` (unconfirmed faces)
- Test: `Tests/TeststripAppTests/` (presentation tests)

**Interfaces:**
- Consumes: per-label `origin` (`aiUnconfirmedKeywords`/`aiUnconfirmedFields`; `person_faces.origin`).
- Produces: unconfirmed keyword/caption chips render a ✨ and offer confirm/remove; unconfirmed faces are visually distinguished (the prominent people treatment is sub-project 2 — here, minimal ✨ + confirm/remove).

- [ ] **Steps:** presentation test (a chip for an `aiUnconfirmedKeywords` member reports `isUnconfirmed == true`) → implement the presentation flag + view marker + confirm/remove buttons wired to Task 10/11 gestures → pass → commit `feat: ✨ markers and confirm/remove affordances for AI labels`.

### Task 15: Remove the inline suggestion pills

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`currentBatchKeywordSuggestionBar` ~1118-1159, its mount ~806, `BatchKeywordSuggestionPresentation`); `Sources/TeststripApp/AppModel.swift` (`batchKeywordSuggestions`, `acceptVisible/SelectedBatchKeywordSuggestion` and their call sites)
- Test: update/remove the corresponding tests

**Interfaces:**
- Produces: the inline "Suggestions" pill bar is gone; keyword suggestions now surface as ✨ auto-applied keywords (Task 7/14). The Batch Metadata popover (with its confirmation gate) is unaffected.

- [ ] **Steps:** delete the pill bar view + its presentation + the visible-scope accept path + their tests; run the suite; commit `refactor: remove inline batch-keyword suggestion pills (superseded by auto-applied ✨ keywords)`.

### Task 16: Invariant rewrite in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the "Non-negotiable invariants" → Confirm-before-write section)

- [ ] **Steps:** replace the "Confirm-before-write" bullet with the "Auto-apply with provenance" text from the spec's Invariant rewrite section, keeping the re-pointed negative assertions; commit `docs: rewrite confirm-before-write invariant to auto-apply-with-provenance`.

### Task 17: E2E scenario card (VM)

**Files:**
- Create: `test/scenarios/people-020-ai-label-provenance.md`

- [ ] **Steps:** author a scenario card per `test/scenarios/README.md` conventions: seed + evaluate photos; assert ✨ AI keywords appear, catalog rows have `origin='ai'`, no `.xmp` files exist, and no photo was relocated; confirm one keyword and assert `origin='user'` + the `.xmp` now carries it; run autopilot and assert a tentative AI reject does not relocate the original until confirmed; assert originals unchanged. (Card authored here; live VM run is a separate, human-triggered step via `script/vm_scenario_run.sh`.) Commit `test: scenario card for AI-label provenance & auto-apply`.

---

## Self-Review

**Spec coverage:** provenance flag (T1,T2,T3), `removed_ai_labels` (T1,T4), confirmed projection + sidecar layer (T2,T5,T6), import merge + no AI-only churn (T6), promotion keywords/caption/faces (T7,T8,T9), confirmed centroids + face-level unassigned + guarded insert (T3,T8), confirm/remove/reject (T10,T11), autopilot tentative + keyword routing + undo (T12), tentative-flags-never-destructive (T13), ✨ UI + remove pills (T14,T15), invariant rewrite (T16), E2E (T17). All spec sections map to a task.

**Type consistency:** `MetadataField` (`flag`/`caption`/`rating`/`keyword`) is defined in T2 and extended in T4; `aiUnconfirmedFields` only ever holds `flag`/`caption`/`rating`; `insertAIFace`/`confirmFace`/`confirmedProjection`/`removedAILabels`/`RemovedAILabel` names are used consistently across T3–T13.

**Note for the implementer:** T5, T6, T8, T11, T12, T13 modify large existing methods whose exact current signatures must be read before editing (anchors given). Match the project's timestamp/clock source rather than hand-rolling `Date()`, and follow the existing `database.execute`/`rows` binding conventions (all binds are `String`).
