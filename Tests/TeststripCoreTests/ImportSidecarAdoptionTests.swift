import XCTest
import TeststripCore

/// import-005: a pre-existing `.xmp` sidecar beside an original is folded into
/// the catalog at import — its portable metadata and its rotation override are
/// adopted immediately, not lazily on first touch. A sidecar is never written
/// just because a file was imported.
final class ImportSidecarAdoptionTests: XCTestCase {
    private func makeRepository(_ root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func ingestInPlace(_ root: URL, repository: CatalogRepository) throws -> [Asset] {
        try IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))
            .ingest(plan: IngestPlanner.addFolder(root), repository: repository)
    }

    func testImportFoldsPreExistingSidecarPortableFields() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "import-sidecar-adopt")
        let image = root.appendingPathComponent("frame.jpg")
        try Data("jpg".utf8).write(to: image)
        let sidecarMetadata = AssetMetadata(
            rating: 4,
            colorLabel: .green,
            flag: .pick,
            keywords: ["sunset", "keeper"],
            caption: "Golden hour",
            creator: "Jesse Vincent",
            copyright: "© 2026 Jesse Vincent"
        )
        let sidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        let sidecarURL = image.appendingPathExtension("xmp")
        try sidecarData.write(to: sidecarURL)
        let repository = try makeRepository(root)

        let imported = try ingestInPlace(root, repository: repository)

        XCTAssertEqual(imported.count, 1)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.metadata, sidecarMetadata)
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: fetched.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        // Importing must never rewrite the sidecar next to the original.
        XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarData)
    }

    func testImportAdoptsPreExistingSidecarRotation() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "import-sidecar-rotation")
        let image = root.appendingPathComponent("frame.jpg")
        try Data("jpg".utf8).write(to: image)
        let sidecarData = try XMPPacket(metadata: AssetMetadata(rating: 3), rotation: 90).xmlData()
        let sidecarURL = image.appendingPathExtension("xmp")
        try sidecarData.write(to: sidecarURL)
        let repository = try makeRepository(root)

        let imported = try ingestInPlace(root, repository: repository)

        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.metadata.rating, 3)
        // The sidecar's rotation override is adopted at import, matching what
        // the worker's `.importSidecar` handler does on first touch.
        XCTAssertEqual(fetched.technicalMetadata?.rotation, 90)
        XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarData)
    }

    func testReimportKeepsCatalogValueWhenSidecarUnchangedSinceSync() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "import-sidecar-precedence")
        let image = root.appendingPathComponent("frame.jpg")
        try Data("jpg".utf8).write(to: image)
        let sidecarURL = image.appendingPathExtension("xmp")
        try XMPPacket(metadata: AssetMetadata(rating: 2)).xmlData().write(to: sidecarURL)
        let repository = try makeRepository(root)
        let firstImport = try ingestInPlace(root, repository: repository)
        let assetID = firstImport[0].id

        // The catalog moves ahead of the sidecar (a user edit whose writeback
        // has not landed yet); the sidecar on disk stays at rating 2.
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 4
        }

        _ = try ingestInPlace(root, repository: repository)

        // Catalog changed alone: the catalog wins, and the stale sidecar value
        // is not silently adopted back over the newer catalog edit.
        XCTAssertEqual(try repository.asset(id: assetID).metadata.rating, 4)
    }
}
