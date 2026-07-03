import XCTest
import TeststripCore

final class LibraryImportServiceTests: XCTestCase {
    func testAddFolderCatalogsSupportedImagesAndGeneratesMicroAndGridPreviews() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures, [])
        let asset = result.importedAssets[0]
        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.originalURL, image)
        for level in [PreviewLevel.micro, .grid] {
            let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: level))
            XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
            let dimensions = try PreviewRenderer().dimensions(of: previewURL)
            XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), level.maxPixelDimension!)
        }
    }

    func testAddFolderCanDeferPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-deferred-preview")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(
            root,
            repository: repository,
            previewPolicy: .deferGeneration
        )

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures, [])
        let asset = result.importedAssets[0]
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .micro),
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
    }

    func testAddFolderKeepsCatalogedAssetWhenPreviewRenderFails() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-preview-failure")
        let invalidImage = root.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: invalidImage)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures.count, 1)
        XCTAssertEqual(result.previewFailures[0].assetID, result.importedAssets[0].id)
        XCTAssertEqual(result.previewFailures[0].sourceURL, invalidImage)
        XCTAssertEqual(try repository.allAssets(limit: 10).map(\.originalURL), [invalidImage])
        let pendingItems = try repository.pendingPreviewGenerationItems()
        XCTAssertEqual(pendingItems.count, 2)
        XCTAssertTrue(pendingItems.contains(PreviewGenerationItem(
            assetID: result.importedAssets[0].id,
            level: .micro
        )))
        XCTAssertTrue(pendingItems.contains(PreviewGenerationItem(
            assetID: result.importedAssets[0].id,
            level: .grid
        )))
        let failureState = try XCTUnwrap(repository.previewGenerationQueueState(
            assetID: result.importedAssets[0].id,
            level: .micro
        ))
        XCTAssertEqual(failureState.attemptCount, 1)
        XCTAssertEqual(failureState.lastErrorMessage, result.previewFailures[0].message)
        XCTAssertNotNil(failureState.lastAttemptedAt)
        XCTAssertEqual(
            try repository.previewGenerationQueueState(assetID: result.importedAssets[0].id, level: .grid)?.attemptCount,
            0
        )
    }

    func testAddFolderReportsPreviewProgress() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-progress")
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("one.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("two.jpg"), width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately) { progress in
            recorder.append(progress)
        }

        XCTAssertEqual(result.importedAssets.count, 2)
        let updates = recorder.values()
        XCTAssertEqual(updates.map(\.completedUnitCount), [0, 1, 2, 0, 1, 2, 2, 0, 1, 2, 3, 4])
        XCTAssertEqual(updates.map(\.totalUnitCount), [nil, nil, nil, 2, 2, 2, 2, 4, 4, 4, 4, 4])
        XCTAssertEqual(updates.map(\.detail), [
            "Scanning library-import-progress",
            "Scanning library-import-progress: found 1 photo",
            "Scanning library-import-progress: found 2 photos",
            "Cataloging 2 photos",
            "Cataloging 1 of 2 photos",
            "Cataloging 2 of 2 photos",
            "Cataloged 2 photos",
            "Generating previews",
            "Generated 1 of 4 previews",
            "Generated 2 of 4 previews",
            "Generated 3 of 4 previews",
            "Generated 4 of 4 previews"
        ])
        XCTAssertEqual(updates.map(\.catalogedAssetIDs.count), [0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0])
        let catalogedUpdate = try XCTUnwrap(updates.first { !$0.catalogedAssetIDs.isEmpty })
        XCTAssertEqual(catalogedUpdate.catalogedAssetIDs, result.importedAssets.map(\.id))
        XCTAssertEqual(updates.last?.detail, "Generated 4 of 4 previews")
    }

    func testAddFolderReportsScanProgressBeforeCataloging() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-scan-progress")
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("one.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("two.jpg"), width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        _ = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration) { progress in
            recorder.append(progress)
        }

        let updates = recorder.values()
        let catalogingIndex = try XCTUnwrap(updates.firstIndex { $0.totalUnitCount == 2 })
        let scanUpdates = updates[..<catalogingIndex]
        XCTAssertEqual(scanUpdates.map(\.completedUnitCount), [0, 1, 2])
        XCTAssertEqual(scanUpdates.map(\.totalUnitCount), [nil, nil, nil])
    }

    func testAddFolderReportsPerFileCatalogingProgressBeforeFinalCatalogedUpdate() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-cataloging-progress")
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("one.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("two.jpg"), width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration) { progress in
            recorder.append(progress)
        }

        let catalogingUpdates = recorder.values().filter { $0.totalUnitCount == 2 }
        XCTAssertEqual(catalogingUpdates.map(\.detail), [
            "Cataloging 2 photos",
            "Cataloging 1 of 2 photos",
            "Cataloging 2 of 2 photos",
            "Cataloged 2 photos"
        ])
        XCTAssertEqual(catalogingUpdates.map(\.completedUnitCount), [0, 1, 2, 2])
        XCTAssertEqual(catalogingUpdates.map(\.catalogedAssetIDs.count), [0, 0, 0, 2])
        XCTAssertEqual(catalogingUpdates.last?.catalogedAssetIDs, result.importedAssets.map(\.id))
    }

    func testAddFolderCoalescesScanProgressForLargeFolders() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-coalesced-scan-progress")
        for index in 0..<250 {
            try Data("jpg-\(index)".utf8).write(to: root.appendingPathComponent("image-\(index).jpg"))
        }
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        _ = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration) { progress in
            recorder.append(progress)
        }

        let updates = recorder.values()
        let catalogingIndex = try XCTUnwrap(updates.firstIndex { $0.totalUnitCount == 250 })
        let scanUpdates = updates[..<catalogingIndex]
        XCTAssertEqual(scanUpdates.map(\.completedUnitCount), [0, 1, 100, 200, 250])
        XCTAssertEqual(scanUpdates.map(\.totalUnitCount), [nil, nil, nil, nil, nil])
    }

    func testCopyFromCardCopiesOriginalSidecarAndDefersPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-copy-card")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.jpg")
        try TestDirectories.writeTestJPEG(to: sourceFile, width: 1200, height: 800)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: sourceFile)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        let result = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            repository: repository,
            previewPolicy: .deferGeneration
        ) { progress in
            recorder.append(progress)
        }

        let destinationFile = destination.appendingPathComponent("IMG_0001.jpg")
        let destinationSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: destinationFile)
        let asset = try XCTUnwrap(result.importedAssets.first)
        XCTAssertEqual(result.importedAssets.map(\.originalURL), [destinationFile])
        XCTAssertEqual(try Data(contentsOf: sourceFile), try Data(contentsOf: destinationFile))
        XCTAssertEqual(try Data(contentsOf: sourceSidecar), sidecarData)
        XCTAssertEqual(try Data(contentsOf: destinationSidecar), sidecarData)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, metadata)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .micro),
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)).path))
        let details = recorder.values().map(\.detail)
        XCTAssertTrue(details.contains("Copying 1 photo to Library"))
        XCTAssertTrue(details.contains("Copied 1 photo to Library"))
    }

    func testCopyFromCardReportsPerFileCopyProgressBeforeFinalCatalogedUpdate() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-copy-progress")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: source.appendingPathComponent("IMG_0001.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: source.appendingPathComponent("IMG_0002.jpg"), width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        let result = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            repository: repository,
            previewPolicy: .deferGeneration
        ) { progress in
            recorder.append(progress)
        }

        let copyUpdates = recorder.values().filter { $0.totalUnitCount == 2 && $0.detail.contains("Library") }
        XCTAssertEqual(copyUpdates.map(\.detail), [
            "Copying 2 photos to Library",
            "Copying 1 of 2 photos to Library",
            "Copying 2 of 2 photos to Library",
            "Copied 2 photos to Library"
        ])
        XCTAssertEqual(copyUpdates.map(\.completedUnitCount), [0, 1, 2, 2])
        XCTAssertEqual(copyUpdates.map(\.catalogedAssetIDs.count), [0, 0, 0, 2])
        XCTAssertEqual(copyUpdates.last?.catalogedAssetIDs, result.importedAssets.map(\.id))
    }

    func testReimportPreservesAssetIdentityMetadataAndRefreshesPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-reimport")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let firstResult = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)
        let assetID = firstResult.importedAssets[0].id
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 4
            metadata.keywords = ["keeper"]
        }
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        try FileManager.default.removeItem(at: previewURL)
        try TestDirectories.writeTestJPEG(to: image, width: 640, height: 480)

        let secondResult = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)

        XCTAssertEqual(secondResult.importedAssets.map(\.id), [assetID])
        let fetched = try repository.asset(id: assetID)
        XCTAssertEqual(fetched.metadata.rating, 4)
        XCTAssertEqual(fetched.metadata.keywords, ["keeper"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
    }

    func testReimportUnchangedAssetWithCachedGridPreviewDoesNotQueuePreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-reimport-unchanged-preview")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewRoot = try TestDirectories.makeTemporaryDirectory(named: "library-import-reimport-unchanged-preview-cache")
        let previewCache = PreviewCache(root: previewRoot)
        let service = makeService(previewCache: previewCache)
        let firstResult = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)
        let assetID = firstResult.importedAssets[0].id
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])

        let secondResult = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration)

        XCTAssertEqual(secondResult.importedAssets.map(\.id), [assetID])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
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
            return try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)
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
