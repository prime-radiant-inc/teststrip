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

    func testProbeTreatsCatalogRoundTripFingerprintAsOnline() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-catalog-round-trip")
        let originalURL = directory.appendingPathComponent("frame.jpg")
        try Data("image bytes".utf8).write(to: originalURL)
        let modificationDate = Date(timeIntervalSince1970: 1_783_024_454.8119888)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: originalURL.path)
        let fingerprint = try catalogRoundTrippedFingerprint(try fileFingerprint(for: originalURL))
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

    func testProbeMarksOriginalOnUnmountedVolumeOffline() {
        let volumeName = "TeststripOffline-\(UUID().uuidString)"
        let originalURL = URL(fileURLWithPath: "/Volumes/\(volumeName)/Job/frame.jpg")
        let asset = makeAsset(
            originalURL: originalURL,
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10))
        )

        let availability = SourceAvailabilityProbe().availability(for: asset)

        XCTAssertEqual(availability, .offline)
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

    func testRepositoryReconnectsSourceRootWhenRelativeFileFingerprintMatches() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-reconnect-root")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("2024/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("2024/frame.jpg")
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-match"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)

        let result = try repository.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.scannedAssetCount, 1)
        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(result.missingFileCount, 0)
        XCTAssertEqual(result.fingerprintMismatchCount, 0)
        let reconnected = try repository.asset(id: asset.id)
        XCTAssertEqual(reconnected.originalURL, newOriginalURL)
        XCTAssertEqual(reconnected.availability, .online)
        XCTAssertEqual(reconnected.metadata.rating, 4)
        XCTAssertEqual(try repository.catalogGeneration(assetID: asset.id), 1)
    }

    func testRepositoryReconnectRecordsNewSourceRootAfterFingerprintMatch() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-reconnect-root-history")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("2024/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-root-history"),
            originalURL: oldRoot.appendingPathComponent("2024/frame.jpg"),
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)

        _ = try repository.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(try repository.sourceRoots(), [
            CatalogSourceRoot(
                path: newRoot.standardizedFileURL.path,
                name: newRoot.lastPathComponent,
                assetCount: 1,
                unavailableAssetCount: 0
            )
        ])
    }

    func testRepositoryDoesNotReconnectSourceRootWhenCandidateFingerprintDiffers() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-reconnect-mismatch")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("2024/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("different original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("2024/frame.jpg")
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-mismatch"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .missing,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)

        let result = try repository.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.scannedAssetCount, 1)
        XCTAssertEqual(result.reconnectedAssetCount, 0)
        XCTAssertEqual(result.missingFileCount, 0)
        XCTAssertEqual(result.fingerprintMismatchCount, 1)
        let unchanged = try repository.asset(id: asset.id)
        XCTAssertEqual(unchanged.originalURL, oldOriginalURL)
        XCTAssertEqual(unchanged.availability, .missing)
    }

    func testRepositoryReconnectUpdatesMetadataSyncSidecarPath() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-reconnect-xmp")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("2024/frame.dng")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same raw bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("2024/frame.dng")
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-xmp"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.markMetadataSynced(
            assetID: asset.id,
            sidecarURL: oldOriginalURL.appendingPathExtension("xmp"),
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            fingerprint: "sidecar-fingerprint"
        )

        _ = try repository.reconnectSourceRoot(from: oldRoot, to: newRoot)

        let syncItem = try XCTUnwrap(repository.metadataSyncItem(assetID: asset.id))
        XCTAssertEqual(syncItem.sidecarURL, newOriginalURL.appendingPathExtension("xmp"))
        XCTAssertEqual(syncItem.lastSyncedFingerprint, "sidecar-fingerprint")
    }

    func testRepositoryReconnectUsesExistingAdobeStyleSidecarPath() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "source-reconnect-adobe-xmp")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("2024/frame.dng")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same raw bytes".utf8).write(to: newOriginalURL)
        let newSidecarURL = newOriginalURL.deletingPathExtension().appendingPathExtension("xmp")
        try Data("existing adobe-style sidecar".utf8).write(to: newSidecarURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("2024/frame.dng")
        let oldSidecarURL = oldOriginalURL.deletingPathExtension().appendingPathExtension("xmp")
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-adobe-xmp"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.markMetadataSynced(
            assetID: asset.id,
            sidecarURL: oldSidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            fingerprint: "sidecar-fingerprint"
        )

        _ = try repository.reconnectSourceRoot(from: oldRoot, to: newRoot)

        let syncItem = try XCTUnwrap(repository.metadataSyncItem(assetID: asset.id))
        XCTAssertEqual(syncItem.sidecarURL, newSidecarURL)
        XCTAssertEqual(syncItem.lastSyncedFingerprint, "sidecar-fingerprint")
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

    private func catalogRoundTrippedFingerprint(_ fingerprint: FileFingerprint) throws -> FileFingerprint {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(fingerprint)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(FileFingerprint.self, from: data)
    }
}
