import XCTest
@testable import TeststripCore

final class WorkerCommandExecutorTests: XCTestCase {
    func testGeneratePreviewCommandRendersRequestedPreviewFromCatalogAsset() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-command-executor")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: source),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.generatePreview(assetID: asset.id, level: .medium))

        XCTAssertEqual(result, .completed("generated medium preview for source.jpg"))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        let dimensions = try PreviewRenderer().dimensions(of: previewURL)
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.medium.maxPixelDimension!)
    }

    func testGeneratePreviewCommandRendersOriginalLevelAtFullResolution() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-command-executor-original")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: source),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .original))
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.generatePreview(assetID: asset.id, level: .original))

        XCTAssertEqual(result, .completed("generated original preview for source.jpg"))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .original))
        let dimensions = try PreviewRenderer().dimensions(of: previewURL)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 1600, height: 1000))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testGeneratePreviewCommandClearsPendingPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-preview-queue-clear")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: source),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )

        _ = try executor.execute(.generatePreview(assetID: asset.id, level: .grid))

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testGeneratePreviewCommandRecordsFailureStateWhenRenderFails() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-preview-queue-failure")
        let source = root.appendingPathComponent("source.jpg")
        try Data("not an image".utf8).write(to: source)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: source),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )

        XCTAssertThrowsError(try executor.execute(.generatePreview(assetID: asset.id, level: .grid)))

        let failureState = try XCTUnwrap(repository.previewGenerationQueueState(assetID: asset.id, level: .grid))
        XCTAssertEqual(failureState.attemptCount, 1)
        XCTAssertNotNil(failureState.lastErrorMessage)
        XCTAssertNotNil(failureState.lastAttemptedAt)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
    }

    func testGeneratePreviewCommandMarksOfflineOriginalWithoutBurningPreviewAttempt() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-preview-offline-source")
        let source = URL(fileURLWithPath: "/Volumes/TeststripOffline-\(UUID().uuidString)/Job/source.jpg")
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "offline-volume",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )

        XCTAssertThrowsError(try executor.execute(.generatePreview(assetID: asset.id, level: .grid)))

        XCTAssertEqual(try repository.asset(id: asset.id).availability, .offline)
        let state = try XCTUnwrap(repository.previewGenerationQueueState(assetID: asset.id, level: .grid))
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastAttemptedAt)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
    }

    func testGeneratePreviewCommandMarksMissingOriginalWithoutBurningPreviewAttempt() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-preview-missing-source")
        let source = root.appendingPathComponent("missing-source.jpg")
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )

        XCTAssertThrowsError(try executor.execute(.generatePreview(assetID: asset.id, level: .grid)))

        XCTAssertEqual(try repository.asset(id: asset.id).availability, .missing)
        let state = try XCTUnwrap(repository.previewGenerationQueueState(assetID: asset.id, level: .grid))
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastAttemptedAt)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
    }

    func testGeneratePreviewCommandMarksStaleOriginalWithoutClearingPendingPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-preview-stale-source")
        let source = root.appendingPathComponent("stale-source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        XCTAssertThrowsError(try executor.execute(.generatePreview(assetID: asset.id, level: .grid)))

        XCTAssertEqual(try repository.asset(id: asset.id).availability, .stale)
        let state = try XCTUnwrap(repository.previewGenerationQueueState(assetID: asset.id, level: .grid))
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastAttemptedAt)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewCache.url(
            for: PreviewCacheKey(assetID: asset.id, level: .grid)
        ).path))
    }

    func testRefreshAvailabilityCommandUpdatesCatalogSourceState() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-refresh-availability")
        let source = root.appendingPathComponent("source.jpg")
        try Data("original".utf8).write(to: source)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try FileManager.default.removeItem(at: source)
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )

        let result = try executor.execute(.refreshAvailability(assetID: asset.id))

        XCTAssertEqual(result, .completed("source missing for source.jpg"))
        XCTAssertEqual(try repository.asset(id: asset.id).availability, .missing)
    }

    func testRefreshAvailabilityBatchCommandUpdatesCatalogAndReportsProgress() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-refresh-availability-batch")
        let onlineSource = root.appendingPathComponent("online.jpg")
        let missingSource = root.appendingPathComponent("missing.jpg")
        try Data("online".utf8).write(to: onlineSource)
        try Data("missing".utf8).write(to: missingSource)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let onlineAsset = Asset(
            id: AssetID(rawValue: "online"),
            originalURL: onlineSource,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: onlineSource),
            availability: .missing,
            metadata: AssetMetadata()
        )
        let missingAsset = Asset(
            id: AssetID(rawValue: "missing"),
            originalURL: missingSource,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: missingSource),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert([onlineAsset, missingAsset])
        try FileManager.default.removeItem(at: missingSource)
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )
        let recorder = ImportProgressRecorder()

        let result = try executor.execute(
            .refreshAvailabilityBatch(assetIDs: [onlineAsset.id, missingAsset.id]),
            progress: recorder.append
        )

        XCTAssertEqual(result, .completed("checked 2 sources"))
        XCTAssertEqual(try repository.asset(id: onlineAsset.id).availability, .online)
        XCTAssertEqual(try repository.asset(id: missingAsset.id).availability, .missing)
        XCTAssertEqual(recorder.values(), [
            LibraryImportProgress(completedUnitCount: 1, totalUnitCount: 2, detail: "Checked 1 of 2 sources"),
            LibraryImportProgress(completedUnitCount: 2, totalUnitCount: 2, detail: "Checked 2 of 2 sources")
        ])
    }

    func testImportFolderCommandCatalogsAssetsAndDefersPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-folder")
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importFolder(root: sourceRoot))

        let imported = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.map(\.originalURL), [source])
        XCTAssertEqual(result, .completedImport(
            "imported 1 photo from photos",
            importedAssetIDs: [asset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        ))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .micro),
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)).path))
    }

    func testImportFolderCommandCatalogsRecognizedUnsupportedRawWithoutPreviewWork() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-folder-catalog-only-raw")
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("foveon.X3F")
        try Data("catalog-only raw bytes".utf8).write(to: source)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importFolder(root: sourceRoot))

        let imported = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.map(\.originalURL), [source])
        XCTAssertEqual(result, .completedImport(
            "imported 1 photo from photos",
            importedAssetIDs: [asset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        ))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testImportFolderCommandReportsExistingAssetsOnReimport() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-folder-reimport")
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)
        let firstResult = try executor.execute(.importFolder(root: sourceRoot))
        guard case .completedImport(_, let importedAssetIDs, 1, 0, 0, []) = firstResult else {
            XCTFail("expected first import to report one new asset")
            return
        }

        let secondResult = try executor.execute(.importFolder(root: sourceRoot))

        XCTAssertEqual(secondResult, .completedImport(
            "imported 1 photo from photos",
            importedAssetIDs: importedAssetIDs,
            newAssetCount: 0,
            existingAssetCount: 1,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        ))
    }

    func testImportFolderCommandReportsSkippedSourceFileCount() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-folder-skipped-source")
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let survivor = sourceRoot.appendingPathComponent("one.jpg")
        let disappearing = sourceRoot.appendingPathComponent("two.jpg")
        try TestDirectories.writeTestJPEG(to: survivor, width: 1600, height: 1000)
        try TestDirectories.writeTestJPEG(to: disappearing, width: 1000, height: 1600)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importFolder(root: sourceRoot)) { progress in
            if progress.detail == "Cataloging 2 photos" {
                try? FileManager.default.removeItem(at: disappearing)
            }
        }

        let imported = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.map(\.originalURL), [survivor])
        guard case .completedImport(
            "imported 1 photo from photos",
            [asset.id],
            1,
            0,
            1,
            let skippedSourceFiles
        ) = result else {
            XCTFail("expected completed import with skipped source details")
            return
        }
        XCTAssertEqual(skippedSourceFiles.count, 1)
        XCTAssertEqual(skippedSourceFiles[0].sourceURL, disappearing)
        XCTAssertTrue(skippedSourceFiles[0].message.contains("could not fingerprint"))
    }

    func testImportFolderCommandReportsProgress() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-folder-progress")
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: sourceRoot.appendingPathComponent("source.jpg"), width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)
        let recorder = ImportProgressRecorder()

        _ = try executor.execute(.importFolder(root: sourceRoot), progress: recorder.append)

        let updates = recorder.values()
        XCTAssertTrue(updates.contains(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: nil,
            detail: "Scanning photos"
        )))
        XCTAssertTrue(updates.contains { progress in
            progress.detail == "Cataloged 1 photo" &&
                progress.completedUnitCount == 1 &&
                progress.totalUnitCount == 1 &&
                progress.catalogedAssetIDs.count == 1
        })
    }

    func testImportCardCommandCopiesAssetsAndDefersPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-card")
        let sourceRoot = root.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: source)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importCard(
            source: sourceRoot,
            destinationRoot: destinationRoot,
            destinationPolicy: .flat,
            secondCopyDestination: nil
        ))

        let destination = destinationRoot.appendingPathComponent("source.jpg")
        let imported = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.map(\.originalURL), [destination])
        XCTAssertEqual(result, .completedImport(
            "imported 1 photo from DCIM to Library",
            importedAssetIDs: [asset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        ))
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, metadata)
        XCTAssertEqual(try Data(contentsOf: XMPSidecarStore().sidecarURL(forOriginalAt: destination)), sidecarData)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .micro),
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)).path))
    }

    func testImportCardCommandHonorsDatedFoldersAndReportsSecondCopyFailures() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-card-dated")
        let sourceRoot = root.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Library", isDirectory: true)
        let secondCopyRoot = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let backupDatedFolder = secondCopyRoot
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDatedFolder, withIntermediateDirectories: true)
        let conflictingBackup = backupDatedFolder.appendingPathComponent("source.jpg")
        try Data("existing".utf8).write(to: conflictingBackup)
        let source = sourceRoot.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        // Local midday keeps the expected folder name timezone-independent:
        // modification dates file under the local calendar day.
        try FileManager.default.setAttributes(
            [.modificationDate: try XCTUnwrap(FolderImportTests.localDate(2025, 1, 3, 12, 0, 0))],
            ofItemAtPath: source.path
        )
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importCard(
            source: sourceRoot,
            destinationRoot: destinationRoot,
            destinationPolicy: .capturedDate,
            secondCopyDestination: secondCopyRoot
        ))

        let destination = destinationRoot
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
            .appendingPathComponent("source.jpg")
        XCTAssertEqual(try repository.allAssets(limit: 10).map(\.originalURL), [destination])
        guard case .completedImport(_, _, _, _, let skippedSourceFileCount, let skippedSourceFiles) = result else {
            return XCTFail("expected completedImport result, got \(result)")
        }
        XCTAssertEqual(skippedSourceFileCount, 0, "a photo imported with a failed backup is not a skipped file")
        XCTAssertEqual(skippedSourceFiles.map(\.sourceURL), [source])
        XCTAssertEqual(skippedSourceFiles.map(\.kind), [.backupFailed])
        let message = try XCTUnwrap(skippedSourceFiles.first?.message)
        XCTAssertTrue(
            message.hasPrefix("backup copy failed: "),
            "expected honest backup failure message, got \(message)"
        )
        XCTAssertEqual(try String(contentsOf: conflictingBackup, encoding: .utf8), "existing")
    }

    func testSyncMetadataCommandWritesMissingSidecarFromCatalogMetadata() throws {
        let setup = try makeMetadataSyncSetup(named: "worker-sync-write", metadata: AssetMetadata(rating: 4, flag: .pick))

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("synced metadata for asset.raw"))
        let sidecarData = try Data(contentsOf: setup.sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, setup.asset.metadata)
        XCTAssertEqual(
            try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
    }

    func testSyncMetadataCommandReportsFilenameWhenSidecarIsUpToDate() throws {
        let setup = try makeMetadataSyncSetup(named: "worker-sync-up-to-date", metadata: AssetMetadata(rating: 4))
        let write = try XMPSidecarStore().write(metadata: setup.asset.metadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: write.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: write.fingerprint
        )

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata up to date for asset.raw"))
    }

    func testSyncMetadataCommandClearsPendingRowWhenMatchingSidecarIsAlreadyWritten() throws {
        let setup = try makeMetadataSyncSetup(named: "worker-sync-up-to-date-pending", metadata: AssetMetadata(rating: 5))
        let write = try XMPSidecarStore().write(metadata: setup.asset.metadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: setup.asset.id,
            sidecarURL: write.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            lastSyncedFingerprint: write.fingerprint
        ))

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata up to date for asset.raw"))
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id),
            write.fingerprint
        )
    }

    func testSyncMetadataCommandRecordsPendingWhenSidecarCannotBeWritten() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-sync-pending")
        let originalURL = root
            .appendingPathComponent("offline", isDirectory: true)
            .appendingPathComponent("asset.raw")
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: originalURL,
            volumeIdentifier: "offline-volume",
            fingerprint: FileFingerprint(size: 14, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .missing,
            metadata: AssetMetadata(rating: 4, flag: .pick)
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)
        let catalogGeneration = try repository.catalogGeneration(assetID: asset.id)

        let result = try executor.execute(.syncMetadata(assetID: asset.id))

        XCTAssertEqual(result, .completed("metadata pending for asset.raw"))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [
            MetadataSyncItem(
                assetID: asset.id,
                sidecarURL: originalURL.appendingPathExtension("xmp"),
                catalogGeneration: catalogGeneration,
                lastSyncedFingerprint: nil
            )
        ])
    }

    func testSyncMetadataCommandImportsExternallyChangedSidecarWhenCatalogIsUnchanged() throws {
        let catalogMetadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-import", metadata: catalogMetadata)
        let initialWrite = try XMPSidecarStore().write(metadata: catalogMetadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["external"])
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("imported metadata for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, sidecarMetadata)
        let currentSidecarData = try Data(contentsOf: setup.sidecarURL)
        XCTAssertEqual(
            try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id),
            XMPSidecarStore.fingerprint(for: currentSidecarData)
        )
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
    }

    func testSyncMetadataCommandImportsExistingAdobeStyleSidecarWhenCatalogIsUnchanged() throws {
        let catalogMetadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-import-adobe-style", metadata: catalogMetadata)
        let sidecarURL = setup.asset.originalURL.deletingPathExtension().appendingPathExtension("xmp")
        let initialData = try XMPPacket(metadata: catalogMetadata).xmlData()
        try initialData.write(to: sidecarURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: XMPSidecarStore.fingerprint(for: initialData)
        )
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["external"])
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("imported metadata for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, sidecarMetadata)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.sidecarURL.path))
        XCTAssertEqual(try setup.repository.metadataSyncItem(assetID: setup.asset.id)?.sidecarURL, sidecarURL)
    }

    func testSyncMetadataCommandRefreshesNewerSidecarCheckpointWhenContentsMatch() throws {
        let metadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-newer-sidecar-checkpoint", metadata: metadata)
        let initialWrite = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        let initialSync = try XCTUnwrap(try setup.repository.metadataSyncItem(assetID: setup.asset.id)?.lastSyncedAt)
        Thread.sleep(forTimeInterval: 0.01)
        let newerModificationDate = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: newerModificationDate],
            ofItemAtPath: setup.sidecarURL.path
        )

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("imported metadata for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, metadata)
        let refreshedSync = try XCTUnwrap(try setup.repository.metadataSyncItem(assetID: setup.asset.id)?.lastSyncedAt)
        XCTAssertGreaterThan(refreshedSync.timeIntervalSince1970, initialSync.timeIntervalSince1970)
    }

    func testSyncMetadataCommandRecordsConflictWhenCatalogAndSidecarBothChanged() throws {
        let initialMetadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-conflict", metadata: initialMetadata)
        let initialWrite = try XMPSidecarStore().write(metadata: initialMetadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        try setup.repository.updateMetadata(assetID: setup.asset.id) { metadata in
            metadata.rating = 4
        }
        let sidecarMetadata = AssetMetadata(rating: 5)
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata.rating, 4)
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: setup.sidecarURL)).metadata, sidecarMetadata)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
    }

    func testSyncMetadataCommandWritesPendingCatalogEditOverOlderUncheckpointedSidecar() throws {
        let catalogMetadata = AssetMetadata(rating: 4, flag: .pick, keywords: ["catalog"])
        let setup = try makeMetadataSyncSetup(named: "worker-sync-pending-writes-older-sidecar", metadata: catalogMetadata)
        let originalData = try Data(contentsOf: setup.asset.originalURL)
        let sidecarMetadata = AssetMetadata(rating: 1, keywords: ["old-sidecar"])
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: setup.sidecarURL.path
        )
        try setup.repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: setup.asset.id,
            sidecarURL: setup.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            lastSyncedFingerprint: nil
        ))

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("synced metadata for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, catalogMetadata)
        let sidecarData = try Data(contentsOf: setup.sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, catalogMetadata)
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems(), [])
        XCTAssertEqual(
            try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(try Data(contentsOf: setup.asset.originalURL), originalData)
    }

    func testSyncMetadataCommandConflictsPendingCatalogEditWithNewerUncheckpointedSidecar() throws {
        let catalogMetadata = AssetMetadata(rating: 4, keywords: ["catalog"])
        let setup = try makeMetadataSyncSetup(named: "worker-sync-pending-conflicts-newer-sidecar", metadata: catalogMetadata)
        let originalData = try Data(contentsOf: setup.asset.originalURL)
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["new-sidecar"])
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: setup.sidecarURL.path
        )
        try setup.repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: setup.asset.id,
            sidecarURL: setup.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            lastSyncedFingerprint: nil
        ))
        Thread.sleep(forTimeInterval: 0.01)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: setup.sidecarURL.path
        )

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, catalogMetadata)
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: setup.sidecarURL)).metadata, sidecarMetadata)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
        XCTAssertEqual(try Data(contentsOf: setup.asset.originalURL), originalData)
    }

    func testSyncMetadataCommandRecordsConflictWhenPendingWriteHitsUnparsableSidecar() throws {
        let catalogMetadata = AssetMetadata(rating: 4, keywords: ["catalog"])
        let setup = try makeMetadataSyncSetup(named: "worker-sync-pending-unparsable-sidecar", metadata: catalogMetadata)
        let foreignSidecarData = Data("""
        <xmpmeta xmlns="https://teststrip.app/xmp">
          <rating>2</rating>
        </xmpmeta>
        """.utf8)
        try foreignSidecarData.write(to: setup.sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: setup.sidecarURL.path
        )
        try setup.repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: setup.asset.id,
            sidecarURL: setup.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            lastSyncedFingerprint: nil
        ))

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, catalogMetadata)
        XCTAssertEqual(try Data(contentsOf: setup.sidecarURL), foreignSidecarData)
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
    }

    func testSyncMetadataCommandRecordsConflictWhenUnparsableSidecarCannotBeImported() throws {
        let catalogMetadata = AssetMetadata(rating: 4, keywords: ["catalog"])
        let setup = try makeMetadataSyncSetup(named: "worker-sync-import-unparsable-sidecar", metadata: catalogMetadata)
        let foreignSidecarData = Data("""
        <xmpmeta xmlns="https://teststrip.app/xmp">
          <rating>2</rating>
        </xmpmeta>
        """.utf8)
        try foreignSidecarData.write(to: setup.sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, catalogMetadata)
        XCTAssertEqual(try Data(contentsOf: setup.sidecarURL), foreignSidecarData)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
    }

    func testSyncMetadataCommandPreservesConflictWhenUnreadableSidecarBecomesParsable() throws {
        let catalogMetadata = AssetMetadata(rating: 4, keywords: ["catalog"])
        let setup = try makeMetadataSyncSetup(named: "worker-sync-conflict-sidecar-becomes-parsable", metadata: catalogMetadata)
        let foreignSidecarData = Data("""
        <xmpmeta xmlns="https://teststrip.app/xmp">
          <rating>2</rating>
        </xmpmeta>
        """.utf8)
        try foreignSidecarData.write(to: setup.sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: setup.sidecarURL.path
        )
        try setup.repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: setup.asset.id,
            sidecarURL: setup.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            lastSyncedFingerprint: nil
        ))
        XCTAssertEqual(
            try setup.executor.execute(.syncMetadata(assetID: setup.asset.id)),
            .completed("metadata conflict for asset.raw")
        )
        // An external tool later re-saves the sidecar as valid XMP carrying its
        // stale metadata; a routine sync check must not import it over the
        // user's pending catalog edit without offering the conflict choice.
        try XMPPacket(metadata: AssetMetadata(rating: 2)).xmlData().write(to: setup.sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, catalogMetadata)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
        XCTAssertNil(try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id))
    }

    func testSyncMetadataCommandPreservesRecordedConflictAcrossSubsequentSyncChecks() throws {
        let initialMetadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-conflict-repeat-check", metadata: initialMetadata)
        let initialWrite = try XMPSidecarStore().write(metadata: initialMetadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        try setup.repository.updateMetadata(assetID: setup.asset.id) { metadata in
            metadata.rating = 4
        }
        let sidecarMetadata = AssetMetadata(rating: 5)
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)
        XCTAssertEqual(
            try setup.executor.execute(.syncMetadata(assetID: setup.asset.id)),
            .completed("metadata conflict for asset.raw")
        )

        // Selecting the photo again re-runs the sync check; the recorded
        // conflict must survive instead of being auto-resolved by importing
        // the sidecar over the user's catalog edit.
        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset.raw"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata.rating, 4)
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: setup.sidecarURL)).metadata, sidecarMetadata)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
    }

    func testUnreadableSidecarConflictGuardSkipsConflictWhenSnapshotIsStale() throws {
        let setup = try makeMetadataSyncSetup(named: "worker-sync-torn-sidecar-read", metadata: AssetMetadata(rating: 4))
        // A Finder/SMB copy or non-atomic saver can be mid-write when the
        // sync check snapshots the sidecar: the snapshot fails to parse, but
        // the file on disk finishes and parses fine moments later. The guard
        // must not record a durable conflict from the torn snapshot.
        let tornSnapshot = Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf".utf8)
        try XMPPacket(metadata: AssetMetadata(rating: 2)).xmlData().write(to: setup.sidecarURL)

        let result = try setup.executor.recordConflictForUnreadableSidecar(
            assetID: setup.asset.id,
            assetName: "asset.raw",
            sidecarURL: setup.sidecarURL,
            sidecarData: tornSnapshot,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id)
        )

        XCTAssertNil(result)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems(), [])
    }

    func testUnreadableSidecarConflictGuardSkipsConflictWhileSidecarIsStillChanging() throws {
        let setup = try makeMetadataSyncSetup(named: "worker-sync-changing-sidecar-read", metadata: AssetMetadata(rating: 4))
        let tornSnapshot = Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf".utf8)
        try Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xml".utf8).write(to: setup.sidecarURL)

        let result = try setup.executor.recordConflictForUnreadableSidecar(
            assetID: setup.asset.id,
            assetName: "asset.raw",
            sidecarURL: setup.sidecarURL,
            sidecarData: tornSnapshot,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id)
        )

        XCTAssertNil(result)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems(), [])
    }

    func testRunEvaluationPersistsSignalsFromNamedProviderUsingCachedPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-evaluation")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cached preview".utf8).write(to: previewURL)
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: previewCache,
            evaluationProviders: [PreviewPathEvaluationProvider(name: "local")]
        )

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "local"))

        XCTAssertEqual(result, .completed("evaluated source.jpg with local"))
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id), [
            EvaluationSignal(
                assetID: asset.id,
                kind: .aesthetics,
                value: .text(previewURL.path),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: "local", model: "preview-path", version: "1", settingsHash: "default")
            )
        ])
    }

    func testRunEvaluationPersistsAndReplacesFaceObservationsFromFaceProviders() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-face-observations")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let provenance = ProviderProvenance(provider: "stub-faces", model: "stub", version: "1", settingsHash: "default")
        let twoFaces = [
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.9,
                embedding: [1, 0],
                provenance: provenance
            ),
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 1,
                boundingBox: FaceBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                captureQuality: nil,
                embedding: [0, 1],
                provenance: provenance
            )
        ]

        let firstExecutor = WorkerCommandExecutor(
            repository: repository,
            previewCache: previewCache,
            evaluationProviders: [StubFaceEvaluationProvider(
                name: "stub-faces",
                faceProvenance: provenance,
                outcome: FaceEvaluationOutcome(signals: [], faceObservations: twoFaces)
            )]
        )
        _ = try firstExecutor.execute(.runEvaluation(assetID: asset.id, provider: "stub-faces"))

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), twoFaces)

        let secondExecutor = WorkerCommandExecutor(
            repository: repository,
            previewCache: previewCache,
            evaluationProviders: [StubFaceEvaluationProvider(
                name: "stub-faces",
                faceProvenance: provenance,
                outcome: FaceEvaluationOutcome(signals: [], faceObservations: [twoFaces[0]])
            )]
        )
        _ = try secondExecutor.execute(.runEvaluation(assetID: asset.id, provider: "stub-faces"))

        XCTAssertEqual(try repository.faceObservations(assetID: asset.id), [twoFaces[0]])
    }

    func testRuntimeConfigurationRegistersLocalImageMetricsProvider() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-evaluation")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root
        ))

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "local-image-metrics"))

        XCTAssertEqual(result, .completed("evaluated source.jpg with local-image-metrics"))
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id).map(\.kind), [
            .exposure,
            .colorPalette,
            .focus,
            .motionBlur,
            .framing,
            .aesthetics
        ])
    }

    func testRuntimeConfigurationRegistersAppleVisionProvider() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-apple-vision")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root
        ))

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "apple-vision"))

        XCTAssertEqual(result, .completed("evaluated source.jpg with apple-vision"))
    }

    func testRuntimeConfigurationRegistersFaceExpressionProvider() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-face-expression")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root
        ))

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "core-image-faces"))

        XCTAssertEqual(result, .completed("evaluated source.jpg with core-image-faces"))
        // The faceless test JPEG must record no expression signals rather than fake reads.
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id), [])
    }

    func testRuntimeConfigurationRegistersLocalHTTPModelProviderWhenConfigured() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-local-http-model")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let transport = RecordingLocalHTTPModelTransport(response: .success(LocalHTTPModelHTTPResponse(
            statusCode: 200,
            data: try chatCompletionData(content: """
            {"signals":[{"kind":"aesthetics","label":"portfolio","confidence":0.71}]}
            """)
        )))
        let executor = try WorkerCommandExecutor(
            configuration: WorkerRuntimeConfiguration(
                catalogURL: catalogURL,
                previewCacheRoot: previewCache.root,
                localHTTPModel: LocalHTTPModelProviderConfiguration(
                    endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
                    model: "llava",
                    timeout: 6
                )
            ),
            localHTTPModelTransport: transport
        )

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "local-http-model"))

        XCTAssertEqual(result, .completed("evaluated source.jpg with local-http-model"))
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id), [
            EvaluationSignal(
                assetID: asset.id,
                kind: .aesthetics,
                value: .label("portfolio"),
                confidence: 0.71,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            )
        ])
        let request = try XCTUnwrap(transport.requests().first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(request.timeoutInterval, 6)
    }

    func testLocalHTTPModelProviderAcceptsFencedJSONContent() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "local-http-model-fenced-json")
        let previewURL = root.appendingPathComponent("preview.jpg")
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let transport = RecordingLocalHTTPModelTransport(response: .success(LocalHTTPModelHTTPResponse(
            statusCode: 200,
            data: try chatCompletionData(content: """
            ```json
            {"signals":[{"kind":"focus","score":0.91,"confidence":0.82}]}
            ```
            """)
        )))
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            transport: transport
        )

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        XCTAssertEqual(signals, [
            EvaluationSignal(
                assetID: AssetID(rawValue: "asset-1"),
                kind: .focus,
                value: .score(0.91),
                confidence: 0.82,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            )
        ])
    }

    func testRuntimeConfigurationParsesOptionalLocalHTTPModelArguments() throws {
        let configuration = try WorkerRuntimeConfiguration(arguments: [
            "--catalog",
            "/tmp/catalog.sqlite",
            "--preview-cache",
            "/tmp/previews",
            "--local-http-model-endpoint",
            "http://localhost:1234/v1/chat/completions",
            "--local-http-model",
            "llava",
            "--local-http-model-timeout",
            "6"
        ])

        XCTAssertEqual(configuration.localHTTPModel, LocalHTTPModelProviderConfiguration(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            timeout: 6
        ))
    }

    private func makeMetadataSyncSetup(
        named name: String,
        metadata: AssetMetadata
    ) throws -> (
        repository: CatalogRepository,
        executor: WorkerCommandExecutor,
        asset: Asset,
        sidecarURL: URL
    ) {
        let root = try TestDirectories.makeTemporaryDirectory(named: name)
        let originalURL = root.appendingPathComponent("asset.raw")
        try Data("original bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: originalURL,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 14, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: metadata
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        return (
            repository: repository,
            executor: WorkerCommandExecutor(repository: repository, previewCache: previewCache),
            asset: asset,
            sidecarURL: originalURL.appendingPathExtension("xmp")
        )
    }
}

private struct PreviewPathEvaluationProvider: EvaluationProvider {
    var name: String

    func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        [
            EvaluationSignal(
                assetID: assetID,
                kind: .aesthetics,
                value: .text(previewURL.path),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: name, model: "preview-path", version: "1", settingsHash: "default")
            )
        ]
    }
}

private struct StubFaceEvaluationProvider: FaceObservationEvaluationProvider {
    var name: String
    var faceProvenance: ProviderProvenance
    var outcome: FaceEvaluationOutcome

    func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        outcome.signals
    }

    func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome {
        outcome
    }
}

private final class RecordingLocalHTTPModelTransport: LocalHTTPModelTransport, @unchecked Sendable {
    private let response: Result<LocalHTTPModelHTTPResponse, Error>
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    init(response: Result<LocalHTTPModelHTTPResponse, Error>) {
        self.response = response
    }

    func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
        return try response.get()
    }

    func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

private final class ImportProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [LibraryImportProgress] = []

    func append(_ progress: LibraryImportProgress) {
        lock.lock()
        updates.append(progress)
        lock.unlock()
    }

    func values() -> [LibraryImportProgress] {
        lock.lock()
        defer { lock.unlock() }
        return updates
    }
}

private func fileFingerprint(for url: URL) throws -> FileFingerprint {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return FileFingerprint(
        size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
        modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
    )
}

private func chatCompletionData(content: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "choices": [
            [
                "message": [
                    "content": content
                ]
            ]
        ]
    ])
}
