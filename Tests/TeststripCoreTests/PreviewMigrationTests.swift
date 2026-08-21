import XCTest
@testable import TeststripCore

final class PreviewMigrationTests: XCTestCase {
    func testDeleteExistingJPEGPreviewsRemovesAllJPEGFiles() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "migration-delete-jpegs")
        let previewRoot = root.appendingPathComponent("previews", isDirectory: true)
        let assetDir = previewRoot.appendingPathComponent("asset-1", isDirectory: true)
        try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)

        let microJPG = assetDir.appendingPathComponent("micro.jpg")
        let gridJPG = assetDir.appendingPathComponent("grid.jpg")
        let largeJPG = assetDir.appendingPathComponent("large.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: microJPG)
        try Data([0xFF, 0xD8, 0xFF]).write(to: gridJPG)
        try Data([0xFF, 0xD8, 0xFF]).write(to: largeJPG)

        let cache = PreviewCache(root: previewRoot)
        try PreviewMigration.deleteExistingJPEGPreviews(in: cache)

        XCTAssertFalse(FileManager.default.fileExists(atPath: microJPG.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: gridJPG.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: largeJPG.path))
    }

    func testDeleteExistingJPEGPreviewsPreservesHEICFiles() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "migration-preserve-heic")
        let previewRoot = root.appendingPathComponent("previews", isDirectory: true)
        let assetDir = previewRoot.appendingPathComponent("asset-1", isDirectory: true)
        try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)

        let gridHEIC = assetDir.appendingPathComponent("grid.heic")
        let largeHEIC = assetDir.appendingPathComponent("large.heic")
        try Data([0x00, 0x00, 0x00]).write(to: gridHEIC)
        try Data([0x00, 0x00, 0x00]).write(to: largeHEIC)

        let cache = PreviewCache(root: previewRoot)
        try PreviewMigration.deleteExistingJPEGPreviews(in: cache)

        XCTAssertTrue(FileManager.default.fileExists(atPath: gridHEIC.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: largeHEIC.path))
    }

    func testResetPreviewGenerationQueueRequeuesOnePerPhysicalFile() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "migration-reset-queue")
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: root.appendingPathComponent("source.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)

        // Mark some levels as generated (old state)
        try repository.markPreviewGenerated(assetID: asset.id, level: .micro)
        try repository.markPreviewGenerated(assetID: asset.id, level: .grid)

        // Run the queue reset migration
        try PreviewMigration.resetPreviewGenerationQueue(repository: repository)

        // Should re-queue one item per physical file: .grid, .large, .original
        let pending = try repository.pendingPreviewGenerationItems()
        let assetPending = pending.filter { $0.assetID == asset.id }
        XCTAssertEqual(Set(assetPending.map(\.level)), Set([PreviewLevel.grid, .large, .original]))
    }

    func testResetPreviewGenerationQueueClearsExistingEntries() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "migration-clear-queue")
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: root.appendingPathComponent("source.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)

        // Queue old-style items with failure state
        try repository.recordPreviewGenerationPending([
            PreviewGenerationItem(assetID: asset.id, level: .micro),
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        try repository.recordPreviewGenerationFailure(
            assetID: asset.id, level: .micro, errorMessage: "old error"
        )

        // Run the queue reset migration
        try PreviewMigration.resetPreviewGenerationQueue(repository: repository)

        // Old .micro entry should be gone (not in the re-queued set)
        XCTAssertNil(try repository.previewGenerationQueueState(assetID: asset.id, level: .micro))
        // Re-queued items should have fresh state (no error)
        let gridState = try XCTUnwrap(repository.previewGenerationQueueState(assetID: asset.id, level: .grid))
        XCTAssertEqual(gridState.attemptCount, 0)
        XCTAssertNil(gridState.lastErrorMessage)
    }
}
