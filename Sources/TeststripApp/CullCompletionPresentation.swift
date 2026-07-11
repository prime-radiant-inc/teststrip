import TeststripCore

/// The stage-replacing state shown in the cull loupe once nothing is left
/// undecided in the session: a handoff offering the next move (export,
/// relocate rejects, or review picks) instead of an empty stage.
struct CullCompletionPresentation: Equatable {
    enum Action: Equatable, Hashable {
        case export
        case moveRejects
        case moveRejectsToTrash
        case reviewPicks
    }

    var picks: Int
    var rejects: Int
    var actions: [Action]

    /// Builds the completion state, or `nil` if there's still undecided work
    /// (or the session has no assets at all).
    ///
    /// `undecidedCount` is the count of unflagged frames in the session —
    /// see `AppModel.cullUndecidedCount`. The `.picks`/`.rejects` scopes are
    /// review scopes, not deciding scopes: they exclude unflagged frames by
    /// definition, so completion is suppressed there — otherwise switching
    /// to them (including via the ReviewPicks action itself) would show
    /// "Nothing left to decide" instead of the frames being reviewed.
    static func presentation(
        pickCount: Int,
        rejectCount: Int,
        totalCount: Int,
        undecidedCount: Int,
        scope: CullScope
    ) -> CullCompletionPresentation? {
        guard scope == .unrated || scope == .all else { return nil }
        guard totalCount > 0, undecidedCount == 0 else { return nil }
        return CullCompletionPresentation(
            picks: pickCount,
            rejects: rejectCount,
            actions: [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks]
        )
    }
}
