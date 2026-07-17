import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Task 8 (culling-flow shell): the in-memory run tracker behind the cull
// completion summary's skipped/neverViewed counts. Viewed is recorded at the
// single selection choke point every culling navigation path funnels through
// (AppModel.selectAssetID); skipped only by the Space (.nextPhoto) arm, and
// only while the departed frame is still undecided (confirmed-flag math).
final class CullRunTrackerTests: XCTestCase {
    // MARK: - Tracker semantics

    func testRecordViewedAndSkippedAccumulateAsSets() {
        var tracker = CullRunTracker()

        tracker.recordViewed(AssetID(rawValue: "a"))
        tracker.recordViewed(AssetID(rawValue: "a"))
        tracker.recordViewed(AssetID(rawValue: "b"))
        tracker.recordSkipped(AssetID(rawValue: "b"))
        tracker.recordSkipped(AssetID(rawValue: "b"))

        XCTAssertEqual(tracker.viewedAssetIDs, [AssetID(rawValue: "a"), AssetID(rawValue: "b")])
        XCTAssertEqual(tracker.skippedAssetIDs, [AssetID(rawValue: "b")])
    }

    func testResetClearsBothSets() {
        var tracker = CullRunTracker()
        tracker.recordViewed(AssetID(rawValue: "a"))
        tracker.recordSkipped(AssetID(rawValue: "b"))

        tracker.reset()

        XCTAssertEqual(tracker.viewedAssetIDs, [])
        XCTAssertEqual(tracker.skippedAssetIDs, [])
    }

    // MARK: - Viewed wiring: every culling navigation path lands in the tracker

    func testCullingNavigationPathsRecordArrivalAsViewed() throws {
        // Four standalone stops (capture times an hour apart, so no two frames
        // auto-group into a burst): drive one arrival through each navigation
        // family — Space, J-fallback, stack-arrow, and direct select (the
        // run-strip click / cull-sidebar click route).
        let assets = (0..<4).map { index in
            Self.asset(id: "stop-\(index)", capturedAt: Date(timeIntervalSince1970: TimeInterval(index) * 3600))
        }
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: assets)

        try model.applyCullingShortcut(.nextPhoto)
        try model.applyCullingShortcut(.nextCandidateInStack)
        try model.applyCullingShortcut(.nextStack)
        model.select(assets[0].id)

        XCTAssertEqual(model.selectedAssetID, assets[0].id)
        XCTAssertEqual(
            model.cullRunTracker.viewedAssetIDs,
            Set(assets.map(\.id))
        )
    }

    // MARK: - Skipped wiring: Space only, undecided departures only

    func testSpaceRecordsDepartedUndecidedFrameAsSkipped() throws {
        let first = Self.asset(id: "undecided-first")
        let second = Self.asset(id: "second")
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second])

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.cullRunTracker.skippedAssetIDs, [first.id])
        XCTAssertTrue(model.cullRunTracker.viewedAssetIDs.contains(second.id))
    }

    func testSpaceOnConfirmedDecidedFrameDoesNotRecordSkip() throws {
        let first = Self.asset(id: "decided-first", flag: .pick)
        let second = Self.asset(id: "second")
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second])

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.cullRunTracker.skippedAssetIDs, [])
    }

    // INVARIANT: a tentative (AI-unconfirmed) flag is not a decision — leaving
    // it with Space is a skip, exactly like an unflagged frame.
    func testSpaceOnTentativeAIFlagRecordsSkip() throws {
        let first = Self.asset(id: "tentative-first", flag: .pick, tentative: true)
        let second = Self.asset(id: "second")
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second])

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.cullRunTracker.skippedAssetIDs, [first.id])
    }

    func testPreviousPhotoDoesNotRecordSkip() throws {
        let first = Self.asset(id: "first")
        let second = Self.asset(id: "second")
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second])

        try model.applyCullingShortcut(.nextPhoto)
        try model.applyCullingShortcut(.previousPhoto)

        // Only the forward Space arm skips; going back is not a skip gesture.
        XCTAssertEqual(model.cullRunTracker.skippedAssetIDs, [first.id])
    }

    // MARK: - Reset wiring: cull-source change, NOT scope cycling

    func testScopeCycleDoesNotResetTracker() throws {
        let first = Self.asset(id: "first")
        let second = Self.asset(id: "second")
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second])
        try model.applyCullingShortcut(.nextPhoto)

        model.cycleCullScope()

        XCTAssertEqual(model.cullRunTracker.skippedAssetIDs, [first.id])
        XCTAssertTrue(model.cullRunTracker.viewedAssetIDs.contains(second.id))
    }

    func testBeginCullingSessionResetsTrackerAndSeedsLandingFrameAsViewed() throws {
        let assets = (0..<3).map { index in
            Self.asset(id: "batch-\(index)")
        }
        let (model, _) = try makeModelWithCatalogAssets(named: "run-tracker-session-reset", assets: assets)
        try model.applyCullingShortcut(.nextPhoto)
        XCTAssertFalse(model.cullRunTracker.skippedAssetIDs.isEmpty)

        try model.beginCullingSession(named: "Fresh Batch")

        XCTAssertEqual(model.cullRunTracker.skippedAssetIDs, [])
        // The frame the new batch landed on is on stage now — it is viewed,
        // so the completion summary's neverViewed set can't include it.
        XCTAssertEqual(
            model.cullRunTracker.viewedAssetIDs,
            model.selectedAssetID.map { [$0] } ?? []
        )
    }

    // MARK: - Fixtures

    private static func asset(
        id: String,
        flag: PickFlag? = nil,
        tentative: Bool = false,
        capturedAt: Date? = nil
    ) -> Asset {
        var metadata = AssetMetadata()
        metadata.flag = flag
        if tentative {
            metadata.aiUnconfirmedFields = [.flag]
        }
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata,
            technicalMetadata: capturedAt.map { capturedAt in
                AssetTechnicalMetadata(
                    pixelWidth: 6000,
                    pixelHeight: 4000,
                    capturedAt: capturedAt,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            }
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
