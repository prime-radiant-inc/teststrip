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
