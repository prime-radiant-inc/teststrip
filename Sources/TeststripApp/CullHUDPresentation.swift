import TeststripCore

/// The single-row cull HUD replacing the old header pills and command rail:
/// filename, rating, color label, progress, undecided count, picks/rejects,
/// and the assist verdict text — all in one strip over the stage.
struct CullHUDPresentation: Equatable {
    var filename: String
    var rating: Int
    var colorLabel: ColorLabel?
    var progressFraction: Double
    var undecidedCount: Int
    var pickCount: Int
    var rejectCount: Int
    var verdict: String?
    var scope: CullScope

    init(
        filename: String,
        rating: Int,
        colorLabel: ColorLabel?,
        summary: CullingProgressSummary,
        verdict: String?,
        scope: CullScope = .all
    ) {
        self.filename = filename
        self.rating = rating
        self.colorLabel = colorLabel
        self.pickCount = summary.pickCount
        self.rejectCount = summary.rejectCount
        self.undecidedCount = max(summary.totalCount - summary.pickCount - summary.rejectCount, 0)
        self.progressFraction = summary.totalCount > 0
            ? Double(summary.reviewedCount) / Double(summary.totalCount)
            : 0
        self.verdict = verdict
        self.scope = scope
    }
}
