import TeststripCore

/// A background work row in the Activity Center, wrapping an `AppWorkActivity`
/// with the control availability flags that gate the star/pause/resume/cancel
/// buttons in `ActivityView`.
public struct ActivityJobRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var activity: AppWorkActivity
    public var canStar: Bool
    public var canPause: Bool
    public var canResume: Bool
    public var canCancel: Bool

    public init(
        activity: AppWorkActivity,
        canStar: Bool,
        canPause: Bool,
        canResume: Bool,
        canCancel: Bool
    ) {
        self.id = activity.id
        self.activity = activity
        self.canStar = canStar
        self.canPause = canPause
        self.canResume = canResume
        self.canCancel = canCancel
    }
}

/// Presentation for the active import's progress, surfaced in the Activity
/// Center's import row.
public struct ImportProgressRow: Equatable, Sendable {
    public var phaseLabel: String
    public var fraction: Double?
    public var cancelActionID: String

    public init(activity: AppWorkActivity) {
        self.phaseLabel = Self.phaseLabel(for: activity.status)
        if let total = activity.totalUnitCount, total > 0 {
            self.fraction = Double(activity.completedUnitCount) / Double(total)
        } else {
            self.fraction = nil
        }
        self.cancelActionID = activity.id
    }

    private static func phaseLabel(for status: WorkSessionStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .running: "Importing"
        case .paused: "Paused"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// A source root's availability, surfaced in the Activity Center's sources
/// list with the reconnect/refresh actions available for it.
public struct SourceStatusRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var availability: SourceAvailability
    public var reconnectActionID: String?
    public var refreshActionID: String?

    public init(
        id: String,
        name: String,
        availability: SourceAvailability,
        reconnectActionID: String? = nil,
        refreshActionID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.availability = availability
        self.reconnectActionID = reconnectActionID
        self.refreshActionID = refreshActionID
    }
}

/// An asset with a pending XMP sidecar conflict, surfaced in the Activity
/// Center with a deep-link payload back to the asset.
public struct ConflictRow: Equatable, Identifiable, Sendable {
    public var assetID: AssetID
    public var displayName: String

    public var id: String { assetID.rawValue }

    public init(assetID: AssetID, displayName: String) {
        self.assetID = assetID
        self.displayName = displayName
    }
}

/// Aggregates the four status subsystems (background work, import,
/// source availability, XMP sync) that the toolbar's Activity Center popover
/// surfaces in one place. A pure function of value inputs: it holds no
/// reference to `AppModel`, so callers snapshot the fields they need.
public struct ActivityCenterPresentation: Equatable {
    public enum Badge: Equatable {
        case none
        case problems(Int)
    }

    public var badge: Badge
    public var isWorking: Bool
    public var jobs: [ActivityJobRow]
    public var importProgress: ImportProgressRow?
    public var importError: String?
    public var sources: [SourceStatusRow]
    public var xmpConflicts: [ConflictRow]

    public init(
        jobs: [ActivityJobRow],
        importActivity: AppWorkActivity?,
        importError: String?,
        sources: [SourceStatusRow],
        xmpConflicts: [ConflictRow],
        providerFailureCount: Int
    ) {
        self.jobs = jobs
        self.importProgress = importActivity.map(ImportProgressRow.init(activity:))
        self.importError = importError
        self.sources = sources
        self.xmpConflicts = xmpConflicts

        let unavailableSourceCount = sources.filter { $0.availability != .online }.count
        let problemCount = xmpConflicts.count + unavailableSourceCount + providerFailureCount
        self.badge = problemCount > 0 ? .problems(problemCount) : .none

        func isActive(_ status: WorkSessionStatus) -> Bool {
            status == .running || status == .queued
        }
        let hasActiveJob = jobs.contains { isActive($0.activity.status) }
        let hasActiveImport = importActivity.map { isActive($0.status) } ?? false
        self.isWorking = hasActiveJob || hasActiveImport
    }
}
