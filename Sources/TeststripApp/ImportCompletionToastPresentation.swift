import Foundation
import TeststripCore

/// The completion moment: one thin capsule, top-right, that fades after ~10s
/// (or on click/dismiss) and docks into the Activity Center bell as the
/// receipt. It replaces the post-import banner's headline, four metric tiles,
/// and nine action buttons — whose nine actions collapsed to four intents,
/// three of which were different doors into culling the same set.
public struct ImportCompletionToastPresentation: Equatable, Sendable {
    /// ~10s, then the bell keeps the full receipt.
    public static let visibleDuration: TimeInterval = 10

    public var summaryID: String
    public var sessionID: WorkSessionID
    public var headline: String
    public var warningText: String?
    public var showsStartCulling: Bool
    public var cullingSessionName: String

    public init(
        summaryID: String,
        sessionID: WorkSessionID,
        headline: String,
        warningText: String?,
        showsStartCulling: Bool,
        cullingSessionName: String
    ) {
        self.summaryID = summaryID
        self.sessionID = sessionID
        self.headline = headline
        self.warningText = warningText
        self.showsStartCulling = showsStartCulling
        self.cullingSessionName = cullingSessionName
    }

    /// The optional return *is* the gating decision, expressed as data.
    /// Session-scoped on purpose: a summary restored from persisted work
    /// history must never resurrect the toast on relaunch (persona-7's zombie
    /// panel, which `app-006` tests for).
    public static func toast(
        for summary: ImportCompletionSummary?,
        isCurrentSessionActivity: Bool,
        isImporting: Bool
    ) -> ImportCompletionToastPresentation? {
        guard let summary, isCurrentSessionActivity, !isImporting else { return nil }
        let skippedCount = summary.issues.filter { $0.kind == .skippedSourceFile }.count
        let isExistingOnly = summary.newPhotoCount == 0 && summary.existingPhotoCount > 0
        return ImportCompletionToastPresentation(
            summaryID: summary.id,
            sessionID: WorkSessionID(rawValue: summary.activityID),
            headline: isExistingOnly
                ? "No new photos imported — \(summary.existingPhotoCount) already in catalog"
                : "Imported \(summary.photoCountText)",
            warningText: skippedCount > 0
                ? "\(skippedCount) \(skippedCount == 1 ? "file" : "files") skipped"
                : nil,
            showsStartCulling: !isExistingOnly && summary.newPhotoCount > 0,
            cullingSessionName: summary.cullingSessionName
        )
    }
}

/// A completed import, archived in the Activity Center bell. The fifth item
/// family: the first four (work kinds, import progress, sources, XMP
/// conflicts) are all about work in flight or problems; this one is history.
public struct ImportReceiptRow: Equatable, Identifiable, Sendable {
    /// How many receipts the bell keeps. Older imports stay reachable through
    /// the sidebar's Imports section, which is unbounded.
    public static let retentionLimit = 5

    public var id: String
    public var sessionID: WorkSessionID
    public var title: String
    public var detail: String
    public var issueCount: Int
    public var canStartCulling: Bool

    public init(
        id: String,
        sessionID: WorkSessionID,
        title: String,
        detail: String,
        issueCount: Int,
        canStartCulling: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.detail = detail
        self.issueCount = issueCount
        self.canStartCulling = canStartCulling
    }

    public static func rows(from activities: [AppWorkActivity], limit: Int) -> [ImportReceiptRow] {
        activities
            .filter { $0.kind == .ingest && $0.status == .completed }
            .prefix(limit)
            .map { activity in
                let skippedCount = activity.issues.filter { $0.kind == .skippedSourceFile }.count
                return ImportReceiptRow(
                    id: activity.id,
                    sessionID: WorkSessionID(rawValue: activity.id),
                    title: activity.detail.isEmpty ? "Import complete" : activity.detail,
                    detail: skippedCount > 0
                        ? "\(skippedCount) \(skippedCount == 1 ? "file" : "files") skipped"
                        : "",
                    issueCount: skippedCount,
                    canStartCulling: activity.completedUnitCount > 0
                )
            }
    }
}
