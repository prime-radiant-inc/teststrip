import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 2: CullRunTracker persistence lifecycle — the tracker saves to a
// JSON file after every mutation and resumes exactly on a fresh AppModel over
// the same catalog directory.
final class CullRunLifecycleTests: XCTestCase {
    func testTrackerPersistsAndResumesAcrossAppModelInstances() throws {
        let assets = (0..<4).map { index in
            Self.asset(id: "lifecycle-\(index)")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-cull-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appSupport = directory.appendingPathComponent("app-support", isDirectory: true)

        // First instance: start a cull session, record viewed + skipped.
        let (model1, repository) = try makeModelWithCatalogAssets(
            appSupport: appSupport,
            named: "lifecycle-first",
            assets: assets
        )
        try model1.beginCullingSession(named: "Batch")
        try model1.applyCullingShortcut(.nextPhoto)  // skip asset[0], land on asset[1]
        try model1.applyCullingShortcut(.nextPhoto)  // skip asset[1], land on asset[2]
        let savedViewed = model1.cullRunTracker.viewedAssetIDs
        let savedSkipped = model1.cullRunTracker.skippedAssetIDs
        XCTAssertFalse(savedViewed.isEmpty)
        XCTAssertFalse(savedSkipped.isEmpty)

        // The tracker JSON must exist in the catalog's app-support root.
        let trackerURL = appSupport
            .appendingPathComponent("Teststrip", isDirectory: true)
            .appendingPathComponent("cull-run-tracker.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trackerURL.path),
                      "tracker JSON should exist at \(trackerURL.path)")

        // Second instance: fresh AppModel over the same catalog directory.
        let (model2, _) = try makeModelWithCatalogAssets(
            appSupport: appSupport,
            named: "lifecycle-second",
            assets: assets
        )
        // Before resume, the fresh model's tracker is empty.
        XCTAssertTrue(model2.cullRunTracker.viewedAssetIDs.isEmpty)
        XCTAssertTrue(model2.cullRunTracker.skippedAssetIDs.isEmpty)

        model2.resumeCullRunIfNeeded()

        XCTAssertEqual(model2.cullRunTracker.viewedAssetIDs, savedViewed)
        XCTAssertEqual(model2.cullRunTracker.skippedAssetIDs, savedSkipped)
        _ = repository  // keep alive
    }

    func testResumeIsNoOpWhenNoTrackerFileExists() throws {
        let assets = (0..<2).map { index in
            Self.asset(id: "noresume-\(index)")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-cull-noresume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appSupport = directory.appendingPathComponent("app-support", isDirectory: true)

        let (model, _) = try makeModelWithCatalogAssets(
            appSupport: appSupport,
            named: "noresume",
            assets: assets
        )
        // No cull session started → no tracker file → resume is a no-op.
        model.resumeCullRunIfNeeded()

        XCTAssertTrue(model.cullRunTracker.viewedAssetIDs.isEmpty)
        XCTAssertTrue(model.cullRunTracker.skippedAssetIDs.isEmpty)
    }

    // MARK: - Fixtures

    private static func asset(id: String) -> Asset {
        var metadata = AssetMetadata()
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata
        )
    }

    private func makeModelWithCatalogAssets(
        appSupport: URL,
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = appSupport
            .deletingLastPathComponent()
            .appendingPathComponent("teststrip-catalog-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: appSupport),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        return (try AppModel.load(catalog: catalog), repository)
    }
}
