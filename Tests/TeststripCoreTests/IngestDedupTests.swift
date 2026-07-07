import XCTest
@testable import TeststripCore

final class IngestDedupTests: XCTestCase {
    private func makeRepository(in root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    func testContentHashIsStoredAtIngest() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-hash-stored")
        let image = root.appendingPathComponent("one.jpg")
        try Data("some bytes".utf8).write(to: image)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(
            imported[0].fingerprint.contentHash,
            try ContentHash.compute(forFileAt: image)
        )
        XCTAssertEqual(try repository.asset(contentHash: imported[0].fingerprint.contentHash ?? "")?.id, imported[0].id)
    }

    func testReimportingCardSkipsAlreadyImportedContent() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-reimport-card")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("frame one".utf8).write(to: source.appendingPathComponent("IMG_0001.jpg"))
        try Data("frame two".utf8).write(to: source.appendingPathComponent("IMG_0002.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))
        let plan = IngestPlanner.copyFromCard(
            source: source,
            destinationRoot: destination,
            duplicateHandling: .skipCatalogedContent
        )

        let firstImport = try service.ingest(plan: plan, repository: repository)
        XCTAssertEqual(firstImport.count, 2)

        var skipped: [IngestSkippedSourceFile] = []
        let sourceFiles = try service.files(for: plan)
        let secondImport = try service.ingest(
            files: sourceFiles,
            plan: plan,
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport, [], "re-inserting the same card must copy nothing")
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 2)
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent).sorted(), ["IMG_0001.jpg", "IMG_0002.jpg"])
    }

    func testSameContentUnderDifferentNameIsDetectedAcrossPaths() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-cross-path")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let sharedContent = Data("identical frame".utf8)
        try sharedContent.write(to: firstFolder.appendingPathComponent("original.jpg"))
        try sharedContent.write(to: secondFolder.appendingPathComponent("renamed-copy.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [secondFolder.appendingPathComponent("renamed-copy.jpg")],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport, [], "the same content under a different name is already in the catalog")
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent), ["renamed-copy.jpg"])
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 1)
    }

    func testDuplicatesWithinOneBatchCollapse() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-within-batch")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        let firstCard = source.appendingPathComponent("100CANON", isDirectory: true)
        let secondCard = source.appendingPathComponent("101CANON", isDirectory: true)
        try FileManager.default.createDirectory(at: firstCard, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCard, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sharedContent = Data("the same shot twice".utf8)
        let firstFile = firstCard.appendingPathComponent("IMG_0001.jpg")
        let secondFile = secondCard.appendingPathComponent("DUP_0001.jpg")
        try sharedContent.write(to: firstFile)
        try sharedContent.write(to: secondFile)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        var skipped: [IngestSkippedSourceFile] = []
        let imported = try service.ingest(
            files: [firstFile, secondFile],
            plan: IngestPlanner.copyFromCard(
                source: source,
                destinationRoot: destination,
                duplicateHandling: .skipCatalogedContent
            ),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(imported.count, 1, "a shot appearing twice in one batch collapses to one catalog entry")
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent), ["DUP_0001.jpg"])
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 1)
    }

    func testImportAllKeepsEveryDuplicate() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-import-all")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let sharedContent = Data("identical frame".utf8)
        try sharedContent.write(to: firstFolder.appendingPathComponent("original.jpg"))
        try sharedContent.write(to: secondFolder.appendingPathComponent("copy.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [secondFolder.appendingPathComponent("copy.jpg")],
            plan: IngestPlanner.addFolder(secondFolder),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport.count, 1, "import-all catalogs duplicates the user explicitly asked to keep")
        XCTAssertEqual(skipped, [])
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 2)
    }

    func testGenuinelyNewContentIsImportedUnderSkipMode() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-new-content")
        let folder = root.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("new frame".utf8).write(to: folder.appendingPathComponent("one.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        let imported = try service.ingest(
            plan: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent),
            repository: repository
        )

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 1)
    }

    func testPartialHashCollisionWithDistinctBytesIsNotCollapsed() throws {
        // A forced hash collision (distinct files, identical partial hash) must
        // never drop a distinct file: the exact byte comparison before skipping
        // keeps both. This guards the bounded-hash strategy against data loss.
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-collision")
        let folder = root.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = folder.appendingPathComponent("first.jpg")
        let second = folder.appendingPathComponent("second.jpg")
        try Data("distinct content A".utf8).write(to: first)
        try Data("distinct content B".utf8).write(to: second)
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            contentHasher: { _ in "forced-collision" }
        )

        var skipped: [IngestSkippedSourceFile] = []
        let imported = try service.ingest(
            files: [first, second],
            plan: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(imported.count, 2, "colliding but distinct bytes must both be imported")
        XCTAssertEqual(skipped, [])
    }

    func testOfflineCatalogedOriginalIsTrustedByHash() throws {
        // When a matching cataloged original cannot be read (an offline drive),
        // the content hash is trusted so re-inserting the card still skips.
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-offline")
        let folder = root.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("one.jpg")
        try Data("archived frame".utf8).write(to: source)
        let repository = try makeRepository(in: root)
        let offlineOriginal = URL(fileURLWithPath: "/Volumes/Unmounted/archive/one.jpg")
        try repository.upsert(Asset(
            id: .new(),
            originalURL: offlineOriginal,
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(
                size: 100,
                modificationDate: Date(timeIntervalSince1970: 1),
                contentHash: try ContentHash.compute(forFileAt: source)
            ),
            availability: .offline,
            metadata: AssetMetadata()
        ))
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        var skipped: [IngestSkippedSourceFile] = []
        let imported = try service.ingest(
            files: [source],
            plan: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(imported, [])
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent), ["one.jpg"])
    }
}
