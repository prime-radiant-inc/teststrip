import XCTest
@testable import TeststripCore

final class IngestPreflightTests: XCTestCase {
    private func makeRepository(in root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    func testCopyImportThrowsAndCopiesNothingWhenDestinationVolumeIsFull() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "preflight-full-volume")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("frame one".utf8).write(to: source.appendingPathComponent("IMG_0001.jpg"))
        try Data("frame two".utf8).write(to: source.appendingPathComponent("IMG_0002.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            availableCapacityForImportantUsage: { _ in 100 }
        )
        let plan = IngestPlanner.copyFromCard(source: source, destinationRoot: destination)

        XCTAssertThrowsError(
            try service.ingest(plan: plan, repository: repository)
        ) { error in
            guard case TeststripError.io(let message) = error else {
                return XCTFail("expected IO error, got \(error)")
            }
            XCTAssertTrue(
                message.localizedCaseInsensitiveContains("space") || message.localizedCaseInsensitiveContains("room"),
                "expected the error to mention space/room, got: \(message)"
            )
        }
        let copiedFiles = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(copiedFiles, [], "a failed preflight must copy nothing")
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 0)
    }

    func testCopyImportProceedsWhenDestinationVolumeHasAmpleSpace() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "preflight-ample-space")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("frame one".utf8).write(to: source.appendingPathComponent("IMG_0001.jpg"))
        try Data("frame two".utf8).write(to: source.appendingPathComponent("IMG_0002.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            availableCapacityForImportantUsage: { _ in 1_000_000_000_000 }
        )
        let plan = IngestPlanner.copyFromCard(source: source, destinationRoot: destination)

        let imported = try service.ingest(plan: plan, repository: repository)

        XCTAssertEqual(imported.count, 2)
        let copiedFiles = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(copiedFiles, ["IMG_0001.jpg", "IMG_0002.jpg"])
    }

    func testAddInPlaceIgnoresAvailableCapacity() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "preflight-add-in-place")
        let folder = root.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("frame one".utf8).write(to: folder.appendingPathComponent("one.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            availableCapacityForImportantUsage: { _ in 0 }
        )

        let imported = try service.ingest(plan: IngestPlanner.addFolder(folder), repository: repository)

        XCTAssertEqual(imported.count, 1, "add-in-place must never be blocked by destination free space")
    }
}
