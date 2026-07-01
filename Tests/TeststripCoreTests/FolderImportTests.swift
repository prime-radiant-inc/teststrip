import XCTest
@testable import TeststripCore

final class FolderImportTests: XCTestCase {
    func testFolderScannerFindsSupportedImageFiles() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan")
        try Data("raw".utf8).write(to: root.appendingPathComponent("one.CR2"))
        try Data("jpg".utf8).write(to: root.appendingPathComponent("two.jpg"))
        try Data("txt".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let scanner = FolderScanner(supportedExtensions: ["cr2", "jpg"])
        let files = try scanner.scan(root: root).map(\.lastPathComponent).sorted()

        XCTAssertEqual(files, ["one.CR2", "two.jpg"])
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
}
