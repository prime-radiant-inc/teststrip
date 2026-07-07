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

    func testAddFolderCatalogsRecognizedUnsupportedRawWithoutPreviewWork() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-catalog-only-raw")
        let catalogOnlyRaw = root.appendingPathComponent("foveon.X3F")
        try Data("catalog-only raw bytes".utf8).write(to: catalogOnlyRaw)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = LibraryImportService(
            ingestService: IngestService(
                scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions),
                decodeRegistry: DecodeRegistry(providers: [ImageIODecodeProvider()])
            ),
            previewCache: previewCache
        )

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration)

        XCTAssertEqual(result.importedAssets.map(\.originalURL), [catalogOnlyRaw])
        let asset = try XCTUnwrap(result.importedAssets.first)
        XCTAssertEqual(try repository.asset(id: asset.id).originalURL, catalogOnlyRaw)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testAddFolderRecordsCatalogSourceRoot() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-source-root")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        _ = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration)

        XCTAssertEqual(try repository.sourceRoots(), [
            CatalogSourceRoot(
                path: root.standardizedFileURL.path,
                name: root.lastPathComponent,
                assetCount: 1,
                unavailableAssetCount: 0
            )
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

    func testCatalogsMetadataOnlyDecodeProviderAssetWithoutQueuingPreviews() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-metadata-only")
        let image = root.appendingPathComponent("one.metadataonly")
        try Data("metadata-only raw bytes".utf8).write(to: image)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = LibraryImportService(
            ingestService: IngestService(
                scanner: FolderScanner(supportedExtensions: ["metadataonly"]),
                decodeRegistry: DecodeRegistry(providers: [MetadataOnlyDecodeProvider()])
            ),
            previewCache: previewCache
        )

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .generateImmediately)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures, [])
        let asset = try repository.asset(id: result.importedAssets[0].id)
        XCTAssertEqual(asset.technicalMetadata?.pixelWidth, 6000)
        XCTAssertEqual(asset.technicalMetadata?.pixelHeight, 4000)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testAddFolderContinuesWhenOneSourceDisappearsBeforeCataloging() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-disappearing-source")
        let photoFolder = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let survivor = photoFolder.appendingPathComponent("one.jpg")
        let disappearing = photoFolder.appendingPathComponent("two.jpg")
        try TestDirectories.writeTestJPEG(to: survivor, width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: disappearing, width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(photoFolder, repository: repository, previewPolicy: .deferGeneration) { progress in
            if progress.detail == "Cataloging 2 photos" {
                try? FileManager.default.removeItem(at: disappearing)
            }
        }

        XCTAssertEqual(result.importedAssets.map(\.originalURL), [survivor])
        XCTAssertEqual(result.skippedSourceFiles.count, 1)
        XCTAssertEqual(result.skippedSourceFiles[0].sourceURL, disappearing)
        XCTAssertTrue(result.skippedSourceFiles[0].message.contains("could not fingerprint"))
        XCTAssertEqual(try repository.allAssets(limit: 10).map(\.originalURL), [survivor])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: result.importedAssets[0].id, level: .micro),
            PreviewGenerationItem(assetID: result.importedAssets[0].id, level: .grid)
        ])
    }

    func testAddFolderReportsNonCatalogableFilesAsSkipped() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-non-catalogable")
        let photoFolder = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let video = photoFolder.appendingPathComponent("clip.mov")
        try Data("mov".utf8).write(to: video)
        let stray = photoFolder.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: stray)
        let sidecarData = try XMPPacket(metadata: AssetMetadata(rating: 3)).xmlData()
        try sidecarData.write(to: photoFolder.appendingPathComponent("one.jpg.xmp"))
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(photoFolder, repository: repository, previewPolicy: .deferGeneration)

        XCTAssertEqual(result.importedAssets.map(\.originalURL), [image])
        XCTAssertEqual(result.skippedSourceFileCount, 2)
        XCTAssertEqual(result.skippedSourceFiles, [
            LibrarySkippedSourceFile(sourceURL: video, message: "video file not supported"),
            LibrarySkippedSourceFile(sourceURL: stray, message: "file type not supported")
        ])
    }

    func testCopyFromCardReportsNonCatalogableFilesAsSkippedWithoutCopyingThem() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-card-non-catalogable")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let image = source.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let video = source.appendingPathComponent("clip.mp4")
        try Data("mp4".utf8).write(to: video)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            repository: repository,
            previewPolicy: .deferGeneration
        )

        XCTAssertEqual(result.importedAssets.map(\.originalURL), [destination.appendingPathComponent("one.jpg")])
        XCTAssertEqual(result.skippedSourceFileCount, 1)
        XCTAssertEqual(result.skippedSourceFiles, [
            LibrarySkippedSourceFile(sourceURL: video, message: "video file not supported")
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("clip.mp4").path))
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
        XCTAssertEqual(updates.map(\.catalogedAssetIDs.count), [0, 0, 0, 0, 1, 1, 2, 0, 0, 0, 0, 0])
        let finalCatalogedUpdate = try XCTUnwrap(updates.last { !$0.catalogedAssetIDs.isEmpty })
        XCTAssertEqual(finalCatalogedUpdate.catalogedAssetIDs, result.importedAssets.map(\.id))
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
        XCTAssertEqual(catalogingUpdates.map(\.catalogedAssetIDs.count), [0, 1, 1, 2])
        XCTAssertEqual(catalogingUpdates.last?.catalogedAssetIDs, result.importedAssets.map(\.id))
    }

    func testAddFolderCatalogsFirstAssetBeforeFinalImportCompletion() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-early-catalog")
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("one.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: root.appendingPathComponent("two.jpg"), width: 800, height: 1200)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let recorder = EarlyCatalogProgressRecorder(
            repository: repository,
            targetDetail: "Cataloging 1 of 2 photos"
        )

        let result = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration, progress: recorder.append)
        let snapshot = recorder.snapshot()

        XCTAssertEqual(snapshot.catalogedAssetIDs, [result.importedAssets[0].id])
        XCTAssertTrue(snapshot.assetWasReadable)
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
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
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
        XCTAssertEqual(try repository.sourceRoots(), [
            CatalogSourceRoot(
                path: destination.standardizedFileURL.path,
                name: destination.lastPathComponent,
                assetCount: 1,
                unavailableAssetCount: 0
            )
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
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
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
        XCTAssertEqual(copyUpdates.map(\.catalogedAssetIDs.count), [0, 1, 1, 2])
        XCTAssertEqual(copyUpdates.last?.catalogedAssetIDs, result.importedAssets.map(\.id))
    }

    func testCopyFromCardOrganizesIntoDatedFoldersWhenPolicyIsCapturedDate() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-copy-dated")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.jpg")
        try TestDirectories.writeTestJPEG(to: sourceFile, width: 1200, height: 800)
        try FileManager.default.setAttributes(
            [.modificationDate: FolderImportTests.utcDate(2025, 1, 3, 10, 30, 0)],
            ofItemAtPath: sourceFile.path
        )
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            destinationPolicy: .capturedDate,
            repository: repository,
            previewPolicy: .deferGeneration
        )

        let destinationFile = destination
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
            .appendingPathComponent("IMG_0001.jpg")
        XCTAssertEqual(result.importedAssets.map(\.originalURL), [destinationFile])
        XCTAssertEqual(try Data(contentsOf: sourceFile), try Data(contentsOf: destinationFile))
    }

    func testCopyFromCardReportsDatedFolderNameCollisionAsSkipAndImportsRemainingFiles() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-copy-dated-collision")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        let firstDirectory = source.appendingPathComponent("100CANON", isDirectory: true)
        let secondDirectory = source.appendingPathComponent("101CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let firstFile = firstDirectory.appendingPathComponent("IMG_0001.jpg")
        let collidingFile = secondDirectory.appendingPathComponent("IMG_0001.jpg")
        let laterFile = secondDirectory.appendingPathComponent("IMG_0002.jpg")
        try Data("first".utf8).write(to: firstFile)
        try Data("second".utf8).write(to: collidingFile)
        try Data("third".utf8).write(to: laterFile)
        let captureInstant = FolderImportTests.utcDate(2025, 1, 3, 12, 0, 0)
        for file in [firstFile, collidingFile, laterFile] {
            try FileManager.default.setAttributes([.modificationDate: captureInstant], ofItemAtPath: file.path)
        }
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            destinationPolicy: .capturedDate,
            repository: repository,
            previewPolicy: .deferGeneration
        )

        XCTAssertEqual(
            result.importedAssets.map(\.originalURL.lastPathComponent),
            ["IMG_0001.jpg", "IMG_0002.jpg"],
            "files before and after the collision must still be imported"
        )
        XCTAssertEqual(try repository.allAssets(limit: 10).count, 2)
        let importedByName = Dictionary(uniqueKeysWithValues: result.importedAssets.map { ($0.originalURL.lastPathComponent, $0.originalURL) })
        XCTAssertEqual(try String(contentsOf: importedByName["IMG_0001.jpg"]!, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: importedByName["IMG_0002.jpg"]!, encoding: .utf8), "third")
        XCTAssertEqual(result.skippedSourceFiles.map(\.sourceURL), [collidingFile])
        XCTAssertEqual(result.skippedSourceFileCount, 1)
        let message = try XCTUnwrap(result.skippedSourceFiles.first?.message)
        XCTAssertTrue(
            message.contains("ingest destination already exists"),
            "expected destination-collision skip message, got \(message)"
        )
        XCTAssertEqual(try String(contentsOf: collidingFile, encoding: .utf8), "second")
    }

    func testCopyFromCardWritesSecondCopyAndReportsBackupFailuresWithoutFailingImport() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-copy-second")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        let secondCopy = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: source.appendingPathComponent("IMG_0001.jpg"), width: 1200, height: 800)
        try TestDirectories.writeTestJPEG(to: source.appendingPathComponent("IMG_0002.jpg"), width: 800, height: 1200)
        let conflictingBackup = secondCopy.appendingPathComponent("IMG_0002.jpg")
        try Data("existing".utf8).write(to: conflictingBackup)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            secondCopyDestination: secondCopy,
            repository: repository,
            previewPolicy: .deferGeneration
        )

        XCTAssertEqual(
            result.importedAssets.map(\.originalURL),
            [
                destination.appendingPathComponent("IMG_0001.jpg"),
                destination.appendingPathComponent("IMG_0002.jpg")
            ]
        )
        XCTAssertEqual(
            try Data(contentsOf: source.appendingPathComponent("IMG_0001.jpg")),
            try Data(contentsOf: secondCopy.appendingPathComponent("IMG_0001.jpg"))
        )
        XCTAssertEqual(try String(contentsOf: conflictingBackup, encoding: .utf8), "existing")
        XCTAssertEqual(result.skippedSourceFiles.map(\.sourceURL), [source.appendingPathComponent("IMG_0002.jpg")])
        XCTAssertEqual(result.skippedSourceFileCount, 1)
        let message = try XCTUnwrap(result.skippedSourceFiles.first?.message)
        XCTAssertTrue(
            message.hasPrefix("backup copy failed: "),
            "expected honest backup failure message, got \(message)"
        )
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

    func testReimportReportsExistingAssetsSeparatelyFromNewAssets() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-reimport-counts")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let firstResult = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration)
        let secondResult = try service.addFolderInPlace(root, repository: repository, previewPolicy: .deferGeneration)

        XCTAssertEqual(firstResult.importedAssets.count, 1)
        XCTAssertEqual(firstResult.newAssetCount, 1)
        XCTAssertEqual(firstResult.existingAssetCount, 0)
        XCTAssertEqual(secondResult.importedAssets.map(\.id), firstResult.importedAssets.map(\.id))
        XCTAssertEqual(secondResult.newAssetCount, 0)
        XCTAssertEqual(secondResult.existingAssetCount, 1)
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

private final class EarlyCatalogProgressRecorder: @unchecked Sendable {
    private let repository: CatalogRepository
    private let targetDetail: String
    private let lock = NSLock()
    private var catalogedAssetIDs: [AssetID] = []
    private var assetWasReadable = false

    init(repository: CatalogRepository, targetDetail: String) {
        self.repository = repository
        self.targetDetail = targetDetail
    }

    func append(_ progress: LibraryImportProgress) {
        guard progress.detail == targetDetail else { return }
        lock.withLock {
            catalogedAssetIDs = progress.catalogedAssetIDs
            if let firstCatalogedID = progress.catalogedAssetIDs.first {
                assetWasReadable = ((try? repository.asset(id: firstCatalogedID)) != nil)
            }
        }
    }

    func snapshot() -> (catalogedAssetIDs: [AssetID], assetWasReadable: Bool) {
        lock.withLock {
            (catalogedAssetIDs, assetWasReadable)
        }
    }
}

private struct MetadataOnlyDecodeProvider: DecodeProvider {
    let name = "metadata-only"

    func canDecode(url: URL) -> Bool {
        url.pathExtension.lowercased() == "metadataonly"
    }

    func capability(forFileExtension fileExtension: String) -> DecodeCapability? {
        DecodeCapability(
            providerName: name,
            fileExtension: fileExtension,
            support: .bestEffort,
            canReadMetadata: true,
            canUseEmbeddedPreview: false,
            canRenderPreview: false,
            canRenderFullImage: false,
            note: "Metadata-only test provider"
        )
    }

    func metadata(for url: URL) throws -> DecodeMetadata {
        DecodeMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            provenance: ProviderProvenance(provider: name, model: "fixture", version: "1", settingsHash: "default")
        )
    }
}
