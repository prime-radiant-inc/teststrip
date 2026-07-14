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
        let expected = RejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        XCTAssertTrue(all.contains(expected))
    }

    func testClearRejectedFacePersonRemovesIt() throws {
        let r = try repo()
        try r.recordRejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        try r.clearRejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        let all = try r.rejectedFacePeople()
        let cleared = RejectedFacePerson(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")
        XCTAssertFalse(all.contains(cleared))
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
