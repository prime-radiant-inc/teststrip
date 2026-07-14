import XCTest
@testable import TeststripCore

final class RejectedFacePeopleTests: XCTestCase {
    private func repo() throws -> (CatalogRepository, CatalogDatabase) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rfp-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url); try db.migrate()
        return (CatalogRepository(database: db), db)
    }

    func testRecordAndReadRejection() throws {
        let (r, _) = try repo()
        try r.recordRejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        let all = try r.rejectedFacePeople()
        let expected = RejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        XCTAssertTrue(all.contains(expected))
    }

    func testClearRejectedFacePersonRemovesIt() throws {
        let (r, _) = try repo()
        try r.recordRejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        try r.clearRejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        let all = try r.rejectedFacePeople()
        let cleared = RejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        XCTAssertFalse(all.contains(cleared))
    }

    func testUnassignFacesRemovesOnlyTargetedPersonFaces() throws {
        let (r, db) = try repo()
        try r.upsertPerson(id: "p1", name: "Ann")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)], toPersonID: "p1")
        try r.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 1)], toPersonID: "p1")
        try r.unassignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)])
        // unassignFaces mutates person_faces (not person_assets, which stays keyed
        // by asset since both faces belong to the same asset). Query person_faces
        // directly so this test actually exercises sibling-face survival: face 0
        // must be gone and face 1 must remain.
        let rows = try db.rows(
            "SELECT face_index FROM person_faces WHERE asset_id = ? ORDER BY face_index",
            bindings: ["a"]
        )
        let remainingFaceIndexes = rows.compactMap { $0["face_index"] }
        XCTAssertEqual(remainingFaceIndexes, ["1"])
    }
}
