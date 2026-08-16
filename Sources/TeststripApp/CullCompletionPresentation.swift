import TeststripCore

/// The stage-replacing state shown in the cull loupe once nothing is left
/// undecided in the session: a handoff offering the next move (export,
/// relocate rejects, review picks, or save the picks as a set) instead of an
/// empty stage, plus the run's quality-of-coverage counts (skipped, never
/// viewed). Purely about the user's decisions — machine suggestions are
/// ambient and never nag from here.
struct CullCompletionPresentation: Equatable {
    enum Action: Equatable, Hashable {
        case export
        case moveRejects
        case moveRejectsToTrash
        case reviewPicks
        case savePicksAsSet
    }

    struct MiniRun: Equatable, Sendable {
        let number: Int    // 1-6, stable (the key the user presses)
        let label: String  // "Cull undecided", "Cull skipped", etc.
        let action: MiniRunAction

        enum MiniRunAction: Equatable, Sendable {
            case cullUndecided
            case cullSkipped
            case cullNeverViewed
            case reviewAI
            case export
            case moveRejects
        }
    }

    var picks: Int
    var rejects: Int
    var undecided: Int
    var skipped: Int
    var neverViewed: Int
    var actions: [Action]
    var awaitingReviewCount: Int = 0
    var miniRuns: [MiniRun] = []

    // SP-D Task 3: session-level fields for unification with
    // CullingSessionCompletionSummary. Populated when the completion fires
    // from a formal work session; nil/empty for the ad-hoc path.
    var sessionID: WorkSessionID?
    var title: String?
    var picksSetID: AssetSetID?
    var remainingSingleAssetIDs: [AssetID] = []

    /// The run-summary math, ungated: classifies every frame in the scope by
    /// its CONFIRMED flag — a tentative (AI-unconfirmed) flag counts as
    /// undecided and never as a pick/reject (the provenance invariant), so a
    /// scope still carrying a ghost is not complete and never reaches here.
    /// skipped = skipped ∖ decided (a skipped-then-decided frame counts as
    /// decided, subtracted here so the tracker never needs a write-back);
    /// neverViewed = scope ∖ viewed.
    static func summary(
        assets: [Asset],
        viewedAssetIDs: Set<AssetID>,
        skippedAssetIDs: Set<AssetID>,
        awaitingReviewCount: Int = 0
    ) -> CullCompletionPresentation {
        var pickCount = 0
        var rejectCount = 0
        var undecidedCount = 0
        var neverViewedCount = 0
        var decidedAssetIDs: Set<AssetID> = []
        for asset in assets {
            switch asset.metadata.confirmedProjection.flag {
            case .pick:
                pickCount += 1
                decidedAssetIDs.insert(asset.id)
            case .reject:
                rejectCount += 1
                decidedAssetIDs.insert(asset.id)
            case nil:
                undecidedCount += 1
            }
            if !viewedAssetIDs.contains(asset.id) {
                neverViewedCount += 1
            }
        }
        let scopeAssetIDs = Set(assets.map(\.id))
        let skippedCount = skippedAssetIDs
            .intersection(scopeAssetIDs)
            .subtracting(decidedAssetIDs)
            .count
        // The core four always; Save Picks only when it has work to do — a
        // Save Picks row with no picks would be a dead control.
        var actions: [Action] = [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks]
        if pickCount > 0 {
            actions.append(.savePicksAsSet)
        }
        let miniRuns = buildMiniRuns(
            undecided: undecidedCount,
            skipped: skippedCount,
            neverViewed: neverViewedCount,
            awaitingReview: awaitingReviewCount,
            rejects: rejectCount
        )
        return CullCompletionPresentation(
            picks: pickCount,
            rejects: rejectCount,
            undecided: undecidedCount,
            skipped: skippedCount,
            neverViewed: neverViewedCount,
            actions: actions,
            awaitingReviewCount: awaitingReviewCount,
            miniRuns: miniRuns
        )
    }

    /// Builds the completion state, or `nil` if there's still undecided work
    /// (or the session has no assets at all).
    ///
    /// `assets` is the session universe (the same in-memory array
    /// `CullScopeOrdering` navigates — see `AppModel.cullUndecidedCount`);
    /// undecided is counted session-wide from it. The `.picks`/`.rejects`
    /// scopes are review scopes, not deciding scopes: they exclude unflagged
    /// frames by definition, so completion is suppressed there — otherwise
    /// switching to them (including via the ReviewPicks action itself) would
    /// show "Nothing left to decide" instead of the frames being reviewed.
    static func presentation(
        assets: [Asset],
        viewedAssetIDs: Set<AssetID>,
        skippedAssetIDs: Set<AssetID>,
        scope: CullScope
    ) -> CullCompletionPresentation? {
        guard scope == .unrated || scope == .all else { return nil }
        guard !assets.isEmpty else { return nil }
        let summary = summary(
            assets: assets,
            viewedAssetIDs: viewedAssetIDs,
            skippedAssetIDs: skippedAssetIDs
        )
        guard summary.undecided == 0 else { return nil }
        return summary
    }

    /// Numbered one-key jumps for scoped mini-runs. Numbers are stable (1–6);
    /// entries with a zero count are omitted but the numbers never renumber.
    /// Export (5) is always available.
    private static func buildMiniRuns(
        undecided: Int,
        skipped: Int,
        neverViewed: Int,
        awaitingReview: Int,
        rejects: Int
    ) -> [MiniRun] {
        var runs: [MiniRun] = []
        if undecided > 0 {
            runs.append(MiniRun(number: 1, label: "Cull undecided", action: .cullUndecided))
        }
        if skipped > 0 {
            runs.append(MiniRun(number: 2, label: "Cull skipped", action: .cullSkipped))
        }
        if neverViewed > 0 {
            runs.append(MiniRun(number: 3, label: "Cull never-viewed", action: .cullNeverViewed))
        }
        if awaitingReview > 0 {
            runs.append(MiniRun(number: 4, label: "Review ✨", action: .reviewAI))
        }
        runs.append(MiniRun(number: 5, label: "Export", action: .export))
        if rejects > 0 {
            runs.append(MiniRun(number: 6, label: "Move rejects", action: .moveRejects))
        }
        return runs
    }
}
