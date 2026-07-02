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
