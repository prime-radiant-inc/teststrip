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

    func testCopyFromCardCopiesAdjacentSidecarAndImportsMetadataFromDestination() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "card-copy-sidecar")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
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
