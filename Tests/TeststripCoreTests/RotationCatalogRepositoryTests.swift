import XCTest
@testable import TeststripCore

final class RotationCatalogRepositoryTests: XCTestCase {
    func testRotationDecodesAsNilForOldCatalogs() throws {
        let json = """
        {"pixelWidth":4000,"pixelHeight":3000,"provenance":{"provider":"test","model":"","version":"","settingsHash":""}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AssetTechnicalMetadata.self, from: json)
        XCTAssertNil(decoded.rotation)
    }

    func testRotationEncodesAndDecodes() throws {
        let meta = AssetTechnicalMetadata(
            pixelWidth: 4000, pixelHeight: 3000,
            provenance: ProviderProvenance(provider: "test", model: "", version: "", settingsHash: "")
        )
        var withRotation = meta
        withRotation.rotation = 90
        let encoded = try JSONEncoder().encode(withRotation)
        let decoded = try JSONDecoder().decode(AssetTechnicalMetadata.self, from: encoded)
        XCTAssertEqual(decoded.rotation, 90)
    }

    func testUpdateRotationWritesToCatalog() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "rotation-write")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repo = CatalogRepository(database: database)
        let assetID = AssetID(rawValue: "test-asset")
        try repo.upsert(
            Asset(
                id: assetID,
                originalURL: URL(fileURLWithPath: "/tmp/test.jpg"),
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: 1, modificationDate: Date()),
                availability: .online,
                metadata: AssetMetadata(),
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 4000, pixelHeight: 3000,
                    provenance: ProviderProvenance(provider: "test", model: "", version: "", settingsHash: "")
                )
            )
        )
        try repo.updateRotation(assetID: assetID, rotation: 90)
        let asset = try repo.asset(id: assetID)
        XCTAssertEqual(asset.technicalMetadata?.rotation, 90)
    }

    func testUpdateRotationToZeroClearsRotation() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "rotation-clear")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repo = CatalogRepository(database: database)
        let assetID = AssetID(rawValue: "test-asset")
        try repo.upsert(
            Asset(
                id: assetID,
                originalURL: URL(fileURLWithPath: "/tmp/test.jpg"),
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: 1, modificationDate: Date()),
                availability: .online,
                metadata: AssetMetadata(),
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 4000, pixelHeight: 3000,
                    provenance: ProviderProvenance(provider: "test", model: "", version: "", settingsHash: "")
                )
            )
        )
        try repo.updateRotation(assetID: assetID, rotation: 90)
        try repo.updateRotation(assetID: assetID, rotation: 0)
        let asset = try repo.asset(id: assetID)
        XCTAssertEqual(asset.technicalMetadata?.rotation, 0)
    }
}
