import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 4: `startCullRun()` is a thin convenience that starts a cull run
// without a custom name, and `cullStartCardPresentation` provides batch stats
// for the ⌘R start card.
final class CullStartRunTests: XCTestCase {
    func testStartCullRunBeginsSessionAndSwitchesToLoupe() throws {
        let assets = (0..<5).map { index in
            Self.asset(id: "start-\(index)")
        }
        let (model, _) = try makeModelWithCatalogAssets(
            named: "start-cull-run",
            assets: assets
        )

        let session = try model.startCullRun()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty, "startCullRun should use a default session name")
    }

    func testCullStartCardPresentationReportsPhotoAndStackCounts() throws {
        let assets = (0..<4).map { index in
            Self.asset(id: "card-\(index)")
        }
        let (model, _) = try makeModelWithCatalogAssets(
            named: "start-card",
            assets: assets
        )

        let card = model.cullStartCardPresentation

        XCTAssertEqual(card.photoCount, 4)
        XCTAssertEqual(card.stackCount, 0, "standalone photos produce no multi-frame stacks")
        XCTAssertEqual(card.autoAdvanceEnabled, model.cullAutoAdvanceEnabled)
        XCTAssertEqual(card.landOnRecommended, model.cullLandOnRecommendedFrame)
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
