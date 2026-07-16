import XCTest
@testable import TeststripCore

final class CatalogBondingTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    func testSetBondRecordsPrimaryAndSecondary() throws {
        let repository = try makeRepository(named: "bonding-set")
        try repository.upsert(asset(id: "raw", path: "/photos/IMG_1.CR3"))
        try repository.upsert(asset(id: "jpg", path: "/photos/IMG_1.JPG"))

        try repository.setBond(secondaryID: AssetID(rawValue: "jpg"), primaryID: AssetID(rawValue: "raw"))

        XCTAssertEqual(try repository.bondedPrimaryID(of: AssetID(rawValue: "jpg")), AssetID(rawValue: "raw"))
        XCTAssertNil(try repository.bondedPrimaryID(of: AssetID(rawValue: "raw")))
        XCTAssertEqual(try repository.bondedSecondaryIDs(of: AssetID(rawValue: "raw")), [AssetID(rawValue: "jpg")])
        XCTAssertEqual(try repository.assetIDsWithBondedSecondaries(), [AssetID(rawValue: "raw")])
    }

    func testClearingBondRemovesPrimary() throws {
        let repository = try makeRepository(named: "bonding-clear")
        try repository.upsert(asset(id: "raw", path: "/photos/IMG_1.CR3"))
        try repository.upsert(asset(id: "jpg", path: "/photos/IMG_1.JPG"))
        try repository.setBond(secondaryID: AssetID(rawValue: "jpg"), primaryID: AssetID(rawValue: "raw"))

        try repository.setBond(secondaryID: AssetID(rawValue: "jpg"), primaryID: nil)

        XCTAssertNil(try repository.bondedPrimaryID(of: AssetID(rawValue: "jpg")))
    }
}
