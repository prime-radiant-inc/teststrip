import XCTest
@testable import TeststripCore

/// Covers `personFaces(assetID:)`: maps one photo's `person_faces` rows
/// (face index -> person + origin) straight off the table, scoped to that
/// asset. Task 11 widened this from confirmed-only to carry `origin` too,
/// since `person_faces` now also holds provisional `'ai'` rows (Task 8) that
/// the per-photo People inspector must tell apart from confirmed `'user'`
/// ones.
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

        let assignments = try r.personFaces(assetID: AssetID(rawValue: "a"))
        XCTAssertEqual(assignments, [
            0: PersonFaceAssignment(personID: "p1", origin: "user"),
            2: PersonFaceAssignment(personID: "p2", origin: "user")
        ])
    }

    func testReadsAIOriginFaceForAsset() throws {
        let (r, _) = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        try r.insertAIFace(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")

        let assignments = try r.personFaces(assetID: AssetID(rawValue: "a"))
        XCTAssertEqual(assignments, [0: PersonFaceAssignment(personID: "p1", origin: "ai")])
    }

    func testReturnsEmptyForAssetWithNoConfirmedFaces() throws {
        let (r, _) = try repo()
        let assignments = try r.personFaces(assetID: AssetID(rawValue: "a"))
        XCTAssertTrue(assignments.isEmpty)
    }
}
