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
            createdAt: Date(timeIntervalSince1970: 1_754_000_000),
            completedUnitCount: 4,
            totalUnitCount: 9
        ))

        try model.refreshImportSourceSummaries()

        let summary = try XCTUnwrap(model.importSourceSummaries.first)
        XCTAssertTrue(summary.title.hasSuffix("Imported from /Cards/CARD-A"), summary.title)
        XCTAssertTrue(summary.title.contains(" · "), summary.title)
        XCTAssertNotEqual(summary.title, "Import photos")
        XCTAssertEqual(summary.assetCount, 9, "assetCount prefers totalUnitCount (9) over completedUnitCount (4)")
    }

    func testImportSummaryAssetCountFallsBackToCompletedUnitCountWhenTotalIsNil() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-title-fallback", assets: [])
        try repository.save(makeImportSession(
            id: "import-fallback",
            detail: "Imported from /Cards/CARD-B",
            createdAt: Date(timeIntervalSince1970: 1_754_000_000),
            completedUnitCount: 6,
            totalUnitCount: nil
        ))

        try model.refreshImportSourceSummaries()

        let summary = try XCTUnwrap(model.importSourceSummaries.first)
        XCTAssertEqual(summary.assetCount, 6, "assetCount falls back to completedUnitCount when totalUnitCount is nil")
    }

    // Import-scoped counts are the smart source's own SetQuery ANDed with
    // `.importBatch(sessionID)` — the shape `importChildCounts(sessionID:)`
    // itself already uses for `likelyIssues`/`facesFound`. Never a third
    // expression of the same predicate.
    func testImportChildCountsAreScopedToTheImport() throws {
        let inside = makeAsset(id: "inside", path: "/Photos/Import/inside.jpg", rating: 0)
        let outside = makeAsset(id: "outside", path: "/Photos/Other/outside.jpg", rating: 0)
        // Two low-focus assets inside the import and one outside it: the
        // inside/outside counts (2 vs. 3 catalog-wide) are chosen to differ
        // from facesFound's inside count (1), so a likelyIssues composition
        // that drifted onto facesFound's predicates, or dropped the
        // `.importBatch` scope, would land on the wrong number rather than
        // coincidentally matching.
        let insideIssue = makeAsset(id: "inside-issue", path: "/Photos/Import/inside-issue.jpg", rating: 0)
        let insideIssue2 = makeAsset(id: "inside-issue-2", path: "/Photos/Import/inside-issue-2.jpg", rating: 0)
        let outsideIssue = makeAsset(id: "outside-issue", path: "/Photos/Other/outside-issue.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "import-child-counts",
            assets: [inside, outside, insideIssue, insideIssue2, outsideIssue]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        // The focus family is only ever written by LocalImageMetricsEvaluationProvider
        // (see its `provenance` in Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift);
        // apple-vision never produces a `.focus` signal, so a likely-issue
        // fixture must use this provenance rather than `provenance` above.
        let focusProvenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: inside.id, kind: .faceCount, value: .score(2), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: outside.id, kind: .faceCount, value: .score(2), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: insideIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: focusProvenance),
            EvaluationSignal(assetID: insideIssue2.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: focusProvenance),
            EvaluationSignal(assetID: outsideIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: focusProvenance)
        ])
        let sessionID = WorkSessionID(rawValue: "import-scoped")
        let outputSetID = AssetSetID(rawValue: "work-output-import-scoped")
        try repository.upsert(AssetSet.manual(id: outputSetID, name: "Imported", assetIDs: [inside.id, insideIssue.id, insideIssue2.id]))
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
        XCTAssertEqual(counts.likelyIssues, 2, "the outside import's low-focus asset must not count")
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

    private func makeImportSession(
        id: String,
        detail: String,
        createdAt: Date,
        completedUnitCount: Int = 0,
        totalUnitCount: Int? = nil
    ) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: detail,
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
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
