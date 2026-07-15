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

    // Regression: mergePerson deleted the source `people` row but left
    // contact_reference_faces.person_id pointing at the dead source id. A
    // regenerated suggestion for the dead id could then pass the
    // `contactReferenceFace(personID:) != nil` confirm gate and
    // upsertPerson-resurrect the merged-away person, silently undoing the
    // merge. The fix re-keys the reference to the target instead of
    // orphaning it. Pre-fix, this test fails: contactReferenceEmbeddingsByPerson()
    // would still key the embedding under "contact:C1", and
    // contactReferenceFace(personID: "contact:C1") would still be non-nil.
    func testMergePersonReKeysContactReferenceToTarget() throws {
        let (r, _) = try repo()
        try r.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                         embedding: [0.1, 0.2], boundingBox: box(), photoHash: "h1")
        try r.upsertPerson(id: "contact:C1", name: "Dan Shapiro")
        try r.upsertPerson(id: "person-other", name: "Someone Else")

        try r.mergePerson(sourceID: "contact:C1", into: "person-other")

        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson(), ["person-other": [[0.1, 0.2]]])
        XCTAssertNil(try r.contactReferenceFace(personID: "contact:C1"))
        XCTAssertEqual(try r.contactReferenceFace(personID: "person-other")?.name, "Dan Shapiro")
    }
}
