import XCTest
@testable import TeststripCore

// Issue #18: the People grid visibly reorders itself depending on whether a
// source is selected because the unscoped `people()` path sorts in SQL via
// `people.name COLLATE NOCASE ASC` (ASCII-only byte folding) while the scoped
// path re-sorts in Swift with `localizedCaseInsensitiveCompare` (locale-aware).
// For accented names the two collations disagree — same list, two orders.
//
// The names below are chosen so the collations provably disagree:
//   COLLATE NOCASE (byte order): Chelsea, César, Suzanne, Søren
//     — é (0xC3A9) > h (0x68) so "Chelsea" < "César";
//       ø (0xC3B8) > u (0x75) so "Suzanne" < "Søren".
//   localizedCaseInsensitiveCompare (base-letter order): César, Chelsea, Søren, Suzanne
//     — base "e" < "h" so "César" < "Chelsea";
//       base "o" < "u" so "Søren" < "Suzanne".
//
// The expected order is computed with the same comparator the fix uses, so the
// assertion is locale-independent yet still pins the collation to locale-aware.
final class PeopleSortConsistencyTests: XCTestCase {
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

    func testPeopleSortOrderIsIdenticalAcrossScopedAndUnscopedPaths() throws {
        let repository = try makeRepository(named: "people-sort-consistency")

        let names = ["César", "Chelsea", "Søren", "Suzanne"]
        var assets: [Asset] = []
        for (index, name) in names.enumerated() {
            let frame = asset(path: "/Photos/Shoot/\(index).jpg")
            assets.append(frame)
            try repository.upsert(frame)
            try repository.upsertPerson(id: "person-\(index)", name: name)
            try repository.assignAssets([frame.id], toPersonID: "person-\(index)")
        }

        // Expected order is the locale-aware sort — the collation the fix
        // applies on both paths. Computing it here (same comparator) keeps the
        // assertion locale-independent while still rejecting a NOCASE result.
        let expected = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let unscoped = try repository.people()
        let scoped = try repository.people(assetIDs: assets.map(\.id))

        XCTAssertEqual(unscoped.map(\.name), expected,
                      "Unscoped people() must use locale-aware sort, not ASCII NOCASE")
        XCTAssertEqual(scoped.map(\.name), expected,
                      "Scoped people() must use locale-aware sort")
        XCTAssertEqual(unscoped.map(\.name), scoped.map(\.name),
                      "Scoped and unscoped people() must produce identical order")
    }
}
