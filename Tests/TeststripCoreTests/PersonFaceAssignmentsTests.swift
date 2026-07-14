import XCTest
@testable import TeststripCore

/// Covers Task 7's new repo read: `personFaceAssignments(assetID:)` maps one
/// photo's confirmed faces (face index -> person id) straight off
/// `person_faces`, scoped to that asset.
final class PersonFaceAssignmentsTests: XCTestCase {
    private func repo() throws -> (CatalogRepository, CatalogDatabase) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pfa-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url); try db.migrate()
        return (CatalogRepository(database: db), db)
    }

    func testReadsConfirmedFaceIndexesForAsset() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        try r.upsertPerson(id: "p2", name: "Beau")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)], toPersonID: "p1")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 2)], toPersonID: "p2")
        // A different asset's confirmed face must not leak into this read.
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "b"), faceIndex: 0)], toPersonID: "p1")

        let assignments = try r.personFaceAssignments(assetID: AssetID(rawValue: "a"))
        XCTAssertEqual(assignments, [0: "p1", 2: "p2"])
    }

    func testReturnsEmptyForAssetWithNoConfirmedFaces() throws {
        let (r, _) = try repo()
        let assignments = try r.personFaceAssignments(assetID: AssetID(rawValue: "a"))
        XCTAssertTrue(assignments.isEmpty)
    }
}
