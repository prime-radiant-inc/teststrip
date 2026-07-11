import XCTest
@testable import TeststripCore

// Jesse's ruling (2026-07-11): out-of-band sidecar edits after a clean sync
// must be detected — on catalog open and via Metadata ▸ Check Sidecars for
// Changes — and re-enter the existing planner flow (pending or conflict)
// instead of staying "synced" forever (activity-006 product gap).
final class SidecarRescanServiceTests: XCTestCase {
    func testOutOfBandSidecarEditRequeuesRowAsPending() throws {
        let fixture = try makeSyncedFixture(named: "rescan-pending")

        // Out-of-band edit: different metadata written directly to the
        // sidecar after the clean sync, mtime moved past the sync instant.
        let editedData = try XMPPacket(metadata: AssetMetadata(rating: 4)).xmlData()
        try editedData.write(to: fixture.sidecarURL)
        try Self.setModificationDate(Date().addingTimeInterval(60), at: fixture.sidecarURL)

        let summary = try SidecarRescanService().rescanSyncedSidecars(repository: fixture.repository)

        XCTAssertEqual(summary.checkedCount, 1)
        XCTAssertEqual(summary.pendingCount, 1)
        XCTAssertEqual(summary.conflictCount, 0)
        XCTAssertNotNil(try fixture.repository.pendingMetadataSyncItem(assetID: fixture.assetID))
        XCTAssertEqual(try fixture.repository.syncedMetadataSyncItems().count, 0)
    }

    func testSidecarAndCatalogBothChangedRecordsConflict() throws {
        let fixture = try makeSyncedFixture(named: "rescan-conflict")

        let editedData = try XMPPacket(metadata: AssetMetadata(rating: 4)).xmlData()
        try editedData.write(to: fixture.sidecarURL)
        try Self.setModificationDate(Date().addingTimeInterval(60), at: fixture.sidecarURL)
        // Catalog edit after the sync bumps the asset's generation.
        var changed = try fixture.repository.asset(id: fixture.assetID)
        changed.metadata.rating = 2
        try fixture.repository.upsert([changed])
        XCTAssertNotEqual(
            try fixture.repository.catalogGeneration(assetID: fixture.assetID),
            fixture.syncedGeneration
        )

        let summary = try SidecarRescanService().rescanSyncedSidecars(repository: fixture.repository)

        XCTAssertEqual(summary.conflictCount, 1)
        XCTAssertEqual(summary.pendingCount, 0)
        XCTAssertNotNil(try fixture.repository.metadataSyncConflictItem(assetID: fixture.assetID))
    }

    func testUntouchedSidecarIsSkippedByTheCheapGateAndStaysSynced() throws {
        let fixture = try makeSyncedFixture(named: "rescan-untouched")
        // Pin the mtime firmly before the recorded sync instant so the stat
        // gate proves it skipped without reading the file.
        try Self.setModificationDate(Date().addingTimeInterval(-3600), at: fixture.sidecarURL)

        let summary = try SidecarRescanService().rescanSyncedSidecars(repository: fixture.repository)

        XCTAssertEqual(summary, SidecarRescanSummary())
        XCTAssertEqual(try fixture.repository.syncedMetadataSyncItems().count, 1)
        XCTAssertNil(try fixture.repository.pendingMetadataSyncItem(assetID: fixture.assetID))
    }

    func testMissingSidecarRequeuesForRewrite() throws {
        let fixture = try makeSyncedFixture(named: "rescan-missing")
        try FileManager.default.removeItem(at: fixture.sidecarURL)

        let summary = try SidecarRescanService().rescanSyncedSidecars(repository: fixture.repository)

        XCTAssertEqual(summary.pendingCount, 1)
        XCTAssertNotNil(try fixture.repository.pendingMetadataSyncItem(assetID: fixture.assetID))
    }

    func testScopeFilterOnlyTouchesRequestedAssets() throws {
        let fixture = try makeSyncedFixture(named: "rescan-scope")
        let editedData = try XMPPacket(metadata: AssetMetadata(rating: 4)).xmlData()
        try editedData.write(to: fixture.sidecarURL)
        try Self.setModificationDate(Date().addingTimeInterval(60), at: fixture.sidecarURL)

        let summary = try SidecarRescanService().rescanSyncedSidecars(
            repository: fixture.repository,
            assetIDs: [AssetID(rawValue: "someone-else")]
        )

        XCTAssertEqual(summary, SidecarRescanSummary())
        XCTAssertEqual(try fixture.repository.syncedMetadataSyncItems().count, 1)
    }

    // MARK: - Fixtures

    private struct SyncedFixture {
        var repository: CatalogRepository
        var assetID: AssetID
        var sidecarURL: URL
        var syncedGeneration: Int
    }

    private func makeSyncedFixture(named name: String) throws -> SyncedFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-core-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let assetID = AssetID(rawValue: "\(name)-asset")
        let originalURL = directory.appendingPathComponent("photo.jpg")
        try Data("jpeg-bytes".utf8).write(to: originalURL)
        let metadata = AssetMetadata(rating: 3)
        try repository.upsert([Asset(
            id: assetID,
            originalURL: originalURL,
            volumeIdentifier: "vol",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata
        )])

        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sidecarURL)
        let generation = try repository.catalogGeneration(assetID: assetID)
        try repository.markMetadataSynced(
            assetID: assetID,
            sidecarURL: sidecarURL,
            catalogGeneration: generation,
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )
        // The clean-sync fixture must not trip the mtime gate on its own.
        try Self.setModificationDate(Date().addingTimeInterval(-3600), at: sidecarURL)
        return SyncedFixture(
            repository: repository,
            assetID: assetID,
            sidecarURL: sidecarURL,
            syncedGeneration: generation
        )
    }

    private static func setModificationDate(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
