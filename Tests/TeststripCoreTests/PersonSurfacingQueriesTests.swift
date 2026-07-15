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
