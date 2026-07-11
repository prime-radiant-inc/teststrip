import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullSourcePresentationTests: XCTestCase {
    func testSourcesIncludeRecentImportAndBothReviewQueueGroups() throws {
        let asset = makeAsset(id: "a1", path: "/Photos/Cull/a1.jpg", rating: 3)
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-sources-basic", assets: [asset])

        model.reviewQueueCounts = [
            .picks: 2,
            .potentialPicks: 1,
            .likelyIssues: 1,
            .needsEvaluation: 3
        ]

        let sources = model.cullSourcePresentation.sources

        XCTAssertTrue(sources.contains { $0.group == .topPicks && $0.target == .reviewQueue(.picks) })
        XCTAssertTrue(sources.contains { $0.group == .topPicks && $0.target == .reviewQueue(.potentialPicks) })
        XCTAssertTrue(sources.contains { $0.group == .needsEyes && $0.target == .reviewQueue(.likelyIssues) })
        XCTAssertTrue(sources.contains { $0.group == .needsEyes && $0.target == .reviewQueue(.needsEvaluation) })

        let picksSource = try XCTUnwrap(sources.first { $0.target == .reviewQueue(.picks) })
        XCTAssertEqual(picksSource.count, 2)
    }

    func testSourcesIncludeRecentImportWhenLatestImportCompletionExists() throws {
        let asset = makeAsset(id: "a1", path: "/Photos/Cull/a1.jpg", rating: 3)
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-sources-import", assets: [asset])

        model.recentWork = [
            AppWorkActivity(
                id: "import-1",
                kind: .ingest,
                status: .completed,
                title: "Imported 1 photo",
                detail: "1 new",
                completedUnitCount: 1,
                totalUnitCount: 1,
                failureCount: 0
            )
        ]
        model.refreshLatestImportPresentation()

        let sources = model.cullSourcePresentation.sources
        XCTAssertTrue(sources.contains { $0.group == .recentImport && $0.target == .recentImport })
    }

    func testSourcesOmitAutopilotProposalsRowWhenNoneArePending() throws {
        let asset = makeAsset(id: "a1", path: "/Photos/Cull/a1.jpg", rating: 3)
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-sources-no-proposals", assets: [asset])

        let sources = model.cullSourcePresentation.sources
        XCTAssertFalse(sources.contains { $0.target == CullSource.Target.autopilotProposals })
    }

    func testSourcesIncludeAutopilotProposalsRowWhileProposalsArePending() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(
            id: "proposal-lead",
            path: "/Photos/Cull/proposal-lead.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let alternate = makeAsset(
            id: "proposal-alt",
            path: "/Photos/Cull/proposal-alt.cr2",
            rating: 0,
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "cull-sources-proposals",
            assets: [lead, alternate]
        ) { repository in
            let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
            try repository.recordEvaluationSignals([
                EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
                EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
            ])
        }
        try model.selectSidebarTarget(.allPhotographs)

        _ = try model.runAutopilotOnCurrentScope()

        let proposalsSource = try XCTUnwrap(
            model.cullSourcePresentation.sources.first { $0.target == CullSource.Target.autopilotProposals }
        )
        XCTAssertEqual(proposalsSource.group, .autopilotProposals)
        XCTAssertEqual(proposalsSource.count, model.pendingAutopilotProposals.count)
        XCTAssertGreaterThan(proposalsSource.count, 0)
    }

    func testVisibleSourcesOmitsZeroCountRows() {
        let presentation = CullSourcePresentation(sources: [
            CullSource(id: "a", group: .topPicks, title: "Picks", systemImage: "star", count: 3, target: .reviewQueue(.picks)),
            CullSource(id: "b", group: .needsEyes, title: "Needs Evaluation", systemImage: "eye", count: 0, target: .reviewQueue(.needsEvaluation)),
            CullSource(id: "c", group: .selection, title: "Selection", systemImage: "checkmark.circle", count: 0, target: .selection)
        ])

        XCTAssertEqual(presentation.visibleSources.map(\.id), ["a"])
    }

    func testIsEmptyIsTrueOnlyWhenAllSourcesAreZeroCount() {
        let allZero = CullSourcePresentation(sources: [
            CullSource(id: "a", group: .topPicks, title: "Picks", systemImage: "star", count: 0, target: .reviewQueue(.picks))
        ])
        XCTAssertTrue(allZero.isEmpty)

        let oneNonZero = CullSourcePresentation(sources: [
            CullSource(id: "a", group: .topPicks, title: "Picks", systemImage: "star", count: 0, target: .reviewQueue(.picks)),
            CullSource(id: "b", group: .selection, title: "Selection", systemImage: "checkmark.circle", count: 2, target: .selection)
        ])
        XCTAssertFalse(oneNonZero.isEmpty)

        let noSources = CullSourcePresentation(sources: [])
        XCTAssertTrue(noSources.isEmpty)
    }

    func testCullCurrentSelectionScopesToSelectedBatchAndSwitchesToCull() throws {
        let keeper = makeAsset(id: "keeper", path: "/Photos/Cull/keeper.jpg", rating: 5)
        let reject = makeAsset(id: "reject", path: "/Photos/Cull/reject.jpg", rating: 1)
        let bystander = makeAsset(id: "bystander", path: "/Photos/Cull/bystander.jpg", rating: 2)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "cull-current-selection",
            assets: [keeper, reject, bystander]
        )

        model.setBatchSelection(keeper.id, isSelected: true)
        model.setBatchSelection(reject.id, isSelected: true)

        _ = try model.cullCurrentSelection()

        XCTAssertEqual(model.selectedWorkspace, .cull)
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([keeper.id, reject.id]))
    }

    func testCullCurrentSelectionFallsBackToSingleSelectedAsset() throws {
        let onlyAsset = makeAsset(id: "solo", path: "/Photos/Cull/solo.jpg", rating: 4)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "cull-current-selection-single",
            assets: [onlyAsset]
        )
        model.select(onlyAsset.id)

        _ = try model.cullCurrentSelection()

        XCTAssertEqual(model.selectedWorkspace, .cull)
        XCTAssertEqual(model.assets.map(\.id), [onlyAsset.id])
    }

    func testCullCurrentSelectionThrowsWhenNothingSelected() throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-current-selection-empty", assets: [])

        XCTAssertThrowsError(try model.cullCurrentSelection())
    }

    // MARK: - Fixtures

    private func makeAsset(
        id: String,
        path: String,
        rating: Int,
        flag: PickFlag? = nil,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: .online,
            metadata: AssetMetadata(rating: rating, colorLabel: nil, flag: flag, keywords: []),
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset],
        configureRepository: (CatalogRepository) throws -> Void = { _ in }
    ) throws -> (AppModel, CatalogRepository) {
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
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
