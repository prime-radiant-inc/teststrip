import XCTest
@testable import TeststripCore

final class SourceAvailabilityTests: XCTestCase {
    func testProbeMarksMatchingOriginalOnline() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-online")
        let originalURL = directory.appendingPathComponent("frame.jpg")
        try Data("image bytes".utf8).write(to: originalURL)
        let fingerprint = try fileFingerprint(for: originalURL)
        let asset = makeAsset(originalURL: originalURL, fingerprint: fingerprint)

        let availability = SourceAvailabilityProbe().availability(for: asset)

        XCTAssertEqual(availability, .online)
    }

    func testProbeMarksChangedOriginalStale() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-stale")
        let originalURL = directory.appendingPathComponent("frame.jpg")
        try Data("new image bytes".utf8).write(to: originalURL)
        let oldFingerprint = FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1))
        let asset = makeAsset(originalURL: originalURL, fingerprint: oldFingerprint)

        let availability = SourceAvailabilityProbe().availability(for: asset)

        XCTAssertEqual(availability, .stale)
    }

    func testProbeMarksAbsentOriginalMissing() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-missing")
        let originalURL = directory.appendingPathComponent("missing.jpg")
        let asset = makeAsset(
            originalURL: originalURL,
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10))
        )

        let availability = SourceAvailabilityProbe().availability(for: asset)

        XCTAssertEqual(availability, .missing)
    }

    func testRepositoryUpdatesAvailabilityWithoutIncrementingCatalogGeneration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-availability-repository")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(
            originalURL: directory.appendingPathComponent("missing.jpg"),
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10))
        )
        try repository.upsert(asset)

        try repository.updateAvailability(assetID: asset.id, availability: .missing)

        XCTAssertEqual(try repository.asset(id: asset.id).availability, .missing)
        XCTAssertEqual(try repository.catalogGeneration(assetID: asset.id), 1)
    }

    private func makeAsset(originalURL: URL, fingerprint: FileFingerprint) -> Asset {
        Asset(
            id: AssetID(rawValue: "source-asset"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: fingerprint,
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func fileFingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }
}
