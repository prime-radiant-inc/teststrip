import XCTest
@testable import TeststripCore
@testable import TeststripApp

// The Imports sidebar section is backed by the existing unbounded
// `workSessions(kind: .ingest, statuses: [.completed])` query — not the
// mixed-kind, limit-10 `recentWork` cache, which cannot promise three imports.
// The row label derives from the session's createdAt plus its `detail`,
// because an import's `title` and `intent` are both the constant
// "Import photos".
final class ImportSourceScopingTests: XCTestCase {
    func testImportSummariesComeFromEveryCompletedIngestSessionNewestFirst() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-summaries", assets: [])
        for index in 0..<12 {
            try repository.save(makeImportSession(
                id: "import-\(index)",
                detail: "Imported from /Cards/CARD-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index * 100))
            ))
        }
        // A culling session must not appear among the imports.
        try repository.save(WorkSession(
            id: WorkSessionID(rawValue: "cull-1"),
            kind: .culling,
            intent: "Cull the shoot",
            title: "Cull the shoot",
            detail: "Cull the shoot",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            createdAt: Date(timeIntervalSince1970: 9_000),
            updatedAt: Date(timeIntervalSince1970: 9_000)
        ))

        try model.refreshImportSourceSummaries()

        XCTAssertEqual(model.importSourceSummaries.count, 12, "recentWork's limit-10 cache cannot back this section")
        XCTAssertEqual(model.importSourceSummaries.first?.sessionID.rawValue, "import-11")
        XCTAssertFalse(model.importSourceSummaries.contains { $0.sessionID.rawValue == "cull-1" })
    }

    func testImportRowTitleUsesTheSessionDateAndItsFolderDetail() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-title", assets: [])
        try repository.save(makeImportSession(
            id: "import-titled",
            detail: "Imported from /Cards/CARD-A",
            createdAt: Date(timeIntervalSince1970: 1_754_000_000)
        ))

        try model.refreshImportSourceSummaries()

        let summary = try XCTUnwrap(model.importSourceSummaries.first)
        XCTAssertTrue(summary.title.hasSuffix("Imported from /Cards/CARD-A"), summary.title)
        XCTAssertTrue(summary.title.contains(" · "), summary.title)
        XCTAssertNotEqual(summary.title, "Import photos")
    }

    // Import-scoped counts are the smart source's own SetQuery ANDed with
    // `.importBatch(sessionID)` — the shape latestImportFlaggedReviewAssetCount
    // already uses. Never a third expression of the same predicate.
    func testImportChildCountsAreScopedToTheImport() throws {
        let inside = makeAsset(id: "inside", path: "/Photos/Import/inside.jpg", rating: 0)
        let outside = makeAsset(id: "outside", path: "/Photos/Other/outside.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "import-child-counts",
            assets: [inside, outside]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: inside.id, kind: .faceCount, value: .score(2), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: outside.id, kind: .faceCount, value: .score(2), confidence: 0.9, provenance: provenance)
        ])
        let sessionID = WorkSessionID(rawValue: "import-scoped")
        let outputSetID = AssetSetID(rawValue: "work-output-import-scoped")
        try repository.upsert(AssetSet.manual(id: outputSetID, name: "Imported", assetIDs: [inside.id]))
        try repository.save(WorkSession(
            id: sessionID,
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported from /Cards/CARD-A",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSetID],
            issues: [WorkSessionIssue(kind: .skippedSourceFile, sourceURL: URL(fileURLWithPath: "/Cards/CARD-A/bad.raf"), message: "unsupported")],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        let counts = try model.importChildCounts(sessionID: sessionID)

        XCTAssertEqual(counts.facesFound, 1, "the other import's face asset must not count")
        XCTAssertEqual(counts.skippedFiles, 1)
        XCTAssertEqual(counts.previewFailed, 0)
        XCTAssertEqual(counts.likelyIssues, 0)
        XCTAssertFalse(counts.isEmpty)
    }

    func testImportChildCountsAreAllZeroForAnEmptyImport() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-child-empty", assets: [])
        let sessionID = WorkSessionID(rawValue: "import-empty")
        try repository.save(makeImportSession(
            id: sessionID.rawValue,
            detail: "Imported from /Cards/EMPTY",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))

        let counts = try model.importChildCounts(sessionID: sessionID)

        XCTAssertTrue(counts.isEmpty)
    }

    // MARK: - Fixtures

    private func makeImportSession(id: String, detail: String, createdAt: Date) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: detail,
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeAsset(id: String, path: String, rating: Int) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
