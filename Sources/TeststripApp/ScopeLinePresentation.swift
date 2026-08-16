import Foundation
import TeststripCore

/// The persistent line under the toolbar: what you are looking at, and
/// lens-appropriate status about it. Pure value logic — the view is a thin
/// shell over this.
public struct ScopeLinePresentation: Equatable, Sendable {
    public var sourceTitle: String
    public var statusText: String

    public init(sourceTitle: String, statusText: String) {
        self.sourceTitle = sourceTitle
        self.statusText = statusText
    }

    public static func line(
        source: LibrarySource,
        lens: LibraryLens,
        resultCount: Int,
        activeFilterChips: [String],
        cullProgress: CullingProgressSummary?,
        stackCount: Int,
        skippedCount: Int = 0,
        neverViewedCount: Int = 0,
        awaitingReviewCount: Int = 0,
        hiddenByLensCount: Int = 0
    ) -> ScopeLinePresentation {
        ScopeLinePresentation(
            sourceTitle: source.title,
            statusText: lens == .cull
                ? cullStatusText(
                    resultCount: resultCount,
                    cullProgress: cullProgress,
                    stackCount: stackCount,
                    skippedCount: skippedCount,
                    neverViewedCount: neverViewedCount,
                    awaitingReviewCount: awaitingReviewCount,
                    hiddenByLensCount: hiddenByLensCount
                )
                : browseStatusText(resultCount: resultCount, activeFilterChips: activeFilterChips)
        )
    }

    private static func photoCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func browseStatusText(resultCount: Int, activeFilterChips: [String]) -> String {
        let count = photoCountText(resultCount)
        guard !activeFilterChips.isEmpty else { return count }
        return "\(count) · \(activeFilterChips.joined(separator: " + "))"
    }

    /// "854 photos · 326 stacks · ✓ 15 · ✕ 5 · ⊘ 12 skipped · ◌ 3 unviewed ·
    /// ✨ 96 awaiting · 834 left". The stack segment is omitted when the run has
    /// no multi-frame stacks, and the whole progress tail is omitted when no
    /// run is under way. Skipped, unviewed, and awaiting segments are omitted
    /// when their count is zero.
    private static func cullStatusText(
        resultCount: Int,
        cullProgress: CullingProgressSummary?,
        stackCount: Int,
        skippedCount: Int = 0,
        neverViewedCount: Int = 0,
        awaitingReviewCount: Int = 0,
        hiddenByLensCount: Int = 0
    ) -> String {
        guard let cullProgress else { return photoCountText(resultCount) }
        var segments = [photoCountText(cullProgress.totalCount)]
        if stackCount > 0 {
            segments.append("\(stackCount) \(stackCount == 1 ? "stack" : "stacks")")
        }
        segments.append("✓ \(cullProgress.pickCount)")
        segments.append("✕ \(cullProgress.rejectCount)")
        if skippedCount > 0 {
            segments.append("⊘ \(skippedCount) skipped")
        }
        if neverViewedCount > 0 {
            segments.append("◌ \(neverViewedCount) unviewed")
        }
        if awaitingReviewCount > 0 {
            segments.append("✨ \(awaitingReviewCount) awaiting")
        }
        segments.append("\(max(cullProgress.totalCount - cullProgress.reviewedCount, 0)) left")
        return segments.joined(separator: " · ")
    }
}
