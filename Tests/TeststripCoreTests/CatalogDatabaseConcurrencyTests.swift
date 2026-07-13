import XCTest
@testable import TeststripCore

final class CatalogDatabaseConcurrencyTests: XCTestCase {
    func testConcurrentTransactionsSerializeWithoutCorruption() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cat-\(UUID().uuidString).sqlite")
        let db = try CatalogDatabase.open(at: url)
        try db.execute("CREATE TABLE t (v INTEGER)")
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            try? db.transaction { try db.execute("INSERT INTO t (v) VALUES (1)") }
        }
        let rows = try db.rows("SELECT COUNT(*) AS c FROM t")
        XCTAssertEqual(rows.first?["c"], "200")
    }
}
