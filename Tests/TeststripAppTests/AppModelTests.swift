import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class AppModelTests: XCTestCase {
    func testAppModelStartsWithStudioLayoutSections() {
        let model = AppModel.demo()

        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Library"))
        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Work"))
        let librarySection = model.sidebarSections.first { $0.title == "Library" }
        XCTAssertEqual(librarySection?.rows.first { $0.title == "All Photographs" }?.countText, "1")
        let workSection = model.sidebarSections.first { $0.title == "Work" }
        XCTAssertEqual(workSection?.rows.first { $0.title == "Recent" }?.detailText, "No recent work")
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.selectedAsset?.id, model.assets.first?.id)
    }

    func testSidebarSectionCanBeConstructedByPublicClients() {
        let section = SidebarSection(title: "Library", rows: ["All Photographs"])

        XCTAssertEqual(section.title, "Library")
        XCTAssertEqual(section.rowTitles, ["All Photographs"])
    }

    func testWorkActivityShowsProgressOnlyForActiveWorkWithKnownTotal() {
        var activity = AppWorkActivity(
            kind: .previewGeneration,
            status: .running,
            title: "Generate preview",
            detail: "Rendering",
            completedUnitCount: 1,
            totalUnitCount: 8,
            failureCount: 0
        )

        XCTAssertTrue(activity.showsProgress)

        activity.status = .queued
        XCTAssertTrue(activity.showsProgress)

        activity.status = .paused
        XCTAssertTrue(activity.showsProgress)

        activity.status = .completed
        XCTAssertFalse(activity.showsProgress)

        activity.status = .failed
        XCTAssertFalse(activity.showsProgress)

        activity.status = .cancelled
        XCTAssertFalse(activity.showsProgress)

        activity.status = .running
        activity.totalUnitCount = nil
        XCTAssertFalse(activity.showsProgress)
    }

    func testSelectingAssetUpdatesInspector() {
        let first = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: URL(fileURLWithPath: "/Photos/first.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "second"),
            originalURL: URL(fileURLWithPath: "/Photos/second.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 2, modificationDate: Date(timeIntervalSince1970: 2)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        XCTAssertEqual(model.selectedAsset?.id, first.id)

        model.select(second.id)

        XCTAssertEqual(model.selectedAsset?.id, second.id)
    }

    func testOpenAssetInLoupeSelectsAssetAndSwitchesView() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        model.openAssetInLoupe(second.id)

        XCTAssertEqual(model.selectedAsset?.id, second.id)
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testSelectedAssetPositionTextShowsFrameWithinLibrary() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let third = makeAsset(id: "third", size: 3)
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [first, second, third])

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetPositionText, "Frame 2 of 3")
    }

    func testCullingProgressSummaryCountsVisibleDecisions() {
        let pick = makeAsset(id: "pick", path: "/Photos/pick.jpg", rating: 0, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 0, flag: .reject)
        let unreviewed = makeAsset(id: "unreviewed", path: "/Photos/unreviewed.jpg", rating: 0)
        let secondPick = makeAsset(id: "second-pick", path: "/Photos/second-pick.jpg", rating: 0, flag: .pick)
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: [pick, reject, unreviewed, secondPick])

        model.select(unreviewed.id)

        XCTAssertEqual(
            model.cullingProgressSummary,
            CullingProgressSummary(
                selectedPosition: 3,
                positionText: "Frame 3 of 4",
                pickCount: 2,
                rejectCount: 1,
                totalCount: 4
            )
        )
        XCTAssertEqual(model.cullingProgressSummary.reviewedCount, 3)
    }

    func testCullingProgressSummaryCountsEntireCatalogScope() throws {
        var assets: [Asset] = []
        for index in 0..<125 {
            let flag: PickFlag?
            switch index {
            case 121, 124:
                flag = .pick
            case 122:
                flag = .reject
            default:
                flag = nil
            }
            assets.append(makeAsset(id: "asset-\(index)", path: "/Photos/asset-\(index).jpg", rating: 0, flag: flag))
        }
        let (model, _) = try makeModelWithCatalogAssets(named: "culling-summary-entire-catalog", assets: assets)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 125)
        XCTAssertEqual(model.cullingProgressSummary.pickCount, 2)
        XCTAssertEqual(model.cullingProgressSummary.rejectCount, 1)
        XCTAssertEqual(model.cullingProgressSummary.reviewedCount, 3)
    }

    func testCullingProgressSummaryCountsCurrentFilteredScope() throws {
        var assets: [Asset] = []
        for index in 0..<130 {
            let isFilteredAsset = index < 125
            let flag: PickFlag?
            switch index {
            case 121, 124, 128:
                flag = .pick
            case 122:
                flag = .reject
            default:
                flag = nil
            }
            assets.append(makeAsset(
                id: "filtered-\(index)",
                path: "/Photos/filtered-\(index).jpg",
                rating: isFilteredAsset ? 5 : 0,
                flag: flag
            ))
        }
        let (model, _) = try makeModelWithCatalogAssets(named: "culling-summary-filtered-catalog", assets: assets)

        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 125)
        XCTAssertEqual(model.cullingProgressSummary.pickCount, 2)
        XCTAssertEqual(model.cullingProgressSummary.rejectCount, 1)
        XCTAssertEqual(model.cullingProgressSummary.reviewedCount, 3)
    }

    func testCullingProgressSummaryCountsExplicitSavedSetScope() throws {
        let directory = try makeTemporaryDirectory(named: "culling-summary-explicit-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        var assets: [Asset] = []
        for index in 0..<130 {
            let flag: PickFlag?
            switch index {
            case 121, 124, 128:
                flag = .pick
            case 122:
                flag = .reject
            default:
                flag = nil
            }
            assets.append(makeAsset(id: "manual-\(index)", path: "/Photos/manual-\(index).jpg", rating: 0, flag: flag))
        }
        let manualSet = AssetSet.manual(
            id: AssetSetID(rawValue: "manual-cull"),
            name: "Manual Cull",
            assetIDs: Array(assets.prefix(125).map(\.id))
        )
        try repository.upsert(assets)
        try repository.upsert(manualSet)
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
        let model = try AppModel.load(catalog: catalog)
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Saved Sets" }?.rows.first { $0.title == "Manual Cull" })

        try model.selectSidebarRow(row)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 125)
        XCTAssertEqual(model.cullingProgressSummary.pickCount, 2)
        XCTAssertEqual(model.cullingProgressSummary.rejectCount, 1)
        XCTAssertEqual(model.cullingProgressSummary.reviewedCount, 3)
    }

    func testSelectNextAssetMovesSelectionForwardThroughLoadedAssets() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        model.selectNextAsset()
        XCTAssertEqual(model.selectedAsset?.id, second.id)

        model.selectNextAsset()
        XCTAssertEqual(model.selectedAsset?.id, second.id)
    }

    func testSelectPreviousAssetMovesSelectionBackwardThroughLoadedAssets() {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])
        model.select(second.id)

        model.selectPreviousAsset()
        XCTAssertEqual(model.selectedAsset?.id, first.id)

        model.selectPreviousAsset()
        XCTAssertEqual(model.selectedAsset?.id, first.id)
    }

    func testCompareAssetsReturnWindowAroundSelectionWhenSelectionLeavesCurrentSet() {
        let assets = (0..<10).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .compare, assets: assets)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[0..<8].map(\.id))

        model.select(assets[9].id)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[2..<10].map(\.id))
    }

    func testCompareAssetsUseCandidateStackAroundSelectedCaptureTime() {
        let captureStart = Date(timeIntervalSince1970: 1_900_000_000)
        let assets = [
            makeAsset(id: "lead-0", size: 1),
            makeAsset(id: "lead-1", size: 2),
            makeAsset(id: "lead-2", size: 3),
            makeAsset(id: "lead-3", size: 4),
            makeAsset(
                id: "stack-0",
                path: "/Photos/stack-0.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart)
            ),
            makeAsset(
                id: "stack-1",
                path: "/Photos/stack-1.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(1))
            ),
            makeAsset(
                id: "stack-2",
                path: "/Photos/stack-2.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(2))
            ),
            makeAsset(
                id: "later",
                path: "/Photos/later.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(12))
            )
        ]
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)

        model.select(assets[5].id)
        model.selectedView = .compare

        XCTAssertEqual(model.compareAssets().map(\.id), assets[4..<7].map(\.id))
        XCTAssertEqual(model.compareGroupKind(), .candidateStack)
    }

    func testCompareAssetsLimitLargeCandidateStackAroundSelection() {
        let captureStart = Date(timeIntervalSince1970: 1_900_000_100)
        let assets = (0..<10).map { index in
            makeAsset(
                id: "stack-\(index)",
                path: "/Photos/stack-\(index).jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(TimeInterval(index)))
            )
        }
        let model = AppModel(sidebarSections: [], selectedView: .compare, assets: assets)

        model.select(assets[9].id)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[2..<10].map(\.id))
        XCTAssertEqual(model.compareGroupKind(), .candidateStack)
    }

    func testCompareCandidateStackSplitsDifferentFolders() {
        let captureStart = Date(timeIntervalSince1970: 1_900_000_200)
        let assets = [
            makeAsset(id: "lead-0", size: 1),
            makeAsset(id: "lead-1", size: 2),
            makeAsset(id: "lead-2", size: 3),
            makeAsset(id: "lead-3", size: 4),
            makeAsset(
                id: "same-folder-0",
                path: "/Photos/Job/same-folder-0.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart)
            ),
            makeAsset(
                id: "same-folder-1",
                path: "/Photos/Job/same-folder-1.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(1))
            ),
            makeAsset(
                id: "other-folder",
                path: "/Photos/Other/other-folder.jpg",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(2))
            )
        ]
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)

        model.select(assets[5].id)
        model.selectedView = .compare

        XCTAssertEqual(model.compareAssets().map(\.id), assets[4..<6].map(\.id))
        XCTAssertEqual(model.compareGroupKind(), .candidateStack)
    }

    func testCompareAssetsUseVisualSimilaritySignalsAcrossFoldersAndCaptureTimes() throws {
        let captureStart = Date(timeIntervalSince1970: 1_900_000_250)
        let first = makeAsset(
            id: "visual-similarity-first",
            path: "/Photos/Job/first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: captureStart)
        )
        let similar = makeAsset(
            id: "visual-similarity-similar",
            path: "/Photos/Other/similar.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(60))
        )
        let different = makeAsset(
            id: "visual-similarity-different",
            path: "/Photos/Job/different.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(120))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-visual-similarity",
            assets: [first, similar, different]
        )
        let provenance = ProviderProvenance(provider: "local-http-model", model: "embedding", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .visualSimilarity, value: .vector([0.1, 0.2, 0.3]), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: similar.id, kind: .visualSimilarity, value: .vector([0.11, 0.2, 0.29]), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: different.id, kind: .visualSimilarity, value: .vector([0.8, 0.1, 0.1]), confidence: 0.9, provenance: provenance)
        ])
        model.selectedView = .compare
        model.select(similar.id)

        XCTAssertEqual(model.compareAssets().map(\.id), [first.id, similar.id])
        XCTAssertEqual(model.compareGroupKind(), .candidateStack)
    }

    func testCompareAssetsDoNotTreatColorPaletteVectorsAsNearDuplicateSimilarity() throws {
        let captureStart = Date(timeIntervalSince1970: 1_900_000_260)
        let first = makeAsset(
            id: "color-vector-first",
            path: "/Photos/Job/first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: captureStart)
        )
        let similarColor = makeAsset(
            id: "color-vector-similar",
            path: "/Photos/Other/similar.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: captureStart.addingTimeInterval(60))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-color-vector-not-similarity",
            assets: [first, similarColor]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .colorPalette, value: .vector([0.1, 0.2, 0.3]), confidence: 1.0, provenance: provenance),
            EvaluationSignal(assetID: similarColor.id, kind: .colorPalette, value: .vector([0.11, 0.2, 0.29]), confidence: 1.0, provenance: provenance)
        ])
        model.selectedView = .compare
        model.select(similarColor.id)

        XCTAssertEqual(model.compareAssets().map(\.id), [first.id, similarColor.id])
        XCTAssertEqual(model.compareGroupKind(), .nearbyFrames)
    }

    func testCompareGroupKindTreatsPersistedWorkStackSetAsCandidateStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_900_000_300)
        let lead = makeAsset(
            id: "compare-persisted-stack-lead",
            path: "/Photos/Stack/lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let alternate = makeAsset(
            id: "compare-persisted-stack-alternate",
            path: "/Photos/Other/alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-persisted-work-stack",
            assets: [lead, alternate]
        )
        let stackSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-cull-session-1"),
            name: "Cull Stack 1",
            assetIDs: [lead.id, alternate.id]
        )
        try repository.upsert(stackSet)
        try model.applyAssetSet(id: stackSet.id)
        model.select(alternate.id)
        model.selectedView = .compare

        XCTAssertEqual(model.compareAssets().map(\.id), [lead.id, alternate.id])
        XCTAssertEqual(model.compareGroupKind(), .candidateStack)
    }

    func testCompareAssetsStayStableWhenSelectingAssetInsideCurrentCompareSet() {
        let assets = (0..<6).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)
        model.selectedView = .compare
        let initialCompareIDs = model.compareAssets().map(\.id)

        model.select(assets[3].id)

        XCTAssertEqual(model.compareAssets().map(\.id), initialCompareIDs)
    }

    func testComparePreviewRequestIDChangesWhenSelectionChangesInsideSameWindow() {
        let assets = (0..<10).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .compare, assets: assets)
        let initialRequestID = ComparePreviewRequestID.make(for: model)

        model.select(assets[1].id)

        XCTAssertEqual(model.compareAssets().map(\.id), assets[0..<8].map(\.id))
        XCTAssertNotEqual(ComparePreviewRequestID.make(for: model), initialRequestID)
    }

    func testKeepComparePrimaryRejectsCurrentCompareAlternatesOnly() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-action-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-group-action",
            assets: assets
        )
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[1].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[2].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[3].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[4].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[5].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[6].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[7].id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: assets[8].id).metadata.flag)
        XCTAssertEqual(model.assets[0].metadata.flag, .reject)
        XCTAssertEqual(model.assets[1].metadata.flag, .pick)
        XCTAssertEqual(model.assets[2].metadata.flag, .reject)
        XCTAssertEqual(model.assets[3].metadata.flag, .reject)
        XCTAssertEqual(model.assets[4].metadata.flag, .reject)
        XCTAssertEqual(model.assets[5].metadata.flag, .reject)
        XCTAssertEqual(model.assets[6].metadata.flag, .reject)
        XCTAssertEqual(model.assets[7].metadata.flag, .reject)
        XCTAssertNil(model.assets[8].metadata.flag)
    }

    func testKeepRecommendedCompareAssetRejectsCurrentCompareAlternatesOnly() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-recommended-action-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-recommended-group-action",
            assets: assets
        )
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepCompareAssetAndRejectAlternates(assetID: assets[3].id)

        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[1].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[2].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[3].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[4].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[5].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[6].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[7].id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: assets[8].id).metadata.flag)
        XCTAssertEqual(model.statusMessage, "Kept compare-recommended-action-3.jpg; rejected 7 alternates")
    }

    func testKeepAllCompareAssetsMarksCurrentCompareSetAsPicksOnly() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-keep-all-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-keep-all-action",
            assets: assets
        )
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepAllCompareAssets()

        for asset in assets[0..<8] {
            XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .pick)
        }
        XCTAssertNil(try repository.asset(id: assets[8].id).metadata.flag)
        for asset in model.assets[0..<8] {
            XCTAssertEqual(asset.metadata.flag, .pick)
        }
        XCTAssertNil(model.assets[8].metadata.flag)
    }

    func testBeginManualCullingFromCompareSetCreatesWorkStackScope() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-manual-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-manual-cull",
            assets: assets
        )
        model.selectedView = .compare
        model.select(assets[1].id)

        let session = try model.beginManualCullingFromCompareSet()

        let stackSetID = try XCTUnwrap(session.inputSetIDs.first)
        XCTAssertTrue(stackSetID.rawValue.hasPrefix("work-stack-\(session.id.rawValue)-"))
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: stackSetID)), assets[0..<8].map(\.id))
        XCTAssertEqual(model.selectedAssetSetID, stackSetID)
        XCTAssertEqual(model.assets.map(\.id), assets[0..<8].map(\.id))
        XCTAssertEqual(model.selectedAssetID, assets[1].id)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(session.kind, .culling)
        XCTAssertEqual(session.intent, "Manually cull current compare set")
        XCTAssertEqual(session.totalUnitCount, 8)
        XCTAssertEqual(model.selectedCullingStackScope?.assetIDs, assets[0..<8].map(\.id))
        XCTAssertNil(try repository.asset(id: assets[0].id).metadata.flag)
        XCTAssertNil(try repository.asset(id: assets[8].id).metadata.flag)
    }

    func testLibraryCountTextShowsLoadedAndTotalWhenGridIsLimited() {
        let asset = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: URL(fileURLWithPath: "/Photos/first.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [asset], totalAssetCount: 3)

        XCTAssertEqual(model.libraryCountText, "Showing 1 of 3 photographs")
    }

    func testLibraryTitleReflectsSelectedCatalogScope() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        XCTAssertEqual(model.libraryTitle, "All Photographs")

        model.folderFilterText = "/Volumes/NAS/Wedding/Ceremony/"
        XCTAssertEqual(model.libraryTitle, "Ceremony")

        model.evaluationKindFilter = .faceQuality
        model.folderFilterText = ""
        XCTAssertEqual(model.libraryTitle, "Face Quality Signal")

        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "ceremony-picks"),
            name: "Ceremony Picks",
            assetIDs: []
        )
        model.savedAssetSets = [set]
        model.selectedAssetSetID = set.id
        XCTAssertEqual(model.libraryTitle, "Ceremony Picks")
    }

    func testCatalogDisplayNameUsesCatalogRootName() throws {
        let directory = try makeTemporaryDirectory(named: "catalog-display-name")
        let root = directory.appendingPathComponent("Wedding Archive", isDirectory: true)
        let previewCache = PreviewCache(root: root.appendingPathComponent("Previews", isDirectory: true))
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let catalog = AppCatalog(
            paths: AppCatalogPaths(
                root: root,
                catalogURL: root.appendingPathComponent("catalog.sqlite"),
                previewCacheRoot: root.appendingPathComponent("Previews", isDirectory: true)
            ),
            repository: CatalogRepository(database: database),
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [], catalog: catalog)

        XCTAssertEqual(model.catalogDisplayName, "Wedding Archive")
    }

    func testRatingSelectedAssetUpdatesCatalogAndLoadedAsset() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-rating")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "rating-target"),
            originalURL: URL(fileURLWithPath: "/Photos/rating.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setRatingForSelectedAsset(4)

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 4)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 4)
    }

    func testFlagSelectedAssetUpdatesCatalogAndLoadedAsset() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-flag")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "flag-target"),
            originalURL: URL(fileURLWithPath: "/Photos/flag.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setFlagForSelectedAsset(.reject)

        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .reject)
    }

    func testRatingSelectedAssetWritesXmpSidecarWhenOriginalIsAvailable() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "xmp-write-target"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setRatingForSelectedAsset(5)

        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.rating, 5)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
    }

    func testKeywordTextSelectedAssetNormalizesKeywordsAndWritesXmpSidecar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-keyword-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "keyword-xmp-write-target"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setKeywordTextForSelectedAsset(" Patagonia, keeper, , Patagonia ")

        let expectedKeywords = ["Patagonia", "keeper"]
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, expectedKeywords)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testRemovingKeywordFromSelectedAssetWritesCatalogAndXmpSidecar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-keyword-remove-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "keyword-remove-xmp-write-target"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["Patagonia", "keeper", "travel"])
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.removeKeywordFromSelectedAsset("keeper")

        let expectedKeywords = ["Patagonia", "travel"]
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, expectedKeywords)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testPortableTextMetadataSelectedAssetWritesXmpSidecar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-portable-text-xmp-write")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "portable-text-xmp-write-target"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        try model.setCaptionForSelectedAsset("  Fitz Roy sunrise  ")
        try model.setCreatorForSelectedAsset("  Jesse  ")
        try model.setCopyrightForSelectedAsset("  Copyright Jesse  ")

        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        let catalogMetadata = try repository.asset(id: asset.id).metadata
        let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata
        XCTAssertEqual(model.selectedAsset?.metadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(model.selectedAsset?.metadata.creator, "Jesse")
        XCTAssertEqual(model.selectedAsset?.metadata.copyright, "Copyright Jesse")
        XCTAssertEqual(catalogMetadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(catalogMetadata.creator, "Jesse")
        XCTAssertEqual(catalogMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(sidecarMetadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(sidecarMetadata.creator, "Jesse")
        XCTAssertEqual(sidecarMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testVisibleBatchMetadataAppliesPortableFieldsAndWritesXmpSidecars() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-visible-batch-metadata")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let firstURL = photosDirectory.appendingPathComponent("first.cr2")
        let secondURL = photosDirectory.appendingPathComponent("second.cr2")
        try Data("first original raw bytes".utf8).write(to: firstURL)
        try Data("second original raw bytes".utf8).write(to: secondURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset(
            id: AssetID(rawValue: "visible-batch-metadata-first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["existing"])
        )
        let second = Asset(
            id: AssetID(rawValue: "visible-batch-metadata-second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["existing"])
        )
        try repository.upsert([first, second])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        let appliedCount = try model.applyVisibleBatchMetadata(
            keywordText: " mountain, existing, ",
            caption: "  Patagonia selects  ",
            creator: "  Jesse  ",
            copyright: "  Copyright Jesse  "
        )

        XCTAssertEqual(appliedCount, 2)
        XCTAssertEqual(model.statusMessage, "Applied batch metadata to 2 photos")
        for asset in [first, second] {
            let catalogMetadata = try repository.asset(id: asset.id).metadata
            let sidecarURL = asset.originalURL.appendingPathExtension("xmp")
            let sidecarData = try Data(contentsOf: sidecarURL)
            let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata

            XCTAssertEqual(catalogMetadata.keywords, ["existing", "mountain"])
            XCTAssertEqual(catalogMetadata.caption, "Patagonia selects")
            XCTAssertEqual(catalogMetadata.creator, "Jesse")
            XCTAssertEqual(catalogMetadata.copyright, "Copyright Jesse")
            XCTAssertEqual(sidecarMetadata.keywords, ["existing", "mountain"])
            XCTAssertEqual(sidecarMetadata.caption, "Patagonia selects")
            XCTAssertEqual(sidecarMetadata.creator, "Jesse")
            XCTAssertEqual(sidecarMetadata.copyright, "Copyright Jesse")
            XCTAssertEqual(
                try repository.lastMetadataSyncFingerprint(assetID: asset.id),
                XMPSidecarStore.fingerprint(for: sidecarData)
            )
        }
        XCTAssertEqual(try Data(contentsOf: firstURL), Data("first original raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("second original raw bytes".utf8))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
    }

    func testSelectedBatchMetadataAppliesOnlySelectedAssetsAndWritesXmpSidecars() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-selected-batch-metadata")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let firstURL = photosDirectory.appendingPathComponent("first.cr2")
        let secondURL = photosDirectory.appendingPathComponent("second.cr2")
        let outsideURL = photosDirectory.appendingPathComponent("outside.cr2")
        try Data("first original raw bytes".utf8).write(to: firstURL)
        try Data("second original raw bytes".utf8).write(to: secondURL)
        try Data("outside original raw bytes".utf8).write(to: outsideURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset(
            id: AssetID(rawValue: "selected-batch-metadata-first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["existing"])
        )
        let second = Asset(
            id: AssetID(rawValue: "selected-batch-metadata-second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["existing"])
        )
        let outside = Asset(
            id: AssetID(rawValue: "selected-batch-metadata-outside"),
            originalURL: outsideURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 12, modificationDate: Date(timeIntervalSince1970: 12)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["existing"])
        )
        try repository.upsert([first, second, outside])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.setBatchSelection(first.id, isSelected: true)
        model.setBatchSelection(second.id, isSelected: true)

        let appliedCount = try model.applySelectedBatchMetadata(
            keywordText: "portfolio, existing",
            caption: "  Selected keepers  ",
            creator: "  Jesse  ",
            copyright: ""
        )

        XCTAssertEqual(model.selectedBatchAssetCount, 2)
        XCTAssertEqual(appliedCount, 2)
        XCTAssertEqual(model.statusMessage, "Applied batch metadata to 2 photos")
        for asset in [first, second] {
            let catalogMetadata = try repository.asset(id: asset.id).metadata
            let sidecarData = try Data(contentsOf: asset.originalURL.appendingPathExtension("xmp"))
            let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata

            XCTAssertEqual(catalogMetadata.keywords, ["existing", "portfolio"])
            XCTAssertEqual(catalogMetadata.caption, "Selected keepers")
            XCTAssertEqual(catalogMetadata.creator, "Jesse")
            XCTAssertEqual(sidecarMetadata.keywords, ["existing", "portfolio"])
            XCTAssertEqual(sidecarMetadata.caption, "Selected keepers")
            XCTAssertEqual(sidecarMetadata.creator, "Jesse")
        }
        XCTAssertEqual(try repository.asset(id: outside.id).metadata.keywords, ["existing"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.originalURL.appendingPathExtension("xmp").path))
        XCTAssertEqual(try Data(contentsOf: firstURL), Data("first original raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("second original raw bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: outsideURL), Data("outside original raw bytes".utf8))
    }

    func testWorkerBackedBatchMetadataRefreshesXmpStateOnceForBatch() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-batch-metadata")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        var metadataSyncStateQueryCount = 0
        database.rowQueryObserver = { sql in
            if sql.contains("FROM metadata_sync_state") {
                metadataSyncStateQueryCount += 1
            }
        }
        let repository = CatalogRepository(database: database)
        let assets = [
            makeAsset(id: "worker-batch-first", size: 10),
            makeAsset(id: "worker-batch-second", size: 11),
            makeAsset(id: "worker-batch-third", size: 12)
        ]
        try repository.upsert(assets)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
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
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: assets,
            totalAssetCount: assets.count,
            catalog: catalog,
            workerSupervisor: supervisor
        )

        metadataSyncStateQueryCount = 0
        let appliedCount = try model.applyVisibleBatchMetadata(
            keywordText: "portfolio",
            caption: "  Worker batch  ",
            creator: "",
            copyright: ""
        )

        XCTAssertEqual(appliedCount, 3)
        XCTAssertLessThanOrEqual(metadataSyncStateQueryCount, 9)
        XCTAssertEqual(model.pendingMetadataSyncCount, 3)
        XCTAssertEqual(Set(model.pendingMetadataSyncItems.map(\.assetID)), Set(assets.map(\.id)))
        XCTAssertEqual(Set(try repository.pendingMetadataSyncItems().map(\.assetID)), Set(assets.map(\.id)))
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }.count, 3)
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: assets[0].id)])
        XCTAssertEqual(try repository.asset(id: assets[2].id).metadata.caption, "Worker batch")
    }

    func testBatchSelectionDoesNotReplacePrimarySelection() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-selected-batch-primary")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset(
            id: AssetID(rawValue: "selected-batch-primary-first"),
            originalURL: photosDirectory.appendingPathComponent("first.cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "selected-batch-primary-second"),
            originalURL: photosDirectory.appendingPathComponent("second.cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert([first, second])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        XCTAssertEqual(model.selectedAssetID, first.id)

        model.setBatchSelection(second.id, isSelected: true)

        XCTAssertEqual(model.selectedBatchAssetCount, 1)
        XCTAssertEqual(model.selectedAssetID, first.id)
    }

    func testRangeBatchSelectionUsesPrimarySelectionAsAnchor() throws {
        let first = makeAsset(id: "range-first", path: "/Photos/range-first.jpg", rating: 1)
        let second = makeAsset(id: "range-second", path: "/Photos/range-second.jpg", rating: 2)
        let third = makeAsset(id: "range-third", path: "/Photos/range-third.jpg", rating: 3)
        let fourth = makeAsset(id: "range-fourth", path: "/Photos/range-fourth.jpg", rating: 4)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "batch-range-selection",
            assets: [first, second, third, fourth]
        )
        model.select(second.id)

        model.selectBatchRange(to: fourth.id)
        let savedSet = try model.saveSelectedAssetAsManualSet(named: "Range")

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertEqual(model.selectedBatchAssetCount, 3)
        XCTAssertFalse(model.isBatchSelected(first.id))
        XCTAssertTrue(model.isBatchSelected(second.id))
        XCTAssertTrue(model.isBatchSelected(third.id))
        XCTAssertTrue(model.isBatchSelected(fourth.id))
        XCTAssertEqual(savedSet.membership, .manual([second.id, third.id, fourth.id]))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
    }

    func testBatchSelectionSurvivesLoadedPageChangesInCatalogOrder() throws {
        let model = try makeModelWithSeededCatalog(named: "batch-selection-cross-page", count: 121)
        model.setBatchSelection(AssetID(rawValue: "asset-0"), isSelected: true)

        try model.loadMoreAssets()
        model.setBatchSelection(AssetID(rawValue: "asset-120"), isSelected: true)
        let savedSet = try model.saveSelectedAssetAsManualSet(named: "Cross Page")

        XCTAssertEqual(model.selectedBatchAssetCount, 2)
        XCTAssertTrue(model.isBatchSelected(AssetID(rawValue: "asset-0")))
        XCTAssertTrue(model.isBatchSelected(AssetID(rawValue: "asset-120")))
        XCTAssertEqual(savedSet.membership, .manual([
            AssetID(rawValue: "asset-0"),
            AssetID(rawValue: "asset-120")
        ]))
    }

    func testBatchSelectionPrunesAssetsOutsideReloadedScope() throws {
        let keeper = makeAsset(id: "batch-scope-keeper", path: "/Photos/batch-scope-keeper.jpg", rating: 5)
        let outside = makeAsset(id: "batch-scope-outside", path: "/Photos/batch-scope-outside.jpg", rating: 1)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "batch-selection-filter-scope",
            assets: [keeper, outside]
        )
        model.setBatchSelection(keeper.id, isSelected: true)
        model.setBatchSelection(outside.id, isSelected: true)

        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.selectedBatchAssetCount, 1)
        XCTAssertTrue(model.isBatchSelected(keeper.id))
        XCTAssertFalse(model.isBatchSelected(outside.id))
    }

    func testBatchSelectionKeepsMatchingAssetsOutsideReloadedPage() throws {
        let model = try makeModelWithSeededCatalog(named: "batch-selection-filtered-cross-page", count: 121)
        let firstKeeperID = AssetID(rawValue: "asset-5")
        let laterKeeperID = AssetID(rawValue: "asset-119")
        model.setBatchSelection(firstKeeperID, isSelected: true)

        try model.loadMoreAssets()
        model.setBatchSelection(laterKeeperID, isSelected: true)
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.selectedBatchAssetCount, 2)
        XCTAssertTrue(model.isBatchSelected(firstKeeperID))
        XCTAssertTrue(model.isBatchSelected(laterKeeperID))
    }

    func testCurrentScopeBatchMetadataAppliesBeyondLoadedPageAndWritesXmpSidecars() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-current-scope-batch-metadata")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let matchingAssets = try (0..<121).map { index in
            let url = photosDirectory.appendingPathComponent("matching-\(index).cr2")
            try Data("matching original \(index)".utf8).write(to: url)
            return Asset(
                id: AssetID(rawValue: "current-scope-batch-matching-\(index)"),
                originalURL: url,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 10), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 10))),
                availability: .online,
                metadata: AssetMetadata(colorLabel: .green)
            )
        }
        let outsideURL = photosDirectory.appendingPathComponent("outside.cr2")
        try Data("outside original".utf8).write(to: outsideURL)
        let outsideAsset = Asset(
            id: AssetID(rawValue: "current-scope-batch-outside"),
            originalURL: outsideURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 200, modificationDate: Date(timeIntervalSince1970: 200)),
            availability: .online,
            metadata: AssetMetadata(colorLabel: .red)
        )
        try repository.upsert(matchingAssets + [outsideAsset])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()

        XCTAssertEqual(model.totalAssetCount, matchingAssets.count)
        XCTAssertLessThan(model.assets.count, matchingAssets.count)
        XCTAssertFalse(model.assets.contains { $0.id == matchingAssets.last?.id })

        let appliedCount = try model.applyCurrentScopeBatchMetadata(
            keywordText: "portfolio",
            caption: "  Green selects  ",
            creator: "  Jesse  ",
            copyright: ""
        )

        XCTAssertEqual(appliedCount, matchingAssets.count)
        XCTAssertEqual(model.statusMessage, "Applied batch metadata to 121 photos")
        let unloadedAsset = try XCTUnwrap(matchingAssets.last)
        let unloadedMetadata = try repository.asset(id: unloadedAsset.id).metadata
        let unloadedSidecarData = try Data(contentsOf: unloadedAsset.originalURL.appendingPathExtension("xmp"))
        let unloadedSidecarMetadata = try XMPPacket.parse(unloadedSidecarData).metadata
        XCTAssertEqual(unloadedMetadata.keywords, ["portfolio"])
        XCTAssertEqual(unloadedMetadata.caption, "Green selects")
        XCTAssertEqual(unloadedMetadata.creator, "Jesse")
        XCTAssertEqual(unloadedSidecarMetadata.keywords, ["portfolio"])
        XCTAssertEqual(unloadedSidecarMetadata.caption, "Green selects")
        XCTAssertEqual(try repository.asset(id: outsideAsset.id).metadata.keywords, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideAsset.originalURL.appendingPathExtension("xmp").path))
    }

    func testCurrentScopeBatchMetadataAppliesExplicitSetBeyondLoadedPage() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-current-scope-batch-metadata-set")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let setAssets = try (0..<121).map { index in
            let url = photosDirectory.appendingPathComponent("set-\(index).cr2")
            try Data("set original \(index)".utf8).write(to: url)
            return Asset(
                id: AssetID(rawValue: "current-scope-set-\(index)"),
                originalURL: url,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 10), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 10))),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
        let outsideURL = photosDirectory.appendingPathComponent("outside-set.cr2")
        try Data("outside original".utf8).write(to: outsideURL)
        let outsideAsset = Asset(
            id: AssetID(rawValue: "current-scope-set-outside"),
            originalURL: outsideURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 200, modificationDate: Date(timeIntervalSince1970: 200)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(setAssets + [outsideAsset])
        let assetSet = AssetSet.manual(
            id: AssetSetID(rawValue: "current-scope-set"),
            name: "Current Scope Set",
            assetIDs: setAssets.map(\.id)
        )
        try repository.upsert(assetSet)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        try model.applyAssetSet(id: assetSet.id)

        XCTAssertEqual(model.totalAssetCount, setAssets.count)
        XCTAssertLessThan(model.assets.count, setAssets.count)
        XCTAssertFalse(model.assets.contains { $0.id == setAssets.last?.id })

        let appliedCount = try model.applyCurrentScopeBatchMetadata(
            keywordText: "portfolio",
            caption: "",
            creator: "",
            copyright: "  Copyright Jesse  "
        )

        XCTAssertEqual(appliedCount, setAssets.count)
        let unloadedAsset = try XCTUnwrap(setAssets.last)
        let unloadedMetadata = try repository.asset(id: unloadedAsset.id).metadata
        let unloadedSidecarData = try Data(contentsOf: unloadedAsset.originalURL.appendingPathExtension("xmp"))
        let unloadedSidecarMetadata = try XMPPacket.parse(unloadedSidecarData).metadata
        XCTAssertEqual(unloadedMetadata.keywords, ["portfolio"])
        XCTAssertEqual(unloadedMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(unloadedSidecarMetadata.keywords, ["portfolio"])
        XCTAssertEqual(unloadedSidecarMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(try repository.asset(id: outsideAsset.id).metadata.keywords, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideAsset.originalURL.appendingPathExtension("xmp").path))
    }

    func testRatingSelectedAssetQueuesXmpWhenSidecarCannotBeWritten() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "xmp-pending")

        try model.setRatingForSelectedAsset(5)

        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [pending])
    }

    func testLoadExposesMetadataSyncConflicts() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-conflict")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "conflict-target"),
            originalURL: URL(fileURLWithPath: "/Photos/conflict.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        )
        try repository.recordMetadataSyncConflict(conflict)

        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        XCTAssertEqual(model.metadataSyncConflictItems, [conflict])
    }

    func testSelectingMetadataConflictSidebarRowLoadsConflictedAssets() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-conflict-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let conflicted = makeAsset(id: "conflicted", path: "/Photos/conflicted.jpg", rating: 0)
        let clean = makeAsset(id: "clean", path: "/Photos/clean.jpg", rating: 0)
        try repository.upsert([conflicted, clean])
        try repository.recordMetadataSyncConflict(MetadataSyncItem(
            assetID: conflicted.id,
            sidecarURL: conflicted.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        let syncSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sync" })
        XCTAssertEqual(syncSection.rowTitles, ["XMP Conflicts"])
        XCTAssertEqual(syncSection.rows.first?.countText, "1")
        XCTAssertEqual(syncSection.rows.first?.tone, .destructive)

        try model.selectSidebarRow(try XCTUnwrap(syncSection.rows.first))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.metadataSyncConflictFilter)
        XCTAssertEqual(model.assets.map(\.id), [conflicted.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSelectingPendingMetadataSyncSidebarRowLoadsPendingAssets() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-pending-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let pending = makeAsset(id: "pending-xmp", path: "/Photos/pending.jpg", rating: 0)
        let clean = makeAsset(id: "clean-xmp", path: "/Photos/clean.jpg", rating: 0)
        try repository.upsert([pending, clean])
        try repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: pending.id,
            sidecarURL: pending.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        let syncSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sync" })
        XCTAssertEqual(syncSection.rowTitles, ["XMP Pending"])
        XCTAssertEqual(syncSection.rows.first?.countText, "1")
        XCTAssertEqual(syncSection.rows.first?.tone, .warning)

        try model.selectSidebarRow(try XCTUnwrap(syncSection.rows.first))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.metadataSyncPendingFilter)
        XCTAssertEqual(model.assets.map(\.id), [pending.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSelectingAssetLoadsPendingMetadataSyncOutsideStateSample() throws {
        let directory = try makeTemporaryDirectory(named: "selected-pending-xmp-outside-sample")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<(AppModel.metadataSyncStateDisplayLimit + 1)).map { index in
            makeAsset(id: "pending-xmp-sample-\(index)", path: "/Photos/pending-\(index).cr2", rating: 0)
        }
        let selectedOutsideSample = try XCTUnwrap(assets.last)
        try repository.upsert(assets)
        for asset in assets {
            try repository.recordMetadataSyncPending(MetadataSyncItem(
                assetID: asset.id,
                sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
                catalogGeneration: 1,
                lastSyncedFingerprint: "old"
            ))
        }
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        XCTAssertEqual(model.pendingMetadataSyncItems.count, AppModel.metadataSyncStateDisplayLimit)

        model.select(selectedOutsideSample.id)

        XCTAssertEqual(model.selectedPendingMetadataSyncItem?.assetID, selectedOutsideSample.id)
        XCTAssertEqual(model.pendingMetadataSyncCount, AppModel.metadataSyncStateDisplayLimit + 1)
    }

    func testResolveSelectedMetadataConflictUsingCatalogOverwritesSidecar() throws {
        let catalogMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["catalog"])
        let sidecarMetadata = AssetMetadata(rating: 2, colorLabel: .red, flag: .reject, keywords: ["sidecar"])
        let (model, repository, asset, originalURL, sidecarURL) = try makeModelWithXMPConflict(
            named: "resolve-conflict-catalog",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )

        try model.resolveSelectedMetadataConflictUsingCatalog()

        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, catalogMetadata)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, catalogMetadata)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [])
        XCTAssertEqual(model.metadataSyncConflictItems, [])
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testResolvingMetadataConflictRemovesAssetFromConflictFilter() throws {
        let catalogMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["catalog"])
        let sidecarMetadata = AssetMetadata(rating: 2, colorLabel: .red, flag: .reject, keywords: ["sidecar"])
        let (model, _, asset, _, _) = try makeModelWithXMPConflict(
            named: "resolve-conflict-filter",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )
        model.metadataSyncConflictFilter = true
        try model.reload()
        XCTAssertEqual(model.assets.map(\.id), [asset.id])

        try model.resolveSelectedMetadataConflictUsingCatalog()

        XCTAssertEqual(model.assets, [])
        XCTAssertEqual(model.totalAssetCount, 0)
        XCTAssertNil(model.sidebarSections.first { $0.title == "Sync" })
    }

    func testResolveSelectedMetadataConflictUsingSidecarImportsSidecarMetadata() throws {
        let catalogMetadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["catalog"])
        let sidecarMetadata = AssetMetadata(rating: 2, colorLabel: .red, flag: .reject, keywords: ["sidecar"])
        let (model, repository, asset, originalURL, sidecarURL) = try makeModelWithXMPConflict(
            named: "resolve-conflict-sidecar",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )
        XCTAssertEqual(reviewQueueCount("Picks", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Rejects", in: model), "0")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "1")

        try model.resolveSelectedMetadataConflictUsingSidecar()

        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, sidecarMetadata)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, sidecarMetadata)
        XCTAssertEqual(model.selectedAsset?.metadata, sidecarMetadata)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [])
        XCTAssertEqual(model.metadataSyncConflictItems, [])
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(reviewQueueCount("Picks", in: model), "0")
        XCTAssertEqual(reviewQueueCount("Rejects", in: model), "1")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "0")
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testResolveSelectedMetadataConflictMergesMissingSidecarFieldsIntoCatalog() throws {
        let catalogMetadata = AssetMetadata(
            rating: 0,
            colorLabel: .green,
            flag: nil,
            keywords: ["catalog", "Shared"],
            caption: nil,
            creator: "Catalog Creator"
        )
        let sidecarMetadata = AssetMetadata(
            rating: 4,
            colorLabel: .red,
            flag: .pick,
            keywords: ["sidecar", "shared"],
            caption: "Sidecar caption",
            creator: "Sidecar Creator",
            copyright: "Sidecar copyright"
        )
        let expectedMetadata = AssetMetadata(
            rating: 4,
            colorLabel: .green,
            flag: .pick,
            keywords: ["catalog", "Shared", "sidecar"],
            caption: "Sidecar caption",
            creator: "Catalog Creator",
            copyright: "Sidecar copyright"
        )
        let (model, repository, asset, originalURL, sidecarURL) = try makeModelWithXMPConflict(
            named: "resolve-conflict-merge-missing",
            catalogMetadata: catalogMetadata,
            sidecarMetadata: sidecarMetadata
        )

        try model.resolveSelectedMetadataConflictByMergingMissingSidecarFields()

        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, expectedMetadata)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, expectedMetadata)
        XCTAssertEqual(model.selectedAsset?.metadata, expectedMetadata)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(try repository.metadataSyncConflictItems(), [])
        XCTAssertEqual(model.metadataSyncConflictItems, [])
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testSelectedMetadataConflictSidecarMetadataParsesSelectedSidecar() throws {
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["sidecar"])
        let (model, _, asset, _, _) = try makeModelWithXMPConflict(
            named: "selected-conflict-sidecar-metadata",
            catalogMetadata: AssetMetadata(rating: 4, colorLabel: .red, keywords: ["catalog"]),
            sidecarMetadata: sidecarMetadata
        )

        model.select(asset.id)

        XCTAssertEqual(model.selectedMetadataSyncConflictSidecarMetadata, sidecarMetadata)
    }

    func testRatingSelectedAssetDispatchesWorkerMetadataSyncWhenSupervisorConfigured() throws {
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "app-model-worker-xmp",
            assetID: "worker-xmp-target"
        )

        try model.setRatingForSelectedAsset(5)

        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [pending])
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appendingPathExtension("xmp").path))
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Writing XMP sidecar")
    }

    @MainActor
    func testCompletedWorkerMetadataSyncClearsPendingMetadataSync() async throws {
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "app-model-worker-xmp-complete",
            assetID: "worker-xmp-complete-target"
        )

        try model.setRatingForSelectedAsset(5)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: try repository.asset(id: asset.id).metadata).xmlData()
        try sidecarData.write(to: sidecarURL)
        try repository.markMetadataSynced(
            assetID: asset.id,
            sidecarURL: sidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "synced metadata for frame.cr2"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
    }

    func testSelectingAssetQueuesWorkerMetadataSyncCheckWhenSupervisorConfigured() throws {
        let first = makeAsset(id: "selection-xmp-first", size: 1)
        let second = makeAsset(id: "selection-xmp-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "selection-worker-xmp-check",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: second.id)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Checking XMP sidecar")
    }

    func testSelectingAssetDoesNotSynchronouslyWriteXmpWithoutWorker() throws {
        let directory = try makeTemporaryDirectory(named: "selection-no-worker-xmp")
        let firstURL = directory.appendingPathComponent("first.dng")
        let secondURL = directory.appendingPathComponent("second.dng")
        try Data("first original".utf8).write(to: firstURL)
        try Data("second original".utf8).write(to: secondURL)
        let first = Asset(
            id: AssetID(rawValue: "selection-no-worker-first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: firstURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "selection-no-worker-second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: secondURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "selection-no-worker-xmp-catalog",
            assets: [first, second]
        )

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.appendingPathExtension("xmp").path))
    }

    func testSelectingAssetDoesNotQueueDuplicateActiveMetadataSyncCheck() throws {
        let first = makeAsset(id: "duplicate-selection-xmp-first", size: 1)
        let second = makeAsset(id: "duplicate-selection-xmp-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "duplicate-selection-worker-xmp-check",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        model.select(second.id)

        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: second.id)])
    }

    @MainActor
    func testSelectingThroughAssetsCancelsStaleQueuedMetadataSyncChecks() async throws {
        let first = makeAsset(id: "stale-selection-xmp-first", size: 1)
        let second = makeAsset(id: "stale-selection-xmp-second", size: 2)
        let third = makeAsset(id: "stale-selection-xmp-third", size: 3)
        let fourth = makeAsset(id: "stale-selection-xmp-fourth", size: 4)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "stale-selection-worker-xmp-check",
            assets: [first, second, third, fourth],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        let runningItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        model.select(third.id)
        model.select(fourth.id)

        let queuedChecks = model.backgroundWorkQueue.queuedItems.filter { $0.title == "Check XMP" }
        XCTAssertEqual(queuedChecks.count, 1)
        XCTAssertTrue(queuedChecks[0].id.rawValue.hasPrefix("xmp-check-\(fourth.id.rawValue)-"))
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: second.id)])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: runningItemID,
            message: "metadata up to date for second.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: runningItemID, in: model)
        XCTAssertEqual(try transport.commands(), [
            .syncMetadata(assetID: second.id),
            .syncMetadata(assetID: fourth.id)
        ])

        let fourthItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: fourthItemID,
            message: "metadata up to date for fourth.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: fourthItemID, in: model)
        XCTAssertNil(model.visibleWorkActivity)
    }

    @MainActor
    func testCompletedSelectionMetadataCheckDoesNotReplaceVisibleActivity() async throws {
        let first = makeAsset(id: "completed-selection-xmp-first", size: 1)
        let second = makeAsset(id: "completed-selection-xmp-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "completed-selection-worker-xmp-check",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "metadata up to date for second.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertNil(model.visibleWorkActivity)
    }

    @MainActor
    func testCompletedMetadataSyncRefreshesLoadedAssetMetadata() async throws {
        let first = makeAsset(id: "completed-xmp-refresh-first", size: 1)
        let second = makeAsset(id: "completed-xmp-refresh-second", size: 2)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "completed-xmp-refresh",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        model.select(second.id)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["sidecar"])
        try repository.updateMetadata(assetID: second.id) { metadata in
            metadata = sidecarMetadata
        }

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "imported metadata for completed-xmp-refresh-second.jpg"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.selectedAsset?.metadata, sidecarMetadata)
        XCTAssertEqual(model.assets.first { $0.id == second.id }?.metadata, sidecarMetadata)
    }

    func testLoadQueuesPendingMetadataSyncWhenSupervisorConfigured() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let originalURL = photoFolder.appendingPathComponent("frame.cr2")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "pending-worker-xmp-target"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: nil
        )
        try repository.recordMetadataSyncPending(pending)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let model = try AppModel.load(
            catalog: AppCatalog(
                paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
                repository: repository,
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
                importService: LibraryImportService(
                    ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                    previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
                )
            ),
            workerSupervisor: supervisor
        )

        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Writing XMP sidecar")
    }

    func testLoadSkipsPendingMetadataSyncForUnavailableOriginal() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp-offline")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let originalURL = photoFolder.appendingPathComponent("frame.cr2")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "pending-worker-xmp-offline"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .offline,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: nil
        )
        try repository.recordMetadataSyncPending(pending)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let model = try AppModel.load(
            catalog: AppCatalog(
                paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
                repository: repository,
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
                importService: LibraryImportService(
                    ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                    previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
                )
            ),
            workerSupervisor: supervisor
        )

        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }, [])
        XCTAssertEqual(try transport.commands(), [])
    }

    func testLoadBoundsPendingMetadataSyncRetries() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-pending-worker-xmp-limit")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<205).map { index in
            Asset(
                id: AssetID(rawValue: "pending-worker-xmp-limit-\(index)"),
                originalURL: photoFolder.appendingPathComponent("frame-\(index).cr2"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata(rating: 4)
            )
        }
        try repository.upsert(assets)
        for asset in assets {
            try repository.recordMetadataSyncPending(MetadataSyncItem(
                assetID: asset.id,
                sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
                catalogGeneration: 1,
                lastSyncedFingerprint: nil
            ))
        }
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let model = try AppModel.load(
            catalog: AppCatalog(
                paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
                repository: repository,
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
                importService: LibraryImportService(
                    ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                    previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
                )
            ),
            workerSupervisor: supervisor
        )

        XCTAssertEqual(model.pendingMetadataSyncItems.count, AppModel.metadataSyncStateDisplayLimit)
        XCTAssertEqual(model.pendingMetadataSyncCount, 205)
        let syncSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sync" })
        XCTAssertEqual(syncSection.rows.first { $0.title == "XMP Pending" }?.countText, "205")
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }.count, 200)
    }

    func testLoadBoundsPreviewGenerationQueueStateSample() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-preview-queue-state-limit")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<205).map { index in
            Asset(
                id: AssetID(rawValue: "preview-state-limit-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/frame-\(index).cr2"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
        try repository.upsert(assets)
        for asset in assets {
            try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        }
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )

        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.previewGenerationQueueStates.count, AppModel.previewGenerationQueueStateDisplayLimit)
        XCTAssertEqual(try repository.previewGenerationQueueStates().count, 205)
    }

    func testRetrySelectedPendingMetadataSyncWritesSidecarWithoutWorker() throws {
        let directory = try makeTemporaryDirectory(named: "retry-selected-pending-xmp")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        let originalData = Data("original raw bytes".utf8)
        try originalData.write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "retry-selected-pending-xmp"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 5, keywords: ["keeper"])
        )
        try repository.upsert(asset)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            lastSyncedFingerprint: nil
        )
        try repository.recordMetadataSyncPending(pending)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        XCTAssertTrue(model.canRetrySelectedMetadataSync)
        try model.retrySelectedMetadataSync()

        let sidecarData = try Data(contentsOf: pending.sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.rating, 5)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.keywords, ["keeper"])
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
    }

    func testRetrySelectedPendingMetadataSyncQueuesWorkerCommand() throws {
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "retry-selected-pending-worker-xmp",
            assetID: "retry-selected-pending-worker-xmp"
        )
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            lastSyncedFingerprint: nil
        )
        try repository.recordMetadataSyncPending(pending)
        model.pendingMetadataSyncItems = [pending]

        XCTAssertTrue(model.canRetrySelectedMetadataSync)
        try model.retrySelectedMetadataSync()

        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .xmpSync)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Writing XMP sidecar")
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [pending])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.sidecarURL.path))
    }

    func testRetryPendingMetadataSyncInCurrentScopeQueuesOnlyRetryableItems() throws {
        let fixture = try makePendingMetadataSyncScopeModel(named: "retry-pending-xmp-scope")
        fixture.model.metadataSyncPendingFilter = true

        let queuedCount = try fixture.model.retryPendingMetadataSyncInCurrentScope()

        XCTAssertEqual(queuedCount, 1)
        XCTAssertEqual(try fixture.transport.commands(), [
            .syncMetadata(assetID: fixture.retryableAssetID)
        ])
        XCTAssertEqual(fixture.model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }.count, 1)
    }

    func testRetryPendingMetadataSyncInCurrentScopeDoesNotDuplicateActiveWork() throws {
        let fixture = try makePendingMetadataSyncScopeModel(named: "retry-pending-xmp-duplicates")
        fixture.model.metadataSyncPendingFilter = true

        XCTAssertEqual(try fixture.model.retryPendingMetadataSyncInCurrentScope(), 1)
        XCTAssertEqual(try fixture.model.retryPendingMetadataSyncInCurrentScope(), 0)

        XCTAssertEqual(try fixture.transport.commands(), [
            .syncMetadata(assetID: fixture.retryableAssetID)
        ])
        XCTAssertEqual(fixture.model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }.count, 1)
    }

    func testRetryPendingMetadataSyncInCurrentScopeRequiresWorker() throws {
        let fixture = try makePendingMetadataSyncScopeModel(
            named: "retry-pending-xmp-missing-worker",
            includeWorker: false
        )
        fixture.model.metadataSyncPendingFilter = true

        XCTAssertThrowsError(try fixture.model.retryPendingMetadataSyncInCurrentScope())
        XCTAssertEqual(fixture.model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }, [])
    }

    func testCanRetryPendingMetadataSyncInCurrentScopeRequiresPendingFilterAndRetryableVisibleItem() throws {
        let fixture = try makePendingMetadataSyncScopeModel(named: "can-retry-pending-xmp-scope")

        XCTAssertFalse(fixture.model.canRetryPendingMetadataSyncInCurrentScope)

        fixture.model.metadataSyncPendingFilter = true
        XCTAssertTrue(fixture.model.canRetryPendingMetadataSyncInCurrentScope)

        try fixture.model.retryPendingMetadataSyncInCurrentScope()
        XCTAssertFalse(fixture.model.canRetryPendingMetadataSyncInCurrentScope)
    }

    func testCanRetryPendingMetadataSyncInCurrentScopeRequiresWorker() throws {
        let fixture = try makePendingMetadataSyncScopeModel(
            named: "can-retry-pending-xmp-missing-worker",
            includeWorker: false
        )
        fixture.model.metadataSyncPendingFilter = true

        XCTAssertFalse(fixture.model.canRetryPendingMetadataSyncInCurrentScope)
    }

    func testRatingCullingCommandUpdatesSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "rating-command")

        try model.applyCullingCommand(.rating(5))

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
    }

    func testFlagCullingCommandUpdatesSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "flag-command")

        try model.applyCullingCommand(.pick)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .pick)

        try model.applyCullingCommand(.clearFlag)
        XCTAssertNil(model.selectedAsset?.metadata.flag)

        try model.applyCullingCommand(.reject)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .reject)
    }

    func testColorLabelCullingCommandUpdatesSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "color-label-command")

        try model.applyCullingCommand(.colorLabel(.green))
        XCTAssertEqual(model.selectedAsset?.metadata.colorLabel, .green)

        try model.applyCullingCommand(.colorLabel(nil))
        XCTAssertNil(model.selectedAsset?.metadata.colorLabel)
        XCTAssertNil(try repository.asset(id: asset.id).metadata.colorLabel)
    }

    func testCullingShortcutMovesSelectionThroughLoadedAssets() throws {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        try model.applyCullingShortcut(.nextPhoto)
        XCTAssertEqual(model.selectedAsset?.id, second.id)

        try model.applyCullingShortcut(.previousPhoto)
        XCTAssertEqual(model.selectedAsset?.id, first.id)
    }

    func testCullingShortcutAppliesMetadataToSelectedAsset() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "shortcut-metadata")

        try model.applyCullingShortcut(.rating(5))
        XCTAssertEqual(model.selectedAsset?.metadata.rating, 5)

        try model.applyCullingShortcut(.colorLabel(.green))
        XCTAssertEqual(model.selectedAsset?.metadata.colorLabel, .green)

        try model.applyCullingShortcut(.reject)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.colorLabel, .green)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .reject)
    }

    func testCullingShortcutAdvancesAfterRatingSelectedAsset() throws {
        let directory = try makeTemporaryDirectory(named: "culling-shortcut-advance")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 2, repository: repository)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        let firstID = AssetID(rawValue: "asset-0")
        let secondID = AssetID(rawValue: "asset-1")

        try model.applyCullingShortcut(.rating(5))

        XCTAssertEqual(try repository.asset(id: firstID).metadata.rating, 5)
        XCTAssertEqual(model.selectedAssetID, secondID)
    }

    func testKeepingSelectedStackFrameRejectsAlternatesAndAdvancesPastStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "stack-first",
            path: "/Photos/Job/stack-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let selected = makeAsset(
            id: "stack-selected",
            path: "/Photos/Job/stack-selected.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let alternate = makeAsset(
            id: "stack-alternate",
            path: "/Photos/Job/stack-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let next = makeAsset(
            id: "stack-next",
            path: "/Photos/Other/stack-next.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(4))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "keep-selected-stack-frame",
            assets: [first, selected, alternate, next]
        )
        model.select(selected.id)

        try model.keepSelectedStackFrameAndRejectAlternates()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: selected.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: next.id).metadata.flag)
        XCTAssertEqual(model.assets.map(\.metadata.flag), [.reject, .pick, .reject, nil])
        XCTAssertEqual(model.selectedAssetID, next.id)
    }

    func testCullingShortcutAcceptsSelectedStackFrame() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "shortcut-stack-first",
            path: "/Photos/Job/shortcut-stack-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let selected = makeAsset(
            id: "shortcut-stack-selected",
            path: "/Photos/Job/shortcut-stack-selected.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let alternate = makeAsset(
            id: "shortcut-stack-alternate",
            path: "/Photos/Job/shortcut-stack-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let next = makeAsset(
            id: "shortcut-stack-next",
            path: "/Photos/Other/shortcut-stack-next.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(4))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "accept-selected-stack-shortcut",
            assets: [first, selected, alternate, next]
        )
        model.select(selected.id)

        try model.applyCullingShortcut(.acceptStackSelection)

        XCTAssertEqual(try repository.asset(id: first.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: selected.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .reject)
        XCTAssertEqual(model.selectedAssetID, next.id)
    }

    func testCullingShortcutAcceptStackSelectionNoOpsOutsideStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "shortcut-accept-stackless-first",
            path: "/Photos/Job/shortcut-accept-stackless-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let second = makeAsset(
            id: "shortcut-accept-stackless-second",
            path: "/Photos/Job/shortcut-accept-stackless-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(5))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "accept-stack-shortcut-outside-stack",
            assets: [first, second]
        )
        model.select(first.id)

        try model.applyCullingShortcut(.acceptStackSelection)

        XCTAssertEqual(model.selectedAssetID, first.id)
        XCTAssertNil(try repository.asset(id: first.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: second.id).metadata.flag)
    }

    func testCullingShortcutAcceptsPersistedStackSetWithoutTimeAdjacency() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(
            id: "persisted-shortcut-lead",
            path: "/Photos/Stack/lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let alternate = makeAsset(
            id: "persisted-shortcut-alternate",
            path: "/Photos/Other/alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "persisted-stack-shortcut",
            assets: [lead, alternate]
        )
        let stackSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-cull-session-1"),
            name: "Cull Stack 1",
            assetIDs: [lead.id, alternate.id]
        )
        try repository.upsert(stackSet)
        try repository.save(cullingSession(id: "cull-session", inputSetIDs: [stackSet.id], totalUnitCount: 2))
        try model.applyAssetSet(id: stackSet.id)
        model.select(alternate.id)

        try model.applyCullingShortcut(.acceptStackSelection)

        XCTAssertEqual(try repository.asset(id: lead.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, alternate.id)
    }

    func testAcceptingPersistedStackSelectionUpdatesCullingSessionProgress() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "persisted-stack-progress",
            sessionID: "progress-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstAlternate.id)

        try fixture.model.applyCullingShortcut(.acceptStackSelection)

        let session = try fixture.repository.session(id: WorkSessionID(rawValue: "progress-session"))
        XCTAssertEqual(session.completedUnitCount, 2)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.detail, "Reviewed 2 of 4 frames · 1 pick · 1 reject")
        XCTAssertEqual(fixture.model.recentWork.first?.id, "progress-session")
        XCTAssertEqual(fixture.model.recentWork.first?.detail, "Reviewed 2 of 4 frames · 1 pick · 1 reject")
        XCTAssertEqual(fixture.model.recentWork.first?.completedUnitCount, 2)
        XCTAssertEqual(fixture.model.recentWork.first?.totalUnitCount, 4)
        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondLead.id)
    }

    func testKeepingAllFramesInPersistedStackMarksEveryFrameAsPickAndAdvancesProgress() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "persisted-stack-keep-all",
            sessionID: "keep-all-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstAlternate.id)

        try fixture.model.keepAllFramesInSelectedCullingStack()

        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstLead.id).metadata.flag, .pick)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstAlternate.id).metadata.flag, .pick)
        XCTAssertNil(try fixture.repository.asset(id: fixture.secondLead.id).metadata.flag)
        XCTAssertNil(try fixture.repository.asset(id: fixture.secondAlternate.id).metadata.flag)

        let session = try fixture.repository.session(id: WorkSessionID(rawValue: "keep-all-session"))
        XCTAssertEqual(session.completedUnitCount, 2)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(fixture.model.recentWork.first?.id, "keep-all-session")
        XCTAssertEqual(fixture.model.recentWork.first?.completedUnitCount, 2)
        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondLead.id)
    }

    func testKeepingTopRankedFramesInPersistedStackPicksRankedFramesRejectsTheRestAndAdvancesProgress() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "top-ranked-first",
            path: "/Photos/Stack/top-ranked-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let second = makeAsset(
            id: "top-ranked-second",
            path: "/Photos/Stack/top-ranked-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let third = makeAsset(
            id: "top-ranked-third",
            path: "/Photos/Stack/top-ranked-third.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2))
        )
        let fourth = makeAsset(
            id: "top-ranked-fourth",
            path: "/Photos/Stack/top-ranked-fourth.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(3))
        )
        let next = makeAsset(
            id: "top-ranked-next",
            path: "/Photos/Stack/top-ranked-next.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(20))
        )
        let nextAlternate = makeAsset(
            id: "top-ranked-next-alternate",
            path: "/Photos/Stack/top-ranked-next-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(21))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "keep-top-ranked-persisted-stack",
            assets: [first, second, third, fourth, next, nextAlternate]
        )
        let firstSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-top-ranked-session-1"),
            name: "Cull Stack 1",
            assetIDs: [first.id, second.id, third.id, fourth.id]
        )
        let secondSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-top-ranked-session-2"),
            name: "Cull Stack 2",
            assetIDs: [next.id, nextAlternate.id]
        )
        try repository.upsert(firstSet)
        try repository.upsert(secondSet)
        try repository.save(cullingSession(id: "top-ranked-session", inputSetIDs: [firstSet.id, secondSet.id], totalUnitCount: 6))
        try model.applyAssetSet(id: firstSet.id)
        model.select(second.id)

        try model.keepTopRankedFramesInSelectedCullingStack(assetIDs: [third.id, second.id])

        XCTAssertEqual(try repository.asset(id: first.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: second.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: third.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: fourth.id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: next.id).metadata.flag)
        XCTAssertEqual(model.assets.map(\.metadata.flag), [nil, nil])

        let session = try repository.session(id: WorkSessionID(rawValue: "top-ranked-session"))
        XCTAssertEqual(session.completedUnitCount, 4)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(model.recentWork.first?.id, "top-ranked-session")
        XCTAssertEqual(model.recentWork.first?.completedUnitCount, 4)
        XCTAssertEqual(model.selectedAssetSetID, secondSet.id)
        XCTAssertEqual(model.selectedAssetID, next.id)
    }

    func testAcceptingFinalPersistedStackSelectionCompletesCullingSession() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "persisted-stack-completion",
            sessionID: "complete-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)
        try fixture.model.applyCullingShortcut(.acceptStackSelection)

        let session = try fixture.repository.session(id: WorkSessionID(rawValue: "complete-session"))
        XCTAssertEqual(session.completedUnitCount, 4)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(fixture.model.recentWork.first?.id, "complete-session")
        XCTAssertEqual(fixture.model.recentWork.first?.status, .completed)
        XCTAssertEqual(fixture.model.recentWork.first?.completedUnitCount, 4)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstLead.id).metadata.flag, .pick)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstAlternate.id).metadata.flag, .reject)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.secondLead.id).metadata.flag, .pick)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.secondAlternate.id).metadata.flag, .reject)

        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try fixture.repository.assetSet(id: outputSetID)), [fixture.firstLead.id, fixture.secondLead.id])

        try fixture.model.applyWorkSession(id: session.id)

        XCTAssertEqual(fixture.model.selectedAssetSetID, outputSetID)
        XCTAssertEqual(fixture.model.assets.map(\.id), [fixture.firstLead.id, fixture.secondLead.id])
    }

    func testSelectedCullingStackScopeUsesPersistedStackSetMembership() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(
            id: "persisted-scope-lead",
            path: "/Photos/Stack/lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let alternate = makeAsset(
            id: "persisted-scope-alternate",
            path: "/Photos/Other/alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "persisted-stack-scope",
            assets: [lead, alternate]
        )
        let stackSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-cull-session-1"),
            name: "Cull Stack 1",
            assetIDs: [lead.id, alternate.id]
        )
        let provenance = ProviderProvenance(
            provider: "local-image-metrics",
            model: "sharpness",
            version: "1",
            settingsHash: "default"
        )
        let leadSignal = EvaluationSignal(
            assetID: lead.id,
            kind: .focus,
            value: .score(0.72),
            confidence: 0.84,
            provenance: provenance
        )
        let alternateSignal = EvaluationSignal(
            assetID: alternate.id,
            kind: .focus,
            value: .score(0.93),
            confidence: 0.89,
            provenance: provenance
        )
        try repository.upsert(stackSet)
        try repository.save(cullingSession(id: "cull-session", inputSetIDs: [stackSet.id], totalUnitCount: 2))
        try repository.recordEvaluationSignals([leadSignal, alternateSignal])
        try model.applyAssetSet(id: stackSet.id)
        model.select(alternate.id)

        let scope = try XCTUnwrap(model.selectedCullingStackScope)
        XCTAssertEqual(scope.assetIDs, [lead.id, alternate.id])
        XCTAssertEqual(scope.stackIndex, 1)
        XCTAssertEqual(scope.stackCount, 1)
        XCTAssertEqual(scope.rationaleText, "Saved stack from culling session")
        XCTAssertEqual(model.selectedCullingStackEvaluationSignals()[lead.id], [leadSignal])
        XCTAssertEqual(model.selectedCullingStackEvaluationSignals()[alternate.id], [alternateSignal])
    }

    func testCullingShortcutMovesBetweenPersistedStackSets() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstLead = makeAsset(
            id: "persisted-nav-first-lead",
            path: "/Photos/Stack/first-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstAlternate = makeAsset(
            id: "persisted-nav-first-alternate",
            path: "/Photos/Other/first-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let secondLead = makeAsset(
            id: "persisted-nav-second-lead",
            path: "/Photos/Stack/second-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(120))
        )
        let secondAlternate = makeAsset(
            id: "persisted-nav-second-alternate",
            path: "/Photos/Other/second-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(180))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "persisted-stack-navigation",
            assets: [firstLead, firstAlternate, secondLead, secondAlternate]
        )
        let firstSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-cull-session-1"),
            name: "Cull Stack 1",
            assetIDs: [firstLead.id, firstAlternate.id]
        )
        let secondSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-cull-session-2"),
            name: "Cull Stack 2",
            assetIDs: [secondLead.id, secondAlternate.id]
        )
        try repository.upsert(firstSet)
        try repository.upsert(secondSet)
        try repository.save(cullingSession(id: "cull-session", inputSetIDs: [firstSet.id, secondSet.id], totalUnitCount: 4))
        let firstAlternateSignal = EvaluationSignal(
            assetID: firstAlternate.id,
            kind: .focus,
            value: .score(0.91),
            confidence: 0.88,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "sharpness", version: "1", settingsHash: "default")
        )
        try repository.recordEvaluationSignals([firstAlternateSignal])
        try model.applyAssetSet(id: firstSet.id)
        model.select(firstAlternate.id)

        XCTAssertEqual(
            model.selectedCullingStackScope,
            CullingStackScope(
                assetIDs: [firstLead.id, firstAlternate.id],
                stackIndex: 1,
                stackCount: 2,
                rationaleText: "Saved stack from culling session"
            )
        )
        XCTAssertEqual(model.selectedCullingStackEvaluationSignals(), [
            firstLead.id: [],
            firstAlternate.id: [firstAlternateSignal]
        ])

        try model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(model.selectedAssetSetID, secondSet.id)
        XCTAssertEqual(model.assets.map(\.id), [secondLead.id, secondAlternate.id])
        XCTAssertEqual(model.selectedAssetID, secondLead.id)
        XCTAssertEqual(
            model.selectedCullingStackScope,
            CullingStackScope(
                assetIDs: [secondLead.id, secondAlternate.id],
                stackIndex: 2,
                stackCount: 2,
                rationaleText: "Saved stack from culling session"
            )
        )

        try model.applyCullingShortcut(.previousStack)

        XCTAssertEqual(model.selectedAssetSetID, firstSet.id)
        XCTAssertEqual(model.assets.map(\.id), [firstLead.id, firstAlternate.id])
        XCTAssertEqual(model.selectedAssetID, firstLead.id)
    }

    func testCullingShortcutMovesBetweenLoadedStacks() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstStackFirst = makeAsset(
            id: "shortcut-first-stack-first",
            path: "/Photos/Job/shortcut-first-stack-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstStackSecond = makeAsset(
            id: "shortcut-first-stack-second",
            path: "/Photos/Job/shortcut-first-stack-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let singleton = makeAsset(
            id: "shortcut-stack-singleton",
            path: "/Photos/Job/shortcut-stack-singleton.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(5))
        )
        let secondStackFirst = makeAsset(
            id: "shortcut-second-stack-first",
            path: "/Photos/Job/shortcut-second-stack-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(10))
        )
        let secondStackSecond = makeAsset(
            id: "shortcut-second-stack-second",
            path: "/Photos/Job/shortcut-second-stack-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(11))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "stack-navigation-shortcuts",
            assets: [firstStackFirst, firstStackSecond, singleton, secondStackFirst, secondStackSecond]
        )
        model.select(firstStackSecond.id)

        try model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(model.selectedAssetID, secondStackFirst.id)

        model.select(singleton.id)
        try model.applyCullingShortcut(.previousStack)

        XCTAssertEqual(model.selectedAssetID, firstStackFirst.id)
    }

    func testCullingStackShortcutsIgnoreCatalogsWithoutLoadedStacks() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "shortcut-stackless-first",
            path: "/Photos/Job/shortcut-stackless-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let second = makeAsset(
            id: "shortcut-stackless-second",
            path: "/Photos/Job/shortcut-stackless-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(5))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "stack-navigation-without-stacks",
            assets: [first, second]
        )
        model.select(second.id)

        try model.applyCullingShortcut(.nextStack)
        XCTAssertEqual(model.selectedAssetID, second.id)

        try model.applyCullingShortcut(.previousStack)
        XCTAssertEqual(model.selectedAssetID, second.id)
    }

    func testCullingShortcutLoadsNextPageWhenAdvancingPastLoadedAssets() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-next-page", count: 121)
        model.select(AssetID(rawValue: "asset-119"))

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-120"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-120"))
        XCTAssertFalse(model.hasMoreAssets)
    }

    func testCullingShortcutLoadsPreviousPageWhenMovingBeforeLoadedAssets() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-previous-page", count: 360)
        try model.loadMoreAssets()
        try model.loadMoreAssets()
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-120"))
        model.select(AssetID(rawValue: "asset-120"))

        try model.applyCullingShortcut(.previousPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-119"))
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-0"))
        XCTAssertTrue(model.hasMoreAssets)
    }

    func testCullingShortcutInterpretsKeyboardKeys() {
        XCTAssertEqual(CullingShortcut(key: .rightArrow), .nextPhoto)
        XCTAssertEqual(CullingShortcut(key: .leftArrow), .previousPhoto)
        XCTAssertEqual(CullingShortcut(key: .upArrow), .previousStack)
        XCTAssertEqual(CullingShortcut(key: .downArrow), .nextStack)
        XCTAssertEqual(CullingShortcut(key: .character(" ")), .nextPhoto)
        XCTAssertEqual(CullingShortcut(key: .returnKey), .acceptStackSelection)
        XCTAssertEqual(CullingShortcut(key: .character("5")), .rating(5))
        XCTAssertEqual(CullingShortcut(key: .character("6")), .colorLabel(.red))
        XCTAssertEqual(CullingShortcut(key: .character("7")), .colorLabel(.yellow))
        XCTAssertEqual(CullingShortcut(key: .character("8")), .colorLabel(.green))
        XCTAssertEqual(CullingShortcut(key: .character("9")), .colorLabel(.blue))
        XCTAssertEqual(CullingShortcut(key: .character("v")), .colorLabel(.purple))
        XCTAssertEqual(CullingShortcut(key: .character("-")), .colorLabel(nil))
        XCTAssertEqual(CullingShortcut(key: .character("P")), .pick)
        XCTAssertEqual(CullingShortcut(key: .character("x")), .reject)
        XCTAssertEqual(CullingShortcut(key: .character("u")), .clearFlag)
        XCTAssertNil(CullingShortcut(key: .character("a")))
    }

    func testBackgroundWorkQueueIsVisibleAndBounded() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")

        model.enqueueBackgroundWork(first)
        model.enqueueBackgroundWork(second)

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id), [first.id])
        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.id), [second.id])
        XCTAssertEqual(model.visibleWorkActivity?.id, first.id.rawValue)
        XCTAssertEqual(model.visibleWorkActivity?.title, "Generate previews")
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
        XCTAssertTrue(model.canPauseBackgroundWork)
    }

    func testVisibleWorkActivitiesExposeBackgroundQueueShape() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        let first = BackgroundWorkItem.testItem(id: "first")
        let second = BackgroundWorkItem.testItem(id: "second")
        let third = BackgroundWorkItem.testItem(id: "third")

        model.enqueueBackgroundWork(first)
        model.enqueueBackgroundWork(second)
        model.enqueueBackgroundWork(third)

        XCTAssertEqual(model.visibleWorkActivities.map(\.id), [
            first.id.rawValue,
            second.id.rawValue,
            third.id.rawValue
        ])
        XCTAssertEqual(model.visibleWorkActivities.map(\.status), [.running, .queued, .queued])
        XCTAssertEqual(model.visibleWorkActivity?.id, first.id.rawValue)
    }

    func testLibraryStatusTextShowsPreviewGenerationAfterImportCompletes() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        model.statusMessage = "Imported 12 photos"

        model.enqueueBackgroundWork(BackgroundWorkItem.testItem(id: "preview-after-import"))

        XCTAssertEqual(model.libraryStatusText, "Imported 12 photos; generating previews")
    }

    func testBackgroundWorkCanPauseResumeAndCancel() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1)
        )
        let item = BackgroundWorkItem.testItem(id: "pause-target")
        model.enqueueBackgroundWork(item)
        XCTAssertNil(model.backgroundWorkPauseNotice)

        model.pauseBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
        XCTAssertEqual(model.backgroundWorkPauseNotice, "Queue paused after current task")
        XCTAssertFalse(model.canPauseBackgroundWork)
        XCTAssertTrue(model.canResumeBackgroundWork)

        model.resumeBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
        XCTAssertNil(model.backgroundWorkPauseNotice)
        XCTAssertTrue(model.canPauseBackgroundWork)
        XCTAssertFalse(model.canResumeBackgroundWork)

        model.cancelBackgroundWork()
        XCTAssertEqual(model.visibleWorkActivity?.status, .cancelled)
        XCTAssertFalse(model.canPauseBackgroundWork)
    }

    func testUndoMetadataChangeRestoresLoadedAssetAndCatalog() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "undo-rating")

        try model.setRatingForSelectedAsset(4)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertFalse(model.canRedoMetadataChange)

        try model.undoMetadataChange()

        XCTAssertEqual(model.selectedAsset?.metadata.rating, 0)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.rating, 0)
        XCTAssertFalse(model.canUndoMetadataChange)
        XCTAssertTrue(model.canRedoMetadataChange)
    }

    func testRedoMetadataChangeReappliesLoadedAssetAndCatalog() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "redo-flag")

        try model.setFlagForSelectedAsset(.pick)
        try model.undoMetadataChange()
        try model.redoMetadataChange()

        XCTAssertEqual(model.selectedAsset?.metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .pick)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertFalse(model.canRedoMetadataChange)
    }

    func testLoadsAssetsFromCatalogRepository() throws {
        let directory = try makeTemporaryDirectory(named: "app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "catalog-asset"),
            originalURL: URL(fileURLWithPath: "/Photos/catalog.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 5)
        )
        try repository.upsert(asset)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.selectedAsset?.id, asset.id)
    }

    func testLoadKeepsTotalAssetCountWhenGridIsLimited() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-count")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        for index in 0..<501 {
            try repository.upsert(Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertEqual(model.libraryCountText, "Showing 120 of 501 photographs")
    }

    func testLoadMoreAssetsAppendsNextCatalogPage() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-load-more")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        for index in 0..<501 {
            try repository.upsert(Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertTrue(model.hasMoreAssets)

        try model.loadMoreAssets()

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-239"))
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 240 of 501 photographs")
    }

    func testPagingSynthetic100kCatalogKeepsLoadedAssetWindowBounded() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-100k-window")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 100_000, repository: repository)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 100_000)

        for _ in 0..<20 {
            try model.loadMoreAssets()
        }

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-2280"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-2519"))
        XCTAssertEqual(model.totalAssetCount, 100_000)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 2281-2520 of 100000 photographs")
    }

    func testLoadingSynthetic100kCatalogDoesNotReadEveryFolderPath() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-100k-folder-query")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 100_000, repository: repository)
        var rowQueries: [String] = []
        database.rowQueryObserver = { sql in
            rowQueries.append(sql.replacingOccurrences(of: "\n", with: " "))
        }
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )

        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.catalogFolders, [
            CatalogFolder(path: "/Volumes/NAS/Photos/", name: "Photos", assetCount: 100_000)
        ])
        XCTAssertFalse(rowQueries.contains { sql in
            sql.contains("SELECT original_path FROM assets")
        })
    }

    func testLoadPreviousAssetsKeepsLoadedAssetWindowBounded() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-previous-window")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 600, repository: repository)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        for _ in 0..<3 {
            try model.loadMoreAssets()
        }

        try model.loadPreviousAssets()

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-120"))
        XCTAssertEqual(model.assets.last?.id, AssetID(rawValue: "asset-359"))
        XCTAssertEqual(model.totalAssetCount, 600)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertEqual(model.libraryCountText, "Showing 121-360 of 600 photographs")
    }

    func testApplyingLibraryFiltersLoadsMatchingCatalogAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-filter")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([
            Asset(
                id: AssetID(rawValue: "keeper"),
                originalURL: URL(fileURLWithPath: "/Photos/Wedding/ceremony-keeper.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: .online,
                metadata: AssetMetadata(rating: 5, colorLabel: .green, flag: .pick)
            ),
            Asset(
                id: AssetID(rawValue: "reject"),
                originalURL: URL(fileURLWithPath: "/Photos/Wedding/ceremony-blink.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 2, modificationDate: Date(timeIntervalSince1970: 2)),
                availability: .online,
                metadata: AssetMetadata(rating: 1, colorLabel: .red, flag: .reject)
            ),
            Asset(
                id: AssetID(rawValue: "travel"),
                originalURL: URL(fileURLWithPath: "/Photos/Travel/mountain.jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 3, modificationDate: Date(timeIntervalSince1970: 3)),
                availability: .online,
                metadata: AssetMetadata(rating: 5)
            )
        ])
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        model.librarySearchText = "CEREMONY"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "keeper")])
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "keeper"))
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.libraryCountText, "1 photograph")
    }

    func testApplyingLibraryFiltersUsesFolderPrefix() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-filter",
            assets: [ceremony, portraits, travel]
        )

        model.folderFilterText = "/Volumes/NAS/Wedding/"
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [portraits.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        let savedSet = try model.saveCurrentLibraryQuery(named: "Wedding Five Stars")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .folderPrefix("/Volumes/NAS/Wedding/"),
            .ratingAtLeast(5)
        ])))
    }

    func testApplyingLibrarySearchIntentFiltersCatalogResults() throws {
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedPick = makeAsset(
            id: "lower-rated",
            path: "/Photos/Wedding/ceremony-lower-rated.jpg",
            rating: 4,
            flag: .pick
        )
        let rejected = makeAsset(
            id: "rejected",
            path: "/Photos/Wedding/ceremony-rejected.jpg",
            rating: 5,
            flag: .reject
        )
        let keyworded = makeAsset(
            id: "keyworded",
            path: "/Photos/Wedding/ceremony-keyworded.jpg",
            rating: 5,
            flag: .pick,
            keywords: ["portfolio"]
        )
        let travel = makeAsset(
            id: "travel",
            path: "/Photos/Travel/mountain.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-library-search-intent",
            assets: [keeper, lowerRatedPick, rejected, keyworded, travel]
        )

        model.librarySearchText = "ceremony picks 5 stars needs keywords"
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSavingLibrarySearchIntentStoresStructuredPredicates() throws {
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-library-search-intent-save",
            assets: [keeper]
        )

        model.librarySearchText = "ceremony picks 5 stars needs keywords"

        let savedSet = try model.saveCurrentLibraryQuery(named: "Ceremony Keepers")

        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .text("ceremony"),
            .flag(.pick),
            .ratingAtLeast(5),
            .missingKeywords
        ])))
        XCTAssertEqual(model.librarySearchText, "")
    }

    func testApplyingLibraryFiltersUsesTechnicalMetadata() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-technical-filters")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_086_400)
        let canon = makeAsset(
            id: "canon",
            path: "/Photos/Job/canon.cr3",
            rating: 4,
            availability: .offline,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                cameraMake: "Canon",
                cameraModel: "EOS R5",
                lensModel: "RF 50mm F1.2L USM",
                isoSpeed: 1600,
                capturedAt: Date(timeIntervalSince1970: 1_800_010_000),
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
        let fuji = makeAsset(
            id: "fuji",
            path: "/Photos/Job/fuji.raf",
            rating: 5,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 8256,
                pixelHeight: 5504,
                cameraMake: "Fujifilm",
                cameraModel: "GFX 100S",
                lensModel: "GF80mmF1.7 R WR",
                isoSpeed: 400,
                capturedAt: Date(timeIntervalSince1970: 1_800_020_000),
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
        try repository.upsert([canon, fuji])
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        model.cameraFilterText = "canon"
        model.lensFilterText = "RF 50"
        model.minimumISOFilter = 800
        model.captureDateStartFilter = start
        model.captureDateEndFilter = end
        model.availabilityFilter = .offline

        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [canon.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertTrue(model.canSaveCurrentLibraryQuery)
        let savedSet = try model.saveCurrentLibraryQuery(named: "Canon High ISO")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .camera("canon"),
            .lens("RF 50"),
            .isoAtLeast(800),
            .capturedAtOrAfter(start),
            .capturedBefore(end),
            .availability(.offline)
        ])))
    }

    func testApplyingLibraryFiltersUsesEvaluationKind() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-evaluation-kind-filter")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let focused = makeAsset(id: "focused", path: "/Photos/Job/focused.jpg", rating: 0)
        let object = makeAsset(id: "object", path: "/Photos/Job/object.jpg", rating: 0)
        let framed = makeAsset(id: "framed", path: "/Photos/Job/framed.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([focused, object, framed])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: focused.id, kind: .focus, value: .score(0.91), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance),
            EvaluationSignal(assetID: framed.id, kind: .framing, value: .label("balanced"), confidence: 0.8, provenance: provenance)
        ])
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        model.evaluationKindFilter = .focus

        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [focused.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        let savedSet = try model.saveCurrentLibraryQuery(named: "Focused")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [.evaluationKind(.focus)])))

        try model.clearLibraryFilters()
        model.librarySearchText = "signal:framing"
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.map(\.id), [framed.id])
        let framingSet = try model.saveCurrentLibraryQuery(named: "Framed")
        XCTAssertEqual(framingSet.membership, .dynamic(SetQuery(predicates: [.evaluationKind(.framing)])))
    }

    func testSelectingPeopleSignalAppliesEvaluationFilterAndShowsMatchingAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-people-signal-filter")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let faceCount = makeAsset(id: "face-count", path: "/Photos/People/face-count.jpg", rating: 0)
        let faceQuality = makeAsset(id: "face-quality", path: "/Photos/People/face-quality.jpg", rating: 0)
        let object = makeAsset(id: "object", path: "/Photos/People/object.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([faceCount, faceQuality, object])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: faceCount.id, kind: .faceCount, value: .count(2), confidence: 0.91, provenance: provenance),
            EvaluationSignal(assetID: faceQuality.id, kind: .faceQuality, value: .score(0.82), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance)
        ])
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
        let model = try AppModel.load(catalog: catalog)

        try model.selectPeopleSignal(.faceCount)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.evaluationKindFilter, .faceCount)
        XCTAssertEqual(model.assets.map(\.id), [faceCount.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectPeopleSignal(.faceQuality)

        XCTAssertEqual(model.evaluationKindFilter, .faceQuality)
        XCTAssertEqual(model.assets.map(\.id), [faceQuality.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSelectingSidebarTargetAppliesReviewQueueWithoutConstructingSidebarRow() throws {
        let evaluated = makeAsset(id: "evaluated-target", path: "/Photos/Target/evaluated.jpg", rating: 0)
        let unevaluated = makeAsset(id: "unevaluated-target", path: "/Photos/Target/unevaluated.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "sidebar-target-review-queue",
            assets: [evaluated, unevaluated]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: evaluated.id, kind: .object, value: .label("camera"), confidence: 0.8, provenance: provenance)
        ])

        try model.selectSidebarTarget(.reviewQueue(.needsEvaluation))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertTrue(model.needsEvaluationFilter)
        XCTAssertEqual(model.assets.map(\.id), [unevaluated.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testActiveLibraryFilterRowsBridgeConcreteFiltersToExistingTargets() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.librarySearchText = "picks 5 stars needs evaluation"
        model.availabilityFilter = .missing
        model.evaluationKindFilter = .faceQuality
        model.metadataSyncPendingFilter = true

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
            ActiveLibraryFilterRow(title: "Rating >= 5", target: .reviewQueue(.fiveStars)),
            ActiveLibraryFilterRow(title: "Needs Evaluation", target: .reviewQueue(.needsEvaluation)),
            ActiveLibraryFilterRow(title: "Source: Missing", target: .sourceAvailability(.missing)),
            ActiveLibraryFilterRow(title: "Signal: Face Quality", target: .evaluationKind(.faceQuality)),
            ActiveLibraryFilterRow(title: "XMP Pending", target: .metadataSyncPending)
        ])
        XCTAssertEqual(model.activeLibraryFilterChips, model.activeLibraryFilterRows.map(\.title))
    }

    func testReviewQueueSignalFiltersUseUserFacingQueueNames() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])

        model.evaluationKindFilter = .faceCount

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Faces Found", target: .reviewQueue(.facesFound))
        ])
        XCTAssertEqual(model.suggestedSavedSearchName, "Faces Found")

        model.evaluationKindFilter = .ocrText

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "OCR Found", target: .reviewQueue(.ocrFound))
        ])
        XCTAssertEqual(model.suggestedSavedSearchName, "OCR Found")
    }

    func testActiveLibraryFilterRowsExposeSelectedDynamicSetRules() {
        let set = AssetSet.dynamic(
            id: AssetSetID(rawValue: "ceremony-keepers"),
            name: "Ceremony Keepers",
            query: SetQuery(predicates: [
                .text("ceremony"),
                .flag(.pick),
                .ratingAtLeast(5),
                .missingKeywords
            ])
        )
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            savedAssetSets: [set],
            selectedAssetSetID: set.id
        )

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Ceremony Keepers", target: .assetSet(set.id)),
            ActiveLibraryFilterRow(title: "Search: ceremony"),
            ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
            ActiveLibraryFilterRow(title: "Rating >= 5", target: .reviewQueue(.fiveStars)),
            ActiveLibraryFilterRow(title: "Needs Keywords", target: .reviewQueue(.needsKeywords))
        ])
    }

    func testTimelineSidebarRowOpensTimelineView() throws {
        let calendar = Self.gregorianUTC
        let asset = makeAsset(
            id: "timeline-sidebar",
            path: "/Photos/Timeline/sidebar.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 2, day: 4, calendar: calendar))
        )
        let (model, _) = try makeModelWithCatalogAssets(named: "timeline-sidebar", assets: [asset])
        let timelineRow = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" }?.rows.first { $0.title == "Timeline" })

        XCTAssertEqual(timelineRow.target, .timeline)
        XCTAssertEqual(timelineRow.countText, "1")

        try model.selectSidebarRow(timelineRow)

        XCTAssertEqual(model.selectedView, .timeline)
        XCTAssertEqual(model.libraryTitle, "Timeline")
    }

    func testSelectingTimelineDayAppliesDateRangeAndLoadsMatchingAssets() throws {
        let calendar = Self.gregorianUTC
        let selectedDay = makeAsset(
            id: "selected-day",
            path: "/Photos/Timeline/selected-day.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 2, day: 4, hour: 9, calendar: calendar))
        )
        let otherDay = makeAsset(
            id: "other-day",
            path: "/Photos/Timeline/other-day.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 2, day: 5, hour: 9, calendar: calendar))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "timeline-select-day",
            assets: [selectedDay, otherDay]
        )

        let timelineDay = CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 1)

        try model.selectTimelineDay(timelineDay, calendar: calendar)

        XCTAssertEqual(model.selectedView, .timeline)
        XCTAssertEqual(model.assets.map(\.id), [selectedDay.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.captureDateStartFilter, timelineDay.startDate(calendar: calendar))
        XCTAssertEqual(model.captureDateEndFilter, timelineDay.endDate(calendar: calendar))
    }

    func testSelectingTimelineMonthAppliesDateRangeAndLoadsMatchingAssets() throws {
        let calendar = Self.gregorianUTC
        let earlyMonth = makeAsset(
            id: "early-month",
            path: "/Photos/Timeline/early-month.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 2, day: 4, hour: 9, calendar: calendar))
        )
        let lateMonth = makeAsset(
            id: "late-month",
            path: "/Photos/Timeline/late-month.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 2, day: 28, hour: 21, calendar: calendar))
        )
        let otherMonth = makeAsset(
            id: "other-month",
            path: "/Photos/Timeline/other-month.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 3, day: 1, hour: 9, calendar: calendar))
        )
        let previousYear = makeAsset(
            id: "previous-year",
            path: "/Photos/Timeline/previous-year.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2025, month: 2, day: 4, hour: 9, calendar: calendar))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "timeline-select-month",
            assets: [otherMonth, earlyMonth, previousYear, lateMonth]
        )

        try model.selectTimelineMonth(year: 2026, month: 2, calendar: calendar)

        let expectedStart = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))
        let expectedEnd = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))
        XCTAssertEqual(model.selectedView, .timeline)
        XCTAssertEqual(model.assets.map(\.id.rawValue).sorted(), ["early-month", "late-month"])
        XCTAssertEqual(model.totalAssetCount, 2)
        XCTAssertEqual(model.captureDateStartFilter, expectedStart)
        XCTAssertEqual(model.captureDateEndFilter, expectedEnd)
    }

    func testSelectingTimelineYearAppliesDateRangeAndLoadsMatchingAssets() throws {
        let calendar = Self.gregorianUTC
        let earlyYear = makeAsset(
            id: "early-year",
            path: "/Photos/Timeline/early-year.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 1, day: 1, hour: 1, calendar: calendar))
        )
        let lateYear = makeAsset(
            id: "late-year",
            path: "/Photos/Timeline/late-year.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2026, month: 12, day: 31, hour: 22, calendar: calendar))
        )
        let previousYear = makeAsset(
            id: "previous-year",
            path: "/Photos/Timeline/previous-year.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2025, month: 12, day: 31, hour: 22, calendar: calendar))
        )
        let nextYear = makeAsset(
            id: "next-year",
            path: "/Photos/Timeline/next-year.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: Self.date(year: 2027, month: 1, day: 1, hour: 1, calendar: calendar))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "timeline-select-year",
            assets: [nextYear, earlyYear, previousYear, lateYear]
        )

        try model.selectTimelineYear(2026, calendar: calendar)

        let expectedStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        let expectedEnd = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))
        XCTAssertEqual(model.selectedView, .timeline)
        XCTAssertEqual(model.assets.map(\.id.rawValue).sorted(), ["early-year", "late-year"])
        XCTAssertEqual(model.totalAssetCount, 2)
        XCTAssertEqual(model.captureDateStartFilter, expectedStart)
        XCTAssertEqual(model.captureDateEndFilter, expectedEnd)
    }

    func testSelectingTimelineDayInSynthetic100kCatalogKeepsLoadedAssetWindowBounded() throws {
        let calendar = Self.gregorianUTC
        let selectedCapturedAt = Self.date(year: 2026, month: 2, day: 4, hour: 9, calendar: calendar)
        let otherCapturedAt = Self.date(year: 2026, month: 2, day: 5, hour: 9, calendar: calendar)
        let directory = try makeTemporaryDirectory(named: "timeline-100k-window")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedTimelineCatalogAssets(
            count: 100_000,
            selectedDayCount: 60_000,
            selectedCapturedAt: selectedCapturedAt,
            otherCapturedAt: otherCapturedAt,
            repository: repository
        )
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
        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 100_000)
        XCTAssertEqual(model.catalogTimelineDays, [
            CatalogTimelineDay(year: 2026, month: 2, day: 5, assetCount: 40_000),
            CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 60_000)
        ])

        let selectedDay = CatalogTimelineDay(year: 2026, month: 2, day: 4, assetCount: 60_000)
        try model.selectTimelineDay(selectedDay, calendar: calendar)

        XCTAssertEqual(model.selectedView, .timeline)
        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 60_000)
        XCTAssertTrue(model.assets.allSatisfy { asset in
            asset.technicalMetadata?.capturedAt.map { calendar.isDate($0, inSameDayAs: selectedCapturedAt) } ?? false
        })

        for _ in 0..<3 {
            try model.loadMoreAssets()
        }

        XCTAssertEqual(model.assets.count, 240)
        XCTAssertEqual(model.totalAssetCount, 60_000)
        XCTAssertTrue(model.hasPreviousAssets)
        XCTAssertTrue(model.hasMoreAssets)
        XCTAssertTrue(model.assets.allSatisfy { asset in
            asset.technicalMetadata?.capturedAt.map { calendar.isDate($0, inSameDayAs: selectedCapturedAt) } ?? false
        })
    }

    func testLoadExposesEvaluationSignalSidebarAndSelectingSignalAppliesFilter() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-evaluation-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let face = makeAsset(id: "face", path: "/Photos/Job/face.jpg", rating: 0)
        let object = makeAsset(id: "object", path: "/Photos/Job/object.jpg", rating: 0)
        let unevaluated = makeAsset(id: "unevaluated", path: "/Photos/Job/unevaluated.jpg", rating: 0)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([face, object, unevaluated])
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: face.id, kind: .faceQuality, value: .score(0.82), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: object.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance)
        ])
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        let signalSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "AI" })
        XCTAssertEqual(signalSection.rowTitles, ["Faces", "Objects"])
        let faceRow = try XCTUnwrap(signalSection.rows.first { $0.title == "Faces" })

        try model.selectSidebarRow(faceRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.evaluationKindFilter, .faceQuality)
        XCTAssertEqual(model.assets.map(\.id), [face.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testLoadExposesReviewQueuesAndSelectingQueueAppliesFilter() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-review-queue-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let pick = makeAsset(id: "pick", path: "/Photos/Job/pick.jpg", rating: 4, flag: .pick, keywords: ["tagged"])
        let reject = makeAsset(id: "reject", path: "/Photos/Job/reject.jpg", rating: 1, flag: .reject, keywords: ["tagged"])
        let fiveStar = makeAsset(id: "five-star", path: "/Photos/Job/five-star.jpg", rating: 5, keywords: ["tagged"])
        let unreviewed = makeAsset(id: "unreviewed", path: "/Photos/Job/unreviewed.jpg", rating: 0, keywords: ["tagged"])
        let needsKeywords = makeAsset(id: "needs-keywords", path: "/Photos/Job/needs-keywords.jpg", rating: 3)
        let faceFound = makeAsset(id: "face-found", path: "/Photos/Job/face-found.jpg", rating: 3, keywords: ["tagged"])
        let ocrFound = makeAsset(id: "ocr-found", path: "/Photos/Job/ocr-found.jpg", rating: 3, keywords: ["tagged"])
        let likelyIssue = makeAsset(id: "likely-issue", path: "/Photos/Job/likely-issue.jpg", rating: 3, keywords: ["tagged"])
        let providerFailure = makeAsset(id: "provider-failure", path: "/Photos/Job/provider-failure.jpg", rating: 3, keywords: ["tagged"])
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.upsert([pick, reject, fiveStar, unreviewed, needsKeywords, faceFound, ocrFound, likelyIssue, providerFailure])
        try repository.recordEvaluationFailure(assetID: providerFailure.id, provider: "local-http-model", message: "model timed out")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: pick.id, kind: .faceQuality, value: .score(0.82), confidence: 0.82, provenance: provenance),
            EvaluationSignal(assetID: reject.id, kind: .object, value: .label("camera"), confidence: 0.74, provenance: provenance),
            EvaluationSignal(assetID: fiveStar.id, kind: .object, value: .label("receipt"), confidence: 0.69, provenance: provenance),
            EvaluationSignal(assetID: faceFound.id, kind: .faceCount, value: .count(2), confidence: 0.91, provenance: provenance),
            EvaluationSignal(assetID: ocrFound.id, kind: .ocrText, value: .text("invoice"), confidence: 0.94, provenance: provenance),
            EvaluationSignal(assetID: likelyIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance),
            EvaluationSignal(assetID: providerFailure.id, kind: .object, value: .label("person"), confidence: 0.77, provenance: provenance)
        ])
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
        let model = try AppModel.load(catalog: catalog)

        let reviewSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Review" })
        XCTAssertEqual(reviewSection.rowTitles, [
            "Picks",
            "Rejects",
            "5 Stars",
            "Needs Keywords",
            "Needs Evaluation",
            "Faces Found",
            "OCR Found",
            "Likely Issues",
            "Provider Failures"
        ])
        XCTAssertEqual(reviewQueueCount("Picks", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Rejects", in: model), "1")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Needs Keywords", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Needs Evaluation", in: model), "2")
        XCTAssertEqual(reviewQueueCount("Faces Found", in: model), "1")
        XCTAssertEqual(reviewQueueCount("OCR Found", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Likely Issues", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Provider Failures", in: model), "1")

        let picksRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Picks" })
        try model.selectSidebarRow(picksRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let rejectsRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Rejects" })
        try model.selectSidebarRow(rejectsRow)

        XCTAssertEqual(model.flagFilter, .reject)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [reject.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let fiveStarsRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "5 Stars" })
        try model.selectSidebarRow(fiveStarsRow)

        XCTAssertNil(model.flagFilter)
        XCTAssertEqual(model.minimumRatingFilter, 5)
        XCTAssertEqual(model.assets.map(\.id), [fiveStar.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let needsKeywordsRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Needs Keywords" })
        try model.selectSidebarRow(needsKeywordsRow)

        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertTrue(model.needsKeywordsFilter)
        XCTAssertEqual(model.assets.map(\.id), [needsKeywords.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let needsEvaluationRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Needs Evaluation" })
        try model.selectSidebarRow(needsEvaluationRow)

        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertFalse(model.needsKeywordsFilter)
        XCTAssertTrue(model.needsEvaluationFilter)
        XCTAssertEqual(model.assets.map(\.id), [unreviewed.id, needsKeywords.id])
        XCTAssertEqual(model.totalAssetCount, 2)

        let facesFoundRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Faces Found" })
        try model.selectSidebarRow(facesFoundRow)

        XCTAssertEqual(model.evaluationKindFilter, .faceCount)
        XCTAssertEqual(model.assets.map(\.id), [faceFound.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let ocrFoundRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "OCR Found" })
        try model.selectSidebarRow(ocrFoundRow)

        XCTAssertEqual(model.evaluationKindFilter, .ocrText)
        XCTAssertEqual(model.assets.map(\.id), [ocrFound.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let likelyIssuesRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Likely Issues" })
        try model.selectSidebarRow(likelyIssuesRow)

        XCTAssertTrue(model.likelyIssuesFilter)
        XCTAssertNil(model.evaluationKindFilter)
        XCTAssertEqual(model.assets.map(\.id), [likelyIssue.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let providerFailuresRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Provider Failures" })
        try model.selectSidebarRow(providerFailuresRow)

        XCTAssertTrue(model.providerFailuresFilter)
        XCTAssertFalse(model.likelyIssuesFilter)
        XCTAssertNil(model.evaluationKindFilter)
        XCTAssertEqual(model.assets.map(\.id), [providerFailure.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSelectingAllPhotographsSidebarRowReturnsToGridAndClearsFilters() throws {
        let filtered = makeAsset(id: "filtered", path: "/Photos/Job/filtered.jpg", rating: 5, keywords: ["selected"])
        let unfiltered = makeAsset(id: "unfiltered", path: "/Photos/Job/unfiltered.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-all-photographs-sidebar",
            assets: [filtered, unfiltered]
        )
        model.selectedView = .copilot
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        XCTAssertEqual(model.assets.map(\.id), [filtered.id])
        let librarySection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Library" })
        let allPhotographsRow = try XCTUnwrap(librarySection.rows.first { $0.id == "library-all" })

        try model.selectSidebarRow(allPhotographsRow)

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.librarySearchText, "")
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [filtered.id, unfiltered.id])
    }

    func testReviewQueueCountsRefreshAfterMetadataChanges() throws {
        let asset = makeAsset(
            id: "metadata-target",
            path: "/Photos/Job/metadata-target.jpg",
            rating: 0,
            keywords: ["tagged"]
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-review-count-refresh",
            assets: [asset]
        )

        XCTAssertEqual(reviewQueueCount("Picks", in: model), "0")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "0")
        XCTAssertEqual(reviewQueueCount("Needs Keywords", in: model), "0")

        try model.setFlagForSelectedAsset(.pick)
        try model.setRatingForSelectedAsset(5)
        try model.setKeywordTextForSelectedAsset("")

        XCTAssertEqual(reviewQueueCount("Picks", in: model), "1")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Needs Keywords", in: model), "1")
    }

    @MainActor
    func testEvaluationCompletionRefreshesNeedsEvaluationReviewCount() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "needs-evaluation-refresh", path: "/Photos/needs-evaluation-refresh.jpg", rating: 0)
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "needs-evaluation-refresh",
            assets: [asset],
            workerSupervisor: supervisor
        )
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .faceQuality,
            value: .score(0.82),
            confidence: 0.82,
            provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(reviewQueueCount("Needs Evaluation", in: model), "1")

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        try model.requestEvaluation(assetID: asset.id, provider: "apple-vision")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-apple-vision"),
            message: "evaluated \(asset.id.rawValue) with apple-vision"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(reviewQueueCount("Needs Evaluation", in: model), "0")
    }

    func testTechnicalFiltersCountAsActiveLibraryFiltersAndClear() throws {
        let (model, _, _) = try makeModelWithCatalogAsset(named: "active-technical-filter")

        model.cameraFilterText = "Canon"
        model.folderFilterText = "/Photos/Jobs/"
        model.keywordFilterText = "portfolio"
        model.colorLabelFilter = .green
        model.availabilityFilter = .offline
        XCTAssertTrue(model.hasActiveLibraryFilters)

        try model.clearLibraryFilters()

        XCTAssertFalse(model.hasActiveLibraryFilters)
        XCTAssertNil(model.colorLabelFilter)
        XCTAssertNil(model.availabilityFilter)
        XCTAssertEqual(model.keywordFilterText, "")
        XCTAssertEqual(model.folderFilterText, "")
        XCTAssertEqual(model.cameraFilterText, "")
        XCTAssertEqual(model.lensFilterText, "")
        XCTAssertNil(model.minimumISOFilter)
        XCTAssertNil(model.captureDateStartFilter)
        XCTAssertNil(model.captureDateEndFilter)
    }

    func testLoadExposesSavedAndStarredAssetSetsInSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-saved-sets")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let starred = AssetSet(
            id: AssetSetID(rawValue: "starred"),
            name: "Portfolio Shortlist",
            membership: .dynamic(SetQuery(predicates: [.ratingAtLeast(5)])),
            starred: true
        )
        let saved = AssetSet.dynamic(
            id: AssetSetID(rawValue: "saved"),
            name: "Ceremony Picks",
            query: SetQuery(predicates: [.text("ceremony"), .flag(.pick)])
        )
        let manual = AssetSet.manual(
            id: AssetSetID(rawValue: "manual"),
            name: "Manual Keeper",
            assetIDs: [AssetID(rawValue: "ceremony-pick"), AssetID(rawValue: "missing")]
        )
        try repository.upsert([
            makeAsset(id: "portfolio", path: "/Photos/Portfolio/hero.jpg", rating: 5),
            makeAsset(id: "ceremony-pick", path: "/Photos/Ceremony/pick.jpg", rating: 5, flag: .pick),
            makeAsset(id: "ceremony-reject", path: "/Photos/Ceremony/reject.jpg", rating: 1, flag: .reject)
        ])
        try repository.upsert(starred)
        try repository.upsert(saved)
        try repository.upsert(manual)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.savedAssetSets.map(\.id), [starred.id, saved.id, manual.id])
        XCTAssertEqual(model.starredAssetSets.map(\.id), [starred.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, [starred.name])
        XCTAssertEqual(sidebarRowCount(starred.name, in: "Starred", of: model), "2")
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Saved Sets" }?.rowTitles, [starred.name, saved.name, manual.name])
        let savedRows = try XCTUnwrap(model.sidebarSections.first { $0.title == "Saved Sets" }?.rows)
        XCTAssertEqual(savedRows.map(\.detailText), ["Smart collection", "Smart collection", "Manual set"])
        XCTAssertEqual(savedRows.map(\.countText), ["2", "1", "1"])
        XCTAssertEqual(savedRows.map(\.tone), [.accent, .accent, .neutral])
    }

    func testSavedSetCountsRefreshAfterMetadataChanges() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-saved-set-count-refresh")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "saved-set-target", path: "/Photos/target.jpg", rating: 0)
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        try repository.upsert(asset)
        try repository.upsert(savedSet)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))

        XCTAssertEqual(sidebarRowCount("Five Stars", in: "Saved Sets", of: model), "0")

        try model.setRatingForSelectedAsset(5)

        XCTAssertEqual(sidebarRowCount("Five Stars", in: "Saved Sets", of: model), "1")
    }

    func testTogglingSavedAssetSetStarredPersistsAndRefreshesSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-toggle-saved-set-star")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        try repository.upsert(asset)
        try repository.upsert(savedSet)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let savedSetRow = try XCTUnwrap(model.sidebarSections.first { $0.title == "Saved Sets" }?.rows.first)

        XCTAssertTrue(model.canToggleAssetSetStarred(savedSetRow))
        XCTAssertNil(model.sidebarSections.first { $0.title == "Starred" })

        try model.toggleAssetSetStarred(id: savedSet.id)

        XCTAssertTrue(try repository.assetSet(id: savedSet.id).starred)
        XCTAssertEqual(model.starredAssetSets.map(\.id), [savedSet.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, ["Five Stars"])
        XCTAssertEqual(sidebarRowCount("Five Stars", in: "Starred", of: model), "1")

        try model.setAssetSetStarred(id: savedSet.id, starred: false)

        XCTAssertFalse(try repository.assetSet(id: savedSet.id).starred)
        XCTAssertEqual(model.starredAssetSets, [])
        XCTAssertNil(model.sidebarSections.first { $0.title == "Starred" })
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Saved Sets" }?.rowTitles, ["Five Stars"])
    }

    func testRenamingSavedAssetSetPersistsAndRefreshesSidebar() throws {
        let asset = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-rename-saved-set",
            assets: [asset]
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: savedSet.id)

        try model.renameAssetSet(id: savedSet.id, to: " Ceremony Keepers ")

        XCTAssertEqual(try repository.assetSet(id: savedSet.id).name, "Ceremony Keepers")
        XCTAssertEqual(model.savedAssetSets.first?.name, "Ceremony Keepers")
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Saved Sets" }?.rowTitles, ["Ceremony Keepers"])
        XCTAssertEqual(model.activeLibraryFilterRows.first?.title, "Ceremony Keepers")
        XCTAssertEqual(model.statusMessage, "Renamed Ceremony Keepers")
    }

    func testFreezingDynamicSavedAssetSetCreatesSelectedSnapshot() throws {
        let firstKeeper = makeAsset(id: "first-keeper", path: "/Photos/first.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        let secondKeeper = makeAsset(id: "second-keeper", path: "/Photos/second.jpg", rating: 5)
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-freeze-saved-set",
            assets: [firstKeeper, reject, secondKeeper]
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()

        let snapshot = try model.freezeAssetSetSnapshot(id: savedSet.id)

        XCTAssertEqual(snapshot.name, "Five Stars Snapshot")
        XCTAssertEqual(snapshot.membership, .snapshot([firstKeeper.id, secondKeeper.id]))
        XCTAssertEqual(try repository.assetSet(id: snapshot.id), snapshot)
        XCTAssertEqual(model.savedAssetSets.map(\.id), [savedSet.id, snapshot.id])
        XCTAssertEqual(model.selectedAssetSetID, snapshot.id)
        XCTAssertEqual(model.assets.map(\.id), [firstKeeper.id, secondKeeper.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Saved Sets" }?.rowTitles, ["Five Stars", "Five Stars Snapshot"])
        XCTAssertEqual(sidebarRowCount("Five Stars Snapshot", in: "Saved Sets", of: model), "2")
        XCTAssertEqual(model.statusMessage, "Saved Five Stars Snapshot")

        var changedKeeper = firstKeeper
        changedKeeper.metadata.rating = 1
        try repository.upsert(changedKeeper)
        try model.reload()

        XCTAssertEqual(model.assets.map(\.id), [firstKeeper.id, secondKeeper.id])
    }

    func testDuplicatingSavedAssetSetCopiesMembershipAndSelectsCopy() throws {
        let first = makeAsset(id: "first", path: "/Photos/first.jpg", rating: 1)
        let second = makeAsset(id: "second", path: "/Photos/second.jpg", rating: 2)
        let savedSet = AssetSet.manual(
            id: AssetSetID(rawValue: "manual-keepers"),
            name: "Manual Keepers",
            assetIDs: [second.id, first.id]
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-duplicate-saved-set",
            assets: [first, second]
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()

        let duplicate = try model.duplicateAssetSet(id: savedSet.id, named: " Copy of Keepers ", starred: true)

        XCTAssertNotEqual(duplicate.id, savedSet.id)
        XCTAssertEqual(duplicate.name, "Copy of Keepers")
        XCTAssertEqual(duplicate.membership, savedSet.membership)
        XCTAssertTrue(duplicate.starred)
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(try repository.assetSet(id: duplicate.id), duplicate)
        XCTAssertEqual(model.savedAssetSets.map(\.id), [savedSet.id, duplicate.id])
        XCTAssertEqual(model.starredAssetSets.map(\.id), [duplicate.id])
        XCTAssertEqual(model.selectedAssetSetID, duplicate.id)
        XCTAssertEqual(model.assets.map(\.id), [second.id, first.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Saved Sets" }?.rowTitles, ["Manual Keepers", "Copy of Keepers"])
        XCTAssertEqual(sidebarRowCount("Copy of Keepers", in: "Saved Sets", of: model), "2")
        XCTAssertEqual(model.statusMessage, "Saved Copy of Keepers")
    }

    func testDeletingSavedAssetSetPersistsRefreshesSidebarAndClearsActiveScope() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-delete-saved-set",
            assets: [keeper, reject]
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: savedSet.id)

        try model.deleteAssetSet(id: savedSet.id)

        XCTAssertThrowsError(try repository.assetSet(id: savedSet.id))
        XCTAssertEqual(model.savedAssetSets, [])
        XCTAssertEqual(model.starredAssetSets, [])
        XCTAssertNil(model.sidebarSections.first { $0.title == "Saved Sets" })
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, reject.id])
        XCTAssertEqual(model.statusMessage, "Deleted Five Stars")
    }

    func testSidebarContextActionsExposeSavedSetRenameAndStarToggle() throws {
        let asset = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-saved-set-context-actions",
            assets: [asset]
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()
        let savedSetRow = try XCTUnwrap(model.sidebarSections.first { $0.title == "Saved Sets" }?.rows.first)

        let actions = model.sidebarContextActions(for: savedSetRow)

        XCTAssertEqual(actions.map(\.kind), [
            .renameAssetSet(savedSet.id),
            .duplicateAssetSet(savedSet.id),
            .freezeAssetSetSnapshot(savedSet.id),
            .toggleAssetSetStarred(savedSet.id),
            .deleteAssetSet(savedSet.id)
        ])
        XCTAssertEqual(actions.map(\.title), ["Rename Set", "Duplicate Set...", "Freeze Snapshot...", "Star Set", "Delete Set..."])
        XCTAssertEqual(actions.map(\.systemImage), ["pencil", "plus.square.on.square", "camera.aperture", "star", "trash"])
    }

    func testSidebarContextActionsDoNotExposeFreezeForManualSavedSets() throws {
        let asset = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let savedSet = AssetSet.manual(
            id: AssetSetID(rawValue: "manual-keepers"),
            name: "Manual Keepers",
            assetIDs: [asset.id]
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-manual-set-context-actions",
            assets: [asset]
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()
        let savedSetRow = try XCTUnwrap(model.sidebarSections.first { $0.title == "Saved Sets" }?.rows.first)

        let actions = model.sidebarContextActions(for: savedSetRow)

        XCTAssertEqual(actions.map(\.kind), [
            .renameAssetSet(savedSet.id),
            .duplicateAssetSet(savedSet.id),
            .toggleAssetSetStarred(savedSet.id),
            .deleteAssetSet(savedSet.id)
        ])
    }

    func testCanToggleAssetSetStarredOnlyForSavedSetRowsWithCatalog() throws {
        let asset = makeAsset(id: "uncataloged", path: "/Photos/uncataloged.jpg", rating: 0)
        let modelWithoutCatalog = AppModel(sidebarSections: [], selectedView: .grid, assets: [asset])
        let assetSetRow = SidebarRow(id: "saved", title: "Saved", target: .assetSet(AssetSetID(rawValue: "saved")))
        let libraryRow = SidebarRow(id: "all", title: "All", target: .allPhotographs)

        XCTAssertFalse(modelWithoutCatalog.canToggleAssetSetStarred(assetSetRow))
        XCTAssertFalse(modelWithoutCatalog.canToggleAssetSetStarred(libraryRow))
    }

    func testLoadExposesCatalogFoldersInSidebarAndSelectingFolderAppliesFilter() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-sidebar",
            assets: [ceremony, portraits, travel]
        )

        let folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        XCTAssertEqual(folderSection.rowTitles, ["Travel", "Ceremony", "Portraits"])
        let ceremonyRow = try XCTUnwrap(folderSection.rows.first { $0.title == "Ceremony" })

        try model.selectSidebarRow(ceremonyRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.folderFilterText, "/Volumes/NAS/Wedding/Ceremony/")
        XCTAssertEqual(model.assets.map(\.id), [ceremony.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testLoadExposesCatalogPeople() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-people")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "maya-frame", path: "/Volumes/NAS/Wedding/maya.jpg", rating: 4)
        try repository.upsert(asset)
        try repository.upsertPerson(id: "person-maya", name: "Maya")
        try repository.assignAssets([asset.id], toPersonID: "person-maya")
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

        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.catalogPeople, [
            CatalogPerson(id: "person-maya", name: "Maya", assetCount: 1)
        ])
    }

    func testConfirmSelectedAssetAsPersonPersistsNamedGroup() throws {
        let asset = makeAsset(id: "selected-face", path: "/Volumes/NAS/Wedding/selected-face.jpg", rating: 4)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-confirm-person",
            assets: [asset]
        )

        let person = try model.confirmSelectedAssetsAsPerson(named: " Maya ", id: "person-maya")

        XCTAssertEqual(person, CatalogPerson(id: "person-maya", name: "Maya", assetCount: 1))
        XCTAssertEqual(model.catalogPeople, [person])
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [asset.id])
    }

    func testConfirmSelectedBatchAsPersonUsesBatchInsteadOfPrimarySelection() throws {
        let primary = makeAsset(id: "primary", path: "/Volumes/NAS/Wedding/primary.jpg", rating: 4)
        let batchA = makeAsset(id: "batch-a", path: "/Volumes/NAS/Wedding/batch-a.jpg", rating: 4)
        let batchB = makeAsset(id: "batch-b", path: "/Volumes/NAS/Wedding/batch-b.jpg", rating: 4)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-confirm-person-batch",
            assets: [primary, batchA, batchB]
        )
        model.setBatchSelection(batchA.id, isSelected: true)
        model.setBatchSelection(batchB.id, isSelected: true)

        let person = try model.confirmSelectedAssetsAsPerson(named: "Maya", id: "person-maya")

        XCTAssertEqual(person, CatalogPerson(id: "person-maya", name: "Maya", assetCount: 2))
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [batchA.id, batchB.id])
    }

    func testMergePersonPersistsAndRefreshesCatalogPeople() throws {
        let targetAsset = makeAsset(id: "target-asset", path: "/Volumes/NAS/Wedding/target.jpg", rating: 4)
        let sourceAsset = makeAsset(id: "source-asset", path: "/Volumes/NAS/Wedding/source.jpg", rating: 4)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-merge-person",
            assets: [targetAsset, sourceAsset],
            configureRepository: { repository in
                try repository.upsertPerson(id: "target", name: "Maya")
                try repository.upsertPerson(id: "source", name: "Maya duplicate")
                try repository.assignAssets([targetAsset.id], toPersonID: "target")
                try repository.assignAssets([sourceAsset.id], toPersonID: "source")
            }
        )

        try model.mergePerson(sourceID: "source", into: "target")

        XCTAssertEqual(model.catalogPeople, [CatalogPerson(id: "target", name: "Maya", assetCount: 2)])
        XCTAssertEqual(try repository.assetIDs(personID: "target"), [targetAsset.id, sourceAsset.id])
        XCTAssertEqual(try repository.assetIDs(personID: "source"), [])
    }

    func testDismissSelectedFaceReviewAssetsPersistsAndRefreshesReviewQueue() throws {
        let dismissed = makeAsset(id: "dismissed-face", path: "/Volumes/NAS/Wedding/dismissed.jpg", rating: 4)
        let active = makeAsset(id: "active-face", path: "/Volumes/NAS/Wedding/active.jpg", rating: 4)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-dismiss-face-review",
            assets: [dismissed, active],
            configureRepository: { repository in
                try repository.recordEvaluationSignals([
                    EvaluationSignal(assetID: dismissed.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
                    EvaluationSignal(assetID: active.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance)
                ])
                try repository.upsertPerson(id: "person-maya", name: "Maya")
                try repository.assignAssets([dismissed.id], toPersonID: "person-maya")
            }
        )
        try model.selectSidebarTarget(.reviewQueue(.facesFound))
        model.selectedAssetID = dismissed.id

        try model.dismissSelectedFaceReviewAssets()

        XCTAssertEqual(try repository.dismissedFaceAssetIDs(), [dismissed.id])
        XCTAssertEqual(model.assets.map(\.id), [active.id])
        XCTAssertEqual(model.reviewQueueCounts[.facesFound], 1)
        XCTAssertEqual(model.catalogEvaluationKindSummaries, [
            CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 1)
        ])
        XCTAssertEqual(model.catalogPeople, [CatalogPerson(id: "person-maya", name: "Maya", assetCount: 0)])
    }

    func testLoadExposesSourceAvailabilityRowsInSidebarAndSelectingRowAppliesFilter() throws {
        let online = makeAsset(id: "online", path: "/Volumes/NAS/Job/online.cr2", rating: 4)
        let offline = makeAsset(id: "offline", path: "/Volumes/NAS/Job/offline.cr2", rating: 4, availability: .offline)
        let firstMissing = makeAsset(id: "missing-a", path: "/Volumes/NAS/Job/missing-a.cr2", rating: 4, availability: .missing)
        let secondMissing = makeAsset(id: "missing-b", path: "/Volumes/NAS/Job/missing-b.cr2", rating: 4, availability: .missing)
        let moved = makeAsset(id: "moved", path: "/Volumes/NAS/Job/moved.cr2", rating: 4, availability: .moved)
        let stale = makeAsset(id: "stale", path: "/Volumes/NAS/Job/stale.cr2", rating: 4, availability: .stale)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-source-availability-sidebar",
            assets: [online, offline, firstMissing, secondMissing, moved, stale]
        )

        let sourceSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sources" })
        XCTAssertEqual(sourceSection.rowTitles, [
            "Offline Originals",
            "Missing Originals",
            "Moved Originals",
            "Stale Originals"
        ])
        XCTAssertEqual(sourceSection.rows.map(\.countText), ["1", "2", "1", "1"])
        let missingRow = try XCTUnwrap(sourceSection.rows.first { $0.title == "Missing Originals" })

        try model.selectSidebarRow(missingRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.availabilityFilter, .missing)
        XCTAssertEqual(model.assets.map(\.id), [firstMissing.id, secondMissing.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testLoadExposesSourceBookmarkRepairRowsInSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-bookmark-repair-sidebar")
        let sourceRoot = directory.appendingPathComponent("photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("source-root-bookmark".utf8)
        try catalog.repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
        let asset = Asset(
            id: AssetID(rawValue: "repair-needed"),
            originalURL: sourceRoot.appendingPathComponent("repair-needed.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 4)
        )
        try catalog.repository.upsert(asset)
        let model = try AppModel.load(catalog: catalog, resourceAccess: RecordingSecurityScopedResourceAccess(requiresSuccessfulAccess: false).value)

        let sourceSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sources" })
        let repairRow = try XCTUnwrap(sourceSection.rows.first { $0.id == "source-bookmark-repair-\(sourceRoot.path)" })

        XCTAssertEqual(repairRow.title, "Reconnect photos")
        XCTAssertEqual(repairRow.detailText, "Permission needs refresh")
        XCTAssertEqual(repairRow.countText, "1")
        XCTAssertEqual(repairRow.tone, .warning)
        XCTAssertTrue(repairRow.isSelectable)
        XCTAssertEqual(repairRow.target, .sourceBookmarkRepair(sourceRoot.path))
    }

    func testReconnectSourceRootRefreshesLoadedAssetsAndSourceSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        let sourceSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sources" })
        XCTAssertEqual(sourceSection.rowTitles, ["Missing Originals"])
        XCTAssertEqual(sourceSection.rows.first?.countText, "1")

        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [newOriginalURL])
        XCTAssertEqual(model.assets.map(\.availability), [.online])
        XCTAssertNil(model.sidebarSections.first { $0.title == "Sources" })
        XCTAssertEqual(model.statusMessage, "Reconnected 1 source")
    }

    func testReconnectSourceRootEnqueuesPendingPreviewForRestoredOriginal() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect-preview")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-preview"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        let pendingPreview = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(pendingPreview)
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        XCTAssertEqual(try transport.commands(), [])
        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .grid)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [pendingPreview])
    }

    func testReconnectSourceRootPersistsFreshSecurityScopedBookmarkForNewRoot() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect-bookmark")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: newOriginalURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-bookmark"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: newOriginalURL),
            availability: .missing,
            metadata: AssetMetadata(rating: 4)
        )
        try repository.upsert(asset)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let bookmarkData = Data("fresh-mounted-root-bookmark".utf8)
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: false,
            bookmarkDataByURL: [newRoot: bookmarkData]
        )
        let model = try AppModel.load(catalog: catalog, resourceAccess: access.value)

        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)
        let reconnectedRoot = try XCTUnwrap(try repository.sourceRoots().first { $0.path == newRoot.path })

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(reconnectedRoot.securityScopedBookmarkData, bookmarkData)
    }

    func testSuggestedReconnectOldRootUsesVisibleUnavailableAssets() {
        let online = makeAsset(id: "online", path: "/Volumes/Current/Job/online.jpg", rating: 0)
        let firstMissing = makeAsset(id: "missing-a", path: "/Volumes/Archive/Job/a.jpg", rating: 0, availability: .missing)
        let secondMissing = makeAsset(id: "missing-b", path: "/Volumes/Archive/Job/Nested/b.jpg", rating: 0, availability: .offline)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [online, firstMissing, secondMissing])

        XCTAssertEqual(model.suggestedReconnectOldRootPath, "/Volumes/Archive/Job")
    }

    func testSuggestedReconnectOldRootUsesCatalogSourceRootsBeyondLoadedWindow() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-root-history")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: 500, repository: repository)
        let missingArchiveAsset = makeAsset(
            id: "archive-missing",
            path: "/Volumes/Archive/Job/Nested/missing.jpg",
            rating: 0,
            availability: .missing
        )
        try repository.upsert(missingArchiveAsset)
        try repository.recordSourceRoot(URL(fileURLWithPath: "/Volumes/Archive/Job", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )

        let model = try AppModel.load(catalog: catalog)

        XCTAssertFalse(model.assets.contains { $0.id == missingArchiveAsset.id })
        XCTAssertEqual(model.suggestedReconnectOldRootPath, "/Volumes/Archive/Job")
    }

    func testLoadExposesRecentAndStarredWorkSessionsInSidebar() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-work-sessions")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let recent = WorkSession(
            id: WorkSessionID(rawValue: "recent-import"),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported 12 photos",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 12,
            totalUnitCount: 12,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let starred = WorkSession(
            id: WorkSessionID(rawValue: "starred-cull"),
            kind: .culling,
            intent: "One hero per burst",
            title: "Cull Ceremony",
            detail: "Reviewing ceremony candidates",
            status: .paused,
            inputSetIDs: [AssetSetID(rawValue: "candidates")],
            outputSetIDs: [],
            completedUnitCount: 25,
            totalUnitCount: 100,
            failureCount: 0,
            starred: true,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 15)
        )
        try repository.save(recent)
        try repository.save(starred)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.recentWork.map(\.id), [recent.id.rawValue, starred.id.rawValue])
        XCTAssertEqual(model.starredWork.map(\.id), [starred.id.rawValue])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Recent Work" }?.rowTitles, [recent.detail, starred.title])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.map(\.target), [
            .workSession(recent.id),
            .workSession(starred.id)
        ])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred Work" }?.rowTitles, [starred.title])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.map(\.isSelectable), [true, true])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred Work" }?.rows.map(\.isSelectable), [true])
    }

    func testWorkSidebarIncludesStarredSessionOutsideDisplayedRecentRows() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-work-sidebar-starred-overflow")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "starred-cull-input"),
            name: "Starred Cull Input",
            assetIDs: [keeper.id]
        )
        try repository.upsert(inputSet)
        let oldStarredCull = WorkSession(
            id: WorkSessionID(rawValue: "old-starred-cull"),
            kind: .culling,
            intent: "Long-running edit",
            title: "Long-running Cull",
            detail: "Long-running edit",
            status: .running,
            inputSetIDs: [inputSet.id],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 2,
            failureCount: 0,
            starred: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try repository.save(oldStarredCull)
        for index in 1...5 {
            try repository.save(WorkSession(
                id: WorkSessionID(rawValue: "recent-\(index)"),
                kind: .ingest,
                intent: "Recent \(index)",
                title: "Recent \(index)",
                detail: "Recent \(index)",
                status: .completed,
                inputSetIDs: [],
                outputSetIDs: [],
                completedUnitCount: index,
                totalUnitCount: index,
                failureCount: 0,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
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
        let model = try AppModel.load(catalog: catalog)
        let recentRows = try XCTUnwrap(model.sidebarSections.first { $0.title == "Recent Work" }?.rows)
        let starredRows = try XCTUnwrap(model.sidebarSections.first { $0.title == "Starred Work" }?.rows)

        XCTAssertEqual(recentRows.map(\.title), [
            "Recent 5",
            "Recent 4",
            "Recent 3",
            "Recent 2",
            "Recent 1"
        ])
        XCTAssertEqual(starredRows.map(\.title), ["Long-running Cull"])
        let starredRow = try XCTUnwrap(starredRows.first { $0.title == "Long-running Cull" })
        try model.selectSidebarRow(starredRow)

        XCTAssertEqual(model.selectedAssetSetID, inputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testSettingWorkSessionStarredRefreshesWorkLists() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-star-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Pick strongest frame",
            status: .running,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 10,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        try model.setWorkSessionStarred(id: session.id, starred: true)

        XCTAssertEqual(try repository.session(id: session.id).starred, true)
        XCTAssertEqual(model.recentWork.first?.id, session.id.rawValue)
        XCTAssertEqual(model.recentWork.first?.starred, true)
        XCTAssertEqual(model.starredWork.map(\.id), [session.id.rawValue])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred Work" }?.rowTitles, [session.title])

        try model.setWorkSessionStarred(id: session.id, starred: false)

        XCTAssertEqual(try repository.session(id: session.id).starred, false)
        XCTAssertEqual(model.recentWork.first?.starred, false)
        XCTAssertEqual(model.starredWork, [])
    }

    func testSidebarContextActionsExposeWorkSessionStarToggle() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-work-session-context-actions")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Pick strongest frame",
            status: .running,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 10,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        let recentRow = try XCTUnwrap(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.first)
        var action = try XCTUnwrap(model.sidebarContextActions(for: recentRow).first)

        XCTAssertEqual(action.kind, .toggleWorkSessionStarred(session.id))
        XCTAssertEqual(action.title, "Star Work")
        XCTAssertEqual(action.systemImage, "star")

        try model.performSidebarContextAction(action)

        XCTAssertEqual(try repository.session(id: session.id).starred, true)
        let starredRow = try XCTUnwrap(model.sidebarSections.first { $0.title == "Starred Work" }?.rows.first)
        action = try XCTUnwrap(model.sidebarContextActions(for: starredRow).first)
        XCTAssertEqual(action.kind, .toggleWorkSessionStarred(session.id))
        XCTAssertEqual(action.title, "Remove Star")
        XCTAssertEqual(action.systemImage, "star.slash")
    }

    func testSelectingWorkSessionAppliesAssociatedOutputSet() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-select-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-output"),
            name: "Work Output",
            assetIDs: [keeper.id]
        )
        try repository.upsert(outputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Selected one keeper",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: 2,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
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
        let model = try AppModel.load(catalog: catalog)
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.first)

        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, outputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
    }

    func testSelectingCullingWorkSessionReopensLoupeView() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-select-culling-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "cull-input"),
            name: "Cull Input",
            query: SetQuery(predicates: [.ratingAtLeast(4)])
        )
        try repository.upsert(inputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Pick strongest frame",
            status: .running,
            inputSetIDs: [inputSet.id],
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
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
        let model = try AppModel.load(catalog: catalog)
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.first)

        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, inputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testApplyingDynamicSavedSetLoadsMatchingCatalogAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-dynamic-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/Wedding/ceremony-keeper.jpg", rating: 5, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/ceremony-blink.jpg", rating: 1, flag: .reject)
        try repository.upsert([keeper, reject])
        let set = AssetSet.dynamic(
            id: AssetSetID(rawValue: "ceremony-picks"),
            name: "Ceremony Picks",
            query: SetQuery(predicates: [.text("ceremony"), .ratingAtLeast(4), .flag(.pick)])
        )
        try repository.upsert(set)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        try model.applyAssetSet(id: set.id)

        XCTAssertEqual(model.selectedAssetSetID, set.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.selectedView, .grid)
    }

    func testApplyingSnapshotSavedSetLoadsCatalogAssetsInSavedOrder() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-snapshot-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = makeAsset(id: "first", path: "/Photos/first.jpg", rating: 1)
        let second = makeAsset(id: "second", path: "/Photos/second.jpg", rating: 2)
        let third = makeAsset(id: "third", path: "/Photos/third.jpg", rating: 3)
        try repository.upsert([first, second, third])
        let set = AssetSet(
            id: AssetSetID(rawValue: "portfolio"),
            name: "Portfolio",
            membership: .snapshot([third.id, first.id])
        )
        try repository.upsert(set)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        try model.applyAssetSet(id: set.id)

        XCTAssertEqual(model.selectedAssetSetID, set.id)
        XCTAssertEqual(model.assets.map(\.id), [third.id, first.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testSavingCurrentLibraryQueryCreatesSelectedStarredSet() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-save-search")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            colorLabel: .green,
            flag: .pick,
            keywords: ["portfolio"]
        )
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/ceremony-blink.jpg", rating: 1, colorLabel: .red, flag: .reject)
        try repository.upsert([keeper, reject])
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        model.librarySearchText = "ceremony"
        model.keywordFilterText = "portfolio"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()

        let savedSet = try model.saveCurrentLibraryQuery(named: " Ceremony Picks ", starred: true)

        XCTAssertEqual(savedSet.name, "Ceremony Picks")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [.text("ceremony"), .keyword("portfolio"), .ratingAtLeast(4), .flag(.pick), .colorLabel(.green)])))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.savedAssetSets, [savedSet])
        XCTAssertEqual(model.starredAssetSets, [savedSet])
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.librarySearchText, "")
        XCTAssertEqual(model.keywordFilterText, "")
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.colorLabelFilter)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, ["Ceremony Picks"])
        XCTAssertEqual(sidebarRowCount("Ceremony Picks", in: "Starred", of: model), "1")
    }

    func testSavingCurrentAssetScopeSnapshotCapturesAllFilteredMatchesBeyondLoadedPage() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-save-snapshot")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keepers = (0..<130).map { index in
            makeAsset(id: "keeper-\(index)", path: "/Photos/Wedding/keeper-\(index).jpg", rating: 5)
        }
        let rejects = (0..<3).map { index in
            makeAsset(id: "reject-\(index)", path: "/Photos/Wedding/reject-\(index).jpg", rating: 1)
        }
        try repository.upsert(keepers + rejects)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.assets.count, 120)
        XCTAssertEqual(model.totalAssetCount, 130)

        let savedSet = try model.saveCurrentAssetScopeSnapshot(named: " Ceremony Snapshot ", starred: true)

        XCTAssertEqual(savedSet.name, "Ceremony Snapshot")
        XCTAssertEqual(savedSet.membership, .snapshot(keepers.map(\.id)))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.totalAssetCount, 130)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, ["Ceremony Snapshot"])
        XCTAssertEqual(sidebarRowCount("Ceremony Snapshot", in: "Starred", of: model), "130")

        var changedKeeper = keepers[0]
        changedKeeper.metadata.rating = 1
        try repository.upsert(changedKeeper)
        try model.reload()

        XCTAssertEqual(model.totalAssetCount, 130)
        XCTAssertEqual(model.assets.first?.id, changedKeeper.id)
    }

    func testSavingCurrentLibraryQueryRequiresActiveQuery() throws {
        let (model, _, _) = try makeModelWithCatalogAsset(named: "empty-save-search")

        XCTAssertFalse(model.canSaveCurrentLibraryQuery)
        XCTAssertThrowsError(try model.saveCurrentLibraryQuery(named: "No Filter"))
    }

    func testActiveLibraryFilterChipsSummarizeCurrentFilters() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.librarySearchText = " ceremony "
        model.keywordFilterText = "portfolio"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        model.colorLabelFilter = .green
        model.cameraFilterText = "Sony"
        model.minimumISOFilter = 800

        XCTAssertEqual(model.activeLibraryFilterChips, [
            "Search: ceremony",
            "Keyword: portfolio",
            "Rating >= 4",
            "Pick",
            "Green Label",
            "Camera: Sony",
            "ISO >= 800"
        ])
    }

    func testActiveLibraryFilterChipsIncludeParsedSearchIntent() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.librarySearchText = " ceremony picks camera:Canon keyword:portfolio "
        model.keywordFilterText = "portfolio"

        XCTAssertEqual(model.activeLibraryFilterChips, [
            "Search: ceremony",
            "Pick",
            "Camera: Canon",
            "Keyword: portfolio"
        ])
        XCTAssertEqual(model.suggestedSavedSearchName, "ceremony Pick Canon portfolio")
    }

    func testLikelyIssuesFilterNamesSavedSearchScope() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.likelyIssuesFilter = true

        XCTAssertEqual(model.activeLibraryFilterChips, ["Likely Issues"])
        XCTAssertEqual(model.suggestedSavedSearchName, "Likely Issues")
    }

    func testApplyingSmartCollectionRulePresetNarrowsCurrentQuery() throws {
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedPick = makeAsset(
            id: "lower-rated",
            path: "/Photos/Wedding/ceremony-lower-rated.jpg",
            rating: 3,
            flag: .pick
        )
        let rejected = makeAsset(
            id: "rejected",
            path: "/Photos/Wedding/ceremony-rejected.jpg",
            rating: 5,
            flag: .reject
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "smart-collection-add-rule",
            assets: [keeper, lowerRatedPick, rejected]
        )

        model.librarySearchText = "ceremony"
        try model.applySmartCollectionRulePreset(.ratingFourPlus)
        try model.applySmartCollectionRulePreset(.picked)

        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Search: ceremony", "Rating >= 4", "Pick"])
        let savedSet = try model.saveCurrentLibraryQuery(named: "Ceremony Picks")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .text("ceremony"),
            .ratingAtLeast(4),
            .flag(.pick)
        ])))
    }

    func testApplyingSmartCollectionRuleTextNarrowsCurrentQuery() throws {
        let keeper = makeAsset(
            id: "typed-rule-keeper",
            path: "/Photos/Wedding/typed-rule-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedPick = makeAsset(
            id: "typed-rule-lower-rated",
            path: "/Photos/Wedding/typed-rule-lower-rated.jpg",
            rating: 3,
            flag: .pick
        )
        let rejected = makeAsset(
            id: "typed-rule-rejected",
            path: "/Photos/Wedding/typed-rule-rejected.jpg",
            rating: 5,
            flag: .reject
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "smart-collection-typed-rule",
            assets: [keeper, lowerRatedPick, rejected]
        )

        try model.applySmartCollectionRuleText("rating:4 pick")

        XCTAssertEqual(model.librarySearchText, "rating:4 pick")
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Rating >= 4", "Pick"])
        let savedSet = try model.saveCurrentLibraryQuery(named: "Typed Keepers")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .ratingAtLeast(4),
            .flag(.pick)
        ])))
    }

    func testApplyingSmartCollectionSuggestedTemplatePresetSequenceNarrowsCurrentQuery() throws {
        let fiveStarPick = makeAsset(
            id: "template-five-star-pick",
            path: "/Photos/Job/template-five-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let fourStarPick = makeAsset(
            id: "template-four-star-pick",
            path: "/Photos/Job/template-four-pick.jpg",
            rating: 4,
            flag: .pick
        )
        let threeStarPick = makeAsset(
            id: "template-three-star-pick",
            path: "/Photos/Job/template-three-pick.jpg",
            rating: 3,
            flag: .pick
        )
        let fiveStarReject = makeAsset(
            id: "template-five-star-reject",
            path: "/Photos/Job/template-five-reject.jpg",
            rating: 5,
            flag: .reject
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "smart-collection-suggested-template-presets",
            assets: [fiveStarPick, fourStarPick, threeStarPick, fiveStarReject]
        )
        let presentation = SmartCollectionBuilderPresentation(
            proposedName: "Suggested",
            ruleChips: model.activeLibraryFilterChips,
            matchCount: model.totalAssetCount,
            reviewQueueCounts: model.reviewQueueCounts
        )
        let suggestion = try XCTUnwrap(presentation.suggestedTemplateRows.first { $0.title == "Picked keepers" })

        for preset in suggestion.presets {
            try model.applySmartCollectionRulePreset(preset)
        }

        XCTAssertEqual(model.assets.map(\.id), [fiveStarPick.id, fourStarPick.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Rating >= 4", "Pick"])
    }

    func testApplyingSmartCollectionRulePresetFromSelectedDynamicSetPreservesExistingRules() throws {
        let ceremonyPick = makeAsset(
            id: "ceremony-pick",
            path: "/Photos/Wedding/ceremony-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let ceremonyReject = makeAsset(
            id: "ceremony-reject",
            path: "/Photos/Wedding/ceremony-reject.jpg",
            rating: 5,
            flag: .reject
        )
        let rehearsalPick = makeAsset(
            id: "rehearsal-pick",
            path: "/Photos/Wedding/rehearsal-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedCeremonyPick = makeAsset(
            id: "lower-rated-ceremony-pick",
            path: "/Photos/Wedding/ceremony-lower-rated-pick.jpg",
            rating: 3,
            flag: .pick
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "smart-collection-add-rule-from-dynamic-set",
            assets: [ceremonyPick, ceremonyReject, rehearsalPick, lowerRatedCeremonyPick]
        )
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "ceremony-keepers"),
            name: "Ceremony Keepers",
            query: SetQuery(predicates: [.text("ceremony"), .ratingAtLeast(4)])
        )
        try repository.upsert(dynamicSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: dynamicSet.id)

        try model.applySmartCollectionRulePreset(.picked)

        XCTAssertEqual(model.selectedAssetSetID, dynamicSet.id)
        XCTAssertEqual(model.assets.map(\.id), [ceremonyPick.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Ceremony Keepers", "Search: ceremony", "Rating >= 4", "Pick"])
        let savedSet = try model.saveCurrentLibraryQuery(named: "Ceremony Picked")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .text("ceremony"),
            .ratingAtLeast(4),
            .flag(.pick)
        ])))
    }

    func testApplyingSmartCollectionRuleTextFromSelectedDynamicSetPreservesExistingRules() throws {
        let ceremonyPick = makeAsset(
            id: "typed-dynamic-ceremony-pick",
            path: "/Photos/Wedding/ceremony-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let ceremonyReject = makeAsset(
            id: "typed-dynamic-ceremony-reject",
            path: "/Photos/Wedding/ceremony-reject.jpg",
            rating: 5,
            flag: .reject
        )
        let rehearsalPick = makeAsset(
            id: "typed-dynamic-rehearsal-pick",
            path: "/Photos/Wedding/rehearsal-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "smart-collection-typed-rule-from-dynamic-set",
            assets: [ceremonyPick, ceremonyReject, rehearsalPick]
        )
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "typed-ceremony"),
            name: "Typed Ceremony",
            query: SetQuery(predicates: [.text("ceremony")])
        )
        try repository.upsert(dynamicSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: dynamicSet.id)

        try model.applySmartCollectionRuleText("pick")

        XCTAssertEqual(model.selectedAssetSetID, dynamicSet.id)
        XCTAssertEqual(model.assets.map(\.id), [ceremonyPick.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Typed Ceremony", "Search: ceremony", "Pick"])
    }

    func testApplyingSmartCollectionRulePresetFromManualSetClearsExplicitScope() throws {
        let manualPick = makeAsset(
            id: "manual-pick",
            path: "/Photos/Manual/manual-pick.jpg",
            rating: 0,
            flag: .pick
        )
        let manualReject = makeAsset(
            id: "manual-reject",
            path: "/Photos/Manual/manual-reject.jpg",
            rating: 0,
            flag: .reject
        )
        let catalogPick = makeAsset(
            id: "catalog-pick",
            path: "/Photos/Other/catalog-pick.jpg",
            rating: 0,
            flag: .pick
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "smart-collection-add-rule-from-manual-set",
            assets: [manualPick, manualReject, catalogPick]
        )
        let manualSet = AssetSet.manual(
            id: AssetSetID(rawValue: "manual-review"),
            name: "Manual Review",
            assetIDs: [manualPick.id, manualReject.id]
        )
        try repository.upsert(manualSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: manualSet.id)

        try model.applySmartCollectionRulePreset(.picked)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.assets.map(\.id), [manualPick.id, catalogPick.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Pick"])
    }

    func testApplyingRatingPresetDoesNotLoosenStrongerRatingFilter() throws {
        let fiveStar = makeAsset(id: "five-star", path: "/Photos/Job/five.jpg", rating: 5)
        let fourStar = makeAsset(id: "four-star", path: "/Photos/Job/four.jpg", rating: 4)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "smart-collection-rating-preset",
            assets: [fiveStar, fourStar]
        )
        model.minimumRatingFilter = 5

        try model.applySmartCollectionRulePreset(.ratingFourPlus)

        XCTAssertEqual(model.minimumRatingFilter, 5)
        XCTAssertEqual(model.assets.map(\.id), [fiveStar.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Rating >= 5"])
    }

    func testApplyingSourceAndSignalRulePresetsNarrowTogether() throws {
        let offlineObject = makeAsset(
            id: "offline-object",
            path: "/Photos/Job/offline-object.jpg",
            rating: 0,
            availability: .offline
        )
        let offlinePlain = makeAsset(
            id: "offline-plain",
            path: "/Photos/Job/offline-plain.jpg",
            rating: 0,
            availability: .offline
        )
        let onlineObject = makeAsset(
            id: "online-object",
            path: "/Photos/Job/online-object.jpg",
            rating: 0,
            availability: .online
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "smart-collection-source-signal-preset",
            assets: [offlineObject, offlinePlain, onlineObject]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: offlineObject.id, kind: .object, value: .label("camera"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: onlineObject.id, kind: .object, value: .label("camera"), confidence: 0.8, provenance: provenance)
        ])

        try model.applySmartCollectionRulePreset(.offlineSources)
        try model.applySmartCollectionRulePreset(.objectSignals)

        XCTAssertEqual(model.availabilityFilter, .offline)
        XCTAssertEqual(model.evaluationKindFilter, .object)
        XCTAssertEqual(model.assets.map(\.id), [offlineObject.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Source: Offline", "Signal: Object"])
    }

    func testApplyingXmpRulePresetUsesSingleMetadataSyncState() throws {
        let (model, _, _) = try makeModelWithCatalogAsset(named: "smart-collection-xmp-preset")
        model.metadataSyncConflictFilter = true

        try model.applySmartCollectionRulePreset(.xmpPending)

        XCTAssertTrue(model.metadataSyncPendingFilter)
        XCTAssertFalse(model.metadataSyncConflictFilter)
        XCTAssertEqual(model.activeLibraryFilterChips, ["XMP Pending"])

        try model.applySmartCollectionRulePreset(.xmpConflicts)

        XCTAssertFalse(model.metadataSyncPendingFilter)
        XCTAssertTrue(model.metadataSyncConflictFilter)
        XCTAssertEqual(model.activeLibraryFilterChips, ["XMP Conflicts"])
    }

    func testSavingSelectedAssetCreatesSelectedManualSet() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "manual-set-photo")

        let savedSet = try model.saveSelectedAssetAsManualSet(named: " Keeper ", starred: true)

        XCTAssertEqual(savedSet.name, "Keeper")
        XCTAssertEqual(savedSet.membership, .manual([asset.id]))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.savedAssetSets, [savedSet])
        XCTAssertEqual(model.starredAssetSets, [savedSet])
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Starred" }?.rowTitles, ["Keeper"])
        XCTAssertEqual(sidebarRowCount("Keeper", in: "Starred", of: model), "1")
    }

    func testSavingSelectionAsManualSetUsesSelectedBatchInLoadedOrder() throws {
        let first = makeAsset(id: "first", path: "/Photos/first.jpg", rating: 1)
        let second = makeAsset(id: "second", path: "/Photos/second.jpg", rating: 2)
        let third = makeAsset(id: "third", path: "/Photos/third.jpg", rating: 3)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "manual-set-selected-batch",
            assets: [first, second, third]
        )
        model.setBatchSelection(third.id, isSelected: true)
        model.setBatchSelection(first.id, isSelected: true)

        let savedSet = try model.saveSelectedAssetAsManualSet(named: " Batch Keepers ")

        XCTAssertEqual(savedSet.name, "Batch Keepers")
        XCTAssertEqual(savedSet.membership, .manual([first.id, third.id]))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.assets.map(\.id), [first.id, third.id])
        XCTAssertEqual(sidebarRowCount("Batch Keepers", in: "Saved Sets", of: model), "2")
    }

    func testSavingSelectedAssetAsManualSetRequiresSelection() throws {
        let directory = try makeTemporaryDirectory(named: "manual-set-no-selection")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let model = try AppModel.load(repository: repository)

        XCTAssertThrowsError(try model.saveSelectedAssetAsManualSet(named: "No Selection"))
    }

    func testManualSetSaveAffordancesReflectSelectionAndCatalog() throws {
        let (model, _, asset) = try makeModelWithCatalogAsset(named: "manual-set-photo")

        XCTAssertTrue(model.canSaveSelectedAssetAsManualSet)
        XCTAssertEqual(model.suggestedManualSetName, "manual-set-photo")

        model.selectedAssetID = nil

        XCTAssertFalse(model.canSaveSelectedAssetAsManualSet)
        XCTAssertEqual(model.suggestedManualSetName, "Selection")

        let uncatalogedModel = AppModel(sidebarSections: [], selectedView: .grid, assets: [asset])

        XCTAssertFalse(uncatalogedModel.canSaveSelectedAssetAsManualSet)
    }

    func testManualSetSaveAffordancesReflectSelectedBatch() throws {
        let first = makeAsset(id: "batch-one", path: "/Photos/batch-one.jpg", rating: 1)
        let second = makeAsset(id: "batch-two", path: "/Photos/batch-two.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "manual-set-selected-batch-affordance",
            assets: [first, second]
        )
        model.selectedAssetID = nil
        model.setBatchSelection(second.id, isSelected: true)
        model.setBatchSelection(first.id, isSelected: true)

        XCTAssertTrue(model.canSaveSelectedAssetAsManualSet)
        XCTAssertEqual(model.suggestedManualSetName, "2 Selected Photos")
    }

    func testBeginningCullingSessionUsesSelectedAssetSetAsInput() throws {
        let directory = try makeTemporaryDirectory(named: "culling-session-selected-set")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        try repository.upsert(inputSet)
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
        let model = try AppModel.load(catalog: catalog)
        try model.applyAssetSet(id: inputSet.id)

        let session = try model.beginCullingSession(named: " Ceremony Cull ", intent: " One hero per burst ")

        XCTAssertTrue(model.canBeginCullingSession)
        XCTAssertEqual(session.kind, .culling)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.title, "Ceremony Cull")
        XCTAssertEqual(session.intent, "One hero per burst")
        XCTAssertEqual(session.inputSetIDs, [inputSet.id])
        XCTAssertEqual(session.totalUnitCount, 1)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.recentWork.first?.id, session.id.rawValue)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Recent Work" }?.rowTitles.first, "Ceremony Cull")

        try model.clearLibraryFilters()
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.first)
        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, inputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
    }

    func testBeginningCullingSessionCreatesHiddenInputSetForAdhocSearch() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/Wedding/keeper.jpg", rating: 5, flag: .pick)
        let reject = makeAsset(id: "reject", path: "/Photos/Wedding/reject.jpg", rating: 1, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "culling-session-adhoc-search",
            assets: [keeper, reject]
        )
        model.librarySearchText = "Wedding"
        model.minimumRatingFilter = 4
        model.flagFilter = .pick
        try model.applyLibraryFilters()

        let session = try model.beginCullingSession(named: "Wedding Cull")

        let inputSetID = try XCTUnwrap(session.inputSetIDs.first)
        let inputSet = try repository.assetSet(id: inputSetID)
        XCTAssertTrue(inputSetID.rawValue.hasPrefix("work-input-"))
        XCTAssertEqual(inputSet.name, "Wedding Cull Input")
        XCTAssertEqual(inputSet.membership, .dynamic(SetQuery(predicates: [.text("Wedding"), .ratingAtLeast(4), .flag(.pick)])))
        XCTAssertEqual(model.selectedAssetSetID, inputSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(model.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Wedding Cull Input")
        })

        try model.clearLibraryFilters()
        let row = try XCTUnwrap(model.sidebarSections.first { $0.title == "Recent Work" }?.rows.first)
        try model.selectSidebarRow(row)

        XCTAssertEqual(model.selectedAssetSetID, inputSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
    }

    func testCullingSessionOverSelectedSetPersistsPicksOutputSet() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/Cull/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/Cull/reject.jpg", rating: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "culling-session-selected-set-output",
            assets: [keeper, reject]
        )
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "selected-cull-set"),
            name: "Selected Cull Set",
            assetIDs: [keeper.id, reject.id]
        )
        try repository.upsert(inputSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: inputSet.id)

        let startedSession = try model.beginCullingSession(named: "Selected Cull")
        XCTAssertEqual(startedSession.outputSetIDs, [])

        model.select(keeper.id)
        try model.applyCullingCommand(.pick)
        model.select(reject.id)
        try model.applyCullingCommand(.reject)

        let session = try repository.session(id: startedSession.id)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.completedUnitCount, 2)

        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: outputSetID)), [keeper.id])

        try model.applyWorkSession(id: session.id)

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.selectedAssetSetID, outputSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
    }

    func testClearingCullingPickRemovesEmptyPicksOutputSet() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/Cull/keeper.jpg", rating: 5)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "culling-session-clear-empty-output",
            assets: [keeper]
        )
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "single-cull-set"),
            name: "Single Cull Set",
            assetIDs: [keeper.id]
        )
        try repository.upsert(inputSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: inputSet.id)

        let startedSession = try model.beginCullingSession(named: "Single Cull")
        model.select(keeper.id)
        try model.applyCullingCommand(.pick)

        let pickedSession = try repository.session(id: startedSession.id)
        let outputSetID = try XCTUnwrap(pickedSession.outputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: outputSetID)), [keeper.id])

        try model.applyWorkSession(id: pickedSession.id)
        XCTAssertEqual(model.selectedAssetSetID, outputSetID)

        try model.applyCullingCommand(.clearFlag)

        let clearedSession = try repository.session(id: startedSession.id)
        XCTAssertEqual(clearedSession.status, .running)
        XCTAssertEqual(clearedSession.completedUnitCount, 0)
        XCTAssertEqual(clearedSession.outputSetIDs, [])
        XCTAssertThrowsError(try repository.assetSet(id: outputSetID))
    }

    func testLoadingEmptyRepositoryLeavesSelectionEmpty() throws {
        let directory = try makeTemporaryDirectory(named: "empty-app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertNil(model.selectedAsset)
    }

    func testImportFolderReloadsAssetsAndExposesGridPreviewURL() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try model.importFolder(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        XCTAssertEqual(model.totalAssetCount, 1)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: result.importedAssets[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.catalogFolders, [
            CatalogFolder(path: "\(photoFolder.path)/", name: "photos", assetCount: 1)
        ])
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Folders" }?.rowTitles, ["photos"])
        XCTAssertEqual(reviewQueueCount("Picks", in: model), "0")
        XCTAssertEqual(reviewQueueCount("Rejects", in: model), "0")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "0")
        XCTAssertEqual(reviewQueueCount("Needs Keywords", in: model), "1")
    }

    func testImportFolderOpensImportedSetWhenActiveFiltersWouldHideNewPhotos() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-filtered")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        XCTAssertEqual(model.assets, [])

        let result = try model.importFolder(photoFolder)

        let activity = try XCTUnwrap(model.recentWork.first)
        let session = try catalog.repository.session(id: WorkSessionID(rawValue: activity.id))
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.selectedAssetSetID, outputSetID)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testReimportFolderReportsNoNewPhotos() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-reimport")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let firstResult = try model.importFolder(photoFolder)
        let secondResult = try model.importFolder(photoFolder)

        XCTAssertEqual(firstResult.newAssetCount, 1)
        XCTAssertEqual(firstResult.existingAssetCount, 0)
        XCTAssertEqual(secondResult.importedAssets.map(\.id), firstResult.importedAssets.map(\.id))
        XCTAssertEqual(secondResult.newAssetCount, 0)
        XCTAssertEqual(secondResult.existingAssetCount, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.statusMessage, "No new photos found")
        XCTAssertEqual(model.recentWork.first?.detail, "No new photos found in photos")
        XCTAssertNil(model.errorMessage)
    }

    func testImportFolderReportsNoSupportedPhotosWhenFolderIsEmpty() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-empty-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: photoFolder.appendingPathComponent("notes.txt"))
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try model.importFolder(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 0)
        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertEqual(model.totalAssetCount, 0)
        XCTAssertEqual(model.statusMessage, "No supported photos found")
        XCTAssertEqual(model.recentWork.first?.detail, "No supported photos found in photos")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBackgroundImportShowsImportedAssetWhenFirstCatalogPageIsFull() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-page")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("new.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        for index in 0..<120 {
            try catalog.repository.upsert(Asset(
                id: AssetID(rawValue: "existing-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/existing-\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }
        let model = try AppModel.load(catalog: catalog)
        XCTAssertFalse(model.assets.contains { $0.originalURL == image })

        model.beginImportFolder(photoFolder)
        try await waitForActivityStatus(.completed, in: model)

        let importedAsset = try XCTUnwrap(model.selectedAsset)
        XCTAssertTrue(model.assets.contains { $0.id == importedAsset.id })
        XCTAssertEqual(model.selectedAssetID, importedAsset.id)
        XCTAssertEqual(importedAsset.originalURL, image)
        XCTAssertEqual(model.totalAssetCount, 121)
        XCTAssertEqual(model.libraryCountText, "Showing 121-121 of 121 photographs")
        XCTAssertTrue(model.hasPreviousAssets)

        try model.loadPreviousAssets()

        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "existing-0"))
        XCTAssertEqual(model.assets.last?.id, importedAsset.id)
        XCTAssertFalse(model.hasPreviousAssets)
    }

    func testLoupePreviewURLPrefersLargePreviewOverGridPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-large")
        let gridPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        let largePreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large))
        try writePreviewPlaceholder(to: gridPreview)
        try writePreviewPlaceholder(to: largePreview)

        XCTAssertEqual(model.loupePreviewURL(for: asset.id), largePreview)
    }

    func testLoupePreviewURLFallsBackToGridPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-grid")
        let gridPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try writePreviewPlaceholder(to: gridPreview)

        XCTAssertEqual(model.loupePreviewURL(for: asset.id), gridPreview)
    }

    func testLoupePreviewURLFallsBackToMicroPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-micro")
        let microPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
        try writePreviewPlaceholder(to: microPreview)

        XCTAssertEqual(model.loupePreviewURL(for: asset.id), microPreview)
    }

    func testSelectedPreviewURLUsesSelectedAssetLoupePreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "selected-preview")
        let largePreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large))
        try writePreviewPlaceholder(to: largePreview)

        model.select(asset.id)

        XCTAssertEqual(model.selectedPreviewURL, largePreview)
    }

    func testGridPreviewURLFallsBackToMicroPreview() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "grid-micro")
        let microPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .micro))
        try writePreviewPlaceholder(to: microPreview)

        XCTAssertEqual(model.gridPreviewURL(for: asset.id), microPreview)
    }

    func testOriginalAccessURLReturnsOnlineOriginalOnlyWhenRequested() throws {
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "explicit-original-access",
            sourceIsPresent: true
        )

        XCTAssertNil(model.loupePreviewURL(for: asset.id))
        XCTAssertEqual(try model.originalAccessURL(for: asset.id), asset.originalURL)
    }

    func testOriginalAccessURLMarksUnavailableOriginalMissing() throws {
        let (model, _, asset) = try makeModelWithPreviewCache(named: "explicit-original-missing")

        XCTAssertNil(try model.originalAccessURL(for: asset.id))
        XCTAssertEqual(model.selectedAsset?.availability, .missing)
    }

    func testRefreshSelectedAvailabilityKeepsCachedPreviewsForMissingOriginal() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "offline-preview")
        let gridPreview = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try writePreviewPlaceholder(to: gridPreview)

        try model.refreshSelectedAssetAvailability()

        XCTAssertEqual(model.selectedAsset?.availability, .missing)
        XCTAssertEqual(model.gridPreviewURL(for: asset.id), gridPreview)
        XCTAssertEqual(model.loupePreviewURL(for: asset.id), gridPreview)
    }

    func testRefreshVisibleAvailabilityUpdatesLoadedAssetsAndCatalog() throws {
        let directory = try makeTemporaryDirectory(named: "visible-availability")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let onlineURL = photosDirectory.appendingPathComponent("online.jpg")
        let missingURL = photosDirectory.appendingPathComponent("missing.jpg")
        try Data("online".utf8).write(to: onlineURL)
        try Data("missing".utf8).write(to: missingURL)
        let onlineAsset = Asset(
            id: AssetID(rawValue: "online"),
            originalURL: onlineURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: onlineURL),
            availability: .missing,
            metadata: AssetMetadata()
        )
        let missingAsset = Asset(
            id: AssetID(rawValue: "missing"),
            originalURL: missingURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: missingURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(onlineAsset)
        try repository.upsert(missingAsset)
        try FileManager.default.removeItem(at: missingURL)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(model.assets.map(\.availability), [.online, .missing])
        XCTAssertEqual(try repository.asset(id: onlineAsset.id).availability, .online)
        XCTAssertEqual(try repository.asset(id: missingAsset.id).availability, .missing)
    }

    func testRefreshVisibleAvailabilityRefreshesSourceAvailabilitySidebarCounts() throws {
        let directory = try makeTemporaryDirectory(named: "visible-availability-sidebar")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let imageURL = photosDirectory.appendingPathComponent("online.jpg")
        try Data("online".utf8).write(to: imageURL)
        let asset = Asset(
            id: AssetID(rawValue: "online"),
            originalURL: imageURL,
            volumeIdentifier: "Photos",
            fingerprint: try fileFingerprint(for: imageURL),
            availability: .missing,
            metadata: AssetMetadata()
        )
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(asset)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        let model = try AppModel.load(catalog: catalog)
        let sourceSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Sources" })
        XCTAssertEqual(sourceSection.rowTitles, ["Missing Originals"])
        XCTAssertEqual(sourceSection.rows.first?.countText, "1")

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(model.assets.map(\.availability), [.online])
        XCTAssertNil(model.sidebarSections.first { $0.title == "Sources" })
    }

    @MainActor
    func testRefreshVisibleAvailabilityWithWorkerEnqueuesManagedBatchSourceScan() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = makeAsset(id: "source-first", size: 1)
        let second = makeAsset(id: "source-second", size: 2)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "worker-visible-availability",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(try transport.commands(), [
            .refreshAvailabilityBatch(assetIDs: [first.id, second.id])
        ])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.kind), [.sourceScan])
        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.kind), [])
        XCTAssertEqual(model.visibleWorkActivity?.title, "Refresh sources")
        XCTAssertEqual(model.visibleWorkActivity?.completedUnitCount, 0)
        XCTAssertEqual(model.visibleWorkActivity?.totalUnitCount, 2)
        XCTAssertEqual(model.assets.map(\.availability), [.online, .online])

        try repository.updateAvailability(assetID: first.id, availability: .missing)
        try repository.updateAvailability(assetID: second.id, availability: .stale)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 2,
            detail: "Checked 1 of 2 sources",
            catalogedAssetIDs: []
        )))
        try await waitForVisibleWorkDetail("Checked 1 of 2 sources", in: model)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "checked 2 sources"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(model.assets.map(\.availability), [.missing, .stale])
    }

    @MainActor
    func testCompletedSourceScanEnqueuesPendingPreviewWhenOriginalComesOnline() async throws {
        let directory = try makeTemporaryDirectory(named: "source-scan-recovers-preview")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(
            id: "restored-source",
            path: "/Volumes/NAS/Job/restored-source.cr2",
            rating: 0,
            availability: .offline
        )
        let pendingPreview = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(pendingPreview)
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        XCTAssertEqual(try transport.commands(), [])
        try model.refreshVisibleAssetAvailability()
        XCTAssertEqual(try transport.commands(), [
            .refreshAvailabilityBatch(assetIDs: [asset.id])
        ])
        let scanItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)

        try repository.updateAvailability(assetID: asset.id, availability: .online)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: scanItemID,
            message: "checked 1 source"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: scanItemID, in: model)
        XCTAssertEqual(model.assets.first { $0.id == asset.id }?.availability, .online)
        XCTAssertTrue(waitForCommands([
            .refreshAvailabilityBatch(assetIDs: [asset.id]),
            .generatePreview(assetID: asset.id, level: .grid)
        ], in: transport), commandDescription(transport))
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [pendingPreview])
    }

    @MainActor
    func testCompletedSourceScanRequeuesPreviewAfterUnavailableOriginalFailure() async throws {
        let directory = try makeTemporaryDirectory(named: "source-scan-recovers-failed-preview")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(
            id: "restored-source-after-failure",
            path: "/Volumes/NAS/Job/restored-source-after-failure.cr2",
            rating: 0,
            availability: .offline
        )
        let pendingPreview = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(pendingPreview)
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        let previewItemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid")

        try model.requestPreview(assetID: asset.id, level: .grid)
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .grid)
        ])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: previewItemID,
            message: "original is offline"
        )))
        try await waitForBackgroundWorkStatus(.failed, itemID: previewItemID, in: model)

        try model.refreshVisibleAssetAvailability()
        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: asset.id, level: .grid),
            .refreshAvailabilityBatch(assetIDs: [asset.id])
        ], in: transport), commandDescription(transport))
        let scanItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)

        try repository.updateAvailability(assetID: asset.id, availability: .online)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: scanItemID,
            message: "checked 1 source"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: scanItemID, in: model)
        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: asset.id, level: .grid),
            .refreshAvailabilityBatch(assetIDs: [asset.id]),
            .generatePreview(assetID: asset.id, level: .grid)
        ], in: transport), commandDescription(transport))
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.filter { $0.id == previewItemID }.count, 1)
    }

    @MainActor
    func testRefreshVisibleAvailabilityWithWorkerBatchesLargeSourceScansByVolume() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        func sourceAsset(id: String, volume: String) -> Asset {
            Asset(
                id: AssetID(rawValue: id),
                originalURL: URL(fileURLWithPath: "/Volumes/\(volume)/Photos/\(id).jpg"),
                volumeIdentifier: volume,
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
        let nasAssets = (0...AppModel.sourceAvailabilityBatchSize).map {
            sourceAsset(id: "nas-\($0)", volume: "NAS")
        }
        let archiveAsset = sourceAsset(id: "archive-0", volume: "Archive")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "worker-visible-availability-batched",
            assets: [nasAssets[0], archiveAsset] + Array(nasAssets.dropFirst()),
            workerSupervisor: supervisor
        )

        try model.refreshVisibleAssetAvailability()

        let firstBatch = Array(nasAssets.prefix(AppModel.sourceAvailabilityBatchSize).map(\.id))
        let secondBatch = Array(nasAssets.dropFirst(AppModel.sourceAvailabilityBatchSize).map(\.id))
        let archiveBatch = [archiveAsset.id]
        let expectedFirstCommands: [WorkerCommand] = [
            .refreshAvailabilityBatch(assetIDs: firstBatch)
        ]
        XCTAssertTrue(waitForCommands(expectedFirstCommands, in: transport), commandDescription(transport))
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.first?.totalUnitCount, AppModel.sourceAvailabilityBatchSize)
        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.totalUnitCount), [1, 1])

        let firstItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "checked \(AppModel.sourceAvailabilityBatchSize) sources"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: firstItemID, in: model)

        let expectedSecondCommands: [WorkerCommand] = [
            .refreshAvailabilityBatch(assetIDs: firstBatch),
            .refreshAvailabilityBatch(assetIDs: secondBatch)
        ]
        XCTAssertTrue(waitForCommands(expectedSecondCommands, in: transport), commandDescription(transport))
        let secondItemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: secondItemID,
            message: "checked 1 source"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: secondItemID, in: model)

        let expectedThirdCommands: [WorkerCommand] = [
            .refreshAvailabilityBatch(assetIDs: firstBatch),
            .refreshAvailabilityBatch(assetIDs: secondBatch),
            .refreshAvailabilityBatch(assetIDs: archiveBatch)
        ]
        XCTAssertTrue(waitForCommands(expectedThirdCommands, in: transport), commandDescription(transport))
    }

    func testCanRefreshVisibleAvailabilityRequiresCatalogAndLoadedAssets() throws {
        let (model, _, _) = try makeModelWithPreviewCache(named: "visible-availability-enabled")

        XCTAssertTrue(model.canRefreshVisibleAssetAvailability)

        model.assets = []
        XCTAssertFalse(model.canRefreshVisibleAssetAvailability)

        let localAsset = makeAsset(id: "local-only", size: 1)
        let localOnlyModel = AppModel(sidebarSections: [], selectedView: .grid, assets: [localAsset])

        XCTAssertFalse(localOnlyModel.canRefreshVisibleAssetAvailability)
    }

    func testCanReconnectSourceRootUsesCatalogSourceRootsBeyondLoadedAssets() throws {
        let (model, _, _) = try makeModelWithPreviewCache(named: "source-reconnect-enabled")
        model.assets = []
        model.sourceRoots = [
            CatalogSourceRoot(
                path: "/Volumes/Archive/Job",
                name: "Job",
                assetCount: 120,
                unavailableAssetCount: 37
            )
        ]

        XCTAssertFalse(model.canRefreshVisibleAssetAvailability)
        XCTAssertTrue(model.canReconnectSourceRoot)

        model.sourceRoots = []
        XCTAssertFalse(model.canReconnectSourceRoot)

        model.assets = [
            makeAsset(id: "missing-visible", path: "/Volumes/Archive/Job/frame.jpg", rating: 0, availability: .missing)
        ]
        XCTAssertTrue(model.canReconnectSourceRoot)
    }

    func testRequestMissingPreviewDispatchesWorkerPreviewCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-preview",
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .large)])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .previewGeneration)
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
    }

    func testRequestMissingPreviewRecordsDurablePendingPreviewBeforeDispatch() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "durable-preview", size: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "request-preview-durable-pending",
            assets: [asset],
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .large)
        ])
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .large)])
    }

    func testRequestCachedPreviewDoesNotDispatchWorkerPreviewCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-cached-preview",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testRequestMissingPreviewDoesNotDispatchDuplicateInFlightWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-preview-dedup",
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: asset.id, level: .large)
        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .large)])
        XCTAssertEqual(model.backgroundWorkQueue.items.count, 1)
    }

    func testLoadEnqueuesPendingPreviewGenerationWithWorker() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "pending-preview",
            workerSupervisor: supervisor,
            pendingPreviewLevel: .grid
        )

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .grid)])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .previewGeneration)
    }

    func testLoadCapsPendingPreviewQueueStateHydration() throws {
        var queueStateQueries: [String] = []
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let (model, _, _) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-bounded-state",
            assetCount: AppModel.previewGenerationQueueStateDisplayLimit + 40,
            workerSupervisor: supervisor
        ) { database in
            database.rowQueryObserver = { sql in
                if sql.contains("SELECT asset_id, level, attempt_count"),
                   sql.contains("FROM preview_generation_queue") {
                    queueStateQueries.append(sql.replacingOccurrences(of: "\n", with: " "))
                }
            }
        }

        XCTAssertEqual(model.previewGenerationQueueStates.count, AppModel.previewGenerationQueueStateDisplayLimit)
        XCTAssertFalse(queueStateQueries.isEmpty)
        XCTAssertTrue(queueStateQueries.allSatisfy { sql in
            sql.contains("LIMIT ?") || sql.contains("WHERE asset_id = ?")
        })
    }

    func testSelectingAssetLoadsPreviewFailureOutsideQueueStateSample() throws {
        let directory = try makeTemporaryDirectory(named: "selected-preview-failure-outside-sample")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = (0..<(AppModel.previewGenerationQueueStateDisplayLimit + 1)).map { index in
            makeAsset(id: "preview-failure-sample-\(index)", size: Int64(index + 1))
        }
        let failedAsset = try XCTUnwrap(assets.last)
        try repository.upsert(assets)
        for asset in assets.dropLast() {
            try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        }
        try repository.recordPreviewGenerationFailure(
            assetID: failedAsset.id,
            level: .grid,
            errorMessage: "could not render preview"
        )
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
        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.previewGenerationQueueStates.count, AppModel.previewGenerationQueueStateDisplayLimit)

        model.select(failedAsset.id)

        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.item.assetID, failedAsset.id)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.lastErrorMessage, "could not render preview")
    }

    func testLoadSkipsAutomaticPreviewRetryAfterRepeatedFailures() throws {
        let directory = try makeTemporaryDirectory(named: "pending-preview-retry-exhausted")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "retry-exhausted", size: 1)
        let item = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(item)
        for attempt in 1...3 {
            try repository.recordPreviewGenerationFailure(
                assetID: asset.id,
                level: .grid,
                errorMessage: "render failed \(attempt)"
            )
        }
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [item])
        let failureState = try XCTUnwrap(model.previewGenerationQueueStates.first)
        XCTAssertEqual(failureState.item, item)
        XCTAssertEqual(failureState.attemptCount, 3)
        XCTAssertEqual(failureState.lastErrorMessage, "render failed 3")
    }

    func testRetrySelectedPreviewGenerationFailureDispatchesWorkerPreview() throws {
        let directory = try makeTemporaryDirectory(named: "selected-preview-retry")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "retry-selected-preview", size: 1)
        try repository.upsert(asset)
        for attempt in 1...3 {
            try repository.recordPreviewGenerationFailure(
                assetID: asset.id,
                level: .grid,
                errorMessage: "render failed \(attempt)"
            )
        }
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertTrue(model.canRetrySelectedPreviewGenerationFailures)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.attemptCount, 3)

        try model.retrySelectedPreviewGenerationFailures()

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .grid)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.attemptCount, 3)
    }

    func testLoadSkipsAutomaticPreviewRecoveryForOfflineOriginal() throws {
        let directory = try makeTemporaryDirectory(named: "pending-preview-offline-source")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(
            id: "offline-source",
            path: "/Volumes/NAS/Job/offline-source.cr2",
            rating: 0,
            availability: .offline
        )
        let item = PreviewGenerationItem(assetID: asset.id, level: .grid)
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(item)
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )

        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [item])
        let state = try XCTUnwrap(model.previewGenerationQueueStates.first)
        XCTAssertEqual(state.item, item)
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastErrorMessage)
    }

    func testLoadExposesSelectedPreviewGenerationFailures() throws {
        let directory = try makeTemporaryDirectory(named: "selected-preview-failure")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let failedAsset = makeAsset(id: "failed", path: "/Photos/failed.jpg", rating: 0)
        let pendingAsset = makeAsset(id: "pending", path: "/Photos/pending.jpg", rating: 0)
        try repository.upsert([failedAsset, pendingAsset])
        try repository.recordPreviewGenerationFailure(
            assetID: failedAsset.id,
            level: .grid,
            errorMessage: "could not render preview"
        )
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: pendingAsset.id, level: .grid))
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

        let model = try AppModel.load(catalog: catalog)

        XCTAssertEqual(model.selectedAssetID, failedAsset.id)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.map(\.item), [
            PreviewGenerationItem(assetID: failedAsset.id, level: .grid)
        ])
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.attemptCount, 1)
        XCTAssertEqual(model.selectedPreviewGenerationFailures.first?.lastErrorMessage, "could not render preview")

        model.select(pendingAsset.id)

        XCTAssertEqual(model.selectedPreviewGenerationFailures, [])
    }

    func testPreviewCompletionRefillsPendingPreviewRecoveryBatch() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill",
            assetCount: 41,
            workerSupervisor: supervisor
        )
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        XCTAssertEqual(model.backgroundWorkQueue.items.count, 40)
        XCTAssertNil(model.backgroundWorkQueue.item(id: refillItemID))
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: assets[0].id, level: .grid)])

        try repository.markPreviewGenerated(assetID: assets[0].id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview for asset-0"
        )))

        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: assets[0].id, level: .grid),
            .generatePreview(assetID: assets[1].id, level: .grid)
        ], in: transport))
        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
    }

    func testPreviewFailureRefillsPendingPreviewRecoveryPastUnavailableOriginal() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill-after-unavailable-failure",
            assetCount: 41,
            workerSupervisor: supervisor
        )
        let failedItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        XCTAssertEqual(model.backgroundWorkQueue.items.count, 40)
        XCTAssertNil(model.backgroundWorkQueue.item(id: refillItemID))

        try repository.updateAvailability(assetID: assets[0].id, availability: .missing)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: failedItemID,
            message: "original is missing"
        )))

        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
        XCTAssertEqual(
            try transport.commands().filter { $0 == .generatePreview(assetID: assets[0].id, level: .grid) }.count,
            1
        )
    }

    @MainActor
    func testCompletedPreviewGenerationKeepsOnlyLatestCompletedPreviewInBackgroundQueue() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = makeAsset(id: "completed-preview-first", size: 1)
        let second = makeAsset(id: "completed-preview-second", size: 2)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "completed-preview-pruned",
            assets: [first, second],
            workerSupervisor: supervisor
        )
        let firstItemID = WorkSessionID(rawValue: "preview-\(first.id.rawValue)-grid")
        let secondItemID = WorkSessionID(rawValue: "preview-\(second.id.rawValue)-grid")
        try model.requestPreview(assetID: first.id, level: .grid)
        try model.requestPreview(assetID: second.id, level: .grid)
        try repository.markPreviewGenerated(assetID: first.id, level: .grid)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: firstItemID, in: model)

        try repository.markPreviewGenerated(assetID: second.id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: secondItemID,
            message: "generated grid preview"
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: secondItemID, in: model)
        XCTAssertTrue(waitForBackgroundWorkItemRemoval(firstItemID, in: model))
        XCTAssertEqual(model.backgroundWorkQueue.item(id: secondItemID)?.status, .completed)
    }

    func testPreviewRecoveryRefreshesQueueStateOncePerBatch() throws {
        var queueStateQueryCount = 0
        var assetLookupCount = 0
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill-query-count",
            assetCount: 41,
            workerSupervisor: supervisor
        ) { database in
            database.rowQueryObserver = { sql in
                if sql.contains("SELECT asset_id, level, attempt_count"),
                   sql.contains("FROM preview_generation_queue"),
                   sql.contains("LIMIT ?") {
                    queueStateQueryCount += 1
                }
                if sql == "SELECT * FROM assets WHERE id = ?" {
                    assetLookupCount += 1
                }
            }
        }
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        XCTAssertEqual(queueStateQueryCount, 2)

        queueStateQueryCount = 0
        assetLookupCount = 0
        try repository.markPreviewGenerated(assetID: assets[0].id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview for asset-0"
        )))

        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
        XCTAssertEqual(queueStateQueryCount, 1)
        XCTAssertEqual(assetLookupCount, 1)
    }

    func testPreviewCompletionDoesNotRefreshMetadataSyncState() throws {
        var metadataSyncQueryCount = 0
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, repository, assets) = try makeModelWithPendingPreviewBacklog(
            named: "pending-preview-refill-xmp-query-count",
            assetCount: 41,
            workerSupervisor: supervisor
        ) { database in
            database.rowQueryObserver = { sql in
                if sql.contains("FROM metadata_sync_state") {
                    metadataSyncQueryCount += 1
                }
            }
        }
        let firstItemID = WorkSessionID(rawValue: "preview-asset-0-grid")
        let refillItemID = WorkSessionID(rawValue: "preview-asset-40-grid")

        metadataSyncQueryCount = 0
        try repository.markPreviewGenerated(assetID: assets[0].id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: firstItemID,
            message: "generated grid preview for asset-0"
        )))

        XCTAssertTrue(waitForBackgroundWorkItem(refillItemID, in: model))
        XCTAssertEqual(metadataSyncQueryCount, 0)
    }

    func testRequestQueuedPreviewDoesNotRewriteDurablePendingState() throws {
        let directory = try makeTemporaryDirectory(named: "request-preview-dedup-pending")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let first = makeAsset(id: "asset-0", path: "/Photos/asset-0.jpg", rating: 0)
        let second = makeAsset(id: "asset-1", path: "/Photos/asset-1.jpg", rating: 0)
        try repository.upsert([first, second])
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: first.id, level: .grid))
        Thread.sleep(forTimeInterval: 0.01)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: second.id, level: .grid))
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
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        Thread.sleep(forTimeInterval: 0.01)

        try model.requestPreview(assetID: first.id, level: .grid)

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: first.id, level: .grid),
            PreviewGenerationItem(assetID: second.id, level: .grid)
        ])
    }

    func testVisibleGridPreviewCutsAheadOfPendingPreviewRecoveryBacklog() throws {
        let directory = try makeTemporaryDirectory(named: "visible-preview-priority")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let recoveryFirst = makeAsset(id: "recovery-first", path: "/Photos/recovery-first.jpg", rating: 0)
        let recoverySecond = makeAsset(id: "recovery-second", path: "/Photos/recovery-second.jpg", rating: 0)
        let visible = makeAsset(id: "visible", path: "/Photos/visible.jpg", rating: 0)
        try repository.upsert([recoveryFirst, recoverySecond, visible])
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: recoveryFirst.id, level: .grid))
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: recoverySecond.id, level: .grid))
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        try model.requestVisibleGridPreview(assetID: visible.id)
        try repository.markPreviewGenerated(assetID: recoveryFirst.id, level: .grid)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(recoveryFirst.id.rawValue)-grid"),
            message: "generated grid preview"
        )))

        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: recoveryFirst.id, level: .grid),
            .generatePreview(assetID: visible.id, level: .grid)
        ], in: transport))
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(visible.id.rawValue)-grid"))?.status, .running)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: WorkSessionID(rawValue: "preview-\(recoverySecond.id.rawValue)-grid"))?.status, .queued)
    }

    func testRequestEvaluationDispatchesWorkerRecognitionCommand() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-evaluation",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")

        XCTAssertEqual(try transport.commands(), [.runEvaluation(assetID: asset.id, provider: "local-image-metrics")])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(model.visibleWorkActivity?.kind, .recognition)
        XCTAssertEqual(model.visibleWorkActivity?.status, .running)
    }

    func testRequestEvaluationRequiresCachedPreview() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "request-evaluation-no-preview",
            workerSupervisor: supervisor
        )

        XCTAssertThrowsError(try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics"))
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testRequestSelectedAssetEvaluationUsesDefaultLocalProvider() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-selected-evaluation",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestSelectedAssetEvaluation()

        XCTAssertEqual(try transport.commands(), [.runEvaluation(assetID: asset.id, provider: "local-image-metrics")])
    }

    func testRequestSelectedAssetEvaluationsDispatchesDefaultLocalProviders() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-selected-evaluations",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestSelectedAssetEvaluations()

        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: asset.id, provider: "local-image-metrics")
        ])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-image-metrics"),
            message: "completed local-image-metrics"
        )))

        XCTAssertTrue(waitForCommands([
            .runEvaluation(assetID: asset.id, provider: "local-image-metrics"),
            .runEvaluation(assetID: asset.id, provider: "apple-vision")
        ], in: transport))
    }

    func testRequestVisibleAssetEvaluationsDispatchesForLoadedAssets() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation",
            assets: [first, second],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: first.id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: second.id, level: .grid)))

        XCTAssertTrue(model.canRequestVisibleAssetEvaluations)

        try model.requestVisibleAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(first.id.rawValue)-local-image-metrics"),
            WorkSessionID(rawValue: "evaluation-\(second.id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: first.id, provider: "local-image-metrics")
        ])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(first.id.rawValue)-local-image-metrics"),
            message: "completed local-image-metrics"
        )))
        XCTAssertTrue(waitForCommands([
            .runEvaluation(assetID: first.id, provider: "local-image-metrics"),
            .runEvaluation(assetID: second.id, provider: "local-image-metrics")
        ], in: transport))
    }

    func testRequestVisibleAssetEvaluationsSkipsAssetsWithoutCachedPreviews() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let cached = makeAsset(id: "cached", size: 1)
        let uncached = makeAsset(id: "uncached", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation-skips-uncached",
            assets: [cached, uncached],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: cached.id, level: .grid)))

        try model.requestVisibleAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(cached.id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: cached.id, provider: "local-image-metrics")
        ])
    }

    func testRequestCurrentScopeAssetEvaluationsDispatchesCachedAssetsBeyondLoadedPage() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let matchingAssets = (0..<121).map { index in
            makeAsset(
                id: "current-scope-evaluation-\(index)",
                path: "/Photos/current-scope-evaluation-\(index).jpg",
                rating: 0,
                colorLabel: .green
            )
        }
        let outsideAsset = makeAsset(
            id: "current-scope-evaluation-outside",
            path: "/Photos/current-scope-evaluation-outside.jpg",
            rating: 0,
            colorLabel: .red
        )
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "current-scope-evaluation",
            assets: matchingAssets + [outsideAsset],
            workerSupervisor: supervisor
        )
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: matchingAssets[0].id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: matchingAssets[120].id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: outsideAsset.id, level: .grid)))

        XCTAssertLessThan(model.assets.count, matchingAssets.count)
        XCTAssertFalse(model.assets.contains { $0.id == matchingAssets[120].id })
        XCTAssertTrue(model.canRequestCurrentScopeAssetEvaluations)

        try model.requestCurrentScopeAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(matchingAssets[0].id.rawValue)-local-image-metrics"),
            WorkSessionID(rawValue: "evaluation-\(matchingAssets[120].id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: matchingAssets[0].id, provider: "local-image-metrics")
        ])
    }

    func testRequestCompareAssetEvaluationsDispatchesOnlyCachedCompareAssets() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let compareAssets = (0..<8).map { makeAsset(id: "compare-\($0)", size: Int64($0 + 1)) }
        let outsideCompareSet = makeAsset(id: "outside-compare-set", size: 9)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "compare-evaluation-skips-uncached",
            assets: compareAssets + [outsideCompareSet],
            workerSupervisor: supervisor
        )
        model.selectedView = .compare
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: compareAssets[0].id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: compareAssets[2].id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: outsideCompareSet.id, level: .grid)))

        try model.requestCompareAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(compareAssets[0].id.rawValue)-local-image-metrics"),
            WorkSessionID(rawValue: "evaluation-\(compareAssets[2].id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: compareAssets[0].id, provider: "local-image-metrics")
        ])
    }

    func testCanRequestSelectedAssetEvaluationRequiresSelectionAndWorker() throws {
        let (modelWithoutWorker, _, _) = try makeModelWithPreviewCache(named: "evaluation-without-worker")
        XCTAssertFalse(modelWithoutWorker.canRequestSelectedAssetEvaluation)

        let modelWithoutSelection = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        XCTAssertFalse(modelWithoutSelection.canRequestSelectedAssetEvaluation)

        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: RecordingWorkerTransport()
        )
        let (model, _, _) = try makeModelWithPreviewCache(
            named: "evaluation-preview-required",
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestSelectedAssetEvaluation)
    }

    func testCanRequestVisibleAssetEvaluationsRequiresLoadedAssetsAndWorker() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "visible", size: 1)

        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [asset]).canRequestVisibleAssetEvaluations)
        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [], workerSupervisor: supervisor).canRequestVisibleAssetEvaluations)

        let (model, _, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation-preview-required",
            assets: [asset],
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestVisibleAssetEvaluations)
    }

    func testCanRequestCurrentScopeAssetEvaluationsRequiresCatalogAssetsAndWorker() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "current-scope", size: 1)

        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [asset]).canRequestCurrentScopeAssetEvaluations)
        XCTAssertFalse(AppModel(sidebarSections: [], selectedView: .grid, assets: [], workerSupervisor: supervisor).canRequestCurrentScopeAssetEvaluations)

        let (emptyModel, _, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "current-scope-evaluation-empty",
            assets: [],
            workerSupervisor: supervisor
        )
        XCTAssertFalse(emptyModel.canRequestCurrentScopeAssetEvaluations)

        let (model, _, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "current-scope-evaluation-preview-required",
            assets: [asset],
            workerSupervisor: supervisor
        )

        XCTAssertTrue(model.canRequestCurrentScopeAssetEvaluations)
    }

    func testSelectedEvaluationSignalsLoadFromCatalog() throws {
        let (model, repository, asset) = try makeModelWithCatalogAsset(named: "selected-signals")
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .exposure,
            value: .score(0.72),
            confidence: 0.9,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "average-preview-metrics", version: "1", settingsHash: "default")
        )
        try repository.recordEvaluationSignals([signal])

        XCTAssertEqual(model.selectedEvaluationSignals, [signal])
    }

    func testEvaluationSignalsCanLoadForNonSelectedAsset() throws {
        let selected = makeAsset(id: "selected", size: 1)
        let alternate = makeAsset(id: "alternate", size: 2)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "non-selected-evaluation-signals",
            assets: [selected, alternate]
        )
        let signal = EvaluationSignal(
            assetID: alternate.id,
            kind: .focus,
            value: .score(0.91),
            confidence: 0.88,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "sharpness", version: "1", settingsHash: "default")
        )
        try repository.recordEvaluationSignals([signal])

        XCTAssertEqual(model.selectedAssetID, selected.id)
        XCTAssertEqual(model.evaluationSignals(for: alternate.id), [signal])
    }

    func testSelectedSuggestedKeywordsComeFromObjectEvaluationLabels() throws {
        let asset = Asset(
            id: AssetID(rawValue: "suggested-keywords"),
            originalURL: URL(fileURLWithPath: "/Photos/suggested-keywords.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["camera"])
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "suggested-keywords", assets: [asset])
        let cameraProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision-camera", version: "1", settingsHash: "default")
        let mountainProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision-mountain", version: "1", settingsHash: "default")
        let lakeProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision-lake", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .object, value: .label("camera"), confidence: 0.91, provenance: cameraProvenance),
            EvaluationSignal(assetID: asset.id, kind: .object, value: .label("mountain"), confidence: 0.84, provenance: mountainProvenance),
            EvaluationSignal(assetID: asset.id, kind: .aesthetics, value: .label("keeper"), confidence: 0.98, provenance: mountainProvenance),
            EvaluationSignal(assetID: asset.id, kind: .object, value: .label("  alpine lake  "), confidence: 0.76, provenance: lakeProvenance)
        ])

        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.keyword), ["mountain", "alpine lake"])
        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.confidenceText), ["84%", "76%"])
        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.provenanceText), ["apple-vision/Vision-mountain", "apple-vision/Vision-lake"])
    }

    func testObjectEvaluationLabelsRemainProvisionalUntilAccepted() throws {
        let asset = Asset(
            id: AssetID(rawValue: "provisional-keyword"),
            originalURL: URL(fileURLWithPath: "/Photos/provisional-keyword.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["portfolio"])
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "provisional-keyword", assets: [asset])
        let provenance = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .object, value: .label("mountain"), confidence: 0.84, provenance: provenance)
        ])

        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.keyword), ["mountain"])
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, ["portfolio"])
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.keywords, ["portfolio"])
    }

    func testVisibleBatchKeywordSuggestionsAggregateObjectLabels() throws {
        let first = makeAsset(id: "first-batch-keyword", path: "/Photos/first.jpg", rating: 0)
        let second = makeAsset(id: "second-batch-keyword", path: "/Photos/second.jpg", rating: 0)
        let lake = makeAsset(id: "lake-batch-keyword", path: "/Photos/lake.jpg", rating: 0)
        let keyworded = makeAsset(
            id: "keyworded-batch-keyword",
            path: "/Photos/keyworded.jpg",
            rating: 0,
            keywords: ["mountain"]
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "batch-keyword-suggestions",
            assets: [first, second, lake, keyworded]
        )
        let apple = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let local = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: apple),
            EvaluationSignal(assetID: second.id, kind: .object, value: .label("mountain"), confidence: 0.6, provenance: local),
            EvaluationSignal(assetID: lake.id, kind: .object, value: .label("lake"), confidence: 0.9, provenance: local),
            EvaluationSignal(assetID: keyworded.id, kind: .object, value: .label("mountain"), confidence: 0.95, provenance: apple)
        ])

        let suggestions = model.visibleBatchKeywordSuggestions

        XCTAssertEqual(suggestions.map(\.keyword), ["mountain", "lake"])
        XCTAssertEqual(suggestions.map(\.assetCountText), ["2 photos", "1 photo"])
        XCTAssertEqual(suggestions.map(\.confidenceText), ["70%", "90%"])
        XCTAssertEqual(suggestions[0].provenanceText, "apple-vision/Vision")
    }

    func testAcceptVisibleBatchKeywordSuggestionWritesMatchingVisibleAssetsOnly() throws {
        let directory = try makeTemporaryDirectory(named: "batch-keyword-apply")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let firstURL = photosDirectory.appendingPathComponent("first.cr2")
        let secondURL = photosDirectory.appendingPathComponent("second.cr2")
        let thirdURL = photosDirectory.appendingPathComponent("third.cr2")
        try Data("first raw bytes".utf8).write(to: firstURL)
        try Data("second raw bytes".utf8).write(to: secondURL)
        try Data("third raw bytes".utf8).write(to: thirdURL)
        let first = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let third = Asset(
            id: AssetID(rawValue: "third"),
            originalURL: thirdURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 12, modificationDate: Date(timeIntervalSince1970: 12)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([first, second, third])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: second.id, kind: .object, value: .label("mountain"), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: third.id, kind: .object, value: .label("lake"), confidence: 0.9, provenance: provenance)
        ])

        let appliedCount = try model.acceptVisibleBatchKeywordSuggestion("mountain")

        XCTAssertEqual(appliedCount, 2)
        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: third.id).metadata.keywords, [])
        XCTAssertEqual(model.assets.map(\.metadata.keywords), [["mountain"], ["mountain"], []])
        XCTAssertEqual(model.visibleBatchKeywordSuggestions.map(\.keyword), ["lake"])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: firstURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: secondURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: thirdURL.appendingPathExtension("xmp").path))
    }

    func testAcceptLatestImportBatchKeywordSuggestionUsesImportOutputSet() throws {
        let directory = try makeTemporaryDirectory(named: "latest-import-batch-keyword-apply")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let firstURL = photosDirectory.appendingPathComponent("first.cr2")
        let secondURL = photosDirectory.appendingPathComponent("second.cr2")
        let thirdURL = photosDirectory.appendingPathComponent("third.cr2")
        try Data("first raw bytes".utf8).write(to: firstURL)
        try Data("second raw bytes".utf8).write(to: secondURL)
        try Data("third raw bytes".utf8).write(to: thirdURL)
        let first = Asset(
            id: AssetID(rawValue: "latest-import-first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "latest-import-second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let third = Asset(
            id: AssetID(rawValue: "latest-import-third"),
            originalURL: thirdURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 12, modificationDate: Date(timeIntervalSince1970: 12)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([first, second, third])
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "latest-import-output"),
            name: "Imported 2 photos from Card A",
            assetIDs: [first.id, second.id]
        )
        try repository.upsert(outputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "latest-import-session"),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported 2 photos from Card A",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: 2,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try repository.save(session)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        ))
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: second.id, kind: .object, value: .label("mountain"), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: third.id, kind: .object, value: .label("mountain"), confidence: 0.9, provenance: provenance)
        ])

        XCTAssertEqual(model.latestImportBatchKeywordSuggestions.map(\.keyword), ["mountain"])
        XCTAssertEqual(model.latestImportBatchKeywordSuggestions.map(\.assetCountText), ["2 photos"])

        let appliedCount = try model.acceptLatestImportBatchKeywordSuggestion("mountain")

        XCTAssertEqual(appliedCount, 2)
        XCTAssertEqual(model.selectedAssetSetID, outputSet.id)
        XCTAssertEqual(model.assets.map(\.id), [first.id, second.id])
        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: third.id).metadata.keywords, [])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: firstURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: secondURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: thirdURL.appendingPathExtension("xmp").path))
    }

    func testAcceptCurrentScopeBatchKeywordSuggestionUsesFullFilteredScopeBeyondLoadedPage() throws {
        let directory = try makeTemporaryDirectory(named: "current-scope-batch-keyword-apply")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let matchingAssets = try (0..<121).map { index in
            let url = photosDirectory.appendingPathComponent("matching-\(index).cr2")
            try Data("matching original \(index)".utf8).write(to: url)
            return Asset(
                id: AssetID(rawValue: "current-scope-keyword-matching-\(index)"),
                originalURL: url,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 10), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 10))),
                availability: .online,
                metadata: AssetMetadata(colorLabel: .green)
            )
        }
        let outsideURL = photosDirectory.appendingPathComponent("outside.cr2")
        try Data("outside original".utf8).write(to: outsideURL)
        let outsideAsset = Asset(
            id: AssetID(rawValue: "current-scope-keyword-outside"),
            originalURL: outsideURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 200, modificationDate: Date(timeIntervalSince1970: 200)),
            availability: .online,
            metadata: AssetMetadata(colorLabel: .red)
        )
        try repository.upsert(matchingAssets + [outsideAsset])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: matchingAssets[0].id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: matchingAssets[120].id, kind: .object, value: .label("mountain"), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: outsideAsset.id, kind: .object, value: .label("mountain"), confidence: 0.95, provenance: provenance)
        ])

        XCTAssertLessThan(model.assets.count, matchingAssets.count)
        XCTAssertFalse(model.assets.contains { $0.id == matchingAssets[120].id })
        XCTAssertEqual(model.currentScopeBatchKeywordSuggestions.map(\.keyword), ["mountain"])
        XCTAssertEqual(model.currentScopeBatchKeywordSuggestions.map(\.assetCountText), ["2 photos"])

        let appliedCount = try model.acceptCurrentScopeBatchKeywordSuggestion("mountain")

        XCTAssertEqual(appliedCount, 2)
        XCTAssertEqual(try repository.asset(id: matchingAssets[0].id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: matchingAssets[120].id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: outsideAsset.id).metadata.keywords, [])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: matchingAssets[0].originalURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: matchingAssets[120].originalURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideAsset.originalURL.appendingPathExtension("xmp").path))
    }

    func testAcceptSelectedBatchKeywordSuggestionUsesSelectedAssetsOnly() throws {
        let directory = try makeTemporaryDirectory(named: "selected-batch-keyword-apply")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let firstURL = photosDirectory.appendingPathComponent("first.cr2")
        let secondURL = photosDirectory.appendingPathComponent("second.cr2")
        let unselectedURL = photosDirectory.appendingPathComponent("unselected.cr2")
        try Data("first raw bytes".utf8).write(to: firstURL)
        try Data("second raw bytes".utf8).write(to: secondURL)
        try Data("unselected raw bytes".utf8).write(to: unselectedURL)
        let first = Asset(
            id: AssetID(rawValue: "selected-keyword-first"),
            originalURL: firstURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "selected-keyword-second"),
            originalURL: secondURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let unselected = Asset(
            id: AssetID(rawValue: "selected-keyword-unselected"),
            originalURL: unselectedURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 12, modificationDate: Date(timeIntervalSince1970: 12)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "selected-batch-keyword-suggestions",
            assets: [first, second, unselected]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: second.id, kind: .object, value: .label("lake"), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: unselected.id, kind: .object, value: .label("mountain"), confidence: 0.95, provenance: provenance)
        ])
        model.setBatchSelection(first.id, isSelected: true)
        model.setBatchSelection(second.id, isSelected: true)

        XCTAssertEqual(model.selectedBatchKeywordSuggestions.map(\.keyword), ["lake", "mountain"])
        XCTAssertEqual(model.selectedBatchKeywordSuggestions.map(\.assetCountText), ["1 photo", "1 photo"])

        let appliedCount = try model.acceptSelectedBatchKeywordSuggestion("mountain")

        XCTAssertEqual(appliedCount, 1)
        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, [])
        XCTAssertEqual(try repository.asset(id: unselected.id).metadata.keywords, [])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: firstURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.appendingPathExtension("xmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unselectedURL.appendingPathExtension("xmp").path))
    }

    func testAcceptSuggestedKeywordForSelectedAssetWritesCatalogAndXmp() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-accept-suggested-keyword")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "accept-suggested-keyword"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let provenance = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .object, value: .label("mountain"), confidence: 0.84, provenance: provenance)
        ])

        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.keyword), ["mountain"])

        try model.acceptSuggestedKeywordForSelectedAsset("mountain")

        let expectedKeywords = ["mountain"]
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, expectedKeywords)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.keywords, expectedKeywords)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(model.selectedSuggestedKeywords, [])
    }

    @MainActor
    func testEvaluationCompletionInvalidatesSelectedEvaluationSignals() async throws {
        let directory = try makeTemporaryDirectory(named: "evaluation-completion-signals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: directory.appendingPathComponent("asset.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
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
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .exposure,
            value: .score(0.42),
            confidence: 0.9,
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "average-preview-metrics", version: "1", settingsHash: "default")
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-image-metrics"),
            message: "evaluated \(asset.id.rawValue) with local-image-metrics"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(model.selectedEvaluationSignals, [signal])
    }

    @MainActor
    func testEvaluationCompletionRefreshesSignalSidebarRows() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "evaluation-sidebar-refresh", path: "/Photos/evaluation-sidebar-refresh.jpg", rating: 0)
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "evaluation-sidebar-refresh",
            assets: [asset],
            workerSupervisor: supervisor
        )
        let signal = EvaluationSignal(
            assetID: asset.id,
            kind: .faceQuality,
            value: .score(0.82),
            confidence: 0.82,
            provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        )

        XCTAssertNil(model.sidebarSections.first { $0.title == "AI" })

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        try model.requestEvaluation(assetID: asset.id, provider: "apple-vision")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-apple-vision"),
            message: "evaluated \(asset.id.rawValue) with apple-vision"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        let aiSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "AI" })
        XCTAssertEqual(aiSection.rowTitles, ["Faces"])
        XCTAssertEqual(aiSection.rows.first?.countText, "1")
    }

    @MainActor
    func testWorkerCompletionRefreshesVisibleBackgroundWork() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "preview-completion-refresh", size: 1)
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "preview-completion-refresh",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .large)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))
        try repository.markPreviewGenerated(assetID: asset.id, level: .large)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-large"),
            message: "generated large preview for \(asset.id.rawValue)"
        )))

        try await waitForVisibleWorkStatus(.completed, in: model)
    }

    @MainActor
    func testWorkerImportProgressRefreshesVisibleBackgroundWork() async throws {
        let directory = try makeTemporaryDirectory(named: "worker-import-progress-refresh")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: []
        )))

        try await waitForVisibleWorkDetail("Cataloged 3 photos", in: model)
        XCTAssertEqual(model.visibleWorkActivity?.completedUnitCount, 3)
        XCTAssertEqual(model.visibleWorkActivity?.totalUnitCount, 8)
    }

    @MainActor
    func testVisibleImportActivityUsesWorkerImportProgress() async throws {
        let directory = try makeTemporaryDirectory(named: "visible-import-progress")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        XCTAssertEqual(model.visibleImportActivity?.detail, "Importing from photos")

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: []
        )))

        try await waitForVisibleWorkDetail("Cataloged 3 photos", in: model)
        let activity = try XCTUnwrap(model.visibleImportActivity)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.detail, "Cataloged 3 photos")
        XCTAssertEqual(activity.completedUnitCount, 3)
        XCTAssertEqual(activity.totalUnitCount, 8)
        XCTAssertTrue(activity.showsProgress)
    }

    @MainActor
    func testWorkerFailureRefreshesVisibleBackgroundWork() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "preview-failure-refresh",
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .large)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-large"),
            message: "could not render preview"
        )))

        try await waitForVisibleWorkStatus(.failed, in: model)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "could not render preview")
    }

    @MainActor
    func testWorkerPreviewFailureRefreshesDurableFailureState() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "preview-durable-failure", size: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "preview-durable-failure",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .grid)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid")
        try repository.recordPreviewGenerationFailure(
            assetID: asset.id,
            level: .grid,
            errorMessage: "could not render preview"
        )

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "could not render preview"
        )))

        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)
        XCTAssertEqual(model.previewGenerationQueueStates.first?.lastErrorMessage, "could not render preview")
    }

    @MainActor
    func testWorkerEvaluationFailureRecordsProviderFailureReviewQueue() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "evaluation-provider-failure", path: "/Photos/evaluation-provider-failure.jpg", rating: 0, keywords: ["tagged"])
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "evaluation-provider-failure",
            assets: [asset],
            workerSupervisor: supervisor
        )
        let itemID = WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-http-model")
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestEvaluation(assetID: asset.id, provider: "local-http-model")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "model timed out"
        )))

        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)
        XCTAssertEqual(try repository.assetCount(matching: SetQuery(predicates: [.evaluationFailure])), 1)
        XCTAssertEqual(reviewQueueCount("Provider Failures", in: model), "1")

        let reviewSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Review" })
        let providerFailuresRow = try XCTUnwrap(reviewSection.rows.first { $0.title == "Provider Failures" })
        try model.selectSidebarRow(providerFailuresRow)

        XCTAssertTrue(model.providerFailuresFilter)
        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    @MainActor
    func testWorkerPreviewFailureRefreshesLoadedSourceAvailability() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "preview-failure-source-refresh", size: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "preview-failure-source-refresh",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .grid)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid")
        try repository.updateAvailability(assetID: asset.id, availability: .missing)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "original is missing"
        )))

        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)
        XCTAssertEqual(model.selectedAsset?.availability, .missing)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Sources" }?.rowTitles, ["Missing Originals"])
    }

    @MainActor
    func testWorkerPreviewFailureReloadsActiveAvailabilityFilter() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "preview-failure-source-filter", size: 1)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "preview-failure-source-filter",
            assets: [asset],
            workerSupervisor: supervisor
        )
        model.availabilityFilter = .online
        try model.applyLibraryFilters()
        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        try model.requestPreview(assetID: asset.id, level: .grid)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid")
        try repository.updateAvailability(assetID: asset.id, availability: .missing)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "original is missing"
        )))

        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)
        XCTAssertEqual(model.assets.map(\.id), [])
        XCTAssertEqual(model.totalAssetCount, 0)
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Sources" }?.rowTitles, ["Missing Originals"])
    }

    func testVisibleLoupePreviewRequestsMediumThenLargeWhenNeitherIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "loupe-progressive-preview",
            workerSupervisor: supervisor,
            sourceIsPresent: true
        )

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .medium)
        ])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-\(asset.id.rawValue)-medium",
            "preview-\(asset.id.rawValue)-large"
        ])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium"),
            message: "generated medium preview"
        )))

        XCTAssertTrue(waitForCommands([
            .generatePreview(assetID: asset.id, level: .medium),
            .generatePreview(assetID: asset.id, level: .large)
        ], in: transport))
    }

    func testVisibleLoupePreviewDoesNotDispatchWhenLargePreviewIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "loupe-progressive-cached-large",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testVisibleLoupePreviewUsesCachedPreviewWhenOriginalIsMissing() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "loupe-progressive-missing-original",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(model.selectedAsset?.availability, .missing)
        XCTAssertEqual(model.loupePreviewURL(for: asset.id), previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testVisibleLoupePreviewDoesNotDispatchWhenOriginalVolumeIsOffline() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(
            id: "offline-loupe",
            path: "/Volumes/TeststripOfflineVolume/offline-loupe.jpg",
            rating: 0
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "loupe-progressive-offline-original",
            assets: [asset],
            workerSupervisor: supervisor
        )

        try model.requestVisibleLoupePreview(assetID: asset.id)

        XCTAssertEqual(model.selectedAsset?.availability, .offline)
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
    }

    func testVisibleComparePreviewsRequestMediumForCompareAssetsBeforeLarge() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let (model, _, first, _) = try makeComparePreviewModel(
            named: "compare-progressive-previews",
            workerSupervisor: supervisor
        )

        try model.requestVisibleComparePreviews()

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-first-medium",
            "preview-second-medium"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: first.id, level: .medium)
        ])
    }

    func testVisibleComparePreviewsPromoteSelectedAssetToLargeWhenMediumIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let (model, previewCache, first, _) = try makeComparePreviewModel(
            named: "compare-progressive-selected-large",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: first.id, level: .medium)))

        try model.requestVisibleComparePreviews()

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-first-large",
            "preview-second-medium"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: first.id, level: .large)
        ])
    }

    func testVisibleComparePreviewsDoNotDispatchForUnavailableOriginals() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let offline = makeAsset(
            id: "offline-compare",
            path: "/Volumes/TeststripOfflineVolume/offline-compare.jpg",
            rating: 0,
            availability: .offline
        )
        let missing = makeAsset(
            id: "missing-compare",
            path: "/Photos/missing-compare.jpg",
            rating: 0,
            availability: .missing
        )
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "compare-unavailable-originals",
            assets: [offline, missing],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: offline.id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: missing.id, level: .grid)))

        try model.requestVisibleComparePreviews()

        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(model.loupePreviewURL(for: offline.id), previewCache.url(for: PreviewCacheKey(assetID: offline.id, level: .grid)))
        XCTAssertEqual(model.loupePreviewURL(for: missing.id), previewCache.url(for: PreviewCacheKey(assetID: missing.id, level: .grid)))
    }

    @MainActor
    func testComparePreviewRequestIDChangesWhenSelectedPreviewGenerationChanges() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, first, _) = try makeComparePreviewModel(
            named: "compare-request-id-preview-generation",
            workerSupervisor: supervisor
        )
        let initialRequestID = ComparePreviewRequestID.make(for: model)

        try model.requestPreview(assetID: first.id, level: .medium)
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: first.id, level: .medium)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(first.id.rawValue)-medium"),
            message: "generated medium preview"
        )))

        try await waitForPreviewCacheGeneration(1, for: first.id, in: model)
        XCTAssertNotEqual(ComparePreviewRequestID.make(for: model), initialRequestID)
    }

    func testVisibleGridPreviewRequestsGridPreviewWhenMissing() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "grid-visible-preview",
            workerSupervisor: supervisor
        )

        try model.requestVisibleGridPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .grid)])
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-\(asset.id.rawValue)-grid"
        ])
    }

    func testVisibleGridPreviewPromotesExistingQueuedPreviewWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let running = makeAsset(id: "running", size: 1)
        let olderQueued = makeAsset(id: "older", size: 2)
        let visible = makeAsset(id: "visible", size: 3)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "grid-promotes-existing-preview",
            assets: [running, olderQueued, visible],
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: running.id, level: .grid)
        try model.requestPreview(assetID: olderQueued.id, level: .grid)
        try model.requestPreview(assetID: visible.id, level: .grid)

        try model.requestVisibleGridPreview(assetID: visible.id)

        XCTAssertEqual(model.backgroundWorkQueue.queuedItems.map(\.id.rawValue), [
            "preview-\(visible.id.rawValue)-grid",
            "preview-\(olderQueued.id.rawValue)-grid"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: running.id, level: .grid)
        ])
    }

    func testVisibleGridPreviewDoesNotDispatchForKnownUnavailableOriginals() throws {
        for availability in [SourceAvailability.offline, .missing, .moved] {
            let transport = RecordingWorkerTransport()
            let supervisor = WorkerSupervisor(
                queue: BackgroundWorkQueue(maxRunningCount: 1),
                transport: transport
            )
            let directory = try makeTemporaryDirectory(named: "grid-known-\(availability.rawValue)")
            let asset = Asset(
                id: AssetID(rawValue: "known-\(availability.rawValue)"),
                originalURL: directory.appendingPathComponent("unavailable.jpg"),
                volumeIdentifier: "local",
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: availability,
                metadata: AssetMetadata()
            )
            let (model, _) = try makeModelWithCatalogAssets(
                named: "grid-known-\(availability.rawValue)",
                assets: [asset],
                workerSupervisor: supervisor
            )

            try model.requestVisibleGridPreview(assetID: asset.id)

            XCTAssertEqual(try transport.commands(), [], "unexpected grid preview command for \(availability.rawValue) asset")
            XCTAssertEqual(model.backgroundWorkQueue.items, [], "unexpected grid preview work for \(availability.rawValue) asset")
        }
    }

    @MainActor
    func testPreviewCompletionInvalidatesPreviewCacheGeneration() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-completion-invalidation")
        let source = directory.appendingPathComponent("source.jpg")
        try writeTestPNG(to: source)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let otherAsset = Asset(
            id: AssetID(rawValue: "asset-2"),
            originalURL: directory.appendingPathComponent("other.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(asset)
        try catalog.repository.upsert(otherAsset)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        try model.requestVisibleGridPreview(assetID: asset.id)
        let previewURL = catalog.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try writePreviewPlaceholder(to: previewURL)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-grid"),
            message: "generated grid preview for \(asset.id.rawValue)"
        )))

        try await waitForPreviewCacheGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(model.previewCacheGeneration(for: otherAsset.id), 0)
        XCTAssertEqual(model.gridPreviewURL(for: asset.id), previewURL)
    }

    func testBackgroundControlsForwardToWorkerSupervisor() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, _, asset) = try makeModelWithPreviewCache(
            named: "preview-controls",
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .medium)

        model.pauseBackgroundWork()
        model.resumeBackgroundWork()
        model.cancelBackgroundWork()

        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .medium),
            .pause,
            .resume,
            .cancelAll
        ])
        XCTAssertEqual(model.visibleWorkActivity?.status, .cancelled)
    }

    @MainActor
    func testIdleWorkerProcessCanBeStoppedWithoutCancellingCompletedWork() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "idle-worker-stop",
            workerSupervisor: supervisor
        )
        try model.requestPreview(assetID: asset.id, level: .medium)
        let itemID = WorkSessionID(rawValue: "preview-\(asset.id.rawValue)-medium")
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: asset.id, level: .medium)
        ])
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium))
        try writePreviewPlaceholder(to: previewURL)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: itemID,
            message: "generated medium preview"
        )))
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertTrue(model.isWorkerProcessRunning)
        XCTAssertTrue(model.canStopIdleWorkerProcess)
        XCTAssertEqual(model.idleWorkerStatusText, "Worker idle")

        model.stopIdleWorkerProcess()

        XCTAssertFalse(model.isWorkerProcessRunning)
        XCTAssertNil(model.idleWorkerStatusText)
        XCTAssertFalse(transport.isRunning)
        XCTAssertEqual(transport.terminateCount, 1)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: itemID)?.status, .completed)
        XCTAssertEqual(model.statusMessage, "Worker stopped")
    }

    func testCancellingQueuedEvaluationWorkPreservesRunningPreviewAndDoesNotCancelAll() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let previewAsset = makeAsset(id: "running-preview", size: 1)
        let evaluationAsset = makeAsset(id: "queued-evaluation", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "cancel-queued-evaluation",
            assets: [previewAsset, evaluationAsset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: evaluationAsset.id, level: .grid)))
        try model.requestPreview(assetID: previewAsset.id, level: .medium)
        try model.requestEvaluation(assetID: evaluationAsset.id, provider: "local-image-metrics")
        let previewID = WorkSessionID(rawValue: "preview-\(previewAsset.id.rawValue)-medium")
        let evaluationID = WorkSessionID(rawValue: "evaluation-\(evaluationAsset.id.rawValue)-local-image-metrics")

        model.cancelBackgroundWork(id: evaluationID)

        XCTAssertEqual(model.backgroundWorkQueue.item(id: evaluationID)?.status, .cancelled)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: previewID)?.status, .running)
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: previewAsset.id, level: .medium)
        ])
        XCTAssertNotEqual(model.statusMessage, "Cancelled import")
    }

    func testCancellingRunningLocalHTTPModelEvaluationRestartsWorkerAndStartsNextQueuedWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let evaluationAsset = makeAsset(id: "running-evaluation", size: 1)
        let previewAsset = makeAsset(id: "queued-preview", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "cancel-running-evaluation",
            assets: [evaluationAsset, previewAsset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: evaluationAsset.id, level: .grid)))
        try model.requestEvaluation(assetID: evaluationAsset.id, provider: "local-http-model")
        try model.requestPreview(assetID: previewAsset.id, level: .medium)
        let evaluationID = WorkSessionID(rawValue: "evaluation-\(evaluationAsset.id.rawValue)-local-http-model")
        let previewID = WorkSessionID(rawValue: "preview-\(previewAsset.id.rawValue)-medium")

        model.cancelBackgroundWork(id: evaluationID)

        XCTAssertEqual(model.backgroundWorkQueue.item(id: evaluationID)?.status, .cancelled)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: previewID)?.status, .running)
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: evaluationAsset.id, provider: "local-http-model"),
            .cancelAll,
            .generatePreview(assetID: previewAsset.id, level: .medium)
        ])
    }

    func testCanCancelBackgroundWorkActivityRequiresActiveBackgroundItem() {
        let runningItem = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "running"),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Rendering",
            status: .running,
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        let completedItem = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "completed"),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Done",
            status: .completed,
            completedUnitCount: 1,
            totalUnitCount: 1
        )
        let running = AppWorkActivity(workItem: runningItem)
        let completed = AppWorkActivity(workItem: completedItem)
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1, items: [runningItem, completedItem])
        )

        XCTAssertTrue(model.canCancelBackgroundWorkActivity(running))
        XCTAssertFalse(model.canCancelBackgroundWorkActivity(completed))
    }

    @MainActor
    func testBackgroundImportReloadsAssetsAndExposesGridPreviewURL() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importFolderInBackground(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        XCTAssertEqual(model.totalAssetCount, 1)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: result.importedAssets[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBackgroundImportWithWorkerDefersPreviewGenerationToWorker() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import-worker-previews")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        let result = try await model.importFolderInBackground(photoFolder)

        let assetID = result.importedAssets[0].id
        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertNil(model.gridPreviewURL(for: assetID))
        XCTAssertEqual(try catalog.repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: assetID, level: .micro),
            PreviewGenerationItem(assetID: assetID, level: .grid)
        ])
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: assetID, level: .micro)])
        XCTAssertEqual(model.visibleWorkActivity?.kind, .previewGeneration)
    }

    @MainActor
    func testBeginImportFolderWithWorkerEnqueuesManagedImportAndReloadsOnCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-folder-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        XCTAssertNil(model.activeWork)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(importItem.kind, .ingest)
        XCTAssertEqual(importItem.title, "Import photos")
        XCTAssertEqual(importItem.detail, "Importing from photos")
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder)])

        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .micro))
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .grid))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder),
            .generatePreview(assetID: importedAsset.id, level: .micro)
        ])
    }

    @MainActor
    func testLatestImportCompletionSummarySurfacesDeferredPreviewFailuresForWorkerImport() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-preview-failure-summary")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .micro))
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .grid))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)
        try catalog.repository.recordPreviewGenerationFailure(
            assetID: importedAsset.id,
            level: .micro,
            errorMessage: "could not render micro preview"
        )
        try catalog.repository.recordPreviewGenerationFailure(
            assetID: importedAsset.id,
            level: .grid,
            errorMessage: "could not render grid preview"
        )

        let summary = try XCTUnwrap(model.latestImportCompletionSummary)

        XCTAssertEqual(summary.previewFailureCount, 1)
        XCTAssertEqual(summary.failureText, "1 preview failure")
        XCTAssertEqual(summary.previewStatusText, "1 preview failure")
    }

    @MainActor
    func testWorkerImportCompletionReportsSkippedSourceFiles() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-skipped-source")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 1
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)

        XCTAssertEqual(model.statusMessage, "Imported 1 photo (1 file skipped)")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos (1 file skipped)")
    }

    @MainActor
    func testWorkerImportWaitingForDispatchPresentsAsWaiting() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-waiting-for-dispatch")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let previewAsset = Asset(
            id: AssetID(rawValue: "preview-ahead-of-import"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(previewAsset)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        try model.requestPreview(assetID: previewAsset.id, level: .grid)
        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.items.first { $0.kind == .ingest })
        XCTAssertEqual(importItem.status, .running)
        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: previewAsset.id, level: .grid)])
        let activity = try XCTUnwrap(model.visibleImportActivity)
        XCTAssertEqual(activity.status, .queued)
        XCTAssertEqual(ImportProgressPresentation.presentation(for: activity).phaseText, "Waiting")
    }

    @MainActor
    func testBeginImportFolderDoesNotEnqueueDuplicateImportWhileRunning() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-folder-import-duplicate")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        model.beginImportFolder(photoFolder)

        XCTAssertEqual(model.errorMessage, "Another import is already running")
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder)])
    }

    @MainActor
    func testBeginImportCardDoesNotEnqueueWhileFolderImportIsRunning() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-import-duplicate")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        let cardSource = directory.appendingPathComponent("DCIM", isDirectory: true)
        let cardDestination = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cardSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cardDestination, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        model.beginImportCard(source: cardSource, destinationRoot: cardDestination)

        XCTAssertEqual(model.errorMessage, "Another import is already running")
        XCTAssertEqual(model.backgroundWorkQueue.runningItems.count, 1)
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder)])
    }

    @MainActor
    func testBeginImportFolderWithWorkerRejectsMissingSourceWithoutEnqueueing() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-missing-source")
        let missingFolder = directory.appendingPathComponent("missing-photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(missingFolder)

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.errorMessage, "Source folder is missing")
        XCTAssertEqual(model.statusMessage, nil)
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try transport.commands(), [])
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from missing-photos: Source folder is missing")
        XCTAssertEqual(activity.failureCount, 1)
    }

    @MainActor
    func testBeginImportFolderRejectsMissingSourceWithoutStartingLocalImport() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-missing-source")
        let missingFolder = directory.appendingPathComponent("missing-photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportFolder(missingFolder)

        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Source folder is missing")
        XCTAssertEqual(model.statusMessage, nil)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from missing-photos: Source folder is missing")
    }

    @MainActor
    func testBeginImportFolderContinuesWhenSecurityScopeIsUnavailableByDefault() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-import-optional-security-scope")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let access = RecordingSecurityScopedResourceAccess(requiresSuccessfulAccess: false)
        let importTask = RecordingCall()
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _ in
                importTask.call()
                return Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            },
            resourceAccess: access.value
        )

        model.beginImportFolder(photoFolder)

        XCTAssertTrue(importTask.wasCalled)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(access.startedURLs, [photoFolder])
        XCTAssertEqual(access.stoppedURLs, [])
    }

    @MainActor
    func testCompletedFolderImportPersistsSecurityScopedBookmarkForSourceRoot() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-import-source-root-bookmark")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let imageURL = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: imageURL)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("source-root-bookmark".utf8)
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: false,
            grantedURLs: [photoFolder],
            bookmarkDataByURL: [photoFolder: bookmarkData]
        )
        let model = try AppModel.load(catalog: catalog, resourceAccess: access.value)

        model.beginImportFolder(photoFolder)

        try await waitForStatusMessage("Imported 1 photo", in: model)
        XCTAssertEqual(try catalog.repository.sourceRoots().first?.securityScopedBookmarkData, bookmarkData)
    }

    @MainActor
    func testLoadRestoresSecurityScopedAccessForBookmarkedSourceRoots() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-load-source-root-bookmark")
        let sourceRoot = directory.appendingPathComponent("photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("source-root-bookmark".utf8)
        try catalog.repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: false,
            grantedURLs: [sourceRoot],
            resolvedURLByBookmarkData: [bookmarkData: sourceRoot]
        )

        _ = try AppModel.load(catalog: catalog, resourceAccess: access.value)

        XCTAssertEqual(access.resolvedBookmarkData, [bookmarkData])
        XCTAssertEqual(access.startedURLs, [sourceRoot])
    }

    @MainActor
    func testLoadMarksSourceRootBookmarkRepairWhenBookmarkRestoreFails() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-load-source-root-bookmark-repair")
        let sourceRoot = directory.appendingPathComponent("photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("source-root-bookmark".utf8)
        try catalog.repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
        let access = RecordingSecurityScopedResourceAccess(requiresSuccessfulAccess: false)

        let model = try AppModel.load(catalog: catalog, resourceAccess: access.value)
        let diagnosticsSourceRoot = try XCTUnwrap(model.diagnosticsSnapshot.sourceRoots.first)

        XCTAssertEqual(access.resolvedBookmarkData, [bookmarkData])
        XCTAssertTrue(diagnosticsSourceRoot.hasSecurityScopedBookmark)
        XCTAssertTrue(diagnosticsSourceRoot.needsSecurityScopedBookmarkRepair)
        XCTAssertTrue(model.diagnosticsReportText.contains("bookmark repair needed"))
    }

    @MainActor
    func testLoadMarksSourceRootBookmarkRepairWhenBookmarkIsStaleButAccessible() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-load-source-root-stale-bookmark")
        let sourceRoot = directory.appendingPathComponent("photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("source-root-bookmark".utf8)
        try catalog.repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: false,
            grantedURLs: [sourceRoot],
            resolvedURLByBookmarkData: [bookmarkData: sourceRoot],
            staleBookmarkData: [bookmarkData]
        )

        let model = try AppModel.load(catalog: catalog, resourceAccess: access.value)
        let diagnosticsSourceRoot = try XCTUnwrap(model.diagnosticsSnapshot.sourceRoots.first)

        XCTAssertEqual(access.startedURLs, [sourceRoot])
        XCTAssertTrue(diagnosticsSourceRoot.needsSecurityScopedBookmarkRepair)
    }

    @MainActor
    func testBeginImportFolderRejectsSecurityScopeDenialWhenRequired() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-import-required-security-scope")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let access = RecordingSecurityScopedResourceAccess(requiresSuccessfulAccess: true)
        let importTask = RecordingCall()
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _ in
                importTask.call()
                return Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            },
            resourceAccess: access.value
        )

        model.beginImportFolder(photoFolder)

        XCTAssertFalse(importTask.wasCalled)
        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Import permission was not granted for photos")
        XCTAssertEqual(model.statusMessage, nil)
        XCTAssertEqual(access.startedURLs, [photoFolder])
        XCTAssertEqual(access.stoppedURLs, [])
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from photos: Import permission was not granted for photos")
    }

    @MainActor
    func testBeginImportCardStopsGrantedSourceWhenDestinationScopeIsDenied() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-destination-scope-denied")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: true,
            grantedURLs: [source]
        )
        let importTask = RecordingCall()
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _ in
                importTask.call()
                return Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            },
            resourceAccess: access.value
        )

        model.beginImportCard(source: source, destinationRoot: destinationRoot)

        XCTAssertFalse(importTask.wasCalled)
        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Import permission was not granted for Library")
        XCTAssertEqual(access.startedURLs, [source, destinationRoot])
        XCTAssertEqual(access.stoppedURLs, [source])
    }

    @MainActor
    func testBeginImportFolderWithWorkerRejectsSecurityScopeDenialWhenRequiredWithoutEnqueueing() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-required-security-scope")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let access = RecordingSecurityScopedResourceAccess(requiresSuccessfulAccess: true)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor, resourceAccess: access.value)

        model.beginImportFolder(photoFolder)

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.errorMessage, "Import permission was not granted for photos")
        XCTAssertEqual(model.statusMessage, nil)
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(access.startedURLs, [photoFolder])
        XCTAssertEqual(access.stoppedURLs, [])
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from photos: Import permission was not granted for photos")
    }

    @MainActor
    func testBeginImportFolderWithWorkerHoldsSecurityScopeUntilCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-holds-security-scope")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: true,
            grantedURLs: [photoFolder]
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor, resourceAccess: access.value)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)

        XCTAssertEqual(access.startedURLs, [photoFolder])
        XCTAssertEqual(access.stoppedURLs, [])

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: itemID,
            message: "imported 0 photos",
            importedAssetIDs: [],
            newAssetCount: 0,
            existingAssetCount: 0,
            skippedSourceFileCount: 0
        )))

        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)
        XCTAssertEqual(access.stoppedURLs, [photoFolder])
    }

    @MainActor
    func testBeginImportFolderWithWorkerImportsDisabledRunsLocalImportAndGeneratesPreview() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-import-with-worker-disabled")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let imageURL = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: imageURL)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: true,
            grantedURLs: [photoFolder]
        )
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: supervisor,
            resourceAccess: access.value,
            workerImportsEnabled: false
        )

        model.beginImportFolder(photoFolder)

        let assetID = try await waitForFirstAsset(in: model)
        let previewURL = try await waitForGridPreview(assetID: assetID, in: model)
        try await waitForStatusMessage("Imported 1 photo", in: model)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(access.startedURLs, [photoFolder])
        XCTAssertEqual(access.stoppedURLs, [photoFolder])
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
    }

    @MainActor
    func testBeginImportCardWithWorkerRejectsMissingSourceWithoutEnqueueing() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-missing-source")
        let missingSource = directory.appendingPathComponent("missing-card", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportCard(source: missingSource, destinationRoot: destinationRoot)

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.errorMessage, "Source folder is missing")
        XCTAssertEqual(model.statusMessage, nil)
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try transport.commands(), [])
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from missing-card to Library: Source folder is missing")
    }

    @MainActor
    func testBeginImportCardRejectsMissingSourceWithoutStartingLocalImport() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-missing-source")
        let missingSource = directory.appendingPathComponent("missing-card", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(source: missingSource, destinationRoot: destinationRoot)

        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Source folder is missing")
        XCTAssertEqual(model.statusMessage, nil)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from missing-card to Library: Source folder is missing")
    }

    @MainActor
    func testBeginImportCardWithWorkerRejectsMissingDestinationWithoutEnqueueing() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-missing-destination")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let missingDestination = directory.appendingPathComponent("missing-library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportCard(source: source, destinationRoot: missingDestination)

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.errorMessage, "Destination folder is missing")
        XCTAssertEqual(model.statusMessage, nil)
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try transport.commands(), [])
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from DCIM to missing-library: Destination folder is missing")
    }

    @MainActor
    func testBeginImportCardRejectsMissingDestinationWithoutStartingLocalImport() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-missing-destination")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let missingDestination = directory.appendingPathComponent("missing-library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(source: source, destinationRoot: missingDestination)

        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Destination folder is missing")
        XCTAssertEqual(model.statusMessage, nil)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from DCIM to missing-library: Destination folder is missing")
    }

    @MainActor
    func testBeginImportCardWithWorkerRejectsDestinationMatchingSourceWithoutEnqueueing() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-matching-destination")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportCard(source: source, destinationRoot: source)

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.errorMessage, "Destination must be different from the card source")
        XCTAssertEqual(model.statusMessage, nil)
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertEqual(try transport.commands(), [])
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from DCIM to DCIM: Destination must be different from the card source")
    }

    @MainActor
    func testBeginImportCardRejectsDestinationInsideSourceWithoutStartingLocalImport() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-nested-destination")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let nestedDestination = source.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDestination, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(source: source, destinationRoot: nestedDestination)

        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Destination cannot be inside the card source")
        XCTAssertEqual(model.statusMessage, nil)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from DCIM to Library: Destination cannot be inside the card source")
    }

    @MainActor
    func testWorkerImportPersistsRunningActivityAndReloadMarksItInterrupted() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-interrupted")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let runningSession = try catalog.repository.session(id: importItem.id)
        XCTAssertEqual(runningSession.kind, .ingest)
        XCTAssertEqual(runningSession.status, .running)
        XCTAssertEqual(runningSession.detail, "Importing from photos")

        let reloaded = try AppModel.load(catalog: catalog)
        let interruptedSession = try catalog.repository.session(id: importItem.id)
        XCTAssertEqual(interruptedSession.status, .failed)
        XCTAssertEqual(interruptedSession.detail, "Import interrupted before completion")
        XCTAssertEqual(interruptedSession.failureCount, 1)
        XCTAssertEqual(reloaded.recentWork.first?.id, importItem.id.rawValue)
        XCTAssertEqual(reloaded.recentWork.first?.status, .failed)
    }

    @MainActor
    func testInterruptedWorkerImportPreservesLastProgressDetail() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-interrupted-progress")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 7,
            totalUnitCount: 20,
            detail: "Cataloging 7 of 20 photos",
            catalogedAssetIDs: []
        )))
        try await waitForPersistedWorkDetail("Cataloging 7 of 20 photos", itemID: itemID, repository: catalog.repository)

        let reloaded = try AppModel.load(catalog: catalog)
        let interruptedSession = try catalog.repository.session(id: itemID)
        XCTAssertEqual(interruptedSession.status, .failed)
        XCTAssertEqual(interruptedSession.completedUnitCount, 7)
        XCTAssertEqual(interruptedSession.totalUnitCount, 20)
        XCTAssertEqual(interruptedSession.detail, "Import interrupted before completion (last progress: Cataloging 7 of 20 photos)")
        XCTAssertEqual(reloaded.recentWork.first?.detail, interruptedSession.detail)
    }

    @MainActor
    func testWorkerImportProgressShowsCatalogedAssetsBeforeCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("early.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-early-import"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 10,
            detail: "Cataloging 1 of 10 photos",
            catalogedAssetIDs: [importedAsset.id]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(model.visibleWorkActivity?.completedUnitCount, 1)
        XCTAssertEqual(model.visibleWorkActivity?.totalUnitCount, 10)
        XCTAssertEqual(model.visibleWorkActivity?.detail, "Cataloging 1 of 10 photos")
    }

    @MainActor
    func testWorkerImportProgressDoesNotReloadForEveryCatalogedAsset() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-coalesced-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let firstImage = photoFolder.appendingPathComponent("first.png")
        let secondImage = photoFolder.appendingPathComponent("second.png")
        try writeTestPNG(to: firstImage)
        try writeTestPNG(to: secondImage)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let firstAsset = Asset(
            id: AssetID(rawValue: "worker-early-import-first"),
            originalURL: firstImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let secondAsset = Asset(
            id: AssetID(rawValue: "worker-early-import-second"),
            originalURL: secondImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(firstAsset)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 10,
            detail: "Cataloging 1 of 10 photos",
            catalogedAssetIDs: [firstAsset.id]
        )))
        try await waitForSelectedAsset(firstAsset.id, in: model)

        try catalog.repository.upsert(secondAsset)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 2,
            totalUnitCount: 10,
            detail: "Cataloging 2 of 10 photos",
            catalogedAssetIDs: [secondAsset.id]
        )))

        try await waitForVisibleWorkDetail("Cataloging 2 of 10 photos", in: model)
        XCTAssertEqual(model.selectedAssetID, firstAsset.id)
        XCTAssertEqual(model.assets.map(\.id), [firstAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    @MainActor
    func testWorkerImportProgressPersistsRunningSessionDetail() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-progress-session")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 7,
            totalUnitCount: 20,
            detail: "Cataloging 7 of 20 photos",
            catalogedAssetIDs: []
        )))

        try await waitForPersistedWorkDetail("Cataloging 7 of 20 photos", itemID: itemID, repository: catalog.repository)
        let session = try catalog.repository.session(id: itemID)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.completedUnitCount, 7)
        XCTAssertEqual(session.totalUnitCount, 20)
        XCTAssertEqual(session.detail, "Cataloging 7 of 20 photos")
    }

    @MainActor
    func testWorkerImportProgressPrefersCatalogedAssetWhenCurrentPageIsFull() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-full-page-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("new.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        for index in 0..<120 {
            try catalog.repository.upsert(Asset(
                id: AssetID(rawValue: "existing-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/existing-\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))),
                availability: .online,
                metadata: AssetMetadata()
            ))
        }
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "existing-0"))

        model.beginImportFolder(photoFolder)
        let itemID = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first?.id)
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-early-import-full-page"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10_000, modificationDate: Date(timeIntervalSince1970: 10_000)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.progress(
            itemID: itemID,
            completedUnitCount: 1,
            totalUnitCount: 121,
            detail: "Cataloging 1 of 121 photos",
            catalogedAssetIDs: [importedAsset.id]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertEqual(model.totalAssetCount, 121)
        XCTAssertEqual(model.libraryCountText, "Showing 121-121 of 121 photographs")
        XCTAssertTrue(model.isImporting)
    }

    @MainActor
    func testFailedWorkerImportRecordsFailedActivityForReload() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-failure-activity")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: importItem.id,
            message: "disk read failed"
        )))

        try await waitForActivityStatus(.failed, in: model)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.id, importItem.id.rawValue)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from photos: disk read failed")
        XCTAssertEqual(activity.failureCount, 1)

        let reloaded = try AppModel.load(catalog: catalog)
        XCTAssertEqual(reloaded.recentWork.first?.id, importItem.id.rawValue)
        XCTAssertEqual(reloaded.recentWork.first?.status, .failed)
        XCTAssertEqual(reloaded.recentWork.first?.detail, "Import failed from photos: disk read failed")
    }

    @MainActor
    func testCancellingWorkerImportCancelsManagedBackgroundWork() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-cancel")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        XCTAssertTrue(model.isImporting)

        model.cancelBackgroundWork()

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.backgroundWorkQueue.items.first?.status, .cancelled)
        XCTAssertEqual(model.statusMessage, "Cancelled import")
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder),
            .cancelAll
        ])

        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.id, model.backgroundWorkQueue.items.first?.id.rawValue)
        XCTAssertEqual(activity.status, .cancelled)
        XCTAssertEqual(activity.detail, "Cancelled import from photos")

        let reloaded = try AppModel.load(catalog: catalog)
        XCTAssertEqual(reloaded.recentWork.first?.id, activity.id)
        XCTAssertEqual(reloaded.recentWork.first?.status, .cancelled)
        XCTAssertEqual(reloaded.recentWork.first?.detail, "Cancelled import from photos")
    }

    @MainActor
    func testCancellingVisibleWorkerImportPreservesOtherBackgroundWork() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-import-targeted-cancel")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        let previewItem = BackgroundWorkItem.testItem(id: "preview")
        let previewCommand = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .grid)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        try supervisor.enqueue(previewItem, command: previewCommand)

        model.cancelImportWork()

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: importItem.id)?.status, .cancelled)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: previewItem.id)?.status, .running)
        XCTAssertEqual(model.statusMessage, "Cancelled import")
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder),
            .cancelAll,
            previewCommand
        ])
        XCTAssertEqual(model.recentWork.first?.id, importItem.id.rawValue)
        XCTAssertEqual(model.recentWork.first?.status, .cancelled)
        XCTAssertEqual(model.recentWork.first?.detail, "Cancelled import from photos")
    }

    @MainActor
    func testBeginImportCardWithWorkerEnqueuesManagedCopyAndRecordsDestination() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-import")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sourceImage = source.appendingPathComponent("one.png")
        try writeTestPNG(to: sourceImage)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportCard(source: source, destinationRoot: destinationRoot)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        XCTAssertTrue(model.isImporting)
        XCTAssertEqual(importItem.kind, .ingest)
        XCTAssertEqual(importItem.detail, "Importing from DCIM to Library")
        XCTAssertEqual(try transport.commands(), [.importCard(source: source, destinationRoot: destinationRoot)])

        let destinationImage = destinationRoot.appendingPathComponent("one.png")
        let importedAsset = Asset(
            id: AssetID(rawValue: "worker-card-imported"),
            originalURL: destinationImage,
            volumeIdentifier: "Library",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from DCIM to Library",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.originalURL), [destinationImage])
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertEqual(model.recentWork.first?.detail, "Imported 1 photo from DCIM to Library")
        XCTAssertFalse(model.isImporting)
    }

    @MainActor
    func testBackgroundImportWithMissingWorkerExecutableGeneratesPreviewLocally() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import-missing-worker")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let model = try AppCatalog.loadModel(
            paths: paths,
            workerExecutableURL: directory.appendingPathComponent("missing-worker")
        )

        let result = try await model.importFolderInBackground(photoFolder)

        let assetID = result.importedAssets[0].id
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: assetID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.backgroundWorkQueue.items, [])
        XCTAssertFalse(model.canRequestSelectedAssetEvaluation)
    }

    @MainActor
    func testBackgroundImportRecordsCompletedActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-activity")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importFolderInBackground(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertNil(model.activeWork)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.title, "Import photos")
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(activity.completedUnitCount, 1)
        XCTAssertEqual(activity.failureCount, 0)
    }

    @MainActor
    func testBackgroundImportReportsSkippedSourceFilesInCompletionCopy() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-skipped-source")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        let skipped = photoFolder.appendingPathComponent("two.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let importedAsset = Asset(
            id: AssetID(rawValue: "imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { paths, _, _ in
                Task.detached {
                    let backgroundCatalog = try AppCatalog.open(paths: paths)
                    try backgroundCatalog.repository.upsert(importedAsset)
                    return AppImportOutput(
                        result: LibraryImportResult(
                            importedAssets: [importedAsset],
                            previewFailures: [],
                            skippedSourceFiles: [
                                LibrarySkippedSourceFile(
                                    sourceURL: skipped,
                                    message: "could not fingerprint \(skipped.path)"
                                )
                            ],
                            newAssetCount: 1,
                            existingAssetCount: 0
                        ),
                        assets: try backgroundCatalog.repository.allAssets(limit: 500),
                        totalAssetCount: try backgroundCatalog.repository.assetCount()
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)
        try await waitForActivityStatus(.completed, in: model)

        XCTAssertEqual(model.statusMessage, "Imported 1 photo (1 file skipped)")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos (1 file skipped)")
        XCTAssertEqual(activity.failureCount, 0)
    }

    @MainActor
    func testBackgroundImportReportsNoPhotosImportedWhenEverySourceFileIsSkipped() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-all-skipped")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let firstSkipped = photoFolder.appendingPathComponent("one.png")
        let secondSkipped = photoFolder.appendingPathComponent("two.png")
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _ in
                Task {
                    AppImportOutput(
                        result: LibraryImportResult(
                            importedAssets: [],
                            previewFailures: [],
                            skippedSourceFiles: [
                                LibrarySkippedSourceFile(sourceURL: firstSkipped, message: "could not fingerprint \(firstSkipped.path)"),
                                LibrarySkippedSourceFile(sourceURL: secondSkipped, message: "could not fingerprint \(secondSkipped.path)")
                            ],
                            newAssetCount: 0,
                            existingAssetCount: 0
                        ),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)
        try await waitForActivityStatus(.completed, in: model)

        XCTAssertEqual(model.statusMessage, "No photos imported (2 files skipped)")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.detail, "No photos imported from photos (2 files skipped)")
    }

    @MainActor
    func testBackgroundCardImportCopiesIntoDestinationAndRecordsActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-card-import")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destination = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let image = source.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: image)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importCardInBackground(source: source, destinationRoot: destination)

        let destinationImage = destination.appendingPathComponent("one.png")
        let destinationSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: destinationImage)
        let assetID = result.importedAssets[0].id
        XCTAssertEqual(result.importedAssets.map(\.originalURL), [destinationImage])
        XCTAssertEqual(model.assets.map(\.originalURL), [destinationImage])
        XCTAssertEqual(model.selectedAssetID, assetID)
        XCTAssertEqual(try catalog.repository.asset(id: assetID).metadata, metadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceSidecar.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationImage.path))
        XCTAssertEqual(try Data(contentsOf: destinationSidecar), sidecarData)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: assetID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.detail, "Imported 1 photo from DCIM to Library")
    }

    @MainActor
    func testBackgroundImportPersistsCompletedActivityForReload() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-activity-reload")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try await model.importFolderInBackground(photoFolder)
        XCTAssertFalse(model.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Imported 1 photo from photos")
        })

        let reloaded = try AppModel.load(catalog: catalog)
        let activity = try XCTUnwrap(reloaded.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .completed)
        XCTAssertEqual(activity.title, "Import photos")
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos")
        XCTAssertEqual(activity.completedUnitCount, 1)
        XCTAssertEqual(activity.totalUnitCount, 1)
        XCTAssertEqual(activity.failureCount, 0)
        XCTAssertFalse(reloaded.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Imported 1 photo from photos")
        })
        XCTAssertEqual(reloaded.sidebarSections.first { $0.title == "Recent Work" }?.rowTitles.first, "Imported 1 photo from photos")
        let session = try catalog.repository.session(id: WorkSessionID(rawValue: activity.id))
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        let outputSet = try catalog.repository.assetSet(id: outputSetID)
        if case .manual(let assetIDs) = outputSet.membership {
            XCTAssertEqual(assetIDs, [reloaded.assets[0].id])
        } else {
            XCTFail("import output set should be manual")
        }

        let row = try XCTUnwrap(reloaded.sidebarSections.first { $0.title == "Recent Work" }?.rows.first)
        try reloaded.selectSidebarRow(row)

        XCTAssertEqual(reloaded.selectedAssetSetID, outputSetID)
        XCTAssertEqual(reloaded.assets.map(\.originalURL), [image])
    }

    @MainActor
    func testLatestImportCompletionSummaryOpensImportedOutputSet() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-summary-open")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try await model.importFolderInBackground(photoFolder)
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)

        XCTAssertEqual(summary.title, "Import complete")
        XCTAssertEqual(summary.detail, "Imported 1 photo from photos")
        XCTAssertEqual(summary.importedPhotoCount, 1)
        XCTAssertEqual(summary.photoCountText, "1 photo")
        XCTAssertEqual(summary.previewFailureCount, 0)
        XCTAssertEqual(summary.previewStatusText, "Previews ready")
        XCTAssertEqual(summary.cullingSessionName, "Imported 1 photo from photos Cull")
        XCTAssertNil(summary.failureText)

        try model.openLatestImportCompletion()

        let session = try catalog.repository.session(id: WorkSessionID(rawValue: summary.activityID))
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(model.selectedAssetSetID, outputSetID)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedView, .grid)
    }

    func testLatestImportCompletionSummarySeparatesExistingReimportedPhotos() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-summary-reimport")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try model.importFolder(photoFolder)
        _ = try model.importFolder(photoFolder)
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)

        XCTAssertEqual(summary.detail, "No new photos found in photos")
        XCTAssertEqual(summary.importedPhotoCount, 1)
        XCTAssertEqual(summary.newPhotoCount, 0)
        XCTAssertEqual(summary.existingPhotoCount, 1)
        XCTAssertEqual(summary.photoCountText, "1 photo")
    }

    func testLatestImportCompletionSummaryReportsTimeAdjacentStacks() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "stack-summary-first",
            path: "/Photos/Import/stack-summary-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let second = makeAsset(
            id: "stack-summary-second",
            path: "/Photos/Import/stack-summary-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let singleton = makeAsset(
            id: "stack-summary-singleton",
            path: "/Photos/Import/stack-summary-singleton.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(10))
        )
        let (model, _) = try makeModelWithCompletedImportSession(
            named: "import-summary-stack-counts",
            assets: [first, second, singleton],
            outputAssetIDs: [first.id, second.id, singleton.id]
        )

        let summary = try XCTUnwrap(model.latestImportCompletionSummary)

        XCTAssertEqual(summary.stackCount, 1)
        XCTAssertEqual(summary.stackedPhotoCount, 2)
    }

    @MainActor
    func testBeginningCullingFromLatestImportUsesImportOutputSet() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-summary-cull")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try await model.importFolderInBackground(photoFolder)
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)
        let importSession = try catalog.repository.session(id: WorkSessionID(rawValue: summary.activityID))
        let outputSetID = try XCTUnwrap(importSession.outputSetIDs.first)

        let cullingSession = try model.beginCullingFromLatestImportCompletion()

        XCTAssertEqual(cullingSession.title, summary.cullingSessionName)
        XCTAssertEqual(cullingSession.inputSetIDs, [outputSetID])
        XCTAssertEqual(model.selectedAssetSetID, outputSetID)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testBeginningStackCullingFromLatestImportSelectsFirstDetectedStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let singleton = makeAsset(
            id: "stack-cull-singleton",
            path: "/Photos/Import/stack-cull-singleton.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let stackFirst = makeAsset(
            id: "stack-cull-first",
            path: "/Photos/Import/stack-cull-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(10))
        )
        let stackSecond = makeAsset(
            id: "stack-cull-second",
            path: "/Photos/Import/stack-cull-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(11))
        )
        let (model, repository) = try makeModelWithCompletedImportSession(
            named: "stack-culling-from-import",
            assets: [singleton, stackFirst, stackSecond],
            outputAssetIDs: [singleton.id, stackFirst.id, stackSecond.id]
        )

        let session = try model.beginStackCullingFromLatestImportCompletion()

        let stackSetID = try XCTUnwrap(session.inputSetIDs.first)
        XCTAssertTrue(stackSetID.rawValue.hasPrefix("work-stack-\(session.id.rawValue)-"))
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: stackSetID)), [stackFirst.id, stackSecond.id])
        XCTAssertEqual(model.selectedAssetSetID, stackSetID)
        XCTAssertEqual(model.assets.map(\.id), [stackFirst.id, stackSecond.id])
        XCTAssertEqual(session.intent, "Cull 1 stack from latest import")
        XCTAssertEqual(model.selectedAssetID, stackFirst.id)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.statusMessage, "Started stack cull with 1 stack")
        XCTAssertNil(try repository.asset(id: singleton.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: stackFirst.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: stackSecond.id).metadata.flag)
    }

    func testBeginningStackCullingFromLatestImportUsesVisualSimilaritySignals() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "visual-stack-first",
            path: "/Photos/Import/first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let similar = makeAsset(
            id: "visual-stack-similar",
            path: "/Photos/Other/similar.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let different = makeAsset(
            id: "visual-stack-different",
            path: "/Photos/Import/different.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(120))
        )
        let (model, repository) = try makeModelWithCompletedImportSession(
            named: "visual-stack-culling-from-import",
            assets: [first, similar, different],
            outputAssetIDs: [first.id, similar.id, different.id]
        )
        let provenance = ProviderProvenance(provider: "local-http-model", model: "embedding", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .visualSimilarity, value: .vector([0.1, 0.2, 0.3]), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: similar.id, kind: .visualSimilarity, value: .vector([0.11, 0.2, 0.29]), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: different.id, kind: .visualSimilarity, value: .vector([0.8, 0.1, 0.1]), confidence: 0.9, provenance: provenance)
        ])

        let session = try model.beginStackCullingFromLatestImportCompletion()

        let stackSetID = try XCTUnwrap(session.inputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: stackSetID)), [first.id, similar.id])
        XCTAssertEqual(model.selectedAssetSetID, stackSetID)
        XCTAssertEqual(model.assets.map(\.id), [first.id, similar.id])
        XCTAssertEqual(model.selectedAssetID, first.id)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.statusMessage, "Started stack cull with 1 stack")
        XCTAssertNil(try repository.asset(id: different.id).metadata.flag)
    }

    func testBeginningStackCullingFromLatestImportPersistsDetectedStackSets() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstStackLead = makeAsset(
            id: "persisted-stack-first-lead",
            path: "/Photos/Import/persisted-stack-first-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstStackAlternate = makeAsset(
            id: "persisted-stack-first-alternate",
            path: "/Photos/Import/persisted-stack-first-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let singleton = makeAsset(
            id: "persisted-stack-singleton",
            path: "/Photos/Import/persisted-stack-singleton.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(10))
        )
        let secondStackLead = makeAsset(
            id: "persisted-stack-second-lead",
            path: "/Photos/Import/persisted-stack-second-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(20))
        )
        let secondStackAlternate = makeAsset(
            id: "persisted-stack-second-alternate",
            path: "/Photos/Import/persisted-stack-second-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(21))
        )
        let assets = [firstStackLead, firstStackAlternate, singleton, secondStackLead, secondStackAlternate]
        let (model, repository) = try makeModelWithCompletedImportSession(
            named: "persist-stack-culling-from-import",
            assets: assets,
            outputAssetIDs: assets.map(\.id)
        )

        let session = try model.beginStackCullingFromLatestImportCompletion()

        XCTAssertEqual(session.inputSetIDs.count, 2)
        XCTAssertTrue(session.inputSetIDs.allSatisfy { $0.rawValue.hasPrefix("work-stack-\(session.id.rawValue)-") })
        if session.inputSetIDs.count == 2 {
            XCTAssertEqual(assetIDs(in: try repository.assetSet(id: session.inputSetIDs[0])), [firstStackLead.id, firstStackAlternate.id])
            XCTAssertEqual(assetIDs(in: try repository.assetSet(id: session.inputSetIDs[1])), [secondStackLead.id, secondStackAlternate.id])
            XCTAssertEqual(model.selectedAssetSetID, session.inputSetIDs[0])
        }
        XCTAssertEqual(model.assets.map(\.id), [firstStackLead.id, firstStackAlternate.id])
        XCTAssertEqual(model.selectedAssetID, firstStackLead.id)

        model.selectedView = .compare

        XCTAssertEqual(model.compareAssets().map(\.id), [firstStackLead.id, firstStackAlternate.id])
        XCTAssertFalse(model.sidebarSections.contains { section in
            section.title == "Saved Sets"
                && section.rowTitles.contains { $0.localizedCaseInsensitiveContains("Stack 1") }
        })
    }

    func testBeginningStackCullingFromLatestImportLoadsFirstStackBeyondInitialPage() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let singletons = (0..<130).map { index in
            makeAsset(
                id: "stack-cull-leading-singleton-\(index)",
                path: "/Photos/Import/leading-\(index).cr2",
                rating: 0,
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(TimeInterval(index * 10)))
            )
        }
        let stackFirst = makeAsset(
            id: "stack-cull-late-first",
            path: "/Photos/Import/stack-cull-late-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2_000))
        )
        let stackSecond = makeAsset(
            id: "stack-cull-late-second",
            path: "/Photos/Import/stack-cull-late-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2_001))
        )
        let assets = singletons + [stackFirst, stackSecond]
        let (model, _) = try makeModelWithCompletedImportSession(
            named: "stack-culling-from-import-late-stack",
            assets: assets,
            outputAssetIDs: assets.map(\.id)
        )

        XCTAssertFalse(model.assets.contains { $0.id == stackFirst.id })
        XCTAssertEqual(model.latestImportCompletionSummary?.stackCount, 1)

        _ = try model.beginStackCullingFromLatestImportCompletion()

        XCTAssertEqual(model.selectedAssetID, stackFirst.id)
        XCTAssertEqual(model.assets.first?.id, stackFirst.id)
        XCTAssertEqual(model.selectedView, .loupe)
    }

    @MainActor
    func testReviewingLatestImportInCompareUsesImportOutputSet() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-summary-compare")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try await model.importFolderInBackground(photoFolder)
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)
        let importSession = try catalog.repository.session(id: WorkSessionID(rawValue: summary.activityID))
        let outputSetID = try XCTUnwrap(importSession.outputSetIDs.first)

        try model.reviewLatestImportInCompare()

        XCTAssertEqual(model.selectedAssetSetID, outputSetID)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedView, .compare)
        XCTAssertEqual(model.compareAssets().map(\.originalURL), [image])
    }

    @MainActor
    func testCancellingActiveImportRecordsCancelledActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-cancel-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)
        XCTAssertEqual(model.activeWork?.status, .running)

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)

        XCTAssertNil(model.activeWork)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .cancelled)
        XCTAssertEqual(activity.detail, "Cancelled import from photos")
        XCTAssertEqual(model.statusMessage, "Cancelled import")
    }

    @MainActor
    func testBeginImportFolderRecordsRunningActivityImmediately() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-running-import-activity")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)

        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.kind, .ingest)
        XCTAssertEqual(activity.status, .running)
        XCTAssertEqual(activity.detail, "Importing from photos")
        XCTAssertEqual(model.sidebarSections.first { $0.title == "Recent Work" }?.rowTitles.first, "Importing from photos")
        let persisted = try catalog.repository.session(id: WorkSessionID(rawValue: activity.id))
        XCTAssertEqual(persisted.status, .running)
        XCTAssertEqual(persisted.detail, "Importing from photos")

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)
    }

    @MainActor
    func testCancellingActiveCardImportRecordsCancelledActivity() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-cancel-card-import")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destination = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(source: source, destinationRoot: destination)
        XCTAssertEqual(model.activeWork?.detail, "Importing from DCIM to Library")

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)

        XCTAssertNil(model.activeWork)
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .cancelled)
        XCTAssertEqual(activity.detail, "Cancelled import from DCIM to Library")
        XCTAssertEqual(model.statusMessage, "Cancelled import")
    }

    @MainActor
    func testBackgroundImportAppliesProgressUpdatesBeforeCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-progress")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, progress in
                Task {
                    progress(LibraryImportProgress(
                        completedUnitCount: 1,
                        totalUnitCount: 2,
                        detail: "Generated 1 of 2 previews"
                    ))
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)

        try await waitForActiveWorkProgress(
            completedUnitCount: 1,
            totalUnitCount: 2,
            detail: "Generated 1 of 2 previews",
            in: model
        )
        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)
    }

    @MainActor
    func testBackgroundImportShowsCatalogedAssetsBeforePreviewCompletion() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-early-assets")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("early.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let importedAsset = Asset(
            id: AssetID(rawValue: "early-import"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { paths, _, progress in
                Task.detached {
                    let backgroundCatalog = try AppCatalog.open(paths: paths)
                    try backgroundCatalog.repository.upsert(importedAsset)
                    progress(LibraryImportProgress(
                        completedUnitCount: 1,
                        totalUnitCount: 1,
                        detail: "Cataloged 1 photo",
                        catalogedAssetIDs: [importedAsset.id]
                    ))
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [importedAsset], previewFailures: []),
                        assets: try backgroundCatalog.repository.allAssets(limit: 500),
                        totalAssetCount: try backgroundCatalog.repository.assetCount()
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)

        try await waitForSelectedAsset(importedAsset.id, in: model)
        XCTAssertEqual(model.assets.map(\.id), [importedAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)
        XCTAssertEqual(model.activeWork?.status, .running)

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeTestPNG(to url: URL) throws {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
    }

    private func writePreviewPlaceholder(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: url)
    }

    private func sidebarRowCount(_ rowTitle: String, in sectionTitle: String, of model: AppModel) -> String? {
        model.sidebarSections
            .first { $0.title == sectionTitle }?
            .rows
            .first { $0.title == rowTitle }?
            .countText
    }

    private func reviewQueueCount(_ title: String, in model: AppModel) -> String? {
        sidebarRowCount(title, in: "Review", of: model)
    }

    private func fileFingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func seedCatalogAssets(count: Int, repository: CatalogRepository) throws {
        let batchSize = 1_000
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, count)
            let assets = (batchStart..<batchEnd).map { index in
                Asset(
                    id: AssetID(rawValue: "asset-\(index)"),
                    originalURL: URL(fileURLWithPath: "/Volumes/NAS/Photos/frame-\(index).dng"),
                    volumeIdentifier: "NAS",
                    fingerprint: FileFingerprint(
                        size: Int64(index + 1),
                        modificationDate: Date(timeIntervalSince1970: TimeInterval(index))
                    ),
                    availability: index.isMultiple(of: 2) ? .online : .offline,
                    metadata: AssetMetadata(rating: index % 6)
                )
            }
            try repository.upsert(assets)
        }
    }

    private func seedTimelineCatalogAssets(
        count: Int,
        selectedDayCount: Int,
        selectedCapturedAt: Date,
        otherCapturedAt: Date,
        repository: CatalogRepository
    ) throws {
        let batchSize = 1_000
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, count)
            let assets = (batchStart..<batchEnd).map { index in
                let capturedAt = index < selectedDayCount ? selectedCapturedAt : otherCapturedAt
                return Asset(
                    id: AssetID(rawValue: "timeline-\(index)"),
                    originalURL: URL(fileURLWithPath: "/Volumes/NAS/Timeline/frame-\(index).dng"),
                    volumeIdentifier: "NAS",
                    fingerprint: FileFingerprint(
                        size: Int64(index + 1),
                        modificationDate: Date(timeIntervalSince1970: TimeInterval(index))
                    ),
                    availability: .online,
                    metadata: AssetMetadata(),
                    technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
                )
            }
            try repository.upsert(assets)
        }
    }

    private func makeModelWithSeededCatalog(named name: String, count: Int) throws -> AppModel {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try seedCatalogAssets(count: count, repository: repository)
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
        return try AppModel.load(catalog: catalog)
    }

    private func makeAsset(id: String, size: Int64) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: size, modificationDate: Date(timeIntervalSince1970: TimeInterval(size))),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        date(year: year, month: month, day: day, hour: 12, calendar: calendar)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private func makeAsset(
        id: String,
        path: String,
        rating: Int,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        availability: SourceAvailability = .online,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: availability,
            metadata: AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords),
            technicalMetadata: technicalMetadata
        )
    }

    private func makeModelWithPreviewCache(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil,
        pendingPreviewLevel: PreviewLevel? = nil,
        sourceIsPresent: Bool = false
    ) throws -> (AppModel, PreviewCache, Asset) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let originalURL = sourceIsPresent
            ? directory.appendingPathComponent("\(name).jpg")
            : URL(fileURLWithPath: "/Photos/\(name).jpg")
        if sourceIsPresent {
            try Data("original".utf8).write(to: originalURL)
        }
        let originalFingerprint = sourceIsPresent
            ? try fileFingerprint(for: originalURL)
            : FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10))
        let asset = Asset(
            id: AssetID(rawValue: name),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: originalFingerprint,
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        if let pendingPreviewLevel {
            try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: pendingPreviewLevel))
        }
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), previewCache, asset)
    }

    private func makeModelWithPendingPreviewBacklog(
        named name: String,
        assetCount: Int,
        workerSupervisor: WorkerSupervisor,
        configureDatabase: ((CatalogDatabase) -> Void)? = nil
    ) throws -> (AppModel, CatalogRepository, [Asset]) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        configureDatabase?(database)
        let repository = CatalogRepository(database: database)
        let assets = (0..<assetCount).map { index in
            makeAsset(id: "asset-\(index)", path: "/Photos/asset-\(index).jpg", rating: 0)
        }
        try repository.upsert(assets)
        for asset in assets {
            try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        }
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, assets)
    }

    private func makeModelWithCatalogAsset(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, CatalogRepository, Asset) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: name),
            originalURL: URL(fileURLWithPath: "/Photos/\(name).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, asset)
    }

    private func makeWorkerMetadataSyncModel(
        named name: String,
        assetID: String
    ) throws -> (AppModel, CatalogRepository, Asset, URL, RecordingWorkerTransport) {
        let directory = try makeTemporaryDirectory(named: name)
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: assetID),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: supervisor), repository, asset, originalURL, transport)
    }

    private func makePendingMetadataSyncScopeModel(
        named name: String,
        includeWorker: Bool = true
    ) throws -> (model: AppModel, transport: RecordingWorkerTransport, retryableAssetID: AssetID) {
        let directory = try makeTemporaryDirectory(named: name)
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let retryableURL = photosDirectory.appendingPathComponent("retryable.cr2")
        let offlineURL = photosDirectory.appendingPathComponent("offline.cr2")
        let blockedURL = photosDirectory.appendingPathComponent("blocked.cr2")
        try Data("retryable raw bytes".utf8).write(to: retryableURL)
        try Data("offline raw bytes".utf8).write(to: offlineURL)
        try Data("blocked raw bytes".utf8).write(to: blockedURL)

        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let retryable = Asset(
            id: AssetID(rawValue: "retryable"),
            originalURL: retryableURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let offline = Asset(
            id: AssetID(rawValue: "offline"),
            originalURL: offlineURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .offline,
            metadata: AssetMetadata()
        )
        let blocked = Asset(
            id: AssetID(rawValue: "blocked"),
            originalURL: blockedURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 12, modificationDate: Date(timeIntervalSince1970: 12)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert([retryable, offline, blocked])

        let blockedSidecarDirectory = directory.appendingPathComponent("missing-sidecars", isDirectory: true)
        let pendingItems = [
            MetadataSyncItem(
                assetID: retryable.id,
                sidecarURL: retryableURL.appendingPathExtension("xmp"),
                catalogGeneration: try repository.catalogGeneration(assetID: retryable.id),
                lastSyncedFingerprint: nil
            ),
            MetadataSyncItem(
                assetID: offline.id,
                sidecarURL: offlineURL.appendingPathExtension("xmp"),
                catalogGeneration: try repository.catalogGeneration(assetID: offline.id),
                lastSyncedFingerprint: nil
            ),
            MetadataSyncItem(
                assetID: blocked.id,
                sidecarURL: blockedSidecarDirectory.appendingPathComponent("blocked.cr2.xmp"),
                catalogGeneration: try repository.catalogGeneration(assetID: blocked.id),
                lastSyncedFingerprint: nil
            )
        ]
        for item in pendingItems {
            try repository.recordMetadataSyncPending(item)
        }

        let transport = RecordingWorkerTransport()
        let supervisor = includeWorker
            ? WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: transport)
            : nil
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
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [retryable, offline, blocked],
            totalAssetCount: 3,
            catalog: catalog,
            pendingMetadataSyncItems: pendingItems,
            pendingMetadataSyncCount: pendingItems.count,
            workerSupervisor: supervisor
        )
        return (model, transport, retryable.id)
    }

    private func makeModelWithXMPConflict(
        named name: String,
        catalogMetadata: AssetMetadata,
        sidecarMetadata: AssetMetadata
    ) throws -> (AppModel, CatalogRepository, Asset, URL, URL) {
        let directory = try makeTemporaryDirectory(named: name)
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: name),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: catalogMetadata
        )
        try repository.upsert(asset)
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        try sidecarData.write(to: sidecarURL)
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: sidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            lastSyncedFingerprint: "old"
        )
        try repository.recordMetadataSyncConflict(conflict)
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        )
        return (try AppModel.load(catalog: catalog), repository, asset, originalURL, sidecarURL)
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset],
        configureRepository: (CatalogRepository) throws -> Void = { _ in },
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, CatalogRepository) {
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: name,
            assets: assets,
            configureRepository: configureRepository,
            workerSupervisor: workerSupervisor
        )
        return (result.model, result.repository)
    }

    private func makeModelWithCatalogAssetsAndPreviewCache(
        named name: String,
        assets: [Asset],
        configureRepository: (CatalogRepository) throws -> Void = { _ in },
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        try configureRepository(repository)
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, previewCache)
    }

    private func assetIDs(in assetSet: AssetSet) -> [AssetID] {
        switch assetSet.membership {
        case .manual(let assetIDs), .snapshot(let assetIDs):
            assetIDs
        case .dynamic:
            []
        }
    }

    private struct PersistedStackCullingFixture {
        var model: AppModel
        var repository: CatalogRepository
        var firstLead: Asset
        var firstAlternate: Asset
        var secondLead: Asset
        var secondAlternate: Asset
        var firstSet: AssetSet
        var secondSet: AssetSet
    }

    private func makePersistedStackCullingFixture(
        named name: String,
        sessionID: String
    ) throws -> PersistedStackCullingFixture {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstLead = makeAsset(
            id: "\(name)-first-lead",
            path: "/Photos/Stack/\(name)-first-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstAlternate = makeAsset(
            id: "\(name)-first-alternate",
            path: "/Photos/Stack/\(name)-first-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let secondLead = makeAsset(
            id: "\(name)-second-lead",
            path: "/Photos/Stack/\(name)-second-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(20))
        )
        let secondAlternate = makeAsset(
            id: "\(name)-second-alternate",
            path: "/Photos/Stack/\(name)-second-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(21))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [firstLead, firstAlternate, secondLead, secondAlternate]
        )
        let firstSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-\(sessionID)-1"),
            name: "Cull Stack 1",
            assetIDs: [firstLead.id, firstAlternate.id]
        )
        let secondSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-stack-\(sessionID)-2"),
            name: "Cull Stack 2",
            assetIDs: [secondLead.id, secondAlternate.id]
        )
        try repository.upsert(firstSet)
        try repository.upsert(secondSet)
        try repository.save(cullingSession(id: sessionID, inputSetIDs: [firstSet.id, secondSet.id], totalUnitCount: 4))

        return PersistedStackCullingFixture(
            model: model,
            repository: repository,
            firstLead: firstLead,
            firstAlternate: firstAlternate,
            secondLead: secondLead,
            secondAlternate: secondAlternate,
            firstSet: firstSet,
            secondSet: secondSet
        )
    }

    private func cullingSession(id: String, inputSetIDs: [AssetSetID], totalUnitCount: Int) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .culling,
            intent: "Cull persisted stacks",
            title: "Cull persisted stacks",
            detail: "Cull persisted stacks",
            status: .running,
            inputSetIDs: inputSetIDs,
            outputSetIDs: [],
            completedUnitCount: 0,
            totalUnitCount: totalUnitCount,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func makeModelWithCompletedImportSession(
        named name: String,
        assets: [Asset],
        outputAssetIDs: [AssetID]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "latest-import-output"),
            name: "Imported photos",
            assetIDs: outputAssetIDs
        )
        try repository.upsert(outputSet)
        try repository.save(WorkSession(
            id: WorkSessionID(rawValue: "latest-import-session"),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported \(outputAssetIDs.count) photos from Import",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: outputAssetIDs.count,
            totalUnitCount: outputAssetIDs.count,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        ))
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

    private func makeComparePreviewModel(
        named name: String,
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, PreviewCache, Asset, Asset) {
        let directory = try makeTemporaryDirectory(named: name)
        let firstURL = directory.appendingPathComponent("first.jpg")
        let secondURL = directory.appendingPathComponent("second.jpg")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)
        let first = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: firstURL,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: firstURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "second"),
            originalURL: secondURL,
            volumeIdentifier: "local",
            fingerprint: try fileFingerprint(for: secondURL),
            availability: .online,
            metadata: AssetMetadata()
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: name,
            assets: [first, second],
            workerSupervisor: workerSupervisor
        )
        return (result.model, result.previewCache, first, second)
    }

    @MainActor
    private func waitForActivityStatus(_ status: WorkSessionStatus, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.recentWork.first?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for activity status \(status.rawValue)")
    }

    @MainActor
    private func waitForVisibleWorkStatus(_ status: WorkSessionStatus, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.visibleWorkActivity?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for visible work status \(status.rawValue)")
    }

    @MainActor
    private func waitForBackgroundWorkStatus(
        _ status: WorkSessionStatus,
        itemID: WorkSessionID,
        in model: AppModel
    ) async throws {
        for _ in 0..<100 {
            if model.backgroundWorkQueue.item(id: itemID)?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for background work status \(status.rawValue)")
    }

    @MainActor
    private func waitForVisibleWorkDetail(_ detail: String, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.visibleWorkActivity?.detail == detail {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for visible work detail \(detail)")
    }

    @MainActor
    private func waitForPersistedWorkDetail(
        _ detail: String,
        itemID: WorkSessionID,
        repository: CatalogRepository
    ) async throws {
        for _ in 0..<100 {
            if try repository.session(id: itemID).detail == detail {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for persisted work detail \(detail)")
    }

    @MainActor
    private func waitForSelectedAsset(_ assetID: AssetID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.selectedAssetID == assetID {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for selected asset \(assetID.rawValue)")
    }

    @MainActor
    private func waitForFirstAsset(in model: AppModel) async throws -> AssetID {
        for _ in 0..<100 {
            if let assetID = model.assets.first?.id {
                return assetID
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw TeststripError.invalidState("timed out waiting for first asset")
    }

    @MainActor
    private func waitForGridPreview(assetID: AssetID, in model: AppModel) async throws -> URL {
        for _ in 0..<100 {
            if let previewURL = model.gridPreviewURL(for: assetID) {
                return previewURL
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw TeststripError.invalidState("timed out waiting for grid preview")
    }

    @MainActor
    private func waitForStatusMessage(_ statusMessage: String, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.statusMessage == statusMessage {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw TeststripError.invalidState("timed out waiting for status \(statusMessage)")
    }

    @MainActor
    private func waitForActiveWorkProgress(
        completedUnitCount: Int,
        totalUnitCount: Int?,
        detail: String,
        in model: AppModel
    ) async throws {
        for _ in 0..<100 {
            if model.activeWork?.completedUnitCount == completedUnitCount,
               model.activeWork?.totalUnitCount == totalUnitCount,
               model.activeWork?.detail == detail {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for active import progress")
    }

    private func waitForCommands(
        _ expected: [WorkerCommand],
        in transport: RecordingWorkerTransport,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? transport.commands()) == expected {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return (try? transport.commands()) == expected
    }

    private func commandDescription(_ transport: RecordingWorkerTransport) -> String {
        (try? "\(transport.commands())") ?? "could not decode commands"
    }

    private func waitForBackgroundWorkItem(
        _ itemID: WorkSessionID,
        in model: AppModel,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.backgroundWorkQueue.item(id: itemID) != nil {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return model.backgroundWorkQueue.item(id: itemID) != nil
    }

    private func waitForBackgroundWorkItemRemoval(
        _ itemID: WorkSessionID,
        in model: AppModel,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.backgroundWorkQueue.item(id: itemID) == nil {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return model.backgroundWorkQueue.item(id: itemID) == nil
    }

    @MainActor
    private func waitForPreviewCacheGeneration(_ generation: Int, for assetID: AssetID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.previewCacheGeneration(for: assetID) == generation {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for preview cache generation \(generation)")
    }

    @MainActor
    private func waitForEvaluationSignalGeneration(_ generation: Int, for assetID: AssetID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.evaluationSignalGeneration(for: assetID) == generation {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for evaluation signal generation \(generation)")
    }
}

private extension BackgroundWorkItem {
    static func testItem(id: String) -> BackgroundWorkItem {
        BackgroundWorkItem(
            id: WorkSessionID(rawValue: id),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Rendering cached previews",
            completedUnitCount: 0,
            totalUnitCount: 10
        )
    }
}

private final class RecordingCall: @unchecked Sendable {
    private(set) var wasCalled = false

    func call() {
        wasCalled = true
    }
}

private final class RecordingSecurityScopedResourceAccess: @unchecked Sendable {
    let requiresSuccessfulAccess: Bool
    private let grantedPaths: Set<String>
    private let bookmarkDataByPath: [String: Data]
    private let resolvedURLByBookmarkData: [Data: URL]
    private let staleBookmarkData: Set<Data>
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []
    private(set) var resolvedBookmarkData: [Data] = []

    init(
        requiresSuccessfulAccess: Bool,
        grantedURLs: [URL] = [],
        bookmarkDataByURL: [URL: Data] = [:],
        resolvedURLByBookmarkData: [Data: URL] = [:],
        staleBookmarkData: Set<Data> = []
    ) {
        self.requiresSuccessfulAccess = requiresSuccessfulAccess
        self.grantedPaths = Set(grantedURLs.map(\.path))
        self.bookmarkDataByPath = Dictionary(uniqueKeysWithValues: bookmarkDataByURL.map { ($0.key.path, $0.value) })
        self.resolvedURLByBookmarkData = resolvedURLByBookmarkData
        self.staleBookmarkData = staleBookmarkData
    }

    var value: SecurityScopedResourceAccess {
        SecurityScopedResourceAccess(
            requiresSuccessfulAccess: requiresSuccessfulAccess,
            startAccessing: { url in
                self.startedURLs.append(url)
                return self.grantedPaths.contains(url.path)
            },
            stopAccessing: { url in
                self.stoppedURLs.append(url)
            },
            securityScopedBookmarkData: { url in
                self.bookmarkDataByPath[url.path]
            },
            resolveSecurityScopedBookmarkData: { data in
                self.resolvedBookmarkData.append(data)
                guard let url = self.resolvedURLByBookmarkData[data] else {
                    throw TeststripError.invalidState("missing bookmark")
                }
                return SecurityScopedBookmarkResolution(url: url, isStale: self.staleBookmarkData.contains(data))
            }
        )
    }
}

private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?

    private(set) var lines: [String] = []
    private(set) var terminateCount = 0
    private(set) var isRunning = false

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        lines.append(line)
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func commands() throws -> [WorkerCommand] {
        try lines.map { try WorkerProtocolEncoder.decode($0) }
    }

    func emitOutputLine(_ line: String) {
        outputHandler?(line)
    }

    func emitErrorLine(_ line: String) {
        errorHandler?(line)
    }
}
