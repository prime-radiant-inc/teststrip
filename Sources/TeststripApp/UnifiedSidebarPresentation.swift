import Foundation
import TeststripCore

/// One completed import, as the sidebar's Imports section sees it. Built from
/// the persisted `WorkSession` rather than `AppWorkActivity`, which drops both
/// dates — and from the unbounded `workSessions(kind:statuses:)` query rather
/// than the mixed-kind, limit-10 `recentWork` cache, which cannot promise
/// three imports.
///
/// Named `ImportSidebarSummary` rather than `ImportSourceSummary` because
/// `ImportConfirmationDraft.swift` already defines an unrelated
/// `ImportSourceSummary` (a pre-import folder scan), and `ImportCompletionSummary`
/// (the single-import banner) is also already taken.
public struct ImportSidebarSummary: Equatable, Sendable {
    public var sessionID: WorkSessionID
    public var createdAt: Date
    public var detail: String
    public var assetCount: Int
    public var issues: [WorkSessionIssue]

    public init(
        sessionID: WorkSessionID,
        createdAt: Date,
        detail: String,
        assetCount: Int,
        issues: [WorkSessionIssue]
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.detail = detail
        self.assetCount = assetCount
        self.issues = issues
    }

    /// An import's `title` and `intent` are both the constant "Import photos",
    /// so the row label is the session's date plus the source-folder text its
    /// `detail` carries — the only distinguishing field.
    public var title: String {
        let dateText = createdAt.formatted(.dateTime.month(.abbreviated).day())
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDetail.isEmpty ? dateText : "\(dateText) · \(trimmedDetail)"
    }
}

/// The counts behind an import row's disclosure children. `likelyIssues` and
/// `facesFound` are each the smart source's own `SetQuery` ANDed with
/// `.importBatch(sessionID)` — the shape `latestImportFlaggedReviewAssetCount`
/// already uses — so neither can drift from its catalog-wide sibling. The
/// other three are not `SetQuery`s: `stacks` comes from the stack-builder
/// pipeline scoped by `activityID`, `skippedFiles` from the session's stored
/// issue list, and `previewFailed` from `.count` of the same asset-ID list
/// the child row displays.
public struct ImportChildCounts: Equatable, Sendable {
    public var stacks: Int
    public var skippedFiles: Int
    public var previewFailed: Int
    public var likelyIssues: Int
    public var facesFound: Int

    public init(
        stacks: Int = 0,
        skippedFiles: Int = 0,
        previewFailed: Int = 0,
        likelyIssues: Int = 0,
        facesFound: Int = 0
    ) {
        self.stacks = stacks
        self.skippedFiles = skippedFiles
        self.previewFailed = previewFailed
        self.likelyIssues = likelyIssues
        self.facesFound = facesFound
    }

    /// Children render only with nonzero counts, so an all-zero import row
    /// simply has no disclosure triangle.
    public var isEmpty: Bool {
        stacks == 0 && skippedFiles == 0 && previewFailed == 0 && likelyIssues == 0 && facesFound == 0
    }
}
