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

    func testLargeFileWithSameSizeButDifferentMiddleIsNotCollapsed() throws {
        // Two large files (> 128 KB) with the same forced content hash, same
        // size, but different middle bytes must both be imported. The
        // middle-chunk sample comparison catches the difference without
        // reading the entire file.
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-large-collision")
        let folder = root.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Create files larger than 2 × 64 KB so the sample path is exercised.
        let chunkSize = ContentHash.defaultChunkByteCount
        let fileSize = chunkSize * 4 // 256 KB — well above the 128 KB threshold
        var firstData = Data(count: fileSize)
        var secondData = Data(count: fileSize)
        // Fill head and tail identically, middle differently.
        firstData.withUnsafeMutableBytes { ptr in
            memset(ptr.baseAddress, 0xAA, fileSize)
        }
        secondData.withUnsafeMutableBytes { ptr in
            memset(ptr.baseAddress, 0xAA, fileSize)
        }
        // Make middles differ at the midpoint.
        let midOffset = fileSize / 2
        firstData[midOffset] = 0x11
        secondData[midOffset] = 0x22

        let first = folder.appendingPathComponent("first.jpg")
        let second = folder.appendingPathComponent("second.jpg")
        try firstData.write(to: first)
        try secondData.write(to: second)

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

        XCTAssertEqual(imported.count, 2, "large files with different middles must both be imported")
        XCTAssertEqual(skipped, [])
    }

    func testLargeFileWithIdenticalContentIsDetectedBySample() throws {
        // Two genuinely identical large files (> 128 KB) at different paths
        // must be detected as duplicates by the sample comparison, without
        // reading the entire file.
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-large-match")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let chunkSize = ContentHash.defaultChunkByteCount
        let sharedContent = Data(count: chunkSize * 4) // 256 KB
        let first = firstFolder.appendingPathComponent("original.jpg")
        let second = secondFolder.appendingPathComponent("copy.jpg")
        try sharedContent.write(to: first)
        try sharedContent.write(to: second)

        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [second],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport, [], "identical large file under a different name is already in the catalog")
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent), ["copy.jpg"])
    }

    func testInPlaceReimportSkipsAlreadyCatalogedFiles() throws {
        // Re-importing the same folder in-place (addFolder + skipCatalogedContent)
        // must skip every file that's already cataloged at the same path, without
        // a byte-by-byte contentsEqual comparison. On an SMB mount, that comparison
        // reads every file twice over the network, making a 130k-photo re-import
        // take days instead of seconds.
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-inplace-reimport")
        let folder = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("frame one".utf8).write(to: folder.appendingPathComponent("IMG_0001.jpg"))
        try Data("frame two".utf8).write(to: folder.appendingPathComponent("IMG_0002.jpg"))
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        // First import catalogs both files in-place.
        let firstImport = try service.ingest(
            plan: IngestPlanner.addFolder(folder),
            repository: repository
        )
        XCTAssertEqual(firstImport.count, 2)

        // Re-import the same folder with skipCatalogedContent.
        var skipped: [IngestSkippedSourceFile] = []
        let sourceFiles = try service.files(for: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent))
        let secondImport = try service.ingest(
            files: sourceFiles,
            plan: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport, [], "in-place re-import must skip files already in the catalog")
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent).sorted(), ["IMG_0001.jpg", "IMG_0002.jpg"])
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 2, "no duplicate assets created")
    }

    func testModifiedFileIsReimportedNotSkipped() throws {
        // A file that has been modified since being cataloged (different size or
        // modification date) must NOT be skipped by the path-first short-circuit —
        // it needs to be re-imported with updated metadata.
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-modified-reimport")
        let folder = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("photo.jpg")
        try Data("original content".utf8).write(to: file)
        let repository = try makeRepository(in: root)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        // First import catalogs the file.
        let firstImport = try service.ingest(
            plan: IngestPlanner.addFolder(folder),
            repository: repository
        )
        XCTAssertEqual(firstImport.count, 1)

        // Modify the file — different content + new modification date.
        try Data("modified content that is longer".utf8).write(to: file)

        // Re-import: the modified file should NOT be skipped.
        var skipped: [IngestSkippedSourceFile] = []
        let sourceFiles = try service.files(for: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent))
        let secondImport = try service.ingest(
            files: sourceFiles,
            plan: IngestPlanner.addFolder(folder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport.count, 1, "modified file must be re-imported, not skipped")
        XCTAssertEqual(skipped, [], "modified file should not be reported as already in catalog")
    }

    // MARK: - Paranoia: metadata-aware dedup verification

    private struct FakeDecodeProvider: DecodeProvider {
        let name = "fake-decode"
        let technicalMetadata: AssetTechnicalMetadata

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

    private static func fakeTechnicalMetadata(
        capturedAt: Date? = nil,
        pixelWidth: Int = 100,
        pixelHeight: Int = 100
    ) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "fake-decode", model: "fake", version: "1", settingsHash: "default")
        )
    }

    /// Two identical large files at different paths with matching filename and
    /// technical metadata are trusted by the sample check — no full-file read.
    func testCrossPathDuplicateWithMatchingMetadataTrustedBySample() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-meta-match")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let chunkSize = ContentHash.defaultChunkByteCount
        let sharedContent = Data(count: chunkSize * 4) // 256 KB — above 128 KB threshold
        // Same filename in both folders — the metadata trust check requires it.
        let first = firstFolder.appendingPathComponent("IMG_0001.jpg")
        let second = secondFolder.appendingPathComponent("IMG_0001.jpg")
        try sharedContent.write(to: first)
        try sharedContent.write(to: second)

        let metadata = Self.fakeTechnicalMetadata(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: metadata)])
        )

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [second],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport, [], "identical file with matching metadata is already in the catalog")
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent), ["IMG_0001.jpg"])
    }

    /// Two identical large files at different paths with different filenames
    /// trigger the paranoid full-file comparison. Since the content is
    /// genuinely identical, the paranoid check still confirms the duplicate —
    /// the file is correctly skipped, just verified more carefully.
    func testCrossPathDuplicateWithDifferentFilenameUsesParanoidCheck() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-different-name")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let chunkSize = ContentHash.defaultChunkByteCount
        let sharedContent = Data(count: chunkSize * 4) // 256 KB
        // Different filenames — triggers paranoid path.
        let first = firstFolder.appendingPathComponent("original.jpg")
        let second = secondFolder.appendingPathComponent("renamed.jpg")
        try sharedContent.write(to: first)
        try sharedContent.write(to: second)

        let metadata = Self.fakeTechnicalMetadata(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: metadata)])
        )

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [second],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport, [], "identical content under a different name is still a duplicate even with paranoid check")
        XCTAssertEqual(skipped.map(\.sourceURL.lastPathComponent), ["renamed.jpg"])
    }

    /// Two large files with the same forced hash, same filename, same metadata,
    /// but different content — the sample check catches the difference, so both
    /// are imported. This verifies the sample path still rejects mismatches.
    func testMatchingMetadataButDifferentContentNotCollapsed() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-meta-match-diff-content")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let chunkSize = ContentHash.defaultChunkByteCount
        let fileSize = chunkSize * 4 // 256 KB
        var firstData = Data(count: fileSize)
        var secondData = Data(count: fileSize)
        firstData.withUnsafeMutableBytes { ptr in memset(ptr.baseAddress, 0xAA, fileSize) }
        secondData.withUnsafeMutableBytes { ptr in memset(ptr.baseAddress, 0xAA, fileSize) }
        // Same head and tail, different middle — same forced hash, different content.
        firstData[fileSize / 2] = 0x11
        secondData[fileSize / 2] = 0x22

        let first = firstFolder.appendingPathComponent("IMG_0001.jpg")
        let second = secondFolder.appendingPathComponent("IMG_0001.jpg")
        try firstData.write(to: first)
        try secondData.write(to: second)

        let metadata = Self.fakeTechnicalMetadata(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: metadata)]),
            contentHasher: { _ in "forced-collision" }
        )

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [second],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport.count, 1, "different content with matching metadata must not be collapsed by the sample check")
        XCTAssertEqual(skipped, [])
    }

    /// Two large files with the same forced hash, different filenames, and
    /// different content — the paranoid full-file comparison catches the
    /// difference, so both are imported. This is the key paranoia test: a
    /// distinct file is never silently dropped even when the content hash
    /// collides.
    func testDistinctLargeFilesWithDifferentFilenameNotCollapsed() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-paranoid-distinct")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let chunkSize = ContentHash.defaultChunkByteCount
        let fileSize = chunkSize * 4 // 256 KB
        var firstData = Data(count: fileSize)
        var secondData = Data(count: fileSize)
        firstData.withUnsafeMutableBytes { ptr in memset(ptr.baseAddress, 0xAA, fileSize) }
        secondData.withUnsafeMutableBytes { ptr in memset(ptr.baseAddress, 0xAA, fileSize) }
        // Same head and tail, different middle — same forced hash, different content.
        firstData[fileSize / 2] = 0x11
        secondData[fileSize / 2] = 0x22

        // Different filenames — triggers paranoid path.
        let first = firstFolder.appendingPathComponent("first.jpg")
        let second = secondFolder.appendingPathComponent("second.jpg")
        try firstData.write(to: first)
        try secondData.write(to: second)

        let metadata = Self.fakeTechnicalMetadata(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = try makeRepository(in: root)
        let service = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: metadata)]),
            contentHasher: { _ in "forced-collision" }
        )

        _ = try service.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try service.ingest(
            files: [second],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport.count, 1, "distinct files with different names must not be collapsed by paranoid check")
        XCTAssertEqual(skipped, [])
    }

    /// Two large files with the same forced hash, same filename, but different
    /// technical metadata (different pixel dimensions) — the paranoid path is
    /// used, and genuinely different content is not collapsed.
    func testSameFilenameButDifferentMetadataTriggersParanoidCheck() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "dedup-diff-metadata")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let chunkSize = ContentHash.defaultChunkByteCount
        let fileSize = chunkSize * 4 // 256 KB
        var firstData = Data(count: fileSize)
        var secondData = Data(count: fileSize)
        firstData.withUnsafeMutableBytes { ptr in memset(ptr.baseAddress, 0xAA, fileSize) }
        secondData.withUnsafeMutableBytes { ptr in memset(ptr.baseAddress, 0xAA, fileSize) }
        firstData[fileSize / 2] = 0x11
        secondData[fileSize / 2] = 0x22

        // Same filename in both folders.
        let first = firstFolder.appendingPathComponent("IMG_0001.jpg")
        let second = secondFolder.appendingPathComponent("IMG_0001.jpg")
        try firstData.write(to: first)
        try secondData.write(to: second)

        let repository = try makeRepository(in: root)

        // First import with 100×100 metadata.
        let firstMetadata = Self.fakeTechnicalMetadata(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pixelWidth: 100, pixelHeight: 100
        )
        let firstService = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: firstMetadata)]),
            contentHasher: { _ in "forced-collision" }
        )
        _ = try firstService.ingest(plan: IngestPlanner.addFolder(firstFolder), repository: repository)

        // Second import with 200×200 metadata — different metadata triggers paranoid.
        let secondMetadata = Self.fakeTechnicalMetadata(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pixelWidth: 200, pixelHeight: 200
        )
        let secondService = IngestService(
            scanner: FolderScanner(supportedExtensions: ["jpg"]),
            decodeRegistry: DecodeRegistry(providers: [FakeDecodeProvider(technicalMetadata: secondMetadata)]),
            contentHasher: { _ in "forced-collision" }
        )
        var skipped: [IngestSkippedSourceFile] = []
        let secondImport = try secondService.ingest(
            files: [second],
            plan: IngestPlanner.addFolder(secondFolder, duplicateHandling: .skipCatalogedContent),
            repository: repository,
            alreadyInCatalog: { skipped.append($0) }
        )

        XCTAssertEqual(secondImport.count, 1, "distinct files with different metadata must not be collapsed")
        XCTAssertEqual(skipped, [])
    }
}
