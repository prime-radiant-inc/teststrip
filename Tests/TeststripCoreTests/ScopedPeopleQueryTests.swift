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
    }

    func testScopedUnassignedFaceObservationsStillRespectTheLimit() throws {
        let repository = try makeRepository(named: "scoped-unassigned-limit")
        var ids: [AssetID] = []
        for index in 0..<5 {
            let frame = asset(path: "/Photos/Shoot/\(index).jpg")
            try repository.upsert(frame)
            try seedFace(repository, assetID: frame.id, embedding: [Double(index), 0.2, 0.3])
            ids.append(frame.id)
        }

        let scoped = try repository.unassignedFaceObservations(provenance: provenance, limit: 2, assetIDs: ids)

        XCTAssertEqual(scoped.count, 2)
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
