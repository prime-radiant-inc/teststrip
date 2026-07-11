import XCTest
@testable import TeststripApp
import TeststripCore

final class ImportDedupPreviewTests: XCTestCase {
    private func makeDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-dedup-preview-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRepository(in root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    func testScanCountsAllContentAsNewAgainstEmptyCatalog() throws {
        let root = try makeDirectory(named: "empty-catalog")
        let source = root.appendingPathComponent("card", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("frame one".utf8).write(to: source.appendingPathComponent("one.jpg"))
        try Data("frame two".utf8).write(to: source.appendingPathComponent("two.jpg"))
        let repository = try makeRepository(in: root)

        let preview = try XCTUnwrap(ImportDedupPreview.scan(
            sourceURL: source,
            supportedExtensions: ["jpg"],
            repository: repository
        ))

        XCTAssertEqual(preview.newContentCount, 2)
        XCTAssertEqual(preview.existingContentCount, 0)
        XCTAssertFalse(preview.reachedLimit)
    }

    func testScanRecognizesContentAlreadyInCatalog() throws {
        let root = try makeDirectory(named: "known-content")
        let source = root.appendingPathComponent("card", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let known = source.appendingPathComponent("known.jpg")
        try Data("already imported".utf8).write(to: known)
        try Data("brand new".utf8).write(to: source.appendingPathComponent("fresh.jpg"))
        let repository = try makeRepository(in: root)
        try repository.upsert(Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: "/Library/2024/known-under-another-name.jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(
                size: 100,
                modificationDate: Date(timeIntervalSince1970: 1),
                contentHash: try ContentHash.compute(forFileAt: known)
            ),
            availability: .online,
            metadata: AssetMetadata()
        ))

        let preview = try XCTUnwrap(ImportDedupPreview.scan(
            sourceURL: source,
            supportedExtensions: ["jpg"],
            repository: repository
        ))

        XCTAssertEqual(preview.newContentCount, 1)
        XCTAssertEqual(preview.existingContentCount, 1)
    }

    // Persona-7's "Duplicates: 90 new" lie: re-importing a folder whose
    // files are already cataloged *at those exact paths* — but whose rows
    // carry no content hash (older or tool-seeded catalogs) — must not
    // promise them as new. The importer treats a path-matched file as
    // existing, so the preflight must too.
    func testScanRecognizesPathMatchedAssetsWithoutContentHashes() throws {
        let root = try makeDirectory(named: "path-matched")
        let source = root.appendingPathComponent("originals", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let cataloged = source.appendingPathComponent("cataloged.jpg")
        try Data("in place".utf8).write(to: cataloged)
        try Data("brand new".utf8).write(to: source.appendingPathComponent("fresh.jpg"))
        let repository = try makeRepository(in: root)
        try repository.upsert(Asset(
            id: .new(),
            originalURL: cataloged,
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(
                size: 8,
                modificationDate: Date(timeIntervalSince1970: 1)
            ),
            availability: .online,
            metadata: AssetMetadata()
        ))

        let preview = try XCTUnwrap(ImportDedupPreview.scan(
            sourceURL: source,
            supportedExtensions: ["jpg"],
            repository: repository
        ))

        XCTAssertEqual(preview.newContentCount, 1)
        XCTAssertEqual(preview.existingContentCount, 1)
    }

    func testScanCollapsesWithinBatchDuplicates() throws {
        let root = try makeDirectory(named: "within-batch")
        let source = root.appendingPathComponent("card", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let shared = Data("the same shot".utf8)
        try shared.write(to: source.appendingPathComponent("a.jpg"))
        try shared.write(to: source.appendingPathComponent("b.jpg"))
        let repository = try makeRepository(in: root)

        let preview = try XCTUnwrap(ImportDedupPreview.scan(
            sourceURL: source,
            supportedExtensions: ["jpg"],
            repository: repository
        ))

        XCTAssertEqual(preview.newContentCount, 1, "a shot appearing twice counts as one new photo")
        XCTAssertEqual(preview.existingContentCount, 1)
    }

    func testScanFlagsReachingTheScanLimit() throws {
        let root = try makeDirectory(named: "scan-limit")
        let source = root.appendingPathComponent("card", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for index in 0..<5 {
            try Data("frame \(index)".utf8).write(to: source.appendingPathComponent("frame\(index).jpg"))
        }
        let repository = try makeRepository(in: root)

        let preview = try XCTUnwrap(ImportDedupPreview.scan(
            sourceURL: source,
            supportedExtensions: ["jpg"],
            repository: repository,
            limit: 3
        ))

        XCTAssertEqual(preview.newContentCount, 3)
        XCTAssertTrue(preview.reachedLimit)
    }
}
