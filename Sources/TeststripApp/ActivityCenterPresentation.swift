import TeststripCore

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

/// One aggregate progress row per active work kind in the Activity Center,
/// rolling every in-flight item of that kind into a single bar.
public struct ActivityKindRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var title: String
    public var detail: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var status: WorkSessionStatus
    public var activeItemCount: Int
    public var canPause: Bool
    public var canResume: Bool
    public var canCancel: Bool

    public static func title(for kind: WorkSessionKind) -> String {
        switch kind {
        case .ingest: "Import photos"
        case .previewGeneration: "Generate previews"
        case .recognition: "Evaluate photos"
        case .xmpSync: "Sync sidecars"
        case .sourceScan: "Check sources"
        case .geocoding: "Find places"
        case .locationBackfill: "Backfill locations"
        case .culling: "Culling"
        case .collecting: "Collecting"
        case .searchSort: "Sorting"
        case .keywording: "Keywording"
        case .export: "Export"
        case .relocation: "Relocating"
        }
    }

    // Running outranks paused outranks queued outranks completed/failed.
    private static let statusRank: [WorkSessionStatus: Int] = [
        .running: 5, .paused: 4, .queued: 3, .completed: 2, .failed: 1, .cancelled: 0,
    ]

    public static func rows(
        from activities: [AppWorkActivity],
        canPause: Bool,
        canResume: Bool
    ) -> [ActivityKindRow] {
        var order: [WorkSessionKind] = []
        var byKind: [WorkSessionKind: [AppWorkActivity]] = [:]
        for activity in activities {
            if byKind[activity.kind] == nil { order.append(activity.kind) }
            byKind[activity.kind, default: []].append(activity)
        }
        return order.map { kind in
            let items = byKind[kind]!
            let dominant = items.max { (statusRank[$0.status] ?? 0) < (statusRank[$1.status] ?? 0) }!
            let totals = items.compactMap(\.totalUnitCount)
            let total = totals.count == items.count ? totals.reduce(0, +) : nil
            let running = items.first { $0.status == .running }
            return ActivityKindRow(
                id: kind.rawValue,
                kind: kind,
                title: title(for: kind),
                detail: (running ?? dominant).detail,
                completedUnitCount: items.map(\.completedUnitCount).reduce(0, +),
                totalUnitCount: total,
                status: dominant.status,
                activeItemCount: items.count,
                canPause: canPause,
                canResume: canResume,
                canCancel: items.contains { [.queued, .running, .paused].contains($0.status) }
            )
        }
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
    public var kindRows: [ActivityKindRow]
    public var importProgress: ImportProgressRow?
    public var importError: String?
    public var sources: [SourceStatusRow]
    public var xmpConflicts: [ConflictRow]

    public init(
        kindRows: [ActivityKindRow],
        importActivity: AppWorkActivity?,
        importError: String?,
        sources: [SourceStatusRow],
        xmpConflicts: [ConflictRow],
        providerFailureCount: Int
    ) {
        self.kindRows = kindRows
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
        let hasActiveKindRow = kindRows.contains { isActive($0.status) }
        let hasActiveImport = importActivity.map { isActive($0.status) } ?? false
        self.isWorking = hasActiveKindRow || hasActiveImport
    }
}
