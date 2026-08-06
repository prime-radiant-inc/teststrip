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

    var picks: Int
    var rejects: Int
    var undecided: Int
    var skipped: Int
    var neverViewed: Int
    var actions: [Action]

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
        skippedAssetIDs: Set<AssetID>
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
        return CullCompletionPresentation(
            picks: pickCount,
            rejects: rejectCount,
            undecided: undecidedCount,
            skipped: skippedCount,
            neverViewed: neverViewedCount,
            actions: actions
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
}
