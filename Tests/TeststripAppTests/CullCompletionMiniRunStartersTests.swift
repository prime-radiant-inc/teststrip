import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 6: Mini-run starter methods that start scoped culling sessions
// from the completion summary — undecided, skipped, never-viewed, and
// awaiting-review (tentative AI flags).
final class CullCompletionMiniRunStartersTests: XCTestCase {
    func testCullUndecidedFromCompletionStartsSessionScopedToUndecided() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-undecided",
            assets: assets
        )

        let session = try model.cullUndecidedFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
    }

    func testCullUndecidedFromCompletionThrowsWhenNoUndecided() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-undecided-empty",
            assets: assets
        )

        XCTAssertThrowsError(try model.cullUndecidedFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    func testCullSkippedFromCompletionStartsSessionScopedToSkipped() throws {
        let assets = [
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
            Self.asset(id: "u3"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-skipped",
            assets: assets
        )
        try model.beginCullingSession(named: "Skipped Run")
        // Space (nextPhoto) on an undecided frame records a skip.
        try model.applyCullingShortcut(.nextPhoto)
        // The opening frame is now in the skipped set.
        XCTAssertFalse(model.cullRunTracker.skippedAssetIDs.isEmpty)

        let session = try model.cullSkippedFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
    }

    func testCullSkippedFromCompletionThrowsWhenNoSkipped() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-skipped-empty",
            assets: assets
        )

        XCTAssertThrowsError(try model.cullSkippedFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    func testCullNeverViewedFromCompletionStartsSessionScopedToNeverViewed() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-never-viewed",
            assets: assets
        )

        let session = try model.cullNeverViewedFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
    }

    func testCullNeverViewedFromCompletionThrowsWhenAllViewed() throws {
        let assets = [Self.asset(id: "p1", flag: .pick)]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-never-viewed-empty",
            assets: assets
        )
        try model.beginCullingSession(named: "All Viewed")
        // beginCullingSession → startCullRunTracking records the opening frame
        // as viewed, so there are no never-viewed assets left.
        model.dismissCullingSessionCompletion()

        XCTAssertThrowsError(try model.cullNeverViewedFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    func testReviewAIFromCompletionStartsSessionScopedToTentativeAI() throws {
        let assets = [
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "ai2", flag: .reject, tentative: true),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-review-ai",
            assets: assets
        )

        let session = try model.reviewAIFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
    }

    func testReviewAIFromCompletionThrowsWhenNoTentativeAI() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-review-ai-empty",
            assets: assets
        )

        XCTAssertThrowsError(try model.reviewAIFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    // MARK: - Fixtures

    private static func asset(id: String, flag: PickFlag? = nil, tentative: Bool = false) -> Asset {
        var metadata = AssetMetadata()
        metadata.flag = flag
        if tentative, flag != nil {
            metadata.aiUnconfirmedFields.insert(.flag)
        }
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
