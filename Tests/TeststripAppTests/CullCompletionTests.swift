import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullCompletionTests: XCTestCase {
    // MARK: - Presentation appears only at zero undecided, non-empty session

    func testPresentationIsNilWhenUndecidedRemains() {
        let presentation = CullCompletionPresentation.presentation(
            assets: [
                Self.asset(id: "asset-0", flag: .pick),
                Self.asset(id: "asset-1", flag: .pick),
                Self.asset(id: "asset-2", flag: .reject),
                Self.asset(id: "asset-3"),
                Self.asset(id: "asset-4")
            ],
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertNil(presentation)
    }

    func testPresentationIsNilWhenSessionIsEmpty() {
        let presentation = CullCompletionPresentation.presentation(
            assets: [],
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertNil(presentation)
    }

    func testPresentationAppearsWhenUndecidedIsZeroAndSessionNonEmpty() {
        for scope in [CullScope.unrated, .all] {
            let presentation = CullCompletionPresentation.presentation(
                assets: Self.decidedAssets(picks: 3, rejects: 2),
                viewedAssetIDs: [],
                skippedAssetIDs: [],
                pendingProposalAssetIDs: [],
                scope: scope
            )
            XCTAssertEqual(presentation?.picks, 3, "scope \(scope)")
            XCTAssertEqual(presentation?.rejects, 2, "scope \(scope)")
        }
    }

    // MARK: - Review scopes never show completion

    func testPresentationIsSuppressedInReviewScopesEvenWhenComplete() {
        // .picks/.rejects are review scopes: even a genuinely-complete
        // session must show the frames under review, not the handoff.
        for scope in [CullScope.picks, .rejects] {
            let presentation = CullCompletionPresentation.presentation(
                assets: Self.decidedAssets(picks: 3, rejects: 2),
                viewedAssetIDs: [],
                skippedAssetIDs: [],
                pendingProposalAssetIDs: [],
                scope: scope
            )
            XCTAssertNil(presentation, "scope \(scope)")
        }
    }

    func testSwitchingToPicksScopeWithUndecidedWorkDoesNotShowCompletionAndPicksAreBrowsable() {
        // Regression: undecided must be counted session-wide, not within the
        // scope filter — .picks excludes unflagged frames by definition, so a
        // scope-filtered count is trivially zero and falsely reports done.
        let model = makeModel(withFlags: [nil, .pick, .pick, nil])
        cycleCullScope(model, to: .picks)

        XCTAssertEqual(model.cullUndecidedCount, 2)
        let presentation = CullCompletionPresentation.presentation(
            assets: model.assets,
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingProposalAssetIDs: [],
            scope: model.cullScope
        )
        XCTAssertNil(presentation)
        // The picks are browsable: scope navigation has picks to land on.
        XCTAssertEqual(
            CullScopeOrdering.filteredAssetIDs(model.assets, scope: model.cullScope),
            [AssetID(rawValue: "asset-1"), AssetID(rawValue: "asset-2")]
        )
    }

    // MARK: - Run summary counts (Task 8)

    func testSummaryCountsClassifyScopeAgainstTrackerAndProposals() {
        // a0 pick, viewed · a1 reject, skipped then decided · a2 undecided,
        // skipped · a3 undecided, viewed · a4 pick, never viewed · a5
        // tentative-pick with a pending proposal, never viewed.
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
            Self.asset(id: "a2"),
            Self.asset(id: "a3"),
            Self.asset(id: "a4", flag: .pick),
            Self.asset(id: "a5", flag: .pick, tentative: true)
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id, assets[2].id, assets[3].id],
            skippedAssetIDs: [assets[1].id, assets[2].id],
            pendingProposalAssetIDs: [assets[5].id, AssetID(rawValue: "outside-scope")]
        )

        XCTAssertEqual(summary.picks, 2)
        XCTAssertEqual(summary.rejects, 1)
        XCTAssertEqual(summary.undecided, 3)
        // a1 was skipped but later decided: skipped ∖ decided drops it.
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.neverViewed, 2)
        // The out-of-scope proposal is excluded: pending proposals ∩ scope.
        XCTAssertEqual(summary.sparkleAwaiting, 1)
    }

    // INVARIANT (negative): a tentative ✨ flag is not a decision. It counts
    // in undecided AND in sparkleAwaiting, never in picked/rejected — and a
    // tentative-only scope is not complete.
    func testTentativeOnlyFlagCountsAsUndecidedAndSparkleAwaitingNeverPickedOrRejected() {
        for flag in [PickFlag.pick, .reject] {
            let asset = Self.asset(id: "tentative", flag: flag, tentative: true)
            let summary = CullCompletionPresentation.summary(
                assets: [asset],
                viewedAssetIDs: [asset.id],
                skippedAssetIDs: [],
                pendingProposalAssetIDs: [asset.id]
            )
            XCTAssertEqual(summary.picks, 0, "flag \(flag)")
            XCTAssertEqual(summary.rejects, 0, "flag \(flag)")
            XCTAssertEqual(summary.undecided, 1, "flag \(flag)")
            XCTAssertEqual(summary.sparkleAwaiting, 1, "flag \(flag)")

            let presentation = CullCompletionPresentation.presentation(
                assets: [asset],
                viewedAssetIDs: [asset.id],
                skippedAssetIDs: [],
                pendingProposalAssetIDs: [asset.id],
                scope: .all
            )
            XCTAssertNil(presentation, "flag \(flag)")
        }
    }

    func testPresentationCarriesRunCountsWhenComplete() {
        // Fully decided scope: a0 pick (viewed, pending keyword suggestion),
        // a1 reject (skipped then decided), a2 pick (never viewed).
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
            Self.asset(id: "a2", flag: .pick)
        ]
        let presentation = CullCompletionPresentation.presentation(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: [assets[1].id],
            pendingProposalAssetIDs: [assets[0].id],
            scope: .all
        )

        XCTAssertEqual(presentation?.picks, 2)
        XCTAssertEqual(presentation?.rejects, 1)
        XCTAssertEqual(presentation?.undecided, 0)
        XCTAssertEqual(presentation?.skipped, 0)
        XCTAssertEqual(presentation?.neverViewed, 1)
        XCTAssertEqual(presentation?.sparkleAwaiting, 1)
    }

    // MARK: - Actions

    func testActionsAreCoreFourWhenNoPicksAndNoPendingSuggestions() {
        let presentation = CullCompletionPresentation.presentation(
            assets: Self.decidedAssets(picks: 0, rejects: 2),
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertEqual(presentation?.actions, [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks])
    }

    func testActionsAppendReviewAISuggestionsAndSavePicksWhenApplicable() {
        let assets = Self.decidedAssets(picks: 1, rejects: 1)
        let presentation = CullCompletionPresentation.presentation(
            assets: assets,
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingProposalAssetIDs: [assets[0].id],
            scope: .all
        )
        XCTAssertEqual(
            presentation?.actions,
            [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks, .reviewAISuggestions, .savePicksAsSet]
        )
    }

    // MARK: - Undecided count on AppModel

    func testCullUndecidedCountIsSessionWideRegardlessOfScope() {
        let model = makeModel(withFlags: [nil, .pick, .reject, nil])
        XCTAssertEqual(model.cullScope, .all)
        XCTAssertEqual(model.cullUndecidedCount, 2)

        cycleCullScope(model, to: .picks)
        XCTAssertEqual(model.cullUndecidedCount, 2)

        cycleCullScope(model, to: .unrated)
        XCTAssertEqual(model.cullUndecidedCount, 2)
    }

    // MARK: - ReviewPicks sets scope

    func testReviewPicksActionSetsCullScopeToPicks() {
        let model = makeModel(withFlags: [nil, .pick])
        XCTAssertNotEqual(model.cullScope, .picks)

        model.applyCullCompletionReviewPicks()

        XCTAssertEqual(model.cullScope, .picks)
    }

    func testReviewPicksFromCompleteSessionShowsPicksNotCompletion() {
        // From a genuinely-complete session, ReviewPicks must land the user
        // on the picks stage, not re-render the completion state.
        let model = makeModel(withFlags: [.pick, .reject, .pick])
        XCTAssertEqual(model.cullUndecidedCount, 0)

        model.applyCullCompletionReviewPicks()

        XCTAssertEqual(model.cullScope, .picks)
        let presentation = CullCompletionPresentation.presentation(
            assets: model.assets,
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingProposalAssetIDs: [],
            scope: model.cullScope
        )
        XCTAssertNil(presentation)
        // A pick is selected, so the stage shows a pick.
        let pickIDs = CullScopeOrdering.filteredAssetIDs(model.assets, scope: .picks)
        XCTAssertFalse(pickIDs.isEmpty)
        if let selected = model.selectedAssetID {
            XCTAssertTrue(pickIDs.contains(selected))
        }
    }

    // MARK: - SavePicksAsSet action

    func testSaveCullingPicksAsSetRefreshesActiveSessionPicksSet() throws {
        let assets = [
            Self.asset(id: "session-a"),
            Self.asset(id: "session-b"),
            Self.asset(id: "session-c")
        ]
        let (model, repository) = try makeModelWithCatalogAssets(named: "save-picks-session", assets: assets)
        try model.beginCullingSession(named: "Batch")
        // Decide behind the session's back (direct catalog writes), so only
        // the action's own refresh can fold these into the picks set.
        try repository.updateMetadata(assetID: assets[0].id) { metadata in
            metadata.flag = .pick
        }
        try repository.updateMetadata(assetID: assets[1].id) { metadata in
            metadata.flag = .pick
            metadata.aiUnconfirmedFields = [.flag]
        }

        let picksSet = try model.saveCullingPicksAsSet()

        XCTAssertEqual(picksSet.name, "Batch Picks")
        let persisted = try XCTUnwrap(repository.assetSets().first { $0.id == picksSet.id })
        // Confirmed picks only: the tentative AI pick never lands in the
        // persisted set (confirm-before-write).
        XCTAssertEqual(Self.snapshotAssetIDs(of: persisted), [assets[0].id])
    }

    func testSaveCullingPicksAsSetWithoutSessionSnapshotsConfirmedPicksOnly() throws {
        let confirmed = Self.asset(id: "adhoc-confirmed", flag: .pick)
        let tentative = Self.asset(id: "adhoc-tentative", flag: .pick, tentative: true)
        let unflagged = Self.asset(id: "adhoc-unflagged")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "save-picks-adhoc",
            assets: [confirmed, tentative, unflagged]
        )

        let picksSet = try model.saveCullingPicksAsSet()

        let persisted = try XCTUnwrap(repository.assetSets().first { $0.id == picksSet.id })
        XCTAssertEqual(Self.snapshotAssetIDs(of: persisted), [confirmed.id])
        XCTAssertEqual(model.selectedAssetSetID, picksSet.id)
    }

    func testSaveCullingPicksAsSetThrowsWhenOnlyTentativePicksExist() throws {
        let tentative = Self.asset(id: "only-tentative", flag: .pick, tentative: true)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "save-picks-tentative-only",
            assets: [tentative]
        )

        // INVARIANT: a tentative flag never drives the committing picks-set
        // operation — with nothing confirmed there is nothing to save.
        XCTAssertThrowsError(try model.saveCullingPicksAsSet())
        XCTAssertTrue(try repository.assetSets().isEmpty)
    }

    // MARK: - Helpers

    private func cycleCullScope(_ model: AppModel, to target: CullScope) {
        while model.cullScope != target {
            model.cycleCullScope()
        }
    }

    private func makeModel(withFlags flags: [PickFlag?]) -> AppModel {
        let assets = flags.enumerated().map { index, flag -> Asset in
            var metadata = AssetMetadata()
            metadata.flag = flag
            return Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/tmp/asset-\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index))),
                availability: .online,
                metadata: metadata
            )
        }
        return AppModel(sidebarSections: [], selectedView: .loupe, assets: assets)
    }

    private static func asset(id: String, flag: PickFlag? = nil, tentative: Bool = false) -> Asset {
        var metadata = AssetMetadata()
        metadata.flag = flag
        if tentative {
            metadata.aiUnconfirmedFields = [.flag]
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

    private static func decidedAssets(picks: Int, rejects: Int) -> [Asset] {
        let pickAssets = (0..<picks).map { asset(id: "pick-\($0)", flag: .pick) }
        let rejectAssets = (0..<rejects).map { asset(id: "reject-\($0)", flag: .reject) }
        return pickAssets + rejectAssets
    }

    private static func snapshotAssetIDs(of assetSet: AssetSet) -> [AssetID] {
        guard case .snapshot(let assetIDs) = assetSet.membership else {
            return []
        }
        return assetIDs
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
