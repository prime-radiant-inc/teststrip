import XCTest
@testable import TeststripCore

/// Task 4: importing a file that shares a folder and stem with an existing
/// (or newly-imported) sibling bonds RAW+JPEG pairs at import time, in either
/// arrival order, without needing the one-time catalog-wide backfill.
final class IngestBondingTests: XCTestCase {
    private func makeRepository(in root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    func testImportingSiblingJPEGAfterRAWBondsItToTheRAW() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "bonding-raw-then-jpeg")
        let rawFile = root.appendingPathComponent("IMG_0001.CR2")
        try Data("raw bytes".utf8).write(to: rawFile)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2", "jpg"]))

        let rawImport = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        XCTAssertEqual(rawImport.map(\.originalURL), [rawFile])

        let jpegFile = root.appendingPathComponent("IMG_0001.jpg")
        try Data("jpg bytes".utf8).write(to: jpegFile)
        let secondImport = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        let jpegAsset = try XCTUnwrap(secondImport.first { $0.originalURL == jpegFile })
        let rawID = rawImport[0].id
        XCTAssertEqual(try repository.bondedPrimaryID(of: jpegAsset.id), rawID)
        XCTAssertNil(try repository.bondedPrimaryID(of: rawID), "a RAW is always the primary, never a secondary")
    }

    func testImportingRAWAfterSiblingJPEGBondsTheJPEGToTheRAW() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "bonding-jpeg-then-raw")
        let jpegFile = root.appendingPathComponent("IMG_0002.jpg")
        try Data("jpg bytes".utf8).write(to: jpegFile)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2", "jpg"]))

        let jpegImport = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        let jpegID = jpegImport[0].id
        XCTAssertNil(
            try repository.bondedPrimaryID(of: jpegID),
            "no RAW sibling exists yet, so the JPEG must import unbonded"
        )

        let rawFile = root.appendingPathComponent("IMG_0002.CR2")
        try Data("raw bytes".utf8).write(to: rawFile)
        let secondImport = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        let rawAsset = try XCTUnwrap(secondImport.first { $0.originalURL == rawFile })
        XCTAssertEqual(try repository.bondedPrimaryID(of: jpegID), rawAsset.id)
    }

    func testImportingRAWAndJPEGTogetherInOneBatchBondsThem() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "bonding-same-batch")
        let rawFile = root.appendingPathComponent("IMG_0004.CR2")
        let jpegFile = root.appendingPathComponent("IMG_0004.jpg")
        try Data("raw bytes".utf8).write(to: rawFile)
        try Data("jpg bytes".utf8).write(to: jpegFile)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2", "jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        let rawAsset = try XCTUnwrap(imported.first { $0.originalURL == rawFile })
        let jpegAsset = try XCTUnwrap(imported.first { $0.originalURL == jpegFile })
        XCTAssertEqual(try repository.bondedPrimaryID(of: jpegAsset.id), rawAsset.id)
    }

    func testJPEGWithNoRAWSiblingImportsUnbonded() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "bonding-jpeg-alone")
        let jpegFile = root.appendingPathComponent("IMG_0003.jpg")
        try Data("jpg bytes".utf8).write(to: jpegFile)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["cr2", "jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(imported.map(\.originalURL), [jpegFile])
        XCTAssertNil(try repository.bondedPrimaryID(of: imported[0].id))
    }
}
