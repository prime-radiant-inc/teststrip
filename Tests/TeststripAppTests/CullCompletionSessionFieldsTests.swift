import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 3: When a formal cull session completes, the unified
// `cullCompletion` (CullCompletionPresentation) carries the session-level
// fields (sessionID, title, picksSetID, remainingSingleAssetIDs) so the ad-hoc
// and formal paths never disagree.
final class CullCompletionSessionFieldsTests: XCTestCase {
    func testCullCompletionCarriesSessionFieldsWhenSessionCompletes() throws {
        let assets = (0..<3).map { index in
            Self.asset(id: "completion-\(index)")
        }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "completion-session-fields",
            assets: assets
        )
        let session = try model.beginCullingSession(named: "Batch 2026")

        // Flag all assets to drive the session to completion. Two picks and
        // one reject — all confirmed (no tentative AI flags).
        model.select(assets[0].id)
        try model.setFlagForSelectedAsset(.pick)
        model.select(assets[2].id)
        try model.setFlagForSelectedAsset(.reject)
        model.select(assets[1].id)
        try model.setFlagForSelectedAsset(.pick)

        let completion = try XCTUnwrap(model.cullCompletion)
        XCTAssertEqual(completion.sessionID, session.id)
        XCTAssertEqual(completion.title, "Batch 2026")
        XCTAssertEqual(completion.picksSetID, AssetSetID(rawValue: "work-output-\(session.id.rawValue)-picks"),
                       "picks set ID should be the culling output set for this session")
        // Regular (non-stack) cull: no remaining singles.
        XCTAssertTrue(completion.remainingSingleAssetIDs.isEmpty)
        // The run-summary counts should agree with the confirmed flags.
        XCTAssertEqual(completion.picks, 2)
        XCTAssertEqual(completion.rejects, 1)
        XCTAssertEqual(completion.undecided, 0)
        _ = repository
    }

    func testCullCompletionIsClearedWhenNewSessionBegins() throws {
        let assets = (0..<2).map { index in
            Self.asset(id: "clear-\(index)")
        }
        let (model, _) = try makeModelWithCatalogAssets(
            named: "completion-clear",
            assets: assets
        )
        try model.beginCullingSession(named: "First Batch")
        // Complete the first session.
        model.select(assets[0].id)
        try model.setFlagForSelectedAsset(.pick)
        model.select(assets[1].id)
        try model.setFlagForSelectedAsset(.reject)
        XCTAssertNotNil(model.cullCompletion)

        // Starting a new session should clear the completion.
        try model.beginCullingSession(named: "Second Batch")

        XCTAssertNil(model.cullCompletion)
    }

    // MARK: - Fixtures

    private static func asset(id: String) -> Asset {
        let metadata = AssetMetadata()
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
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
        return (try AppModel.load(catalog: catalog), repository)
    }
}
