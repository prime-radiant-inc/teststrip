import XCTest
@testable import TeststripCore

// "People over an import is who's in this shoot; People × All Photos is the
// global queue." Not one of the sixteen people/face reads accepted an asset
// scope before this change — these three now do, with nil meaning
// catalog-wide so every existing caller is unchanged.
final class ScopedPeopleQueryTests: XCTestCase {
    private let provenance = ProviderProvenance(
        provider: "face-recognition",
        model: "auraface-v1",
        version: "1",
        settingsHash: "default"
    )

    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func seedFace(_ repository: CatalogRepository, assetID: AssetID, embedding: [Double]) throws {
        try repository.replaceFaceObservations(
            assetID: assetID,
            provenance: provenance,
            with: [
                CatalogFaceObservation(
                    assetID: assetID,
                    faceIndex: 0,
                    boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    captureQuality: 0.9,
                    embedding: embedding,
                    provenance: provenance
                )
            ]
        )
    }

    private struct TestFaceObservationPayload: Codable {
        var boundingBox: FaceBoundingBox
        var captureQuality: Double?
        var embedding: [Double]
    }

    // Bypasses `replaceFaceObservations` to pin an exact `created_at`, the
    // same way `CatalogDatabaseTests.insertTestAsset` pins asset timestamps —
    // the public API always stamps the current wall clock.
    private func insertFaceObservation(
        _ database: CatalogDatabase,
        assetID: AssetID,
        createdAt: String,
        provenanceJSON: String
    ) throws {
        let payload = TestFaceObservationPayload(
            boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            captureQuality: 0.9,
            embedding: [0.1, 0.2, 0.3]
        )
        let faceJSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        try database.execute(
            """
            INSERT INTO face_observations (
                asset_id, face_index, face_json, provenance_json,
                provider, model, version, settings_hash, created_at, updated_at
            )
            VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                assetID.rawValue,
                faceJSON,
                provenanceJSON,
                provenance.provider,
                provenance.model,
                provenance.version,
                provenance.settingsHash,
                createdAt,
                createdAt
            ]
        )
    }

    func testPeopleScopedToASubsetOnlyReturnsPeoplePresentInIt() throws {
        let repository = try makeRepository(named: "scoped-people")
        let shootFrame = asset(path: "/Photos/Shoot/a.jpg")
        let otherFrame = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([shootFrame, otherFrame])
        try repository.upsertPerson(id: "person-shoot", name: "Ada")
        try repository.upsertPerson(id: "person-other", name: "Grace")
        try repository.assignAssets([shootFrame.id], toPersonID: "person-shoot")
        try repository.assignAssets([otherFrame.id], toPersonID: "person-other")

        let scoped = try repository.people(assetIDs: [shootFrame.id])

        XCTAssertEqual(scoped.map(\.id), ["person-shoot"])
        XCTAssertEqual(scoped.first?.assetCount, 1)
    }

    func testPeopleWithNilScopeIsUnchangedCatalogWideBehaviour() throws {
        let repository = try makeRepository(named: "scoped-people-nil")
        let first = asset(path: "/Photos/Shoot/a.jpg")
        let second = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([first, second])
        try repository.upsertPerson(id: "person-a", name: "Ada")
        try repository.assignAssets([first.id, second.id], toPersonID: "person-a")

        XCTAssertEqual(try repository.people(assetIDs: nil), try repository.people())
        XCTAssertEqual(try repository.people().first?.assetCount, 2)
    }

    func testPeopleScopedToAnEmptyScopeReturnsNobody() throws {
        let repository = try makeRepository(named: "scoped-people-empty")
        let frame = asset(path: "/Photos/Shoot/a.jpg")
        try repository.upsert(frame)
        try repository.upsertPerson(id: "person-a", name: "Ada")
        try repository.assignAssets([frame.id], toPersonID: "person-a")

        XCTAssertEqual(try repository.people(assetIDs: []), [])
    }

    func testUnassignedFaceObservationsHonourTheScope() throws {
        let repository = try makeRepository(named: "scoped-unassigned-faces")
        let shootFrame = asset(path: "/Photos/Shoot/a.jpg")
        let otherFrame = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([shootFrame, otherFrame])
        try seedFace(repository, assetID: shootFrame.id, embedding: [0.1, 0.2, 0.3])
        try seedFace(repository, assetID: otherFrame.id, embedding: [0.9, 0.8, 0.7])

        let scoped = try repository.unassignedFaceObservations(
            provenance: provenance,
            limit: 100,
            assetIDs: [shootFrame.id]
        )
        let global = try repository.unassignedFaceObservations(provenance: provenance, limit: 100)

        XCTAssertEqual(scoped.map(\.assetID), [shootFrame.id])
        XCTAssertEqual(Set(global.map(\.assetID)), Set([shootFrame.id, otherFrame.id]))
        XCTAssertEqual(try repository.unassignedFaceObservations(provenance: provenance, limit: 100, assetIDs: []), [])
    }

    // Pins distinct `created_at` values (rather than `seedFace`'s wall-clock
    // stamp) so the returned order actually exercises `created_at DESC` —
    // otherwise every row would tie and the assertion couldn't distinguish
    // the real comparator from a reversed one.
    func testScopedUnassignedFaceObservationsStillRespectTheLimit() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "scoped-unassigned-limit")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenanceJSON = String(data: try JSONEncoder().encode(provenance), encoding: .utf8)!

        var ids: [AssetID] = []
        for index in 0..<5 {
            let frame = asset(path: "/Photos/Shoot/\(index).jpg")
            try repository.upsert(frame)
            try insertFaceObservation(database, assetID: frame.id, createdAt: "\(1000 + index)", provenanceJSON: provenanceJSON)
            ids.append(frame.id)
        }

        let scoped = try repository.unassignedFaceObservations(provenance: provenance, limit: 2, assetIDs: ids)

        XCTAssertEqual(scoped.count, 2)
        XCTAssertEqual(scoped.map(\.assetID), [ids[4], ids[3]])
    }

    // Task 3 review: `unassignedFaceObservations` binds the *full* `limit` to
    // each chunk's own `LIMIT ?`, appends chunks in input order, and
    // truncates with `prefix(limit)` — so once a scope crosses the 500-id
    // chunk boundary, an earlier chunk that alone satisfies `limit` masks a
    // later chunk's newer rows entirely, rather than the merge picking the
    // true global-newest `limit` rows. This seeds 505 scoped assets — 500 in
    // the first chunk (older `created_at`) and 5 in the second chunk (the
    // globally newest `created_at`) — so the correct top 10 spans both
    // chunks while the current merge returns only the first chunk's top 10.
    func testUnassignedFaceObservationsAcrossChunksReturnGlobalNewestNotJustTheFirstChunk() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "scoped-unassigned-chunked")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let provenanceJSON = String(data: try JSONEncoder().encode(provenance), encoding: .utf8)!

        let firstChunkAssets = (0..<500).map { asset(path: "/Photos/Chunk1/\($0).jpg") }
        let secondChunkAssets = (0..<5).map { asset(path: "/Photos/Chunk2/\($0).jpg") }
        try repository.upsert(firstChunkAssets + secondChunkAssets)
        try database.transaction {
            for (index, frame) in firstChunkAssets.enumerated() {
                try insertFaceObservation(database, assetID: frame.id, createdAt: "\(1000 + index)", provenanceJSON: provenanceJSON)
            }
            for (index, frame) in secondChunkAssets.enumerated() {
                try insertFaceObservation(database, assetID: frame.id, createdAt: "\(2000 + index)", provenanceJSON: provenanceJSON)
            }
        }

        let scope = (firstChunkAssets + secondChunkAssets).map(\.id)
        let expectedNewestFirst = secondChunkAssets.reversed().map(\.id) + firstChunkAssets.suffix(5).reversed().map(\.id)

        let scoped = try repository.unassignedFaceObservations(provenance: provenance, limit: 10, assetIDs: scope)

        XCTAssertEqual(scoped.map(\.assetID), expectedNewestFirst)
    }

    func testFaceObservationAssetCountHonoursTheScope() throws {
        let repository = try makeRepository(named: "scoped-face-count")
        let shootFrame = asset(path: "/Photos/Shoot/a.jpg")
        let otherFrame = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([shootFrame, otherFrame])
        try seedFace(repository, assetID: shootFrame.id, embedding: [0.1, 0.2, 0.3])
        try seedFace(repository, assetID: otherFrame.id, embedding: [0.9, 0.8, 0.7])

        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance, assetIDs: [shootFrame.id]), 1)
        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance), 2)
        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance, assetIDs: []), 0)
    }
}
