import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 5: CullingProgressSummary gains loud accounting fields
// (viewedCount, skippedCount, neverViewedCount, awaitingReviewCount,
// hiddenByLensCount) for the scope line's prominent coverage readout.
final class CullingProgressSummaryFieldsTests: XCTestCase {
    func testProgressSummaryPopulatesLoudAccountingFields() throws {
        // 5 assets: 2 decided (pick + reject), 1 with tentative AI flag,
        // 2 undecided. The tracker records viewed/skipped as we navigate.
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-summary",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")

        let summary = model.cullingProgressSummary

        // viewedCount: the tracker records the first selected asset on
        // startCullRunTracking, so at least 1.
        XCTAssertGreaterThanOrEqual(summary.viewedCount, 1)
        // neverViewedCount = total - viewed
        XCTAssertEqual(summary.neverViewedCount, model.totalAssetCount - summary.viewedCount)
        // awaitingReviewCount: one asset with tentative AI flag
        XCTAssertEqual(summary.awaitingReviewCount, 1)
        // hiddenByLensCount: 0 when scope is .all (default)
        XCTAssertEqual(summary.hiddenByLensCount, 0)
        // skippedCount starts at 0 (no skips yet)
        XCTAssertEqual(summary.skippedCount, 0)
    }

    func testTentativeAIFlagNeverCountsAsDecided() throws {
        // A tentative AI pick counts as awaiting review, not as a confirmed
        // pick. The provenance invariant: confirmedProjection.flag is nil for
        // tentative flags, so they never drive "decided" math.
        let assets = [
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-tentative",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")

        let summary = model.cullingProgressSummary

        // The tentative pick is not a confirmed pick
        XCTAssertEqual(summary.pickCount, 0)
        // It is awaiting review
        XCTAssertEqual(summary.awaitingReviewCount, 1)
    }

    func testHiddenByLensCountReflectsScope() throws {
        // 4 assets: 1 pick, 1 reject, 2 undecided. Scoping to .unrated hides
        // the decided assets.
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-hidden",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")
        model.cycleCullScope()

        let summary = model.cullingProgressSummary

        // .unrated shows only undecided: 2 of 4 → hidden 2
        XCTAssertEqual(summary.hiddenByLensCount, 2)
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
