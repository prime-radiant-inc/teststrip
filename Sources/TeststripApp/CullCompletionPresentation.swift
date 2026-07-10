import TeststripCore

/// The stage-replacing state shown in the cull loupe once nothing is left
/// undecided in the current `CullScope`: a handoff offering the next move
/// (export, relocate rejects, or review picks) instead of an empty stage.
struct CullCompletionPresentation: Equatable {
    enum Action: Equatable, Hashable {
        case export
        case moveRejects
        case reviewPicks
    }

    var picks: Int
    var rejects: Int
    var actions: [Action]

    /// Builds the completion state, or `nil` if there's still undecided work
    /// in the current scope (or the session has no assets at all).
    ///
    /// `scopedUndecidedCount` must be counted against the current `CullScope`
    /// filter, not the whole session — see `AppModel.scopedUndecidedCount`.
    static func presentation(
        pickCount: Int,
        rejectCount: Int,
        totalCount: Int,
        scopedUndecidedCount: Int
    ) -> CullCompletionPresentation? {
        guard totalCount > 0, scopedUndecidedCount == 0 else { return nil }
        return CullCompletionPresentation(
            picks: pickCount,
            rejects: rejectCount,
            actions: [.export, .moveRejects, .reviewPicks]
        )
    }
}
