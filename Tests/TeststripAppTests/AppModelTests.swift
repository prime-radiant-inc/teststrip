import Observation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class AppModelTests: XCTestCase {
    func testAppModelStartsWithStudioLayoutSections() {
        let model = AppModel.demo()

        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Collections"))
        XCTAssertFalse(model.sidebarSections.map(\.title).contains("Work"))
        let collectionsSection = model.sidebarSections.first { $0.title == "Collections" }
        XCTAssertEqual(collectionsSection?.rows.first { $0.title == "All Photographs" }?.countText, "1")
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.selectedAsset?.id, model.assets.first?.id)
    }

    func testDefaultEvaluationProvidersIncludeFaceExpressionPass() {
        XCTAssertEqual(
            AppModel.defaultEvaluationProviderNames,
            ["local-image-metrics", "apple-vision", "core-image-faces"]
        )
    }

    func testEmptyCatalogDoesNotShowDeadWorkSidebarPlaceholders() {
        let model = AppModel.demo()

        XCTAssertFalse(model.sidebarSections.contains { $0.title == "Work" })
        XCTAssertFalse(model.sidebarSections.flatMap(\.rows).contains { row in
            row.title == "Recent" || row.title == "Starred"
        })
    }

    func testEmptyCatalogDoesNotShowDeadReviewQueueSidebarPlaceholders() throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "empty-review-sidebar", assets: [])

        XCTAssertFalse(model.sidebarSections.contains { $0.title == "Review" })
        XCTAssertFalse(model.sidebarSections.flatMap(\.rows).contains { row in
            [
                "Picks",
                "Rejects",
                "5 Stars",
                "Needs Keywords",
                "Not analyzed yet",
                "Faces Found",
                "OCR Found",
                "Likely Issues",
                "Provider Failures"
            ].contains(row.title)
        })
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

    // Regression for the never-dismissing "Saved …" toast: confirmation
    // messages auto-clear after their lifetime, ongoing-work messages
    // (trailing ellipsis) persist until the work replaces them.
    @MainActor
    func testTransientStatusMessageAutoClearsButOngoingWorkMessagePersists() async throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.transientStatusMessageLifetime = .milliseconds(20)

        model.statusMessage = "Saved One-star picks"
        model.scheduleTransientStatusMessageAutoClear()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(model.statusMessage)

        model.statusMessage = "Importing Vacation…"
        model.scheduleTransientStatusMessageAutoClear()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.statusMessage, "Importing Vacation…")
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

        XCTAssertEqual(model.assets.count, 125)
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

        XCTAssertEqual(model.assets.count, 125)
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

        XCTAssertEqual(model.assets.count, 125)
        XCTAssertEqual(model.totalAssetCount, 125)
        XCTAssertEqual(model.cullingProgressSummary.pickCount, 2)
        XCTAssertEqual(model.cullingProgressSummary.rejectCount, 1)
        XCTAssertEqual(model.cullingProgressSummary.reviewedCount, 3)
    }

    func testNavigateBackAndForwardMovesThroughSidebarViewHistory() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        XCTAssertFalse(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)

        try model.selectSidebarTarget(.people)
        try model.selectSidebarTarget(.timeline)
        try model.selectSidebarTarget(.search)
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertTrue(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)

        try model.navigateBack()
        XCTAssertEqual(model.selectedView, .timeline)
        XCTAssertTrue(model.canNavigateForward)

        try model.navigateBack()
        XCTAssertEqual(model.selectedView, .people)
        XCTAssertFalse(model.canNavigateBack)

        try model.navigateForward()
        XCTAssertEqual(model.selectedView, .timeline)
        try model.navigateForward()
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertFalse(model.canNavigateForward)
    }

    func testNavigatingToANewViewAfterGoingBackClearsForwardHistory() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        try model.selectSidebarTarget(.people)
        try model.selectSidebarTarget(.timeline)

        try model.navigateBack()
        XCTAssertEqual(model.selectedView, .people)
        XCTAssertTrue(model.canNavigateForward)

        try model.selectSidebarTarget(.search)
        XCTAssertFalse(model.canNavigateForward)

        try model.navigateBack()
        XCTAssertEqual(model.selectedView, .people)
    }

    func testRepeatingTheCurrentViewDoesNotGrowNavigationHistory() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        try model.selectSidebarTarget(.people)
        try model.selectSidebarTarget(.people)
        XCTAssertFalse(model.canNavigateBack)
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

    func testComparePickRejectRefreshesActiveCullingSessionProgressAndOutputSet() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-cull-action-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-cull-group-action",
            assets: assets
        )
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "compare-cull-set"),
            name: "Compare Cull Set",
            assetIDs: assets.map(\.id)
        )
        try repository.upsert(inputSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: inputSet.id)
        let startedSession = try model.beginCullingSession(named: "Compare Cull")
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepComparePrimaryAndRejectAlternates()

        let session = try repository.session(id: startedSession.id)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.completedUnitCount, 8)
        XCTAssertEqual(session.totalUnitCount, 9)
        XCTAssertEqual(session.detail, "Reviewed 8 of 9 frames · 1 pick · 7 rejects")
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: outputSetID)), [assets[1].id])
    }

    func testKeepABFramePicksOneAndRejectsOnlyTheOther() throws {
        let assets = (0..<4).map { makeAsset(id: "ab-keep-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(named: "ab-keep-group", assets: assets)
        model.selectedView = .abCompare
        model.select(assets[0].id)

        try model.keepABFrame(keeping: assets[0].id, over: assets[1].id)

        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[1].id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: assets[2].id).metadata.flag)
        XCTAssertNil(try repository.asset(id: assets[3].id).metadata.flag)
    }

    // Persona-3 item 2: `,`/`.` are A/B Compare's keyboard verdicts, wired
    // through the same monitor path as every other culling shortcut.
    func testCommaAndPeriodMapToABKeepShortcuts() {
        XCTAssertEqual(CullingShortcut(key: .character(",")), .keepAOverB)
        XCTAssertEqual(CullingShortcut(key: .character(".")), .keepBOverA)
    }

    func testKeepAOverBShortcutKeepsPrimaryAndRejectsContender() throws {
        let assets = (0..<4).map { makeAsset(id: "ab-key-comma-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(named: "ab-key-comma-group", assets: assets)
        model.selectedView = .abCompare
        model.select(assets[0].id)

        try model.applyCullingShortcut(.keepAOverB)

        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[1].id).metadata.flag, .reject)
    }

    func testKeepBOverAShortcutKeepsContenderAndRejectsPrimary() throws {
        let assets = (0..<4).map { makeAsset(id: "ab-key-period-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(named: "ab-key-period-group", assets: assets)
        model.selectedView = .abCompare
        model.select(assets[0].id)

        try model.applyCullingShortcut(.keepBOverA)

        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[1].id).metadata.flag, .pick)
    }

    func testABKeepShortcutsThrowOutsideABCompare() throws {
        let assets = (0..<2).map { makeAsset(id: "ab-key-wrong-mode-\($0)", size: Int64($0 + 1)) }
        let (model, _) = try makeModelWithCatalogAssets(named: "ab-key-wrong-mode-group", assets: assets)
        model.selectedView = .loupe
        model.select(assets[0].id)

        XCTAssertThrowsError(try model.applyCullingShortcut(.keepAOverB))
    }

    // Persona-3 item 1: "b" toggles — pressed again from inside .abCompare it
    // exits back to .loupe instead of re-entering a no-op.
    func testShowABCompareShortcutTogglesBackToLoupeWhenAlreadyInABCompare() throws {
        let model = AppModel.demo()
        model.selectedView = .abCompare

        try model.applyCullingShortcut(.showABCompare)

        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testShowABCompareShortcutEntersABCompareFromLoupe() throws {
        let model = AppModel.demo()
        model.selectedView = .loupe

        try model.applyCullingShortcut(.showABCompare)

        XCTAssertEqual(model.selectedView, .abCompare)
    }

    // Esc exits .compare/.abCompare back to .loupe (the modal-trap fix).
    func testExitCullSubViewShortcutReturnsToLoupeFromCompare() throws {
        let model = AppModel.demo()
        model.selectedView = .compare

        try model.applyCullingShortcut(.exitCullSubView)

        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testExitCullSubViewShortcutReturnsToLoupeFromABCompare() throws {
        let model = AppModel.demo()
        model.selectedView = .abCompare

        try model.applyCullingShortcut(.exitCullSubView)

        XCTAssertEqual(model.selectedView, .loupe)
    }

    // ⌘1's root cause: lastSubView[.cull] was recorded as .abCompare on the
    // way in, so re-selecting the already-active Cull workspace round-tripped
    // right back into the trap. .compare/.abCompare must not be sticky.
    func testReselectingCullWorkspaceEscapesABCompareTrap() throws {
        let model = AppModel.demo()
        model.selectedView = .cullGrid
        model.selectedView = .loupe
        model.selectedView = .abCompare

        model.selectWorkspace(.cull)

        XCTAssertEqual(model.selectedView, .loupe)
    }

    // Persona-3 item 3: while the ? overlay is visible it owns navigation —
    // ↑/↓ (within-stack candidate nav) scroll the overlay's section index;
    // the deck's selection must not move. ←/→ (stack nav) are swallowed and
    // must not scroll the overlay, since it's a vertical list.
    func testArrowShortcutsScrollKeyMapOverlayInsteadOfNavigatingWhileVisible() throws {
        let model = AppModel.demo()
        model.selectedView = .loupe
        model.isKeyMapOverlayVisible = true
        let selectionBefore = model.selectedAssetID

        try model.applyCullingShortcut(.nextCandidateInStack)
        XCTAssertEqual(model.keyMapOverlayScrollIndex, 1)
        XCTAssertEqual(model.selectedAssetID, selectionBefore)

        try model.applyCullingShortcut(.previousCandidateInStack)
        XCTAssertEqual(model.keyMapOverlayScrollIndex, 0)
    }

    func testStackShortcutsDoNotScrollKeyMapOverlayWhileVisible() throws {
        let model = AppModel.demo()
        model.selectedView = .loupe
        model.isKeyMapOverlayVisible = true
        let selectionBefore = model.selectedAssetID

        try model.applyCullingShortcut(.nextStack)
        XCTAssertEqual(model.keyMapOverlayScrollIndex, 0)
        XCTAssertEqual(model.selectedAssetID, selectionBefore)

        try model.applyCullingShortcut(.previousStack)
        XCTAssertEqual(model.keyMapOverlayScrollIndex, 0)
        XCTAssertEqual(model.selectedAssetID, selectionBefore)
    }

    func testPickShortcutIsSwallowedWhileKeyMapOverlayVisible() throws {
        let assets = (0..<2).map { makeAsset(id: "overlay-swallow-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(named: "overlay-swallow-group", assets: assets)
        model.selectedView = .loupe
        model.select(assets[0].id)
        model.isKeyMapOverlayVisible = true

        try model.applyCullingShortcut(.pick)

        XCTAssertNil(try repository.asset(id: assets[0].id).metadata.flag)
    }

    func testShowKeyMapDismissesOverlayEvenWhileVisible() throws {
        let model = AppModel.demo()
        model.isKeyMapOverlayVisible = true

        try model.applyCullingShortcut(.showKeyMap)

        XCTAssertFalse(model.isKeyMapOverlayVisible)
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

    func testKeepTopTwoCompareContendersPicksTopTwoAndRejectsThirdContenderOnly() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-contenders-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-contenders-action",
            assets: assets
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: assets[0].id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[3].id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[5].id, kind: .focus, value: .score(0.5), confidence: 0.9, provenance: provenance)
        ])
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepTopTwoCompareContendersAndRejectAlternates(assetIDs: [assets[0].id, assets[3].id])

        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[3].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[5].id).metadata.flag, .reject)
        // Unranked frames inside the compare window, and everything outside
        // it, must stay untouched: only the visible contenders are decided.
        for index in [1, 2, 4, 6, 7] {
            XCTAssertNil(try repository.asset(id: assets[index].id).metadata.flag)
        }
        XCTAssertNil(try repository.asset(id: assets[8].id).metadata.flag)
    }

    func testKeepTopTwoCompareContendersRequiresAtLeastThreeRankedContenders() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-contenders-few-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-contenders-few-action",
            assets: assets
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: assets[0].id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[3].id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance)
        ])
        model.selectedView = .compare
        model.select(assets[1].id)

        XCTAssertThrowsError(try model.keepTopTwoCompareContendersAndRejectAlternates(assetIDs: [assets[0].id, assets[3].id]))
    }

    func testKeepTopTwoCompareContendersRejectsInvalidKeepSelection() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-contenders-invalid-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-contenders-invalid-action",
            assets: assets
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: assets[0].id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[3].id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[5].id, kind: .focus, value: .score(0.5), confidence: 0.9, provenance: provenance)
        ])
        model.selectedView = .compare
        model.select(assets[1].id)

        // Rank 1 and rank 3, not the top two.
        XCTAssertThrowsError(try model.keepTopTwoCompareContendersAndRejectAlternates(assetIDs: [assets[0].id, assets[5].id]))
    }

    func testKeepTopTwoCompareContendersRefreshesActiveCullingSessionProgress() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-contenders-progress-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-contenders-progress-action",
            assets: assets
        )
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "compare-contenders-progress-set"),
            name: "Compare Contenders Progress Set",
            assetIDs: assets.map(\.id)
        )
        try repository.upsert(inputSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: inputSet.id)
        let startedSession = try model.beginCullingSession(named: "Compare Contenders Progress")
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: assets[0].id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[3].id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: assets[5].id, kind: .focus, value: .score(0.5), confidence: 0.9, provenance: provenance)
        ])
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepTopTwoCompareContendersAndRejectAlternates(assetIDs: [assets[0].id, assets[3].id])

        let session = try repository.session(id: startedSession.id)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.completedUnitCount, 3)
        XCTAssertEqual(session.totalUnitCount, 9)
        XCTAssertEqual(session.detail, "Reviewed 3 of 9 frames · 2 picks · 1 reject")
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(Set(assetIDs(in: try repository.assetSet(id: outputSetID))), Set([assets[0].id, assets[3].id]))
    }

    func testCompareGroupDecisionAdvancesToNextPersistedStackInCompare() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "compare-advance-persisted",
            sessionID: "compare-advance-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        fixture.model.selectedView = .compare
        XCTAssertEqual(fixture.model.compareAssets().map(\.id), [fixture.firstLead.id, fixture.firstAlternate.id])

        try fixture.model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstLead.id).metadata.flag, .pick)
        XCTAssertEqual(try fixture.repository.asset(id: fixture.firstAlternate.id).metadata.flag, .reject)
        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedView, .compare)
        XCTAssertEqual(fixture.model.compareAssets().map(\.id), [fixture.secondLead.id, fixture.secondAlternate.id])
    }

    func testCompareGroupDecisionAdvancesToNextCandidateStackWindow() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstBurstLead = makeAsset(
            id: "compare-advance-a1",
            path: "/Photos/Job/compare-advance-a1.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstBurstAlternate = makeAsset(
            id: "compare-advance-a2",
            path: "/Photos/Job/compare-advance-a2.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let secondBurstLead = makeAsset(
            id: "compare-advance-b1",
            path: "/Photos/Job/compare-advance-b1.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(60))
        )
        let secondBurstAlternate = makeAsset(
            id: "compare-advance-b2",
            path: "/Photos/Job/compare-advance-b2.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(61))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-advance-window",
            assets: [firstBurstLead, firstBurstAlternate, secondBurstLead, secondBurstAlternate]
        )
        model.select(firstBurstLead.id)
        model.selectedView = .compare
        XCTAssertEqual(model.compareAssets().map(\.id), [firstBurstLead.id, firstBurstAlternate.id])

        try model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(try repository.asset(id: firstBurstLead.id).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, secondBurstLead.id)
        XCTAssertEqual(model.selectedView, .compare)
        XCTAssertEqual(model.compareAssets().map(\.id), [secondBurstLead.id, secondBurstAlternate.id])
    }

    func testCompareGroupDecisionStaysPutOnLastGroup() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "compare-advance-last",
            sessionID: "compare-advance-last-session"
        )
        try fixture.model.applyAssetSet(id: fixture.secondSet.id)
        fixture.model.select(fixture.secondLead.id)
        fixture.model.selectedView = .compare

        try fixture.model.keepComparePrimaryAndRejectAlternates()

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedView, .compare)
        XCTAssertEqual(fixture.model.statusMessage, "Kept \(fixture.secondLead.originalURL.lastPathComponent); rejected 1 alternates")
    }

    func testStackNavigationStaysInCompareWhenCompareIsActive() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "compare-stack-navigation",
            sessionID: "compare-stack-navigation-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        fixture.model.selectedView = .compare

        try fixture.model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedView, .compare)
        XCTAssertEqual(fixture.model.compareAssets().map(\.id), [fixture.secondLead.id, fixture.secondAlternate.id])
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

    func testBeginManualCullingFromCompareSetReusesOpenSessionForSameSet() throws {
        let assets = (0..<9).map { makeAsset(id: "compare-manual-reuse-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-manual-cull-reuse",
            assets: assets
        )
        model.selectedView = .compare
        model.select(assets[1].id)

        let firstSession = try model.beginManualCullingFromCompareSet()

        model.selectedView = .compare
        let secondSession = try model.beginManualCullingFromCompareSet()

        XCTAssertEqual(secondSession.id, firstSession.id)
        XCTAssertEqual(secondSession.inputSetIDs, firstSession.inputSetIDs)
        XCTAssertEqual(model.selectedAssetSetID, firstSession.inputSetIDs.first)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(
            try repository.workSessions(kind: .culling, statuses: [.queued, .running, .paused]).count,
            1
        )
    }

    func testBeginManualCullingFromCompareSetDoesNotReuseCompletedSession() throws {
        let assets = (0..<3).map { makeAsset(id: "compare-manual-completed-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "compare-manual-cull-completed",
            assets: assets
        )
        model.selectedView = .compare
        model.select(assets[0].id)

        let firstSession = try model.beginManualCullingFromCompareSet()
        try model.applyCullingShortcut(.pick)
        try model.applyCullingShortcut(.pick)
        try model.applyCullingShortcut(.pick)
        XCTAssertEqual(try repository.session(id: firstSession.id).status, .completed)

        model.selectedView = .compare
        let secondSession = try model.beginManualCullingFromCompareSet()

        XCTAssertNotEqual(secondSession.id, firstSession.id)
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

    @MainActor
    func testBatchFlagAppliesToWholeSelectionInOneUndoGroup() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-batch-flag")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try (0..<3).map { index -> Asset in
            let url = photosDirectory.appendingPathComponent("photo-\(index).png")
            try writeTestPNG(to: url)
            return makeAsset(id: "batch-flag-\(index)", path: url.path, rating: 0)
        }
        try repository.upsert(assets)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.setBatchSelection(assets[0].id, isSelected: true)
        model.setBatchSelection(assets[2].id, isSelected: true)

        try model.setFlagForSelectedAssets(.reject)

        // Both selected photos are rejected; the unselected one is untouched.
        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: assets[2].id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: assets[1].id).metadata.flag)

        // A single undo reverts the whole selection at once (one change group).
        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: assets[0].id).metadata.flag)
        XCTAssertNil(try repository.asset(id: assets[2].id).metadata.flag)
    }

    func testBatchKeywordTextAppendsPerAssetDedupedWithoutClobberingOtherAssetsKeywords() throws {
        let a = makeAsset(id: "kw-batch-a", path: "/Volumes/NAS/Wedding/kw-batch-a.jpg", rating: 0, keywords: ["existing-a"])
        let b = makeAsset(id: "kw-batch-b", path: "/Volumes/NAS/Wedding/kw-batch-b.jpg", rating: 0, keywords: ["existing-b", "sunset"])
        let (model, repository) = try makeModelWithCatalogAssets(named: "app-model-batch-keyword-text", assets: [a, b])
        model.setBatchSelection(a.id, isSelected: true)
        model.setBatchSelection(b.id, isSelected: true)

        try model.setKeywordTextForSelectedAssets("sunset, new-tag")

        // Appends new-tag to both, sunset only to `a` (already deduped on `b`);
        // each asset's unrelated existing keyword survives untouched.
        XCTAssertEqual(try repository.asset(id: a.id).metadata.keywords, ["existing-a", "sunset", "new-tag"])
        XCTAssertEqual(try repository.asset(id: b.id).metadata.keywords, ["existing-b", "sunset", "new-tag"])

        try model.undoMetadataChange()
        XCTAssertEqual(try repository.asset(id: a.id).metadata.keywords, ["existing-a"])
        XCTAssertEqual(try repository.asset(id: b.id).metadata.keywords, ["existing-b", "sunset"])
    }

    func testBatchKeywordTextStillReplacesForASingleFocusedAsset() throws {
        // No batch selection active — preserves the pre-existing single-asset
        // full-replace semantics (e.g. clearing the field clears keywords).
        let asset = makeAsset(id: "kw-single", path: "/Volumes/NAS/Wedding/kw-single.jpg", rating: 0, keywords: ["old"])
        let (model, repository) = try makeModelWithCatalogAssets(named: "app-model-single-keyword-text", assets: [asset])
        model.select(asset.id)

        try model.setKeywordTextForSelectedAssets("")

        XCTAssertEqual(try repository.asset(id: asset.id).metadata.keywords, [])
    }

    func testBatchRemoveKeywordRemovesFromEverySelectedAsset() throws {
        let a = makeAsset(id: "kw-remove-a", path: "/Volumes/NAS/Wedding/kw-remove-a.jpg", rating: 0, keywords: ["keeper", "travel"])
        let b = makeAsset(id: "kw-remove-b", path: "/Volumes/NAS/Wedding/kw-remove-b.jpg", rating: 0, keywords: ["keeper"])
        let (model, repository) = try makeModelWithCatalogAssets(named: "app-model-batch-keyword-remove", assets: [a, b])
        model.setBatchSelection(a.id, isSelected: true)
        model.setBatchSelection(b.id, isSelected: true)

        try model.removeKeywordFromSelectedAssets("keeper")

        XCTAssertEqual(try repository.asset(id: a.id).metadata.keywords, ["travel"])
        XCTAssertEqual(try repository.asset(id: b.id).metadata.keywords, [])
    }

    func testBatchCaptionCreatorCopyrightOverwriteWholeSelectionInOneUndoGroup() throws {
        let a = makeAsset(id: "text-batch-a", path: "/Volumes/NAS/Wedding/text-batch-a.jpg", rating: 0)
        let b = makeAsset(id: "text-batch-b", path: "/Volumes/NAS/Wedding/text-batch-b.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(named: "app-model-batch-caption-creator-copyright", assets: [a, b])
        model.setBatchSelection(a.id, isSelected: true)
        model.setBatchSelection(b.id, isSelected: true)

        try model.setCaptionForSelectedAssets("Fitz Roy sunrise")
        try model.setCreatorForSelectedAssets("Jesse")
        try model.setCopyrightForSelectedAssets("Copyright Jesse")

        for assetID in [a.id, b.id] {
            let metadata = try repository.asset(id: assetID).metadata
            XCTAssertEqual(metadata.caption, "Fitz Roy sunrise")
            XCTAssertEqual(metadata.creator, "Jesse")
            XCTAssertEqual(metadata.copyright, "Copyright Jesse")
        }

        // Three gestures -> three undo groups, each covering the whole batch.
        try model.undoMetadataChange()
        for assetID in [a.id, b.id] {
            XCTAssertNil(try repository.asset(id: assetID).metadata.copyright)
        }
        try model.undoMetadataChange()
        for assetID in [a.id, b.id] {
            XCTAssertNil(try repository.asset(id: assetID).metadata.creator)
        }
        try model.undoMetadataChange()
        for assetID in [a.id, b.id] {
            XCTAssertNil(try repository.asset(id: assetID).metadata.caption)
        }
    }

    func testBatchAcceptSuggestedKeywordAppendsToEverySelectedAssetDeduped() throws {
        let a = makeAsset(id: "suggest-kw-a", path: "/Volumes/NAS/Wedding/suggest-kw-a.jpg", rating: 0)
        let b = makeAsset(id: "suggest-kw-b", path: "/Volumes/NAS/Wedding/suggest-kw-b.jpg", rating: 0, keywords: ["mountain"])
        let (model, repository) = try makeModelWithCatalogAssets(named: "app-model-batch-accept-keyword", assets: [a, b])
        model.setBatchSelection(a.id, isSelected: true)
        model.setBatchSelection(b.id, isSelected: true)

        try model.acceptSuggestedKeywordForSelectedAssets("mountain")

        XCTAssertEqual(try repository.asset(id: a.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: b.id).metadata.keywords, ["mountain"])
    }

    @MainActor
    func testRequestBatchMetadataSheetBumpsTokenForTheView() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-batch-meta-token")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: CatalogRepository(database: database),
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews2", isDirectory: true))
            )
        ))
        let before = model.batchMetadataRequestToken
        model.requestBatchMetadataSheet()
        XCTAssertEqual(model.batchMetadataRequestToken, before + 1)
    }

    @MainActor
    func testBatchRatingFallsBackToFocusedAssetWithoutAMultiSelection() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-batch-rating-single")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try (0..<2).map { index -> Asset in
            let url = photosDirectory.appendingPathComponent("solo-\(index).png")
            try writeTestPNG(to: url)
            return makeAsset(id: "batch-rating-\(index)", path: url.path, rating: 0)
        }
        try repository.upsert(assets)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.select(assets[1].id)

        try model.setRatingForSelectedAssets(5)

        // With no batch selection, only the focused asset is rated.
        XCTAssertEqual(try repository.asset(id: assets[1].id).metadata.rating, 5)
        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.rating, 0)
    }

    func testWorkerBackedBatchMetadataRefreshesXmpStateOnceForBatch() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-batch-metadata")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        var metadataSyncStateQueryCount = 0
        database.rowQueryObserver = { sql in
            if sql.contains("FROM metadata_sync_state") {
                metadataSyncStateQueryCount += 1
            }
        }
        let repository = CatalogRepository(database: database)
        let firstURL = photosDirectory.appendingPathComponent("first.cr2")
        let secondURL = photosDirectory.appendingPathComponent("second.cr2")
        let thirdURL = photosDirectory.appendingPathComponent("third.cr2")
        try Data("first original raw bytes".utf8).write(to: firstURL)
        try Data("second original raw bytes".utf8).write(to: secondURL)
        try Data("third original raw bytes".utf8).write(to: thirdURL)
        let assets = [
            Asset(
                id: AssetID(rawValue: "worker-batch-first"),
                originalURL: firstURL,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
                availability: .online,
                metadata: AssetMetadata()
            ),
            Asset(
                id: AssetID(rawValue: "worker-batch-second"),
                originalURL: secondURL,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
                availability: .online,
                metadata: AssetMetadata()
            ),
            Asset(
                id: AssetID(rawValue: "worker-batch-third"),
                originalURL: thirdURL,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 12, modificationDate: Date(timeIntervalSince1970: 12)),
                availability: .online,
                metadata: AssetMetadata()
            )
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

    func testWorkerBackedBatchMetadataDoesNotDispatchOfflineOriginals() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-batch-offline-metadata")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let offlineURL = photosDirectory.appendingPathComponent("offline.cr2")
        let onlineURL = photosDirectory.appendingPathComponent("online.cr2")
        try Data("offline original raw bytes".utf8).write(to: offlineURL)
        try Data("online original raw bytes".utf8).write(to: onlineURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let offline = Asset(
            id: AssetID(rawValue: "worker-batch-offline"),
            originalURL: offlineURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .offline,
            metadata: AssetMetadata()
        )
        let online = Asset(
            id: AssetID(rawValue: "worker-batch-online"),
            originalURL: onlineURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert([offline, online])
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
            assets: [offline, online],
            totalAssetCount: 2,
            catalog: catalog,
            workerSupervisor: supervisor
        )

        let appliedCount = try model.applyVisibleBatchMetadata(
            keywordText: "portfolio",
            caption: "",
            creator: "",
            copyright: ""
        )

        XCTAssertEqual(appliedCount, 2)
        XCTAssertEqual(Set(try repository.pendingMetadataSyncItems().map(\.assetID)), Set([offline.id, online.id]))
        XCTAssertEqual(Set(model.pendingMetadataSyncItems.map(\.assetID)), Set([offline.id, online.id]))
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .xmpSync }.map(\.id.rawValue), [
            "xmp-\(online.id.rawValue)-2"
        ])
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: online.id)])
        XCTAssertEqual(try repository.asset(id: offline.id).metadata.keywords, ["portfolio"])
        XCTAssertEqual(try repository.asset(id: online.id).metadata.keywords, ["portfolio"])
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

    func testPlainSelectionClearsExistingBatchSelection() throws {
        let first = makeAsset(id: "plain-select-first", path: "/Photos/plain-select-first.jpg", rating: 1)
        let second = makeAsset(id: "plain-select-second", path: "/Photos/plain-select-second.jpg", rating: 2)
        let third = makeAsset(id: "plain-select-third", path: "/Photos/plain-select-third.jpg", rating: 3)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "plain-selection-clears-batch",
            assets: [first, second, third]
        )
        model.setBatchSelection(first.id, isSelected: true)
        model.setBatchSelection(third.id, isSelected: true)

        model.select(second.id)

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertEqual(model.selectedBatchAssetCount, 0)
        XCTAssertFalse(model.isBatchSelected(first.id))
        XCTAssertFalse(model.isBatchSelected(third.id))
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

    func testBatchSelectionAcrossCatalogKeepsCatalogOrder() throws {
        let model = try makeModelWithSeededCatalog(named: "batch-selection-cross-catalog", count: 121)
        XCTAssertEqual(model.assets.count, 121)
        model.setBatchSelection(AssetID(rawValue: "asset-0"), isSelected: true)
        model.setBatchSelection(AssetID(rawValue: "asset-120"), isSelected: true)
        let savedSet = try model.saveSelectedAssetAsManualSet(named: "Cross Catalog")

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

    func testChangingLibrarySortReloadsCurrentFilteredScope() throws {
        let oldKeeper = makeAsset(
            id: "sort-old-keeper",
            path: "/Photos/sort/old-keeper.cr2",
            rating: 4,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 100))
        )
        let newKeeper = makeAsset(
            id: "sort-new-keeper",
            path: "/Photos/sort/new-keeper.cr2",
            rating: 5,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 200))
        )
        let filteredOut = makeAsset(
            id: "sort-filtered-out",
            path: "/Photos/sort/filtered-out.cr2",
            rating: 1,
            technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 300))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "library-sort-filtered-scope",
            assets: [oldKeeper, newKeeper, filteredOut]
        )
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        try model.setLibrarySortOption(.captureTimeNewestFirst)

        XCTAssertEqual(model.librarySortOption, .captureTimeNewestFirst)
        XCTAssertEqual(model.assets.map(\.id), [newKeeper.id, oldKeeper.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testBatchSelectionKeepsMatchingAssetsAfterFilter() throws {
        let model = try makeModelWithSeededCatalog(named: "batch-selection-filtered-catalog", count: 121)
        let firstKeeperID = AssetID(rawValue: "asset-5")
        let laterKeeperID = AssetID(rawValue: "asset-119")
        model.setBatchSelection(firstKeeperID, isSelected: true)
        model.setBatchSelection(laterKeeperID, isSelected: true)
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()

        XCTAssertEqual(model.selectedBatchAssetCount, 2)
        XCTAssertTrue(model.isBatchSelected(firstKeeperID))
        XCTAssertTrue(model.isBatchSelected(laterKeeperID))
    }

    func testCurrentScopeBatchMetadataAppliesToWholeFilteredScopeAndWritesXmpSidecars() throws {
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

        let appliedCount = try model.applyCurrentScopeBatchMetadata(
            keywordText: "portfolio",
            caption: "  Green selects  ",
            creator: "  Jesse  ",
            copyright: ""
        )

        XCTAssertEqual(appliedCount, matchingAssets.count)
        XCTAssertEqual(model.statusMessage, "Applied batch metadata to 121 photos")
        // The last in-scope asset is written just like the rest — batch
        // metadata covers the whole filtered scope, not only the selection.
        let lastScopedAsset = try XCTUnwrap(matchingAssets.last)
        let lastScopedMetadata = try repository.asset(id: lastScopedAsset.id).metadata
        let lastScopedSidecarData = try Data(contentsOf: lastScopedAsset.originalURL.appendingPathExtension("xmp"))
        let lastScopedSidecarMetadata = try XMPPacket.parse(lastScopedSidecarData).metadata
        XCTAssertEqual(lastScopedMetadata.keywords, ["portfolio"])
        XCTAssertEqual(lastScopedMetadata.caption, "Green selects")
        XCTAssertEqual(lastScopedMetadata.creator, "Jesse")
        XCTAssertEqual(lastScopedSidecarMetadata.keywords, ["portfolio"])
        XCTAssertEqual(lastScopedSidecarMetadata.caption, "Green selects")
        XCTAssertEqual(try repository.asset(id: outsideAsset.id).metadata.keywords, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideAsset.originalURL.appendingPathExtension("xmp").path))
    }

    func testCurrentScopeBatchMetadataAppliesToWholeExplicitSet() throws {
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

        let appliedCount = try model.applyCurrentScopeBatchMetadata(
            keywordText: "portfolio",
            caption: "",
            creator: "",
            copyright: "  Copyright Jesse  "
        )

        XCTAssertEqual(appliedCount, setAssets.count)
        // The whole explicit set is written, including its last member.
        let lastScopedAsset = try XCTUnwrap(setAssets.last)
        let lastScopedMetadata = try repository.asset(id: lastScopedAsset.id).metadata
        let lastScopedSidecarData = try Data(contentsOf: lastScopedAsset.originalURL.appendingPathExtension("xmp"))
        let lastScopedSidecarMetadata = try XMPPacket.parse(lastScopedSidecarData).metadata
        XCTAssertEqual(lastScopedMetadata.keywords, ["portfolio"])
        XCTAssertEqual(lastScopedMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(lastScopedSidecarMetadata.keywords, ["portfolio"])
        XCTAssertEqual(lastScopedSidecarMetadata.copyright, "Copyright Jesse")
        XCTAssertEqual(try repository.asset(id: outsideAsset.id).metadata.keywords, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideAsset.originalURL.appendingPathExtension("xmp").path))
    }

    func testCurrentScopeBatchMetadataSkipsGhostAssetIDLeftInSetMembership() throws {
        // membership_json can retain a trashed asset's ID (deleteAsset
        // doesn't rewrite asset_sets); the current-scope batch path must
        // filter it out on read instead of throwing notFound and aborting
        // the whole batch.
        let directory = try makeTemporaryDirectory(named: "app-model-current-scope-batch-metadata-ghost")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keptURL = photosDirectory.appendingPathComponent("kept.cr2")
        try Data("kept original".utf8).write(to: keptURL)
        let kept = Asset(
            id: AssetID(rawValue: "ghost-set-kept"),
            originalURL: keptURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(kept)
        let ghostID = AssetID(rawValue: "ghost-set-trashed")
        let assetSet = AssetSet.manual(
            id: AssetSetID(rawValue: "ghost-scope-set"),
            name: "Ghost Scope Set",
            assetIDs: [kept.id, ghostID]
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

        let appliedCount = try model.applyCurrentScopeBatchMetadata(
            keywordText: "portfolio",
            caption: "",
            creator: "",
            copyright: ""
        )

        XCTAssertEqual(appliedCount, 1)
        XCTAssertEqual(try repository.asset(id: kept.id).metadata.keywords, ["portfolio"])
    }

    @MainActor
    func testExportVisibleAssetsWritesJpegCopiesAndReportsCompletionSummary() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-visible")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let goodURL = photosDirectory.appendingPathComponent("good.png")
        let brokenURL = photosDirectory.appendingPathComponent("broken.jpg")
        let missingURL = photosDirectory.appendingPathComponent("missing.jpg")
        try writeTestPNG(to: goodURL)
        try Data("not an image".utf8).write(to: brokenURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let good = makeAsset(id: "export-good", path: goodURL.path, rating: 0)
        let broken = makeAsset(id: "export-broken", path: brokenURL.path, rating: 0)
        let missing = makeAsset(id: "export-missing", path: missingURL.path, rating: 0, availability: .missing)
        try repository.upsert([good, broken, missing])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let destination = directory.appendingPathComponent("exports", isDirectory: true)
        let originalBytes = try Data(contentsOf: goodURL)

        let summary = try await model.exportVisibleAssets(
            settings: ExportPreset.web2048.settings,
            destinationFolder: destination
        )

        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.destinationFolder, destination)
        XCTAssertEqual(summary.firstFailureMessage, "could not decode broken.jpg")
        XCTAssertEqual(model.statusMessage, "Exported 1 photo to exports (1 skipped, 1 failed)")
        XCTAssertEqual(model.errorMessage, "could not decode broken.jpg")
        XCTAssertFalse(model.isExporting)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["good.jpg"])
        XCTAssertEqual(try Data(contentsOf: goodURL), originalBytes)
        XCTAssertEqual(try repository.asset(id: good.id), good)
        XCTAssertEqual(try repository.asset(id: broken.id), broken)
        XCTAssertEqual(try repository.asset(id: missing.id), missing)
    }

    @MainActor
    func testExportSelectedAssetsExportsOnlySelectedBatch() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-selected")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try (0..<3).map { index -> Asset in
            let url = photosDirectory.appendingPathComponent("photo-\(index).png")
            try writeTestPNG(to: url)
            return makeAsset(id: "export-selected-\(index)", path: url.path, rating: 0)
        }
        try repository.upsert(assets)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.setBatchSelection(assets[0].id, isSelected: true)
        model.setBatchSelection(assets[2].id, isSelected: true)
        let destination = directory.appendingPathComponent("exports", isDirectory: true)

        let summary = try await model.exportSelectedAssets(
            settings: ExportPreset.fullResolutionJPEG.settings,
            destinationFolder: destination
        )

        XCTAssertEqual(summary.exportedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(model.statusMessage, "Exported 2 photos to exports")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(),
            ["photo-0.jpg", "photo-2.jpg"]
        )
    }

    @MainActor
    func testExportCurrentScopeAssetsExportsWholeFilteredScope() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-current-scope")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let matchingAssets = try (0..<121).map { index -> Asset in
            let url = photosDirectory.appendingPathComponent("matching-\(index).png")
            try writeTestPNG(to: url)
            return makeAsset(id: "export-scope-\(index)", path: url.path, rating: 0, colorLabel: .green)
        }
        let outsideURL = photosDirectory.appendingPathComponent("outside.png")
        try writeTestPNG(to: outsideURL)
        let outsideAsset = makeAsset(id: "export-scope-outside", path: outsideURL.path, rating: 0, colorLabel: .red)
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
        let destination = directory.appendingPathComponent("exports", isDirectory: true)

        let summary = try await model.exportCurrentScopeAssets(
            settings: ExportPreset.web2048.settings,
            destinationFolder: destination
        )

        XCTAssertEqual(summary.exportedCount, matchingAssets.count)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(model.statusMessage, "Exported 121 photos to exports")
        let writtenNames = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(writtenNames.count, matchingAssets.count)
        XCTAssertFalse(writtenNames.contains("outside.jpg"))
    }

    @MainActor
    func testExportWithNoAssetsThrows() async throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "app-model-export-empty", assets: [])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-export-empty-\(UUID().uuidString)", isDirectory: true)

        do {
            _ = try await model.exportVisibleAssets(
                settings: ExportPreset.web2048.settings,
                destinationFolder: destination
            )
            XCTFail("expected export of empty scope to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "no photos to export")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor
    func testSecondExportWhileRunningThrows() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-reentrancy")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let url = photosDirectory.appendingPathComponent("photo.png")
        try writeTestPNG(to: url)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "export-reentrancy", path: url.path, rating: 0)
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
        let destination = directory.appendingPathComponent("exports", isDirectory: true)

        let firstExport = Task { @MainActor in
            try await model.exportVisibleAssets(
                settings: ExportPreset.web2048.settings,
                destinationFolder: destination
            )
        }
        while !model.isExporting {
            await Task.yield()
        }

        do {
            _ = try await model.exportVisibleAssets(
                settings: ExportPreset.web2048.settings,
                destinationFolder: destination
            )
            XCTFail("expected concurrent export to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "another export is already running")
        }
        let summary = try await firstExport.value
        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertFalse(model.isExporting)
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

        // The sidebar "Sync" section is retired; the Activity Center popover's
        // conflict row deep-links via `revealConflicts` instead.
        XCTAssertEqual(model.activityCenterPresentation.xmpConflicts.map(\.assetID), [conflicted.id])

        try model.revealConflicts([conflicted.id])

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.metadataSyncConflictFilter)
        XCTAssertEqual(model.assets.map(\.id), [conflicted.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testRevealConflictsSwitchesToLibrarySelectsAssetsAndShowsInspector() throws {
        let directory = try makeTemporaryDirectory(named: "xmp-conflict-reveal")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = makeAsset(id: "conflicted-1", path: "/Photos/conflicted-1.jpg", rating: 0)
        let second = makeAsset(id: "conflicted-2", path: "/Photos/conflicted-2.jpg", rating: 0)
        try repository.upsert([first, second])
        try repository.recordMetadataSyncConflict(MetadataSyncItem(
            assetID: first.id,
            sidecarURL: first.originalURL.appendingPathExtension("xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: "old"
        ))
        try repository.recordMetadataSyncConflict(MetadataSyncItem(
            assetID: second.id,
            sidecarURL: second.originalURL.appendingPathExtension("xmp"),
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
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedWorkspace, .cull)
        XCTAssertFalse(model.isInspectorVisible)
        model.scrollInspector(to: .describe)

        try model.revealConflicts([first.id, second.id])

        XCTAssertEqual(model.selectedWorkspace, .library)
        XCTAssertEqual(model.selectedBatchAssetIDs, [first.id, second.id])
        XCTAssertTrue(model.isInspectorVisible)
        XCTAssertTrue(model.metadataSyncConflictFilter)
        // The deep-link always lands on the conflict resolver, which lives
        // in the Info section (Task 11) — scrolling there confirms it.
        XCTAssertEqual(model.inspectorScrollTarget, .info)

        // Conflicted assets are only visible in the Grid subview, so a reveal
        // must land there even when Library last showed another subview.
        model.selectedView = .timeline
        model.selectWorkspace(.cull)
        try model.revealConflicts([first.id])
        XCTAssertEqual(model.selectedView, .grid)

        // Empty reveal is a no-op: no workspace switch or filter churn.
        model.selectWorkspace(.cull)
        model.isInspectorVisible = false
        try model.revealConflicts([])
        XCTAssertEqual(model.selectedWorkspace, .cull)
        XCTAssertFalse(model.isInspectorVisible)
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

        // The sidebar "Sync" section is retired; the `xmp:pending` filter-bar
        // token is the sole remaining route to this filter, so exercise the
        // underlying model filter directly.
        XCTAssertEqual(model.pendingMetadataSyncCount, 1)
        model.selectedAssetSetID = nil
        model.metadataSyncPendingFilter = true
        try model.reload()

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.metadataSyncPendingFilter)
        XCTAssertEqual(model.assets.map(\.id), [pending.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    // persona-1 Maya: "Filter chips lied to me" — applying the Pick chip
    // while a cull session's explicit-ID scope (AssetSet.manual) was active
    // left the grid unchanged. reload()'s explicit-scope branch bypassed
    // flagFilter entirely; it must narrow within the scoped set instead of
    // ignoring the filter.
    func testFlagFilterNarrowsWithinExplicitAssetSetScope() throws {
        let directory = try makeTemporaryDirectory(named: "flag-filter-explicit-scope")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let picked = makeAsset(id: "scope-picked", path: "/Photos/scope-picked.jpg", rating: 0, flag: .pick)
        let rejected = makeAsset(id: "scope-rejected", path: "/Photos/scope-rejected.jpg", rating: 0, flag: .reject)
        let undecided = makeAsset(id: "scope-undecided", path: "/Photos/scope-undecided.jpg", rating: 0)
        try repository.upsert([picked, rejected, undecided])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "cull-session-scope"),
            name: "Cull Session",
            assetIDs: [picked.id, rejected.id, undecided.id]
        )
        model.savedAssetSets = [set]
        model.selectedAssetSetID = set.id
        try model.reload()
        XCTAssertEqual(Set(model.assets.map(\.id)), [picked.id, rejected.id, undecided.id])

        model.flagFilter = .pick
        try model.reload()

        XCTAssertEqual(model.assets.map(\.id), [picked.id])
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
        XCTAssertTrue(model.activityCenterPresentation.xmpConflicts.isEmpty)
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
        XCTAssertNil(reviewQueueCount("Rejects", in: model))
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
        XCTAssertNil(reviewQueueCount("Picks", in: model))
        XCTAssertEqual(reviewQueueCount("Rejects", in: model), "1")
        XCTAssertNil(reviewQueueCount("5 Stars", in: model))
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

    func testSelectedMetadataConflictSidecarMetadataStateReportsUnreadableSidecar() throws {
        let (model, _, asset, _, sidecarURL) = try makeModelWithXMPConflict(
            named: "selected-conflict-unreadable-sidecar",
            catalogMetadata: AssetMetadata(rating: 4, colorLabel: .red, keywords: ["catalog"]),
            sidecarMetadata: AssetMetadata(rating: 5, colorLabel: .green, keywords: ["sidecar"])
        )
        try Data("not xmp".utf8).write(to: sidecarURL)

        model.select(asset.id)

        XCTAssertEqual(model.selectedMetadataSyncConflictSidecarMetadataState, .unreadable)
        XCTAssertNil(model.selectedMetadataSyncConflictSidecarMetadata)
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

    func testWorkerBackedSelectedMetadataEditsCoalesceQueuedXmpSyncToLatestGeneration() throws {
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "app-model-worker-xmp-coalesce",
            assetID: "worker-xmp-coalesce-target"
        )
        model.pauseBackgroundWork()

        try model.setColorLabelForSelectedAsset(.green)
        try model.setFlagForSelectedAsset(.pick)
        try model.setKeywordTextForSelectedAsset("portfolio")
        try model.setCaptionForSelectedAsset("Final select")

        let latestGeneration = try repository.catalogGeneration(assetID: asset.id)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: latestGeneration,
            lastSyncedFingerprint: nil
        )
        XCTAssertEqual(latestGeneration, 5)
        XCTAssertEqual(model.selectedAsset?.metadata.colorLabel, .green)
        XCTAssertEqual(model.selectedAsset?.metadata.flag, .pick)
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, ["portfolio"])
        XCTAssertEqual(model.selectedAsset?.metadata.caption, "Final select")
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, model.selectedAsset?.metadata)
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [pending])
        XCTAssertEqual(model.pendingMetadataSyncItems, [pending])
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appendingPathExtension("xmp").path))
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertEqual(
            model.backgroundWorkQueue.queuedItems.filter { $0.kind == .xmpSync }.map(\.id.rawValue),
            ["xmp-\(asset.id.rawValue)-\(latestGeneration)"]
        )
        XCTAssertEqual(model.visibleWorkActivities.filter { $0.kind == .xmpSync }.count, 1)
    }

    func testRatingOfflineSelectedAssetRecordsPendingXmpWithoutDispatchingWorkerSync() throws {
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "app-model-worker-xmp-offline-edit",
            assetID: "worker-xmp-offline-edit-target",
            availability: .offline
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
        XCTAssertEqual(try transport.commands(), [])
        XCTAssertFalse(model.visibleWorkActivities.contains { $0.kind == .xmpSync })
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

    @MainActor
    func testRetrySelectedPendingMetadataSyncReenqueuesAfterAPriorFailure() async throws {
        // Reproduces inspect-003: a first sync write failed (e.g. the sidecar
        // folder was briefly unwritable) and left a terminal `.failed` item in
        // the queue under the same asset+generation ID. Pressing Retry must
        // enqueue a fresh write, not silently no-op because an item with that
        // ID already exists.
        let (model, repository, asset, originalURL, transport) = try makeWorkerMetadataSyncModel(
            named: "retry-selected-pending-worker-xmp-after-failure",
            assetID: "retry-selected-pending-worker-xmp-after-failure"
        )
        let generation = try repository.catalogGeneration(assetID: asset.id)
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: originalURL.appendingPathExtension("xmp"),
            catalogGeneration: generation,
            lastSyncedFingerprint: nil
        )
        try repository.recordMetadataSyncPending(pending)
        model.pendingMetadataSyncItems = [pending]

        // Drive an initial write attempt through the real path so it lands in
        // the worker supervisor's own queue (the one dedup checks read), then
        // fail it — simulating a transient failure like an unwritable folder.
        try model.retrySelectedMetadataSync()
        let staleItemID = WorkSessionID(rawValue: "xmp-\(asset.id.rawValue)-\(generation)")
        XCTAssertEqual(try transport.commands(), [.syncMetadata(assetID: asset.id)])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: staleItemID,
            message: "XMP sidecar folder is not writable"
        )))
        try await waitForBackgroundWorkStatus(.failed, itemID: staleItemID, in: model)

        XCTAssertTrue(model.canRetrySelectedMetadataSync)
        try model.retrySelectedMetadataSync()

        XCTAssertEqual(try transport.commands(), [
            .syncMetadata(assetID: asset.id),
            .syncMetadata(assetID: asset.id),
        ])
        XCTAssertTrue(model.backgroundWorkQueue.items.contains {
            $0.id == staleItemID && [.queued, .running].contains($0.status)
        })
    }

    @MainActor
    func testRetrySelectedPendingMetadataSyncRewritesSidecarThroughRealWorkerAfterStaleGenerationFailure() async throws {
        // Reproduces inspect-003's retry-FAIL leg end to end through the real
        // supervisor->executor path (a "loopback" transport that actually runs
        // WorkerCommandExecutor against the same repository, instead of the
        // dumb RecordingWorkerTransport other tests use). The prior fix
        // (ac207bbb) made Retry enqueue again; this proves the re-enqueued
        // command actually rewrites the sidecar and clears the pending row
        // when the pending row's recorded generation trails the current one.
        let directory = try makeTemporaryDirectory(named: "retry-selected-pending-loopback")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "retry-selected-pending-loopback"),
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 2)
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let initialWrite = try XMPSidecarStore().write(metadata: asset.metadata, forOriginalAt: originalURL)
        try repository.markMetadataSynced(
            assetID: asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
            fingerprint: initialWrite.fingerprint
        )

        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: photosDirectory.path)
        try repository.updateMetadata(assetID: asset.id) { $0.rating = 3 }
        _ = try executor.execute(.syncMetadata(assetID: asset.id))
        try repository.updateMetadata(assetID: asset.id) { $0.rating = 4 }
        _ = try executor.execute(.syncMetadata(assetID: asset.id))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: photosDirectory.path)

        let pendingBeforeRetry = try XCTUnwrap(try repository.pendingMetadataSyncItem(assetID: asset.id))
        XCTAssertNotEqual(
            pendingBeforeRetry.catalogGeneration,
            try repository.catalogGeneration(assetID: asset.id),
            "pending row must trail the catalog generation for this repro to be meaningful"
        )

        let transport = LoopbackWorkerTransport(executor: executor)
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
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
        model.pendingMetadataSyncItems = [pendingBeforeRetry]

        try model.retrySelectedMetadataSync()
        let itemID = WorkSessionID(rawValue: "xmp-\(asset.id.rawValue)-\(pendingBeforeRetry.catalogGeneration)")
        try await waitForBackgroundWorkStatus(.completed, itemID: itemID, in: model)

        XCTAssertEqual(transport.executedCommands, [.syncMetadata(assetID: asset.id)])
        if let lastError = transport.lastError {
            XCTFail("worker command threw: \(lastError)")
        }
        XCTAssertEqual(transport.lastResult, .completed("synced metadata for frame.cr2"))
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, AssetMetadata(rating: 4))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(
            try repository.lastMetadataSyncFingerprint(assetID: asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(model.pendingMetadataSyncItems, [])
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

    func testRetryPendingMetadataSyncInCurrentScopeQueuesTheSoleRetryableItem() throws {
        let fixture = try makePendingMetadataSyncScopeModelWithSingleRetryableItem(
            named: "retry-pending-xmp-single-retryable"
        )
        fixture.model.metadataSyncPendingFilter = true
        try fixture.model.reload()

        let queuedCount = try fixture.model.retryPendingMetadataSyncInCurrentScope()

        XCTAssertEqual(queuedCount, 1)
        XCTAssertEqual(try fixture.transport.commands(), [
            .syncMetadata(assetID: fixture.retryableAssetID)
        ])
    }

    func testCanRetryPendingMetadataSyncInCurrentScopeFindsTheSoleRetryableItem() throws {
        let fixture = try makePendingMetadataSyncScopeModelWithSingleRetryableItem(
            named: "can-retry-pending-xmp-single-retryable"
        )
        fixture.model.metadataSyncPendingFilter = true
        try fixture.model.reload()

        XCTAssertTrue(fixture.model.canRetryPendingMetadataSyncInCurrentScope)
    }

    func testCanRetryPendingMetadataSyncInCurrentScopeRequiresPendingFilterAndRetryableCurrentScopeItem() throws {
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

    func testToggleZoomCullingShortcutTogglesBetweenFitAndCenteredActualSize() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom", size: 1)])

        XCTAssertNil(model.loupeZoomFocus)

        try model.applyCullingShortcut(.toggleZoom)
        XCTAssertEqual(model.loupeZoomFocus, .center)

        try model.applyCullingShortcut(.toggleZoom)
        XCTAssertNil(model.loupeZoomFocus)
    }

    func testZoomLoupeSetsFocusPoint() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "zoom-focus", size: 1)])

        model.zoomLoupe(to: LoupeZoomFocus(x: 0.25, y: 0.75))

        XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.25, y: 0.75))
    }

    func testFrameAdvanceResetsLoupeZoom() throws {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])
        model.zoomLoupe(to: .center)

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.selectedAssetID, second.id)
        XCTAssertNil(model.loupeZoomFocus)
    }

    // The Culling menu's shortcut items (main.swift's `CullingCommands`) fire
    // via bare SwiftUI `.keyboardShortcut` bindings that are workspace-blind,
    // unlike `CullingKeyCaptureView`'s local key monitor which
    // `CullingKeyCaptureGate` scopes to the Cull workspace's loupe/compare/
    // A-B sub-views. `isCullingMenuShortcutActive` drives those menu items'
    // `.disabled` state so the menu can't leak a pick/reject write into e.g.
    // Library Loupe the way the bare "P" keystroke used to.
    func testCullingMenuShortcutActiveMirrorsKeyCaptureGate() {
        let asset = makeAsset(id: "menu-gate", size: 1)

        let libraryLoupe = AppModel(sidebarSections: [], selectedView: .libraryLoupe, assets: [asset])
        XCTAssertFalse(libraryLoupe.isCullingMenuShortcutActive)

        let libraryGrid = AppModel(sidebarSections: [], selectedView: .grid, assets: [asset])
        XCTAssertFalse(libraryGrid.isCullingMenuShortcutActive)

        let cullGrid = AppModel(sidebarSections: [], selectedView: .cullGrid, assets: [asset])
        XCTAssertFalse(cullGrid.isCullingMenuShortcutActive)

        let cullLoupe = AppModel(sidebarSections: [], selectedView: .loupe, assets: [asset])
        XCTAssertTrue(cullLoupe.isCullingMenuShortcutActive)
    }

    func testReselectingSameAssetKeepsLoupeZoom() {
        let first = makeAsset(id: "first", size: 1)
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first])
        model.zoomLoupe(to: .center)

        model.select(first.id)

        XCTAssertEqual(model.loupeZoomFocus, .center)
    }

    func testToggleZoomKeepsSelectionAndMetadataDecisionFeedback() throws {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "toggle-zoom-keeps-feedback",
            assets: [first, second]
        )

        try model.applyCullingShortcut(.pick)
        XCTAssertNotNil(model.lastCullingMetadataDecision)
        let selectionAfterPick = model.selectedAssetID

        try model.applyCullingShortcut(.toggleZoom)

        XCTAssertEqual(model.selectedAssetID, selectionAfterPick)
        XCTAssertNotNil(model.lastCullingMetadataDecision)
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

    func testCullingShortcutRecordsLastMetadataDecisionBeforeAdvancing() throws {
        let directory = try makeTemporaryDirectory(named: "culling-shortcut-feedback")
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

        try model.applyCullingShortcut(.rating(5))

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-1"))
        XCTAssertEqual(model.lastCullingMetadataDecision, CullingMetadataDecisionFeedback(
            assetID: firstID,
            filename: "frame-0.dng",
            command: .rating(5),
            decisionText: "Rated 5"
        ))
    }

    func testNavigationCullingShortcutsClearLastMetadataDecisionFeedback() throws {
        let first = makeAsset(id: "first", size: 1)
        let second = makeAsset(id: "second", size: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "culling-shortcut-feedback-clear",
            assets: [first, second]
        )

        try model.applyCullingShortcut(.pick)
        XCTAssertNotNil(model.lastCullingMetadataDecision)

        try model.applyCullingShortcut(.previousPhoto)

        XCTAssertNil(model.lastCullingMetadataDecision)
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

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: selected.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: next.id).metadata.flag)
        XCTAssertEqual(model.assets.map(\.metadata.flag), [.reject, .pick, .reject, nil])
        XCTAssertEqual(model.selectedAssetID, next.id)
    }

    func testLoadedStackSelectionUpdatesActiveCullingSessionProgressAndOutputSet() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(
            id: "loaded-stack-cull-first",
            path: "/Photos/Job/loaded-stack-cull-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let selected = makeAsset(
            id: "loaded-stack-cull-selected",
            path: "/Photos/Job/loaded-stack-cull-selected.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let alternate = makeAsset(
            id: "loaded-stack-cull-alternate",
            path: "/Photos/Job/loaded-stack-cull-alternate.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let next = makeAsset(
            id: "loaded-stack-cull-next",
            path: "/Photos/Other/loaded-stack-cull-next.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(4))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "loaded-stack-cull-session-progress",
            assets: [first, selected, alternate, next]
        )
        model.select(selected.id)
        let startedSession = try model.beginCullingSession(named: "Loaded Stack Cull")

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: selected.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .reject)
        XCTAssertNil(try repository.asset(id: next.id).metadata.flag)
        XCTAssertEqual(model.selectedAssetID, next.id)

        let session = try repository.session(id: startedSession.id)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.completedUnitCount, 3)
        XCTAssertEqual(session.totalUnitCount, 4)
        XCTAssertEqual(session.detail, "Reviewed 3 of 4 frames · 1 pick · 2 rejects")
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: outputSetID)), [selected.id])
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

        try model.applyCullingShortcut(.promoteAndRejectSiblings)

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

        try model.applyCullingShortcut(.promoteAndRejectSiblings)

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

        try model.applyCullingShortcut(.promoteAndRejectSiblings)

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

        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)

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

    func testFlaggingLastStackFramePublishesCullingCompletionSummary() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-summary",
            sessionID: "completion-summary-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        XCTAssertNil(fixture.model.cullingSessionCompletion)

        // Auto-advance landed on the second stack; decide it too.
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)

        let completion = try XCTUnwrap(fixture.model.cullingSessionCompletion)
        XCTAssertEqual(completion.sessionID, WorkSessionID(rawValue: "completion-summary-session"))
        XCTAssertEqual(completion.title, "Cull persisted stacks")
        XCTAssertEqual(completion.pickCount, 2)
        XCTAssertEqual(completion.rejectCount, 2)
        XCTAssertEqual(completion.picksSetID, AssetSetID(rawValue: "work-output-completion-summary-session-picks"))
        XCTAssertEqual(completion.detailText, "2 picks · 2 rejects — Cull persisted stacks")
    }

    func testOpeningCullingCompletionPicksAppliesTheOutputSet() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-open-picks",
            sessionID: "completion-open-picks-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        let completion = try XCTUnwrap(fixture.model.cullingSessionCompletion)
        let picksSetID = try XCTUnwrap(completion.picksSetID)

        try fixture.model.openCullingSessionPicks()

        XCTAssertEqual(fixture.model.selectedAssetSetID, picksSetID)
        XCTAssertEqual(fixture.model.selectedView, .grid)
        XCTAssertEqual(
            Set(fixture.model.assets.map(\.id)),
            [fixture.firstLead.id, fixture.secondLead.id]
        )
        XCTAssertNil(fixture.model.cullingSessionCompletion)
    }

    func testClearingAFlagWithdrawsTheCompletionSummary() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-withdrawn",
            sessionID: "completion-withdrawn-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        XCTAssertNotNil(fixture.model.cullingSessionCompletion)

        fixture.model.select(fixture.secondAlternate.id)
        try fixture.model.setFlagForSelectedAsset(nil)

        XCTAssertNil(fixture.model.cullingSessionCompletion)
    }

    func testStartingANewCullingSessionClearsTheCompletionSummary() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "completion-cleared-on-start",
            sessionID: "completion-cleared-on-start-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        XCTAssertNotNil(fixture.model.cullingSessionCompletion)

        fixture.model.selectedAssetSetID = nil
        try fixture.model.reload()
        _ = try fixture.model.beginCullingSession(named: "Fresh Cull")

        XCTAssertNil(fixture.model.cullingSessionCompletion)
    }

    func testStackCullCompletionOffersToCullLeftoverSingles() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let singletonFirst = makeAsset(
            id: "leftover-singleton-first",
            path: "/Photos/Import/leftover-singleton-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let singletonSecond = makeAsset(
            id: "leftover-singleton-second",
            path: "/Photos/Import/leftover-singleton-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(100))
        )
        let stackFirst = makeAsset(
            id: "leftover-stack-first",
            path: "/Photos/Import/leftover-stack-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(200))
        )
        let stackSecond = makeAsset(
            id: "leftover-stack-second",
            path: "/Photos/Import/leftover-stack-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(201))
        )
        let assets = [singletonFirst, singletonSecond, stackFirst, stackSecond]
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "stack-cull-leftover-singles",
            assets: assets,
            outputAssetIDs: assets.map(\.id)
        )

        let session = try model.beginStackCullingFromLatestImportCompletion()
        XCTAssertEqual(session.inputSetIDs.count, 1)
        XCTAssertNil(model.cullingSessionCompletion)

        // Decide the only stack; the session completes and should notice the
        // two unstacked singles that never got a flag.
        try model.applyCullingShortcut(.promoteAndRejectSiblings)

        let completion = try XCTUnwrap(model.cullingSessionCompletion)
        XCTAssertEqual(completion.remainingSingleCount, 2)
        XCTAssertEqual(
            Set(completion.remainingSingleAssetIDs),
            [singletonFirst.id, singletonSecond.id]
        )

        let singlesSession = try model.cullRemainingSinglesFromCullingCompletion()

        let singlesSetID = try XCTUnwrap(singlesSession.inputSetIDs.first)
        XCTAssertEqual(
            Set(assetIDs(in: try repository.assetSet(id: singlesSetID))),
            [singletonFirst.id, singletonSecond.id]
        )
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(
            Set(model.assets.map(\.id)),
            [singletonFirst.id, singletonSecond.id]
        )
        XCTAssertNil(try repository.asset(id: singletonFirst.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: singletonSecond.id).metadata.flag)
    }

    func testCullingCompletionHasNoLeftoverSinglesWhenEveryFrameIsStacked() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let stackFirst = makeAsset(
            id: "fully-stacked-first",
            path: "/Photos/Import/fully-stacked-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let stackSecond = makeAsset(
            id: "fully-stacked-second",
            path: "/Photos/Import/fully-stacked-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let assets = [stackFirst, stackSecond]
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "stack-cull-no-leftover-singles",
            assets: assets,
            outputAssetIDs: assets.map(\.id)
        )

        _ = try model.beginStackCullingFromLatestImportCompletion()
        try model.applyCullingShortcut(.promoteAndRejectSiblings)

        let completion = try XCTUnwrap(model.cullingSessionCompletion)
        XCTAssertEqual(completion.remainingSingleCount, 0)
        XCTAssertTrue(completion.remainingSingleAssetIDs.isEmpty)

        XCTAssertThrowsError(try model.cullRemainingSinglesFromCullingCompletion())
    }

    func testCullingStackListEntriesDescribeSessionStacksWithDecidedState() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-list-entries",
            sessionID: "stack-list-entries-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        let initialEntries = fixture.model.cullingStackListEntries()
        XCTAssertEqual(initialEntries.map(\.setID), [fixture.firstSet.id, fixture.secondSet.id])
        XCTAssertEqual(initialEntries.map(\.title), ["Stack 1", "Stack 2"])
        XCTAssertEqual(initialEntries.map(\.frameCountText), ["2 frames", "2 frames"])
        XCTAssertEqual(initialEntries.map(\.leadAssetID), [fixture.firstLead.id, fixture.secondLead.id])
        XCTAssertEqual(initialEntries.map(\.isDecided), [false, false])
        XCTAssertEqual(initialEntries.map(\.isSelected), [true, false])

        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)

        let advancedEntries = fixture.model.cullingStackListEntries()
        XCTAssertEqual(advancedEntries.map(\.isDecided), [true, false])
        XCTAssertEqual(advancedEntries.map(\.isSelected), [false, true])
    }

    func testCullingStackListEntriesAreEmptyOutsidePersistedStackSessions() throws {
        let first = makeAsset(id: "stack-list-none-first", path: "/Photos/Job/a.cr2", rating: 0)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "stack-list-entries-none",
            assets: [first]
        )
        model.select(first.id)

        XCTAssertEqual(model.cullingStackListEntries(), [])
    }

    func testSelectingAStackSetFromTheListJumpsToItsRecommendedFrame() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-list-jump",
            sessionID: "stack-list-jump-session"
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try fixture.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: fixture.secondAlternate.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance)
        ])
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.selectCullingStackSet(id: fixture.secondSet.id)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondAlternate.id)
        XCTAssertEqual(fixture.model.selectedView, .loupe)
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

        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)
        try fixture.model.applyCullingShortcut(.promoteAndRejectSiblings)

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

        XCTAssertNil(fixture.model.selectedAssetSetID)
        XCTAssertEqual(fixture.model.librarySearchText, "session:\(session.id.rawValue)")
        XCTAssertEqual(fixture.model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(session.id.rawValue)", target: .workSession(session.id))
        ])
        XCTAssertEqual(fixture.model.assets.map(\.id), [
            fixture.firstLead.id,
            fixture.firstAlternate.id,
            fixture.secondLead.id,
            fixture.secondAlternate.id
        ])
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
            version: "2",
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
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "sharpness", version: "2", settingsHash: "default")
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
        // Re-entry lands on the ranked frame: firstAlternate carries the only focus signal.
        XCTAssertEqual(model.selectedAssetID, firstAlternate.id)
    }

    func testNextStackNavigationSelectsRecommendedFrameWhenRanked() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-entry-recommended",
            sessionID: "stack-entry-recommended-session"
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try fixture.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: fixture.secondLead.id, kind: .focus, value: .score(0.4), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: fixture.secondAlternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondAlternate.id)
        XCTAssertEqual(fixture.model.selectedView, .loupe)
    }

    func testNextStackNavigationFallsBackToFirstFrameWithoutSignals() throws {
        let fixture = try makePersistedStackCullingFixture(
            named: "stack-entry-fallback",
            sessionID: "stack-entry-fallback-session"
        )
        try fixture.model.applyAssetSet(id: fixture.firstSet.id)
        fixture.model.select(fixture.firstLead.id)

        try fixture.model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(fixture.model.selectedAssetSetID, fixture.secondSet.id)
        XCTAssertEqual(fixture.model.selectedAssetID, fixture.secondLead.id)
    }

    func testBeginningStackCullingSelectsRecommendedFrameOfFirstStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let stackFirst = makeAsset(
            id: "recommended-entry-first",
            path: "/Photos/Import/recommended-entry-first.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let stackSecond = makeAsset(
            id: "recommended-entry-second",
            path: "/Photos/Import/recommended-entry-second.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "recommended-entry-stack-culling",
            assets: [stackFirst, stackSecond],
            outputAssetIDs: [stackFirst.id, stackSecond.id]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: stackSecond.id, kind: .focus, value: .score(0.92), confidence: 0.9, provenance: provenance)
        ])

        _ = try model.beginStackCullingFromLatestImportCompletion()

        XCTAssertEqual(model.selectedAssetID, stackSecond.id)
        XCTAssertEqual(model.selectedView, .loupe)
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

    func testCullingShortcutAdvancesAcrossWholeLoadedCatalog() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-next", count: 121)
        XCTAssertEqual(model.assets.count, 121)
        model.select(AssetID(rawValue: "asset-119"))

        try model.applyCullingShortcut(.nextPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-120"))
    }

    func testCullingShortcutRetreatsAcrossWholeLoadedCatalog() throws {
        let model = try makeModelWithSeededCatalog(named: "culling-previous", count: 360)
        XCTAssertEqual(model.assets.count, 360)
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "asset-0"))
        model.select(AssetID(rawValue: "asset-120"))

        try model.applyCullingShortcut(.previousPhoto)

        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "asset-119"))
    }

    func testCullingShortcutInterpretsKeyboardKeys() {
        XCTAssertEqual(CullingShortcut(key: .leftArrow), .previousStack)
        XCTAssertEqual(CullingShortcut(key: .rightArrow), .nextStack)
        XCTAssertEqual(CullingShortcut(key: .upArrow), .previousCandidateInStack)
        XCTAssertEqual(CullingShortcut(key: .downArrow), .nextCandidateInStack)
        XCTAssertEqual(CullingShortcut(key: .character(" ")), .nextPhoto)
        XCTAssertEqual(CullingShortcut(key: .returnKey), .promoteAndRejectSiblings)
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

    func testVisibleWorkActivitiesDoNotClaimUndispatchedWorkerItemsAreRunning() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 2),
            transport: transport
        )
        let first = makeAsset(id: "dispatched-preview", size: 1)
        let second = makeAsset(id: "undispatched-preview", size: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "undispatched-worker-activity",
            assets: [first, second],
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: first.id, level: .grid)
        try model.requestPreview(assetID: second.id, level: .grid)

        XCTAssertEqual(model.backgroundWorkQueue.runningItems.map(\.id.rawValue), [
            "preview-\(first.id.rawValue)-grid",
            "preview-\(second.id.rawValue)-grid"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: first.id, level: .grid)
        ])
        XCTAssertEqual(model.visibleWorkActivities.map(\.status), [.running, .queued])
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

    func testBatchMetadataUndoRevertsAllAssetsInOneStep() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "undo-batch-a", path: "/Photos/Job/undo-batch-a.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let second = makeAsset(id: "undo-batch-b", path: "/Photos/Job/undo-batch-b.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-batch-metadata", assets: [first, second])
        try model.selectSidebarTarget(.allPhotographs)

        let applied = try model.applyVisibleBatchMetadata(keywordText: "patagonia", caption: "", creator: "", copyright: "")
        XCTAssertEqual(applied, 2)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertEqual(model.lastUndoableActionLabel, "Applied metadata to 2 photos")

        try model.undoMetadataChange()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, [])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, [])
        XCTAssertFalse(model.canUndoMetadataChange)
        XCTAssertTrue(model.canRedoMetadataChange)
        XCTAssertEqual(model.statusMessage, "Undid: Applied metadata to 2 photos")
    }

    func testBatchKeywordUndoRevertsAllAssetsInOneStep() throws {
        let first = makeAsset(id: "undo-kw-a", path: "/Photos/Job/undo-kw-a.cr2", rating: 0)
        let second = makeAsset(id: "undo-kw-b", path: "/Photos/Job/undo-kw-b.cr2", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-batch-keyword", assets: [first, second])
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: second.id, kind: .object, value: .label("mountain"), confidence: 0.7, provenance: provenance)
        ])
        try model.selectSidebarTarget(.allPhotographs)

        let applied = try model.acceptVisibleBatchKeywordSuggestion("mountain")
        XCTAssertEqual(applied, 2)
        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertEqual(model.lastUndoableActionLabel, "Applied mountain to 2 photos")

        try model.undoMetadataChange()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, [])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, [])
        XCTAssertFalse(model.canUndoMetadataChange)
        XCTAssertEqual(model.statusMessage, "Undid: Applied mountain to 2 photos")

        try model.redoMetadataChange()

        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(model.statusMessage, "Redid: Applied mountain to 2 photos")
    }

    func testCullingDecisionUndoRevertsAllContenderFlagsInOneStep() throws {
        let assets = (0..<9).map { makeAsset(id: "undo-cull-\($0)", size: Int64($0 + 1)) }
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-culling-decision", assets: assets)
        model.selectedView = .compare
        model.select(assets[1].id)

        try model.keepCompareAssetAndRejectAlternates(assetID: assets[3].id)

        XCTAssertTrue(model.canUndoMetadataChange)
        XCTAssertEqual(model.lastUndoableActionLabel, "Kept 1, rejected 7")
        for asset in assets[0..<8] {
            XCTAssertNotNil(try repository.asset(id: asset.id).metadata.flag)
        }

        try model.undoMetadataChange()

        for asset in assets {
            XCTAssertNil(try repository.asset(id: asset.id).metadata.flag)
        }
        XCTAssertFalse(model.canUndoMetadataChange)
        XCTAssertEqual(model.statusMessage, "Undid: Kept 1, rejected 7")

        try model.redoMetadataChange()

        XCTAssertEqual(try repository.asset(id: assets[3].id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: assets[0].id).metadata.flag, .reject)
        XCTAssertEqual(model.statusMessage, "Redid: Kept 1, rejected 7")
    }

    func testSingleFlagEditRemainsAOneChangeGroup() throws {
        let asset = makeAsset(id: "undo-single", path: "/Photos/Job/undo-single.cr2", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-single", assets: [asset])
        model.select(asset.id)

        try model.setFlagForSelectedAsset(.pick)
        XCTAssertEqual(model.lastUndoableActionLabel, "Flag")

        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: asset.id).metadata.flag)
        try model.redoMetadataChange()
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.flag, .pick)
    }

    func testRunAutopilotProducesPendingProposalsWithoutWritingMetadata() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "ap-lead", path: "/Photos/Job/ap-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "ap-alt", path: "/Photos/Job/ap-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)

        let summary = try model.runAutopilot(scope: .visible)

        XCTAssertEqual(summary.keeperCount, 1)
        XCTAssertEqual(summary.rejectCount, 1)
        XCTAssertEqual(summary.stackCount, 1)
        XCTAssertEqual(summary.bannerText, "1 keepers · 1 rejects · dupes→stacks")
        XCTAssertEqual(model.autopilotProposalDecision(for: alternate.id), .pick)
        XCTAssertEqual(model.autopilotProposalDecision(for: lead.id), .reject)
        // Provisional only: nothing written.
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
    }

    func testRunAutopilotOnCurrentScopeProducesProposalsWithoutWritingMetadata() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "ondemand-lead", path: "/Photos/Job/ondemand-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "ondemand-alt", path: "/Photos/Job/ondemand-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot-ondemand", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        let leadGenerationBefore = try repository.catalogGeneration(assetID: lead.id)
        let alternateGenerationBefore = try repository.catalogGeneration(assetID: alternate.id)

        let summary = try model.runAutopilotOnCurrentScope()

        XCTAssertEqual(summary?.keeperCount, 1)
        XCTAssertEqual(summary?.rejectCount, 1)
        XCTAssertNotNil(model.autopilotRunSummary)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
        // Provisional only: nothing written, so no catalog generation bump.
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertEqual(try repository.catalogGeneration(assetID: lead.id), leadGenerationBefore)
        XCTAssertEqual(try repository.catalogGeneration(assetID: alternate.id), alternateGenerationBefore)
    }

    func testRunAutopilotOnFlatDistinctLibrarySurfacesKeywordOutcomeNotBareZero() throws {
        // A normal flat library: distinct singletons, no bursts. The marquee
        // keep/cut path honestly yields nothing to rank, but the run still
        // produces keyword suggestions. The banner must name that outcome
        // rather than the demoralizing bare "0 keepers · 0 rejects".
        let first = makeAsset(id: "flat-1", path: "/Photos/Trip/flat-1.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 100)))
        let second = makeAsset(id: "flat-2", path: "/Photos/Trip/flat-2.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: Date(timeIntervalSince1970: 100_000)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot-flat", assets: [first, second]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "objects", version: "1", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: first.id, kind: .object, value: .label("beach"), confidence: 0.8, provenance: provenance),
                EvaluationSignal(assetID: second.id, kind: .object, value: .label("mountain"), confidence: 0.8, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)

        let summary = try model.runAutopilot(scope: .visible)

        XCTAssertEqual(summary.keeperCount, 0)
        XCTAssertEqual(summary.rejectCount, 0)
        XCTAssertEqual(summary.stackCount, 0)
        XCTAssertEqual(summary.keywordCount, 2)
        XCTAssertEqual(summary.bannerText, "No clear cuts to propose — 2 keyword suggestions ready to review")
        XCTAssertEqual(model.statusMessage?.contains("0 keepers"), false)
        XCTAssertEqual(model.statusMessage, "Autopilot: No clear cuts to propose — 2 keyword suggestions ready to review")
        // Confirm-before-write: nothing committed to metadata by the run itself.
        XCTAssertNil(try repository.asset(id: first.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: second.id).metadata.flag)
        XCTAssertTrue(try repository.asset(id: first.id).metadata.keywords.isEmpty)
        XCTAssertTrue(try repository.asset(id: second.id).metadata.keywords.isEmpty)
    }

    func testRunAutopilotOnCurrentScopeWithoutEvaluationsSetsStatusMessage() throws {
        let unevaluated = makeAsset(id: "noeval", path: "/Photos/Job/noeval.cr2", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot-noeval", assets: [unevaluated])
        try model.selectSidebarTarget(.allPhotographs)

        let summary = try model.runAutopilotOnCurrentScope()

        XCTAssertNil(summary)
        XCTAssertNil(model.autopilotRunSummary)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 0)
        XCTAssertEqual(model.statusMessage, "Autopilot: no evaluated photos in view to run on")
    }

    func testBeginAutopilotReviewLoadsProposedAssets() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "rev-lead", path: "/Photos/Job/rev-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "rev-alt", path: "/Photos/Job/rev-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, _) = try makeModelWithCatalogAssets(named: "autopilot-review", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)

        try model.beginAutopilotReview()

        XCTAssertTrue(model.isAutopilotReviewActive)
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(Set(model.assets.map(\.id)), [lead.id, alternate.id])
        XCTAssertEqual(model.autopilotReviewProposalCount, 2)
    }

    func testRunAutopilotIsIdempotentForTheSameScope() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "ap2-lead", path: "/Photos/Job/ap2-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "ap2-alt", path: "/Photos/Job/ap2-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "run-autopilot-idem", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)

        _ = try model.runAutopilot(scope: .visible)
        _ = try model.runAutopilot(scope: .visible)

        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
    }

    func testCommitAllAutopilotProposalsWritesFlagsAndKeywordsAsOneUndoGroup() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "commit-lead", path: "/Photos/Job/commit-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "commit-alt", path: "/Photos/Job/commit-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "commit-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)

        let committed = try model.commitAllAutopilotProposals()

        XCTAssertEqual(committed, 2)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: lead.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 0)
        XCTAssertEqual(model.lastUndoableActionLabel, "Autopilot")

        // Exactly one undo group reverts the whole batch.
        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertFalse(model.canUndoMetadataChange)
    }

    func testCommitAllAutopilotProposalsSkipsDanglingProposalForMissingAsset() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "dangling-lead", path: "/Photos/Job/dangling-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "dangling-alt", path: "/Photos/Job/dangling-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let directory = try makeTemporaryDirectory(named: "commit-autopilot-dangling")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert([lead, alternate])
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
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
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)
        XCTAssertEqual(model.pendingAutopilotProposals.count, 2)

        // Simulate a proposal left dangling by data corruption or a bypassed
        // cascade: delete the asset row directly (not via repository.deleteAsset,
        // which would clean up the proposal) so the proposal row survives with
        // no matching asset.
        try database.execute("DELETE FROM assets WHERE id = ?", bindings: [lead.id.rawValue])

        let committed = try model.commitAllAutopilotProposals()

        XCTAssertEqual(committed, 1)
        XCTAssertEqual(try repository.asset(id: alternate.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.autopilotProposals(status: .pending), [])
        XCTAssertEqual(try repository.autopilotProposals(status: .dismissed).count, 1)
    }

    func testUndoAutopilotRunRevertsMetadataAndRestoresPendingProposals() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "undoall-lead", path: "/Photos/Job/undoall-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "undoall-alt", path: "/Photos/Job/undoall-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "undo-all-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)
        _ = try model.commitAllAutopilotProposals()
        XCTAssertTrue(model.canUndoAutopilotRun)

        try model.undoAutopilotRun()

        XCTAssertNil(try repository.asset(id: alternate.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertEqual(try repository.pendingAutopilotProposalCount(), 2)
        XCTAssertEqual(model.autopilotProposalDecision(for: alternate.id), .pick)
        XCTAssertFalse(model.canUndoAutopilotRun)
    }

    func testDismissAutopilotProposalsLeavesMetadataUntouched() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "dismiss-lead", path: "/Photos/Job/dismiss-lead.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt))
        let alternate = makeAsset(id: "dismiss-alt", path: "/Photos/Job/dismiss-alt.cr2", rating: 0, technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)))
        let (model, repository) = try makeModelWithCatalogAssets(named: "dismiss-autopilot", assets: [lead, alternate]) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)
        _ = try model.runAutopilot(scope: .visible)

        let dismissed = try model.dismissAutopilotProposals(assetIDs: [lead.id])

        XCTAssertEqual(dismissed, 1)
        XCTAssertNil(try repository.asset(id: lead.id).metadata.flag)
        XCTAssertEqual(model.autopilotProposalDecision(for: lead.id), nil)
        XCTAssertEqual(model.autopilotProposalDecision(for: alternate.id), .pick)
        XCTAssertFalse(model.canUndoMetadataChange)
    }

    func testAskFallsBackToDeterministicParserWithoutTranslator() throws {
        let asset = makeAsset(id: "ask-fallback", path: "/Photos/Job/ask-fallback.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "ask-fallback", assets: [asset])
        try model.selectSidebarTarget(.allPhotographs)

        try model.applyNaturalLanguageAsk("rating:5")

        XCTAssertEqual(model.librarySearchText, "rating:5")
        XCTAssertTrue(model.activeLibraryFilterChips.contains("Rating >= 5"))
    }

    func testAskUsesConfiguredTranslatorAndRendersSameChipVocabulary() throws {
        let asset = makeAsset(id: "ask-translated", path: "/Photos/Job/ask-translated.cr2", rating: 4, keywords: ["dog"])
        let (model, _) = try makeModelWithCatalogAssets(named: "ask-translated", assets: [asset])
        try model.selectSidebarTarget(.allPhotographs)
        model.autopilotQueryTranslator = StubQueryTranslator(query: "rating:4 keyword:dog")

        try model.applyNaturalLanguageAsk("four star dog photos")

        XCTAssertEqual(model.librarySearchText, "rating:4 keyword:dog")
        XCTAssertTrue(model.activeLibraryFilterChips.contains("Rating >= 4"))
        XCTAssertTrue(model.activeLibraryFilterChips.contains("Keyword: dog"))
    }

    func testAskFallsBackToRawTextWhenTranslatorFails() throws {
        let asset = makeAsset(id: "ask-error", path: "/Photos/Job/ask-error.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "ask-error", assets: [asset])
        try model.selectSidebarTarget(.allPhotographs)
        model.autopilotQueryTranslator = FailingQueryTranslator()

        try model.applyNaturalLanguageAsk("rating:5")

        XCTAssertEqual(model.librarySearchText, "rating:5")
        XCTAssertTrue(model.activeLibraryFilterChips.contains("Rating >= 5"))
        XCTAssertEqual(model.statusMessage, "Ask used plain-text search (model unavailable)")
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

    func testLoadReturnsEveryCatalogAsset() throws {
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

        XCTAssertEqual(model.assets.count, 501)
        XCTAssertEqual(model.totalAssetCount, 501)
        XCTAssertEqual(model.libraryCountText, "501 photos")
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

        XCTAssertEqual(model.assets.count, 100_000)
        XCTAssertEqual(model.catalogFolders, [
            CatalogFolder(path: "/Volumes/NAS/Photos/", name: "Photos", assetCount: 100_000)
        ])
        XCTAssertFalse(rowQueries.contains { sql in
            sql.contains("SELECT original_path FROM assets")
        })
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
        XCTAssertEqual(model.libraryCountText, "1 photo")
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

    func testSavingLibrarySearchIntentPreservesQuotedFieldsAndImportBatch() throws {
        let frame = makeAsset(
            id: "quoted-field-frame",
            path: "/Volumes/NAS/Wedding 2026/frame-1.jpg",
            rating: 5,
            keywords: ["New York"]
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-library-search-quoted-fields",
            assets: [frame]
        )

        model.librarySearchText = "folder:\"/Volumes/NAS/Wedding 2026\" keyword:\"New York\" import:import-42"

        let savedSet = try model.saveCurrentLibraryQuery(named: "Quoted Import")

        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .folderPrefix("/Volumes/NAS/Wedding 2026"),
            .keyword("New York"),
            .importBatch("import-42")
        ])))
        XCTAssertEqual(model.librarySearchText, "")
    }

    func testSavedSearchWithPersonPredicateFiltersAssetsWhenSelected() throws {
        let annaPhoto = makeAsset(id: "anna-photo", path: "/Photos/Wedding/anna-photo.jpg", rating: 0)
        let other = makeAsset(id: "other", path: "/Photos/Wedding/other.jpg", rating: 0)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "person-saved-search",
            assets: [annaPhoto, other],
            configureRepository: { repository in
                try repository.upsertPerson(id: "person-anna", name: "Anna")
                try repository.assignAssets([annaPhoto.id], toPersonID: "person-anna")
            }
        )

        model.librarySearchText = "person:Anna"

        let savedSet = try model.saveCurrentLibraryQuery(named: "Anna")

        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [.person("Anna")])))
        XCTAssertEqual(model.librarySearchText, "")

        try model.selectSidebarTarget(.assetSet(savedSet.id))

        XCTAssertEqual(model.assets.map(\.id), [annaPhoto.id])
        XCTAssertEqual(model.totalAssetCount, 1)
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
        model.librarySearchText = "picks 5 stars needs evaluation session:cull-42 import:import-7"
        model.availabilityFilter = .missing
        model.evaluationKindFilter = .faceQuality
        model.metadataSyncPendingFilter = true

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
            ActiveLibraryFilterRow(title: "Rating >= 5", target: .reviewQueue(.fiveStars)),
            ActiveLibraryFilterRow(title: "Not analyzed yet", target: .reviewQueue(.needsEvaluation)),
            ActiveLibraryFilterRow(title: "Session: cull-42", target: .workSession(WorkSessionID(rawValue: "cull-42"))),
            ActiveLibraryFilterRow(title: "Import: import-7", target: .workSession(WorkSessionID(rawValue: "import-7"))),
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

    func testActiveLibraryFilterRowsFlagResidualSearchTextAsPlainSearchFallback() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.librarySearchText = "ceremony picks"

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Search: ceremony", isPlainSearchFallback: true),
            ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks))
        ])
    }

    func testActiveLibraryFilterRowsOmitPlainSearchFallbackFlagWhenSearchIsFullyParsed() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.librarySearchText = "picks 5 stars"

        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Pick", target: .reviewQueue(.picks)),
            ActiveLibraryFilterRow(title: "Rating >= 5", target: .reviewQueue(.fiveStars))
        ])
        XCTAssertFalse(model.activeLibraryFilterRows.contains { $0.isPlainSearchFallback })
    }

    func testActiveLibraryFilterRowsOmitPlainSearchFallbackFlagWhenSearchTextIsEmpty() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])

        XCTAssertTrue(model.activeLibraryFilterRows.isEmpty)
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

        // Timeline's sidebar row is gone (Task 7); the View menu's temporary
        // "Timeline" item drives the same route until Task 10 lands the
        // Library view toggle.
        model.selectedView = .timeline

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

        // The sidebar "AI" section is retired; the `signal:` filter-bar token
        // is the sole remaining route to this filter (Task 8 replaces it with
        // first-class tokens), so exercise the underlying model filter directly.
        model.selectedAssetSetID = nil
        model.evaluationKindFilter = .faceQuality
        model.selectedView = .grid
        try model.reload()

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

        // Review-queue rows are gone from the Library sidebar (Task 7 moves
        // them to the Cull sidebar in Task 13); the counts stay live on the
        // model and each queue's target still applies its filter directly.
        XCTAssertEqual(reviewQueueCount("Picks", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Rejects", in: model), "1")
        XCTAssertEqual(reviewQueueCount("5 Stars", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Needs Keywords", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Not analyzed yet", in: model), "2")
        XCTAssertEqual(reviewQueueCount("Faces Found", in: model), "1")
        XCTAssertEqual(reviewQueueCount("OCR Found", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Likely Issues", in: model), "1")
        XCTAssertEqual(reviewQueueCount("Analysis Failures", in: model), "1")

        try model.selectSidebarTarget(.reviewQueue(.picks))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.rejects))

        XCTAssertEqual(model.flagFilter, .reject)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.assets.map(\.id), [reject.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.fiveStars))

        XCTAssertNil(model.flagFilter)
        XCTAssertEqual(model.minimumRatingFilter, 5)
        XCTAssertEqual(model.assets.map(\.id), [fiveStar.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.needsKeywords))

        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertTrue(model.needsKeywordsFilter)
        XCTAssertEqual(model.assets.map(\.id), [needsKeywords.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.needsEvaluation))

        XCTAssertNil(model.flagFilter)
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertFalse(model.needsKeywordsFilter)
        XCTAssertTrue(model.needsEvaluationFilter)
        XCTAssertEqual(model.assets.map(\.id), [unreviewed.id, needsKeywords.id])
        XCTAssertEqual(model.totalAssetCount, 2)

        try model.selectSidebarTarget(.reviewQueue(.facesFound))

        XCTAssertEqual(model.evaluationKindFilter, .faceCount)
        XCTAssertEqual(model.assets.map(\.id), [faceFound.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.ocrFound))

        XCTAssertEqual(model.evaluationKindFilter, .ocrText)
        XCTAssertEqual(model.assets.map(\.id), [ocrFound.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.likelyIssues))

        XCTAssertTrue(model.likelyIssuesFilter)
        XCTAssertNil(model.evaluationKindFilter)
        XCTAssertEqual(model.assets.map(\.id), [likelyIssue.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        try model.selectSidebarTarget(.reviewQueue(.providerFailures))

        XCTAssertTrue(model.providerFailuresFilter)
        XCTAssertFalse(model.likelyIssuesFilter)
        XCTAssertNil(model.evaluationKindFilter)
        XCTAssertEqual(model.assets.map(\.id), [providerFailure.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testFindBestShotsRoutesToPicksWhenTheUserAlreadyHasThem() throws {
        let pick = makeAsset(id: "fbs-pick", path: "/Photos/Job/fbs-pick.jpg", rating: 4, flag: .pick, keywords: ["tagged"])
        let plain = makeAsset(id: "fbs-plain", path: "/Photos/Job/fbs-plain.jpg", rating: 3, keywords: ["tagged"])
        let (model, _) = try makeModelWithCatalogAssets(named: "find-best-shots-picks", assets: [pick, plain])

        XCTAssertTrue(model.canFindBestShots)
        let plan = try model.findBestShots()

        XCTAssertEqual(plan.route, .reviewQueue(.picks))
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
    }

    func testFindBestShotsNeverDeadEndsOnAnUnrankableScope() throws {
        // No picks, nothing likely-picks, and no worker to evaluate with: the
        // action must surface plain language, not route to an empty queue and
        // never a bare "0".
        let plain = makeAsset(id: "fbs-distinct", path: "/Photos/Job/fbs-distinct.jpg", rating: 3, keywords: ["tagged"])
        let (model, _) = try makeModelWithCatalogAssets(named: "find-best-shots-empty", assets: [plain])

        let plan = try model.findBestShots()

        XCTAssertEqual(plan.route, .nothingRanked(message: FindBestShotsRouter.nothingRankedMessage))
        XCTAssertEqual(model.statusMessage, FindBestShotsRouter.nothingRankedMessage)
        XCTAssertFalse((model.statusMessage ?? "").contains("0 keepers"))
    }

    func testReviewSidebarShowsOnlyQueuesWithCatalogBackedCounts() throws {
        let pick = makeAsset(id: "single-review-pick", path: "/Photos/Job/single-review-pick.jpg", rating: 4, flag: .pick, keywords: ["tagged"])
        let plain = makeAsset(id: "single-review-plain", path: "/Photos/Job/single-review-plain.jpg", rating: 3, keywords: ["tagged"])
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "single-review-sidebar",
            assets: [pick, plain]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: pick.id, kind: .object, value: .label("camera"), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: plain.id, kind: .object, value: .label("camera"), confidence: 0.8, provenance: provenance)
        ])
        try model.reload()

        // Review-queue rows are gone from the Library sidebar (Task 7); the
        // "only queues with catalog-backed counts" behavior now lives purely
        // in `reviewQueueCounts` (nil/absent entries for empty queues).
        // Both assets carry evaluation signals and reload() refreshes counts,
        // so "Not analyzed yet" is empty — it previously showed the stale
        // pre-signal count (persona-7's sidebar drift).
        XCTAssertEqual(reviewQueueCount("Picks", in: model), "1")
        XCTAssertNil(reviewQueueCount("Not analyzed yet", in: model))
        XCTAssertNil(reviewQueueCount("Rejects", in: model))
    }

    func testSelectingAllPhotographsSidebarRowReturnsToGridAndClearsFilters() throws {
        let filtered = makeAsset(id: "filtered", path: "/Photos/Job/filtered.jpg", rating: 5, keywords: ["selected"])
        let unfiltered = makeAsset(id: "unfiltered", path: "/Photos/Job/unfiltered.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-all-photos-sidebar",
            assets: [filtered, unfiltered]
        )
        model.selectedView = .timeline
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        XCTAssertEqual(model.assets.map(\.id), [filtered.id])

        // The sidebar is empty while in Cull's sub-views (Task 7); the All
        // Photographs target still works directly regardless of which
        // sidebar rows are currently rendered.
        try model.selectSidebarTarget(.allPhotographs)

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

        XCTAssertNil(reviewQueueCount("Picks", in: model))
        XCTAssertNil(reviewQueueCount("5 Stars", in: model))
        XCTAssertNil(reviewQueueCount("Needs Keywords", in: model))

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

        XCTAssertEqual(reviewQueueCount("Not analyzed yet", in: model), "1")

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        try model.requestEvaluation(assetID: asset.id, provider: "apple-vision")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-apple-vision"),
            message: "evaluated \(asset.id.rawValue) with apple-vision"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        XCTAssertNil(reviewQueueCount("Not analyzed yet", in: model))
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
        XCTAssertEqual(starredCollectionRows(model).map(\.title), [starred.name])
        XCTAssertEqual(sidebarRowCount(starred.name, in: "Collections", of: model), "2")
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
        XCTAssertTrue(starredCollectionRows(model).isEmpty)

        try model.toggleAssetSetStarred(id: savedSet.id)

        XCTAssertTrue(try repository.assetSet(id: savedSet.id).starred)
        XCTAssertEqual(model.starredAssetSets.map(\.id), [savedSet.id])
        XCTAssertEqual(starredCollectionRows(model).map(\.title), ["Five Stars"])
        XCTAssertEqual(sidebarRowCount("Five Stars", in: "Collections", of: model), "1")

        try model.setAssetSetStarred(id: savedSet.id, starred: false)

        XCTAssertFalse(try repository.assetSet(id: savedSet.id).starred)
        XCTAssertEqual(model.starredAssetSets, [])
        XCTAssertTrue(starredCollectionRows(model).isEmpty)
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

    func testFolderSidebarTreeCollapsesSharedRootToOneRowByDefault() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-sidebar",
            assets: [ceremony, portraits, travel]
        )

        let folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })

        // "/Volumes/NAS" holds no photos of its own and has no sibling
        // directories, so it reads as one collapsed root row rather than
        // two meaningless expand clicks through "Volumes" then "NAS".
        XCTAssertEqual(folderSection.rowTitles, ["NAS"])
        let rootRow = folderSection.rows[0]
        XCTAssertEqual(rootRow.depth, 0)
        XCTAssertEqual(rootRow.disclosure, .collapsed)
        XCTAssertEqual(rootRow.countText, "3")
        XCTAssertEqual(rootRow.detailText, "/Volumes/NAS/")
        XCTAssertEqual(rootRow.target, .folder("/Volumes/NAS/"))
    }

    func testExpandingFolderRowRevealsChildrenAndTogglingAgainCollapsesThem() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-sidebar-expand",
            assets: [ceremony, portraits, travel]
        )

        model.toggleFolderExpansion(path: "/Volumes/NAS/")

        var folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        XCTAssertEqual(folderSection.rowTitles, ["NAS", "Travel", "Wedding"])
        XCTAssertEqual(folderSection.rows[0].disclosure, .expanded)
        let travelRow = folderSection.rows[1]
        let weddingRow = folderSection.rows[2]
        XCTAssertEqual(travelRow.depth, 1)
        XCTAssertEqual(travelRow.disclosure, .none)
        XCTAssertEqual(travelRow.countText, "1")
        XCTAssertEqual(weddingRow.depth, 1)
        XCTAssertEqual(weddingRow.disclosure, .collapsed)
        XCTAssertEqual(weddingRow.countText, "2")

        model.toggleFolderExpansion(path: "/Volumes/NAS/")

        folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        XCTAssertEqual(folderSection.rowTitles, ["NAS"])
        XCTAssertEqual(folderSection.rows[0].disclosure, .collapsed)
    }

    func testExpandingNestedFolderRowRevealsGrandchildrenAndSelectingALeafAppliesFilter() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-sidebar-nested",
            assets: [ceremony, portraits, travel]
        )

        model.toggleFolderExpansion(path: "/Volumes/NAS/")
        model.toggleFolderExpansion(path: "/Volumes/NAS/Wedding/")

        let folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        XCTAssertEqual(folderSection.rowTitles, ["NAS", "Travel", "Wedding", "Ceremony", "Portraits"])
        let ceremonyRow = try XCTUnwrap(folderSection.rows.first { $0.title == "Ceremony" })
        XCTAssertEqual(ceremonyRow.depth, 2)
        XCTAssertEqual(ceremonyRow.disclosure, .none)

        try model.selectSidebarRow(ceremonyRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.folderFilterText, "/Volumes/NAS/Wedding/Ceremony/")
        XCTAssertEqual(model.assets.map(\.id), [ceremony.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testSelectingABranchFolderRowScopesToAllOfItsDescendants() throws {
        let ceremony = makeAsset(id: "ceremony", path: "/Volumes/NAS/Wedding/Ceremony/frame-1.cr2", rating: 4)
        let portraits = makeAsset(id: "portraits", path: "/Volumes/NAS/Wedding/Portraits/frame-2.cr2", rating: 5)
        let travel = makeAsset(id: "travel", path: "/Volumes/NAS/Travel/frame-3.cr2", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-folder-sidebar-branch-select",
            assets: [ceremony, portraits, travel]
        )

        model.toggleFolderExpansion(path: "/Volumes/NAS/")
        let folderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        let weddingRow = try XCTUnwrap(folderSection.rows.first { $0.title == "Wedding" })

        try model.selectSidebarRow(weddingRow)

        XCTAssertEqual(model.folderFilterText, "/Volumes/NAS/Wedding/")
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([ceremony.id, portraits.id]))
        XCTAssertEqual(model.totalAssetCount, 2)
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

    func testNamedPeoplePersistAcrossCatalogRelaunch() throws {
        // Regression test for a persona report (Ruth, persona-2): after naming two
        // people, an app freeze + quit + relaunch appeared to show "0 people" even
        // though the catalog rows were confirmed present beforehand. AppModel.load
        // re-reads people from the catalog on every launch (no caching layer), so
        // this proves catalog-backed people survive a fresh load against the same
        // database file, simulating a relaunch.
        let directory = try makeTemporaryDirectory(named: "app-model-people-relaunch")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        let asset = makeAsset(id: "rose-frame", path: "/Volumes/NAS/Family/rose.jpg", rating: 4)

        do {
            let database = try CatalogDatabase.open(at: catalogURL)
            try database.migrate()
            let repository = CatalogRepository(database: database)
            try repository.upsert(asset)
            try repository.upsertPerson(id: "person-rose", name: "Grandma Rose")
            try repository.assignAssets([asset.id], toPersonID: "person-rose")
            // `database` (and its underlying sqlite3 handle) goes out of scope here,
            // closing the connection the way process exit/kill would.
        }

        // Simulate relaunch: open a brand-new database/repository/AppModel against
        // the same catalog file, as `AppModel.load(catalog:)` does on every launch.
        let reopenedDatabase = try CatalogDatabase.open(at: catalogURL)
        try reopenedDatabase.migrate()
        let reopenedRepository = CatalogRepository(database: reopenedDatabase)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: reopenedRepository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )

        let relaunchedModel = try AppModel.load(catalog: catalog)

        XCTAssertEqual(relaunchedModel.catalogPeople, [
            CatalogPerson(id: "person-rose", name: "Grandma Rose", assetCount: 1)
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

    func testConfirmSelectedPersonRemovesAssignedAssetsFromFaceReviewQueue() throws {
        let selected = makeAsset(id: "selected-face-review", path: "/Volumes/NAS/Wedding/selected-face-review.jpg", rating: 4)
        let remaining = makeAsset(id: "remaining-face-review", path: "/Volumes/NAS/Wedding/remaining-face-review.jpg", rating: 4)
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-confirm-person-refreshes-face-review",
            assets: [selected, remaining],
            configureRepository: { repository in
                try repository.recordEvaluationSignals([
                    EvaluationSignal(assetID: selected.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
                    EvaluationSignal(assetID: remaining.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance)
                ])
            }
        )
        try model.selectSidebarTarget(.reviewQueue(.facesFound))
        model.selectedAssetID = selected.id

        let person = try model.confirmSelectedAssetsAsPerson(named: "Maya", id: "person-maya")

        XCTAssertEqual(person, CatalogPerson(id: "person-maya", name: "Maya", assetCount: 1))
        XCTAssertEqual(model.catalogPeople, [person])
        XCTAssertEqual(model.assets.map(\.id), [remaining.id])
        XCTAssertEqual(model.reviewQueueCounts[.facesFound], 1)
        XCTAssertEqual(model.catalogEvaluationKindSummaries, [
            CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 1)
        ])
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

    func testConfirmSelectedAssetsAsPersonWithExactNameMatchAttachesToExistingPerson() throws {
        let first = makeAsset(id: "first-face", path: "/Volumes/NAS/Wedding/first-face.jpg", rating: 4)
        let second = makeAsset(id: "second-face", path: "/Volumes/NAS/Wedding/second-face.jpg", rating: 4)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-confirm-person-attach-existing",
            assets: [first, second]
        )
        model.selectedAssetID = first.id
        _ = try model.confirmSelectedAssetsAsPerson(named: "Maya", id: "person-maya")

        model.selectedAssetID = second.id
        // Same name (case-insensitive, matching showPersonPhotos's
        // COLLATE NOCASE filter), different requested id — must attach to
        // the existing person, not mint a duplicate.
        let person = try model.confirmSelectedAssetsAsPerson(named: "MAYA", id: "person-maya-2")

        XCTAssertEqual(person.id, "person-maya")
        XCTAssertEqual(model.catalogPeople.count, 1)
        XCTAssertEqual(person.assetCount, 2)
        XCTAssertEqual(Set(try repository.assetIDs(personID: "person-maya")), [first.id, second.id])
    }

    func testConfirmSelectedAssetsAsPersonWithDistinctNameCreatesNewPerson() throws {
        let first = makeAsset(id: "first-face", path: "/Volumes/NAS/Wedding/first-face.jpg", rating: 4)
        let second = makeAsset(id: "second-face", path: "/Volumes/NAS/Wedding/second-face.jpg", rating: 4)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "app-model-confirm-person-distinct-name",
            assets: [first, second]
        )
        model.selectedAssetID = first.id
        _ = try model.confirmSelectedAssetsAsPerson(named: "Maya", id: "person-maya")

        model.selectedAssetID = second.id
        let person = try model.confirmSelectedAssetsAsPerson(named: "Robert", id: "person-robert")

        XCTAssertEqual(person.id, "person-robert")
        XCTAssertEqual(model.catalogPeople.count, 2)
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

    private func makeFaceSuggestionModel(
        named name: String
    ) throws -> (model: AppModel, repository: CatalogRepository, incoming: Asset, groupA: Asset, groupB: Asset) {
        let known = makeAsset(id: "known", path: "/Volumes/NAS/Wedding/known.jpg", rating: 0)
        let incoming = makeAsset(id: "incoming", path: "/Volumes/NAS/Wedding/incoming.jpg", rating: 0)
        let groupA = makeAsset(id: "group-a", path: "/Volumes/NAS/Wedding/group-a.jpg", rating: 0)
        let groupB = makeAsset(id: "group-b", path: "/Volumes/NAS/Wedding/group-b.jpg", rating: 0)
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        func observation(_ asset: Asset, _ embedding: [Double]) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.9,
                embedding: embedding,
                provenance: provenance
            )
        }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [known, incoming, groupA, groupB],
            configureRepository: { repository in
                try repository.replaceFaceObservations(assetID: known.id, provenance: provenance, with: [observation(known, [1, 0, 0])])
                try repository.replaceFaceObservations(assetID: incoming.id, provenance: provenance, with: [observation(incoming, [0.99, 0.1, 0])])
                try repository.replaceFaceObservations(assetID: groupA.id, provenance: provenance, with: [observation(groupA, [0, 1, 0])])
                try repository.replaceFaceObservations(assetID: groupB.id, provenance: provenance, with: [observation(groupB, [0, 0.99, 0.14])])
                try repository.upsertPerson(id: "person-maya", name: "Maya")
                try repository.assignFaces([FaceID(assetID: known.id, faceIndex: 0)], toPersonID: "person-maya")
            }
        )
        return (model, repository, incoming, groupA, groupB)
    }

    func testRefreshPeopleFaceSuggestionsBuildsMatchAndClusterSuggestions() throws {
        let (model, _, incoming, groupA, groupB) = try makeFaceSuggestionModel(named: "app-model-face-suggestions")

        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(model.peopleFaceSuggestions.count, 2)
        XCTAssertEqual(model.peopleFaceObservationAssetCount, 4)
        let match = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertEqual(match.kind, .matchExisting(personID: "person-maya", personName: "Maya"))
        XCTAssertEqual(match.faceIDs, [FaceID(assetID: incoming.id, faceIndex: 0)])
        XCTAssertEqual(match.assetIDs, [incoming.id])
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
        XCTAssertEqual(cluster.faceIDs, [
            FaceID(assetID: groupA.id, faceIndex: 0),
            FaceID(assetID: groupB.id, faceIndex: 0)
        ])
        XCTAssertEqual(cluster.id, "face-cluster-\(groupA.id.rawValue)-0")
    }

    func testConfirmMatchSuggestionAssignsFacesToExistingPerson() throws {
        let (model, repository, incoming, _, _) = try makeFaceSuggestionModel(named: "app-model-face-confirm-match")
        model.refreshPeopleFaceSuggestions()
        let match = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })

        try model.confirmPeopleFaceSuggestion(match)

        XCTAssertEqual(Set(try repository.assetIDs(personID: "person-maya")).contains(incoming.id), true)
        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertEqual(model.catalogPeople.first?.assetCount, 2)
    }

    func testConfirmClusterSuggestionCreatesNamedPersonThroughExistingPath() throws {
        let (model, repository, _, groupA, groupB) = try makeFaceSuggestionModel(named: "app-model-face-confirm-cluster")
        model.refreshPeopleFaceSuggestions()
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })

        let person = try model.confirmPeopleFaceSuggestion(cluster, personName: " Lee ", personID: "person-lee")

        XCTAssertEqual(person, CatalogPerson(id: "person-lee", name: "Lee", assetCount: 2))
        XCTAssertEqual(try repository.assetIDs(personID: "person-lee"), [groupA.id, groupB.id])
        XCTAssertNil(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
    }

    func testConfirmClusterSuggestionWithExactNameMatchAttachesToExistingPerson() throws {
        let (model, repository, _, groupA, groupB) = try makeFaceSuggestionModel(named: "app-model-face-confirm-cluster-attach")
        try repository.upsertPerson(id: "person-lee", name: "Lee")
        model.catalogPeople = try repository.people()
        model.refreshPeopleFaceSuggestions()
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })

        // Same name as an already-existing person, but a *different*
        // requested personID — must attach to person-lee, not mint a
        // duplicate "person-new-lee".
        let person = try model.confirmPeopleFaceSuggestion(cluster, personName: "Lee", personID: "person-new-lee")

        XCTAssertEqual(person.id, "person-lee")
        XCTAssertEqual(model.catalogPeople.filter { $0.name == "Lee" }.count, 1)
        XCTAssertEqual(try repository.assetIDs(personID: "person-lee"), [groupA.id, groupB.id])
    }

    func testMergePersonRefreshesFaceSuggestions() throws {
        let (model, repository, incoming, _, _) = try makeFaceSuggestionModel(named: "app-model-merge-refreshes-suggestions")
        try repository.upsertPerson(id: "person-robert", name: "Robert")
        model.refreshPeopleFaceSuggestions()
        XCTAssertNotNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })

        try model.mergePerson(sourceID: "person-maya", into: "person-robert")

        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        let refreshed = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-robert" })
        XCTAssertEqual(refreshed.faceIDs, [FaceID(assetID: incoming.id, faceIndex: 0)])
    }

    func testConfirmingStaleSuggestionForMergedAwayPersonThrows() throws {
        let (model, repository, _, _, _) = try makeFaceSuggestionModel(named: "app-model-merge-stale-confirm")
        try repository.upsertPerson(id: "person-robert", name: "Robert")
        model.refreshPeopleFaceSuggestions()
        let stale = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        try model.mergePerson(sourceID: "person-maya", into: "person-robert")

        XCTAssertThrowsError(try model.confirmPeopleFaceSuggestion(stale)) { error in
            XCTAssertEqual(error as? CatalogError, .notFound("person-maya"))
        }
        XCTAssertEqual(try repository.assetIDs(personID: "person-maya"), [])
        XCTAssertNil(
            try repository.confirmedFaceEmbeddingsByPerson(
                provenance: AppleVisionEvaluationProvider.faceProvenance
            )["person-maya"]
        )
        XCTAssertNotNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-robert" })
    }

    func testDismissSuggestionRemovesItFromFutureSuggestions() throws {
        let (model, repository, _, _, _) = try makeFaceSuggestionModel(named: "app-model-face-dismiss")
        model.refreshPeopleFaceSuggestions()
        let cluster = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.kind == .newPerson })

        try model.dismissPeopleFaceSuggestion(cluster)

        XCTAssertNil(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
        XCTAssertEqual(try repository.people(), model.catalogPeople)
        XCTAssertEqual(try repository.assetIDs(personID: "person-lee"), [])
    }

    func testDismissSelectedFaceReviewAssetsRefreshesFaceSuggestions() throws {
        let (model, _, incoming, _, _) = try makeFaceSuggestionModel(named: "app-model-dismiss-assets-refreshes-suggestions")
        model.refreshPeopleFaceSuggestions()
        XCTAssertNotNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        model.selectedAssetID = incoming.id

        try model.dismissSelectedFaceReviewAssets()

        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertNotNil(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
    }

    func testConfirmSelectedAssetsAsPersonRefreshesFaceSuggestions() throws {
        let (model, _, incoming, _, _) = try makeFaceSuggestionModel(named: "app-model-confirm-assets-refreshes-suggestions")
        model.refreshPeopleFaceSuggestions()
        XCTAssertNotNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        model.selectedAssetID = incoming.id

        try model.confirmSelectedAssetsAsPerson(named: "Ida", id: "person-ida")

        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertNotNil(model.peopleFaceSuggestions.first { $0.kind == .newPerson })
    }

    func testSelectingPeopleSidebarTargetRefreshesFaceSuggestions() throws {
        let (model, _, _, _, _) = try makeFaceSuggestionModel(named: "app-model-face-people-entry")
        XCTAssertEqual(model.peopleFaceSuggestions, [])

        try model.selectSidebarTarget(.people)

        XCTAssertEqual(model.peopleFaceSuggestions.count, 2)
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

    func testSourceAvailabilityFilterAppliesToOfflineOriginals() throws {
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

        // The sidebar "Sources" section is retired; the `source:` filter-bar
        // token is the sole remaining route to this filter, so exercise the
        // underlying model filter directly.
        model.selectedAssetSetID = nil
        model.availabilityFilter = .missing
        try model.reload()

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.availabilityFilter, .missing)
        XCTAssertEqual(model.assets.map(\.id), [firstMissing.id, secondMissing.id])
        XCTAssertEqual(model.totalAssetCount, 2)
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
        XCTAssertEqual(model.activityCenterPresentation.sources.map(\.availability), [.missing])

        let result = try model.reconnectSourceRoot(from: oldRoot, to: newRoot)

        XCTAssertEqual(result.reconnectedAssetCount, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [newOriginalURL])
        XCTAssertEqual(model.assets.map(\.availability), [.online])
        XCTAssertTrue(model.activityCenterPresentation.sources.isEmpty)
        XCTAssertEqual(model.statusMessage, "Reconnected 1 source")

        // The Folders tree is rebuilt from the reconnected asset's new path,
        // not the stale offline one.
        let reconnectedFolderSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Folders" })
        XCTAssertEqual(reconnectedFolderSection.rowTitles, ["Job"])
        XCTAssertEqual(reconnectedFolderSection.rows[0].countText, "1")
        XCTAssertEqual(reconnectedFolderSection.rows[0].target, .folder("\(newRoot.path)/Job/"))
    }

    func testReconnectSourceRootThrowsHelpfulErrorWhenNoCatalogAssetsMatchOldRoot() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect-no-match")
        let catalogRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let wrongOldRoot = directory.appendingPathComponent("WrongArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let originalURL = catalogRoot.appendingPathComponent("Job/frame.jpg")
        let remountedURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: remountedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("same original bytes".utf8).write(to: remountedURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-no-match"),
            originalURL: originalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: remountedURL),
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

        XCTAssertThrowsError(try model.reconnectSourceRoot(from: wrongOldRoot, to: newRoot)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "No catalog photos use WrongArchive. Check the old source root."
            )
        }
        XCTAssertNil(model.statusMessage)
        XCTAssertEqual(model.assets.map(\.originalURL), [originalURL])
    }

    func testReconnectSourceRootThrowsHelpfulErrorWhenMatchingFilesAreMissingUnderNewRoot() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect-missing-files")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
        let originalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let fingerprintSourceURL = directory.appendingPathComponent("fingerprint-source.jpg")
        try Data("same original bytes".utf8).write(to: fingerprintSourceURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-missing-files"),
            originalURL: originalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: fingerprintSourceURL),
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

        XCTAssertThrowsError(try model.reconnectSourceRoot(from: oldRoot, to: newRoot)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "No files were reconnected from MountedArchive. 1 catalog photo was found under OfflineArchive, but the matching file was missing under the new root."
            )
        }
        XCTAssertNil(model.statusMessage)
        XCTAssertEqual(model.assets.map(\.originalURL), [originalURL])
    }

    func testReconnectSourceRootThrowsHelpfulErrorWhenMatchingFilesHaveDifferentFingerprints() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-source-reconnect-fingerprint-mismatch")
        let oldRoot = directory.appendingPathComponent("OfflineArchive", isDirectory: true)
        let newRoot = directory.appendingPathComponent("MountedArchive", isDirectory: true)
        let newOriginalURL = newRoot.appendingPathComponent("Job/frame.jpg")
        try FileManager.default.createDirectory(
            at: newOriginalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("different original bytes".utf8).write(to: newOriginalURL)
        let fingerprintSourceURL = directory.appendingPathComponent("fingerprint-source.jpg")
        try Data("expected original bytes".utf8).write(to: fingerprintSourceURL)
        let oldOriginalURL = oldRoot.appendingPathComponent("Job/frame.jpg")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "source-reconnect-fingerprint-mismatch"),
            originalURL: oldOriginalURL,
            volumeIdentifier: "OfflineArchive",
            fingerprint: try fileFingerprint(for: fingerprintSourceURL),
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

        XCTAssertThrowsError(try model.reconnectSourceRoot(from: oldRoot, to: newRoot)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "No files were reconnected from MountedArchive. 1 file was found under the new root, but it did not match the catalog fingerprint."
            )
        }
        XCTAssertNil(model.statusMessage)
        XCTAssertEqual(model.assets.map(\.originalURL), [oldOriginalURL])
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

    func testSuggestedReconnectOldRootUsesCatalogSourceRoots() throws {
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
        XCTAssertEqual(recentWorkCollectionRows(model).map(\.title), [recent.detail, starred.title])
        XCTAssertEqual(recentWorkCollectionRows(model).map(\.target), [
            .workSession(recent.id),
            .workSession(starred.id)
        ])
        XCTAssertEqual(starredWorkCollectionRows(model).map(\.title), [starred.title])
        XCTAssertEqual(recentWorkCollectionRows(model).map(\.isSelectable), [true, true])
        XCTAssertEqual(starredWorkCollectionRows(model).map(\.isSelectable), [true])
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
        let recentRows = recentOnlyWorkRows(model)
        let starredRows = starredWorkCollectionRows(model)

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

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:old-starred-cull")
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
        XCTAssertEqual(starredWorkCollectionRows(model).map(\.title), [session.title])

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
        let recentRow = try XCTUnwrap(recentWorkCollectionRows(model).first)
        var action = try XCTUnwrap(model.sidebarContextActions(for: recentRow).first)

        XCTAssertEqual(action.kind, .toggleWorkSessionStarred(session.id))
        XCTAssertEqual(action.title, "Star Work")
        XCTAssertEqual(action.systemImage, "star")

        try model.performSidebarContextAction(action)

        XCTAssertEqual(try repository.session(id: session.id).starred, true)
        let starredRow = try XCTUnwrap(starredWorkCollectionRows(model).first)
        action = try XCTUnwrap(model.sidebarContextActions(for: starredRow).first)
        XCTAssertEqual(action.kind, .toggleWorkSessionStarred(session.id))
        XCTAssertEqual(action.title, "Remove Star")
        XCTAssertEqual(action.systemImage, "star.slash")
    }

    func testSelectingWorkSessionAppliesSessionQueryScope() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-select-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-input"),
            name: "Work Input",
            assetIDs: [keeper.id, reject.id]
        )
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "work-output"),
            name: "Work Output",
            assetIDs: [keeper.id]
        )
        try repository.upsert(inputSet)
        try repository.upsert(outputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "cull-session"),
            kind: .culling,
            intent: "Pick strongest frame",
            title: "Cull Session",
            detail: "Selected one keeper",
            status: .completed,
            inputSetIDs: [inputSet.id],
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
        let row = try XCTUnwrap(recentWorkCollectionRows(model).first)

        XCTAssertEqual(row.countText, "2")

        try model.selectSidebarRow(row)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:cull-session")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: cull-session", target: .workSession(session.id))
        ])
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, reject.id])
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testSearchWorkspaceExposesMatchingWorkHistoryRows() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-search-work-history")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "ceremony-cull-input"),
            name: "Ceremony Cull Input",
            assetIDs: [keeper.id, reject.id]
        )
        try repository.upsert(inputSet)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "ceremony-cull"),
            kind: .culling,
            intent: "Pick ceremony keepers",
            title: "Cull Ceremony",
            detail: "Reviewed ceremony candidates",
            status: .completed,
            inputSetIDs: [inputSet.id],
            outputSetIDs: [],
            completedUnitCount: 2,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let unrelated = WorkSession(
            id: WorkSessionID(rawValue: "portrait-import"),
            kind: .ingest,
            intent: "Import portraits",
            title: "Import Photos",
            detail: "Imported portraits",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 4,
            totalUnitCount: 4,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        try repository.save(session)
        try repository.save(unrelated)
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

        model.librarySearchText = "ceremony"
        try model.reload()

        XCTAssertEqual(model.workHistorySearchResults.map(\.id), [session.id.rawValue])
        XCTAssertEqual(model.workHistorySearchResults.first?.title, "Cull Ceremony")
        try model.selectSidebarTarget(.workSession(session.id))

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:ceremony-cull")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: ceremony-cull", target: .workSession(session.id))
        ])
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, reject.id])
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testActiveQueryReplacesRecentWorkSidebarRowsWithMatchedSessions() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-matched-work-sidebar")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        try repository.upsert([keeper])
        let ceremony = WorkSession(
            id: WorkSessionID(rawValue: "ceremony-cull"),
            kind: .culling,
            intent: "Pick ceremony keepers",
            title: "Cull Ceremony",
            detail: "Reviewed ceremony candidates",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 2,
            totalUnitCount: 2,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let unrelated = WorkSession(
            id: WorkSessionID(rawValue: "portrait-import"),
            kind: .ingest,
            intent: "Import portraits",
            title: "Import Portraits",
            detail: "Imported portraits",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 4,
            totalUnitCount: 4,
            failureCount: 0,
            createdAt: Date(timeIntervalSince1970: 11),
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        try repository.save(ceremony)
        try repository.save(unrelated)
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
        let defaultRows = recentWorkCollectionRows(model)
        XCTAssertEqual(
            Set(defaultRows.compactMap(workSessionTargetID)),
            [ceremony.id, unrelated.id]
        )

        model.librarySearchText = "ceremony"
        try model.applyLibraryFilters()

        let matchedRows = recentWorkCollectionRows(model)
        XCTAssertEqual(matchedRows.compactMap(workSessionTargetID), [ceremony.id])
        XCTAssertTrue(matchedRows.allSatisfy { $0.id.hasPrefix("work-matched-") })

        model.librarySearchText = ""
        try model.applyLibraryFilters()

        XCTAssertEqual(
            Set(recentWorkCollectionRows(model).compactMap(workSessionTargetID)),
            [ceremony.id, unrelated.id]
        )
    }

    private func workSessionTargetID(_ row: SidebarRow) -> WorkSessionID? {
        if case .workSession(let id) = row.target {
            return id
        }
        return nil
    }

    func testSelectingCullingWorkSessionReopensLoupeView() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-select-culling-work-session")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let keeper = makeAsset(id: "keeper", path: "/Photos/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/reject.jpg", rating: 1)
        try repository.upsert([keeper, reject])
        let inputSet = AssetSet(
            id: AssetSetID(rawValue: "cull-input"),
            name: "Cull Input",
            membership: .snapshot([keeper.id])
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
        let row = try XCTUnwrap(recentWorkCollectionRows(model).first)

        XCTAssertEqual(row.countText, "1")

        try model.selectSidebarRow(row)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:cull-session")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: cull-session", target: .workSession(session.id))
        ])
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
        XCTAssertEqual(starredCollectionRows(model).map(\.title), ["Ceremony Picks"])
        XCTAssertEqual(sidebarRowCount("Ceremony Picks", in: "Collections", of: model), "1")
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

        XCTAssertEqual(model.assets.count, 130)
        XCTAssertEqual(model.totalAssetCount, 130)

        let savedSet = try model.saveCurrentAssetScopeSnapshot(named: " Ceremony Snapshot ", starred: true)

        XCTAssertEqual(savedSet.name, "Ceremony Snapshot")
        XCTAssertEqual(savedSet.membership, .snapshot(keepers.map(\.id)))
        XCTAssertEqual(try repository.assetSet(id: savedSet.id), savedSet)
        XCTAssertEqual(model.selectedAssetSetID, savedSet.id)
        XCTAssertEqual(model.totalAssetCount, 130)
        XCTAssertEqual(starredCollectionRows(model).map(\.title), ["Ceremony Snapshot"])
        XCTAssertEqual(sidebarRowCount("Ceremony Snapshot", in: "Collections", of: model), "130")

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

    func testRemovingActiveLibraryFilterRowClearsExplicitFilterAndReloads() throws {
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedPick = makeAsset(
            id: "lower-rated-pick",
            path: "/Photos/Wedding/ceremony-lower-rated-pick.jpg",
            rating: 3,
            flag: .pick
        )
        let rejected = makeAsset(
            id: "rejected",
            path: "/Photos/Wedding/ceremony-rejected.jpg",
            rating: 5,
            flag: .reject
        )
        let travel = makeAsset(
            id: "travel",
            path: "/Photos/Travel/mountain.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "remove-explicit-active-filter",
            assets: [keeper, lowerRatedPick, rejected, travel]
        )

        model.librarySearchText = "ceremony"
        model.minimumRatingFilter = 5
        model.flagFilter = .pick
        try model.applyLibraryFilters()
        let ratingRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Rating >= 5" })

        try model.removeActiveLibraryFilter(ratingRow)

        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.librarySearchText, "ceremony")
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertEqual(model.activeLibraryFilterChips, ["Search: ceremony", "Pick"])
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, lowerRatedPick.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testRemovingParsedSearchChipRewritesSearchTextAndReloads() throws {
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedPick = makeAsset(
            id: "lower-rated-pick",
            path: "/Photos/Wedding/ceremony-lower-rated-pick.jpg",
            rating: 3,
            flag: .pick
        )
        let rejected = makeAsset(
            id: "rejected",
            path: "/Photos/Wedding/ceremony-rejected.jpg",
            rating: 5,
            flag: .reject
        )
        let travel = makeAsset(
            id: "travel",
            path: "/Photos/Travel/mountain.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "remove-parsed-active-filter",
            assets: [keeper, lowerRatedPick, rejected, travel]
        )

        model.librarySearchText = "ceremony picks 5 stars"
        try model.applyLibraryFilters()
        let pickRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Pick" })

        try model.removeActiveLibraryFilter(pickRow)

        XCTAssertEqual(model.librarySearchText, "ceremony rating:5")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Search: ceremony", "Rating >= 5"])
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, rejected.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testShowPersonPhotosScopesLibraryGridToConfirmedPerson() throws {
        let annaRated = makeAsset(id: "anna-rated", path: "/Photos/Wedding/anna-rated.jpg", rating: 5)
        let annaUnrated = makeAsset(id: "anna-unrated", path: "/Photos/Wedding/anna-unrated.jpg", rating: 0)
        let unassigned = makeAsset(id: "unassigned", path: "/Photos/Wedding/unassigned.jpg", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "show-person-photos",
            assets: [annaRated, annaUnrated, unassigned],
            configureRepository: { repository in
                try repository.upsertPerson(id: "person-anna", name: "Anna Lee")
                try repository.assignAssets([annaRated.id, annaUnrated.id], toPersonID: "person-anna")
            }
        )
        model.selectedView = .people
        model.minimumRatingFilter = 3
        try model.applyLibraryFilters()

        try model.showPersonPhotos(named: "Anna Lee")

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.librarySearchText, "person:\"Anna Lee\"")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Person: Anna Lee"])
        XCTAssertEqual(model.assets.map(\.id), [annaRated.id, annaUnrated.id])
        XCTAssertEqual(model.totalAssetCount, 2)

        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        XCTAssertEqual(model.activeLibraryFilterChips, ["Person: Anna Lee", "Rating >= 4"])
        XCTAssertEqual(model.assets.map(\.id), [annaRated.id])
        XCTAssertEqual(model.totalAssetCount, 1)
    }

    func testRemovingPersonChipRewritesSearchTextAndReloads() throws {
        let both = makeAsset(id: "both", path: "/Photos/Wedding/both.jpg", rating: 0)
        let annaOnly = makeAsset(id: "anna-only", path: "/Photos/Wedding/anna-only.jpg", rating: 0)
        let unassigned = makeAsset(id: "unassigned", path: "/Photos/Wedding/unassigned.jpg", rating: 0)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "remove-person-chip",
            assets: [both, annaOnly, unassigned],
            configureRepository: { repository in
                try repository.upsertPerson(id: "person-anna", name: "Anna Lee")
                try repository.upsertPerson(id: "person-ben", name: "Ben")
                try repository.assignAssets([both.id, annaOnly.id], toPersonID: "person-anna")
                try repository.assignAssets([both.id], toPersonID: "person-ben")
            }
        )

        model.librarySearchText = "person:\"Anna Lee\" person:Ben"
        try model.applyLibraryFilters()

        XCTAssertEqual(model.activeLibraryFilterChips, ["Person: Anna Lee", "Person: Ben"])
        XCTAssertEqual(model.assets.map(\.id), [both.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        let benRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Person: Ben" })
        try model.removeActiveLibraryFilter(benRow)

        XCTAssertEqual(model.librarySearchText, "person:\"Anna Lee\"")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Person: Anna Lee"])
        XCTAssertEqual(model.assets.map(\.id), [both.id, annaOnly.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testRemovingPlainSearchFallbackRowClearsResidualTextButKeepsParsedFilters() throws {
        let keeper = makeAsset(
            id: "keeper",
            path: "/Photos/Wedding/ceremony-keeper.jpg",
            rating: 5,
            flag: .pick
        )
        let travel = makeAsset(
            id: "travel",
            path: "/Photos/Travel/mountain.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "remove-plain-search-fallback-row",
            assets: [keeper, travel]
        )

        model.librarySearchText = "ceremony picks"
        try model.applyLibraryFilters()
        let fallbackRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.isPlainSearchFallback })
        XCTAssertEqual(fallbackRow.title, "Search: ceremony")
        // The chip explains what the leftover text does in user language,
        // not "Plain search fallback" (persona-8).
        XCTAssertEqual(fallbackRow.subtitle, "Not a filter — matching file names and photo text")
        XCTAssertTrue(model.activeLibraryFilterRows.filter { !$0.isPlainSearchFallback }.allSatisfy { $0.subtitle == nil })
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])

        try model.removeActiveLibraryFilter(fallbackRow)

        XCTAssertEqual(model.librarySearchText, "pick")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Pick"])
        XCTAssertFalse(model.activeLibraryFilterRows.contains { $0.isPlainSearchFallback })
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, travel.id])
    }

    func testRemovingParsedSearchFilterQuotesRemainingFieldValuesWithSpaces() throws {
        let frame = makeAsset(
            id: "quoted-remove-frame",
            path: "/Volumes/NAS/Wedding 2026/quiet-frame.jpg",
            rating: 5,
            keywords: ["New York"]
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "remove-quoted-search-filter",
            assets: [frame]
        )

        model.librarySearchText = "quiet folder:\"/Volumes/NAS/Wedding 2026\" keyword:\"New York\""
        try model.applyLibraryFilters()
        let keywordRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Keyword: New York" })

        try model.removeActiveLibraryFilter(keywordRow)

        XCTAssertEqual(model.librarySearchText, "quiet folder:\"/Volumes/NAS/Wedding 2026\"")
        XCTAssertEqual(model.activeLibraryFilterChips, ["Search: quiet", "Folder: Wedding 2026"])
    }

    func testRemovingSavedSetFilterRowClearsSelectedSetScope() throws {
        let ceremony = makeAsset(
            id: "ceremony",
            path: "/Photos/Wedding/ceremony.jpg",
            rating: 5
        )
        let travel = makeAsset(
            id: "travel",
            path: "/Photos/Travel/mountain.jpg",
            rating: 5
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "remove-saved-set-active-filter",
            assets: [ceremony, travel]
        )
        let savedSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "ceremony-set"),
            name: "Ceremony",
            query: SetQuery(predicates: [.text("ceremony")])
        )
        try repository.upsert(savedSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: savedSet.id)
        let setRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Ceremony" })

        try model.removeActiveLibraryFilter(setRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.activeLibraryFilterChips.isEmpty)
        XCTAssertEqual(model.assets.map(\.id), [ceremony.id, travel.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testRemovingSelectedDynamicSetRuleDetachesSetAndPreservesRemainingScope() throws {
        let ceremonyPick = makeAsset(
            id: "ceremony-pick",
            path: "/Photos/Wedding/ceremony-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let lowerRatedCeremonyPick = makeAsset(
            id: "lower-rated-ceremony-pick",
            path: "/Photos/Wedding/ceremony-lower-rated-pick.jpg",
            rating: 3,
            flag: .pick
        )
        let ceremonyReject = makeAsset(
            id: "ceremony-reject",
            path: "/Photos/Wedding/ceremony-reject.jpg",
            rating: 5,
            flag: .reject
        )
        let travelPick = makeAsset(
            id: "travel-pick",
            path: "/Photos/Travel/mountain.jpg",
            rating: 5,
            flag: .pick
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "remove-dynamic-set-rule-active-filter",
            assets: [ceremonyPick, lowerRatedCeremonyPick, ceremonyReject, travelPick]
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
        let ratingRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Rating >= 4" })

        try model.removeActiveLibraryFilter(ratingRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertEqual(model.activeLibraryFilterChips, ["Search: ceremony", "Pick"])
        XCTAssertEqual(model.assets.map(\.id), [ceremonyPick.id, lowerRatedCeremonyPick.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testRemovingSelectedDynamicSetRulePreservesRemainingLikelyIssueScope() throws {
        let blurryPick = makeAsset(
            id: "blurry-pick",
            path: "/Photos/Wedding/blurry-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let sharpPick = makeAsset(
            id: "sharp-pick",
            path: "/Photos/Wedding/sharp-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let blurryReject = makeAsset(
            id: "blurry-reject",
            path: "/Photos/Wedding/blurry-reject.jpg",
            rating: 5,
            flag: .reject
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "remove-dynamic-set-likely-issue-rule",
            assets: [blurryPick, sharpPick, blurryReject],
            configureRepository: { repository in
                try repository.recordEvaluationSignals([
                    EvaluationSignal(assetID: blurryPick.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance),
                    EvaluationSignal(assetID: blurryReject.id, kind: .focus, value: .score(0.33), confidence: 0.86, provenance: provenance)
                ])
            }
        )
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "blurry-picks"),
            name: "Blurry Picks",
            query: SetQuery(predicates: [.likelyIssue, .flag(.pick)])
        )
        try repository.upsert(dynamicSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: dynamicSet.id)
        let pickRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Pick" })

        try model.removeActiveLibraryFilter(pickRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.activeLibraryFilterChips, ["Likely Issues"])
        XCTAssertEqual(model.assets.map(\.id), [blurryPick.id, blurryReject.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testRemovingDetachedDynamicSetRuleClearsRemainingStructuredScope() throws {
        let blurryPick = makeAsset(
            id: "remove-detached-blurry-pick",
            path: "/Photos/Wedding/remove-detached-blurry-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let sharpPick = makeAsset(
            id: "remove-detached-sharp-pick",
            path: "/Photos/Wedding/remove-detached-sharp-pick.jpg",
            rating: 5,
            flag: .pick
        )
        let blurryReject = makeAsset(
            id: "remove-detached-blurry-reject",
            path: "/Photos/Wedding/remove-detached-blurry-reject.jpg",
            rating: 5,
            flag: .reject
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "remove-detached-dynamic-set-rule",
            assets: [blurryPick, sharpPick, blurryReject],
            configureRepository: { repository in
                try repository.recordEvaluationSignals([
                    EvaluationSignal(assetID: blurryPick.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance),
                    EvaluationSignal(assetID: blurryReject.id, kind: .focus, value: .score(0.33), confidence: 0.86, provenance: provenance)
                ])
            }
        )
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "detached-blurry-picks"),
            name: "Detached Blurry Picks",
            query: SetQuery(predicates: [.likelyIssue, .flag(.pick)])
        )
        try repository.upsert(dynamicSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: dynamicSet.id)
        let pickRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Pick" })
        try model.removeActiveLibraryFilter(pickRow)
        let likelyIssueRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Likely Issues" })

        try model.removeActiveLibraryFilter(likelyIssueRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertTrue(model.activeLibraryFilterChips.isEmpty)
        XCTAssertEqual(model.assets.map(\.id), [blurryPick.id, sharpPick.id, blurryReject.id])
        XCTAssertEqual(model.totalAssetCount, 3)
    }

    func testRemovingSelectedDynamicSetRulePreservesRemainingCameraScopeWithSpaces() throws {
        let metadataProvenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        let sonyPick = makeAsset(
            id: "sony-pick",
            path: "/Photos/Wedding/sony-pick.jpg",
            rating: 5,
            flag: .pick,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                cameraMake: "Sony",
                cameraModel: "Alpha 7R V",
                provenance: metadataProvenance
            )
        )
        let canonPick = makeAsset(
            id: "canon-pick",
            path: "/Photos/Wedding/canon-pick.jpg",
            rating: 5,
            flag: .pick,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                cameraMake: "Canon",
                cameraModel: "EOS R5",
                provenance: metadataProvenance
            )
        )
        let sonyReject = makeAsset(
            id: "sony-reject",
            path: "/Photos/Wedding/sony-reject.jpg",
            rating: 5,
            flag: .reject,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                cameraMake: "Sony",
                cameraModel: "Alpha 7R V",
                provenance: metadataProvenance
            )
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "remove-dynamic-set-camera-rule",
            assets: [sonyPick, canonPick, sonyReject]
        )
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "sony-picks"),
            name: "Sony Picks",
            query: SetQuery(predicates: [.camera("Sony Alpha"), .flag(.pick)])
        )
        try repository.upsert(dynamicSet)
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: dynamicSet.id)
        let pickRow = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "Pick" })

        try model.removeActiveLibraryFilter(pickRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.activeLibraryFilterChips, ["Camera: Sony Alpha"])
        XCTAssertEqual(model.assets.map(\.id), [sonyPick.id, sonyReject.id])
        XCTAssertEqual(model.totalAssetCount, 2)
    }

    func testLikelyIssuesFilterNamesSavedSearchScope() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        model.likelyIssuesFilter = true

        XCTAssertEqual(model.activeLibraryFilterChips, ["Likely Issues"])
        XCTAssertEqual(model.suggestedSavedSearchName, "Likely Issues")
    }

    func testPotentialPicksReviewQueueFiltersToLikelyKeepersWithoutWritingFlags() throws {
        let strong = makeAsset(id: "potential-strong", path: "/Photos/Job/strong.cr2", rating: 0)
        let weak = makeAsset(id: "potential-weak", path: "/Photos/Job/weak.cr2", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "potential-picks-queue",
            assets: [strong, weak]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: strong.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: weak.id, kind: .focus, value: .score(0.3), confidence: 0.9, provenance: provenance)
        ])

        try model.selectSidebarTarget(.reviewQueue(.potentialPicks))

        XCTAssertEqual(model.assets.map(\.id), [strong.id])
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertTrue(model.potentialPicksFilter)
        XCTAssertNil(try repository.asset(id: strong.id).metadata.flag)
        XCTAssertEqual(model.suggestedSavedSearchName, "Potential Picks")
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

    func testApplyingSmartCollectionRuleTextUsesReviewQueuePhrases() throws {
        let faceIssue = makeAsset(
            id: "typed-rule-face-issue",
            path: "/Photos/Wedding/typed-rule-face-issue.jpg",
            rating: 0,
            keywords: ["tagged"]
        )
        let faceOnly = makeAsset(
            id: "typed-rule-face-only",
            path: "/Photos/Wedding/typed-rule-face-only.jpg",
            rating: 0,
            keywords: ["tagged"]
        )
        let issueOnly = makeAsset(
            id: "typed-rule-issue-only",
            path: "/Photos/Wedding/typed-rule-issue-only.jpg",
            rating: 0,
            keywords: ["tagged"]
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "smart-collection-review-queue-phrases",
            assets: [faceIssue, faceOnly, issueOnly]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: faceIssue.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: faceIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance),
            EvaluationSignal(assetID: faceOnly.id, kind: .faceCount, value: .count(1), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: issueOnly.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance)
        ])

        try model.applySmartCollectionRuleText("faces found likely issues")

        XCTAssertEqual(model.librarySearchText, "faces found likely issues")
        XCTAssertEqual(model.assets.map(\.id), [faceIssue.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Faces Found", "Likely Issues"])
        let savedSet = try model.saveCurrentLibraryQuery(named: "Face Issues")
        XCTAssertEqual(savedSet.membership, .dynamic(SetQuery(predicates: [
            .evaluationKind(.faceCount),
            .likelyIssue
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

    func testApplyingFocusSignalRulePresetNarrowsCurrentQuery() throws {
        let focused = makeAsset(id: "focus-signal", path: "/Photos/Job/focus-signal.jpg", rating: 0)
        let objectOnly = makeAsset(id: "object-signal", path: "/Photos/Job/object-signal.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "smart-collection-focus-signal-preset",
            assets: [focused, objectOnly]
        )
        let provenance = ProviderProvenance(provider: "local-metrics", model: "ImageMetrics", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: focused.id, kind: .focus, value: .score(0.82), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: objectOnly.id, kind: .object, value: .label("camera"), confidence: 0.8, provenance: provenance)
        ])

        try model.applySmartCollectionRulePreset(.focusSignals)

        XCTAssertEqual(model.evaluationKindFilter, .focus)
        XCTAssertEqual(model.assets.map(\.id), [focused.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Signal: Focus"])
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
        XCTAssertEqual(starredCollectionRows(model).map(\.title), ["Keeper"])
        XCTAssertEqual(sidebarRowCount("Keeper", in: "Collections", of: model), "1")
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

    // persona-2 item 2: File ▸ New Set from Selection… (and the Saved Sets
    // sidebar "+") bump this token the same way Move Rejects… does, so
    // LibraryGridView's onChange can open the existing manual-set popover
    // without FileCommands needing direct access to that view's @State.
    func testRequestNewSetFromSelectionBumpsToken() throws {
        let (model, _, _) = try makeModelWithCatalogAsset(named: "new-set-from-selection-token")

        XCTAssertEqual(model.newSetFromSelectionRequestToken, 0)

        model.requestNewSetFromSelection()

        XCTAssertEqual(model.newSetFromSelectionRequestToken, 1)
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
        let inputSetID = try XCTUnwrap(session.inputSetIDs.first)
        let workInputSet = try repository.assetSet(id: inputSetID)
        XCTAssertTrue(inputSetID.rawValue.hasPrefix("work-input-"))
        XCTAssertEqual(workInputSet.name, "Ceremony Cull Input")
        XCTAssertEqual(workInputSet.membership, .snapshot([keeper.id]))
        XCTAssertEqual(session.totalUnitCount, 1)
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.recentWork.first?.id, session.id.rawValue)

        // Cull's sidebar is empty (Task 7); switch to Library to read the
        // Collections row before returning to Cull via the row's own target.
        model.selectedView = .grid
        XCTAssertEqual(recentWorkCollectionRows(model).first?.title, "Ceremony Cull")
        let row = try XCTUnwrap(recentWorkCollectionRows(model).first)

        try model.clearLibraryFilters()
        try model.selectSidebarRow(row)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(session.id.rawValue)")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(session.id.rawValue)", target: .workSession(session.id))
        ])
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
        XCTAssertEqual(inputSet.membership, .snapshot([keeper.id]))
        XCTAssertEqual(model.selectedAssetSetID, inputSetID)
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(model.sidebarSections.contains { section in
            section.title == "Saved Sets" && section.rowTitles.contains("Wedding Cull Input")
        })

        try model.clearLibraryFilters()
        // Cull's sidebar is empty (Task 7); switch to Library to read the
        // Collections row before returning to Cull via the row's own target.
        model.selectedView = .grid
        let row = try XCTUnwrap(recentWorkCollectionRows(model).first)
        try model.selectSidebarRow(row)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(session.id.rawValue)")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(session.id.rawValue)", target: .workSession(session.id))
        ])
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
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(session.id.rawValue)")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(session.id.rawValue)", target: .workSession(session.id))
        ])
        XCTAssertEqual(model.assets.map(\.id), [keeper.id, reject.id])
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
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(pickedSession.id.rawValue)")
        XCTAssertEqual(model.assets.map(\.id), [keeper.id])

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
        XCTAssertNil(reviewQueueCount("Picks", in: model))
        XCTAssertNil(reviewQueueCount("Rejects", in: model))
        XCTAssertNil(reviewQueueCount("5 Stars", in: model))
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
    func testBackgroundImportShowsImportedAssetInFullCatalog() async throws {
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
        XCTAssertEqual(model.assets.count, 121)
        XCTAssertEqual(model.libraryCountText, "121 photos")
        // The whole catalog stays loaded, so the pre-existing assets remain in
        // view alongside the freshly imported one.
        XCTAssertEqual(model.assets.first?.id, AssetID(rawValue: "existing-0"))
        XCTAssertEqual(model.assets.last?.id, importedAsset.id)
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
        XCTAssertEqual(model.activityCenterPresentation.sources.map(\.availability), [.missing])

        try model.refreshVisibleAssetAvailability()

        XCTAssertEqual(model.assets.map(\.availability), [.online])
        XCTAssertTrue(model.activityCenterPresentation.sources.isEmpty)
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

    func testLoupeZoomPreviewURLPrefersOriginalLevel() throws {
        let (model, previewCache, asset) = try makeModelWithPreviewCache(named: "loupe-zoom-url")
        let largeURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large))
        let originalURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .original))
        try writePreviewPlaceholder(to: largeURL)

        XCTAssertEqual(model.loupeZoomPreviewURL(for: asset.id), largeURL)

        try writePreviewPlaceholder(to: originalURL)

        XCTAssertEqual(model.loupeZoomPreviewURL(for: asset.id), originalURL)
    }

    func testRequestLoupeFullResolutionPreviewDispatchesOriginalRender() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let asset = makeAsset(
            id: "full-res",
            path: "/Photos/full-res.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-request",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try result.model.requestLoupeFullResolutionPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .original)])
    }

    func testRequestLoupeFullResolutionPreviewRendersWhenAssetPixelSizeUnknown() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let asset = makeAsset(id: "full-res-unknown", path: "/Photos/full-res-unknown.jpg", rating: 0)
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-unknown",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try result.model.requestLoupeFullResolutionPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [.generatePreview(assetID: asset.id, level: .original)])
    }

    func testRequestLoupeFullResolutionPreviewSkipsWhenCachedPreviewCoversAssetPixels() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let asset = makeAsset(
            id: "full-res-covered",
            path: "/Photos/full-res-covered.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 3000, pixelHeight: 2000)
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-covered",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try result.model.requestLoupeFullResolutionPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [])
    }

    func testRequestLoupeFullResolutionPreviewSkipsWhenOriginalLevelCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let asset = makeAsset(
            id: "full-res-cached",
            path: "/Photos/full-res-cached.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-cached",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .original)))

        try result.model.requestLoupeFullResolutionPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [])
    }

    func testRequestLoupeFullResolutionPreviewSkipsWhenOriginalUnavailable() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let asset = makeAsset(
            id: "full-res-offline",
            path: "/Volumes/Archive/full-res-offline.jpg",
            rating: 0,
            availability: .offline,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-offline",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))

        try result.model.requestLoupeFullResolutionPreview(assetID: asset.id)

        XCTAssertEqual(try transport.commands(), [])
    }

    func testLoupeZoomFullResolutionStatusReportsSatisfiedLoadingAndUnavailable() throws {
        let originalCached = makeAsset(
            id: "status-original",
            path: "/Photos/status-original.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let coveredByLarge = makeAsset(
            id: "status-covered",
            path: "/Photos/status-covered.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 3000, pixelHeight: 2000)
        )
        let needsOriginal = makeAsset(
            id: "status-needs-original",
            path: "/Photos/status-needs-original.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let offline = makeAsset(
            id: "status-offline",
            path: "/Volumes/Archive/status-offline.jpg",
            rating: 0,
            availability: .offline,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-status",
            assets: [originalCached, coveredByLarge, needsOriginal, offline]
        )
        for asset in [originalCached, coveredByLarge, needsOriginal, offline] {
            try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))
        }
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: originalCached.id, level: .original)))

        XCTAssertEqual(result.model.loupeZoomFullResolutionStatus(for: originalCached.id), .satisfied)
        XCTAssertEqual(result.model.loupeZoomFullResolutionStatus(for: coveredByLarge.id), .satisfied)
        XCTAssertEqual(result.model.loupeZoomFullResolutionStatus(for: needsOriginal.id), .loading)
        XCTAssertEqual(result.model.loupeZoomFullResolutionStatus(for: offline.id), .unavailable)
    }

    @MainActor
    func testLoupeZoomFullResolutionStatusReportsUnavailableAfterRenderFailure() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let asset = makeAsset(
            id: "status-failed",
            path: "/Photos/status-failed.jpg",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(pixelWidth: 8000, pixelHeight: 5000)
        )
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "loupe-full-res-failed",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: result.previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .large)))
        try result.model.requestLoupeFullResolutionPreview(assetID: asset.id)
        let itemID = try XCTUnwrap(result.model.backgroundWorkQueue.runningItems.first?.id)

        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "could not render original"
        )))

        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: result.model)
        XCTAssertEqual(result.model.loupeZoomFullResolutionStatus(for: asset.id), .unavailable)
    }

    func testRequestVisibleLoupePreviewPrefetchesNeighborLargePreviews() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let fixture = try makeLoupeCullingFixture(
            named: "loupe-neighbor-prefetch",
            assetCount: 4,
            workerSupervisor: supervisor
        )

        try fixture.model.requestVisibleLoupePreview(assetID: fixture.assets[1].id)

        // The transport only sees one command at a time; the queue carries the
        // visible frame's previews first, then exactly one neighbor each way.
        XCTAssertEqual(previewGenerationItemIDs(in: fixture.model), [
            "preview-\(fixture.assets[1].id.rawValue)-medium",
            "preview-\(fixture.assets[1].id.rawValue)-large",
            "preview-\(fixture.assets[2].id.rawValue)-large",
            "preview-\(fixture.assets[0].id.rawValue)-large"
        ])
        XCTAssertEqual(try transport.commands(), [
            .generatePreview(assetID: fixture.assets[1].id, level: .medium)
        ])
    }

    func testRequestVisibleLoupePreviewPrefetchesNeighborsWhenVisiblePreviewIsCached() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let fixture = try makeLoupeCullingFixture(
            named: "loupe-neighbor-prefetch-cached",
            assetCount: 3,
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(
            to: fixture.previewCache.url(for: PreviewCacheKey(assetID: fixture.assets[1].id, level: .large))
        )

        try fixture.model.requestVisibleLoupePreview(assetID: fixture.assets[1].id)

        XCTAssertEqual(previewGenerationItemIDs(in: fixture.model), [
            "preview-\(fixture.assets[2].id.rawValue)-large",
            "preview-\(fixture.assets[0].id.rawValue)-large"
        ])
    }

    func testRequestVisibleLoupePreviewSkipsUnavailableNeighborPrefetch() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8),
            transport: transport
        )
        let fixture = try makeLoupeCullingFixture(
            named: "loupe-neighbor-prefetch-offline",
            assetCount: 3,
            workerSupervisor: supervisor,
            availabilityForIndex: { index in index == 2 ? .offline : .online }
        )
        try writePreviewPlaceholder(
            to: fixture.previewCache.url(for: PreviewCacheKey(assetID: fixture.assets[1].id, level: .large))
        )

        try fixture.model.requestVisibleLoupePreview(assetID: fixture.assets[1].id)

        XCTAssertEqual(previewGenerationItemIDs(in: fixture.model), [
            "preview-\(fixture.assets[0].id.rawValue)-large"
        ])
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

    @MainActor
    func testRequestEvaluationCanRetryFailedProviderWork() async throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "request-evaluation-retry-failed",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        let itemID = WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-image-metrics")

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.failed(
            itemID: itemID,
            message: "provider failed"
        )))
        try await waitForBackgroundWorkStatus(.failed, itemID: itemID, in: model)

        try model.requestEvaluation(assetID: asset.id, provider: "local-image-metrics")

        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: asset.id, provider: "local-image-metrics"),
            .runEvaluation(assetID: asset.id, provider: "local-image-metrics")
        ])
        XCTAssertEqual(model.backgroundWorkQueue.item(id: itemID)?.status, .running)
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

    func testSelectedProviderFailuresExposeProviderMessageAndRetryFailedProvider() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "selected-provider-failure", path: "/Photos/selected-provider-failure.jpg", rating: 0, keywords: ["tagged"])
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "selected-provider-failure",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        try repository.recordEvaluationFailure(assetID: asset.id, provider: "local-http-model", message: "model timed out")

        let failure = try XCTUnwrap(model.selectedProviderFailures.first)
        XCTAssertEqual(failure.assetID, asset.id)
        XCTAssertEqual(failure.provider, "local-http-model")
        XCTAssertEqual(failure.message, "model timed out")

        try model.retrySelectedProviderFailure(provider: "local-http-model")

        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: asset.id, provider: "local-http-model")
        ])
    }

    func testSelectedProviderFailureRetryRequiresMatchingFailureCachedPreviewAndInactiveWork() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "provider-failure-retry-state", path: "/Photos/provider-failure-retry-state.jpg", rating: 0, keywords: ["tagged"])
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "provider-failure-retry-state",
            assets: [asset],
            workerSupervisor: supervisor
        )
        try repository.recordEvaluationFailure(assetID: asset.id, provider: "local-http-model", message: "model timed out")

        XCTAssertFalse(model.canRetrySelectedProviderFailure(provider: "local-http-model"))

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        XCTAssertTrue(model.canRetrySelectedProviderFailure(provider: "local-http-model"))
        XCTAssertFalse(model.canRetrySelectedProviderFailure(provider: "apple-vision"))

        try model.retrySelectedProviderFailure(provider: "local-http-model")

        XCTAssertFalse(model.canRetrySelectedProviderFailure(provider: "local-http-model"))
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

    func testRequestCurrentScopeAssetEvaluationsDispatchesCachedAssetsAcrossWholeScope() throws {
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

    func testRequestPeopleFaceScanQueuesAppleVisionForCurrentScope() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let matchingAssets = (0..<121).map { index in
            makeAsset(
                id: "people-current-scope-\(index)",
                path: "/Photos/People/people-current-scope-\(index).jpg",
                rating: 0,
                colorLabel: .green
            )
        }
        let outsideAsset = makeAsset(
            id: "people-current-scope-outside",
            path: "/Photos/People/outside.jpg",
            rating: 0,
            colorLabel: .red
        )
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "people-current-scope-scan",
            assets: matchingAssets + [outsideAsset],
            workerSupervisor: supervisor
        )
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: matchingAssets[0].id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: matchingAssets[120].id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: outsideAsset.id, level: .grid)))

        XCTAssertTrue(model.canRequestPeopleFaceScan)

        try model.requestPeopleFaceScan()

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(matchingAssets[0].id.rawValue)-apple-vision"),
            WorkSessionID(rawValue: "evaluation-\(matchingAssets[120].id.rawValue)-apple-vision")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: matchingAssets[0].id, provider: "apple-vision")
        ])
    }

    func testRequestCurrentScopeAssetEvaluationsQueuesOnlyBoundedCachedBatch() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let expectedBatchSize = 40
        let assets = (0..<(expectedBatchSize + 2)).map { index in
            makeAsset(
                id: "current-scope-evaluation-batch-\(index)",
                path: "/Photos/current-scope-evaluation-batch-\(index).jpg",
                rating: 0
            )
        }
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "current-scope-evaluation-batch",
            assets: assets,
            workerSupervisor: supervisor
        )
        for asset in assets {
            try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        }

        try model.requestCurrentScopeAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.count, expectedBatchSize)
        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), assets.prefix(expectedBatchSize).map { asset in
            WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-local-image-metrics")
        })
        XCTAssertEqual(model.statusMessage, "Queued local reads for 40 photos; 2 cached photos remain")
    }

    func testRequestLatestImportAssetEvaluationsDispatchesOnlyCachedImportedAssets() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let importedCached = makeAsset(id: "latest-import-cached", size: 1)
        let importedUncached = makeAsset(id: "latest-import-uncached", size: 2)
        let outsideCached = makeAsset(id: "outside-latest-import", size: 3)
        let (model, _, previewCache) = try makeModelWithCompletedImportSession(
            named: "latest-import-evaluation",
            assets: [importedCached, importedUncached, outsideCached],
            outputAssetIDs: [importedCached.id, importedUncached.id],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: importedCached.id, level: .grid)))
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: outsideCached.id, level: .grid)))

        XCTAssertTrue(model.canRequestLatestImportAssetEvaluations)

        try model.requestLatestImportAssetEvaluations(providers: ["local-image-metrics"])

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "evaluation-\(importedCached.id.rawValue)-local-image-metrics")
        ])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: importedCached.id, provider: "local-image-metrics")
        ])
    }

    func testCanRequestLatestImportAssetEvaluationsRequiresWorkerAndCachedImportedPreview() throws {
        let imported = makeAsset(id: "latest-import-gate-imported", size: 1)
        let outsideCached = makeAsset(id: "latest-import-gate-outside", size: 2)
        let (noWorkerModel, _, noWorkerPreviewCache) = try makeModelWithCompletedImportSession(
            named: "latest-import-evaluation-no-worker",
            assets: [imported],
            outputAssetIDs: [imported.id]
        )
        try writePreviewPlaceholder(to: noWorkerPreviewCache.url(for: PreviewCacheKey(assetID: imported.id, level: .grid)))
        XCTAssertFalse(noWorkerModel.canRequestLatestImportAssetEvaluations)

        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: transport
        )
        let (model, _, previewCache) = try makeModelWithCompletedImportSession(
            named: "latest-import-evaluation-only-outside-preview",
            assets: [imported, outsideCached],
            outputAssetIDs: [imported.id],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: outsideCached.id, level: .grid)))

        XCTAssertFalse(model.canRequestLatestImportAssetEvaluations)
    }

    func testLatestImportFaceReviewCountIgnoresFacesOutsideLatestImport() throws {
        let importedFace = makeAsset(id: "latest-import-face", size: 1)
        let importedNoFace = makeAsset(id: "latest-import-no-face", size: 2)
        let olderFace = makeAsset(id: "older-face-signal", size: 2)
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "latest-import-face-count",
            assets: [importedFace, importedNoFace, olderFace],
            outputAssetIDs: [importedFace.id, importedNoFace.id]
        )
        try repository.recordEvaluationSignals([
            EvaluationSignal(
                assetID: importedFace.id,
                kind: .faceCount,
                value: .count(1),
                confidence: 0.9,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: olderFace.id,
                kind: .faceCount,
                value: .count(1),
                confidence: 0.9,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            )
        ])

        XCTAssertEqual(model.latestImportFaceReviewAssetCount, 1)
    }

    func testLatestImportFlaggedReviewCountIsScopedToImportOutputSet() throws {
        let importedIssue = makeAsset(id: "latest-import-likely-issue", size: 1)
        let importedClean = makeAsset(id: "latest-import-clean", size: 2)
        let outsideIssue = makeAsset(id: "outside-latest-import-issue", size: 3)
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "latest-import-flagged-review-count",
            assets: [importedIssue, importedClean, outsideIssue],
            outputAssetIDs: [importedIssue.id, importedClean.id]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: importedIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance),
            EvaluationSignal(assetID: outsideIssue.id, kind: .focus, value: .score(0.29), confidence: 0.89, provenance: provenance)
        ])

        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 1)
    }

    func testLatestImportFlaggedReviewCountCachesUntilPresentationRefresh() throws {
        let firstIssue = makeAsset(id: "latest-import-cached-issue", size: 1)
        let secondIssue = makeAsset(id: "latest-import-second-issue", size: 2)
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "latest-import-flagged-count-cache",
            assets: [firstIssue, secondIssue],
            outputAssetIDs: [firstIssue.id, secondIssue.id]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: firstIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance)
        ])

        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 1)

        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondIssue.id, kind: .focus, value: .score(0.29), confidence: 0.89, provenance: provenance)
        ])

        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 1)

        model.refreshLatestImportPresentation()

        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 2)
    }

    func testLatestImportPreviewQueueChangeKeepsFlaggedCountCachedWhileUpdatingPreviewStatus() throws {
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: RecordingWorkerTransport()
        )
        let firstIssue = makeAsset(id: "latest-import-split-first-issue", size: 1)
        let secondIssue = makeAsset(id: "latest-import-split-second-issue", size: 2)
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "latest-import-preview-status-split",
            assets: [firstIssue, secondIssue],
            outputAssetIDs: [firstIssue.id, secondIssue.id],
            workerSupervisor: supervisor
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: firstIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance)
        ])

        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 1)
        XCTAssertEqual(model.latestImportCompletionSummary?.previewStatusText, "Previews ready")

        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondIssue.id, kind: .focus, value: .score(0.29), confidence: 0.89, provenance: provenance)
        ])
        try model.requestPreview(assetID: secondIssue.id, level: .grid)

        XCTAssertEqual(model.latestImportCompletionSummary?.previewStatusText, "generating previews")
        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 1)

        model.refreshLatestImportPresentation()

        XCTAssertEqual(model.latestImportFlaggedReviewAssetCount, 2)
    }

    func testCoalescedBackgroundWorkPublicationDefersQueueUpdatesUntilFlush() throws {
        let scheduler = ManualBackgroundWorkPublicationScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: RecordingWorkerTransport()
        )
        let first = makeAsset(id: "coalesced-publication-first", size: 1)
        let second = makeAsset(id: "coalesced-publication-second", size: 2)
        let (model, _, _) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "coalesced-queue-publication",
            assets: [first, second],
            workerSupervisor: supervisor,
            backgroundWorkPublicationInterval: 0.25,
            backgroundWorkPublicationScheduler: scheduler
        )

        try model.requestPreview(assetID: first.id, level: .grid)
        try model.requestPreview(assetID: first.id, level: .grid)
        try model.requestPreview(assetID: second.id, level: .grid)

        XCTAssertTrue(model.backgroundWorkQueue.items.isEmpty)
        XCTAssertEqual(scheduler.scheduledActions.count, 1)

        scheduler.fireScheduledActions()

        XCTAssertEqual(model.backgroundWorkQueue.items.map(\.id), [
            WorkSessionID(rawValue: "preview-\(first.id.rawValue)-grid"),
            WorkSessionID(rawValue: "preview-\(second.id.rawValue)-grid")
        ])
    }

    func testGridPreviewURLCachesLookupsBetweenBackgroundWorkPublications() throws {
        let scheduler = ManualBackgroundWorkPublicationScheduler()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: RecordingWorkerTransport()
        )
        let cached = makeAsset(id: "grid-preview-memo-cached", size: 1)
        let requested = makeAsset(id: "grid-preview-memo-requested", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "grid-preview-memo",
            assets: [cached, requested],
            workerSupervisor: supervisor,
            backgroundWorkPublicationInterval: 0.25,
            backgroundWorkPublicationScheduler: scheduler
        )

        XCTAssertNil(model.gridPreviewURL(for: cached.id))

        let placeholderURL = previewCache.url(for: PreviewCacheKey(assetID: cached.id, level: .grid))
        try writePreviewPlaceholder(to: placeholderURL)

        XCTAssertNil(model.gridPreviewURL(for: cached.id))

        try model.requestPreview(assetID: requested.id, level: .grid)
        scheduler.fireScheduledActions()

        XCTAssertEqual(model.gridPreviewURL(for: cached.id), placeholderURL)
    }

    @MainActor
    func testPreviewQueueTransitionsDoNotRepublishUnchangedImportActivity() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-activity-quiescence")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let existing = makeAsset(id: "quiescence-existing", size: 1)
        try catalog.repository.upsert(existing)
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 4),
            transport: RecordingWorkerTransport()
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)

        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        XCTAssertEqual(model.recentWork.first?.id, importItem.id.rawValue)

        let recentWorkRepublished = ObservationChangeFlag()
        withObservationTracking {
            _ = model.recentWork
        } onChange: {
            recentWorkRepublished.value = true
        }

        try model.requestPreview(assetID: existing.id, level: .grid)

        XCTAssertFalse(recentWorkRepublished.value)
        XCTAssertEqual(model.recentWork.first?.id, importItem.id.rawValue)
    }

    func testReviewLatestImportFlaggedAppliesImportBatchLikelyIssueScope() throws {
        let importedIssue = makeAsset(id: "review-import-likely-issue", size: 1)
        let importedClean = makeAsset(id: "review-import-clean", size: 2)
        let outsideIssue = makeAsset(id: "review-outside-import-issue", size: 3)
        let (model, repository, _) = try makeModelWithCompletedImportSession(
            named: "review-latest-import-flagged",
            assets: [importedIssue, importedClean, outsideIssue],
            outputAssetIDs: [importedIssue.id, importedClean.id]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: importedIssue.id, kind: .focus, value: .score(0.31), confidence: 0.88, provenance: provenance),
            EvaluationSignal(assetID: outsideIssue.id, kind: .focus, value: .score(0.29), confidence: 0.89, provenance: provenance)
        ])

        try model.reviewLatestImportFlagged()

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.assets.map(\.id), [importedIssue.id])
        XCTAssertEqual(model.activeLibraryFilterChips, ["Import: latest-import-session", "Likely Issues"])
        XCTAssertNil(try repository.asset(id: importedIssue.id).metadata.flag)
        XCTAssertEqual(try repository.pendingMetadataSyncItems(limit: 10), [])
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

    func testCanRequestSelectedAssetEvaluationRequiresSelectionWorkerAndCachedPreview() throws {
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

        XCTAssertFalse(model.canRequestSelectedAssetEvaluation)
    }

    func testCanRequestSelectedAssetEvaluationAllowsCachedPreviewCandidate() throws {
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: RecordingWorkerTransport()
        )
        let (model, previewCache, asset) = try makeModelWithPreviewCache(
            named: "evaluation-cached-preview",
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

        XCTAssertTrue(model.canRequestSelectedAssetEvaluation)
    }

    func testCanRequestVisibleAssetEvaluationsRequiresLoadedAssetsWorkerAndCachedPreview() throws {
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

        XCTAssertFalse(model.canRequestVisibleAssetEvaluations)
    }

    func testCanRequestVisibleAssetEvaluationsAllowsCachedPreviewCandidate() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let uncached = makeAsset(id: "visible-uncached", size: 1)
        let cached = makeAsset(id: "visible-cached", size: 2)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "visible-evaluation-cached-preview",
            assets: [uncached, cached],
            workerSupervisor: supervisor
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: cached.id, level: .grid)))

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

        XCTAssertFalse(model.canRequestCurrentScopeAssetEvaluations)
    }

    func testCanRequestCurrentScopeAssetEvaluationsRequiresCachedPreviewCandidate() throws {
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let asset = makeAsset(id: "current-scope-cached-preview", size: 1)
        let (model, _, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "current-scope-evaluation-cached-preview",
            assets: [asset],
            workerSupervisor: supervisor
        )

        XCTAssertFalse(model.canRequestCurrentScopeAssetEvaluations)

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))

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
            provenance: ProviderProvenance(provider: "local-image-metrics", model: "sharpness", version: "2", settingsHash: "default")
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

    func testSelectedSuggestedKeywordsComeFromMultiLabelObjectSignals() throws {
        let asset = Asset(
            id: AssetID(rawValue: "multi-label-suggested-keywords"),
            originalURL: URL(fileURLWithPath: "/Photos/multi-label-suggested-keywords.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(keywords: ["camera"])
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "multi-label-suggested-keywords", assets: [asset])
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(
                assetID: asset.id,
                kind: .object,
                value: .labels(["camera", "  alpine lake  ", "forest", "forest"]),
                confidence: 0.86,
                provenance: provenance
            )
        ])

        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.keyword), ["alpine lake", "forest"])
        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.confidenceText), ["86%", "86%"])
        XCTAssertEqual(model.selectedSuggestedKeywords.map(\.provenanceText), ["apple-vision/Vision", "apple-vision/Vision"])
        XCTAssertEqual(model.selectedAsset?.metadata.keywords, ["camera"])
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

    func testSelectedSuggestedCaptionsComeFromOCRTextSignals() throws {
        let asset = Asset(
            id: AssetID(rawValue: "suggested-caption"),
            originalURL: URL(fileURLWithPath: "/Photos/suggested-caption.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "suggested-captions", assets: [asset])
        let receiptProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision-OCR", version: "1", settingsHash: "default")
        let lowerProvenance = ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .ocrText, value: .text("  Invoice 123\nClient ABC  "), confidence: 0.92, provenance: receiptProvenance),
            EvaluationSignal(assetID: asset.id, kind: .ocrText, value: .text("Invoice 123"), confidence: 0.64, provenance: lowerProvenance),
            EvaluationSignal(assetID: asset.id, kind: .object, value: .label("document"), confidence: 0.8, provenance: receiptProvenance)
        ])

        XCTAssertEqual(model.selectedSuggestedCaptions.map(\.caption), ["Invoice 123 Client ABC", "Invoice 123"])
        XCTAssertEqual(model.selectedSuggestedCaptions.map(\.confidenceText), ["92%", "64%"])
        XCTAssertEqual(model.selectedSuggestedCaptions.map(\.provenanceText), ["apple-vision/Vision-OCR", "local-http-model/llava"])
    }

    func testOCRTextRemainsProvisionalUntilAccepted() throws {
        let asset = Asset(
            id: AssetID(rawValue: "provisional-caption"),
            originalURL: URL(fileURLWithPath: "/Photos/provisional-caption.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "provisional-caption", assets: [asset])
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision-OCR", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .ocrText, value: .text("Invoice 123"), confidence: 0.92, provenance: provenance)
        ])

        XCTAssertEqual(model.selectedSuggestedCaptions.map(\.caption), ["Invoice 123"])
        XCTAssertNil(model.selectedAsset?.metadata.caption)
        XCTAssertNil(try repository.asset(id: asset.id).metadata.caption)
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

    func testVisibleBatchKeywordSuggestionsAggregateMultiLabelObjectSignals() throws {
        let first = makeAsset(id: "first-multi-label-batch-keyword", path: "/Photos/first.jpg", rating: 0)
        let second = makeAsset(id: "second-multi-label-batch-keyword", path: "/Photos/second.jpg", rating: 0)
        let keyworded = makeAsset(
            id: "keyworded-multi-label-batch-keyword",
            path: "/Photos/keyworded.jpg",
            rating: 0,
            keywords: ["mountain"]
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "multi-label-batch-keyword-suggestions",
            assets: [first, second, keyworded]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: first.id, kind: .object, value: .labels(["mountain", "lake"]), confidence: 0.8, provenance: provenance),
            EvaluationSignal(assetID: second.id, kind: .object, value: .labels(["lake", "forest"]), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: keyworded.id, kind: .object, value: .labels(["mountain", "lake"]), confidence: 0.95, provenance: provenance)
        ])

        let suggestions = model.visibleBatchKeywordSuggestions

        XCTAssertEqual(suggestions.map(\.keyword), ["lake", "mountain", "forest"])
        XCTAssertEqual(suggestions.map(\.assetCountText), ["3 photos", "1 photo", "1 photo"])
        XCTAssertEqual(suggestions.map(\.confidenceText), ["78%", "80%", "60%"])
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
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(session.id.rawValue)")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(session.id.rawValue)", target: .workSession(session.id))
        ])
        XCTAssertEqual(model.assets.map(\.id), [first.id, second.id])
        XCTAssertEqual(try repository.asset(id: first.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: second.id).metadata.keywords, ["mountain"])
        XCTAssertEqual(try repository.asset(id: third.id).metadata.keywords, [])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: firstURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: secondURL.appendingPathExtension("xmp"))).metadata.keywords, ["mountain"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: thirdURL.appendingPathExtension("xmp").path))
    }

    func testAcceptCurrentScopeBatchKeywordSuggestionUsesFullFilteredScope() throws {
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

    func testAcceptSuggestedCaptionForSelectedAssetWritesCatalogAndXmp() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-accept-suggested-caption")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let originalURL = photosDirectory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "accept-suggested-caption"),
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
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision-OCR", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .ocrText, value: .text("Invoice 123\nClient ABC"), confidence: 0.92, provenance: provenance)
        ])

        XCTAssertEqual(model.selectedSuggestedCaptions.map(\.caption), ["Invoice 123 Client ABC"])

        try model.acceptSuggestedCaptionForSelectedAsset("Invoice 123 Client ABC")

        let expectedCaption = "Invoice 123 Client ABC"
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(model.selectedAsset?.metadata.caption, expectedCaption)
        XCTAssertEqual(try repository.asset(id: asset.id).metadata.caption, expectedCaption)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata.caption, expectedCaption)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        XCTAssertEqual(model.selectedSuggestedCaptions, [])
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

        // The sidebar "AI" section is retired (the `signal:` filter-bar token
        // is the remaining route); assert the underlying summary refreshes.
        XCTAssertTrue(model.catalogEvaluationKindSummaries.isEmpty)

        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)))
        try model.requestEvaluation(assetID: asset.id, provider: "apple-vision")
        try repository.recordEvaluationSignals([signal])
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: WorkSessionID(rawValue: "evaluation-\(asset.id.rawValue)-apple-vision"),
            message: "evaluated \(asset.id.rawValue) with apple-vision"
        )))

        try await waitForEvaluationSignalGeneration(1, for: asset.id, in: model)
        XCTAssertEqual(model.catalogEvaluationKindSummaries, [
            CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 1)
        ])
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
        XCTAssertEqual(reviewQueueCount("Analysis Failures", in: model), "1")

        try model.selectSidebarTarget(.reviewQueue(.providerFailures))

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
        XCTAssertEqual(model.activityCenterPresentation.sources.map(\.availability), [.missing])
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
        XCTAssertEqual(model.activityCenterPresentation.sources.map(\.availability), [.missing])
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

    @MainActor
    func testCancellingRunningLocalHTTPModelEvaluationSoftCancelsAndStartsNextQueuedWorkOnTerminal() async throws {
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

        // Per-item cancel is soft: the dispatched evaluation keeps its lane until its
        // natural terminal, so no cancelAll is broadcast and the queued preview waits.
        XCTAssertEqual(model.backgroundWorkQueue.item(id: evaluationID)?.status, .running)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: previewID)?.status, .queued)
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: evaluationAsset.id, provider: "local-http-model")
        ])

        // The worker's terminal finalizes the cancelled evaluation as cancelled and
        // frees the lane for the queued preview — without terminating the worker.
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: evaluationID,
            message: "evaluated running-evaluation"
        )))

        try await waitForBackgroundWorkStatus(.cancelled, itemID: evaluationID, in: model)
        try await waitForBackgroundWorkStatus(.running, itemID: previewID, in: model)
        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: evaluationAsset.id, provider: "local-http-model"),
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
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent)])

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
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
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
            .importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent),
            .generatePreview(assetID: importedAsset.id, level: .micro)
        ])
    }

    @MainActor
    func testWorkerImportCompletionQueuesEvaluationsForCachedPreviews() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-cached-preview")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        // Preview already cached before the import completes: evaluations queue immediately.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(importedAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testAutopilotArmedImportPublishesRunSummaryAfterEvaluationsComplete() async throws {
        let directory = try makeTemporaryDirectory(named: "autopilot-armed-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        model.autopilotEnabled = true

        model.beginImportFolder(photoFolder, autopilotAfterImport: true)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "autopilot-armed-imported"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try catalog.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: importedAsset.id, kind: .focus, value: .score(0.8), confidence: 0.9, provenance: provenance)
        ])
        // Preview already cached so evaluations queue at import completion.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)

        // Provisional-only until evaluations resolve: no run summary yet.
        XCTAssertNil(model.autopilotRunSummary)

        // Complete each provider's evaluation; the last one resolves the armed set.
        for provider in AppModel.defaultEvaluationProviderNames {
            transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
                itemID: WorkSessionID(rawValue: "evaluation-\(importedAsset.id.rawValue)-\(provider)"),
                message: "evaluated"
            )))
        }

        for _ in 0..<200 {
            if model.autopilotRunSummary != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(model.autopilotRunSummary)
        // Provisional only: import autopilot never writes catalog metadata.
        XCTAssertNil(try catalog.repository.asset(id: importedAsset.id).metadata.flag)
    }

    @MainActor
    func testAutopilotArmedImportRunsEvenWhenGlobalAutopilotIsDisabled() async throws {
        let directory = try makeTemporaryDirectory(named: "autopilot-armed-import-global-off")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        // The sheet's explicit per-import opt-in must run autopilot regardless
        // of the standing global default (which only seeds the toggle's
        // initial checked state, not a second gate).
        model.autopilotEnabled = false

        model.beginImportFolder(photoFolder, autopilotAfterImport: true)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "autopilot-armed-imported-global-off"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try catalog.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: importedAsset.id, kind: .focus, value: .score(0.8), confidence: 0.9, provenance: provenance)
        ])
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)

        for provider in AppModel.defaultEvaluationProviderNames {
            transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
                itemID: WorkSessionID(rawValue: "evaluation-\(importedAsset.id.rawValue)-\(provider)"),
                message: "evaluated"
            )))
        }

        for _ in 0..<200 {
            if model.autopilotRunSummary != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(model.autopilotRunSummary, "sheet-armed autopilot must run even when the global default is off")
        XCTAssertNil(try catalog.repository.asset(id: importedAsset.id).metadata.flag)
    }

    @MainActor
    func testUnarmedImportDoesNotRunAutopilotEvenWhenGlobalAutopilotIsEnabled() async throws {
        let directory = try makeTemporaryDirectory(named: "autopilot-unarmed-import-global-on")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        model.autopilotEnabled = true

        // Sheet's opt-in explicitly left unchecked for this import.
        model.beginImportFolder(photoFolder, autopilotAfterImport: false)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "autopilot-unarmed-imported-global-on"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try catalog.repository.recordEvaluationSignals([
            EvaluationSignal(assetID: importedAsset.id, kind: .focus, value: .score(0.8), confidence: 0.9, provenance: provenance)
        ])
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)

        for provider in AppModel.defaultEvaluationProviderNames {
            transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
                itemID: WorkSessionID(rawValue: "evaluation-\(importedAsset.id.rawValue)-\(provider)"),
                message: "evaluated"
            )))
        }

        // Give any (incorrect) autopilot run a chance to fire.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(model.autopilotRunSummary, "unarmed import must not run autopilot even though the global default is on")
    }

    @MainActor
    func testPreviewCompletionQueuesEvaluationsForPendingImportedAsset() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-preview-drain")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-drained"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .micro))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)
        // No cached preview yet, so nothing queued at completion time.
        XCTAssertFalse(model.backgroundWorkQueue.items.contains { $0.kind == .recognition })

        // The micro preview finishes: the completion hook queues the evaluation passes.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .micro)))
        let previewItemID = WorkSessionID(rawValue: "preview-\(importedAsset.id.rawValue)-micro")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: previewItemID,
            message: "generated micro preview"
        )))
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(importedAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testSecondImportCompletionKeepsPriorImportPendingEvaluations() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-two-import-drain")
        let firstFolder = directory.appendingPathComponent("photos-first", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("photos-second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstImage = firstFolder.appendingPathComponent("one.png")
        let secondImage = secondFolder.appendingPathComponent("two.png")
        try writeTestPNG(to: firstImage)
        try writeTestPNG(to: secondImage)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(firstFolder)
        let firstImportItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let firstAsset = Asset(
            id: AssetID(rawValue: "auto-eval-first-import"),
            originalURL: firstImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(firstAsset)
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: firstImportItem.id,
            message: "imported 1 photo from photos-first",
            importedAssetIDs: [firstAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(firstAsset.id, in: model)
        // No cached preview yet, so nothing queued at the first completion.
        XCTAssertFalse(model.backgroundWorkQueue.items.contains { $0.kind == .recognition })

        // A second import completes while the first import's previews still drain.
        model.beginImportFolder(secondFolder)
        let secondImportItem = try XCTUnwrap(model.backgroundWorkQueue.items.first { item in
            item.kind == .ingest && item.id != firstImportItem.id
        })
        let secondAsset = Asset(
            id: AssetID(rawValue: "auto-eval-second-import"),
            originalURL: secondImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 20, modificationDate: Date(timeIntervalSince1970: 20)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(secondAsset)
        // The first import's preview backlog beyond the active recovery batch is
        // still pending in the repository, so the second import's completion
        // enqueues it at the back of the queue -- behind its own ingest item.
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: firstAsset.id, level: .micro))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: secondImportItem.id,
            message: "imported 1 photo from photos-second",
            importedAssetIDs: [secondAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(secondAsset.id, in: model)

        // The first import's micro preview finishes: its evaluation passes must
        // still queue even though a second import completed in between.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: firstAsset.id, level: .micro)))
        let previewItemID = WorkSessionID(rawValue: "preview-\(firstAsset.id.rawValue)-micro")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: previewItemID,
            message: "generated micro preview"
        )))
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(firstAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testDisabledEvaluateAfterImportQueuesNoEvaluations() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-disabled")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder, evaluateAfterImport: false)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-off"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)

        XCTAssertFalse(model.backgroundWorkQueue.items.contains { $0.kind == .recognition })
    }

    @MainActor
    func testRejectedConcurrentFolderImportKeepsInFlightAutoEvaluationEnabled() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-rejected-folder-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        let otherFolder = directory.appendingPathComponent("photos-other", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder, evaluateAfterImport: true)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)

        // A rejected concurrent import must not change the in-flight import's
        // auto-evaluation setting.
        model.beginImportFolder(otherFolder, evaluateAfterImport: false)
        XCTAssertEqual(model.errorMessage, "Another import is already running")

        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-rejected-folder"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(importedAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testRejectedConcurrentCardImportKeepsInFlightAutoEvaluationEnabled() async throws {
        let directory = try makeTemporaryDirectory(named: "auto-eval-rejected-card-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        let cardSource = directory.appendingPathComponent("DCIM", isDirectory: true)
        let cardDestination = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cardSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cardDestination, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder, evaluateAfterImport: true)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)

        // A rejected concurrent card import must not change the in-flight
        // import's auto-evaluation setting.
        model.beginImportCard(source: cardSource, destinationRoot: cardDestination, evaluateAfterImport: false)
        XCTAssertEqual(model.errorMessage, "Another import is already running")

        let importedAsset = Asset(
            id: AssetID(rawValue: "auto-eval-rejected-card"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .grid)))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)

        let evaluationItemIDs = model.backgroundWorkQueue.items
            .filter { $0.kind == .recognition }
            .map(\.id.rawValue)
        XCTAssertEqual(evaluationItemIDs.sorted(), AppModel.defaultEvaluationProviderNames.map { provider in
            "evaluation-\(importedAsset.id.rawValue)-\(provider)"
        }.sorted())
    }

    @MainActor
    func testPreviewCompletionEnablesLatestImportEvaluateActionWhenAutoEvaluationDisabled() async throws {
        let directory = try makeTemporaryDirectory(named: "latest-import-evaluate-gate-preview-drain")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 8), transport: transport)
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportFolder(photoFolder, evaluateAfterImport: false)
        let importItem = try XCTUnwrap(model.backgroundWorkQueue.runningItems.first)
        let importedAsset = Asset(
            id: AssetID(rawValue: "evaluate-gate-deferred"),
            originalURL: image,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(importedAsset)
        try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: importedAsset.id, level: .micro))
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))
        try await waitForSelectedAsset(importedAsset.id, in: model)
        // The worker import deferred preview generation, so the evaluate action
        // is still gated off. This access caches the presentation core.
        XCTAssertFalse(model.canRequestLatestImportAssetEvaluations)

        // The only preview finishes: with auto-evaluation off, no recognition
        // completion will ever refresh the panel, so the preview transition
        // itself must flip the evaluate gate.
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: importedAsset.id, level: .micro)))
        let previewItemID = WorkSessionID(rawValue: "preview-\(importedAsset.id.rawValue)-micro")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completed(
            itemID: previewItemID,
            message: "generated micro preview"
        )))
        try await waitForCompletedBackgroundWorkItem(id: previewItemID, in: model)

        XCTAssertTrue(model.canRequestLatestImportAssetEvaluations)
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
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
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
        let skipped = photoFolder.appendingPathComponent("missing.png")
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 1 photo from photos",
            importedAssetIDs: [importedAsset.id],
            newAssetCount: 1,
            existingAssetCount: 0,
            skippedSourceFileCount: 1,
            skippedSourceFiles: [
                LibrarySkippedSourceFile(
                    sourceURL: skipped,
                    message: "could not fingerprint \(skipped.path)"
                )
            ]
        )))

        try await waitForSelectedAsset(importedAsset.id, in: model)

        XCTAssertEqual(model.statusMessage, "Imported 1 photo (1 file skipped)")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos (1 file skipped)")
        XCTAssertEqual(activity.issues.count, 1)
        XCTAssertEqual(activity.issues[0].sourceURL, skipped)
        XCTAssertTrue(activity.issues[0].message.contains("could not fingerprint"))
        let session = try catalog.repository.session(id: importItem.id)
        XCTAssertEqual(session.issues, activity.issues)
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
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent)])
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
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent)])
    }

    @MainActor
    func testBeginImportFolderRejectsDuplicateImportBeforeCoalescedQueuePublication() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-folder-import-duplicate-coalesced")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let scheduler = ManualBackgroundWorkPublicationScheduler()
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: supervisor,
            backgroundWorkPublicationInterval: 0.25,
            backgroundWorkPublicationScheduler: scheduler
        )

        // The published queue still lags behind the supervisor queue: the guard
        // must read the current queue, not the coalesced published copy.
        model.beginImportFolder(photoFolder)
        model.beginImportFolder(photoFolder)

        XCTAssertEqual(model.errorMessage, "Another import is already running")

        scheduler.fireScheduledActions()

        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind == .ingest }.count, 1)
        XCTAssertEqual(try transport.commands(), [.importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent)])
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
            importTaskFactory: { _, _, _, _ in
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
            importTaskFactory: { _, _, _, _ in
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
        let sourceRoot = try XCTUnwrap(model.sourceRoots.first)
        XCTAssertEqual(sourceRoot.path, photoFolder.path)
        XCTAssertEqual(sourceRoot.assetCount, 1)
        XCTAssertEqual(sourceRoot.securityScopedBookmarkData, bookmarkData)
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
            importTaskFactory: { _, _, _, _ in
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
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
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
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
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
        // Local import still auto-queues the imported-frame evaluation passes.
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)
        XCTAssertEqual(
            model.backgroundWorkQueue.items.filter { $0.kind == .recognition }.map(\.id.rawValue).sorted(),
            AppModel.defaultEvaluationProviderNames.map { provider in
                "evaluation-\(assetID.rawValue)-\(provider)"
            }.sorted()
        )
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind != .recognition }, [])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: assetID, provider: AppModel.defaultEvaluationProviderName)
        ])
        XCTAssertEqual(access.startedURLs, [photoFolder])
        XCTAssertEqual(access.stoppedURLs, [photoFolder])
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
    }

    @MainActor
    func testBeginImportCardWithWorkerImportsDisabledRunsLocalCopyAndGeneratesPreview() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-import-with-worker-disabled")
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
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: true,
            grantedURLs: [source, destinationRoot]
        )
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: supervisor,
            resourceAccess: access.value,
            workerImportsEnabled: false
        )

        model.beginImportCard(source: source, destinationRoot: destinationRoot)

        let assetID = try await waitForFirstAsset(in: model)
        let previewURL = try await waitForGridPreview(assetID: assetID, in: model)
        try await waitForStatusMessage("Imported 1 photo", in: model)
        let destinationImage = destinationRoot.appendingPathComponent("one.png")
        XCTAssertEqual(model.assets.map(\.originalURL), [destinationImage])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationImage.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        // Local card import still auto-queues the imported-frame evaluation passes.
        try await waitForRecognitionItemCount(AppModel.defaultEvaluationProviderNames.count, in: model)
        XCTAssertEqual(
            model.backgroundWorkQueue.items.filter { $0.kind == .recognition }.map(\.id.rawValue).sorted(),
            AppModel.defaultEvaluationProviderNames.map { provider in
                "evaluation-\(assetID.rawValue)-\(provider)"
            }.sorted()
        )
        XCTAssertEqual(model.backgroundWorkQueue.items.filter { $0.kind != .recognition }, [])
        XCTAssertEqual(try transport.commands(), [
            .runEvaluation(assetID: assetID, provider: AppModel.defaultEvaluationProviderName)
        ])
        XCTAssertEqual(access.startedURLs, [source, destinationRoot])
        XCTAssertEqual(access.stoppedURLs, [source, destinationRoot])
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
    }

    @MainActor
    func testCompletedCardImportPersistsSecurityScopedBookmarkForDestinationRoot() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-import-destination-bookmark")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let sourceImage = source.appendingPathComponent("one.png")
        try writeTestPNG(to: sourceImage)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("card-destination-bookmark".utf8)
        let access = RecordingSecurityScopedResourceAccess(
            requiresSuccessfulAccess: false,
            grantedURLs: [source, destinationRoot],
            bookmarkDataByURL: [destinationRoot: bookmarkData]
        )
        let model = try AppModel.load(catalog: catalog, resourceAccess: access.value)

        model.beginImportCard(source: source, destinationRoot: destinationRoot)

        try await waitForStatusMessage("Imported 1 photo", in: model)
        let sourceRoot = try XCTUnwrap(model.sourceRoots.first)
        XCTAssertEqual(sourceRoot.path, destinationRoot.path)
        XCTAssertEqual(sourceRoot.assetCount, 1)
        XCTAssertEqual(sourceRoot.securityScopedBookmarkData, bookmarkData)
        XCTAssertEqual(try catalog.repository.sourceRoots().first?.securityScopedBookmarkData, bookmarkData)
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
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
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
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
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
    func testBeginImportCardPassesDatedPolicyAndSecondCopyToLocalImportTask() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-policy")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        let secondCopy = directory.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let recorder = CardImportRequestRecorder()
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, destinationPolicy, secondCopyDestination, _, _ in
                recorder.record(destinationPolicy: destinationPolicy, secondCopyDestination: secondCopyDestination)
                return Task {
                    AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: .capturedDate,
            secondCopyDestination: secondCopy
        )

        XCTAssertEqual(recorder.destinationPolicies, [.capturedDate])
        XCTAssertEqual(recorder.secondCopyDestinations, [secondCopy])
    }

    @MainActor
    func testBeginImportCardWithWorkerCarriesDatedPolicyAndSecondCopyInCommand() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-worker-card-policy")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        let secondCopy = directory.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)

        model.beginImportCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: .capturedDate,
            secondCopyDestination: secondCopy
        )

        XCTAssertEqual(try transport.commands(), [.importCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: .capturedDate,
            secondCopyDestination: secondCopy,
            duplicateHandling: .skipCatalogedContent
        )])
    }

    @MainActor
    func testBeginImportCardRejectsMissingSecondCopyDestinationWithoutStartingLocalImport() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-missing-second-copy")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        let missingSecondCopy = directory.appendingPathComponent("missing-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let importTask = RecordingCall()
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
                importTask.call()
                return Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(
            source: source,
            destinationRoot: destinationRoot,
            secondCopyDestination: missingSecondCopy
        )

        XCTAssertFalse(importTask.wasCalled)
        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Second copy destination folder is missing")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from DCIM to Library: Second copy destination folder is missing")
    }

    @MainActor
    func testBeginImportCardRejectsSecondCopyDestinationMatchingPrimaryWithoutStartingLocalImport() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-local-card-second-copy-matching-primary")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let importTask = RecordingCall()
        let model = try AppModel.load(
            catalog: catalog,
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
                importTask.call()
                return Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )

        model.beginImportCard(
            source: source,
            destinationRoot: destinationRoot,
            secondCopyDestination: destinationRoot
        )

        XCTAssertFalse(importTask.wasCalled)
        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.activeWork)
        XCTAssertEqual(model.errorMessage, "Second copy destination must be different from the primary destination")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.status, .failed)
        XCTAssertEqual(activity.detail, "Import failed from DCIM to Library: Second copy destination must be different from the primary destination")
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
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
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
    func testWorkerImportProgressRevealsCatalogedAsset() async throws {
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
        XCTAssertTrue(model.assets.contains { $0.id == importedAsset.id })
        XCTAssertEqual(model.assets.count, 121)
        XCTAssertEqual(model.totalAssetCount, 121)
        XCTAssertEqual(model.libraryCountText, "121 photos")
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
            .importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent),
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
    func testCancellingVisibleWorkerImportPreservesOtherBackgroundWork() async throws {
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

        // Per-item cancel is soft: the running import keeps its lane until its natural
        // terminal, so the worker is not terminated and the queued preview waits.
        XCTAssertEqual(model.statusMessage, "Cancelled import")
        XCTAssertEqual(model.backgroundWorkQueue.item(id: importItem.id)?.status, .running)
        XCTAssertEqual(model.backgroundWorkQueue.item(id: previewItem.id)?.status, .queued)
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent)
        ])

        // The worker's import terminal finalizes the cancelled import, records the
        // cancelled import activity, and frees the lane for the queued preview.
        transport.emitOutputLine(try WorkerProtocolEncoder.encode(.completedImport(
            itemID: importItem.id,
            message: "imported 0 photos from photos",
            importedAssetIDs: [],
            newAssetCount: 0,
            existingAssetCount: 0,
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
        )))

        try await waitForBackgroundWorkStatus(.cancelled, itemID: importItem.id, in: model)
        try await waitForBackgroundWorkStatus(.running, itemID: previewItem.id, in: model)
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(transport.terminateCount, 0)
        XCTAssertEqual(try transport.commands(), [
            .importFolder(root: photoFolder, duplicateHandling: .skipCatalogedContent),
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
        XCTAssertEqual(try transport.commands(), [.importCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: .flat,
            secondCopyDestination: nil,
            duplicateHandling: .skipCatalogedContent
        )])

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
            skippedSourceFileCount: 0,
            skippedSourceFiles: []
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
            importTaskFactory: { paths, _, _, _ in
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
        XCTAssertEqual(activity.issues, [
            WorkSessionIssue(
                kind: .skippedSourceFile,
                sourceURL: skipped,
                message: "could not fingerprint \(skipped.path)"
            )
        ])
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)
        XCTAssertEqual(summary.issues, activity.issues)
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
            importTaskFactory: { _, _, _, _ in
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
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)
        XCTAssertEqual(summary.detail, "No photos imported from photos (2 files skipped)")
        XCTAssertEqual(summary.importedPhotoCount, 0)
        XCTAssertEqual(summary.photoCountText, "0 photos")
        XCTAssertEqual(summary.newPhotoCount, 0)
        XCTAssertEqual(summary.existingPhotoCount, 0)
        XCTAssertEqual(summary.previewStatusText, "No previews needed")
        XCTAssertEqual(summary.issues.map(\.sourceURL), [firstSkipped, secondSkipped])
    }

    @MainActor
    func testBackgroundImportReportsVideoAndUnrecognizedFileSkipsInCompletionCopy() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-format-honesty")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let video = photoFolder.appendingPathComponent("clip.mov")
        try Data("mov".utf8).write(to: video)
        let stray = photoFolder.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: stray)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        _ = try await model.importFolderInBackground(photoFolder)

        XCTAssertEqual(model.statusMessage, "Imported 1 photo (2 files skipped)")
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.detail, "Imported 1 photo from photos (2 files skipped)")
        XCTAssertEqual(activity.issues, [
            WorkSessionIssue(kind: .skippedSourceFile, sourceURL: video, message: "video file not supported"),
            WorkSessionIssue(kind: .skippedSourceFile, sourceURL: stray, message: "file type not supported")
        ])
        let summary = try XCTUnwrap(model.latestImportCompletionSummary)
        XCTAssertEqual(summary.issues, activity.issues)
        XCTAssertEqual(activity.failureCount, 0)
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
    func testBackgroundCardImportReportsBackupFailuresAsFailedBackupsNotSkippedFiles() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-card-import-backup-failure")
        let source = directory.appendingPathComponent("DCIM", isDirectory: true)
        let destination = directory.appendingPathComponent("Library", isDirectory: true)
        let secondCopy = directory.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondCopy, withIntermediateDirectories: true)
        let image = source.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let conflictingBackup = secondCopy.appendingPathComponent("one.png")
        try Data("existing".utf8).write(to: conflictingBackup)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importCardInBackground(
            source: source,
            destinationRoot: destination,
            secondCopyDestination: secondCopy
        )

        XCTAssertEqual(result.importedAssets.map(\.originalURL), [destination.appendingPathComponent("one.png")])
        XCTAssertEqual(
            model.statusMessage,
            "Imported 1 photo (1 backup copy failed)",
            "a fully imported photo whose backup failed must not be reported as skipped"
        )
        let activity = try XCTUnwrap(model.recentWork.first)
        XCTAssertEqual(activity.detail, "Imported 1 photo from DCIM to Library (1 backup copy failed)")
        XCTAssertEqual(activity.issues.count, 1)
        let issue = try XCTUnwrap(activity.issues.first)
        XCTAssertEqual(issue.kind, .skippedSourceFile)
        XCTAssertEqual(issue.sourceURL, image)
        XCTAssertTrue(
            issue.message.hasPrefix("backup copy failed: "),
            "expected honest backup failure message, got \(issue.message)"
        )
        XCTAssertEqual(try String(contentsOf: conflictingBackup, encoding: .utf8), "existing")
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
        let collectionsSection = try XCTUnwrap(reloaded.sidebarSections.first { $0.title == "Collections" })
        let recentWorkRow = try XCTUnwrap(collectionsSection.rows.first { $0.id.hasPrefix("work-recent-") })
        XCTAssertEqual(recentWorkRow.title, "Imported 1 photo from photos")
        let session = try catalog.repository.session(id: WorkSessionID(rawValue: activity.id))
        let outputSetID = try XCTUnwrap(session.outputSetIDs.first)
        let outputSet = try catalog.repository.assetSet(id: outputSetID)
        if case .manual(let assetIDs) = outputSet.membership {
            XCTAssertEqual(assetIDs, [reloaded.assets[0].id])
        } else {
            XCTFail("import output set should be manual")
        }

        try reloaded.selectSidebarRow(recentWorkRow)

        XCTAssertNil(reloaded.selectedAssetSetID)
        XCTAssertEqual(reloaded.librarySearchText, "session:\(session.id.rawValue)")
        XCTAssertEqual(reloaded.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(session.id.rawValue)", target: .workSession(session.id))
        ])
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
        XCTAssertEqual(assetIDs(in: try catalog.repository.assetSet(id: outputSetID)), [try XCTUnwrap(model.assets.first?.id)])
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(summary.activityID)")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(summary.activityID)", target: .workSession(WorkSessionID(rawValue: summary.activityID)))
        ])
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedView, .grid)
    }

    func testLatestCompletedImportAppearsAsRecentlyAddedLibraryRow() throws {
        let first = makeAsset(id: "latest-first", path: "/Volumes/Archive/Import/first.jpg", rating: 0)
        let second = makeAsset(id: "latest-second", path: "/Volumes/Archive/Import/second.jpg", rating: 0)
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "app-model-recently-added-row",
            assets: [first, second],
            outputAssetIDs: [first.id, second.id]
        )

        let collectionsSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Collections" })
        let recentlyAddedRow = try XCTUnwrap(collectionsSection.rows.first { $0.title == "Recent Import" })

        XCTAssertEqual(collectionsSection.rowTitles.prefix(2), ["All Photographs", "Recent Import"])
        XCTAssertEqual(recentlyAddedRow.detailText, "Imported 2 photos from Import")
        XCTAssertEqual(recentlyAddedRow.countText, "2")
        XCTAssertEqual(recentlyAddedRow.target, .workSession(WorkSessionID(rawValue: "latest-import-session")))
    }

    func testSelectingRecentlyAddedLibraryRowOpensLatestImportOutputSet() throws {
        let first = makeAsset(id: "latest-first", path: "/Volumes/Archive/Import/first.jpg", rating: 0)
        let second = makeAsset(id: "latest-second", path: "/Volumes/Archive/Import/second.jpg", rating: 0)
        let unrelated = makeAsset(id: "unrelated", path: "/Volumes/Archive/Other/unrelated.jpg", rating: 0)
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "app-model-recently-added-select",
            assets: [first, second, unrelated],
            outputAssetIDs: [first.id, second.id]
        )
        model.minimumRatingFilter = 5
        try model.reload()
        let collectionsSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Collections" })
        let recentlyAddedRow = try XCTUnwrap(collectionsSection.rows.first { $0.title == "Recent Import" })

        try model.selectSidebarRow(recentlyAddedRow)

        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:latest-import-session")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: latest-import-session", target: .workSession(WorkSessionID(rawValue: "latest-import-session")))
        ])
        XCTAssertEqual(model.assets.map(\.id), [first.id, second.id])
        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.selectedView, .grid)
    }

    func testCompletedImportWithoutOutputSetDoesNotShowRecentlyAddedLibraryRow() throws {
        let asset = makeAsset(id: "no-output", path: "/Volumes/Archive/Import/no-output.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "app-model-recently-added-no-output",
            assets: [asset],
            configureRepository: { repository in
                try repository.save(WorkSession(
                    id: WorkSessionID(rawValue: "empty-import-session"),
                    kind: .ingest,
                    intent: "Import photos",
                    title: "Import photos",
                    detail: "No photos imported from Import",
                    status: .completed,
                    inputSetIDs: [],
                    outputSetIDs: [],
                    completedUnitCount: 0,
                    totalUnitCount: 0,
                    failureCount: 0,
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20)
                ))
            }
        )

        XCTAssertNotNil(try? repository.session(id: WorkSessionID(rawValue: "empty-import-session")))
        let collectionsSection = try XCTUnwrap(model.sidebarSections.first { $0.title == "Collections" })

        XCTAssertFalse(collectionsSection.rowTitles.contains("Recent Import"))
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
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "import-summary-stack-counts",
            assets: [first, second, singleton],
            outputAssetIDs: [first.id, second.id, singleton.id]
        )

        let summary = try XCTUnwrap(model.latestImportCompletionSummary)

        XCTAssertEqual(summary.stackCount, 1)
        XCTAssertEqual(summary.stackedPhotoCount, 2)
    }

    func testLatestImportCompletionSummaryIgnoresUnrelatedPreviewWork() throws {
        let imported = makeAsset(
            id: "import-summary-ready",
            path: "/Photos/Import/import-summary-ready.cr2",
            rating: 0
        )
        let unrelated = makeAsset(
            id: "unrelated-preview-work",
            path: "/Photos/Other/unrelated-preview-work.cr2",
            rating: 0
        )
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: RecordingWorkerTransport()
        )
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "import-summary-unrelated-preview-work",
            assets: [imported, unrelated],
            outputAssetIDs: [imported.id],
            workerSupervisor: supervisor
        )

        try model.requestPreview(assetID: unrelated.id, level: .grid)

        let summary = try XCTUnwrap(model.latestImportCompletionSummary)

        XCTAssertEqual(summary.previewStatusText, "Previews ready")
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
        let inputSetID = try XCTUnwrap(cullingSession.inputSetIDs.first)
        XCTAssertTrue(inputSetID.rawValue.hasPrefix("work-input-\(cullingSession.id.rawValue)"))
        XCTAssertEqual(assetIDs(in: try catalog.repository.assetSet(id: inputSetID)), assetIDs(in: try catalog.repository.assetSet(id: outputSetID)))
        XCTAssertEqual(model.selectedAssetSetID, inputSetID)
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
        let (model, repository, _) = try makeModelWithCompletedImportSession(
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
        let (model, repository, _) = try makeModelWithCompletedImportSession(
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
        let (model, repository, _) = try makeModelWithCompletedImportSession(
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

    func testBeginningStackCullingFromLatestImportSelectsFirstStack() throws {
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
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "stack-culling-from-import-late-stack",
            assets: assets,
            outputAssetIDs: assets.map(\.id)
        )

        XCTAssertEqual(model.latestImportCompletionSummary?.stackCount, 1)

        _ = try model.beginStackCullingFromLatestImportCompletion()

        XCTAssertEqual(model.selectedAssetID, stackFirst.id)
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

        XCTAssertEqual(assetIDs(in: try catalog.repository.assetSet(id: outputSetID)), [try XCTUnwrap(model.assets.first?.id)])
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.librarySearchText, "session:\(summary.activityID)")
        XCTAssertEqual(model.activeLibraryFilterRows, [
            ActiveLibraryFilterRow(title: "Session: \(summary.activityID)", target: .workSession(WorkSessionID(rawValue: summary.activityID)))
        ])
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
            importTaskFactory: { _, _, _, _ in
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
            importTaskFactory: { _, _, _, _ in
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
        XCTAssertTrue(model.sidebarSections.first { $0.title == "Collections" }?.rowTitles.contains("Importing from photos") ?? false)
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
            cardImportTaskFactory: { _, _, _, _, _, _, _ in
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
            importTaskFactory: { _, _, _, progress in
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
            importTaskFactory: { paths, _, _, progress in
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

    @MainActor
    func testBackgroundImportKeepsFirstCatalogedAssetVisibleDuringLaterProgress() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import-stable-early-asset")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let firstImage = photoFolder.appendingPathComponent("first.png")
        let secondImage = photoFolder.appendingPathComponent("second.png")
        try writeTestPNG(to: firstImage)
        try writeTestPNG(to: secondImage)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let firstAsset = Asset(
            id: AssetID(rawValue: "local-early-import-first"),
            originalURL: firstImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let secondAsset = Asset(
            id: AssetID(rawValue: "local-early-import-second"),
            originalURL: secondImage,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 11, modificationDate: Date(timeIntervalSince1970: 11)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { paths, _, _, progress in
                Task.detached {
                    let backgroundCatalog = try AppCatalog.open(paths: paths)
                    try backgroundCatalog.repository.upsert(firstAsset)
                    progress(LibraryImportProgress(
                        completedUnitCount: 1,
                        totalUnitCount: 2,
                        detail: "Cataloging 1 of 2 photos",
                        catalogedAssetIDs: [firstAsset.id]
                    ))
                    try await Task.sleep(nanoseconds: 20_000_000)
                    try backgroundCatalog.repository.upsert(secondAsset)
                    progress(LibraryImportProgress(
                        completedUnitCount: 2,
                        totalUnitCount: 2,
                        detail: "Cataloging 2 of 2 photos",
                        catalogedAssetIDs: [secondAsset.id]
                    ))
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [firstAsset, secondAsset], previewFailures: []),
                        assets: try backgroundCatalog.repository.allAssets(limit: 500),
                        totalAssetCount: try backgroundCatalog.repository.assetCount()
                    )
                }
            }
        )

        model.beginImportFolder(photoFolder)

        try await waitForSelectedAsset(firstAsset.id, in: model)
        try await waitForActiveWorkProgress(
            completedUnitCount: 2,
            totalUnitCount: 2,
            detail: "Cataloging 2 of 2 photos",
            in: model
        )
        XCTAssertEqual(model.selectedAssetID, firstAsset.id)
        XCTAssertEqual(model.assets.map(\.id), [firstAsset.id])
        XCTAssertEqual(model.totalAssetCount, 1)

        model.cancelActiveWork()
        try await waitForActivityStatus(.cancelled, in: model)
    }

    func testRejectRelocationPreflightCountsRejectsSidecarsAndBytesInScope() throws {
        let directory = try makeTemporaryDirectory(named: "reject-preflight")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let rejectOriginal = shoot.appendingPathComponent("reject.cr2")
        let rejectSidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        let keeperOriginal = shoot.appendingPathComponent("keeper.cr2")
        try Data(repeating: 0, count: 100).write(to: rejectOriginal)
        try Data(repeating: 0, count: 20).write(to: rejectSidecar)
        try Data(repeating: 0, count: 100).write(to: keeperOriginal)
        let reject = makeAsset(id: "pf-reject", path: rejectOriginal.path, rating: 0, flag: .reject)
        let keeper = makeAsset(id: "pf-keeper", path: keeperOriginal.path, rating: 4, flag: .pick)
        let (model, _) = try makeModelWithCatalogAssets(named: "reject-preflight-model", assets: [reject, keeper])

        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )

        XCTAssertEqual(preflight.assetIDs, [reject.id])
        XCTAssertEqual(preflight.moveCount, 1)
        XCTAssertEqual(preflight.sidecarCount, 1)
        XCTAssertEqual(preflight.totalByteCount, 120)
        XCTAssertEqual(preflight.confirmationText, "Move 1 reject photo to rejects")
    }

    func testRejectRelocationPreflightRespectsCurrentSetScope() throws {
        let directory = try makeTemporaryDirectory(named: "reject-preflight-scope")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let inScope = shoot.appendingPathComponent("in.cr2")
        let outOfScope = shoot.appendingPathComponent("out.cr2")
        try Data(repeating: 0, count: 10).write(to: inScope)
        try Data(repeating: 0, count: 10).write(to: outOfScope)
        let inScopeReject = makeAsset(id: "scope-in", path: inScope.path, rating: 0, flag: .reject)
        let outOfScopeReject = makeAsset(id: "scope-out", path: outOfScope.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "reject-preflight-scope-model",
            assets: [inScopeReject, outOfScopeReject]
        )
        try repository.upsert(AssetSet.manual(
            id: AssetSetID(rawValue: "only-in"),
            name: "Only In",
            assetIDs: [inScopeReject.id]
        ))
        try model.reload()
        try model.applyAssetSet(id: AssetSetID(rawValue: "only-in"))

        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )

        XCTAssertEqual(preflight.assetIDs, [inScopeReject.id])
    }

    func testRejectRelocationPreflightFlagsUnavailableOriginals() throws {
        let missingReject = makeAsset(
            id: "pf-missing",
            path: "/Volumes/Gone/missing.cr2",
            rating: 0,
            flag: .reject,
            availability: .missing
        )
        let (model, _) = try makeModelWithCatalogAssets(named: "reject-preflight-missing", assets: [missingReject])

        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: URL(fileURLWithPath: "/tmp/rejects", isDirectory: true)
        )

        XCTAssertEqual(preflight.unavailableCount, 1)
        XCTAssertEqual(preflight.moveCount, 0)
    }

    func testMoveRejectsToFolderMovesOriginalsSidecarsAndRewritesCatalog() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        let sidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        try Data("raw".utf8).write(to: original)
        try Data("<xmp/>".utf8).write(to: sidecar)
        let reject = makeAsset(id: "mv-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-rejects-model", assets: [reject])
        let destination = directory.appendingPathComponent("rejects", isDirectory: true)
        let preflight = try model.rejectRelocationPreflight(destinationFolder: destination)

        let summary = try model.moveRejectsToFolder(preflight)

        XCTAssertEqual(summary.movedCount, 1)
        XCTAssertEqual(summary.sidecarCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        let movedOriginal = destination.appendingPathComponent("reject.cr2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedOriginal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("reject.cr2.xmp").path))
        let updated = try repository.asset(id: reject.id)
        XCTAssertEqual(updated.originalURL, movedOriginal)
        XCTAssertEqual(updated.availability, .online)
        XCTAssertEqual(updated.metadata.flag, .reject)
    }

    func testMoveRejectsRecordsAReversibleManifestAndActivity() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects-manifest")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        try Data("raw".utf8).write(to: original)
        let reject = makeAsset(id: "mf-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-rejects-manifest-model", assets: [reject])
        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )

        let summary = try model.moveRejectsToFolder(preflight)

        let entries = try repository.relocationManifestEntries(sessionID: summary.sessionID)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.assetID, reject.id)
        XCTAssertEqual(entries.first?.originalFrom, original)
        XCTAssertEqual(try repository.session(id: summary.sessionID).kind, .relocation)
        XCTAssertTrue(model.recentWork.contains { $0.id == summary.sessionID.rawValue })
        XCTAssertEqual(model.rejectRelocationSummary?.sessionID, summary.sessionID)
    }

    func testMoveRejectsSkipsUnwritableDestinationWithoutTouchingCatalog() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects-skip")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let goodOriginal = shoot.appendingPathComponent("good.cr2")
        let blockedOriginal = shoot.appendingPathComponent("blocked.cr2")
        try Data("raw".utf8).write(to: goodOriginal)
        try Data("raw".utf8).write(to: blockedOriginal)
        let good = makeAsset(id: "skip-good", path: goodOriginal.path, rating: 0, flag: .reject)
        let blocked = makeAsset(id: "skip-blocked", path: blockedOriginal.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-rejects-skip-model", assets: [good, blocked])
        let destination = directory.appendingPathComponent("rejects", isDirectory: true)
        let preflight = try model.rejectRelocationPreflight(destinationFolder: destination)
        // Delete the blocked source between preflight and move so its per-file
        // moveItem throws deterministically (a missing source always fails),
        // forcing a skip-with-issue while the good file still moves.
        try FileManager.default.removeItem(at: blockedOriginal)

        let summary = try model.moveRejectsToFolder(preflight)

        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.movedCount, 1)
        // The blocked asset keeps its original catalog path; the good one moved.
        XCTAssertEqual(try repository.asset(id: blocked.id).originalURL, blockedOriginal)
        XCTAssertNotEqual(try repository.asset(id: good.id).originalURL, goodOriginal)
    }

    func testMoveBackRelocationRestoresFilesAndCatalogPaths() throws {
        let directory = try makeTemporaryDirectory(named: "move-back")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        let sidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        try Data("raw".utf8).write(to: original)
        try Data("<xmp/>".utf8).write(to: sidecar)
        let reject = makeAsset(id: "mb-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-back-model", assets: [reject])
        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )
        let summary = try model.moveRejectsToFolder(preflight)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))

        let restored = try model.moveBackRelocation(sessionID: summary.sessionID)

        XCTAssertEqual(restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertEqual(try repository.asset(id: reject.id).originalURL, original)
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: summary.sessionID), [])
        XCTAssertNil(model.rejectRelocationSummary)
    }

    func testMoveBackRelocationIsIdempotentWhenAlreadyRestored() throws {
        let directory = try makeTemporaryDirectory(named: "move-back-twice")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        try Data("raw".utf8).write(to: original)
        let reject = makeAsset(id: "mb2-reject", path: original.path, rating: 0, flag: .reject)
        let (model, _) = try makeModelWithCatalogAssets(named: "move-back-twice-model", assets: [reject])
        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )
        let summary = try model.moveRejectsToFolder(preflight)
        _ = try model.moveBackRelocation(sessionID: summary.sessionID)

        // Manifest already deleted; a second call restores nothing and does not throw.
        XCTAssertEqual(try model.moveBackRelocation(sessionID: summary.sessionID), 0)
    }

    func testMoveRejectsToTrashRemovesCatalogRowsPreviewsAndRecordsManifest() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects-trash")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        let sidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        try Data("raw".utf8).write(to: original)
        try Data("<xmp/>".utf8).write(to: sidecar)
        let reject = makeAsset(id: "trash-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository, previewCache) = try makeModelWithCatalogAssetsAndPreviewCache(
            named: "move-rejects-trash-model",
            assets: [reject]
        )
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: reject.id, level: .grid))
        try writePreviewPlaceholder(to: previewURL)
        let preflight = try model.rejectRelocationTrashPreflight()

        let summary = try model.moveRejectsToTrash(preflight)

        XCTAssertEqual(summary.movedCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertThrowsError(try repository.asset(id: reject.id)) { error in
            guard case CatalogError.notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
        let entries = try repository.relocationManifestEntries(sessionID: summary.sessionID)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.assetID, reject.id)
        XCTAssertEqual(entries.first?.assetSnapshot?.id, reject.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(entries.first?.originalTo.path)))
    }

    // Persona-7 count drift: after trashing rejects the sidebar still said
    // "Rejects 40" / "Not analyzed yet 130" while HUD and catalog said
    // otherwise. Every bulk mutation funnels through reload(), so reload()
    // must refresh the sidebar's review-queue/set/folder counts too.
    func testMoveRejectsToTrashRefreshesSidebarCounts() throws {
        let directory = try makeTemporaryDirectory(named: "trash-sidebar-counts")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let rejectOriginal = shoot.appendingPathComponent("reject.cr2")
        let keptOriginal = shoot.appendingPathComponent("kept.cr2")
        try Data("raw-reject".utf8).write(to: rejectOriginal)
        try Data("raw-kept".utf8).write(to: keptOriginal)
        let reject = makeAsset(id: "counts-reject", path: rejectOriginal.path, rating: 0, flag: .reject)
        let kept = makeAsset(id: "counts-kept", path: keptOriginal.path, rating: 0, flag: nil)
        let (model, _) = try makeModelWithCatalogAssets(named: "trash-sidebar-counts-model", assets: [reject, kept])
        try model.reload()
        XCTAssertEqual(model.reviewQueueCounts[.rejects], 1)
        XCTAssertEqual(model.reviewQueueCounts[.needsEvaluation], 2)

        _ = try model.moveRejectsToTrash(try model.rejectRelocationTrashPreflight())

        XCTAssertEqual(model.reviewQueueCounts[.rejects], 0)
        XCTAssertEqual(model.reviewQueueCounts[.needsEvaluation], 1)
    }

    // Session scoping for completion banners: work restored from the
    // persisted history on relaunch is not "this session's" work, so its
    // completion panel must not resurrect; work recorded live is.
    func testCurrentSessionActivityTracksOnlyThisSessionsWork() throws {
        let assets = [makeAsset(id: "session-scope-asset", path: "/Photos/session-scope.jpg", rating: 0, flag: nil)]
        let (model, _, _) = try makeModelWithCompletedImportSession(
            named: "session-scope",
            assets: assets,
            outputAssetIDs: assets.map(\.id)
        )
        XCTAssertNotNil(model.latestImportCompletionSummary)
        XCTAssertFalse(model.isCurrentSessionActivity(id: "latest-import-session"))

        let liveDirectory = try makeTemporaryDirectory(named: "session-scope-live")
        let original = liveDirectory.appendingPathComponent("reject.cr2")
        try Data("raw".utf8).write(to: original)
        let reject = makeAsset(id: "session-scope-reject", path: original.path, rating: 0, flag: .reject)
        let (liveModel, _) = try makeModelWithCatalogAssets(named: "session-scope-live-model", assets: [reject])
        let summary = try liveModel.moveRejectsToTrash(try liveModel.rejectRelocationTrashPreflight())
        XCTAssertTrue(liveModel.isCurrentSessionActivity(id: summary.sessionID.rawValue))
    }

    func testMoveBackFromTrashReinsertsIdenticalRowAndRestoresFile() throws {
        let directory = try makeTemporaryDirectory(named: "move-back-trash")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        let sidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        try Data("raw".utf8).write(to: original)
        try Data("<xmp/>".utf8).write(to: sidecar)
        let reject = makeAsset(id: "back-trash-reject", path: original.path, rating: 3, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-back-trash-model", assets: [reject])
        let preflight = try model.rejectRelocationTrashPreflight()
        let summary = try model.moveRejectsToTrash(preflight)

        let restored = try model.moveBackRelocation(sessionID: summary.sessionID)

        XCTAssertEqual(restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        let reinserted = try repository.asset(id: reject.id)
        XCTAssertEqual(reinserted.id, reject.id)
        XCTAssertEqual(reinserted.originalURL, original)
        XCTAssertEqual(reinserted.metadata, reject.metadata)
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: summary.sessionID), [])
    }

    func testMoveBackFromTrashSkipsAndReportsEntriesWhoseTrashURLWasEmptied() throws {
        let directory = try makeTemporaryDirectory(named: "move-back-trash-emptied")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let keptOriginal = shoot.appendingPathComponent("kept.cr2")
        let emptiedOriginal = shoot.appendingPathComponent("emptied.cr2")
        try Data("raw".utf8).write(to: keptOriginal)
        try Data("raw".utf8).write(to: emptiedOriginal)
        let kept = makeAsset(id: "kept-reject", path: keptOriginal.path, rating: 0, flag: .reject)
        let emptied = makeAsset(id: "emptied-reject", path: emptiedOriginal.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "move-back-trash-emptied-model",
            assets: [kept, emptied]
        )
        let preflight = try model.rejectRelocationTrashPreflight()
        let summary = try model.moveRejectsToTrash(preflight)
        // Simulate the user emptying the Finder Trash for one of the two
        // trashed files between the trash operation and Move Back.
        let entries = try repository.relocationManifestEntries(sessionID: summary.sessionID)
        let emptiedEntry = try XCTUnwrap(entries.first { $0.assetID == emptied.id })
        try FileManager.default.removeItem(at: emptiedEntry.originalTo)

        let restored = try model.moveBackRelocation(sessionID: summary.sessionID)

        XCTAssertEqual(restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptOriginal.path))
        XCTAssertEqual(try repository.asset(id: kept.id).id, kept.id)
        XCTAssertThrowsError(try repository.asset(id: emptied.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptiedOriginal.path))
        // The unrecoverable file is reported on the banner itself, not
        // silently dropped: the summary says what restored and what is gone
        // for good, and — with nothing left restorable — the Move back
        // affordance retires and the manifest is cleared.
        let updatedSummary = try XCTUnwrap(model.rejectRelocationSummary)
        XCTAssertEqual(updatedSummary.restoredCount, 1)
        XCTAssertEqual(updatedSummary.unrestorableCount, 1)
        XCTAssertFalse(updatedSummary.canMoveBack)
        XCTAssertEqual(
            updatedSummary.detailText,
            "Moved back 1 photo · 1 file is no longer in the Trash and can't be restored"
        )
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: summary.sessionID), [])
    }

    // Persona-7 Marcus's "THE APP LIES": trash rejects, empty the Trash in
    // Finder, press Move back — the app must say the files are gone instead
    // of silently doing nothing behind a still-live Move back button.
    func testMoveBackFromTrashReportsWhenEveryTrashFileWasEmptied() throws {
        let directory = try makeTemporaryDirectory(named: "move-back-trash-all-emptied")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let originalA = shoot.appendingPathComponent("a.cr2")
        let originalB = shoot.appendingPathComponent("b.cr2")
        try Data("raw-a".utf8).write(to: originalA)
        try Data("raw-b".utf8).write(to: originalB)
        let rejectA = makeAsset(id: "emptied-a", path: originalA.path, rating: 0, flag: .reject)
        let rejectB = makeAsset(id: "emptied-b", path: originalB.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "move-back-trash-all-emptied-model",
            assets: [rejectA, rejectB]
        )
        let preflight = try model.rejectRelocationTrashPreflight()
        let summary = try model.moveRejectsToTrash(preflight)
        for entry in try repository.relocationManifestEntries(sessionID: summary.sessionID) {
            try FileManager.default.removeItem(at: entry.originalTo)
        }

        let restored = try model.moveBackRelocation(sessionID: summary.sessionID)

        XCTAssertEqual(restored, 0)
        let updatedSummary = try XCTUnwrap(model.rejectRelocationSummary)
        XCTAssertEqual(updatedSummary.restoredCount, 0)
        XCTAssertEqual(updatedSummary.unrestorableCount, 2)
        XCTAssertFalse(updatedSummary.canMoveBack)
        XCTAssertEqual(
            updatedSummary.detailText,
            "2 files are no longer in the Trash and can't be restored"
        )
        XCTAssertEqual(model.statusMessage, "2 files are no longer in the Trash and can't be restored")
        // The manifest is retired: a second press (were the button still
        // rendered) restores nothing and does not throw.
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: summary.sessionID), [])
        XCTAssertEqual(try model.moveBackRelocation(sessionID: summary.sessionID), 0)
    }

    func testLoadSurvivesDanglingPendingMetadataSyncRow() throws {
        // Regression: a pending metadata_sync_state row whose asset row is gone
        // (e.g. trashed before the cascade-delete fix, or any historic orphan)
        // must not crash app launch — enqueuePendingMetadataSync used to call
        // repository.asset(id:) with no per-item guard, so notFound propagated
        // to AppModel.load and main.swift's fatalError.
        let directory = try makeTemporaryDirectory(named: "dangling-sync-row")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let danglingID = AssetID(rawValue: "long-gone-asset")
        try repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: danglingID,
            sidecarURL: directory.appendingPathComponent("gone.cr2.xmp"),
            catalogGeneration: 1,
            lastSyncedFingerprint: nil
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
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: RecordingWorkerTransport()
        )

        XCTAssertNoThrow(try AppModel.load(catalog: catalog, workerSupervisor: supervisor))

        // The dangling row is dropped, not just skipped, so it can't resurface.
        XCTAssertNil(try repository.pendingMetadataSyncItem(assetID: danglingID))
    }

    func testMoveRejectsToTrashRemovesPersonLinksAndMoveBackRestoresThem() throws {
        let directory = try makeTemporaryDirectory(named: "trash-person-links")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let keptOriginal = shoot.appendingPathComponent("kept.cr2")
        let trashedOriginal = shoot.appendingPathComponent("trashed.cr2")
        try Data("raw".utf8).write(to: keptOriginal)
        try Data("raw".utf8).write(to: trashedOriginal)
        let kept = makeAsset(id: "person-kept", path: keptOriginal.path, rating: 0, flag: .pick)
        let trashed = makeAsset(id: "person-trashed", path: trashedOriginal.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "trash-person-links-model",
            assets: [kept, trashed],
            configureRepository: { repository in
                try repository.upsertPerson(id: "person-1", name: "Person One")
                try repository.assignAssets([kept.id, trashed.id], toPersonID: "person-1")
            }
        )
        let summary = try model.moveRejectsToTrash(try model.rejectRelocationTrashPreflight())
        XCTAssertEqual(summary.movedCount, 1)

        // The trashed asset no longer counts toward the person or appears in
        // its asset list; the kept one still does.
        XCTAssertEqual(try repository.people().first?.assetCount, 1)
        XCTAssertEqual(try repository.assetIDs(personID: "person-1"), [kept.id])

        _ = try model.moveBackRelocation(sessionID: summary.sessionID)

        // Move Back is a true undo: the person link comes back with the row.
        XCTAssertEqual(try repository.people().first?.assetCount, 2)
        XCTAssertEqual(Set(try repository.assetIDs(personID: "person-1")), [kept.id, trashed.id])
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

    // The old top-level "Starred" section is now the starred-asset-set rows
    // folded into Collections (Task 7); those rows keep the "asset-set-"
    // id they share with the Saved Sets section, which is what
    // distinguishes them from Collections' other rows.
    private func starredCollectionRows(_ model: AppModel) -> [SidebarRow] {
        (model.sidebarSections.first { $0.title == "Collections" }?.rows ?? [])
            .filter { $0.id.hasPrefix("asset-set-") }
    }

    // The old top-level "Recent Work"/"Starred Work" sections are now one
    // merged group of rows folded into Collections (Task 7).
    // `recentWorkCollectionRows` is the merged group; `starredWorkCollectionRows`
    // is the subset backed by a starred work session, matching the old
    // "Starred Work" section's contents.
    private func recentWorkCollectionRows(_ model: AppModel) -> [SidebarRow] {
        (model.sidebarSections.first { $0.title == "Collections" }?.rows ?? [])
            .filter {
                $0.id.hasPrefix("work-recent-") || $0.id.hasPrefix("work-starred-")
                    || $0.id.hasPrefix("work-matched-")
            }
    }

    // Just the recency-sourced slice (excludes starred sessions old enough
    // to have fallen out of the recent window and only appear via the
    // "work-starred-" overflow rows).
    private func recentOnlyWorkRows(_ model: AppModel) -> [SidebarRow] {
        (model.sidebarSections.first { $0.title == "Collections" }?.rows ?? [])
            .filter { $0.id.hasPrefix("work-recent-") }
    }

    private func starredWorkCollectionRows(_ model: AppModel) -> [SidebarRow] {
        let starredIDs = Set(model.starredWork.map { WorkSessionID(rawValue: $0.id) })
        return recentWorkCollectionRows(model).filter { row in
            if case .workSession(let id) = row.target {
                return starredIDs.contains(id)
            }
            return false
        }
    }

    // Review-queue rows are gone from the Library sidebar (Task 7 moves them
    // to the Cull sidebar in Task 13), but the underlying counts stay live on
    // the model - read those directly instead of a rendered sidebar row.
    private func reviewQueueCount(_ title: String, in model: AppModel) -> String? {
        guard let queue = ReviewQueue.allCases.first(where: { $0.presentation.title == title }),
              let count = model.reviewQueueCounts[queue],
              count > 0 else {
            return nil
        }
        return count.formatted(.number.notation(.compactName))
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

    private static func technicalMetadata(pixelWidth: Int, pixelHeight: Int) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private struct LoupeCullingFixture {
        var model: AppModel
        var previewCache: PreviewCache
        var assets: [Asset]
    }

    private func previewGenerationItemIDs(in model: AppModel) -> [String] {
        model.backgroundWorkQueue.items
            .filter { $0.kind == .previewGeneration }
            .map(\.id.rawValue)
    }

    // Builds a culling-sized asset run whose online originals exist on disk,
    // so requestVisibleLoupePreview's availability probe sees them as present.
    private func makeLoupeCullingFixture(
        named name: String,
        assetCount: Int,
        workerSupervisor: WorkerSupervisor,
        availabilityForIndex: (Int) -> SourceAvailability = { _ in .online }
    ) throws -> LoupeCullingFixture {
        let originalsDirectory = try makeTemporaryDirectory(named: "\(name)-originals")
        var assets: [Asset] = []
        for index in 0..<assetCount {
            let availability = availabilityForIndex(index)
            let originalURL = availability == .online
                ? originalsDirectory.appendingPathComponent("frame-\(index).jpg")
                : URL(fileURLWithPath: "/Volumes/Archive/\(name)/frame-\(index).jpg")
            let fingerprint: FileFingerprint
            if availability == .online {
                try Data("original".utf8).write(to: originalURL)
                fingerprint = try fileFingerprint(for: originalURL)
            } else {
                fingerprint = FileFingerprint(
                    size: Int64(index + 1),
                    modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1))
                )
            }
            assets.append(Asset(
                id: AssetID(rawValue: "\(name)-\(index)"),
                originalURL: originalURL,
                volumeIdentifier: "Photos",
                fingerprint: fingerprint,
                availability: availability,
                metadata: AssetMetadata()
            ))
        }
        let result = try makeModelWithCatalogAssetsAndPreviewCache(
            named: name,
            assets: assets,
            workerSupervisor: workerSupervisor
        )
        return LoupeCullingFixture(model: result.model, previewCache: result.previewCache, assets: assets)
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
        assetID: String,
        availability: SourceAvailability = .online
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
            availability: availability,
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

    private func makePendingMetadataSyncScopeModelWithSingleRetryableItem(
        named name: String
    ) throws -> (model: AppModel, transport: RecordingWorkerTransport, retryableAssetID: AssetID) {
        let directory = try makeTemporaryDirectory(named: name)
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        var assets: [Asset] = []
        for index in 0..<120 {
            let originalURL = photosDirectory.appendingPathComponent("offline-\(index).cr2")
            try Data("offline raw bytes \(index)".utf8).write(to: originalURL)
            assets.append(Asset(
                id: AssetID(rawValue: "offline-\(index)"),
                originalURL: originalURL,
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: 10 + Int64(index), modificationDate: Date(timeIntervalSince1970: TimeInterval(10 + index))),
                availability: .offline,
                metadata: AssetMetadata()
            ))
        }
        let retryableURL = photosDirectory.appendingPathComponent("retryable-beyond-loaded.cr2")
        try Data("retryable raw bytes".utf8).write(to: retryableURL)
        let retryable = Asset(
            id: AssetID(rawValue: "retryable-beyond-loaded"),
            originalURL: retryableURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1_000, modificationDate: Date(timeIntervalSince1970: 1_000)),
            availability: .online,
            metadata: AssetMetadata()
        )
        assets.append(retryable)
        try repository.upsert(assets)

        for asset in assets {
            try repository.recordMetadataSyncPending(MetadataSyncItem(
                assetID: asset.id,
                sidecarURL: asset.originalURL.appendingPathExtension("xmp"),
                catalogGeneration: try repository.catalogGeneration(assetID: asset.id),
                lastSyncedFingerprint: nil
            ))
        }

        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: transport)
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
            pendingMetadataSyncItems: try repository.pendingMetadataSyncItems(),
            pendingMetadataSyncCount: assets.count,
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
        workerSupervisor: WorkerSupervisor? = nil,
        backgroundWorkPublicationInterval: TimeInterval? = nil,
        backgroundWorkPublicationScheduler: any WorkerTimeoutScheduling = DispatchWorkerTimeoutScheduler()
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
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: workerSupervisor,
            backgroundWorkPublicationInterval: backgroundWorkPublicationInterval,
            backgroundWorkPublicationScheduler: backgroundWorkPublicationScheduler
        )
        return (model, repository, previewCache)
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
        outputAssetIDs: [AssetID],
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> (AppModel, CatalogRepository, PreviewCache) {
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
        return (try AppModel.load(catalog: catalog, workerSupervisor: workerSupervisor), repository, previewCache)
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
    private func waitForCompletedBackgroundWorkItem(id itemID: WorkSessionID, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.backgroundWorkQueue.item(id: itemID)?.status == .completed {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for completed work item \(itemID.rawValue)")
    }

    @MainActor
    private func waitForRecognitionItemCount(_ count: Int, in model: AppModel) async throws {
        for _ in 0..<100 {
            if model.backgroundWorkQueue.items.filter({ $0.kind == .recognition }).count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for \(count) recognition work items")
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
        for _ in 0..<1_000 {
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

    func testEnqueuePendingGeocodingPopulatesQueueForGeotaggedAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-geocoding-populate")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(geocodingLocatedAsset(id: "a", latitude: 48.8584, longitude: 2.2945))
        try repository.upsert(geocodingPlainAsset(id: "plain"))
        let (model, transport) = makeGeocodingModel(directory: directory, repository: repository)

        try model.enqueuePendingGeocoding()

        XCTAssertEqual(try repository.geocodeQueueDepth(), 1)
        XCTAssertEqual(try transport.commands().filter(\.isReverseGeocodeBatch).count, 1)
    }

    func testEnqueuePendingGeocodingIsNoOpWhenNoCoordinates() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-geocoding-noop")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(geocodingPlainAsset(id: "plain"))
        let (model, transport) = makeGeocodingModel(directory: directory, repository: repository)

        try model.enqueuePendingGeocoding()

        XCTAssertEqual(try repository.geocodeQueueDepth(), 0)
        XCTAssertTrue(try transport.commands().filter(\.isReverseGeocodeBatch).isEmpty)
    }

    // A coordinate whose geocode attempts are exhausted (attempt_count at the
    // executor's max) must never be re-dispatched: geocode_queue rows aren't
    // deleted on terminal failure, so a depth check that counts *all* rows
    // (rather than only rows still eligible for retry) would keep seeing
    // queueDepth > 0 forever and tight-loop redispatch a batch that always
    // processes zero items. Regression for the CPU-runaway/hang bug.
    func testEnqueuePendingGeocodingDoesNotRedispatchWhenAllItemsHaveExhaustedAttempts() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-geocoding-exhausted")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(geocodingLocatedAsset(id: "a", latitude: 48.8584, longitude: 2.2945))
        let (model, transport) = makeGeocodingModel(directory: directory, repository: repository)

        _ = try repository.enqueueMissingGeocodeCoordinates(limit: 100)
        let key = GeocodeCoordinateKey.key(latitude: 48.8584, longitude: 2.2945)
        for _ in 0..<WorkerCommandExecutor.reverseGeocodeMaximumAttemptCount {
            try repository.recordGeocodeFailure(coordinateKey: key, errorMessage: "network unreachable")
        }

        try model.enqueuePendingGeocoding()

        // The row is still sitting in geocode_queue (never deleted on terminal
        // failure) ...
        XCTAssertEqual(try repository.geocodeQueueDepth(), 1)
        // ... but with no items left eligible for retry, no batch should be
        // dispatched.
        XCTAssertTrue(try transport.commands().filter(\.isReverseGeocodeBatch).isEmpty)
    }

    func testBeginCoordinateBackfillDispatchesBackfillForOnlineUngeotaggedAssets() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-coordinate-backfill")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(geocodingPlainAsset(id: "needs"))  // online, no coordinates
        try repository.upsert(geocodingLocatedAsset(id: "has", latitude: 1, longitude: 2))
        let (model, transport) = makeGeocodingModel(directory: directory, repository: repository)

        try model.beginCoordinateBackfill()

        let backfillCommands = try transport.commands().filter(\.isBackfillCoordinates)
        XCTAssertEqual(backfillCommands.count, 1)
    }

    func testSelectingPlacesTargetEntersMapView() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-places-target")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let (model, _) = makeGeocodingModel(directory: directory, repository: repository)

        try model.selectSidebarTarget(.places)

        XCTAssertEqual(model.selectedView, .map)
    }

    func testSelectPlaceBoundsAppliesGeoFilterAndReturnsToGrid() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-places-bounds")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(geocodingLocatedAsset(id: "paris", latitude: 48.8584, longitude: 2.2945))
        try repository.upsert(geocodingLocatedAsset(id: "sydney", latitude: -33.87, longitude: 151.21))
        let (model, _) = makeGeocodingModel(directory: directory, repository: repository)
        try model.reload()

        try model.selectPlaceBounds(GeoBounds(minLatitude: 48, maxLatitude: 49, minLongitude: 2, maxLongitude: 3))

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.assets.map { $0.originalURL.lastPathComponent }, ["paris.cr2"])
    }

    private func makeGeocodingModel(
        directory: URL,
        repository: CatalogRepository
    ) -> (AppModel, RecordingWorkerTransport) {
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
            assets: [],
            totalAssetCount: 0,
            catalog: catalog,
            workerSupervisor: supervisor
        )
        return (model, transport)
    }

    private func geocodingLocatedAsset(id: String, latitude: Double, longitude: Double) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Volumes/NAS/\(id).cr2"),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1, pixelHeight: 1, latitude: latitude, longitude: longitude,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }

    private func geocodingPlainAsset(id: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Volumes/NAS/\(id).cr2"),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    // MARK: - Activity Center presentation wiring

    @MainActor
    func testActivityCenterPresentationWiresProviderFailureCountFromReviewQueueCounts() {
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            reviewQueueCounts: [.providerFailures: 3]
        )

        XCTAssertEqual(model.activityCenterPresentation.badge, .problems(3))
    }

    @MainActor
    func testActivityCenterPresentationOnlyImportScopedErrorsFeedImportError() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-activity-center-import-error-scoping")
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        model.errorMessage = "an unrelated model error"
        XCTAssertNil(model.activityCenterPresentation.importError, "unrelated model errors must not surface as import errors")

        model.beginImportFolder(directory.appendingPathComponent("does-not-exist", isDirectory: true))

        let importError = try XCTUnwrap(model.activityCenterPresentation.importError)
        XCTAssertFalse(importError.isEmpty)
    }

    @MainActor
    func testActivityCenterPresentationSourcesReflectAvailabilityAndBookmarkRepair() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-activity-center-sources")
        let sourceRoot = directory.appendingPathComponent("photos", isDirectory: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let bookmarkData = Data("source-root-bookmark".utf8)
        try catalog.repository.recordSourceRoot(sourceRoot, securityScopedBookmarkData: bookmarkData)
        let access = RecordingSecurityScopedResourceAccess(requiresSuccessfulAccess: false)

        let model = try AppModel.load(catalog: catalog, resourceAccess: access.value)
        let sources = model.activityCenterPresentation.sources

        XCTAssertTrue(sources.contains { $0.reconnectActionID == sourceRoot.path })
    }

    @MainActor
    func testActivityCenterPresentationXMPConflictsMapFromMetadataSyncConflictItems() {
        let assetID = AssetID(rawValue: "asset-1")
        let sidecarURL = URL(fileURLWithPath: "/Volumes/NAS/Vacation/IMG_0001.xmp")
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            metadataSyncConflictItems: [
                MetadataSyncItem(assetID: assetID, sidecarURL: sidecarURL, catalogGeneration: 1, lastSyncedFingerprint: nil)
            ]
        )

        let conflicts = model.activityCenterPresentation.xmpConflicts

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.assetID, assetID)
        XCTAssertEqual(conflicts.first?.displayName, "IMG_0001")
    }
}

private extension WorkerCommand {
    var isReverseGeocodeBatch: Bool {
        if case .reverseGeocodeBatch = self { return true }
        return false
    }

    var isBackfillCoordinates: Bool {
        if case .backfillCoordinates = self { return true }
        return false
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

private final class CardImportRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [(destinationPolicy: ImportDestinationPolicy, secondCopyDestination: URL?)] = []

    func record(destinationPolicy: ImportDestinationPolicy, secondCopyDestination: URL?) {
        lock.withLock {
            records.append((destinationPolicy: destinationPolicy, secondCopyDestination: secondCopyDestination))
        }
    }

    var destinationPolicies: [ImportDestinationPolicy] {
        lock.withLock { records.map(\.destinationPolicy) }
    }

    var secondCopyDestinations: [URL?] {
        lock.withLock { records.map(\.secondCopyDestination) }
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
    var terminationHandler: (() -> Void)?

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

/// Runs commands through a real `WorkerCommandExecutor` synchronously instead
/// of just recording them, so tests can exercise the full
/// AppModel -> WorkerSupervisor -> WorkerCommandExecutor round trip without
/// spawning the out-of-process worker binary.
private final class LoopbackWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    var terminationHandler: (() -> Void)?

    private let executor: WorkerCommandExecutor
    private(set) var isRunning = false
    private(set) var executedCommands: [WorkerCommand] = []
    private(set) var lastError: Error?
    private(set) var lastResult: WorkerCommandResult?

    init(executor: WorkerCommandExecutor) {
        self.executor = executor
    }

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        let request = try WorkerProtocolEncoder.decodeRequest(line)
        executedCommands.append(request.command)
        let event: WorkerEvent
        do {
            let result = try executor.execute(request.command)
            lastResult = result
            switch result {
            case .accepted(let message):
                event = .accepted(itemID: request.itemID, message: message)
            case .completed(let message):
                event = .completed(itemID: request.itemID, message: message)
            case .completedImport(
                let message,
                let importedAssetIDs,
                let newAssetCount,
                let existingAssetCount,
                let skippedSourceFileCount,
                let skippedSourceFiles
            ):
                event = .completedImport(
                    itemID: request.itemID,
                    message: message,
                    importedAssetIDs: importedAssetIDs,
                    newAssetCount: newAssetCount,
                    existingAssetCount: existingAssetCount,
                    skippedSourceFileCount: skippedSourceFileCount,
                    skippedSourceFiles: skippedSourceFiles
                )
            }
        } catch {
            lastError = error
            event = .failed(itemID: request.itemID, message: error.localizedDescription)
        }
        outputHandler?(try WorkerProtocolEncoder.encode(event))
    }

    func terminate() {
        isRunning = false
    }
}

private final class ManualBackgroundWorkPublicationScheduler: WorkerTimeoutScheduling, @unchecked Sendable {
    private(set) var scheduledActions: [@Sendable () -> Void] = []

    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any WorkerTimeoutCancellation {
        scheduledActions.append(action)
        return ManualBackgroundWorkPublicationCancellation()
    }

    func fireScheduledActions() {
        let actions = scheduledActions
        scheduledActions = []
        for action in actions {
            action()
        }
    }
}

private final class ManualBackgroundWorkPublicationCancellation: WorkerTimeoutCancellation, @unchecked Sendable {
    func cancel() {}
}

private final class ObservationChangeFlag: @unchecked Sendable {
    var value = false
}

private struct StubQueryTranslator: AutopilotQueryTranslator {
    var query: String
    func translate(_ naturalLanguage: String) throws -> String { query }
}

private struct FailingQueryTranslator: AutopilotQueryTranslator {
    func translate(_ naturalLanguage: String) throws -> String {
        throw TeststripError.io("translator offline")
    }
}
