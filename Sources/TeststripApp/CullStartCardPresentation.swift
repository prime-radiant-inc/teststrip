import Foundation

/// Pure presentation type for the ⌘R start card (SP-D Task 4, tutorial §2).
/// Shows batch stats (photo count, stack count, burst percentage), a lens
/// selector with loud narrowing accounting, and Auto-advance + Land-on-
/// recommended toggles. The view code lives in `LibraryGridView`.
struct CullStartCardPresentation: Equatable {
    var photoCount: Int
    var stackCount: Int
    var lensHiddenCount: Int = 0
    var autoAdvanceEnabled: Bool = true
    var landOnRecommended: Bool = true

    /// `stackCount / photoCount * 100`, rounded to the nearest integer.
    var burstPercentage: Int {
        guard photoCount > 0 else { return 0 }
        return Int((Double(stackCount) / Double(photoCount) * 100).rounded())
    }

    /// `"211 photos · 63 stacks (batch is 30% bursts)"` — the tutorial §2
    /// format. Omits the burst annotation when there are no stacks.
    var batchDescription: String {
        let photos = "\(photoCount) \(photoCount == 1 ? "photo" : "photos")"
        let stacks = "\(stackCount) \(stackCount == 1 ? "stack" : "stacks")"
        if burstPercentage > 0 {
            return "\(photos) · \(stacks) (batch is \(burstPercentage)% bursts)"
        }
        return "\(photos) · \(stacks)"
    }

    /// `"Showing 96 of 211 — 115 hidden by lens"` when a lens narrows the run
/// (tutorial §2). `nil` when the lens shows everything.
    var lensDescription: String? {
        guard lensHiddenCount > 0 else { return nil }
        let shown = photoCount - lensHiddenCount
        return "Showing \(shown) of \(photoCount) — \(lensHiddenCount) hidden by lens"
    }
}
