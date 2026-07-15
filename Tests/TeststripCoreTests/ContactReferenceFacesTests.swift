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
