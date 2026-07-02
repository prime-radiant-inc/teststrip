import XCTest
import TeststripCore

final class LibraryImportServiceTests: XCTestCase {
    func testAddFolderCatalogsSupportedImagesAndGeneratesGridPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(root, repository: repository)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures, [])
        let asset = result.importedAssets[0]
        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.originalURL, image)
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        let dimensions = try PreviewRenderer().dimensions(of: previewURL)
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
    }

    func testAddFolderKeepsCatalogedAssetWhenPreviewRenderFails() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-preview-failure")
        let invalidImage = root.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: invalidImage)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(root, repository: repository)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures.count, 1)
        XCTAssertEqual(result.previewFailures[0].assetID, result.importedAssets[0].id)
        XCTAssertEqual(result.previewFailures[0].sourceURL, invalidImage)
        XCTAssertEqual(try repository.allAssets(limit: 10).map(\.originalURL), [invalidImage])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: result.importedAssets[0].id, level: .grid)
        ])
    }

    func testAddFolderReportsPreviewProgress() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-progress")
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("one.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("two.jpg"), width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        let result = try service.addFolderInPlace(root, repository: repository) { progress in
            recorder.append(progress)
        }

        XCTAssertEqual(result.importedAssets.count, 2)
        let updates = recorder.values()
        XCTAssertEqual(updates.map(\.completedUnitCount), [0, 0, 2, 0, 1, 2])
        XCTAssertEqual(updates.map(\.totalUnitCount), [nil, 2, 2, 2, 2, 2])
        XCTAssertEqual(updates.map(\.detail), [
            "Scanning library-import-progress",
            "Cataloging 2 photos",
            "Cataloged 2 photos",
            "Generating previews",
            "Generated 1 of 2 previews",
            "Generated 2 of 2 previews"
        ])
        XCTAssertEqual(updates.map(\.catalogedAssetIDs.count), [0, 0, 2, 0, 0, 0])
        XCTAssertEqual(updates[2].catalogedAssetIDs, result.importedAssets.map(\.id))
        XCTAssertEqual(updates.last?.detail, "Generated 2 of 2 previews")
    }

    func testReimportPreservesAssetIdentityMetadataAndRefreshesPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-reimport")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let firstResult = try service.addFolderInPlace(root, repository: repository)
        let assetID = firstResult.importedAssets[0].id
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 4
            metadata.keywords = ["keeper"]
        }
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        try FileManager.default.removeItem(at: previewURL)
        try TestDirectories.writeTestJPEG(to: image, width: 640, height: 480)

        let secondResult = try service.addFolderInPlace(root, repository: repository)

        XCTAssertEqual(secondResult.importedAssets.map(\.id), [assetID])
        let fetched = try repository.asset(id: assetID)
        XCTAssertEqual(fetched.metadata.rating, 4)
        XCTAssertEqual(fetched.metadata.keywords, ["keeper"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
    }

    func testResumePendingPreviewsGeneratesGridPreviewAndClearsQueue() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-resume-previews")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: image,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))

        let result = try service.resumePendingPreviews(repository: repository)

        XCTAssertEqual(result.generatedCount, 1)
        XCTAssertEqual(result.previewFailures, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testAddFolderStopsBeforeCatalogWritesWhenTaskIsCancelled() async throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-cancelled")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            let database = try CatalogDatabase.open(at: catalogURL)
            try database.migrate()
            let repository = CatalogRepository(database: database)
            return try service.addFolderInPlace(root, repository: repository)
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("cancelled import unexpectedly completed")
        } catch is CancellationError {
            let repository = try makeRepository(in: root)
            XCTAssertEqual(try repository.allAssets(limit: 10), [])
        }
    }

    private func makeRepository(in root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func makeService(previewCache: PreviewCache) -> LibraryImportService {
        LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"])),
            previewCache: previewCache,
            renderer: PreviewRenderer()
        )
    }
}

private final class ImportProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [LibraryImportProgress] = []

    func append(_ progress: LibraryImportProgress) {
        lock.withLock {
            updates.append(progress)
        }
    }

    func values() -> [LibraryImportProgress] {
        lock.withLock {
            updates
        }
    }
}
