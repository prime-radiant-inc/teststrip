import XCTest
import TeststripCore

final class FolderImportTests: XCTestCase {
    func testIngestPlanCanBeConstructedByPublicClients() throws {
        let source = URL(fileURLWithPath: "/Volumes/Card/DCIM")
        let destination = URL(fileURLWithPath: "/Photos/2026")

        let plan = IngestPlan(mode: .copyToDestination, sourceRoot: source, destinationRoot: destination)

        XCTAssertEqual(plan.mode, .copyToDestination)
        XCTAssertEqual(plan.sourceRoot, source)
        XCTAssertEqual(plan.destinationRoot, destination)
    }

    func testFolderScannerFindsSupportedImageFiles() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan")
        try Data("raw".utf8).write(to: root.appendingPathComponent("one.CR2"))
        try Data("jpg".utf8).write(to: root.appendingPathComponent("two.jpg"))
        try Data("txt".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let scanner = FolderScanner(supportedExtensions: ["cr2", "jpg"])
        let files = try scanner.scan(root: root).map(\.lastPathComponent).sorted()

        XCTAssertEqual(files, ["one.CR2", "two.jpg"])
    }

    func testFolderScannerReturnsSupportedFilesInNaturalFilenameOrder() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan-order")
        try Data("ten".utf8).write(to: root.appendingPathComponent("10.jpg"))
        try Data("two".utf8).write(to: root.appendingPathComponent("2.jpg"))
        try Data("one".utf8).write(to: root.appendingPathComponent("1.jpg"))

        let scanner = FolderScanner(supportedExtensions: ["jpg"])
        let files = try scanner.scan(root: root).map(\.lastPathComponent)

        XCTAssertEqual(files, ["1.jpg", "2.jpg", "10.jpg"])
    }

    func testFolderScannerReportsSupportedFileCountWhileScanning() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan-progress")
        try Data("raw".utf8).write(to: root.appendingPathComponent("one.CR2"))
        try Data("jpg".utf8).write(to: root.appendingPathComponent("two.jpg"))
        try Data("txt".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let recorder = FolderScanProgressRecorder()

        let scanner = FolderScanner(supportedExtensions: ["cr2", "jpg"])
        let files = try scanner.scan(root: root) { progress in
            recorder.append(progress)
        }

        XCTAssertEqual(files.map(\.lastPathComponent).sorted(), ["one.CR2", "two.jpg"])
        XCTAssertEqual(recorder.values().map(\.supportedFileCount), [1, 2])
        XCTAssertEqual(recorder.values().map(\.url.lastPathComponent).sorted(), ["one.CR2", "two.jpg"])
    }

    func testFolderScannerNormalizesSupportedExtensions() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan-normalized")
        try Data("jpg".utf8).write(to: root.appendingPathComponent("one.jpg"))

        let scanner = FolderScanner(supportedExtensions: ["JPG"])
        let files = try scanner.scan(root: root).map(\.lastPathComponent)

        XCTAssertEqual(files, ["one.jpg"])
    }

    func testFolderScannerReportsVideoAndUnrecognizedFilesAsSkipped() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan-skipped")
        try Data("jpg".utf8).write(to: root.appendingPathComponent("one.jpg"))
        try Data("mov".utf8).write(to: root.appendingPathComponent("clip.MOV"))
        try Data("mp4".utf8).write(to: root.appendingPathComponent("clip.mp4"))
        try Data("txt".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let recorder = FolderScanSkippedFileRecorder()

        let scanner = FolderScanner(supportedExtensions: ["jpg"])
        let files = try scanner.scan(root: root, skipped: { skippedFile in
            recorder.append(skippedFile)
        })

        XCTAssertEqual(files.map(\.lastPathComponent), ["one.jpg"])
        let skipped = recorder.values().sorted { first, second in
            first.url.lastPathComponent < second.url.lastPathComponent
        }
        XCTAssertEqual(skipped.map(\.url.lastPathComponent), ["clip.MOV", "clip.mp4", "notes.txt"])
        XCTAssertEqual(skipped.map(\.reason), [.videoFile, .videoFile, .unrecognizedFile])
    }

    func testFolderScannerDoesNotReportAncillaryFilesAsSkipped() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan-skipped-ancillary")
        try Data("jpg".utf8).write(to: root.appendingPathComponent("one.jpg"))
        try Data("xmp".utf8).write(to: root.appendingPathComponent("one.jpg.xmp"))
        try Data("xmp".utf8).write(to: root.appendingPathComponent("one.XMP"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        let subfolder = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: subfolder.appendingPathComponent("two.jpg"))
        let recorder = FolderScanSkippedFileRecorder()

        let scanner = FolderScanner(supportedExtensions: ["jpg"])
        let files = try scanner.scan(root: root, skipped: { skippedFile in
            recorder.append(skippedFile)
        })

        XCTAssertEqual(files.map(\.lastPathComponent), ["two.jpg", "one.jpg"])
        XCTAssertEqual(recorder.values(), [])
    }

    func testAddFolderPlanDoesNotMoveOriginals() throws {
        let source = URL(fileURLWithPath: "/Volumes/NAS/Job")
        let plan = IngestPlanner.addFolder(source)

        XCTAssertEqual(plan.mode, .addInPlace)
        XCTAssertEqual(plan.sourceRoot, source)
        XCTAssertNil(plan.destinationRoot)
    }

    func testCardCopyPlanComputesDestination() throws {
        let source = URL(fileURLWithPath: "/Volumes/Card/DCIM")
        let destination = URL(fileURLWithPath: "/Photos/2026")
        let plan = IngestPlanner.copyFromCard(source: source, destinationRoot: destination)

        XCTAssertEqual(plan.mode, .copyToDestination)
        XCTAssertEqual(plan.destinationRoot, destination)
    }

    func testIngestServiceCatalogsFolderAssetsInPlace() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(imported.count, 1)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.originalURL, image)
        XCTAssertEqual(fetched.availability, .online)
    }

    func testIngestServiceCatalogsDecodeTechnicalMetadata() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-technical-metadata")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let technicalMetadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            cameraMake: "Canon",
            cameraModel: "EOS R5",
            lensModel: "RF 50mm F1.2L USM",
            isoSpeed: 800,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            provenance: ProviderProvenance(provider: "fake-decode", model: "fake", version: "1", settingsHash: "default")
        )
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: technicalMetadata)])
        )

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(imported.count, 1)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.technicalMetadata, technicalMetadata)
    }

    func testIngestServiceImportsAdjacentSidecarMetadata() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-sidecar")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        try sidecarData.write(to: image.appendingPathExtension("xmp"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(imported.count, 1)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.metadata, sidecarMetadata)
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: fetched.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
    }

    func testReingestingNewerMatchingSidecarRefreshesSyncCheckpoint() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-newer-sidecar-checkpoint")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        let sidecarURL = image.appendingPathExtension("xmp")
        try sidecarData.write(to: sidecarURL)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))
        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        let assetID = imported[0].id
        let initialSync = try XCTUnwrap(try repository.metadataSyncItem(assetID: assetID)?.lastSyncedAt)
        Thread.sleep(forTimeInterval: 0.01)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: sidecarURL.path)

        _ = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(try repository.asset(id: assetID).metadata, sidecarMetadata)
        let refreshedSync = try XCTUnwrap(try repository.metadataSyncItem(assetID: assetID)?.lastSyncedAt)
        XCTAssertGreaterThan(refreshedSync.timeIntervalSince1970, initialSync.timeIntervalSince1970)
    }

    func testReingestingWithLocalAndSidecarMetadataChangesRecordsConflict() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-sidecar-conflict")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let sidecarURL = image.appendingPathExtension("xmp")
        try XMPPacket(metadata: AssetMetadata(rating: 2)).xmlData().write(to: sidecarURL)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))
        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        let assetID = imported[0].id
        let lastSyncedFingerprint = try XCTUnwrap(try repository.lastMetadataSyncFingerprint(assetID: assetID))
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 4
        }
        try XMPPacket(metadata: AssetMetadata(rating: 5)).xmlData().write(to: sidecarURL)

        _ = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(try repository.asset(id: assetID).metadata.rating, 4)
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [
            MetadataSyncItem(
                assetID: assetID,
                sidecarURL: sidecarURL,
                catalogGeneration: 2,
                lastSyncedFingerprint: lastSyncedFingerprint
            )
        ])
    }

    func testIngestContinuesPastUnparsableSidecarAndRecordsConflict() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-unparsable-sidecar")
        let first = root.appendingPathComponent("one.jpg")
        let second = root.appendingPathComponent("two.jpg")
        try Data("jpg one".utf8).write(to: first)
        try Data("jpg two".utf8).write(to: second)
        let sidecarURL = first.appendingPathExtension("xmp")
        let legacySidecarData = Data("""
        <xmpmeta xmlns="https://teststrip.app/xmp">
          <rating>2</rating>
        </xmpmeta>
        """.utf8)
        try legacySidecarData.write(to: sidecarURL)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        // One legacy or corrupt sidecar must not abort the whole folder
        // import; the asset keeps its catalog metadata and the sidecar lands
        // in XMP Conflicts review instead.
        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(imported.map(\.originalURL), [first, second])
        let firstAsset = try XCTUnwrap(try repository.asset(originalURL: first))
        XCTAssertEqual(firstAsset.metadata, AssetMetadata())
        XCTAssertNotNil(try repository.asset(originalURL: second))
        XCTAssertEqual(try Data(contentsOf: sidecarURL), legacySidecarData)
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [
            MetadataSyncItem(
                assetID: firstAsset.id,
                sidecarURL: sidecarURL,
                catalogGeneration: 1,
                lastSyncedFingerprint: nil
            )
        ])
    }

    func testReingestingFolderPreservesAssetIdentityAndMetadata() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-idempotent")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))
        let firstImport = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        let assetID = firstImport[0].id
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 4
            metadata.keywords = ["keeper"]
        }
        let refreshedData = Data("refreshed jpg".utf8)
        try refreshedData.write(to: image)

        let secondImport = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        let assets = try repository.allAssets(limit: 100)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(secondImport.map(\.id), [assetID])
        let fetched = try repository.asset(id: assetID)
        XCTAssertEqual(fetched.metadata.rating, 4)
        XCTAssertEqual(fetched.metadata.keywords, ["keeper"])
        XCTAssertEqual(fetched.fingerprint.size, Int64(refreshedData.count))
    }

    func testIngestDoesNotUsePathComponentAsVolumeIdentifier() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest-volume")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        let pathComponentFallback = image.pathComponents.dropFirst().first
        XCTAssertNotEqual(imported[0].volumeIdentifier, pathComponentFallback)
    }

    func testCopyFromCardPreservesRelativeDirectoriesForDuplicateBasenames() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let firstDirectory = source.appendingPathComponent("100CANON", isDirectory: true)
        let secondDirectory = source.appendingPathComponent("101CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let firstSource = firstDirectory.appendingPathComponent("IMG_0001.CR2")
        let secondSource = secondDirectory.appendingPathComponent("IMG_0001.CR2")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
            repository: repository
        )

        let firstDestination = destination
            .appendingPathComponent("100CANON", isDirectory: true)
            .appendingPathComponent("IMG_0001.CR2")
        let secondDestination = destination
            .appendingPathComponent("101CANON", isDirectory: true)
            .appendingPathComponent("IMG_0001.CR2")
        XCTAssertEqual(imported.map(\.originalURL).sorted(by: { $0.path < $1.path }), [firstDestination, secondDestination])
        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: secondDestination, encoding: .utf8), "second")
    }

    func testCopyFromCardRejectsMissingDestinationRoot() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-missing-destination")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Destination folder is missing"))
        }
    }

    func testCopyFromCardRejectsDestinationRootThatIsFile() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-file-destination")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        try Data("not a directory".utf8).write(to: destination)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Destination is not a folder"))
        }
    }

    func testCopyFromCardRejectsDestinationMatchingSource() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-matching-destination")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: source),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Destination must be different from the card source"))
        }
    }

    func testCopyFromCardRejectsDestinationInsideSource() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-nested-destination")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = source.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Destination cannot be inside the card source"))
        }
    }

    func testCopyFromCardRejectsSourceInsideDestination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-nested-source")
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let source = destination.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Card source cannot be inside the destination"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("IMG_0001.CR2").path))
    }

    func testCopyFromCardRejectsSourceInsideDestinationWhenFilesAreProvidedDirectly() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-nested-source-direct")
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let source = destination.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.CR2")
        try Data("raw bytes".utf8).write(to: sourceFile)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                files: [sourceFile],
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Card source cannot be inside the destination"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("IMG_0001.CR2").path))
    }

    func testCopyFromCardCopiesAdjacentSidecarAndImportsMetadataFromDestination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-sidecar")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.CR2")
        try Data("raw bytes".utf8).write(to: sourceFile)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = sourceFile.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
            repository: repository
        )

        let destinationFile = destination.appendingPathComponent("IMG_0001.CR2")
        let destinationSidecar = destinationFile.appendingPathExtension("xmp")
        XCTAssertEqual(imported.map(\.originalURL), [destinationFile])
        XCTAssertEqual(try Data(contentsOf: sourceFile), Data("raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: sourceSidecar), sidecarData)
        XCTAssertEqual(try Data(contentsOf: destinationFile), Data("raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationSidecar), sidecarData)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.metadata, metadata)
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: fetched.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testCopyFromCardResumesWhenDestinationOriginalAndSidecarAlreadyExistUncataloged() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-resume")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.CR2")
        try Data("raw bytes".utf8).write(to: sourceFile)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = sourceFile.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let destinationFile = destination.appendingPathComponent("IMG_0001.CR2")
        let destinationSidecar = destinationFile.appendingPathExtension("xmp")
        try Data(contentsOf: sourceFile).write(to: destinationFile)
        try sidecarData.write(to: destinationSidecar)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
            repository: repository
        )

        XCTAssertEqual(imported.map(\.originalURL), [destinationFile])
        XCTAssertEqual(try Data(contentsOf: destinationFile), Data("raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationSidecar), sidecarData)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.metadata, metadata)
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: fetched.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testReingestingCopiedCardAssetReusesCatalogedDestination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-reingest")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let sourceDirectory = source.appendingPathComponent("100CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("IMG_0001.CR2")
        try Data("source".utf8).write(to: sourceFile)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))
        let plan = IngestPlanner.copyFromCard(source: source, destinationRoot: destination)
        let firstImport = try service.ingest(plan: plan, repository: repository)
        let assetID = firstImport[0].id
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 5
            metadata.flag = .pick
        }

        let secondImport = try service.ingest(plan: plan, repository: repository)

        let importedDestination = destination
            .appendingPathComponent("100CANON", isDirectory: true)
            .appendingPathComponent("IMG_0001.CR2")
        let assets = try repository.allAssets(limit: 100)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(secondImport.map(\.id), [assetID])
        let fetched = try repository.asset(originalURL: importedDestination)
        XCTAssertEqual(fetched?.id, assetID)
        XCTAssertEqual(fetched?.metadata.rating, 5)
        XCTAssertEqual(fetched?.metadata.flag, .pick)
    }

    func testCardCopyPlanDefaultsToFlatDestinationPolicy() throws {
        let source = URL(fileURLWithPath: "/Volumes/Card/DCIM")
        let destination = URL(fileURLWithPath: "/Photos/2026")

        let plan = IngestPlanner.copyFromCard(source: source, destinationRoot: destination)

        XCTAssertEqual(plan.destinationPolicy, .flat)
    }

    func testCapturedDateCardCopyPlacesOriginalsInDatedCaptureFolders() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-dated")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let sourceDirectory = source.appendingPathComponent("100CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("IMG_0001.jpg")
        try Data("jpg".utf8).write(to: sourceFile)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(
                technicalMetadata: Self.fakeTechnicalMetadata(capturedAt: Self.utcDate(2025, 1, 3, 10, 30, 0))
            )])
        )

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination, destinationPolicy: .capturedDate),
            repository: repository
        )

        let expectedDestination = destination
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
            .appendingPathComponent("IMG_0001.jpg")
        XCTAssertEqual(imported.map(\.originalURL), [expectedDestination])
        XCTAssertEqual(try String(contentsOf: expectedDestination, encoding: .utf8), "jpg")
        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), "jpg")
    }

    func testCapturedDateCardCopyFallsBackToFileModificationDateWhenCaptureDateIsMissing() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-dated-fallback")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.jpg")
        try Data("jpg".utf8).write(to: sourceFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Self.utcDate(2024, 12, 31, 23, 59, 0)],
            ofItemAtPath: sourceFile.path
        )
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(
                technicalMetadata: Self.fakeTechnicalMetadata(capturedAt: nil)
            )])
        )

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination, destinationPolicy: .capturedDate),
            repository: repository
        )

        let expectedDestination = destination
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("2024-12-31", isDirectory: true)
            .appendingPathComponent("IMG_0001.jpg")
        XCTAssertEqual(imported.map(\.originalURL), [expectedDestination])
    }

    func testCapturedDateCardCopyThrowsWhenDatedDestinationFileAlreadyExists() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-dated-conflict")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let datedFolder = destination
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
        try FileManager.default.createDirectory(at: datedFolder, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.jpg")
        let conflictingFile = datedFolder.appendingPathComponent("IMG_0001.jpg")
        try Data("source".utf8).write(to: sourceFile)
        try Data("existing".utf8).write(to: conflictingFile)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(
                technicalMetadata: Self.fakeTechnicalMetadata(capturedAt: Self.utcDate(2025, 1, 3, 10, 30, 0))
            )])
        )

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination, destinationPolicy: .capturedDate),
                repository: repository
            )
        ) { error in
            guard case TeststripError.io = error else {
                return XCTFail("expected IO error, got \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: conflictingFile, encoding: .utf8), "existing")
    }

    func testCapturedDateCardCopyResumesWhenDatedDestinationAlreadyHoldsIdenticalFile() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-dated-resume")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let datedFolder = destination
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
        try FileManager.default.createDirectory(at: datedFolder, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.jpg")
        let existingDestination = datedFolder.appendingPathComponent("IMG_0001.jpg")
        try Data("jpg".utf8).write(to: sourceFile)
        try Data("jpg".utf8).write(to: existingDestination)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(
                technicalMetadata: Self.fakeTechnicalMetadata(capturedAt: Self.utcDate(2025, 1, 3, 10, 30, 0))
            )])
        )

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination, destinationPolicy: .capturedDate),
            repository: repository
        )

        XCTAssertEqual(imported.map(\.originalURL), [existingDestination])
        XCTAssertEqual(try repository.allAssets(limit: 10).count, 1)
    }

    func testCapturedDateCardCopyThrowsWhenDuplicateBasenamesShareCaptureDay() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-dated-duplicate")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let firstDirectory = source.appendingPathComponent("100CANON", isDirectory: true)
        let secondDirectory = source.appendingPathComponent("101CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstDirectory.appendingPathComponent("IMG_0001.jpg"))
        try Data("second".utf8).write(to: secondDirectory.appendingPathComponent("IMG_0001.jpg"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(
                technicalMetadata: Self.fakeTechnicalMetadata(capturedAt: Self.utcDate(2025, 1, 3, 10, 30, 0))
            )])
        )

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination, destinationPolicy: .capturedDate),
                repository: repository
            )
        ) { error in
            guard case TeststripError.io = error else {
                return XCTFail("expected IO error, got \(error)")
            }
        }
    }

    func testSecondCopyMirrorsOriginalsAndSidecarsUnderSecondCopyRoot() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-second")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let secondCopy = root.appendingPathComponent("Backup", isDirectory: true)
        let sourceDirectory = source.appendingPathComponent("100CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("IMG_0001.CR2")
        try Data("raw bytes".utf8).write(to: sourceFile)
        let sidecarData = try XMPPacket(metadata: AssetMetadata(rating: 5)).xmlData()
        try sidecarData.write(to: sourceFile.appendingPathExtension("xmp"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(
                source: source,
                destinationRoot: destination,
                secondCopyDestination: secondCopy
            ),
            repository: repository
        )

        let primaryFile = destination
            .appendingPathComponent("100CANON", isDirectory: true)
            .appendingPathComponent("IMG_0001.CR2")
        let backupFile = secondCopy
            .appendingPathComponent("100CANON", isDirectory: true)
            .appendingPathComponent("IMG_0001.CR2")
        XCTAssertEqual(imported.map(\.originalURL), [primaryFile])
        XCTAssertEqual(try Data(contentsOf: primaryFile), Data("raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: backupFile), Data("raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: primaryFile.appendingPathExtension("xmp")), sidecarData)
        XCTAssertEqual(try Data(contentsOf: backupFile.appendingPathExtension("xmp")), sidecarData)
    }

    func testSecondCopyUsesDatedFoldersWhenPolicyIsCapturedDate() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-second-dated")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let secondCopy = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.jpg")
        try Data("jpg".utf8).write(to: sourceFile)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(
                technicalMetadata: Self.fakeTechnicalMetadata(capturedAt: Self.utcDate(2025, 1, 3, 10, 30, 0))
            )])
        )

        let imported = try service.ingest(
            plan: IngestPlanner.copyFromCard(
                source: source,
                destinationRoot: destination,
                destinationPolicy: .capturedDate,
                secondCopyDestination: secondCopy
            ),
            repository: repository
        )

        let primaryFile = destination
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
            .appendingPathComponent("IMG_0001.jpg")
        let backupFile = secondCopy
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("2025-01-03", isDirectory: true)
            .appendingPathComponent("IMG_0001.jpg")
        XCTAssertEqual(imported.map(\.originalURL), [primaryFile])
        XCTAssertEqual(try Data(contentsOf: backupFile), Data("jpg".utf8))
    }

    func testSecondCopyFailureIsReportedPerFileWithoutFailingImport() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-second-failure")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let secondCopy = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.CR2")
        try Data("source".utf8).write(to: sourceFile)
        let conflictingBackup = secondCopy.appendingPathComponent("IMG_0001.CR2")
        try Data("existing".utf8).write(to: conflictingBackup)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))
        let plan = IngestPlanner.copyFromCard(
            source: source,
            destinationRoot: destination,
            secondCopyDestination: secondCopy
        )
        var secondCopyFailures: [IngestSkippedSourceFile] = []

        let imported = try service.ingest(
            files: try service.files(for: plan),
            plan: plan,
            repository: repository,
            secondCopyFailure: { secondCopyFailures.append($0) }
        )

        let primaryFile = destination.appendingPathComponent("IMG_0001.CR2")
        XCTAssertEqual(imported.map(\.originalURL), [primaryFile])
        XCTAssertEqual(try Data(contentsOf: primaryFile), Data("source".utf8))
        XCTAssertEqual(secondCopyFailures.map(\.sourceURL), [sourceFile])
        XCTAssertEqual(secondCopyFailures.count, 1)
        XCTAssertTrue(
            secondCopyFailures[0].message.hasPrefix("backup copy failed: "),
            "expected honest backup failure message, got \(secondCopyFailures[0].message)"
        )
        XCTAssertEqual(try String(contentsOf: conflictingBackup, encoding: .utf8), "existing")
    }

    func testCopyFromCardRejectsMissingSecondCopyDestination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-second-missing")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let secondCopy = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(
                    source: source,
                    destinationRoot: destination,
                    secondCopyDestination: secondCopy
                ),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Second copy destination folder is missing"))
        }
    }

    func testCopyFromCardRejectsSecondCopyDestinationMatchingSource() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-second-matching-source")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: source.appendingPathComponent("IMG_0001.CR2"))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(
                    source: source,
                    destinationRoot: destination,
                    secondCopyDestination: source
                ),
                repository: repository
            )
        ) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("Second copy destination must be different from the card source"))
        }
    }

    static func fakeTechnicalMetadata(capturedAt: Date?) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 100,
            pixelHeight: 100,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "fake-decode", model: "fake", version: "1", settingsHash: "default")
        )
    }

    static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    func testCopyFromCardThrowsWhenDestinationFileAlreadyExists() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-conflict")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("IMG_0001.CR2")
        let destinationFile = destination.appendingPathComponent("IMG_0001.CR2")
        try Data("source".utf8).write(to: sourceFile)
        try Data("existing".utf8).write(to: destinationFile)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2"]))

        XCTAssertThrowsError(
            try service.ingest(
                plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destination),
                repository: repository
            )
        ) { error in
            guard case TeststripError.io = error else {
                return XCTFail("expected IO error, got \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: destinationFile, encoding: .utf8), "existing")
    }
}

private final class FolderScanSkippedFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var skippedFiles: [FolderScanSkippedFile] = []

    func append(_ skippedFile: FolderScanSkippedFile) {
        lock.withLock {
            skippedFiles.append(skippedFile)
        }
    }

    func values() -> [FolderScanSkippedFile] {
        lock.withLock {
            skippedFiles
        }
    }
}

private final class FolderScanProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [FolderScanProgress] = []

    func append(_ progress: FolderScanProgress) {
        lock.withLock {
            updates.append(progress)
        }
    }

    func values() -> [FolderScanProgress] {
        lock.withLock {
            updates
        }
    }
}

private struct FakeDecodeProvider: DecodeProvider {
    let name = "fake-decode"
    var technicalMetadata: AssetTechnicalMetadata

    func canDecode(url: URL) -> Bool {
        url.pathExtension.lowercased() == "jpg"
    }

    func metadata(for url: URL) throws -> DecodeMetadata {
        DecodeMetadata(
            pixelWidth: technicalMetadata.pixelWidth,
            pixelHeight: technicalMetadata.pixelHeight,
            cameraMake: technicalMetadata.cameraMake,
            cameraModel: technicalMetadata.cameraModel,
            lensModel: technicalMetadata.lensModel,
            isoSpeed: technicalMetadata.isoSpeed,
            capturedAt: technicalMetadata.capturedAt,
            provenance: technicalMetadata.provenance
        )
    }
}
