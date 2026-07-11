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
    /// True while a rating keystroke's decision-toast echo window (2s) is
    /// still open for this frame, even if the resulting rating is 0.
    var isRatingEchoActive: Bool

    init(
        filename: String,
        rating: Int,
        colorLabel: ColorLabel?,
        summary: CullingProgressSummary,
        verdict: String?,
        scope: CullScope = .all,
        isRatingEchoActive: Bool = false
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
        self.isRatingEchoActive = isRatingEchoActive
    }

    /// Scope chip only carries information once the session is scoped down
    /// from "All".
    var showsScopeChip: Bool { scope != .all }

    /// Rating stars only carry information when the frame has a rating, or
    /// a rating key was just pressed (mirrors the decision-toast echo).
    var showsRating: Bool { rating > 0 || isRatingEchoActive }

    /// Label dot only renders once a color label is actually set.
    var showsLabelDot: Bool { colorLabel != nil }

    /// Merged pick/reject/undecided session cluster, e.g. "✓ 38 · ✕ 71 · 209 left".
    var sessionClusterText: String {
        "\u{2713} \(pickCount) \u{00B7} \u{2715} \(rejectCount) \u{00B7} \(undecidedCount) left"
    }
}
