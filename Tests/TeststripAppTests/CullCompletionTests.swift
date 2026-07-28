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
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertNil(presentation)
    }

    func testPresentationIsNilWhenSessionIsEmpty() {
        let presentation = CullCompletionPresentation.presentation(
            assets: [],
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [],
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
                pendingFlagProposalAssetIDs: [],
                pendingKeywordProposalAssetIDs: [],
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
                pendingFlagProposalAssetIDs: [],
                pendingKeywordProposalAssetIDs: [],
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
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [],
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
            pendingFlagProposalAssetIDs: [assets[5].id, AssetID(rawValue: "outside-scope")],
            pendingKeywordProposalAssetIDs: []
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

    // Mirrors the sparkleAwaiting out-of-scope exclusion above: a skip
    // recorded for an asset ID outside the completion scope (e.g. a frame
    // skipped in a previous cull run, or in another scope) must not inflate
    // `skipped` — skippedAssetIDs ∩ scope, same as pendingFlagProposalAssetIDs ∩ scope.
    func testSummarySkippedCountExcludesOutOfScopeAssetID() {
        let asset = Self.asset(id: "in-scope-not-skipped")
        let summary = CullCompletionPresentation.summary(
            assets: [asset],
            viewedAssetIDs: [],
            skippedAssetIDs: [AssetID(rawValue: "outside-scope")],
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: []
        )

        XCTAssertEqual(summary.skipped, 0)
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
                pendingFlagProposalAssetIDs: [asset.id],
                pendingKeywordProposalAssetIDs: []
            )
            XCTAssertEqual(summary.picks, 0, "flag \(flag)")
            XCTAssertEqual(summary.rejects, 0, "flag \(flag)")
            XCTAssertEqual(summary.undecided, 1, "flag \(flag)")
            XCTAssertEqual(summary.sparkleAwaiting, 1, "flag \(flag)")

            let presentation = CullCompletionPresentation.presentation(
                assets: [asset],
                viewedAssetIDs: [asset.id],
                skippedAssetIDs: [],
                pendingFlagProposalAssetIDs: [asset.id],
                pendingKeywordProposalAssetIDs: [],
                scope: .all
            )
            XCTAssertNil(presentation, "flag \(flag)")
        }
    }

    // MARK: - sparkleAwaiting filters user-decided assets at display time (Task 3)
    //
    // pendingFlagProposalAssetIDs/autopilot_proposals stay untouched — a proposal
    // can go stale (its asset gets a user-origin flag decision through some
    // other path than committing the proposal) and still sit there as
    // "pending". sparkleAwaiting must not count that asset as awaiting
    // review; it already has a decision.

    func testSparkleAwaitingExcludesAssetWithPendingProposalAndConfirmedFlag() {
        // The user decided the frame directly (e.g. P/X) after autopilot
        // proposed it; the proposal row is still pending, but a confirmed
        // (user-origin) flag means this asset is no longer genuinely
        // awaiting review.
        let decidedAfterProposal = Self.asset(id: "decided-after-proposal", flag: .pick)
        let summary = CullCompletionPresentation.summary(
            assets: [decidedAfterProposal],
            viewedAssetIDs: [decidedAfterProposal.id],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [decidedAfterProposal.id],
            pendingKeywordProposalAssetIDs: []
        )
        XCTAssertEqual(summary.sparkleAwaiting, 0)
        // The row's only pending asset is decided, so it correctly disappears.
        XCTAssertFalse(summary.actions.contains(.reviewAISuggestions))
    }

    func testSparkleAwaitingStillCountsAssetWithPendingProposalAndTentativeOnlyFlag() {
        // INVARIANT: a tentative (AI-unconfirmed) flag is not a decision —
        // the pending proposal still counts as genuinely awaiting review.
        let tentativePending = Self.asset(id: "tentative-pending", flag: .pick, tentative: true)
        let summary = CullCompletionPresentation.summary(
            assets: [tentativePending],
            viewedAssetIDs: [tentativePending.id],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [tentativePending.id],
            pendingKeywordProposalAssetIDs: []
        )
        XCTAssertEqual(summary.sparkleAwaiting, 1)
        XCTAssertTrue(summary.actions.contains(.reviewAISuggestions))
    }

    func testSparkleAwaitingCountsOnlyTheUserUndecidedSubsetOfPendingProposals() {
        // Mixed set: a user-decided asset (excluded), a tentative-only
        // asset (still counted), and a never-flagged asset (still counted)
        // — sparkleAwaiting is exactly the undecided-pending subset, 2 of 3.
        let decided = Self.asset(id: "decided", flag: .reject)
        let tentative = Self.asset(id: "tentative", flag: .pick, tentative: true)
        let neverFlagged = Self.asset(id: "never-flagged")
        let summary = CullCompletionPresentation.summary(
            assets: [decided, tentative, neverFlagged],
            viewedAssetIDs: [decided.id, tentative.id, neverFlagged.id],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [decided.id, tentative.id, neverFlagged.id],
            pendingKeywordProposalAssetIDs: []
        )
        XCTAssertEqual(summary.sparkleAwaiting, 2)
    }

    // MARK: - sparkleAwaiting is kind-aware (Finding 1, 2026-07-28)
    //
    // AutopilotProposalKind has three cases: .pick, .reject (flag proposals)
    // and .keyword. A pending keyword proposal has nothing to do with the
    // flag decision — it's a wholly separate piece of unreviewed AI output —
    // so it must count toward sparkleAwaiting regardless of whether the
    // asset's flag is already user-confirmed. A pending flag proposal keeps
    // the original Task 3 filter: excluded once the flag is user-confirmed.

    func testSparkleAwaitingCountsPendingKeywordProposalEvenWithConfirmedFlag() {
        // Pre-fix, a single kind-blind proposal set hid this asset's pending
        // keyword proposal too, once its flag was confirmed — even though
        // the keyword suggestion is still genuinely unreviewed.
        let confirmedWithKeywordProposal = Self.asset(id: "confirmed-keyword-pending", flag: .pick)
        let summary = CullCompletionPresentation.summary(
            assets: [confirmedWithKeywordProposal],
            viewedAssetIDs: [confirmedWithKeywordProposal.id],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [confirmedWithKeywordProposal.id]
        )
        XCTAssertEqual(summary.sparkleAwaiting, 1)
        XCTAssertTrue(summary.actions.contains(.reviewAISuggestions))
    }

    func testSparkleAwaitingStillExcludesPendingFlagProposalWithConfirmedFlag() {
        // The original Task 3 fix must hold under the kind-aware split: a
        // pending *flag* proposal (.pick/.reject) is excluded once the flag
        // itself is user-confirmed.
        let confirmedWithFlagProposal = Self.asset(id: "confirmed-flag-pending", flag: .pick)
        let summary = CullCompletionPresentation.summary(
            assets: [confirmedWithFlagProposal],
            viewedAssetIDs: [confirmedWithFlagProposal.id],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [confirmedWithFlagProposal.id],
            pendingKeywordProposalAssetIDs: []
        )
        XCTAssertEqual(summary.sparkleAwaiting, 0)
        XCTAssertFalse(summary.actions.contains(.reviewAISuggestions))
    }

    func testSparkleAwaitingCountsMixedFlagAndKeywordProposalsExactly() {
        // Three assets: a confirmed flag with a stale pending flag proposal
        // (excluded), a confirmed flag with a pending keyword proposal
        // (counted — a keyword proposal ignores the flag decision), and an
        // undecided asset with a pending flag proposal (counted, same as
        // before Finding 1). Exact count: 2 of 3.
        let confirmedFlagStale = Self.asset(id: "confirmed-flag-stale", flag: .reject)
        let confirmedWithKeyword = Self.asset(id: "confirmed-with-keyword", flag: .pick)
        let undecidedWithFlagProposal = Self.asset(id: "undecided-with-flag-proposal")
        let summary = CullCompletionPresentation.summary(
            assets: [confirmedFlagStale, confirmedWithKeyword, undecidedWithFlagProposal],
            viewedAssetIDs: [confirmedFlagStale.id, confirmedWithKeyword.id, undecidedWithFlagProposal.id],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [confirmedFlagStale.id, undecidedWithFlagProposal.id],
            pendingKeywordProposalAssetIDs: [confirmedWithKeyword.id]
        )
        XCTAssertEqual(summary.sparkleAwaiting, 2)
    }

    func testPresentationCarriesRunCountsWhenComplete() {
        // Fully decided scope: a0 pick (viewed; also carries a pending
        // autopilot proposal, but the flag is already user-confirmed — the
        // proposal went stale rather than tracking the direct decision, so
        // a0 is excluded from sparkleAwaiting), a1 reject (skipped then
        // decided), a2 pick (never viewed).
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
            Self.asset(id: "a2", flag: .pick)
        ]
        let presentation = CullCompletionPresentation.presentation(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: [assets[1].id],
            pendingFlagProposalAssetIDs: [assets[0].id],
            pendingKeywordProposalAssetIDs: [],
            scope: .all
        )

        XCTAssertEqual(presentation?.picks, 2)
        XCTAssertEqual(presentation?.rejects, 1)
        XCTAssertEqual(presentation?.undecided, 0)
        XCTAssertEqual(presentation?.skipped, 0)
        XCTAssertEqual(presentation?.neverViewed, 1)
        XCTAssertEqual(presentation?.sparkleAwaiting, 0)
    }

    // MARK: - Actions

    func testActionsAreCoreFourWhenNoPicksAndNoPendingSuggestions() {
        let presentation = CullCompletionPresentation.presentation(
            assets: Self.decidedAssets(picks: 0, rejects: 2),
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertEqual(presentation?.actions, [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks])
    }

    func testActionsAppendSavePicksWhenApplicable() {
        let assets = Self.decidedAssets(picks: 1, rejects: 1)
        let presentation = CullCompletionPresentation.presentation(
            assets: assets,
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertEqual(
            presentation?.actions,
            [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks, .savePicksAsSet]
        )
    }

    func testActionsOmitReviewAISuggestionsWhenTheOnlyPendingAssetIsUserDecided() {
        // assets[0] (a confirmed pick) carries a pending proposal that went
        // stale — the user decided it directly rather than via the proposal
        // review flow. It's the only pending asset, so the row disappears.
        let assets = Self.decidedAssets(picks: 1, rejects: 1)
        let presentation = CullCompletionPresentation.presentation(
            assets: assets,
            viewedAssetIDs: [],
            skippedAssetIDs: [],
            pendingFlagProposalAssetIDs: [assets[0].id],
            pendingKeywordProposalAssetIDs: [],
            scope: .all
        )
        XCTAssertEqual(
            presentation?.actions,
            [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks, .savePicksAsSet]
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
            pendingFlagProposalAssetIDs: [],
            pendingKeywordProposalAssetIDs: [],
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

    // Distinct code path from the ad-hoc throw above: with an ACTIVE session,
    // saveCullingPicksAsSet goes through refreshCullingSessionOutputSet's
    // no-picks arm (which deletes/never creates the output set) before the
    // `guard let outputSet = savedAssetSets.first(...)` throw fires.
    func testSaveCullingPicksAsSetInActiveSessionThrowsWhenNoConfirmedPicksExist() throws {
        let unflagged = Self.asset(id: "session-throw-unflagged")
        let tentative = Self.asset(id: "session-throw-tentative", flag: .pick, tentative: true)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "save-picks-session-throw",
            assets: [unflagged, tentative]
        )
        try model.beginCullingSession(named: "Batch")

        // INVARIANT: same as the ad-hoc case — a tentative flag never drives
        // the committing picks-set operation, even with a session active.
        // (beginCullingSession persists its own "Batch Input" set, so
        // assertion is on the absent output/picks set, not overall emptiness.)
        XCTAssertThrowsError(try model.saveCullingPicksAsSet())
        XCTAssertTrue(try repository.assetSets().allSatisfy { !$0.name.hasSuffix("Picks") })
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
