import Foundation
import Observation
import TeststripCore

public enum LibraryViewMode: String, Sendable {
    case grid
    case search
    case copilot
    case loupe
    case compare
    case timeline
    case map
    case people
}

public enum CompareGroupKind: Equatable, Sendable {
    case nearbyFrames
    case candidateStack
}

public enum CullingCommand: Equatable, Sendable {
    case rating(Int)
    case colorLabel(ColorLabel?)
    case pick
    case reject
    case clearFlag
}

public struct CullingProgressSummary: Equatable, Sendable {
    public var selectedPosition: Int?
    public var positionText: String?
    public var pickCount: Int
    public var rejectCount: Int
    public var totalCount: Int

    public var reviewedCount: Int {
        pickCount + rejectCount
    }

    public init(selectedPosition: Int?, positionText: String?, pickCount: Int, rejectCount: Int, totalCount: Int) {
        self.selectedPosition = selectedPosition
        self.positionText = positionText
        self.pickCount = pickCount
        self.rejectCount = rejectCount
        self.totalCount = totalCount
    }
}

public enum CullingShortcut: Equatable, Sendable {
    case previousPhoto
    case nextPhoto
    case previousStack
    case nextStack
    case rating(Int)
    case colorLabel(ColorLabel?)
    case pick
    case reject
    case clearFlag
    case acceptStackSelection

    public init?(key: CullingShortcutKey) {
        switch key {
        case .leftArrow:
            self = .previousPhoto
        case .rightArrow:
            self = .nextPhoto
        case .upArrow:
            self = .previousStack
        case .downArrow:
            self = .nextStack
        case .returnKey:
            self = .acceptStackSelection
        case .character(let character):
            switch character.lowercased() {
            case " ": self = .nextPhoto
            case "0": self = .rating(0)
            case "1": self = .rating(1)
            case "2": self = .rating(2)
            case "3": self = .rating(3)
            case "4": self = .rating(4)
            case "5": self = .rating(5)
            case "6": self = .colorLabel(.red)
            case "7": self = .colorLabel(.yellow)
            case "8": self = .colorLabel(.green)
            case "9": self = .colorLabel(.blue)
            case "v": self = .colorLabel(.purple)
            case "-": self = .colorLabel(nil)
            case "p": self = .pick
            case "x": self = .reject
            case "u": self = .clearFlag
            default: return nil
            }
        }
    }
}

public enum CullingShortcutKey: Equatable, Sendable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case returnKey
    case character(String)
}

private enum CullingStackNavigationDirection {
    case previous
    case next
}

private struct IndexedCullingStack {
    var stack: AssetStack
    var firstIndex: Int
    var lastIndex: Int

    var firstAssetID: AssetID? {
        stack.assetIDs.first
    }
}

public enum ReviewQueue: String, Equatable, Hashable, Sendable {
    case picks
    case rejects
    case fiveStars
    case needsKeywords
    case needsEvaluation
    case facesFound
    case ocrFound
    case likelyIssues
    case providerFailures
}

extension EvaluationKind {
    var displayName: String {
        switch self {
        case .focus:
            return "Focus"
        case .motionBlur:
            return "Motion Blur"
        case .exposure:
            return "Exposure"
        case .aesthetics:
            return "Aesthetics"
        case .object:
            return "Object"
        case .faceCount:
            return "Face Count"
        case .faceQuality:
            return "Face Quality"
        case .ocrText:
            return "OCR Text"
        case .colorPalette:
            return "Color Palette"
        case .novelty:
            return "Novelty"
        }
    }
}

public enum SidebarRowTarget: Equatable, Sendable {
    case allPhotographs
    case search
    case copilot
    case timeline
    case people
    case placeholder
    case reviewQueue(ReviewQueue)
    case folder(String)
    case sourceAvailability(SourceAvailability)
    case evaluationKind(EvaluationKind)
    case metadataSyncPending
    case metadataSyncConflicts
    case assetSet(AssetSetID)
    case workSession(WorkSessionID)
}

public enum SidebarRowContextActionKind: Equatable, Sendable {
    case toggleAssetSetStarred(AssetSetID)
    case toggleWorkSessionStarred(WorkSessionID)
}

public struct SidebarRowContextAction: Identifiable, Equatable, Sendable {
    public var kind: SidebarRowContextActionKind
    public var title: String
    public var systemImage: String

    public var id: String {
        switch kind {
        case .toggleAssetSetStarred(let id):
            return "toggle-asset-set-starred-\(id.rawValue)"
        case .toggleWorkSessionStarred(let id):
            return "toggle-work-session-starred-\(id.rawValue)"
        }
    }

    public init(kind: SidebarRowContextActionKind, title: String, systemImage: String) {
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
    }
}

public struct SidebarRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detailText: String?
    public var countText: String?
    public var tone: SidebarRowTone
    public var target: SidebarRowTarget
    public var liveMockupPlaceholder: LiveMockupPlaceholder?

    public init(
        id: String,
        title: String,
        detailText: String? = nil,
        countText: String? = nil,
        tone: SidebarRowTone = .neutral,
        target: SidebarRowTarget = .placeholder,
        liveMockupPlaceholder: LiveMockupPlaceholder? = nil
    ) {
        self.id = id
        self.title = title
        self.detailText = detailText
        self.countText = countText
        self.tone = tone
        self.target = target
        self.liveMockupPlaceholder = liveMockupPlaceholder
    }

    public var isSelectable: Bool {
        target != .placeholder
    }
}

public struct ActiveLibraryFilterRow: Identifiable, Equatable, Sendable {
    public var title: String
    public var target: SidebarRowTarget?

    public var id: String { title }

    public init(title: String, target: SidebarRowTarget? = nil) {
        self.title = title
        self.target = target
    }
}

public enum SidebarRowTone: String, Equatable, Sendable {
    case neutral
    case accent
    case positive
    case warning
    case destructive
}

public struct SidebarSection: Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var rows: [SidebarRow]

    public var rowTitles: [String] {
        rows.map(\.title)
    }

    public init(title: String, rows: [String]) {
        self.title = title
        let sectionTitle = title
        self.rows = rows.enumerated().map { index, title in
            SidebarRow(id: "\(sectionTitle)-\(index)-\(title)", title: title)
        }
    }

    public init(title: String, rows: [SidebarRow]) {
        self.title = title
        self.rows = rows
    }
}

public struct CatalogSourceAvailabilitySummary: Equatable, Sendable {
    public var availability: SourceAvailability
    public var assetCount: Int

    public init(availability: SourceAvailability, assetCount: Int) {
        self.availability = availability
        self.assetCount = assetCount
    }
}

public struct AppDiagnosticsSourceRoot: Equatable, Sendable {
    public var path: String
    public var name: String
    public var assetCount: Int
    public var unavailableAssetCount: Int

    public init(path: String, name: String, assetCount: Int, unavailableAssetCount: Int) {
        self.path = path
        self.name = name
        self.assetCount = assetCount
        self.unavailableAssetCount = unavailableAssetCount
    }
}

public struct AppDiagnosticsWorkStatusCount: Equatable, Sendable {
    public var status: WorkSessionStatus
    public var count: Int

    public init(status: WorkSessionStatus, count: Int) {
        self.status = status
        self.count = count
    }
}

public struct AppDiagnosticsWorkKindCount: Equatable, Sendable {
    public var kind: WorkSessionKind
    public var count: Int

    public init(kind: WorkSessionKind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

public struct AppDiagnosticsSourceAvailabilityCount: Equatable, Sendable {
    public var availability: SourceAvailability
    public var count: Int

    public init(availability: SourceAvailability, count: Int) {
        self.availability = availability
        self.count = count
    }
}

public struct AppDiagnosticsBackgroundWork: Equatable, Sendable {
    public var maxRunningCount: Int
    public var kindRunningLimits: [AppDiagnosticsWorkKindCount]
    public var statusCounts: [AppDiagnosticsWorkStatusCount]
    public var kindCounts: [AppDiagnosticsWorkKindCount]

    public init(
        maxRunningCount: Int,
        kindRunningLimits: [AppDiagnosticsWorkKindCount],
        statusCounts: [AppDiagnosticsWorkStatusCount],
        kindCounts: [AppDiagnosticsWorkKindCount]
    ) {
        self.maxRunningCount = maxRunningCount
        self.kindRunningLimits = kindRunningLimits
        self.statusCounts = statusCounts
        self.kindCounts = kindCounts
    }
}

public struct AppDiagnosticsWorkFailure: Equatable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var title: String
    public var detail: String
    public var failureCount: Int

    public init(id: String, kind: WorkSessionKind, title: String, detail: String, failureCount: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.failureCount = failureCount
    }
}

public struct AppDiagnosticsSnapshot: Equatable, Sendable {
    public var catalogRootPath: String?
    public var catalogDatabasePath: String?
    public var previewCacheRootPath: String?
    public var workerExecutablePath: String?
    public var workerConfigured: Bool
    public var workerEnabled: Bool
    public var workerProcessRunning: Bool
    public var loadedAssetCount: Int
    public var totalAssetCount: Int
    public var pendingBackgroundWorkCount: Int
    public var pendingMetadataSyncCount: Int
    public var metadataSyncConflictCount: Int
    public var backgroundWork: AppDiagnosticsBackgroundWork
    public var sourceAvailabilityCounts: [AppDiagnosticsSourceAvailabilityCount]
    public var sourceRoots: [AppDiagnosticsSourceRoot]
    public var recentFailures: [AppDiagnosticsWorkFailure]

    public var previewCachePath: String? {
        previewCacheRootPath
    }

    public init(
        catalogRootPath: String?,
        catalogDatabasePath: String?,
        previewCacheRootPath: String?,
        workerExecutablePath: String?,
        workerConfigured: Bool,
        workerEnabled: Bool,
        workerProcessRunning: Bool,
        loadedAssetCount: Int,
        totalAssetCount: Int,
        pendingBackgroundWorkCount: Int,
        pendingMetadataSyncCount: Int,
        metadataSyncConflictCount: Int,
        backgroundWork: AppDiagnosticsBackgroundWork,
        sourceAvailabilityCounts: [AppDiagnosticsSourceAvailabilityCount],
        sourceRoots: [AppDiagnosticsSourceRoot],
        recentFailures: [AppDiagnosticsWorkFailure]
    ) {
        self.catalogRootPath = catalogRootPath
        self.catalogDatabasePath = catalogDatabasePath
        self.previewCacheRootPath = previewCacheRootPath
        self.workerExecutablePath = workerExecutablePath
        self.workerConfigured = workerConfigured
        self.workerEnabled = workerEnabled
        self.workerProcessRunning = workerProcessRunning
        self.loadedAssetCount = loadedAssetCount
        self.totalAssetCount = totalAssetCount
        self.pendingBackgroundWorkCount = pendingBackgroundWorkCount
        self.pendingMetadataSyncCount = pendingMetadataSyncCount
        self.metadataSyncConflictCount = metadataSyncConflictCount
        self.backgroundWork = backgroundWork
        self.sourceAvailabilityCounts = sourceAvailabilityCounts
        self.sourceRoots = sourceRoots
        self.recentFailures = recentFailures
    }
}

public typealias AppDiagnosticsFailure = AppDiagnosticsWorkFailure

public enum AppDiagnosticsReport {
    public static func text(for snapshot: AppDiagnosticsSnapshot) -> String {
        let backgroundKindCounts = snapshot.backgroundWork.kindCounts
            .map { "  \($0.kind.rawValue): \($0.count)" }
        let backgroundStatusCounts = snapshot.backgroundWork.statusCounts
            .map { "  \($0.status.rawValue): \($0.count)" }
        let sourceCounts = snapshot.sourceAvailabilityCounts
            .map { "  \($0.availability.rawValue): \($0.count)" }
        let sourceRoots = snapshot.sourceRoots.map { root in
            "  \(root.name): \(root.path) (\(root.unavailableAssetCount) unavailable of \(root.assetCount))"
        }
        let failures = snapshot.recentFailures.map { failure in
            "  \(failure.kind.rawValue) \(failure.id): \(failure.detail)"
        }

        return [
            "Teststrip Diagnostics",
            "Catalog root: \(snapshot.catalogRootPath ?? "Unavailable")",
            "Catalog database: \(snapshot.catalogDatabasePath ?? "Unavailable")",
            "Preview cache: \(snapshot.previewCachePath ?? "Unavailable")",
            "Worker executable: \(snapshot.workerExecutablePath ?? "Unavailable")",
            "Worker enabled: \(snapshot.workerEnabled ? "yes" : "no")",
            "Worker process: \(snapshot.workerProcessRunning ? "running" : "stopped")",
            "Assets loaded/total: \(snapshot.loadedAssetCount)/\(snapshot.totalAssetCount)",
            "Background active: \(snapshot.pendingBackgroundWorkCount)",
            "XMP pending/conflicts: \(snapshot.pendingMetadataSyncCount)/\(snapshot.metadataSyncConflictCount)",
            "Background by kind:",
            backgroundKindCounts.isEmpty ? "  none" : backgroundKindCounts.joined(separator: "\n"),
            "Background by status:",
            backgroundStatusCounts.isEmpty ? "  none" : backgroundStatusCounts.joined(separator: "\n"),
            "Source availability:",
            sourceCounts.isEmpty ? "  none" : sourceCounts.joined(separator: "\n"),
            "Source roots:",
            sourceRoots.isEmpty ? "  none" : sourceRoots.joined(separator: "\n"),
            "Recent failures:",
            failures.isEmpty ? "  none" : failures.joined(separator: "\n")
        ].joined(separator: "\n")
    }
}

public struct AppWorkActivity: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var status: WorkSessionStatus
    public var title: String
    public var detail: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var failureCount: Int
    public var starred: Bool

    public init(
        id: String = UUID().uuidString,
        kind: WorkSessionKind,
        status: WorkSessionStatus,
        title: String,
        detail: String,
        completedUnitCount: Int,
        totalUnitCount: Int?,
        failureCount: Int,
        starred: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.failureCount = failureCount
        self.starred = starred
    }

    public var showsProgress: Bool {
        totalUnitCount != nil && [.queued, .running, .paused].contains(status)
    }

    public init(workItem: BackgroundWorkItem) {
        self.init(
            id: workItem.id.rawValue,
            kind: workItem.kind,
            status: workItem.status,
            title: workItem.title,
            detail: workItem.detail,
            completedUnitCount: workItem.completedUnitCount,
            totalUnitCount: workItem.totalUnitCount,
            failureCount: 0
        )
    }

    public init(workSession: WorkSession) {
        self.init(
            id: workSession.id.rawValue,
            kind: workSession.kind,
            status: workSession.status,
            title: workSession.title.isEmpty ? workSession.kind.rawValue : workSession.title,
            detail: workSession.detail,
            completedUnitCount: workSession.completedUnitCount,
            totalUnitCount: workSession.totalUnitCount,
            failureCount: workSession.failureCount,
            starred: workSession.starred
        )
    }
}

public struct ImportCompletionSummary: Identifiable, Equatable, Sendable {
    public var activityID: String
    public var title: String
    public var detail: String
    public var importedPhotoCount: Int
    public var photoCountText: String
    public var newPhotoCount: Int
    public var existingPhotoCount: Int
    public var previewFailureCount: Int
    public var failureText: String?
    public var previewStatusText: String
    public var cullingSessionName: String

    public var id: String { activityID }
}

public struct KeywordSuggestion: Identifiable, Equatable, Sendable {
    public var keyword: String
    public var sourceKind: EvaluationKind
    public var confidence: Double
    public var providerName: String
    public var modelName: String

    public var id: String {
        keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public var confidenceText: String {
        let clamped = min(max(confidence, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public var provenanceText: String {
        "\(providerName)/\(modelName)"
    }
}

public struct BatchKeywordSuggestion: Identifiable, Equatable, Sendable {
    public var keyword: String
    public var assetCount: Int
    public var averageConfidence: Double
    public var providerName: String
    public var modelName: String

    public var id: String {
        keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public var confidenceText: String {
        let clamped = min(max(averageConfidence, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public var assetCountText: String {
        "\(assetCount) \(assetCount == 1 ? "photo" : "photos")"
    }

    public var provenanceText: String {
        "\(providerName)/\(modelName)"
    }
}

private struct BatchKeywordAccumulator {
    var keyword: String
    var assetCount: Int
    var confidenceTotal: Double
    var providerName: String
    var modelName: String
    var bestConfidence: Double

    var averageConfidence: Double {
        guard assetCount > 0 else { return 0 }
        return confidenceTotal / Double(assetCount)
    }
}

public struct AppImportOutput: Sendable {
    public var result: LibraryImportResult
    public var assets: [Asset]
    public var totalAssetCount: Int
    public var assetPageOffset: Int

    public init(result: LibraryImportResult, assets: [Asset], totalAssetCount: Int, assetPageOffset: Int = 0) {
        self.result = result
        self.assets = assets
        self.totalAssetCount = totalAssetCount
        self.assetPageOffset = assetPageOffset
    }
}

public typealias AppImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>

public typealias AppCardImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    URL,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>

public struct SecurityScopedResourceAccess: Sendable {
    public var requiresSuccessfulAccess: Bool
    public var startAccessing: @Sendable (URL) -> Bool
    public var stopAccessing: @Sendable (URL) -> Void

    public init(
        requiresSuccessfulAccess: Bool,
        startAccessing: @escaping @Sendable (URL) -> Bool,
        stopAccessing: @escaping @Sendable (URL) -> Void
    ) {
        self.requiresSuccessfulAccess = requiresSuccessfulAccess
        self.startAccessing = startAccessing
        self.stopAccessing = stopAccessing
    }

    public static let permissive = SecurityScopedResourceAccess(
        requiresSuccessfulAccess: false,
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() }
    )
}

private struct MetadataChange: Equatable {
    var assetID: AssetID
    var before: AssetMetadata
    var after: AssetMetadata
}

private struct WorkerImportContext {
    var source: URL
    var destinationRoot: URL?
    var didAccessSource: Bool
    var didAccessDestination: Bool
    var displayedCatalogedAssetID: AssetID?
}

private struct MetadataSyncStateSnapshot {
    var pendingItems: [MetadataSyncItem]
    var conflictItems: [MetadataSyncItem]
    var pendingCount: Int
    var conflictCount: Int
}

@Observable
public final class AppModel {
    public var sidebarSections: [SidebarSection]
    public var selectedView: LibraryViewMode {
        didSet {
            updateCompareSetAfterViewChange(from: oldValue)
        }
    }
    public var assets: [Asset]
    public var totalAssetCount: Int
    public var selectedAssetID: AssetID?
    public var statusMessage: String?
    public var errorMessage: String?
    public var activeWork: AppWorkActivity?
    public var recentWork: [AppWorkActivity]
    public var starredWork: [AppWorkActivity]
    public var pendingMetadataSyncItems: [MetadataSyncItem]
    public var metadataSyncConflictItems: [MetadataSyncItem]
    public var pendingMetadataSyncCount: Int
    public var metadataSyncConflictCount: Int
    public var previewGenerationQueueStates: [PreviewGenerationQueueState]
    public var backgroundWorkQueue: BackgroundWorkQueue
    public var librarySearchText: String
    public var keywordFilterText: String
    public var folderFilterText: String
    public var minimumRatingFilter: Int?
    public var flagFilter: PickFlag?
    public var colorLabelFilter: ColorLabel?
    public var cameraFilterText: String
    public var lensFilterText: String
    public var minimumISOFilter: Int?
    public var captureDateStartFilter: Date?
    public var captureDateEndFilter: Date?
    public var availabilityFilter: SourceAvailability?
    public var evaluationKindFilter: EvaluationKind?
    public var needsKeywordsFilter: Bool
    public var needsEvaluationFilter: Bool
    public var likelyIssuesFilter: Bool
    public var providerFailuresFilter: Bool
    public var metadataSyncPendingFilter: Bool
    public var metadataSyncConflictFilter: Bool
    public var savedAssetSets: [AssetSet]
    public var assetSetCounts: [AssetSetID: Int]
    public var catalogFolders: [CatalogFolder]
    public var catalogTimelineDays: [CatalogTimelineDay]
    public var sourceRoots: [CatalogSourceRoot]
    public var sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary]
    public var catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary]
    public var reviewQueueCounts: [ReviewQueue: Int]
    public var selectedAssetSetID: AssetSetID?

    @ObservationIgnored
    private var catalog: AppCatalog?

    @ObservationIgnored
    private let importTaskFactory: AppImportTaskFactory

    @ObservationIgnored
    private let cardImportTaskFactory: AppCardImportTaskFactory

    @ObservationIgnored
    private let workerSupervisor: WorkerSupervisor?

    @ObservationIgnored
    private let workerExecutableURL: URL?

    @ObservationIgnored
    private let resourceAccess: SecurityScopedResourceAccess

    @ObservationIgnored
    private var activeImportTask: Task<AppImportOutput, Error>?

    @ObservationIgnored
    private var workerImportContextsByItemID: [WorkSessionID: WorkerImportContext]

    @ObservationIgnored
    private var evaluationAssetIDsByItemID: [WorkSessionID: AssetID]

    @ObservationIgnored
    private var evaluationProvidersByItemID: [WorkSessionID: String]

    @ObservationIgnored
    private var metadataSyncAssetIDsByItemID: [WorkSessionID: AssetID]

    @ObservationIgnored
    private var availabilityAssetIDsByItemID: [WorkSessionID: [AssetID]]

    private var previewCacheGenerationsByAssetID: [AssetID: Int]
    private var evaluationSignalGenerationsByAssetID: [AssetID: Int]
    private var metadataUndoStack: [MetadataChange]
    private var metadataRedoStack: [MetadataChange]
    private var assetPageOffset: Int
    private var compareAssetIDs: [AssetID]?

    public static let defaultEvaluationProviderName = "local-image-metrics"
    public static let defaultEvaluationProviderNames = [defaultEvaluationProviderName, "apple-vision"]
    private static let assetPageSize = 120
    private static let loadedAssetWindowSize = assetPageSize * 2
    private static let pendingPreviewRecoveryBatchSize = 40
    static let previewGenerationQueueStateDisplayLimit = pendingPreviewRecoveryBatchSize
    private static let pendingMetadataSyncRecoveryBatchSize = 200
    static let metadataSyncStateDisplayLimit = pendingMetadataSyncRecoveryBatchSize
    private static let previewGenerationMaximumAutomaticAttempts = 3
    static let sourceAvailabilityBatchSize = 100
    private static let defaultCompareAssetLimit = 4
    private static let candidateStackMaximumCaptureGap: TimeInterval = 2

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public var selectedPreviewURL: URL? {
        selectedAssetID.flatMap { loupePreviewURL(for: $0) }
    }

    public var selectedPendingMetadataSyncItem: MetadataSyncItem? {
        guard let selectedAssetID else { return nil }
        return pendingMetadataSyncItems.first { $0.assetID == selectedAssetID }
    }

    public var selectedMetadataSyncConflictSidecarMetadata: AssetMetadata? {
        guard let selectedAssetID,
              let conflictItem = metadataSyncConflictItems.first(where: { $0.assetID == selectedAssetID }),
              let sidecarData = try? Data(contentsOf: conflictItem.sidecarURL) else {
            return nil
        }
        return try? XMPPacket.parse(sidecarData).metadata
    }

    public var canRetrySelectedMetadataSync: Bool {
        guard let selectedAsset,
              let pendingItem = selectedPendingMetadataSyncItem else {
            return false
        }
        return canAutomaticallyRetryMetadataSync(for: selectedAsset, sidecarURL: pendingItem.sidecarURL)
    }

    public var canRetryPendingMetadataSyncInCurrentScope: Bool {
        guard metadataSyncPendingFilter,
              let catalog,
              workerSupervisor != nil else {
            return false
        }

        for asset in assets.prefix(Self.metadataSyncStateDisplayLimit) {
            guard let pendingItem = try? catalog.repository.pendingMetadataSyncItem(assetID: asset.id),
                  canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL),
                  !hasActiveMetadataSyncWork(assetID: asset.id, generation: pendingItem.catalogGeneration) else {
                continue
            }
            return true
        }
        return false
    }

    public var selectedAssetPosition: Int? {
        guard let selectedAssetID,
              let selectedIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return nil
        }
        return assetPageOffset + selectedIndex + 1
    }

    public var selectedAssetPositionText: String? {
        guard let position = selectedAssetPosition else {
            return nil
        }
        let totalCount = max(totalAssetCount, position)
        return "Frame \(position) of \(totalCount)"
    }

    public var cullingProgressSummary: CullingProgressSummary {
        let decisionCounts = cullingDecisionCounts()
        return CullingProgressSummary(
            selectedPosition: selectedAssetPosition,
            positionText: selectedAssetPositionText,
            pickCount: decisionCounts.pickCount,
            rejectCount: decisionCounts.rejectCount,
            totalCount: totalAssetCount
        )
    }

    private func cullingDecisionCounts() -> (pickCount: Int, rejectCount: Int) {
        guard let catalog else {
            return loadedCullingDecisionCounts()
        }
        do {
            return (
                try cullingDecisionCount(flag: .pick, repository: catalog.repository),
                try cullingDecisionCount(flag: .reject, repository: catalog.repository)
            )
        } catch {
            return loadedCullingDecisionCounts()
        }
    }

    private func cullingDecisionCount(flag: PickFlag, repository: CatalogRepository) throws -> Int {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            return try repository.assetCount(ids: explicitAssetIDs, flag: flag)
        }
        var predicates = currentLibraryQuery()?.predicates ?? []
        predicates.append(.flag(flag))
        return try repository.assetCount(matching: SetQuery(predicates: predicates))
    }

    private func loadedCullingDecisionCounts() -> (pickCount: Int, rejectCount: Int) {
        (
            assets.filter { $0.metadata.flag == .pick }.count,
            assets.filter { $0.metadata.flag == .reject }.count
        )
    }

    public var hasMoreAssets: Bool {
        assetPageOffset + assets.count < totalAssetCount
    }

    public var hasPreviousAssets: Bool {
        assetPageOffset > 0
    }

    public var libraryCountText: String {
        if assetPageOffset == 0, totalAssetCount > assets.count {
            return "Showing \(assets.count) of \(totalAssetCount) photographs"
        }
        if assetPageOffset > 0 {
            let start = assetPageOffset + 1
            let end = assetPageOffset + assets.count
            return "Showing \(start)-\(end) of \(totalAssetCount) photographs"
        }
        return "\(assets.count) \(assets.count == 1 ? "photograph" : "photographs")"
    }

    public var libraryStatusText: String? {
        guard let statusMessage else { return nil }
        guard statusMessage.hasPrefix("Imported "),
              let previewStatus = activePreviewGenerationStatusText else {
            return statusMessage
        }
        return "\(statusMessage); \(previewStatus)"
    }

    private var activePreviewGenerationStatusText: String? {
        let previewItems = backgroundWorkQueue.items.filter { item in
            item.kind == .previewGeneration && [.queued, .running, .paused].contains(item.status)
        }
        guard !previewItems.isEmpty else { return nil }
        if backgroundWorkQueue.isPaused || previewItems.contains(where: { $0.status == .paused }) {
            return "preview queue paused"
        }
        if previewItems.contains(where: { $0.status == .running }) {
            return "generating previews"
        }
        return "previews queued"
    }

    public var libraryTitle: String {
        if selectedView == .search {
            return "Search"
        }
        if selectedView == .copilot {
            return "Copilot"
        }
        if selectedView == .timeline {
            return "Timeline"
        }
        if selectedView == .people {
            return "People"
        }
        if let selectedAssetSet {
            return selectedAssetSet.name
        }
        if currentLibraryQuery() != nil {
            return suggestedSavedSearchName
        }
        return "All Photographs"
    }

    public var canUndoMetadataChange: Bool {
        !metadataUndoStack.isEmpty
    }

    public var canRedoMetadataChange: Bool {
        !metadataRedoStack.isEmpty
    }

    public var visibleWorkActivity: AppWorkActivity? {
        visibleWorkActivities.first
    }

    public var visibleWorkActivities: [AppWorkActivity] {
        if let activeWork {
            return [activeWork]
        }
        let activeBackgroundItems = visibleActiveBackgroundWorkItems
        if !activeBackgroundItems.isEmpty {
            return activeBackgroundItems.map(AppWorkActivity.init)
        }
        if let backgroundItem = visibleInactiveBackgroundWorkItem {
            return [AppWorkActivity(workItem: backgroundItem)]
        }
        return recentWork.first.map { [$0] } ?? []
    }

    public var visibleImportActivity: AppWorkActivity? {
        if let activeWork, activeWork.kind == .ingest, [.queued, .running, .paused].contains(activeWork.status) {
            return activeWork
        }
        if let backgroundItem = activeBackgroundImportItem {
            return AppWorkActivity(workItem: backgroundItem)
        }
        return nil
    }

    public var selectedPreviewGenerationFailures: [PreviewGenerationQueueState] {
        guard let selectedAssetID else { return [] }
        return previewGenerationQueueStates.filter { state in
            state.item.assetID == selectedAssetID && state.attemptCount > 0
        }
    }

    public var canRetrySelectedPreviewGenerationFailures: Bool {
        guard workerSupervisor != nil,
              !selectedPreviewGenerationFailures.isEmpty else {
            return false
        }
        return selectedAsset?.availability.requiresCachedPreviewOnly != true
    }

    public var canPauseBackgroundWork: Bool {
        !backgroundWorkQueue.isPaused
            && backgroundWorkQueue.items.contains { [.queued, .running].contains($0.status) }
    }

    public var canResumeBackgroundWork: Bool {
        backgroundWorkQueue.isPaused
    }

    public var backgroundWorkPauseNotice: String? {
        guard backgroundWorkQueue.isPaused else { return nil }
        return backgroundWorkQueue.runningItems.isEmpty ? "Queue paused" : "Queue paused after current task"
    }

    public var isWorkerProcessRunning: Bool {
        workerSupervisor?.isWorkerProcessRunning ?? false
    }

    public var canStopIdleWorkerProcess: Bool {
        workerSupervisor?.canStopIdleWorkerProcess ?? false
    }

    public var idleWorkerStatusText: String? {
        canStopIdleWorkerProcess ? "Worker idle" : nil
    }

    public var canCancelBackgroundWork: Bool {
        backgroundWorkQueue.items.contains { [.queued, .running, .paused].contains($0.status) }
    }

    public func canCancelBackgroundWorkActivity(_ activity: AppWorkActivity) -> Bool {
        guard let item = backgroundWorkQueue.item(id: WorkSessionID(rawValue: activity.id)) else {
            return false
        }
        return Self.isActiveBackgroundWorkStatus(item.status)
    }

    public var diagnosticsSnapshot: AppDiagnosticsSnapshot {
        let paths = catalog?.paths
        return AppDiagnosticsSnapshot(
            catalogRootPath: paths?.root.path,
            catalogDatabasePath: paths?.catalogURL.path,
            previewCacheRootPath: paths?.previewCacheRoot.path,
            workerExecutablePath: workerExecutableURL?.path,
            workerConfigured: workerExecutableURL != nil,
            workerEnabled: workerSupervisor != nil,
            workerProcessRunning: isWorkerProcessRunning,
            loadedAssetCount: assets.count,
            totalAssetCount: totalAssetCount,
            pendingBackgroundWorkCount: backgroundWorkQueue.items.filter { Self.isActiveBackgroundWorkStatus($0.status) }.count,
            pendingMetadataSyncCount: pendingMetadataSyncCount,
            metadataSyncConflictCount: metadataSyncConflictCount,
            backgroundWork: Self.diagnosticsBackgroundWork(backgroundWorkQueue),
            sourceAvailabilityCounts: Self.sourceAvailabilityCounts(sourceAvailabilitySummaries),
            sourceRoots: sourceRoots.map {
                AppDiagnosticsSourceRoot(
                    path: $0.path,
                    name: $0.name,
                    assetCount: $0.assetCount,
                    unavailableAssetCount: $0.unavailableAssetCount
                )
            },
            recentFailures: diagnosticsRecentFailures()
        )
    }

    public var diagnosticsReportText: String {
        AppDiagnosticsReport.text(for: diagnosticsSnapshot)
    }

    public var isImporting: Bool {
        if activeWork?.kind == .ingest, let status = activeWork?.status, Self.isActiveBackgroundWorkStatus(status) {
            return true
        }
        guard !workerImportContextsByItemID.isEmpty else { return false }
        return workerImportContextsByItemID.keys.contains { itemID in
            guard let item = backgroundWorkQueue.item(id: itemID), item.kind == .ingest else { return false }
            return Self.isActiveBackgroundWorkStatus(item.status)
        }
    }

    public var canRequestSelectedAssetEvaluation: Bool {
        selectedAssetID != nil && workerSupervisor != nil
    }

    public var canRequestVisibleAssetEvaluations: Bool {
        workerSupervisor != nil && !assets.isEmpty
    }

    public var canRequestCompareAssetEvaluations: Bool {
        workerSupervisor != nil && compareAssets().contains { hasCachedPreview(for: $0.id) }
    }

    public var canRefreshVisibleAssetAvailability: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var selectedEvaluationSignals: [EvaluationSignal] {
        guard let selectedAssetID else { return [] }
        return evaluationSignals(for: selectedAssetID)
    }

    public func evaluationSignals(for assetID: AssetID) -> [EvaluationSignal] {
        guard let catalog else { return [] }
        _ = evaluationSignalGeneration(for: assetID)
        return (try? catalog.repository.evaluationSignals(assetID: assetID)) ?? []
    }

    public var selectedSuggestedKeywords: [KeywordSuggestion] {
        guard let selectedAsset else { return [] }
        return Self.keywordSuggestions(
            from: selectedEvaluationSignals,
            existingKeywords: selectedAsset.metadata.keywords
        )
    }

    public var visibleBatchKeywordSuggestions: [BatchKeywordSuggestion] {
        batchKeywordSuggestions(for: assets)
    }

    public var latestImportBatchKeywordSuggestions: [BatchKeywordSuggestion] {
        guard let catalog,
              let assetIDs = try? latestImportOutputAssetIDs(repository: catalog.repository),
              !assetIDs.isEmpty,
              let importedAssets = try? catalog.repository.assets(ids: assetIDs, limit: assetIDs.count) else {
            return []
        }
        return batchKeywordSuggestions(for: importedAssets)
    }

    public var starredAssetSets: [AssetSet] {
        Self.visibleSavedAssetSets(savedAssetSets).filter(\.starred)
    }

    public var canSaveCurrentLibraryQuery: Bool {
        currentLibraryQuery() != nil
    }

    public var hasActiveLibraryFilters: Bool {
        selectedAssetSetID != nil || currentLibraryQuery() != nil
    }

    public var activeLibraryFilterChips: [String] {
        activeLibraryFilterRows.map(\.title)
    }

    public var activeLibraryFilterRows: [ActiveLibraryFilterRow] {
        var rows: [ActiveLibraryFilterRow] = []
        if let selectedAssetSet {
            Self.append(ActiveLibraryFilterRow(title: selectedAssetSet.name, target: .assetSet(selectedAssetSet.id)), to: &rows)
        }
        if let selectedDynamicSetQuery {
            for predicate in selectedDynamicSetQuery.predicates {
                guard let row = Self.activeLibraryFilterRow(for: predicate) else { continue }
                Self.append(row, to: &rows)
            }
        }
        let searchIntent = LibrarySearchIntent.parse(librarySearchText)
        if let residualSearch = searchIntent.residualText {
            Self.append(ActiveLibraryFilterRow(title: "Search: \(residualSearch)"), to: &rows)
        }
        for (index, chip) in searchIntent.chips.enumerated() {
            let target = searchIntent.predicates.indices.contains(index)
                ? Self.sidebarTarget(for: searchIntent.predicates[index])
                : nil
            Self.append(ActiveLibraryFilterRow(title: chip, target: target), to: &rows)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Keyword: \(trimmedKeyword)"), to: &rows)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Folder: \(URL(fileURLWithPath: trimmedFolder).lastPathComponent)"), to: &rows)
        }
        if let minimumRatingFilter {
            Self.append(
                ActiveLibraryFilterRow(
                    title: "Rating >= \(minimumRatingFilter)",
                    target: minimumRatingFilter == 5 ? .reviewQueue(.fiveStars) : nil
                ),
                to: &rows
            )
        }
        if let flagFilter {
            Self.append(
                ActiveLibraryFilterRow(title: flagFilter.rawValue.capitalized, target: Self.sidebarTarget(for: .flag(flagFilter))),
                to: &rows
            )
        }
        if let colorLabelFilter {
            Self.append(ActiveLibraryFilterRow(title: "\(colorLabelFilter.rawValue.capitalized) Label"), to: &rows)
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Camera: \(trimmedCamera)"), to: &rows)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            Self.append(ActiveLibraryFilterRow(title: "Lens: \(trimmedLens)"), to: &rows)
        }
        if let minimumISOFilter {
            Self.append(ActiveLibraryFilterRow(title: "ISO >= \(minimumISOFilter)"), to: &rows)
        }
        if let captureDateStartFilter {
            Self.append(ActiveLibraryFilterRow(title: "From \(captureDateStartFilter.formatted(date: .abbreviated, time: .omitted))"), to: &rows)
        }
        if let captureDateEndFilter {
            Self.append(ActiveLibraryFilterRow(title: "Before \(captureDateEndFilter.formatted(date: .abbreviated, time: .omitted))"), to: &rows)
        }
        if let availabilityFilter {
            Self.append(
                ActiveLibraryFilterRow(title: "Source: \(availabilityFilter.rawValue.capitalized)", target: .sourceAvailability(availabilityFilter)),
                to: &rows
            )
        }
        if let evaluationKindFilter {
            Self.append(
                ActiveLibraryFilterRow(title: "Signal: \(evaluationKindFilter.displayName)", target: .evaluationKind(evaluationKindFilter)),
                to: &rows
            )
        }
        if needsKeywordsFilter {
            Self.append(ActiveLibraryFilterRow(title: "Needs Keywords", target: .reviewQueue(.needsKeywords)), to: &rows)
        }
        if needsEvaluationFilter {
            Self.append(ActiveLibraryFilterRow(title: "Needs Evaluation", target: .reviewQueue(.needsEvaluation)), to: &rows)
        }
        if likelyIssuesFilter {
            Self.append(ActiveLibraryFilterRow(title: "Likely Issues", target: .reviewQueue(.likelyIssues)), to: &rows)
        }
        if providerFailuresFilter {
            Self.append(ActiveLibraryFilterRow(title: "Provider Failures", target: .reviewQueue(.providerFailures)), to: &rows)
        }
        if metadataSyncPendingFilter {
            Self.append(ActiveLibraryFilterRow(title: "XMP Pending", target: .metadataSyncPending), to: &rows)
        }
        if metadataSyncConflictFilter {
            Self.append(ActiveLibraryFilterRow(title: "XMP Conflicts", target: .metadataSyncConflicts), to: &rows)
        }
        return rows
    }

    public var canSaveSelectedAssetAsManualSet: Bool {
        catalog != nil && selectedAssetID != nil
    }

    public var canSaveCurrentAssetScopeSnapshot: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var canBeginCullingSession: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var latestImportCompletionSummary: ImportCompletionSummary? {
        guard let activity = recentWork.first(where: Self.isImportCompletionActivity) else {
            return nil
        }
        let previewFailureCount = latestImportPreviewFailureCount(activity: activity)
        let failureText = previewFailureCount > 0
            ? "\(previewFailureCount) preview \(previewFailureCount == 1 ? "failure" : "failures")"
            : nil
        let importedPhotoCount = activity.totalUnitCount ?? activity.completedUnitCount
        let newPhotoCount = activity.completedUnitCount
        let existingPhotoCount = max(importedPhotoCount - newPhotoCount, 0)
        return ImportCompletionSummary(
            activityID: activity.id,
            title: "Import complete",
            detail: activity.detail,
            importedPhotoCount: importedPhotoCount,
            photoCountText: Self.photoCountDescription(importedPhotoCount),
            newPhotoCount: newPhotoCount,
            existingPhotoCount: existingPhotoCount,
            previewFailureCount: previewFailureCount,
            failureText: failureText,
            previewStatusText: failureText ?? activePreviewGenerationStatusText ?? "Previews ready",
            cullingSessionName: "\(activity.detail) Cull"
        )
    }

    private func latestImportPreviewFailureCount(activity: AppWorkActivity) -> Int {
        guard let catalog else { return activity.failureCount }
        do {
            let assetIDs = try latestImportOutputAssetIDs(activityID: activity.id, repository: catalog.repository)
            let deferredFailureCount = try catalog.repository.previewGenerationFailureAssetCount(assetIDs: assetIDs)
            return max(activity.failureCount, deferredFailureCount)
        } catch {
            return activity.failureCount
        }
    }

    public var suggestedSavedSearchName: String {
        var parts: [String] = []
        let searchIntent = LibrarySearchIntent.parse(librarySearchText)
        if let residualSearch = searchIntent.residualText {
            parts.append(residualSearch)
        }
        for namePart in searchIntent.nameParts {
            Self.append(namePart, to: &parts)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            Self.append(trimmedKeyword, to: &parts)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            Self.append(URL(fileURLWithPath: trimmedFolder).lastPathComponent, to: &parts)
        }
        if let minimumRatingFilter {
            Self.append("\(minimumRatingFilter)+ Stars", to: &parts)
        }
        if let flagFilter {
            Self.append(flagFilter.rawValue.capitalized, to: &parts)
        }
        if let colorLabelFilter {
            Self.append("\(colorLabelFilter.rawValue.capitalized) Label", to: &parts)
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            Self.append(trimmedCamera, to: &parts)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            Self.append(trimmedLens, to: &parts)
        }
        if let minimumISOFilter {
            Self.append("ISO \(minimumISOFilter)+", to: &parts)
        }
        if let availabilityFilter {
            Self.append(availabilityFilter.rawValue.capitalized, to: &parts)
        }
        if let evaluationKindFilter {
            Self.append("\(evaluationKindFilter.displayName) Signal", to: &parts)
        }
        if needsKeywordsFilter {
            Self.append("Needs Keywords", to: &parts)
        }
        if needsEvaluationFilter {
            Self.append("Needs Evaluation", to: &parts)
        }
        if likelyIssuesFilter {
            Self.append("Likely Issues", to: &parts)
        }
        if providerFailuresFilter {
            Self.append("Provider Failures", to: &parts)
        }
        if metadataSyncPendingFilter {
            Self.append("XMP Pending", to: &parts)
        }
        if metadataSyncConflictFilter {
            Self.append("XMP Conflicts", to: &parts)
        }
        return parts.isEmpty ? "Saved Search" : parts.joined(separator: " ")
    }

    public var suggestedManualSetName: String {
        guard let selectedAsset else {
            return "Selection"
        }
        let filename = selectedAsset.originalURL.deletingPathExtension().lastPathComponent
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFilename.isEmpty ? "Selection" : trimmedFilename
    }

    public var suggestedSnapshotSetName: String {
        if let selectedAssetSet {
            return "\(selectedAssetSet.name) Snapshot"
        }
        if currentLibraryQuery() != nil {
            return "\(suggestedSavedSearchName) Snapshot"
        }
        return "Catalog Snapshot"
    }

    public var suggestedCullingSessionName: String {
        if let selectedAssetSet {
            return "\(selectedAssetSet.name) Cull"
        }
        if currentLibraryQuery() != nil {
            return "\(suggestedSavedSearchName) Cull"
        }
        return "Catalog Cull"
    }

    public var suggestedReconnectOldRootPath: String {
        if let sourceRoot = sourceRoots.first(where: { $0.unavailableAssetCount > 0 }) {
            return sourceRoot.path
        }
        let unavailableFolders = assets
            .filter { $0.availability != .online }
            .map { $0.originalURL.deletingLastPathComponent().standardizedFileURL.path }
        return Self.commonAncestorPath(for: unavailableFolders) ?? ""
    }

    public init(
        sidebarSections: [SidebarSection],
        selectedView: LibraryViewMode,
        assets: [Asset],
        totalAssetCount: Int? = nil,
        catalog: AppCatalog? = nil,
        statusMessage: String? = nil,
        errorMessage: String? = nil,
        activeWork: AppWorkActivity? = nil,
        recentWork: [AppWorkActivity] = [],
        starredWork: [AppWorkActivity] = [],
        pendingMetadataSyncItems: [MetadataSyncItem] = [],
        metadataSyncConflictItems: [MetadataSyncItem] = [],
        pendingMetadataSyncCount: Int? = nil,
        metadataSyncConflictCount: Int? = nil,
        previewGenerationQueueStates: [PreviewGenerationQueueState] = [],
        backgroundWorkQueue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        catalogFolders: [CatalogFolder] = [],
        catalogTimelineDays: [CatalogTimelineDay] = [],
        sourceRoots: [CatalogSourceRoot] = [],
        sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary] = [],
        catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        selectedAssetSetID: AssetSetID? = nil,
        workerSupervisor: WorkerSupervisor? = nil,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil,
        workerExecutableURL: URL? = nil,
        resourceAccess: SecurityScopedResourceAccess = .permissive
    ) {
        let resolvedTotalAssetCount = totalAssetCount ?? assets.count
        let resolvedPendingMetadataSyncCount = pendingMetadataSyncCount ?? pendingMetadataSyncItems.count
        let resolvedMetadataSyncConflictCount = metadataSyncConflictCount ?? metadataSyncConflictItems.count
        self.sidebarSections = sidebarSections.isEmpty ? Self.defaultSidebarSections(
            totalAssetCount: resolvedTotalAssetCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
            pendingMetadataSyncCount: resolvedPendingMetadataSyncCount,
            metadataSyncConflictCount: resolvedMetadataSyncConflictCount,
            recentWork: recentWork,
            starredWork: starredWork
        ) : sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.totalAssetCount = resolvedTotalAssetCount
        self.selectedAssetID = assets.first?.id
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.activeWork = activeWork
        self.recentWork = recentWork
        self.starredWork = starredWork
        self.pendingMetadataSyncItems = pendingMetadataSyncItems
        self.metadataSyncConflictItems = metadataSyncConflictItems
        self.pendingMetadataSyncCount = resolvedPendingMetadataSyncCount
        self.metadataSyncConflictCount = resolvedMetadataSyncConflictCount
        self.previewGenerationQueueStates = previewGenerationQueueStates
        self.backgroundWorkQueue = workerSupervisor?.queue ?? backgroundWorkQueue
        self.librarySearchText = ""
        self.keywordFilterText = ""
        self.folderFilterText = ""
        self.minimumRatingFilter = nil
        self.flagFilter = nil
        self.colorLabelFilter = nil
        self.cameraFilterText = ""
        self.lensFilterText = ""
        self.minimumISOFilter = nil
        self.captureDateStartFilter = nil
        self.captureDateEndFilter = nil
        self.availabilityFilter = nil
        self.evaluationKindFilter = nil
        self.needsKeywordsFilter = false
        self.needsEvaluationFilter = false
        self.likelyIssuesFilter = false
        self.providerFailuresFilter = false
        self.metadataSyncPendingFilter = false
        self.metadataSyncConflictFilter = false
        self.savedAssetSets = savedAssetSets
        self.assetSetCounts = assetSetCounts
        self.catalogFolders = catalogFolders
        self.catalogTimelineDays = catalogTimelineDays
        self.sourceRoots = sourceRoots
        self.sourceAvailabilitySummaries = sourceAvailabilitySummaries
        self.catalogEvaluationKindSummaries = catalogEvaluationKindSummaries
        self.reviewQueueCounts = reviewQueueCounts
        self.selectedAssetSetID = selectedAssetSetID
        self.catalog = catalog
        self.workerSupervisor = workerSupervisor
        self.workerExecutableURL = workerExecutableURL
        self.resourceAccess = resourceAccess
        self.previewCacheGenerationsByAssetID = [:]
        self.evaluationAssetIDsByItemID = [:]
        self.evaluationProvidersByItemID = [:]
        self.metadataSyncAssetIDsByItemID = [:]
        self.availabilityAssetIDsByItemID = [:]
        self.evaluationSignalGenerationsByAssetID = [:]
        let importPreviewPolicy: LibraryImportPreviewPolicy = workerSupervisor == nil ? .generateImmediately : .deferGeneration
        self.importTaskFactory = importTaskFactory ?? { paths, folderURL, progress in
            Self.defaultImportTask(
                paths: paths,
                folderURL: folderURL,
                previewPolicy: importPreviewPolicy,
                progress: progress
            )
        }
        self.cardImportTaskFactory = cardImportTaskFactory ?? { paths, source, destinationRoot, progress in
            Self.defaultCardImportTask(
                paths: paths,
                source: source,
                destinationRoot: destinationRoot,
                previewPolicy: importPreviewPolicy,
                progress: progress
            )
        }
        self.metadataUndoStack = []
        self.metadataRedoStack = []
        self.assetPageOffset = 0
        self.compareAssetIDs = nil
        self.workerImportContextsByItemID = [:]
        self.workerSupervisor?.onQueueChanged = { [weak self] queue in
            let previousQueue = self?.backgroundWorkQueue
            let previousPreviewFailureIDs = Self.failedPreviewGenerationItemIDs(in: self?.backgroundWorkQueue)
            self?.backgroundWorkQueue = queue
            self?.recordPersistedActiveBackgroundWorkActivities(in: queue)
            if Self.metadataSyncWorkChanged(from: previousQueue, to: queue) {
                try? self?.refreshMetadataSyncState()
            }
            let failedPreviewItemIDs = Self.failedPreviewGenerationItemIDs(in: queue)
            let newFailedPreviewItemIDs = failedPreviewItemIDs.subtracting(previousPreviewFailureIDs)
            if !newFailedPreviewItemIDs.isEmpty {
                try? self?.refreshPreviewGenerationQueueStates()
                self?.refreshLoadedAssetAvailabilityForPreviewFailures(newFailedPreviewItemIDs)
                try? self?.enqueuePendingPreviewGeneration(excluding: newFailedPreviewItemIDs)
            }
            self?.releaseInactiveWorkerImportContexts(in: queue)
            self?.releaseInactiveEvaluationContexts(in: queue)
            self?.releaseInactiveMetadataSyncContexts(in: queue)
            self?.releaseInactiveAvailabilityContexts(in: queue)
        }
        self.workerSupervisor?.onCommandProgress = { [weak self] event in
            self?.handleWorkerCommandProgress(event)
        }
        self.workerSupervisor?.onCommandCompleted = { [weak self] event in
            self?.handleWorkerCommandCompleted(event)
        }
        if selectedView == .compare {
            compareAssetIDs = compareWindowAssetIDs(limit: Self.defaultCompareAssetLimit, anchor: selectedAssetID)
        }
    }

    public static func demo() -> AppModel {
        let asset = Asset(
            id: AssetID(rawValue: "demo-1"),
            originalURL: URL(fileURLWithPath: "/Photos/demo.jpg"),
            volumeIdentifier: "Demo",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 4, colorLabel: .green, flag: .pick, keywords: ["demo"])
        )
        return AppModel(
            sidebarSections: defaultSidebarSections(totalAssetCount: 1),
            selectedView: .grid,
            assets: [asset]
        )
    }

    public static func load(repository: CatalogRepository) throws -> AppModel {
        try reconcileInterruptedIngestWorkSessions(repository: repository)
        let assets = try repository.allAssets(limit: Self.assetPageSize)
        let savedAssetSets = try repository.assetSets()
        let assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: repository)
        let catalogFolders = try repository.folders()
        let catalogTimelineDays = try repository.timelineDays()
        let sourceRoots = try repository.sourceRoots()
        let sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: repository)
        let catalogEvaluationKindSummaries = try repository.evaluationKindSummaries()
        let reviewQueueCounts = try Self.reviewQueueCounts(repository: repository)
        let metadataSyncState = try Self.metadataSyncState(
            repository: repository,
            selectedAssetID: assets.first?.id
        )
        let recentWork = try repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let totalAssetCount = try repository.assetCount()
        return AppModel(
            sidebarSections: defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                catalogFolders: catalogFolders,
                catalogTimelineDays: catalogTimelineDays,
                sourceAvailabilitySummaries: sourceAvailabilitySummaries,
                catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
                reviewQueueCounts: reviewQueueCounts,
                pendingMetadataSyncItems: metadataSyncState.pendingItems,
                metadataSyncConflictItems: metadataSyncState.conflictItems,
                pendingMetadataSyncCount: metadataSyncState.pendingCount,
                metadataSyncConflictCount: metadataSyncState.conflictCount,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: totalAssetCount,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: metadataSyncState.pendingItems,
            metadataSyncConflictItems: metadataSyncState.conflictItems,
            pendingMetadataSyncCount: metadataSyncState.pendingCount,
            metadataSyncConflictCount: metadataSyncState.conflictCount,
            previewGenerationQueueStates: try previewGenerationQueueStates(
                repository: repository,
                selectedAssetID: assets.first?.id
            ),
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceRoots: sourceRoots,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts
        )
    }

    public static func load(
        catalog: AppCatalog,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil,
        workerSupervisor: WorkerSupervisor? = nil,
        workerExecutableURL: URL? = nil,
        resourceAccess: SecurityScopedResourceAccess = .permissive
    ) throws -> AppModel {
        try reconcileInterruptedIngestWorkSessions(repository: catalog.repository)
        let assets = try catalog.repository.allAssets(limit: Self.assetPageSize)
        let savedAssetSets = try catalog.repository.assetSets()
        let assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        let catalogFolders = try catalog.repository.folders()
        let catalogTimelineDays = try catalog.repository.timelineDays()
        let sourceRoots = try catalog.repository.sourceRoots()
        let sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        let catalogEvaluationKindSummaries = try catalog.repository.evaluationKindSummaries()
        let reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
        let metadataSyncState = try Self.metadataSyncState(
            repository: catalog.repository,
            selectedAssetID: assets.first?.id
        )
        let recentWork = try catalog.repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try catalog.repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let totalAssetCount = try catalog.repository.assetCount()
        let model = AppModel(
            sidebarSections: defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                catalogFolders: catalogFolders,
                catalogTimelineDays: catalogTimelineDays,
                sourceAvailabilitySummaries: sourceAvailabilitySummaries,
                catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
                reviewQueueCounts: reviewQueueCounts,
                pendingMetadataSyncItems: metadataSyncState.pendingItems,
                metadataSyncConflictItems: metadataSyncState.conflictItems,
                pendingMetadataSyncCount: metadataSyncState.pendingCount,
                metadataSyncConflictCount: metadataSyncState.conflictCount,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: totalAssetCount,
            catalog: catalog,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: metadataSyncState.pendingItems,
            metadataSyncConflictItems: metadataSyncState.conflictItems,
            pendingMetadataSyncCount: metadataSyncState.pendingCount,
            metadataSyncConflictCount: metadataSyncState.conflictCount,
            previewGenerationQueueStates: try previewGenerationQueueStates(
                repository: catalog.repository,
                selectedAssetID: assets.first?.id
            ),
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceRoots: sourceRoots,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            workerSupervisor: workerSupervisor,
            importTaskFactory: importTaskFactory,
            cardImportTaskFactory: cardImportTaskFactory,
            workerExecutableURL: workerExecutableURL,
            resourceAccess: resourceAccess
        )
        try model.enqueuePendingPreviewGeneration()
        try model.enqueuePendingMetadataSync()
        return model
    }

    private static func metadataSyncState(
        repository: CatalogRepository,
        selectedAssetID: AssetID?
    ) throws -> MetadataSyncStateSnapshot {
        var snapshot = MetadataSyncStateSnapshot(
            pendingItems: try repository.pendingMetadataSyncItems(limit: metadataSyncStateDisplayLimit),
            conflictItems: try repository.metadataSyncConflictItems(limit: metadataSyncStateDisplayLimit),
            pendingCount: try repository.pendingMetadataSyncItemCount(),
            conflictCount: try repository.metadataSyncConflictItemCount()
        )
        if let selectedAssetID {
            try mergeMetadataSyncState(for: selectedAssetID, repository: repository, into: &snapshot)
        }
        return snapshot
    }

    private static func mergeMetadataSyncState(
        for assetID: AssetID,
        repository: CatalogRepository,
        into snapshot: inout MetadataSyncStateSnapshot
    ) throws {
        snapshot.pendingItems.removeAll { $0.assetID == assetID }
        snapshot.conflictItems.removeAll { $0.assetID == assetID }
        if let pendingItem = try repository.pendingMetadataSyncItem(assetID: assetID) {
            snapshot.pendingItems.append(pendingItem)
        }
        if let conflictItem = try repository.metadataSyncConflictItem(assetID: assetID) {
            snapshot.conflictItems.append(conflictItem)
        }
    }

    private static func previewGenerationQueueStates(
        repository: CatalogRepository,
        selectedAssetID: AssetID?
    ) throws -> [PreviewGenerationQueueState] {
        var states = try repository.previewGenerationQueueStates(limit: previewGenerationQueueStateDisplayLimit)
        if let selectedAssetID {
            try mergePreviewGenerationQueueStates(for: selectedAssetID, repository: repository, into: &states)
        }
        return states
    }

    private static func mergePreviewGenerationQueueStates(
        for assetID: AssetID,
        repository: CatalogRepository,
        into states: inout [PreviewGenerationQueueState]
    ) throws {
        states.removeAll { $0.item.assetID == assetID }
        for level in PreviewLevel.allCases {
            if let state = try repository.previewGenerationQueueState(assetID: assetID, level: level) {
                states.append(state)
            }
        }
    }

    private static func reconcileInterruptedIngestWorkSessions(repository: CatalogRepository) throws {
        let interruptedStatuses: [WorkSessionStatus] = [.queued, .running, .paused]
        for session in try repository.workSessions(kind: .ingest, statuses: interruptedStatuses) {
            var interruptedSession = session
            interruptedSession.status = .failed
            interruptedSession.detail = interruptedIngestDetail(previousDetail: session.detail)
            interruptedSession.failureCount += 1
            interruptedSession.updatedAt = Date()
            try repository.save(interruptedSession)
        }
    }

    private static func interruptedIngestDetail(previousDetail: String) -> String {
        let baseDetail = "Import interrupted before completion"
        guard !previousDetail.isEmpty, !previousDetail.hasPrefix("Importing from ") else {
            return baseDetail
        }
        return "\(baseDetail) (last progress: \(previousDetail))"
    }

    public func select(_ assetID: AssetID) {
        selectAssetID(assetID)
    }

    private func selectAssetID(_ assetID: AssetID?) {
        selectedAssetID = assetID
        updateCompareSetAfterSelectionChange(to: assetID)
        guard let assetID else { return }
        do {
            try refreshSelectedPreviewGenerationQueueStates(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            try refreshSelectedMetadataSyncState(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            try enqueueMetadataSyncCheck(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectSidebarRow(_ row: SidebarRow) throws {
        try selectSidebarTarget(row.target)
    }

    public func selectSidebarTarget(_ target: SidebarRowTarget) throws {
        switch target {
        case .allPhotographs:
            selectedAssetSetID = nil
            selectedView = .grid
            try clearLibraryFilters()
        case .search:
            selectedAssetSetID = nil
            selectedView = .search
        case .copilot:
            selectedAssetSetID = nil
            selectedView = .copilot
        case .timeline:
            selectedAssetSetID = nil
            selectedView = .timeline
        case .people:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            selectedView = .people
        case .reviewQueue(let queue):
            try applyReviewQueue(queue)
        case .folder(let path):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            folderFilterText = path
            selectedView = .grid
            try reload()
        case .sourceAvailability(let availability):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            availabilityFilter = availability
            selectedView = .grid
            try reload()
        case .evaluationKind(let kind):
            try applyEvaluationKindFilter(kind)
        case .metadataSyncPending:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            metadataSyncPendingFilter = true
            selectedView = .grid
            try reload()
        case .metadataSyncConflicts:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            metadataSyncConflictFilter = true
            selectedView = .grid
            try reload()
        case .assetSet(let id):
            try applyAssetSet(id: id)
        case .workSession(let id):
            try applyWorkSession(id: id)
        case .placeholder:
            break
        }
    }

    public func applyWorkSession(id: WorkSessionID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let session = try catalog.repository.session(id: id)
        if let assetSetID = session.outputSetIDs.first ?? session.inputSetIDs.first {
            try applyAssetSet(id: assetSetID)
            if session.kind == .culling {
                selectedView = .loupe
            }
            return
        }
        statusMessage = session.detail.isEmpty ? session.title : session.detail
    }

    @discardableResult
    public func openLatestImportCompletion() throws -> ImportCompletionSummary {
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("no completed import")
        }
        try applyWorkSession(id: WorkSessionID(rawValue: summary.activityID))
        return summary
    }

    @discardableResult
    public func beginCullingFromLatestImportCompletion() throws -> WorkSession {
        let summary = try openLatestImportCompletion()
        return try beginCullingSession(named: summary.cullingSessionName)
    }

    public func reviewLatestImportInCompare() throws {
        _ = try openLatestImportCompletion()
        selectedView = .compare
    }

    @discardableResult
    public func acceptLatestImportBatchKeywordSuggestion(_ keyword: String) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetIDs = try latestImportOutputAssetIDs(repository: catalog.repository)
        _ = try openLatestImportCompletion()
        return try acceptBatchKeywordSuggestion(keyword, assetIDs: assetIDs)
    }

    public func canToggleWorkSessionStarred(_ activity: AppWorkActivity) -> Bool {
        catalog != nil && persistedWorkActivityIDs.contains(activity.id)
    }

    public func canToggleWorkSessionStarred(_ row: SidebarRow) -> Bool {
        guard catalog != nil,
              case .workSession(let id) = row.target else {
            return false
        }
        return persistedWorkActivityIDs.contains(id.rawValue)
    }

    public func sidebarContextActions(for row: SidebarRow) -> [SidebarRowContextAction] {
        switch row.target {
        case .assetSet(let id):
            guard canToggleAssetSetStarred(row),
                  let assetSet = savedAssetSets.first(where: { $0.id == id }) else {
                return []
            }
            return [
                SidebarRowContextAction(
                    kind: .toggleAssetSetStarred(id),
                    title: assetSet.starred ? "Remove Star" : "Star Set",
                    systemImage: assetSet.starred ? "star.slash" : "star"
                )
            ]
        case .workSession(let id):
            guard canToggleWorkSessionStarred(row),
                  let activity = workActivity(id: id) else {
                return []
            }
            return [
                SidebarRowContextAction(
                    kind: .toggleWorkSessionStarred(id),
                    title: activity.starred ? "Remove Star" : "Star Work",
                    systemImage: activity.starred ? "star.slash" : "star"
                )
            ]
        default:
            return []
        }
    }

    public func performSidebarContextAction(_ action: SidebarRowContextAction) throws {
        switch action.kind {
        case .toggleAssetSetStarred(let id):
            try toggleAssetSetStarred(id: id)
        case .toggleWorkSessionStarred(let id):
            try toggleWorkSessionStarred(id: id)
        }
    }

    public func toggleWorkSessionStarred(id: WorkSessionID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let session = try catalog.repository.session(id: id)
        try setWorkSessionStarred(id: id, starred: !session.starred)
    }

    public func setWorkSessionStarred(id: WorkSessionID, starred: Bool) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var session = try catalog.repository.session(id: id)
        session.starred = starred
        try catalog.repository.save(session)
        try refreshWorkSessions()
    }

    public func canToggleAssetSetStarred(_ row: SidebarRow) -> Bool {
        guard catalog != nil,
              case .assetSet(let id) = row.target else {
            return false
        }
        return savedAssetSets.contains { $0.id == id }
    }

    public func toggleAssetSetStarred(id: AssetSetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetSet = try catalog.repository.assetSet(id: id)
        try setAssetSetStarred(id: id, starred: !assetSet.starred)
    }

    public func setAssetSetStarred(id: AssetSetID, starred: Bool) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        var assetSet = try catalog.repository.assetSet(id: id)
        assetSet.starred = starred
        try catalog.repository.upsert(assetSet)
        try refreshSavedAssetSets()
    }

    private func workActivity(id: WorkSessionID) -> AppWorkActivity? {
        recentWork.first { $0.id == id.rawValue } ?? starredWork.first { $0.id == id.rawValue }
    }

    public func applyAssetSet(id: AssetSetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetSet = try assetSetForSelection(id: id, repository: catalog.repository)
        if !savedAssetSets.contains(where: { $0.id == assetSet.id }) {
            savedAssetSets.append(assetSet)
            assetSetCounts[assetSet.id] = try Self.assetCount(for: assetSet, repository: catalog.repository)
            rebuildSidebarSections()
        }
        selectedAssetSetID = id
        clearLibraryQueryFilters()
        selectedView = .grid
        try reload()
    }

    public func refreshSavedAssetSets() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        rebuildSidebarSections()
    }

    private func refreshWorkSessions() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        recentWork = try catalog.repository.workSessions(limit: 10).map(AppWorkActivity.init)
        starredWork = try catalog.repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        rebuildSidebarSections()
    }

    @discardableResult
    public func saveCurrentLibraryQuery(named name: String, starred: Bool = false) throws -> AssetSet {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("saved search name is required")
        }
        guard let query = currentLibraryQuery() else {
            throw TeststripError.invalidState("there is no active search to save")
        }
        let assetSet = AssetSet(
            id: .new(),
            name: trimmedName,
            membership: .dynamic(query),
            starred: starred
        )
        return try saveAndSelect(assetSet)
    }

    @discardableResult
    public func saveSelectedAssetAsManualSet(named name: String, starred: Bool = false) throws -> AssetSet {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("manual set name is required")
        }
        let assetSet = AssetSet(
            id: .new(),
            name: trimmedName,
            membership: .manual([selectedAssetID]),
            starred: starred
        )
        return try saveAndSelect(assetSet)
    }

    @discardableResult
    public func saveCurrentAssetScopeSnapshot(named name: String, starred: Bool = false) throws -> AssetSet {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("snapshot set name is required")
        }
        let assetIDs = try currentAssetScopeIDs(repository: catalog.repository)
        guard !assetIDs.isEmpty else {
            throw TeststripError.invalidState("there are no photos to snapshot")
        }
        let assetSet = AssetSet(
            id: .new(),
            name: trimmedName,
            membership: .snapshot(assetIDs),
            starred: starred
        )
        return try saveAndSelect(assetSet)
    }

    private func saveAndSelect(_ assetSet: AssetSet) throws -> AssetSet {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.upsert(assetSet)
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        selectedAssetSetID = assetSet.id
        clearLibraryQueryFilters()
        rebuildSidebarSections()
        try reload()
        statusMessage = "Saved \(assetSet.name)"
        return assetSet
    }

    @discardableResult
    public func beginCullingSession(named name: String, intent: String = "") throws -> WorkSession {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !assets.isEmpty else {
            throw TeststripError.invalidState("there are no photos to cull")
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw TeststripError.invalidState("culling session name is required")
        }
        let trimmedIntent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = WorkSessionID.new()
        let totalUnitCount = try currentLibraryAssetCount(repository: catalog.repository)
        let inputSetID = try cullingInputSetID(sessionID: sessionID, title: title)
        let previousSelection = selectedAssetID

        try applyAssetSet(id: inputSetID)
        if let previousSelection, assets.contains(where: { $0.id == previousSelection }) {
            selectedAssetID = previousSelection
        }
        selectedView = .loupe

        let detail = trimmedIntent.isEmpty ? "Culling \(Self.photoCountDescription(totalUnitCount))" : trimmedIntent
        let activity = AppWorkActivity(
            id: sessionID.rawValue,
            kind: .culling,
            status: .running,
            title: title,
            detail: detail,
            completedUnitCount: 0,
            totalUnitCount: totalUnitCount,
            failureCount: 0
        )
        recordRecentActivity(
            activity,
            intent: trimmedIntent.isEmpty ? title : trimmedIntent,
            inputSetIDs: [inputSetID]
        )
        statusMessage = "Started \(title)"
        return try catalog.repository.session(id: sessionID)
    }

    public func openAssetInLoupe(_ assetID: AssetID) {
        select(assetID)
        selectedView = .loupe
    }

    public func compareAssets(limit: Int = 4) -> [Asset] {
        let boundedLimit = max(1, limit)
        if let compareAssetIDs {
            let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            let anchoredAssets = compareAssetIDs.compactMap { assetsByID[$0] }
            if !anchoredAssets.isEmpty {
                return Array(anchoredAssets.prefix(boundedLimit))
            }
        }
        if let candidateStack = candidateStackAssets(limit: boundedLimit, anchor: selectedAssetID) {
            return candidateStack
        }
        return compareWindowAssets(limit: boundedLimit, anchor: selectedAssetID)
    }

    public func compareGroupKind(limit: Int = 4) -> CompareGroupKind {
        let boundedLimit = max(1, limit)
        let candidateStackIDs = candidateStackAssets(limit: boundedLimit, anchor: selectedAssetID)?.map(\.id)
        if let compareAssetIDs, !compareAssetIDs.isEmpty {
            return compareAssetIDs == candidateStackIDs ? .candidateStack : .nearbyFrames
        }
        return candidateStackIDs == nil ? .nearbyFrames : .candidateStack
    }

    public var canKeepComparePrimaryAndRejectAlternates: Bool {
        catalog != nil && !compareAssets().isEmpty
    }

    public func keepComparePrimaryAndRejectAlternates() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let compareGroup = compareAssets()
        guard let primaryAsset = comparePrimaryAsset(in: compareGroup) else {
            throw TeststripError.invalidState("no compare set")
        }

        var changedCount = 0
        var rejectedCount = 0
        for compareAsset in compareGroup {
            let targetFlag: PickFlag = compareAsset.id == primaryAsset.id ? .pick : .reject
            let originalAsset = try catalog.repository.asset(id: compareAsset.id)
            guard originalAsset.metadata.flag != targetFlag else {
                if targetFlag == .reject {
                    rejectedCount += 1
                }
                continue
            }
            var updatedMetadata = originalAsset.metadata
            updatedMetadata.flag = targetFlag
            try applyMetadataSnapshot(assetID: compareAsset.id, metadata: updatedMetadata)
            metadataUndoStack.append(MetadataChange(
                assetID: compareAsset.id,
                before: originalAsset.metadata,
                after: updatedMetadata
            ))
            if targetFlag == .reject {
                rejectedCount += 1
            }
            changedCount += 1
        }

        if changedCount > 0 {
            metadataRedoStack.removeAll()
        }
        statusMessage = rejectedCount == 0
            ? "Kept \(primaryAsset.originalURL.lastPathComponent)"
            : "Kept \(primaryAsset.originalURL.lastPathComponent); rejected \(rejectedCount) alternates"
    }

    private func comparePrimaryAsset(in compareGroup: [Asset]) -> Asset? {
        if let selectedAssetID,
           let selectedAsset = compareGroup.first(where: { $0.id == selectedAssetID }) {
            return selectedAsset
        }
        return compareGroup.first
    }

    private func compareWindowAssets(limit: Int, anchor: AssetID?) -> [Asset] {
        Self.limitedCompareAssets(assets, limit: limit, anchor: anchor)
    }

    private func candidateStackAssets(limit: Int, anchor: AssetID?) -> [Asset]? {
        guard !assets.isEmpty else { return nil }
        guard let selectedAssetID = anchor,
              assets.contains(where: { $0.id == selectedAssetID }) else {
            return nil
        }
        let stack = AssetStackBuilder(maximumCaptureGap: Self.candidateStackMaximumCaptureGap)
            .stacks(from: assets)
            .first { $0.assetIDs.contains(selectedAssetID) }
        guard let stack, stack.assetIDs.count > 1 else {
            return nil
        }

        let stackAssetIDs = Set(stack.assetIDs)
        let stackAssets = assets.filter { stackAssetIDs.contains($0.id) }
        return Self.limitedCompareAssets(stackAssets, limit: limit, anchor: anchor)
    }

    private static func limitedCompareAssets(_ assets: [Asset], limit: Int, anchor: AssetID?) -> [Asset] {
        guard !assets.isEmpty else { return [] }
        let boundedLimit = max(1, limit)
        let selectedIndex = anchor.flatMap { selectedID in
            assets.firstIndex { $0.id == selectedID }
        } ?? 0
        let maximumStartIndex = max(assets.count - boundedLimit, 0)
        let startIndex = min(max(selectedIndex - 1, 0), maximumStartIndex)
        let endIndex = min(startIndex + boundedLimit, assets.count)
        return Array(assets[startIndex..<endIndex])
    }

    private func compareWindowAssetIDs(limit: Int, anchor: AssetID?) -> [AssetID] {
        if let candidateStack = candidateStackAssets(limit: limit, anchor: anchor) {
            return candidateStack.map(\.id)
        }
        return compareWindowAssets(limit: limit, anchor: anchor).map(\.id)
    }

    private func updateCompareSetAfterViewChange(from previousView: LibraryViewMode) {
        guard selectedView == .compare else {
            compareAssetIDs = nil
            return
        }
        guard previousView != .compare else { return }
        compareAssetIDs = compareWindowAssetIDs(limit: Self.defaultCompareAssetLimit, anchor: selectedAssetID)
    }

    private func updateCompareSetAfterSelectionChange(to assetID: AssetID?) {
        guard selectedView == .compare else { return }
        guard let assetID else {
            compareAssetIDs = nil
            return
        }
        if let compareAssetIDs, compareAssetIDs.contains(assetID) {
            return
        }
        compareAssetIDs = compareWindowAssetIDs(limit: Self.defaultCompareAssetLimit, anchor: assetID)
    }

    public func selectNextAsset() {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectAssetID(assets.first?.id)
            return
        }
        selectAssetID(assets[min(index + 1, assets.count - 1)].id)
    }

    public func selectPreviousAsset() {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectAssetID(assets.first?.id)
            return
        }
        selectAssetID(assets[max(index - 1, 0)].id)
    }

    public func applyCullingCommand(_ command: CullingCommand) throws {
        switch command {
        case .rating(let rating):
            try setRatingForSelectedAsset(rating)
        case .colorLabel(let colorLabel):
            try setColorLabelForSelectedAsset(colorLabel)
        case .pick:
            try setFlagForSelectedAsset(.pick)
        case .reject:
            try setFlagForSelectedAsset(.reject)
        case .clearFlag:
            try setFlagForSelectedAsset(nil)
        }
    }

    public func keepSelectedStackFrameAndRejectAlternates() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let stacks = cullingStacks()
        guard let stack = stacks.first(where: { $0.assetIDs.contains(selectedAssetID) }),
              stack.assetIDs.count > 1 else {
            throw TeststripError.invalidState("selected asset is not in a culling stack")
        }
        let nextAssetID = nextAssetID(after: stack)

        for assetID in stack.assetIDs {
            var metadata = try catalog.repository.asset(id: assetID).metadata
            metadata.flag = assetID == selectedAssetID ? .pick : .reject
            try applyMetadataSnapshot(assetID: assetID, metadata: metadata)
        }

        if let nextAssetID {
            selectAssetID(nextAssetID)
        }
    }

    public func applyCullingShortcut(_ shortcut: CullingShortcut) throws {
        switch shortcut {
        case .previousPhoto:
            try selectPreviousAssetForCulling()
        case .nextPhoto:
            try selectNextAssetForCulling()
        case .previousStack:
            selectPreviousStackForCulling()
        case .nextStack:
            selectNextStackForCulling()
        case .rating(let rating):
            try applyCullingCommandAndAdvance(.rating(rating))
        case .colorLabel(let colorLabel):
            try applyCullingCommandAndAdvance(.colorLabel(colorLabel))
        case .pick:
            try applyCullingCommandAndAdvance(.pick)
        case .reject:
            try applyCullingCommandAndAdvance(.reject)
        case .clearFlag:
            try applyCullingCommandAndAdvance(.clearFlag)
        case .acceptStackSelection:
            try acceptSelectedStackSelectionForCulling()
        }
    }

    private func applyCullingCommandAndAdvance(_ command: CullingCommand) throws {
        let originalSelection = selectedAssetID
        try applyCullingCommand(command)
        if selectedAssetID == originalSelection {
            try selectNextAssetForCulling()
        }
    }

    private func selectNextAssetForCulling() throws {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectAssetID(assets.first?.id)
            return
        }
        if index == assets.count - 1, hasMoreAssets {
            try loadMoreAssets()
            guard let reloadedIndex = assets.firstIndex(where: { $0.id == currentSelection }) else {
                selectAssetID(assets.first?.id)
                return
            }
            selectAssetID(assets[min(reloadedIndex + 1, assets.count - 1)].id)
            return
        }
        selectAssetID(assets[min(index + 1, assets.count - 1)].id)
    }

    private func nextAssetID(after stack: AssetStack) -> AssetID? {
        let stackAssetIDs = Set(stack.assetIDs)
        guard let lastStackIndex = assets.lastIndex(where: { stackAssetIDs.contains($0.id) }) else {
            return nil
        }
        let nextIndex = assets.index(after: lastStackIndex)
        guard assets.indices.contains(nextIndex) else {
            return nil
        }
        return assets[nextIndex].id
    }

    private func cullingStacks() -> [AssetStack] {
        AssetStackBuilder(
            maximumCaptureGap: Self.candidateStackMaximumCaptureGap
        ).stacks(from: assets).filter { $0.assetIDs.count > 1 }
    }

    private func selectNextStackForCulling() {
        selectCullingStack(.next)
    }

    private func selectPreviousStackForCulling() {
        selectCullingStack(.previous)
    }

    private func acceptSelectedStackSelectionForCulling() throws {
        guard let selectedAssetID,
              cullingStacks().contains(where: { $0.assetIDs.contains(selectedAssetID) }) else {
            return
        }
        try keepSelectedStackFrameAndRejectAlternates()
    }

    private func selectCullingStack(_ direction: CullingStackNavigationDirection) {
        let indexedStacks = cullingStacks().compactMap { stack -> IndexedCullingStack? in
            let stackAssetIDs = Set(stack.assetIDs)
            guard let firstIndex = assets.firstIndex(where: { stackAssetIDs.contains($0.id) }),
                  let lastIndex = assets.lastIndex(where: { stackAssetIDs.contains($0.id) }) else {
                return nil
            }
            return IndexedCullingStack(stack: stack, firstIndex: firstIndex, lastIndex: lastIndex)
        }
        guard !indexedStacks.isEmpty else { return }

        guard let selectedAssetID,
              let selectedIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            selectAssetID(direction == .next ? indexedStacks.first?.firstAssetID : indexedStacks.last?.firstAssetID)
            return
        }

        let selectedStackIndex = indexedStacks.firstIndex { indexedStack in
            indexedStack.stack.assetIDs.contains(selectedAssetID)
        }
        let targetStack: IndexedCullingStack?
        switch direction {
        case .previous:
            if let selectedStackIndex {
                targetStack = indexedStacks.indices.contains(selectedStackIndex - 1) ? indexedStacks[selectedStackIndex - 1] : nil
            } else {
                targetStack = indexedStacks.last { $0.lastIndex < selectedIndex }
            }
        case .next:
            if let selectedStackIndex {
                targetStack = indexedStacks.indices.contains(selectedStackIndex + 1) ? indexedStacks[selectedStackIndex + 1] : nil
            } else {
                targetStack = indexedStacks.first { $0.firstIndex > selectedIndex }
            }
        }

        if let targetStack {
            selectAssetID(targetStack.firstAssetID)
        }
    }

    private func selectPreviousAssetForCulling() throws {
        guard !assets.isEmpty else {
            selectAssetID(nil)
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectAssetID(assets.first?.id)
            return
        }
        if index == 0, hasPreviousAssets {
            try loadPreviousAssets()
            guard let reloadedIndex = assets.firstIndex(where: { $0.id == currentSelection }) else {
                selectAssetID(assets.last?.id)
                return
            }
            selectAssetID(assets[max(reloadedIndex - 1, 0)].id)
            return
        }
        selectAssetID(assets[max(index - 1, 0)].id)
    }

    public func setRatingForSelectedAsset(_ rating: Int) throws {
        guard (0...5).contains(rating) else {
            throw TeststripError.invalidState("rating must be between 0 and 5")
        }
        try updateSelectedAssetMetadata { metadata in
            metadata.rating = rating
        }
    }

    public func setFlagForSelectedAsset(_ flag: PickFlag?) throws {
        try updateSelectedAssetMetadata { metadata in
            metadata.flag = flag
        }
    }

    public func setColorLabelForSelectedAsset(_ colorLabel: ColorLabel?) throws {
        try updateSelectedAssetMetadata { metadata in
            metadata.colorLabel = colorLabel
        }
    }

    public func setKeywordTextForSelectedAsset(_ keywordText: String) throws {
        try updateSelectedAssetMetadata { metadata in
            metadata.keywords = Self.keywords(from: keywordText)
        }
    }

    public func acceptSuggestedKeywordForSelectedAsset(_ keyword: String) throws {
        let cleanedKeyword = Self.cleanedKeyword(keyword)
        guard !cleanedKeyword.isEmpty else { return }
        try updateSelectedAssetMetadata { metadata in
            guard !Self.keywordList(metadata.keywords, contains: cleanedKeyword) else { return }
            metadata.keywords.append(cleanedKeyword)
        }
    }

    @discardableResult
    public func acceptVisibleBatchKeywordSuggestion(_ keyword: String) throws -> Int {
        try acceptBatchKeywordSuggestion(keyword, assetIDs: assets.map(\.id))
    }

    @discardableResult
    private func acceptBatchKeywordSuggestion(_ keyword: String, assetIDs: [AssetID]) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let cleanedKeyword = Self.cleanedKeyword(keyword)
        guard !cleanedKeyword.isEmpty else { return 0 }
        var appliedCount = 0

        for assetID in assetIDs {
            guard try assetNeedsSuggestedKeyword(assetID: assetID, keyword: cleanedKeyword) else {
                continue
            }
            let originalAsset = try catalog.repository.asset(id: assetID)
            var updatedMetadata = originalAsset.metadata
            guard !Self.keywordList(updatedMetadata.keywords, contains: cleanedKeyword) else {
                continue
            }
            updatedMetadata.keywords.append(cleanedKeyword)

            try applyMetadataSnapshot(assetID: assetID, metadata: updatedMetadata)
            metadataUndoStack.append(MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: updatedMetadata
            ))
            appliedCount += 1
        }

        if appliedCount > 0 {
            metadataRedoStack.removeAll()
            statusMessage = "Applied \(cleanedKeyword) to \(Self.photoCountDescription(appliedCount))"
        }
        return appliedCount
    }

    public func setCaptionForSelectedAsset(_ caption: String) throws {
        try updateSelectedAssetMetadata { metadata in
            metadata.caption = Self.portableText(from: caption)
        }
    }

    public func setCreatorForSelectedAsset(_ creator: String) throws {
        try updateSelectedAssetMetadata { metadata in
            metadata.creator = Self.portableText(from: creator)
        }
    }

    public func setCopyrightForSelectedAsset(_ copyright: String) throws {
        try updateSelectedAssetMetadata { metadata in
            metadata.copyright = Self.portableText(from: copyright)
        }
    }

    public func resolveSelectedMetadataConflictUsingCatalog() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try resolveMetadataConflictUsingCatalog(assetID: selectedAssetID)
    }

    public func resolveSelectedMetadataConflictUsingSidecar() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try resolveMetadataConflictUsingSidecar(assetID: selectedAssetID)
    }

    public func resolveSelectedMetadataConflictByMergingMissingSidecarFields() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try resolveMetadataConflictByMergingMissingSidecarFields(assetID: selectedAssetID)
    }

    public func retrySelectedMetadataSync() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let pendingItem = try pendingMetadataSyncItem(assetID: selectedAssetID, repository: catalog.repository)
        let asset = try catalog.repository.asset(id: selectedAssetID)
        guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
            throw TeststripError.invalidState("XMP sidecar folder is not writable or original is unavailable")
        }

        if workerSupervisor != nil {
            try enqueueMetadataSyncWork(pendingItem: pendingItem, placement: .front)
            return
        }

        try syncMetadataSidecar(for: asset)
        try refreshMetadataSyncState()
    }

    @discardableResult
    public func retryPendingMetadataSyncInCurrentScope(
        limit: Int? = nil
    ) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard workerSupervisor != nil else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }

        let resolvedLimit = limit ?? Self.metadataSyncStateDisplayLimit
        var queuedCount = 0
        for asset in assets.prefix(max(0, resolvedLimit)) {
            guard let pendingItem = try catalog.repository.pendingMetadataSyncItem(assetID: asset.id) else {
                continue
            }
            guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
                continue
            }
            guard !hasActiveMetadataSyncWork(
                assetID: asset.id,
                generation: pendingItem.catalogGeneration
            ) else {
                continue
            }

            try enqueueMetadataSyncWork(pendingItem: pendingItem)
            queuedCount += 1
        }

        statusMessage = queuedCount == 1
            ? "Queued 1 XMP retry"
            : "Queued \(queuedCount) XMP retries"
        return queuedCount
    }

    public func undoMetadataChange() throws {
        guard let change = metadataUndoStack.popLast() else { return }
        try applyMetadataSnapshot(assetID: change.assetID, metadata: change.before)
        metadataRedoStack.append(change)
    }

    public func redoMetadataChange() throws {
        guard let change = metadataRedoStack.popLast() else { return }
        try applyMetadataSnapshot(assetID: change.assetID, metadata: change.after)
        metadataUndoStack.append(change)
    }

    private func updateSelectedAssetMetadata(_ update: (inout AssetMetadata) throws -> Void) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let originalAsset = try catalog.repository.asset(id: selectedAssetID)
        var updatedMetadata = originalAsset.metadata
        try update(&updatedMetadata)
        guard updatedMetadata != originalAsset.metadata else { return }

        try applyMetadataSnapshot(assetID: selectedAssetID, metadata: updatedMetadata)
        metadataUndoStack.append(MetadataChange(
            assetID: selectedAssetID,
            before: originalAsset.metadata,
            after: updatedMetadata
        ))
        metadataRedoStack.removeAll()
    }

    private static func keywords(from keywordText: String) -> [String] {
        var seen = Set<String>()
        return keywordText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func keywordSuggestions(
        from signals: [EvaluationSignal],
        existingKeywords: [String]
    ) -> [KeywordSuggestion] {
        let candidates = signals.compactMap { signal -> (keyword: String, signal: EvaluationSignal)? in
            guard signal.kind == .object,
                  case .label(let label) = signal.value else {
                return nil
            }
            let keyword = cleanedKeyword(label)
            guard !keyword.isEmpty else { return nil }
            return (keyword, signal)
        }
        .sorted { lhs, rhs in
            if lhs.signal.confidence != rhs.signal.confidence {
                return lhs.signal.confidence > rhs.signal.confidence
            }
            return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
        }

        var seen = Set(existingKeywords.map(keywordKey).filter { !$0.isEmpty })
        return candidates.compactMap { candidate in
            let key = keywordKey(candidate.keyword)
            guard seen.insert(key).inserted else { return nil }
            return KeywordSuggestion(
                keyword: candidate.keyword,
                sourceKind: candidate.signal.kind,
                confidence: candidate.signal.confidence,
                providerName: candidate.signal.provenance.provider,
                modelName: candidate.signal.provenance.model
            )
        }
    }

    private func batchKeywordSuggestions(for assets: [Asset]) -> [BatchKeywordSuggestion] {
        var accumulatorsByKey: [String: BatchKeywordAccumulator] = [:]

        for asset in assets {
            let existingKeys = Set(asset.metadata.keywords.map(Self.keywordKey).filter { !$0.isEmpty })
            var assetKeys = Set<String>()
            for signal in evaluationSignals(for: asset.id) {
                guard signal.kind == .object,
                      case .label(let label) = signal.value else {
                    continue
                }
                let keyword = Self.cleanedKeyword(label)
                let key = Self.keywordKey(keyword)
                guard !key.isEmpty,
                      !existingKeys.contains(key),
                      assetKeys.insert(key).inserted else {
                    continue
                }

                var accumulator = accumulatorsByKey[key] ?? BatchKeywordAccumulator(
                    keyword: keyword,
                    assetCount: 0,
                    confidenceTotal: 0,
                    providerName: signal.provenance.provider,
                    modelName: signal.provenance.model,
                    bestConfidence: signal.confidence
                )
                accumulator.assetCount += 1
                accumulator.confidenceTotal += signal.confidence
                if signal.confidence > accumulator.bestConfidence {
                    accumulator.providerName = signal.provenance.provider
                    accumulator.modelName = signal.provenance.model
                    accumulator.bestConfidence = signal.confidence
                }
                accumulatorsByKey[key] = accumulator
            }
        }

        return accumulatorsByKey.values
            .map { accumulator in
                BatchKeywordSuggestion(
                    keyword: accumulator.keyword,
                    assetCount: accumulator.assetCount,
                    averageConfidence: accumulator.averageConfidence,
                    providerName: accumulator.providerName,
                    modelName: accumulator.modelName
                )
            }
            .sorted { lhs, rhs in
                if lhs.assetCount != rhs.assetCount {
                    return lhs.assetCount > rhs.assetCount
                }
                if lhs.averageConfidence != rhs.averageConfidence {
                    return lhs.averageConfidence > rhs.averageConfidence
                }
                return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
            }
    }

    private func assetNeedsSuggestedKeyword(assetID: AssetID, keyword: String) throws -> Bool {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let key = Self.keywordKey(keyword)
        guard !key.isEmpty else { return false }

        let asset = try catalog.repository.asset(id: assetID)
        guard !Self.keywordList(asset.metadata.keywords, contains: keyword) else {
            return false
        }

        return try catalog.repository.evaluationSignals(assetID: assetID).contains { signal in
            guard signal.kind == .object,
                  case .label(let label) = signal.value else {
                return false
            }
            return Self.keywordKey(label) == key
        }
    }

    private static func keywordList(_ keywords: [String], contains keyword: String) -> Bool {
        let key = keywordKey(keyword)
        guard !key.isEmpty else { return false }
        return keywords.contains { keywordKey($0) == key }
    }

    private static func metadataByMergingMissingSidecarFields(
        catalogMetadata: AssetMetadata,
        sidecarMetadata: AssetMetadata
    ) -> AssetMetadata {
        var mergedMetadata = catalogMetadata
        if mergedMetadata.rating == 0 {
            mergedMetadata.rating = sidecarMetadata.rating
        }
        if mergedMetadata.colorLabel == nil {
            mergedMetadata.colorLabel = sidecarMetadata.colorLabel
        }
        if mergedMetadata.flag == nil {
            mergedMetadata.flag = sidecarMetadata.flag
        }
        for keyword in sidecarMetadata.keywords where !keywordList(mergedMetadata.keywords, contains: keyword) {
            mergedMetadata.keywords.append(keyword)
        }
        if mergedMetadata.caption == nil {
            mergedMetadata.caption = sidecarMetadata.caption
        }
        if mergedMetadata.creator == nil {
            mergedMetadata.creator = sidecarMetadata.creator
        }
        if mergedMetadata.copyright == nil {
            mergedMetadata.copyright = sidecarMetadata.copyright
        }
        return mergedMetadata
    }

    private static func cleanedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keywordKey(_ keyword: String) -> String {
        cleanedKeyword(keyword).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func portableText(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyMetadataSnapshot(assetID: AssetID, metadata: AssetMetadata) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        try catalog.repository.updateMetadata(assetID: assetID) { currentMetadata in
            currentMetadata = metadata
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        try syncMetadataSidecar(for: updatedAsset)
        try refreshCatalogSidebarCounts()
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else {
            return
        }
        assets[index] = updatedAsset
    }

    private func syncMetadataSidecar(for asset: Asset) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let generation = try catalog.repository.catalogGeneration(assetID: asset.id)
        let lastFingerprint = try catalog.repository.lastMetadataSyncFingerprint(assetID: asset.id)
        let pendingItem = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: catalog.metadataSidecarStore.sidecarURL(forOriginalAt: asset.originalURL),
            catalogGeneration: generation,
            lastSyncedFingerprint: lastFingerprint
        )
        if workerSupervisor != nil {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            upsertPendingMetadataSyncItem(pendingItem)
            try enqueueMetadataSyncWork(pendingItem: pendingItem)
            return
        }
        do {
            let result = try catalog.metadataSidecarStore.write(metadata: asset.metadata, forOriginalAt: asset.originalURL)
            try catalog.repository.markMetadataSynced(
                assetID: asset.id,
                sidecarURL: result.sidecarURL,
                catalogGeneration: generation,
                fingerprint: result.fingerprint
            )
            pendingMetadataSyncItems.removeAll { $0.assetID == asset.id }
        } catch {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            upsertPendingMetadataSyncItem(pendingItem)
            statusMessage = "XMP write pending for \(asset.originalURL.lastPathComponent)"
        }
    }

    private func resolveMetadataConflictUsingCatalog(assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let conflict = try metadataSyncConflictItem(assetID: assetID, repository: catalog.repository)
        let asset = try catalog.repository.asset(id: assetID)
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        let pendingItem = MetadataSyncItem(
            assetID: assetID,
            sidecarURL: conflict.sidecarURL,
            catalogGeneration: generation,
            lastSyncedFingerprint: conflict.lastSyncedFingerprint
        )

        do {
            let result = try catalog.metadataSidecarStore.write(metadata: asset.metadata, forOriginalAt: asset.originalURL)
            try catalog.repository.markMetadataSynced(
                assetID: assetID,
                sidecarURL: result.sidecarURL,
                catalogGeneration: generation,
                fingerprint: result.fingerprint
            )
            clearMetadataSyncState(assetID: assetID)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "Resolved XMP conflict using catalog metadata"
        } catch {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            metadataSyncConflictItems.removeAll { $0.assetID == assetID }
            upsertPendingMetadataSyncItem(pendingItem)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "XMP write pending for \(asset.originalURL.lastPathComponent)"
        }
    }

    private func resolveMetadataConflictUsingSidecar(assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let conflict = try metadataSyncConflictItem(assetID: assetID, repository: catalog.repository)
        let originalAsset = try catalog.repository.asset(id: assetID)
        let sidecarData = try Data(contentsOf: conflict.sidecarURL)
        let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata

        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            metadata = sidecarMetadata
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        try catalog.repository.markMetadataSynced(
            assetID: assetID,
            sidecarURL: conflict.sidecarURL,
            catalogGeneration: generation,
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )
        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
        try refreshCatalogSidebarCounts()
        if originalAsset.metadata != sidecarMetadata {
            metadataUndoStack.append(MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: sidecarMetadata
            ))
            metadataRedoStack.removeAll()
        }
        clearMetadataSyncState(assetID: assetID)
        try refreshAfterMetadataConflictResolution()
        statusMessage = "Resolved XMP conflict using sidecar metadata"
    }

    private func resolveMetadataConflictByMergingMissingSidecarFields(assetID: AssetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let conflict = try metadataSyncConflictItem(assetID: assetID, repository: catalog.repository)
        let originalAsset = try catalog.repository.asset(id: assetID)
        let sidecarData = try Data(contentsOf: conflict.sidecarURL)
        let sidecarMetadata = try XMPPacket.parse(sidecarData).metadata
        let mergedMetadata = Self.metadataByMergingMissingSidecarFields(
            catalogMetadata: originalAsset.metadata,
            sidecarMetadata: sidecarMetadata
        )

        try catalog.repository.updateMetadata(assetID: assetID) { metadata in
            metadata = mergedMetadata
        }
        let updatedAsset = try catalog.repository.asset(id: assetID)
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        let pendingItem = MetadataSyncItem(
            assetID: assetID,
            sidecarURL: conflict.sidecarURL,
            catalogGeneration: generation,
            lastSyncedFingerprint: conflict.lastSyncedFingerprint
        )

        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
        try refreshCatalogSidebarCounts()
        if originalAsset.metadata != mergedMetadata {
            metadataUndoStack.append(MetadataChange(
                assetID: assetID,
                before: originalAsset.metadata,
                after: mergedMetadata
            ))
            metadataRedoStack.removeAll()
        }

        do {
            let result = try catalog.metadataSidecarStore.write(metadata: mergedMetadata, forOriginalAt: updatedAsset.originalURL)
            try catalog.repository.markMetadataSynced(
                assetID: assetID,
                sidecarURL: result.sidecarURL,
                catalogGeneration: generation,
                fingerprint: result.fingerprint
            )
            clearMetadataSyncState(assetID: assetID)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "Resolved XMP conflict by merging sidecar fields"
        } catch {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            metadataSyncConflictItems.removeAll { $0.assetID == assetID }
            upsertPendingMetadataSyncItem(pendingItem)
            try refreshAfterMetadataConflictResolution()
            statusMessage = "XMP write pending for \(updatedAsset.originalURL.lastPathComponent)"
        }
    }

    private func metadataSyncConflictItem(assetID: AssetID, repository: CatalogRepository) throws -> MetadataSyncItem {
        if let item = metadataSyncConflictItems.first(where: { $0.assetID == assetID }) {
            return item
        }
        if let item = try repository.metadataSyncConflictItem(assetID: assetID) {
            return item
        }
        throw TeststripError.invalidState("selected asset has no XMP conflict")
    }

    private func pendingMetadataSyncItem(assetID: AssetID, repository: CatalogRepository) throws -> MetadataSyncItem {
        if let item = pendingMetadataSyncItems.first(where: { $0.assetID == assetID }) {
            return item
        }
        if let item = try repository.pendingMetadataSyncItem(assetID: assetID) {
            return item
        }
        throw TeststripError.invalidState("selected asset has no pending XMP sync")
    }

    private func clearMetadataSyncState(assetID: AssetID) {
        if pendingMetadataSyncItems.contains(where: { $0.assetID == assetID }) {
            pendingMetadataSyncCount = max(0, pendingMetadataSyncCount - 1)
        }
        if metadataSyncConflictItems.contains(where: { $0.assetID == assetID }) {
            metadataSyncConflictCount = max(0, metadataSyncConflictCount - 1)
        }
        pendingMetadataSyncItems.removeAll { $0.assetID == assetID }
        metadataSyncConflictItems.removeAll { $0.assetID == assetID }
    }

    private func refreshAfterMetadataConflictResolution() throws {
        rebuildSidebarSections()
        if metadataSyncConflictFilter {
            try reload()
        }
    }

    private func enqueueMetadataSyncCheck(for assetID: AssetID) throws {
        guard let catalog, let workerSupervisor else { return }
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
        try cancelStaleQueuedMetadataSyncChecks(keeping: assetID, generation: generation)
        guard !hasActiveMetadataSyncWork(assetID: assetID, generation: generation) else { return }
        let itemID = WorkSessionID(rawValue: "xmp-check-\(assetID.rawValue)-\(generation)-\(UUID().uuidString)")
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .xmpSync,
            title: "Check XMP",
            detail: "Checking XMP sidecar",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        metadataSyncAssetIDsByItemID[itemID] = assetID
        do {
            try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: assetID))
        } catch {
            metadataSyncAssetIDsByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func cancelStaleQueuedMetadataSyncChecks(keeping assetID: AssetID, generation: Int) throws {
        guard let workerSupervisor else { return }
        let keptPrefix = metadataSyncCheckPrefix(assetID: assetID, generation: generation)
        let staleQueuedChecks = backgroundWorkQueue.queuedItems.filter { item in
            isSelectionMetadataSyncCheck(item) && !item.id.rawValue.hasPrefix(keptPrefix)
        }
        for item in staleQueuedChecks {
            try workerSupervisor.cancel(id: item.id)
        }
        if !staleQueuedChecks.isEmpty {
            syncBackgroundWorkQueueFromSupervisor()
        }
    }

    private func hasActiveMetadataSyncWork(assetID: AssetID, generation: Int) -> Bool {
        let writeSyncID = Self.metadataSyncWorkItemID(assetID: assetID, catalogGeneration: generation).rawValue
        let selectionCheckPrefix = metadataSyncCheckPrefix(assetID: assetID, generation: generation)
        return backgroundWorkQueue.items.contains { item in
            item.kind == .xmpSync
                && [.queued, .running, .paused].contains(item.status)
                && (item.id.rawValue == writeSyncID || item.id.rawValue.hasPrefix(selectionCheckPrefix))
        }
    }

    private func metadataSyncCheckPrefix(assetID: AssetID, generation: Int) -> String {
        "xmp-check-\(assetID.rawValue)-\(generation)-"
    }

    private static func metadataSyncWorkItemID(assetID: AssetID, catalogGeneration: Int) -> WorkSessionID {
        WorkSessionID(rawValue: "xmp-\(assetID.rawValue)-\(catalogGeneration)")
    }

    private func enqueueMetadataSyncWork(
        pendingItem: MetadataSyncItem,
        placement: BackgroundWorkQueuePlacement = .back
    ) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        let itemID = Self.metadataSyncWorkItemID(
            assetID: pendingItem.assetID,
            catalogGeneration: pendingItem.catalogGeneration
        )
        if backgroundWorkQueue.item(id: itemID) != nil {
            return
        }
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .xmpSync,
            title: "Sync XMP",
            detail: "Writing XMP sidecar",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        metadataSyncAssetIDsByItemID[itemID] = pendingItem.assetID
        do {
            try workerSupervisor.enqueue(
                item,
                command: .syncMetadata(assetID: pendingItem.assetID),
                placement: placement
            )
        } catch {
            metadataSyncAssetIDsByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func isSelectionMetadataSyncCheck(_ item: BackgroundWorkItem) -> Bool {
        item.kind == .xmpSync && item.title == "Check XMP"
    }

    private func upsertPendingMetadataSyncItem(_ item: MetadataSyncItem) {
        let hadPendingItem = pendingMetadataSyncItems.contains { $0.assetID == item.assetID }
        let hadConflictItem = metadataSyncConflictItems.contains { $0.assetID == item.assetID }
        pendingMetadataSyncItems.removeAll { $0.assetID == item.assetID }
        metadataSyncConflictItems.removeAll { $0.assetID == item.assetID }
        pendingMetadataSyncItems.append(item)
        if !hadPendingItem {
            pendingMetadataSyncCount += 1
        }
        if hadConflictItem {
            metadataSyncConflictCount = max(0, metadataSyncConflictCount - 1)
        }
    }

    private func refreshMetadataSyncState() throws {
        guard let catalog else { return }
        let snapshot = try Self.metadataSyncState(repository: catalog.repository, selectedAssetID: selectedAssetID)
        pendingMetadataSyncItems = snapshot.pendingItems
        metadataSyncConflictItems = snapshot.conflictItems
        pendingMetadataSyncCount = snapshot.pendingCount
        metadataSyncConflictCount = snapshot.conflictCount
        rebuildSidebarSections()
    }

    private func refreshSelectedMetadataSyncState(for assetID: AssetID) throws {
        guard let catalog else { return }
        var snapshot = MetadataSyncStateSnapshot(
            pendingItems: pendingMetadataSyncItems,
            conflictItems: metadataSyncConflictItems,
            pendingCount: pendingMetadataSyncCount,
            conflictCount: metadataSyncConflictCount
        )
        try Self.mergeMetadataSyncState(for: assetID, repository: catalog.repository, into: &snapshot)
        pendingMetadataSyncItems = snapshot.pendingItems
        metadataSyncConflictItems = snapshot.conflictItems
    }

    private func refreshPreviewGenerationQueueStates() throws {
        guard let catalog else { return }
        previewGenerationQueueStates = try Self.previewGenerationQueueStates(
            repository: catalog.repository,
            selectedAssetID: selectedAssetID
        )
    }

    private func refreshSelectedPreviewGenerationQueueStates(for assetID: AssetID) throws {
        guard let catalog else { return }
        try Self.mergePreviewGenerationQueueStates(
            for: assetID,
            repository: catalog.repository,
            into: &previewGenerationQueueStates
        )
    }

    private func refreshSourceAvailabilitySummaries() throws {
        guard let catalog else { return }
        sourceRoots = try catalog.repository.sourceRoots()
        sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        rebuildSidebarSections()
    }

    public func enqueueBackgroundWork(_ item: BackgroundWorkItem) {
        backgroundWorkQueue.enqueue(item)
        backgroundWorkQueue.activateRunnableItems()
    }

    public func pauseBackgroundWork() {
        do {
            if let workerSupervisor {
                try workerSupervisor.pause()
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.pause()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func resumeBackgroundWork() {
        do {
            if let workerSupervisor {
                try workerSupervisor.resume()
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.resume()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelBackgroundWork() {
        do {
            let hadWorkerImport = !workerImportContextsByItemID.isEmpty
            if let workerSupervisor {
                try workerSupervisor.cancelAll()
                cancelWorkerImportContexts()
                if hadWorkerImport {
                    statusMessage = "Cancelled import"
                }
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.cancelAll()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopIdleWorkerProcess() {
        guard workerSupervisor?.stopIdleWorkerProcess() == true else { return }
        syncBackgroundWorkQueueFromSupervisor()
        statusMessage = "Worker stopped"
    }

    public func cancelBackgroundWork(id itemID: WorkSessionID) {
        do {
            if let workerSupervisor {
                try workerSupervisor.cancel(id: itemID)
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.cancel(id: itemID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    public func cancelImportWork() {
        if activeWork?.kind == .ingest || activeImportTask != nil {
            cancelActiveWork()
            return
        }

        do {
            guard let workerSupervisor, !workerImportContextsByItemID.isEmpty else { return }
            for itemID in Array(workerImportContextsByItemID.keys) {
                try workerSupervisor.cancel(id: itemID)
            }
            statusMessage = "Cancelled import"
            syncBackgroundWorkQueueFromSupervisor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestPreview(
        assetID: AssetID,
        level: PreviewLevel,
        placement: BackgroundWorkQueuePlacement = .back
    ) throws {
        try requestPreview(
            assetID: assetID,
            level: level,
            placement: placement,
            recordsPendingPreview: true,
            refreshesPreviewGenerationQueueState: true
        )
    }

    private func requestPreview(
        assetID: AssetID,
        level: PreviewLevel,
        placement: BackgroundWorkQueuePlacement = .back,
        recordsPendingPreview: Bool,
        refreshesPreviewGenerationQueueState: Bool
    ) throws {
        if previewURL(for: assetID, levels: [level]) != nil {
            return
        }
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        let itemID = Self.previewWorkItemID(assetID: assetID, level: level)
        if let existingItem = backgroundWorkQueue.item(id: itemID),
           Self.isActiveBackgroundWorkStatus(existingItem.status) {
            if placement == .front, try workerSupervisor.promoteQueuedItem(id: itemID) {
                syncBackgroundWorkQueueFromSupervisor()
            }
            return
        }
        if recordsPendingPreview, let catalog {
            try catalog.repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: assetID, level: level))
            if refreshesPreviewGenerationQueueState {
                try refreshPreviewGenerationQueueStates()
            }
        }

        let item = BackgroundWorkItem(
            id: itemID,
            kind: .previewGeneration,
            title: "Generate preview",
            detail: "Rendering \(level.rawValue) preview",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        try workerSupervisor.enqueue(
            item,
            command: .generatePreview(assetID: assetID, level: level),
            placement: placement
        )
        syncBackgroundWorkQueueFromSupervisor()
    }

    public func retrySelectedPreviewGenerationFailures() throws {
        let failures = selectedPreviewGenerationFailures
        guard !failures.isEmpty else { return }
        guard selectedAsset?.availability.requiresCachedPreviewOnly != true else {
            throw TeststripError.invalidState("original is unavailable")
        }
        for failure in failures {
            try requestPreview(assetID: failure.item.assetID, level: failure.item.level, placement: .front)
        }
    }

    private func enqueuePendingPreviewGeneration(excluding excludedItemIDs: Set<WorkSessionID> = []) throws {
        guard let catalog, let workerSupervisor else { return }
        var existingPreviewWorkItemIDs = Self.previewGenerationWorkItemIDs(in: backgroundWorkQueue)
        let availableSlotCount = max(
            0,
            Self.pendingPreviewRecoveryBatchSize - Self.activePreviewGenerationWorkCount(in: backgroundWorkQueue)
        )
        guard availableSlotCount > 0 else {
            try refreshPreviewGenerationQueueStates()
            return
        }
        var enqueuedCount = 0
        var requests: [(item: BackgroundWorkItem, command: WorkerCommand, placement: BackgroundWorkQueuePlacement)] = []
        for pendingItem in try catalog.repository.pendingPreviewGenerationItems(
            limit: Self.pendingPreviewRecoveryBatchSize,
            maximumAttemptCount: Self.previewGenerationMaximumAutomaticAttempts,
            requiresAvailableOriginal: true
        ) {
            let itemID = Self.previewWorkItemID(assetID: pendingItem.assetID, level: pendingItem.level)
            if excludedItemIDs.contains(itemID) {
                continue
            }
            if existingPreviewWorkItemIDs.contains(itemID) {
                continue
            }
            let asset = try catalog.repository.asset(id: pendingItem.assetID)
            if asset.availability.requiresCachedPreviewOnly {
                continue
            }
            if previewURL(for: pendingItem.assetID, levels: [pendingItem.level]) != nil {
                try catalog.repository.markPreviewGenerated(assetID: pendingItem.assetID, level: pendingItem.level)
                continue
            }
            let workItem = BackgroundWorkItem(
                id: itemID,
                kind: .previewGeneration,
                title: "Generate preview",
                detail: "Rendering \(pendingItem.level.rawValue) preview",
                completedUnitCount: 0,
                totalUnitCount: 1
            )
            requests.append((
                item: workItem,
                command: .generatePreview(assetID: pendingItem.assetID, level: pendingItem.level),
                placement: .back
            ))
            existingPreviewWorkItemIDs.insert(itemID)
            enqueuedCount += 1
            if enqueuedCount >= availableSlotCount {
                break
            }
        }
        try workerSupervisor.enqueue(requests)
        try refreshPreviewGenerationQueueStates()
    }

    private func enqueuePendingMetadataSync() throws {
        guard let catalog, workerSupervisor != nil else { return }
        var enqueuedCount = 0
        for pendingItem in try catalog.repository.pendingMetadataSyncItems() {
            guard enqueuedCount < Self.pendingMetadataSyncRecoveryBatchSize else {
                break
            }
            let asset = try catalog.repository.asset(id: pendingItem.assetID)
            guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
                continue
            }
            let itemID = Self.metadataSyncWorkItemID(
                assetID: pendingItem.assetID,
                catalogGeneration: pendingItem.catalogGeneration
            )
            if backgroundWorkQueue.item(id: itemID) != nil {
                continue
            }
            try enqueueMetadataSyncWork(pendingItem: pendingItem)
            enqueuedCount += 1
        }
    }

    private func canAutomaticallyRetryMetadataSync(for asset: Asset, sidecarURL: URL) -> Bool {
        guard !asset.availability.requiresCachedPreviewOnly else {
            return false
        }
        let sidecarDirectory = sidecarURL.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: sidecarDirectory.path)
    }

    public func requestVisibleGridPreview(assetID: AssetID) throws {
        if let asset = assets.first(where: { $0.id == assetID }),
           asset.availability.requiresCachedPreviewOnly {
            return
        }

        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .grid(distanceFromViewport: 0)
        )
        try requestPreview(assetID: request.assetID, level: request.level, placement: .front)
    }

    public func previewCacheGeneration(for assetID: AssetID) -> Int {
        previewCacheGenerationsByAssetID[assetID] ?? 0
    }

    public func evaluationSignalGeneration(for assetID: AssetID) -> Int {
        evaluationSignalGenerationsByAssetID[assetID] ?? 0
    }

    public func requestVisibleLoupePreview(assetID: AssetID) throws {
        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .loupe(isVisible: true, requestedFullResolution: false)
        )
        if previewURL(for: assetID, levels: [request.level]) != nil {
            return
        }
        if [.offline, .missing].contains(try refreshAvailability(for: assetID)) {
            return
        }
        if request.level == .large, previewURL(for: assetID, levels: [.medium]) == nil {
            try requestPreview(assetID: assetID, level: .medium, placement: .front)
        }
        try requestPreview(assetID: assetID, level: request.level, placement: .front)
    }

    public func requestVisibleComparePreviews() throws {
        let compareAssets = compareAssets()
        if let selectedAssetID,
           compareAssets.contains(where: { $0.id == selectedAssetID && !$0.availability.requiresCachedPreviewOnly }),
           previewURL(for: selectedAssetID, levels: [.medium]) != nil {
            try requestPreview(assetID: selectedAssetID, level: .large, placement: .front)
        }

        for asset in compareAssets {
            guard !asset.availability.requiresCachedPreviewOnly else { continue }
            try requestPreview(assetID: asset.id, level: .medium, placement: .front)
        }
    }

    public func requestEvaluation(assetID: AssetID, provider: String = AppModel.defaultEvaluationProviderName) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        guard hasCachedPreview(for: assetID) else {
            throw TeststripError.invalidState("no cached preview for \(assetID.rawValue)")
        }
        let itemID = WorkSessionID(rawValue: "evaluation-\(assetID.rawValue)-\(provider)")
        if backgroundWorkQueue.item(id: itemID) != nil {
            return
        }

        let item = BackgroundWorkItem(
            id: itemID,
            kind: .recognition,
            title: "Evaluate photo",
            detail: "Running \(provider)",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        evaluationAssetIDsByItemID[itemID] = assetID
        evaluationProvidersByItemID[itemID] = provider
        do {
            try workerSupervisor.enqueue(item, command: .runEvaluation(assetID: assetID, provider: provider))
        } catch {
            evaluationAssetIDsByItemID[itemID] = nil
            evaluationProvidersByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    public func requestSelectedAssetEvaluation(provider: String = AppModel.defaultEvaluationProviderName) throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try requestEvaluation(assetID: selectedAssetID, provider: provider)
    }

    public func requestSelectedAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        for provider in providers {
            try requestEvaluation(assetID: selectedAssetID, provider: provider)
        }
    }

    public func requestVisibleAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        guard !assets.isEmpty else {
            throw TeststripError.invalidState("no visible assets")
        }
        let evaluableAssets = assets.filter { hasCachedPreview(for: $0.id) }
        guard !evaluableAssets.isEmpty else {
            throw TeststripError.invalidState("no visible assets with cached previews")
        }
        for asset in evaluableAssets {
            for provider in providers {
                try requestEvaluation(assetID: asset.id, provider: provider)
            }
        }
    }

    public func requestCompareAssetEvaluations(providers: [String] = AppModel.defaultEvaluationProviderNames) throws {
        let compareAssets = compareAssets()
        guard !compareAssets.isEmpty else {
            throw TeststripError.invalidState("no compare assets")
        }
        let evaluableAssets = compareAssets.filter { hasCachedPreview(for: $0.id) }
        guard !evaluableAssets.isEmpty else {
            throw TeststripError.invalidState("no compare assets with cached previews")
        }
        for asset in evaluableAssets {
            for provider in providers {
                try requestEvaluation(assetID: asset.id, provider: provider)
            }
        }
    }

    private func syncBackgroundWorkQueueFromSupervisor() {
        if let workerSupervisor {
            backgroundWorkQueue = workerSupervisor.queue
        }
    }

    private static func failedPreviewGenerationItemIDs(in queue: BackgroundWorkQueue?) -> Set<WorkSessionID> {
        Set(
            queue?.items.compactMap { item in
                guard item.kind == .previewGeneration, item.status == .failed else { return nil }
                return item.id
            } ?? []
        )
    }

    private static func metadataSyncWorkChanged(
        from previousQueue: BackgroundWorkQueue?,
        to queue: BackgroundWorkQueue
    ) -> Bool {
        metadataSyncWorkStatuses(in: previousQueue) != metadataSyncWorkStatuses(in: queue)
    }

    private static func metadataSyncWorkStatuses(in queue: BackgroundWorkQueue?) -> [WorkSessionID: WorkSessionStatus] {
        Dictionary(
            uniqueKeysWithValues: queue?.items.compactMap { item in
                guard item.kind == .xmpSync else { return nil }
                return (item.id, item.status)
            } ?? []
        )
    }

    private func enqueueWorkerImport(
        source: URL,
        destinationRoot: URL?,
        command: WorkerCommand
    ) {
        guard let workerSupervisor else { return }
        let itemID = WorkSessionID(rawValue: "import-\(UUID().uuidString)")
        let didAccessSource: Bool
        let didAccessDestination: Bool
        do {
            didAccessSource = try startAccessingImportResource(source)
            do {
                if let destinationRoot {
                    didAccessDestination = try startAccessingImportResource(destinationRoot)
                } else {
                    didAccessDestination = false
                }
            } catch {
                stopAccessingImportResource(source, didAccess: didAccessSource)
                throw error
            }
        } catch {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: error.localizedDescription)
            return
        }
        let context = WorkerImportContext(
            source: source,
            destinationRoot: destinationRoot,
            didAccessSource: didAccessSource,
            didAccessDestination: didAccessDestination
        )
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .ingest,
            title: "Import photos",
            detail: "Importing from \(importSourceDescription(folderURL: source, destinationRoot: destinationRoot))",
            completedUnitCount: 0,
            totalUnitCount: nil
        )
        workerImportContextsByItemID[itemID] = context
        do {
            try workerSupervisor.enqueue(item, command: command)
            recordRecentActivity(AppWorkActivity(workItem: workerSupervisor.queue.item(id: itemID) ?? item))
            syncBackgroundWorkQueueFromSupervisor()
        } catch {
            workerImportContextsByItemID[itemID] = nil
            stopAccessingWorkerImportResources(context)
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func handleWorkerCommandCompleted(_ event: WorkerEvent) {
        switch event {
        case .completed(let itemID, _):
            let completedPreview = invalidatePreviewCacheIfNeeded(itemID: itemID)
            invalidateEvaluationSignalsIfNeeded(itemID: itemID)
            refreshLoadedAssetMetadataIfNeeded(itemID: itemID)
            refreshLoadedAssetAvailabilityIfNeeded(itemID: itemID)
            if completedPreview {
                do {
                    try enqueuePendingPreviewGeneration()
                    workerSupervisor?.pruneCompletedItems(kind: .previewGeneration, keepingLast: 1)
                    syncBackgroundWorkQueueFromSupervisor()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .completedImport(
            let itemID,
            _,
            let importedAssetIDs,
            let newAssetCount,
            let existingAssetCount,
            let skippedSourceFileCount
        ):
            handleWorkerImportCompleted(
                itemID: itemID,
                importedAssetIDs: importedAssetIDs,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount,
                skippedSourceFileCount: skippedSourceFileCount
            )
        case .accepted, .progress, .failed:
            return
        }
    }

    private func handleWorkerCommandProgress(_ event: WorkerEvent) {
        guard case .progress(let itemID, _, _, _, let catalogedAssetIDs) = event,
              let itemID,
              var context = workerImportContextsByItemID[itemID],
              context.displayedCatalogedAssetID == nil,
              let firstCatalogedAssetID = catalogedAssetIDs.first else {
            return
        }
        do {
            try loadCatalogPage(preferredSelection: firstCatalogedAssetID)
            context.displayedCatalogedAssetID = firstCatalogedAssetID
            workerImportContextsByItemID[itemID] = context
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLoadedAssetAvailabilityIfNeeded(itemID: WorkSessionID?) {
        guard let itemID,
              backgroundWorkQueue.item(id: itemID)?.kind == .sourceScan,
              let assetIDs = availabilityAssetIDsByItemID.removeValue(forKey: itemID),
              let catalog else {
            return
        }
        do {
            for assetID in assetIDs {
                let updatedAsset = try catalog.repository.asset(id: assetID)
                if let index = assets.firstIndex(where: { $0.id == assetID }) {
                    assets[index] = updatedAsset
                }
            }
            try refreshSourceAvailabilitySummaries()
            try enqueuePendingPreviewGeneration()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLoadedAssetAvailabilityForPreviewFailures(_ itemIDs: Set<WorkSessionID>) {
        let assetIDs = itemIDs.compactMap(Self.previewAssetID)
        guard !assetIDs.isEmpty, catalog != nil else { return }
        do {
            try reload()
            try refreshSourceAvailabilitySummaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLoadedAssetMetadataIfNeeded(itemID: WorkSessionID?) {
        guard let itemID,
              backgroundWorkQueue.item(id: itemID)?.kind == .xmpSync,
              let assetID = metadataSyncAssetIDsByItemID.removeValue(forKey: itemID),
              let catalog else {
            return
        }
        do {
            let updatedAsset = try catalog.repository.asset(id: assetID)
            if let index = assets.firstIndex(where: { $0.id == assetID }) {
                assets[index] = updatedAsset
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func invalidatePreviewCacheIfNeeded(itemID: WorkSessionID?) -> Bool {
        guard let itemID,
              backgroundWorkQueue.item(id: itemID)?.kind == .previewGeneration,
              let assetID = Self.previewAssetID(from: itemID) else {
            return false
        }
        previewCacheGenerationsByAssetID[assetID, default: 0] += 1
        return true
    }

    private func invalidateEvaluationSignalsIfNeeded(itemID: WorkSessionID?) {
        guard let itemID,
              backgroundWorkQueue.item(id: itemID)?.kind == .recognition,
              let assetID = evaluationAssetIDsByItemID.removeValue(forKey: itemID) else {
            return
        }
        let provider = evaluationProvidersByItemID.removeValue(forKey: itemID)
        if let provider {
            do {
                try catalog?.repository.clearEvaluationFailure(assetID: assetID, provider: provider)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        evaluationSignalGenerationsByAssetID[assetID, default: 0] += 1
        refreshCatalogEvaluationKindSummaries()
        if providerFailuresFilter {
            do {
                try reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func previewAssetID(from itemID: WorkSessionID) -> AssetID? {
        let rawValue = itemID.rawValue
        guard rawValue.hasPrefix("preview-") else {
            return nil
        }
        let prefixedAssetID = rawValue.dropFirst("preview-".count)
        for level in PreviewLevel.allCases {
            let suffix = "-\(level.rawValue)"
            if prefixedAssetID.hasSuffix(suffix) {
                return AssetID(rawValue: String(prefixedAssetID.dropLast(suffix.count)))
            }
        }
        return nil
    }

    private static func previewWorkItemID(assetID: AssetID, level: PreviewLevel) -> WorkSessionID {
        WorkSessionID(rawValue: "preview-\(assetID.rawValue)-\(level.rawValue)")
    }

    private static func previewGenerationWorkItemIDs(in queue: BackgroundWorkQueue) -> Set<WorkSessionID> {
        Set(queue.items.compactMap { item in
            guard item.kind == .previewGeneration,
                  Self.isActiveBackgroundWorkStatus(item.status) else { return nil }
            return item.id
        })
    }

    private static func activePreviewGenerationWorkCount(in queue: BackgroundWorkQueue) -> Int {
        queue.items.filter { item in
            item.kind == .previewGeneration && Self.isActiveBackgroundWorkStatus(item.status)
        }.count
    }

    private static func diagnosticsBackgroundWork(_ queue: BackgroundWorkQueue) -> AppDiagnosticsBackgroundWork {
        AppDiagnosticsBackgroundWork(
            maxRunningCount: queue.maxRunningCount,
            kindRunningLimits: sortedKindCounts(queue.kindRunningLimits),
            statusCounts: sortedStatusCounts(queue.items),
            kindCounts: sortedKindCounts(queue.items.reduce(into: [:]) { counts, item in
                counts[item.kind, default: 0] += 1
            })
        )
    }

    private static func sortedStatusCounts(_ items: [BackgroundWorkItem]) -> [AppDiagnosticsWorkStatusCount] {
        let counts = items.reduce(into: [WorkSessionStatus: Int]()) { counts, item in
            counts[item.status, default: 0] += 1
        }
        return counts
            .map { AppDiagnosticsWorkStatusCount(status: $0.key, count: $0.value) }
            .sorted { statusSortIndex($0.status) < statusSortIndex($1.status) }
    }

    private static func sortedKindCounts(_ counts: [WorkSessionKind: Int]) -> [AppDiagnosticsWorkKindCount] {
        counts
            .map { AppDiagnosticsWorkKindCount(kind: $0.key, count: $0.value) }
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private static func statusSortIndex(_ status: WorkSessionStatus) -> Int {
        switch status {
        case .queued:
            return 0
        case .running:
            return 1
        case .paused:
            return 2
        case .completed:
            return 3
        case .failed:
            return 4
        case .cancelled:
            return 5
        }
    }

    private static func sourceAvailabilityCounts(_ summaries: [CatalogSourceAvailabilitySummary]) -> [AppDiagnosticsSourceAvailabilityCount] {
        var counts: [SourceAvailability: Int] = [:]
        for summary in summaries {
            counts[summary.availability, default: 0] += summary.assetCount
        }
        return counts
            .map { AppDiagnosticsSourceAvailabilityCount(availability: $0.key, count: $0.value) }
            .sorted { $0.availability.rawValue < $1.availability.rawValue }
    }

    private func diagnosticsRecentFailures(limit: Int = 5) -> [AppDiagnosticsWorkFailure] {
        var seenIDs: Set<String> = []
        var failures: [AppDiagnosticsWorkFailure] = []

        for item in backgroundWorkQueue.items where item.status == .failed {
            let failure = AppDiagnosticsWorkFailure(
                id: item.id.rawValue,
                kind: item.kind,
                title: item.title,
                detail: item.detail,
                failureCount: 0
            )
            if seenIDs.insert(failure.id).inserted {
                failures.append(failure)
            }
        }

        for activity in recentWork where activity.status == .failed {
            let failure = AppDiagnosticsWorkFailure(
                id: activity.id,
                kind: activity.kind,
                title: activity.title,
                detail: activity.detail,
                failureCount: activity.failureCount
            )
            if seenIDs.insert(failure.id).inserted {
                failures.append(failure)
            }
        }

        return Array(failures.prefix(limit))
    }

    private static func isActiveBackgroundWorkStatus(_ status: WorkSessionStatus) -> Bool {
        [.queued, .running, .paused].contains(status)
    }

    private func handleWorkerImportCompleted(
        itemID: WorkSessionID?,
        importedAssetIDs: [AssetID],
        newAssetCount: Int,
        existingAssetCount: Int,
        skippedSourceFileCount: Int
    ) {
        guard let itemID,
              let context = workerImportContextsByItemID.removeValue(forKey: itemID) else {
            return
        }
        defer {
            stopAccessingWorkerImportResources(context)
        }
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        do {
            try loadCatalogPage(preferredSelection: importedAssetIDs.first)
            try enqueuePendingPreviewGeneration()
            let importedAssets = try catalog.repository.assets(ids: importedAssetIDs, limit: importedAssetIDs.count)
            let result = LibraryImportResult(
                importedAssets: importedAssets,
                previewFailures: [],
                skippedSourceFileCount: skippedSourceFileCount,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount
            )
            updateImportStatus(with: result)
            recordCompletedImportActivity(
                id: itemID.rawValue,
                folderURL: context.source,
                destinationRoot: context.destinationRoot,
                result: result
            )
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
            failImportActivity(id: itemID.rawValue, folderURL: context.source, destinationRoot: context.destinationRoot, error: error)
        }
    }

    private func releaseInactiveWorkerImportContexts(in queue: BackgroundWorkQueue) {
        for itemID in Array(workerImportContextsByItemID.keys) {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            if let context = workerImportContextsByItemID.removeValue(forKey: itemID) {
                stopAccessingWorkerImportResources(context)
                if item.status == .cancelled {
                    cancelImportActivity(
                        id: itemID.rawValue,
                        folderURL: context.source,
                        destinationRoot: context.destinationRoot
                    )
                } else if item.status == .failed {
                    failImportActivity(
                        id: itemID.rawValue,
                        folderURL: context.source,
                        destinationRoot: context.destinationRoot,
                        error: TeststripError.io(item.detail)
                    )
                }
            }
            if item.status == .failed {
                statusMessage = nil
                errorMessage = item.detail
            }
        }
    }

    private func releaseInactiveEvaluationContexts(in queue: BackgroundWorkQueue) {
        for itemID in Array(evaluationAssetIDsByItemID.keys) {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            let assetID = evaluationAssetIDsByItemID.removeValue(forKey: itemID)
            let provider = evaluationProvidersByItemID.removeValue(forKey: itemID)
            if item.status == .failed,
               let assetID,
               let provider,
               let catalog {
                do {
                    try catalog.repository.recordEvaluationFailure(assetID: assetID, provider: provider, message: item.detail)
                    try refreshCatalogSidebarCounts()
                    if providerFailuresFilter {
                        try reload()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func releaseInactiveMetadataSyncContexts(in queue: BackgroundWorkQueue) {
        for itemID in metadataSyncAssetIDsByItemID.keys {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            metadataSyncAssetIDsByItemID[itemID] = nil
        }
    }

    private func releaseInactiveAvailabilityContexts(in queue: BackgroundWorkQueue) {
        for itemID in availabilityAssetIDsByItemID.keys {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            availabilityAssetIDsByItemID[itemID] = nil
        }
    }

    private func cancelWorkerImportContexts() {
        for context in workerImportContextsByItemID.values {
            stopAccessingWorkerImportResources(context)
        }
        workerImportContextsByItemID.removeAll()
    }

    private func startAccessingImportResource(_ url: URL) throws -> Bool {
        let didAccess = resourceAccess.startAccessing(url)
        if resourceAccess.requiresSuccessfulAccess && !didAccess {
            throw TeststripError.invalidState("Import permission was not granted for \(url.lastPathComponent)")
        }
        return didAccess
    }

    private func stopAccessingImportResource(_ url: URL, didAccess: Bool) {
        guard didAccess else { return }
        resourceAccess.stopAccessing(url)
    }

    private func stopAccessingWorkerImportResources(_ context: WorkerImportContext) {
        stopAccessingImportResource(context.source, didAccess: context.didAccessSource)
        if let destinationRoot = context.destinationRoot {
            stopAccessingImportResource(destinationRoot, didAccess: context.didAccessDestination)
        }
    }

    private var visibleActiveBackgroundWorkItems: [BackgroundWorkItem] {
        backgroundWorkQueue.items.filter { [.running, .paused, .queued].contains($0.status) }
    }

    private var visibleInactiveBackgroundWorkItem: BackgroundWorkItem? {
        backgroundWorkQueue.items.last { isVisibleInactiveBackgroundWork($0) }
    }

    private var persistedWorkActivityIDs: Set<String> {
        Set((recentWork + starredWork).map(\.id))
    }

    private var activeBackgroundImportItem: BackgroundWorkItem? {
        let importItems = workerImportContextsByItemID.keys.compactMap { backgroundWorkQueue.item(id: $0) }
        let item = importItems.first { $0.kind == .ingest && $0.status == .running } ??
            importItems.first { $0.kind == .ingest && $0.status == .paused } ??
            importItems.first { $0.kind == .ingest && $0.status == .queued }
        return item.map(userFacingWorkerImportItem)
    }

    private func userFacingWorkerImportItem(_ item: BackgroundWorkItem) -> BackgroundWorkItem {
        guard item.status == .running,
              workerSupervisor?.isCommandDispatched(for: item.id) == false else {
            return item
        }
        var waitingItem = item
        waitingItem.status = .queued
        return waitingItem
    }

    private func recordPersistedActiveBackgroundWorkActivities(in queue: BackgroundWorkQueue) {
        let persistedIDs = persistedWorkActivityIDs
        for item in queue.items where persistedIDs.contains(item.id.rawValue) && [.queued, .running, .paused].contains(item.status) {
            recordRecentActivity(AppWorkActivity(workItem: item))
        }
    }

    private func isVisibleInactiveBackgroundWork(_ item: BackgroundWorkItem) -> Bool {
        guard [.cancelled, .failed, .completed].contains(item.status) else {
            return false
        }
        return !isSelectionMetadataSyncCheck(item)
    }

    public func reload() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            let loadedAssets = try catalog.repository.assets(ids: explicitAssetIDs, limit: Self.assetPageSize)
            replaceAssets(loadedAssets, pageOffset: 0)
            totalAssetCount = try catalog.repository.assetCount(ids: explicitAssetIDs)
            return
        }
        let loadedAssets: [Asset]
        let count: Int
        if let query = currentLibraryQuery() {
            loadedAssets = try catalog.repository.allAssets(matching: query, limit: Self.assetPageSize)
            count = try catalog.repository.assetCount(matching: query)
        } else {
            loadedAssets = try catalog.repository.allAssets(limit: Self.assetPageSize)
            count = try catalog.repository.assetCount()
        }
        replaceAssets(loadedAssets, pageOffset: 0)
        totalAssetCount = count
    }

    public func loadMoreAssets() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard hasMoreAssets else { return }
        let offset = assetPageOffset + assets.count
        let loadedAssets: [Asset]
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            loadedAssets = try catalog.repository.assets(ids: explicitAssetIDs, limit: Self.assetPageSize, offset: offset)
        } else if let query = currentLibraryQuery() {
            loadedAssets = try catalog.repository.allAssets(matching: query, limit: Self.assetPageSize, offset: offset)
        } else {
            loadedAssets = try catalog.repository.allAssets(limit: Self.assetPageSize, offset: offset)
        }
        assets.append(contentsOf: loadedAssets)
        enforceLoadedAssetWindow(dropping: .leading)
        totalAssetCount = try currentLibraryAssetCount(repository: catalog.repository)
        if selectedAssetID == nil {
            selectedAssetID = assets.first?.id
        }
    }

    public func loadPreviousAssets() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard hasPreviousAssets else { return }
        let previousOffset = max(0, assetPageOffset - Self.assetPageSize)
        let filteredPreviousAssets: [Asset]
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            filteredPreviousAssets = try catalog.repository.assets(
                ids: explicitAssetIDs,
                limit: assetPageOffset - previousOffset,
                offset: previousOffset
            )
        } else if let query = currentLibraryQuery() {
            filteredPreviousAssets = try catalog.repository.allAssets(
                matching: query,
                limit: assetPageOffset - previousOffset,
                offset: previousOffset
            )
        } else {
            filteredPreviousAssets = try catalog.repository.allAssets(
                limit: assetPageOffset - previousOffset,
                offset: previousOffset
            )
        }
        assets.insert(contentsOf: filteredPreviousAssets, at: 0)
        assetPageOffset = previousOffset
        enforceLoadedAssetWindow(dropping: .trailing)
        totalAssetCount = try currentLibraryAssetCount(repository: catalog.repository)
        if selectedAssetID == nil {
            selectedAssetID = assets.first?.id
        }
    }

    public func applyLibraryFilters() throws {
        try reload()
    }

    public func selectPeopleSignal(_ kind: EvaluationKind) throws {
        try applyEvaluationKindFilter(kind)
    }

    public func selectTimelineDay(_ day: CatalogTimelineDay, calendar: Calendar = .current) throws {
        try selectTimelineDateRange(startDate: day.startDate(calendar: calendar), endDate: day.endDate(calendar: calendar))
    }

    public func selectTimelineMonth(year: Int, month: Int, calendar: Calendar = .current) throws {
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        let endDate = startDate.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        try selectTimelineDateRange(startDate: startDate, endDate: endDate)
    }

    public func selectTimelineYear(_ year: Int, calendar: Calendar = .current) throws {
        let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        let endDate = startDate.flatMap { calendar.date(byAdding: .year, value: 1, to: $0) }
        try selectTimelineDateRange(startDate: startDate, endDate: endDate)
    }

    private func selectTimelineDateRange(startDate: Date?, endDate: Date?) throws {
        guard let startDate, let endDate else {
            throw TeststripError.invalidState("timeline selection has an invalid date")
        }
        selectedAssetSetID = nil
        captureDateStartFilter = startDate
        captureDateEndFilter = endDate
        selectedView = .timeline
        try reload()
    }

    private func applyEvaluationKindFilter(_ kind: EvaluationKind) throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        evaluationKindFilter = kind
        selectedView = .grid
        try reload()
    }

    public func clearLibraryFilters() throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        try reload()
    }

    private func applyReviewQueue(_ queue: ReviewQueue) throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        switch queue {
        case .picks:
            flagFilter = .pick
        case .rejects:
            flagFilter = .reject
        case .fiveStars:
            minimumRatingFilter = 5
        case .needsKeywords:
            needsKeywordsFilter = true
        case .needsEvaluation:
            needsEvaluationFilter = true
        case .facesFound:
            evaluationKindFilter = .faceCount
        case .ocrFound:
            evaluationKindFilter = .ocrText
        case .likelyIssues:
            likelyIssuesFilter = true
        case .providerFailures:
            providerFailuresFilter = true
        }
        selectedView = .grid
        try reload()
    }

    public func refreshSelectedAssetAvailability() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        _ = try refreshAvailability(for: selectedAssetID)
        try refreshSourceAvailabilitySummaries()
    }

    public func refreshVisibleAssetAvailability() throws {
        guard catalog != nil else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        if workerSupervisor != nil {
            try requestAvailabilityRefresh(assetIDs: assets.map(\.id))
            return
        }
        let visibleAssetIDs = assets.map(\.id)
        for assetID in visibleAssetIDs {
            _ = try refreshAvailability(for: assetID)
        }
        try refreshSourceAvailabilitySummaries()
    }

    @discardableResult
    public func reconnectSourceRoot(from oldRoot: URL, to newRoot: URL) throws -> SourceRootReconnectResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let preferredSelection = selectedAssetID
        let result = try catalog.repository.reconnectSourceRoot(from: oldRoot, to: newRoot)
        try loadCatalogPage(preferredSelection: preferredSelection)
        catalogFolders = try catalog.repository.folders()
        sourceRoots = try catalog.repository.sourceRoots()
        sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        rebuildSidebarSections()
        if result.reconnectedAssetCount > 0 {
            try enqueuePendingPreviewGeneration()
        }
        let sourceLabel = result.reconnectedAssetCount == 1 ? "source" : "sources"
        statusMessage = "Reconnected \(result.reconnectedAssetCount) \(sourceLabel)"
        return result
    }

    private func requestAvailabilityRefresh(assetID: AssetID) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        if availabilityAssetIDsByItemID.contains(where: { $0.value.contains(assetID) }) {
            return
        }
        let itemID = WorkSessionID(rawValue: "source-\(UUID().uuidString)")
        let assetName = assets.first { $0.id == assetID }?.originalURL.lastPathComponent ?? assetID.rawValue
        let item = BackgroundWorkItem(
            id: itemID,
            kind: .sourceScan,
            title: "Refresh sources",
            detail: "Checking \(assetName)",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        availabilityAssetIDsByItemID[itemID] = [assetID]
        do {
            try workerSupervisor.enqueue(item, command: .refreshAvailability(assetID: assetID))
        } catch {
            availabilityAssetIDsByItemID[itemID] = nil
            throw error
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func requestAvailabilityRefresh(assetIDs: [AssetID]) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        let activeAssetIDs = Set(availabilityAssetIDsByItemID.values.flatMap { $0 })
        let refreshAssetIDs = assetIDs.filter { !activeAssetIDs.contains($0) }
        guard !refreshAssetIDs.isEmpty else { return }

        for batch in sourceAvailabilityRefreshBatches(for: refreshAssetIDs) {
            let itemID = WorkSessionID(rawValue: "source-\(UUID().uuidString)")
            let item = BackgroundWorkItem(
                id: itemID,
                kind: .sourceScan,
                title: "Refresh sources",
                detail: "Checking \(Self.sourceCountDescription(batch.count))",
                completedUnitCount: 0,
                totalUnitCount: batch.count
            )
            availabilityAssetIDsByItemID[itemID] = batch
            do {
                try workerSupervisor.enqueue(item, command: .refreshAvailabilityBatch(assetIDs: batch))
            } catch {
                availabilityAssetIDsByItemID[itemID] = nil
                throw error
            }
        }
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func sourceAvailabilityRefreshBatches(for assetIDs: [AssetID]) -> [[AssetID]] {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var sourceOrder: [String] = []
        var assetIDsBySource: [String: [AssetID]] = [:]

        for assetID in assetIDs {
            let sourceKey = assetsByID[assetID]?.volumeIdentifier ?? ""
            if assetIDsBySource[sourceKey] == nil {
                sourceOrder.append(sourceKey)
                assetIDsBySource[sourceKey] = []
            }
            assetIDsBySource[sourceKey]?.append(assetID)
        }

        return sourceOrder.flatMap { sourceKey -> [[AssetID]] in
            guard let sourceAssetIDs = assetIDsBySource[sourceKey] else { return [] }
            return stride(from: 0, to: sourceAssetIDs.count, by: Self.sourceAvailabilityBatchSize).map { start in
                let end = min(start + Self.sourceAvailabilityBatchSize, sourceAssetIDs.count)
                return Array(sourceAssetIDs[start..<end])
            }
        }
    }

    private static func sourceCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "source" : "sources")"
    }

    @discardableResult
    private func refreshAvailability(for assetID: AssetID) throws -> SourceAvailability {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let asset = try catalog.repository.asset(id: assetID)
        let availability = SourceAvailabilityProbe().availability(for: asset)
        try catalog.repository.updateAvailability(assetID: assetID, availability: availability)
        let updatedAsset = try catalog.repository.asset(id: assetID)
        if let index = assets.firstIndex(where: { $0.id == assetID }) {
            assets[index] = updatedAsset
        }
        return availability
    }

    private enum LoadedAssetWindowDropEdge {
        case leading
        case trailing
    }

    private func enforceLoadedAssetWindow(dropping edge: LoadedAssetWindowDropEdge) {
        let overflowCount = assets.count - Self.loadedAssetWindowSize
        guard overflowCount > 0 else { return }

        switch edge {
        case .leading:
            assets.removeFirst(overflowCount)
            assetPageOffset += overflowCount
        case .trailing:
            assets.removeLast(overflowCount)
        }

        if let selectedAssetID, assets.contains(where: { $0.id == selectedAssetID }) {
            return
        }
        selectedAssetID = assets.first?.id
    }

    private func replaceAssets(
        _ loadedAssets: [Asset],
        pageOffset: Int = 0,
        preferredSelection: AssetID? = nil
    ) {
        let previousSelection = selectedAssetID
        assets = loadedAssets
        assetPageOffset = pageOffset
        if let preferredSelection, assets.contains(where: { $0.id == preferredSelection }) {
            selectedAssetID = preferredSelection
        } else if let previousSelection, assets.contains(where: { $0.id == previousSelection }) {
            selectedAssetID = previousSelection
        } else {
            selectedAssetID = assets.first?.id
        }
    }

    private func loadCatalogPage(preferredSelection: AssetID?) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let page = try Self.catalogPage(
            containing: preferredSelection,
            repository: catalog.repository,
            query: currentLibraryQuery()
        )
        replaceAssets(page.assets, pageOffset: page.offset, preferredSelection: preferredSelection)
        totalAssetCount = page.totalAssetCount
    }

    private static func append(_ predicate: SetQuery.Predicate, to predicates: inout [SetQuery.Predicate]) {
        guard !predicates.contains(predicate) else { return }
        predicates.append(predicate)
    }

    private static func append(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private static func append(_ row: ActiveLibraryFilterRow, to rows: inout [ActiveLibraryFilterRow]) {
        guard !rows.contains(where: { $0.title == row.title }) else { return }
        rows.append(row)
    }

    private static func activeLibraryFilterRow(for predicate: SetQuery.Predicate) -> ActiveLibraryFilterRow? {
        switch predicate {
        case .text(let text):
            ActiveLibraryFilterRow(title: "Search: \(text)")
        case .ratingAtLeast(let rating):
            ActiveLibraryFilterRow(title: "Rating >= \(rating)", target: sidebarTarget(for: predicate))
        case .flag(let flag):
            ActiveLibraryFilterRow(title: flag.rawValue.capitalized, target: sidebarTarget(for: predicate))
        case .colorLabel(let label):
            ActiveLibraryFilterRow(title: "\(label.rawValue.capitalized) Label")
        case .keyword(let keyword):
            ActiveLibraryFilterRow(title: "Keyword: \(keyword)")
        case .missingKeywords:
            ActiveLibraryFilterRow(title: "Needs Keywords", target: sidebarTarget(for: predicate))
        case .availability(let availability):
            ActiveLibraryFilterRow(title: "Source: \(availability.rawValue.capitalized)", target: sidebarTarget(for: predicate))
        case .folderPrefix(let path):
            ActiveLibraryFilterRow(title: "Folder: \(URL(fileURLWithPath: path).lastPathComponent)")
        case .camera(let camera):
            ActiveLibraryFilterRow(title: "Camera: \(camera)")
        case .lens(let lens):
            ActiveLibraryFilterRow(title: "Lens: \(lens)")
        case .isoAtLeast(let iso):
            ActiveLibraryFilterRow(title: "ISO >= \(iso)")
        case .capturedAtOrAfter(let date):
            ActiveLibraryFilterRow(title: "From \(date.formatted(date: .abbreviated, time: .omitted))")
        case .capturedBefore(let date):
            ActiveLibraryFilterRow(title: "Before \(date.formatted(date: .abbreviated, time: .omitted))")
        case .evaluationKind(let kind):
            ActiveLibraryFilterRow(title: "Signal: \(kind.displayName)", target: sidebarTarget(for: predicate))
        case .unevaluated:
            ActiveLibraryFilterRow(title: "Needs Evaluation", target: sidebarTarget(for: predicate))
        case .likelyIssue:
            ActiveLibraryFilterRow(title: "Likely Issues", target: sidebarTarget(for: predicate))
        case .evaluationFailure:
            ActiveLibraryFilterRow(title: "Provider Failures", target: sidebarTarget(for: predicate))
        case .metadataSyncPending:
            ActiveLibraryFilterRow(title: "XMP Pending", target: sidebarTarget(for: predicate))
        case .metadataSyncConflict:
            ActiveLibraryFilterRow(title: "XMP Conflicts", target: sidebarTarget(for: predicate))
        case .importBatch(let id):
            ActiveLibraryFilterRow(title: "Import: \(id)")
        }
    }

    private static func sidebarTarget(for predicate: SetQuery.Predicate) -> SidebarRowTarget? {
        switch predicate {
        case .ratingAtLeast(let rating):
            rating == 5 ? .reviewQueue(.fiveStars) : nil
        case .flag(.pick):
            .reviewQueue(.picks)
        case .flag(.reject):
            .reviewQueue(.rejects)
        case .missingKeywords:
            .reviewQueue(.needsKeywords)
        case .availability(let availability):
            .sourceAvailability(availability)
        case .evaluationKind(let kind):
            .evaluationKind(kind)
        case .unevaluated:
            .reviewQueue(.needsEvaluation)
        case .likelyIssue:
            .reviewQueue(.likelyIssues)
        case .evaluationFailure:
            .reviewQueue(.providerFailures)
        case .metadataSyncPending:
            .metadataSyncPending
        case .metadataSyncConflict:
            .metadataSyncConflicts
        default:
            nil
        }
    }

    private func currentLibraryQuery() -> SetQuery? {
        var predicates: [SetQuery.Predicate] = []
        if let selectedDynamicSetQuery {
            predicates.append(contentsOf: selectedDynamicSetQuery.predicates)
        }
        let searchIntent = LibrarySearchIntent.parse(librarySearchText)
        if let residualSearch = searchIntent.residualText {
            Self.append(.text(residualSearch), to: &predicates)
        }
        for predicate in searchIntent.predicates {
            Self.append(predicate, to: &predicates)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            Self.append(.keyword(trimmedKeyword), to: &predicates)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            Self.append(.folderPrefix(trimmedFolder), to: &predicates)
        }
        if let minimumRatingFilter {
            Self.append(.ratingAtLeast(minimumRatingFilter), to: &predicates)
        }
        if let flagFilter {
            Self.append(.flag(flagFilter), to: &predicates)
        }
        if let colorLabelFilter {
            Self.append(.colorLabel(colorLabelFilter), to: &predicates)
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            Self.append(.camera(trimmedCamera), to: &predicates)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            Self.append(.lens(trimmedLens), to: &predicates)
        }
        if let minimumISOFilter, minimumISOFilter > 0 {
            Self.append(.isoAtLeast(minimumISOFilter), to: &predicates)
        }
        if let captureDateStartFilter {
            Self.append(.capturedAtOrAfter(captureDateStartFilter), to: &predicates)
        }
        if let captureDateEndFilter {
            Self.append(.capturedBefore(captureDateEndFilter), to: &predicates)
        }
        if let availabilityFilter {
            Self.append(.availability(availabilityFilter), to: &predicates)
        }
        if let evaluationKindFilter {
            Self.append(.evaluationKind(evaluationKindFilter), to: &predicates)
        }
        if needsKeywordsFilter {
            Self.append(.missingKeywords, to: &predicates)
        }
        if needsEvaluationFilter {
            Self.append(.unevaluated, to: &predicates)
        }
        if likelyIssuesFilter {
            Self.append(.likelyIssue, to: &predicates)
        }
        if providerFailuresFilter {
            Self.append(.evaluationFailure, to: &predicates)
        }
        if metadataSyncPendingFilter {
            Self.append(.metadataSyncPending, to: &predicates)
        }
        if metadataSyncConflictFilter {
            Self.append(.metadataSyncConflict, to: &predicates)
        }
        return predicates.isEmpty ? nil : SetQuery(predicates: predicates)
    }

    private func clearLibraryQueryFilters() {
        librarySearchText = ""
        keywordFilterText = ""
        folderFilterText = ""
        minimumRatingFilter = nil
        flagFilter = nil
        colorLabelFilter = nil
        cameraFilterText = ""
        lensFilterText = ""
        minimumISOFilter = nil
        captureDateStartFilter = nil
        captureDateEndFilter = nil
        availabilityFilter = nil
        evaluationKindFilter = nil
        needsKeywordsFilter = false
        needsEvaluationFilter = false
        likelyIssuesFilter = false
        providerFailuresFilter = false
        metadataSyncPendingFilter = false
        metadataSyncConflictFilter = false
    }

    private func currentLibraryAssetCount(repository: CatalogRepository) throws -> Int {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            return try repository.assetCount(ids: explicitAssetIDs)
        }
        if let query = currentLibraryQuery() {
            return try repository.assetCount(matching: query)
        }
        return try repository.assetCount()
    }

    private func currentAssetScopeIDs(repository: CatalogRepository) throws -> [AssetID] {
        if let explicitAssetIDs = selectedExplicitAssetIDs {
            return explicitAssetIDs
        }
        if let query = currentLibraryQuery() {
            return try repository.assetIDs(matching: query)
        }
        return try repository.assetIDs()
    }

    private var selectedAssetSet: AssetSet? {
        guard let selectedAssetSetID else { return nil }
        return savedAssetSets.first { $0.id == selectedAssetSetID }
    }

    private var selectedDynamicSetQuery: SetQuery? {
        guard let selectedAssetSet else { return nil }
        if case .dynamic(let query) = selectedAssetSet.membership {
            return query
        }
        return nil
    }

    private var selectedExplicitAssetIDs: [AssetID]? {
        guard let selectedAssetSet else { return nil }
        switch selectedAssetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return ids
        case .dynamic:
            return nil
        }
    }

    private func latestImportOutputAssetIDs(repository: CatalogRepository) throws -> [AssetID] {
        guard let activity = recentWork.first(where: Self.isImportCompletionActivity) else {
            throw TeststripError.invalidState("no completed import")
        }
        return try latestImportOutputAssetIDs(activityID: activity.id, repository: repository)
    }

    private func latestImportOutputAssetIDs(activityID: String, repository: CatalogRepository) throws -> [AssetID] {
        let session = try repository.session(id: WorkSessionID(rawValue: activityID))
        guard let outputSetID = session.outputSetIDs.first else {
            return []
        }
        let assetSet = try assetSetForSelection(id: outputSetID, repository: repository)
        switch assetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return ids
        case .dynamic(let query):
            return try repository.assetIDs(matching: query)
        }
    }

    private func cullingInputSetID(sessionID: WorkSessionID, title: String) throws -> AssetSetID {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        if let selectedAssetSetID {
            return selectedAssetSetID
        }
        let inputSetID = AssetSetID(rawValue: "work-input-\(sessionID.rawValue)")
        let inputSet = AssetSet(
            id: inputSetID,
            name: "\(title) Input",
            membership: .dynamic(currentLibraryQuery() ?? SetQuery(predicates: []))
        )
        try catalog.repository.upsert(inputSet)
        savedAssetSets = try catalog.repository.assetSets()
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        rebuildSidebarSections()
        return inputSetID
    }

    private func assetSetForSelection(id: AssetSetID, repository: CatalogRepository) throws -> AssetSet {
        if let assetSet = savedAssetSets.first(where: { $0.id == id }) {
            return assetSet
        }
        return try repository.assetSet(id: id)
    }

    private func rebuildSidebarSections() {
        sidebarSections = Self.defaultSidebarSections(
            totalAssetCount: totalAssetCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            catalogTimelineDays: catalogTimelineDays,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
            pendingMetadataSyncCount: pendingMetadataSyncCount,
            metadataSyncConflictCount: metadataSyncConflictCount,
            recentWork: recentWork,
            starredWork: starredWork
        )
    }

    private func refreshCatalogFolders() {
        guard let catalog else { return }
        do {
            catalogFolders = try catalog.repository.folders()
            catalogTimelineDays = try catalog.repository.timelineDays()
            sourceRoots = try catalog.repository.sourceRoots()
            rebuildSidebarSections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCatalogEvaluationKindSummaries() {
        guard let catalog else { return }
        do {
            catalogEvaluationKindSummaries = try catalog.repository.evaluationKindSummaries()
            reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
            rebuildSidebarSections()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCatalogSidebarCounts() throws {
        guard let catalog else { return }
        reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
        assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        rebuildSidebarSections()
    }

    @discardableResult
    public func importFolder(_ folderURL: URL) throws -> LibraryImportResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        startImportActivity(folderURL: folderURL)
        do {
            let result = try catalog.importService.addFolderInPlace(
                folderURL,
                repository: catalog.repository,
                previewPolicy: .generateImmediately
            )
            try loadCatalogPage(preferredSelection: result.importedAssets.first?.id)
            updateImportStatus(with: result)
            recordCompletedImportActivity(folderURL: folderURL, result: result)
            return result
        } catch {
            failImportActivity(folderURL: folderURL, error: error)
            throw error
        }
    }

    @discardableResult
    @MainActor
    public func importFolderInBackground(_ folderURL: URL) async throws -> LibraryImportResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        startImportActivity(folderURL: folderURL)
        guard let activityID = activeWork?.id else {
            throw TeststripError.invalidState("import activity was not created")
        }
        let paths = catalog.paths
        do {
            let output = try await importTaskFactory(
                paths,
                folderURL,
                importProgressHandler(activityID: activityID)
            ).value
            replaceAssets(
                output.assets,
                pageOffset: output.assetPageOffset,
                preferredSelection: output.result.importedAssets.first?.id
            )
            totalAssetCount = output.totalAssetCount
            try enqueuePendingPreviewGeneration()
            updateImportStatus(with: output.result)
            recordCompletedImportActivity(folderURL: folderURL, result: output.result)
            return output.result
        } catch {
            failImportActivity(folderURL: folderURL, error: error)
            throw error
        }
    }

    @discardableResult
    @MainActor
    public func importCardInBackground(source: URL, destinationRoot: URL) async throws -> LibraryImportResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(source.lastPathComponent)..."
        startImportActivity(folderURL: source, destinationRoot: destinationRoot)
        guard let activityID = activeWork?.id else {
            throw TeststripError.invalidState("import activity was not created")
        }
        let paths = catalog.paths
        do {
            let output = try await cardImportTaskFactory(
                paths,
                source,
                destinationRoot,
                importProgressHandler(activityID: activityID)
            ).value
            replaceAssets(
                output.assets,
                pageOffset: output.assetPageOffset,
                preferredSelection: output.result.importedAssets.first?.id
            )
            totalAssetCount = output.totalAssetCount
            try enqueuePendingPreviewGeneration()
            updateImportStatus(with: output.result)
            recordCompletedImportActivity(folderURL: source, destinationRoot: destinationRoot, result: output.result)
            return output.result
        } catch {
            failImportActivity(folderURL: source, destinationRoot: destinationRoot, error: error)
            throw error
        }
    }

    @MainActor
    public func beginImportFolder(_ folderURL: URL) {
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        guard !isImporting else {
            errorMessage = "Another import is already running"
            return
        }
        if let blockingReason = ImportSourcePreflight.blockingReason(for: folderURL) {
            failImportBeforeStart(folderURL: folderURL, reason: blockingReason)
            return
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        if workerSupervisor != nil {
            enqueueWorkerImport(source: folderURL, destinationRoot: nil, command: .importFolder(root: folderURL))
            return
        }
        let didAccess: Bool
        do {
            didAccess = try startAccessingImportResource(folderURL)
        } catch {
            failImportBeforeStart(folderURL: folderURL, reason: error.localizedDescription)
            return
        }
        startImportActivity(folderURL: folderURL)
        guard let activityID = activeWork?.id else {
            stopAccessingImportResource(folderURL, didAccess: didAccess)
            return
        }

        let task = importTaskFactory(
            catalog.paths,
            folderURL,
            importProgressHandler(activityID: activityID)
        )
        activeImportTask = task
        Task { @MainActor [weak self] in
            defer {
                self?.stopAccessingImportResource(folderURL, didAccess: didAccess)
            }
            do {
                let output = try await task.value
                guard let self, self.activeWork?.id == activityID else { return }
                self.replaceAssets(
                    output.assets,
                    pageOffset: output.assetPageOffset,
                    preferredSelection: output.result.importedAssets.first?.id
                )
                self.totalAssetCount = output.totalAssetCount
                try self.enqueuePendingPreviewGeneration()
                self.updateImportStatus(with: output.result)
                self.recordCompletedImportActivity(folderURL: folderURL, result: output.result)
                self.activeImportTask = nil
            } catch is CancellationError {
                guard let self, self.activeWork?.id == activityID else { return }
                self.cancelImportActivity(folderURL: folderURL)
                self.activeImportTask = nil
            } catch {
                guard let self, self.activeWork?.id == activityID else { return }
                self.statusMessage = nil
                self.errorMessage = error.localizedDescription
                self.failImportActivity(folderURL: folderURL, error: error)
                self.activeImportTask = nil
            }
        }
    }

    @MainActor
    public func beginImportCard(source: URL, destinationRoot: URL) {
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        guard !isImporting else {
            errorMessage = "Another import is already running"
            return
        }
        if let blockingReason = ImportSourcePreflight.blockingReason(for: source) {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: blockingReason)
            return
        }
        if let blockingReason = CardImportDestinationPreflight.blockingReason(source: source, destinationRoot: destinationRoot) {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: blockingReason)
            return
        }
        errorMessage = nil
        statusMessage = "Importing \(source.lastPathComponent)..."
        if workerSupervisor != nil {
            enqueueWorkerImport(
                source: source,
                destinationRoot: destinationRoot,
                command: .importCard(source: source, destinationRoot: destinationRoot)
            )
            return
        }
        let didAccessSource: Bool
        let didAccessDestination: Bool
        do {
            didAccessSource = try startAccessingImportResource(source)
            do {
                didAccessDestination = try startAccessingImportResource(destinationRoot)
            } catch {
                stopAccessingImportResource(source, didAccess: didAccessSource)
                throw error
            }
        } catch {
            failImportBeforeStart(folderURL: source, destinationRoot: destinationRoot, reason: error.localizedDescription)
            return
        }
        startImportActivity(folderURL: source, destinationRoot: destinationRoot)
        guard let activityID = activeWork?.id else {
            stopAccessingImportResource(source, didAccess: didAccessSource)
            stopAccessingImportResource(destinationRoot, didAccess: didAccessDestination)
            return
        }

        let task = cardImportTaskFactory(
            catalog.paths,
            source,
            destinationRoot,
            importProgressHandler(activityID: activityID)
        )
        activeImportTask = task
        Task { @MainActor [weak self] in
            defer {
                self?.stopAccessingImportResource(source, didAccess: didAccessSource)
                self?.stopAccessingImportResource(destinationRoot, didAccess: didAccessDestination)
            }
            do {
                let output = try await task.value
                guard let self, self.activeWork?.id == activityID else { return }
                self.replaceAssets(
                    output.assets,
                    pageOffset: output.assetPageOffset,
                    preferredSelection: output.result.importedAssets.first?.id
                )
                self.totalAssetCount = output.totalAssetCount
                try self.enqueuePendingPreviewGeneration()
                self.updateImportStatus(with: output.result)
                self.recordCompletedImportActivity(folderURL: source, destinationRoot: destinationRoot, result: output.result)
                self.activeImportTask = nil
            } catch is CancellationError {
                guard let self, self.activeWork?.id == activityID else { return }
                self.cancelImportActivity(folderURL: source, destinationRoot: destinationRoot)
                self.activeImportTask = nil
            } catch {
                guard let self, self.activeWork?.id == activityID else { return }
                self.statusMessage = nil
                self.errorMessage = error.localizedDescription
                self.failImportActivity(folderURL: source, destinationRoot: destinationRoot, error: error)
                self.activeImportTask = nil
            }
        }
    }

    @MainActor
    public func cancelActiveWork() {
        guard let activeImportTask else { return }
        statusMessage = "Cancelling import..."
        activeImportTask.cancel()
    }

    private func updateImportStatus(with result: LibraryImportResult) {
        try? refreshPreviewGenerationQueueStates()
        try? refreshCatalogSidebarCounts()
        statusMessage = Self.importCompletionStatus(result: result)
        if let warningText = Self.importCompletionWarningText(result: result) {
            statusMessage?.append(" (\(warningText))")
        }
    }

    private static func importCompletionStatus(result: LibraryImportResult) -> String {
        guard !result.importedAssets.isEmpty else {
            if result.skippedSourceFileCount > 0 {
                return "No photos imported"
            }
            return "No supported photos found"
        }
        guard result.newAssetCount > 0 else {
            return "No new photos found"
        }
        let photoLabel = result.newAssetCount == 1 ? "photo" : "photos"
        var status = "Imported \(result.newAssetCount) \(photoLabel)"
        if result.existingAssetCount > 0 {
            let existingLabel = result.existingAssetCount == 1 ? "photo" : "photos"
            status.append(" (\(result.existingAssetCount) \(existingLabel) already in catalog)")
        }
        return status
    }

    private static func importCompletionWarningText(result: LibraryImportResult) -> String? {
        var warnings: [String] = []
        if result.skippedSourceFileCount > 0 {
            let fileLabel = result.skippedSourceFileCount == 1 ? "file" : "files"
            warnings.append("\(result.skippedSourceFileCount) \(fileLabel) skipped")
        }
        if !result.previewFailures.isEmpty {
            let previewLabel = result.previewFailures.count == 1 ? "preview failure" : "preview failures"
            warnings.append("\(result.previewFailures.count) \(previewLabel)")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: ", ")
    }

    private func startImportActivity(folderURL: URL, destinationRoot: URL? = nil) {
        activeWork = AppWorkActivity(
            kind: .ingest,
            status: .running,
            title: "Import photos",
            detail: "Importing from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot))",
            completedUnitCount: 0,
            totalUnitCount: nil,
            failureCount: 0
        )
    }

    private func failImportBeforeStart(folderURL: URL, destinationRoot: URL? = nil, reason: String) {
        statusMessage = nil
        errorMessage = reason
        failImportActivity(
            folderURL: folderURL,
            destinationRoot: destinationRoot,
            error: TeststripError.invalidState(reason)
        )
    }

    private func importProgressHandler(activityID: String) -> LibraryImportProgressHandler {
        let sink = AppImportProgressSink(model: self, activityID: activityID)
        return { progress in
            sink.handle(progress)
        }
    }

    fileprivate func applyImportProgress(_ progress: LibraryImportProgress) {
        if let firstCatalogedAssetID = progress.catalogedAssetIDs.first {
            do {
                try loadCatalogPage(preferredSelection: firstCatalogedAssetID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        guard var activity = activeWork else { return }
        activity.detail = progress.detail
        activity.completedUnitCount = progress.completedUnitCount
        activity.totalUnitCount = progress.totalUnitCount
        activeWork = activity
    }

    private func recordCompletedImportActivity(
        id: String? = nil,
        folderURL: URL,
        destinationRoot: URL? = nil,
        result: LibraryImportResult
    ) {
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .completed,
            title: "Import photos",
            detail: Self.importCompletionDetail(
                result: result,
                sourceDescription: importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot)
            ),
            completedUnitCount: result.newAssetCount,
            totalUnitCount: result.importedAssets.count,
            failureCount: result.previewFailures.count
        )
        let outputSetIDs = saveImportOutputSet(for: activity, result: result)
        refreshCatalogFolders()
        activeWork = nil
        recordRecentActivity(activity, outputSetIDs: outputSetIDs)
    }

    private static func importCompletionDetail(result: LibraryImportResult, sourceDescription: String) -> String {
        let warningSuffix = importCompletionWarningText(result: result).map { " (\($0))" } ?? ""
        if result.importedAssets.isEmpty {
            if result.skippedSourceFileCount == 0 {
                return "No supported photos found in \(sourceDescription)"
            }
            return "No photos imported from \(sourceDescription)\(warningSuffix)"
        }
        if result.newAssetCount == 0 {
            return "No new photos found in \(sourceDescription)\(warningSuffix)"
        }
        return "\(importCompletionStatus(result: result)) from \(sourceDescription)\(warningSuffix)"
    }

    private func failImportActivity(id: String? = nil, folderURL: URL, destinationRoot: URL? = nil, error: Error) {
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .failed,
            title: "Import photos",
            detail: "Import failed from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot)): \(error.localizedDescription)",
            completedUnitCount: 0,
            totalUnitCount: nil,
            failureCount: 1
        )
        activeWork = nil
        recordRecentActivity(activity)
    }

    private func cancelImportActivity(id: String? = nil, folderURL: URL, destinationRoot: URL? = nil) {
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .cancelled,
            title: "Import photos",
            detail: "Cancelled import from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot))",
            completedUnitCount: activeWork?.completedUnitCount ?? 0,
            totalUnitCount: activeWork?.totalUnitCount,
            failureCount: 0
        )
        activeWork = nil
        statusMessage = "Cancelled import"
        recordRecentActivity(activity)
    }

    private func importSourceDescription(folderURL: URL, destinationRoot: URL?) -> String {
        guard let destinationRoot else {
            return folderURL.lastPathComponent
        }
        return "\(folderURL.lastPathComponent) to \(destinationRoot.lastPathComponent)"
    }

    private static func photoCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func isImportCompletionActivity(_ activity: AppWorkActivity) -> Bool {
        let importedPhotoCount = activity.totalUnitCount ?? activity.completedUnitCount
        return activity.kind == .ingest && activity.status == .completed && importedPhotoCount > 0
    }

    private func saveImportOutputSet(for activity: AppWorkActivity, result: LibraryImportResult) -> [AssetSetID] {
        guard let catalog, !result.importedAssets.isEmpty else {
            return []
        }
        let outputSetID = AssetSetID(rawValue: "work-output-\(activity.id)")
        let outputSet = AssetSet.manual(
            id: outputSetID,
            name: activity.detail,
            assetIDs: result.importedAssets.map(\.id)
        )
        do {
            try catalog.repository.upsert(outputSet)
            if !savedAssetSets.contains(where: { $0.id == outputSetID }) {
                savedAssetSets.append(outputSet)
                assetSetCounts[outputSetID] = result.importedAssets.count
            }
            return [outputSetID]
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func recordRecentActivity(
        _ activity: AppWorkActivity,
        intent: String? = nil,
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) {
        recentWork.removeAll { $0.id == activity.id }
        recentWork.insert(activity, at: 0)
        rebuildSidebarSections()
        guard let catalog else { return }
        do {
            try catalog.repository.save(activity.workSession(
                intent: intent,
                inputSetIDs: inputSetIDs,
                outputSetIDs: outputSetIDs
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultImportTask(
        paths: AppCatalogPaths,
        folderURL: URL,
        previewPolicy: LibraryImportPreviewPolicy,
        progress: @escaping LibraryImportProgressHandler
    ) -> Task<AppImportOutput, Error> {
        Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.addFolderInPlace(
                folderURL,
                repository: backgroundCatalog.repository,
                previewPolicy: previewPolicy,
                progress: progress
            )
            try Task.checkCancellation()
            let page = try Self.catalogPage(
                containing: result.importedAssets.first?.id,
                repository: backgroundCatalog.repository,
                query: nil
            )
            return AppImportOutput(
                result: result,
                assets: page.assets,
                totalAssetCount: page.totalAssetCount,
                assetPageOffset: page.offset
            )
        }
    }

    private static func defaultCardImportTask(
        paths: AppCatalogPaths,
        source: URL,
        destinationRoot: URL,
        previewPolicy: LibraryImportPreviewPolicy,
        progress: @escaping LibraryImportProgressHandler
    ) -> Task<AppImportOutput, Error> {
        Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.copyFromCard(
                source: source,
                destinationRoot: destinationRoot,
                repository: backgroundCatalog.repository,
                previewPolicy: previewPolicy,
                progress: progress
            )
            try Task.checkCancellation()
            let page = try Self.catalogPage(
                containing: result.importedAssets.first?.id,
                repository: backgroundCatalog.repository,
                query: nil
            )
            return AppImportOutput(
                result: result,
                assets: page.assets,
                totalAssetCount: page.totalAssetCount,
                assetPageOffset: page.offset
            )
        }
    }

    private static func catalogPage(
        containing preferredAssetID: AssetID?,
        repository: CatalogRepository,
        query: SetQuery?
    ) throws -> (assets: [Asset], offset: Int, totalAssetCount: Int) {
        if let query {
            let assets = try repository.allAssets(matching: query, limit: assetPageSize)
            let totalAssetCount = try repository.assetCount(matching: query)
            return (assets, 0, totalAssetCount)
        }

        let offset: Int
        if let preferredAssetID {
            let assetOffset = try repository.assetOffset(id: preferredAssetID)
            offset = (assetOffset / assetPageSize) * assetPageSize
        } else {
            offset = 0
        }
        let assets = try repository.allAssets(limit: assetPageSize, offset: offset)
        let totalAssetCount = try repository.assetCount()
        return (assets, offset, totalAssetCount)
    }

    private static func commonAncestorPath(for paths: [String]) -> String? {
        guard var commonComponents = paths.first.map({ URL(fileURLWithPath: $0).standardizedFileURL.pathComponents }) else {
            return nil
        }
        for path in paths.dropFirst() {
            let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
            var sharedComponents: [String] = []
            for (lhs, rhs) in zip(commonComponents, components) {
                guard lhs == rhs else { break }
                sharedComponents.append(lhs)
            }
            commonComponents = sharedComponents
        }
        guard !commonComponents.isEmpty else { return nil }
        let path = NSString.path(withComponents: commonComponents)
        guard path != "/", path != "/Volumes" else { return nil }
        return path
    }

    public func gridPreviewURL(for assetID: AssetID) -> URL? {
        previewURL(for: assetID, levels: [.grid, .micro])
    }

    public func loupePreviewURL(for assetID: AssetID) -> URL? {
        previewURL(for: assetID, levels: [.large, .medium, .grid, .micro])
    }

    public func originalAccessURL(for assetID: AssetID) throws -> URL? {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let availability = try refreshAvailability(for: assetID)
        try refreshSourceAvailabilitySummaries()
        guard !availability.requiresCachedPreviewOnly else { return nil }
        return try catalog.repository.asset(id: assetID).originalURL
    }

    public func previewURL(for assetID: AssetID, levels: [PreviewLevel]) -> URL? {
        guard let catalog else { return nil }
        for level in levels {
            let url = catalog.previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func hasCachedPreview(for assetID: AssetID) -> Bool {
        previewURL(for: assetID, levels: [.large, .medium, .grid, .micro]) != nil
    }

    private static func defaultSidebarSections(
        totalAssetCount: Int? = nil,
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        catalogFolders: [CatalogFolder] = [],
        catalogTimelineDays: [CatalogTimelineDay] = [],
        sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary] = [],
        catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        pendingMetadataSyncItems: [MetadataSyncItem] = [],
        metadataSyncConflictItems: [MetadataSyncItem] = [],
        pendingMetadataSyncCount: Int? = nil,
        metadataSyncConflictCount: Int? = nil,
        recentWork: [AppWorkActivity] = [],
        starredWork: [AppWorkActivity] = []
    ) -> [SidebarSection] {
        var libraryRows = [
            SidebarRow(
                id: "library-all",
                title: "All Photographs",
                countText: totalAssetCount.map(sidebarCountText),
                target: .allPhotographs
            )
        ]
        libraryRows.append(
            SidebarRow(
                id: "library-search",
                title: "Search",
                detailText: "Ask or filter",
                tone: .accent,
                target: .search,
                liveMockupPlaceholder: .agenticSearch
            )
        )
        libraryRows.append(
            SidebarRow(
                id: "library-copilot",
                title: "Copilot",
                detailText: "Review work",
                tone: .accent,
                target: .copilot,
                liveMockupPlaceholder: .copilotLibrary
            )
        )
        libraryRows.append(
            SidebarRow(
                id: "library-timeline",
                title: "Timeline",
                detailText: "By date",
                countText: catalogTimelineDays.isEmpty ? nil : sidebarCountText(catalogTimelineDays.count),
                tone: .accent,
                target: .timeline,
                liveMockupPlaceholder: .timelineLibrary
            )
        )
        if catalogFolders.isEmpty {
            libraryRows.append(SidebarRow(id: "library-folders", title: "Folders", detailText: "No folders yet"))
        }
        libraryRows.append(
            SidebarRow(
                id: "library-people",
                title: "People",
                detailText: "Face groups",
                tone: .accent,
                target: .people,
                liveMockupPlaceholder: .peopleSidebar
            )
        )
        var sections = [SidebarSection(title: "Library", rows: libraryRows)]
        sections.append(SidebarSection(title: "Review", rows: reviewQueueSidebarRows(reviewQueueCounts: reviewQueueCounts)))
        if !catalogFolders.isEmpty {
            sections.append(SidebarSection(title: "Folders", rows: catalogFolders.prefix(20).map { folder in
                SidebarRow(
                    id: "folder-\(folder.path)",
                    title: folder.name,
                    detailText: folder.path,
                    target: .folder(folder.path)
                )
            }))
        }
        let sourceRows = sourceAvailabilitySidebarRows(sourceAvailabilitySummaries)
        if !sourceRows.isEmpty {
            sections.append(SidebarSection(title: "Sources", rows: sourceRows))
        }
        let evaluationRows = evaluationSignalSidebarRows(catalogEvaluationKindSummaries)
        if !evaluationRows.isEmpty {
            sections.append(SidebarSection(title: "AI", rows: evaluationRows))
        }
        var syncRows: [SidebarRow] = []
        let resolvedPendingMetadataSyncCount = pendingMetadataSyncCount ?? pendingMetadataSyncItems.count
        let resolvedMetadataSyncConflictCount = metadataSyncConflictCount ?? metadataSyncConflictItems.count
        if resolvedPendingMetadataSyncCount > 0 {
            syncRows.append(
                SidebarRow(
                    id: "sync-xmp-pending",
                    title: "XMP Pending",
                    countText: sidebarCountText(resolvedPendingMetadataSyncCount),
                    tone: .warning,
                    target: .metadataSyncPending
                )
            )
        }
        if resolvedMetadataSyncConflictCount > 0 {
            syncRows.append(
                SidebarRow(
                    id: "sync-xmp-conflicts",
                    title: "XMP Conflicts",
                    countText: sidebarCountText(resolvedMetadataSyncConflictCount),
                    tone: .destructive,
                    target: .metadataSyncConflicts
                )
            )
        }
        if !syncRows.isEmpty {
            sections.append(SidebarSection(title: "Sync", rows: syncRows))
        }
        let visibleSavedAssetSets = Self.visibleSavedAssetSets(savedAssetSets)
        let starredRows = visibleSavedAssetSets.filter(\.starred).map { Self.sidebarRow(for: $0, count: assetSetCounts[$0.id]) }
        if !starredRows.isEmpty {
            sections.append(SidebarSection(title: "Starred", rows: starredRows))
        }
        if !visibleSavedAssetSets.isEmpty {
            sections.append(SidebarSection(title: "Saved Sets", rows: visibleSavedAssetSets.map { Self.sidebarRow(for: $0, count: assetSetCounts[$0.id]) }))
        }
        let recentWorkRows = Self.workSidebarRows(for: Array(recentWork.prefix(5)), idPrefix: "work-recent")
        let starredWorkRows = Self.workSidebarRows(for: Array(starredWork.prefix(5)), idPrefix: "work-starred")
        if recentWorkRows.isEmpty && starredWorkRows.isEmpty {
            sections.append(SidebarSection(title: "Work", rows: workPlaceholderSidebarRows()))
        } else {
            if !recentWorkRows.isEmpty {
                sections.append(SidebarSection(title: "Recent Work", rows: recentWorkRows))
            }
            if !starredWorkRows.isEmpty {
                sections.append(SidebarSection(title: "Starred Work", rows: starredWorkRows))
            }
        }
        return sections
    }

    private static func workPlaceholderSidebarRows() -> [SidebarRow] {
        [
            SidebarRow(
                id: "work-recent-placeholder",
                title: "Recent",
                detailText: "No recent work",
                liveMockupPlaceholder: .workHistory
            ),
            SidebarRow(
                id: "work-starred-placeholder",
                title: "Starred",
                detailText: "No starred work",
                liveMockupPlaceholder: .workHistory
            )
        ]
    }

    private static func reviewQueueSidebarRows(reviewQueueCounts: [ReviewQueue: Int]) -> [SidebarRow] {
        reviewQueueSidebarOrder.map { queue in
            SidebarRow(
                id: "review-\(queue.rawValue)",
                title: reviewQueueTitle(queue),
                countText: reviewQueueCounts[queue].map(sidebarCountText),
                target: .reviewQueue(queue)
            )
        }
    }

    private static let reviewQueueSidebarOrder: [ReviewQueue] = [
        .picks,
        .rejects,
        .fiveStars,
        .needsKeywords,
        .needsEvaluation,
        .facesFound,
        .ocrFound,
        .likelyIssues,
        .providerFailures
    ]

    private static func reviewQueueTitle(_ queue: ReviewQueue) -> String {
        switch queue {
        case .picks:
            return "Picks"
        case .rejects:
            return "Rejects"
        case .fiveStars:
            return "5 Stars"
        case .needsKeywords:
            return "Needs Keywords"
        case .needsEvaluation:
            return "Needs Evaluation"
        case .facesFound:
            return "Faces Found"
        case .ocrFound:
            return "OCR Found"
        case .likelyIssues:
            return "Likely Issues"
        case .providerFailures:
            return "Provider Failures"
        }
    }

    private static func reviewQueueCounts(repository: CatalogRepository) throws -> [ReviewQueue: Int] {
        var counts: [ReviewQueue: Int] = [:]
        for queue in reviewQueueSidebarOrder {
            counts[queue] = try repository.assetCount(matching: reviewQueueQuery(queue))
        }
        return counts
    }

    private static func reviewQueueQuery(_ queue: ReviewQueue) -> SetQuery {
        switch queue {
        case .picks:
            return SetQuery(predicates: [.flag(.pick)])
        case .rejects:
            return SetQuery(predicates: [.flag(.reject)])
        case .fiveStars:
            return SetQuery(predicates: [.ratingAtLeast(5)])
        case .needsKeywords:
            return SetQuery(predicates: [.missingKeywords])
        case .needsEvaluation:
            return SetQuery(predicates: [.unevaluated])
        case .facesFound:
            return SetQuery(predicates: [.evaluationKind(.faceCount)])
        case .ocrFound:
            return SetQuery(predicates: [.evaluationKind(.ocrText)])
        case .likelyIssues:
            return SetQuery(predicates: [.likelyIssue])
        case .providerFailures:
            return SetQuery(predicates: [.evaluationFailure])
        }
    }

    private static func sourceAvailabilitySummaries(repository: CatalogRepository) throws -> [CatalogSourceAvailabilitySummary] {
        try sourceAvailabilitySidebarOrder.compactMap { availability in
            let count = try repository.assetCount(matching: SetQuery(predicates: [.availability(availability)]))
            guard count > 0 else { return nil }
            return CatalogSourceAvailabilitySummary(availability: availability, assetCount: count)
        }
    }

    private static func sourceAvailabilitySidebarRows(_ summaries: [CatalogSourceAvailabilitySummary]) -> [SidebarRow] {
        let summariesByAvailability = Dictionary(uniqueKeysWithValues: summaries.map { ($0.availability, $0) })
        return sourceAvailabilitySidebarOrder.compactMap { availability in
            guard let summary = summariesByAvailability[availability], summary.assetCount > 0 else { return nil }
            return SidebarRow(
                id: "source-availability-\(availability.rawValue)",
                title: sourceAvailabilitySidebarTitle(availability),
                countText: sidebarCountText(summary.assetCount),
                tone: availability == .stale ? .warning : .destructive,
                target: .sourceAvailability(availability)
            )
        }
    }

    private static let sourceAvailabilitySidebarOrder: [SourceAvailability] = [
        .offline,
        .missing,
        .moved,
        .stale
    ]

    private static func sourceAvailabilitySidebarTitle(_ availability: SourceAvailability) -> String {
        switch availability {
        case .online:
            return "Online Originals"
        case .offline:
            return "Offline Originals"
        case .missing:
            return "Missing Originals"
        case .moved:
            return "Moved Originals"
        case .stale:
            return "Stale Originals"
        }
    }

    private static func evaluationSignalSidebarRows(_ summaries: [CatalogEvaluationKindSummary]) -> [SidebarRow] {
        let summariesByKind = Dictionary(uniqueKeysWithValues: summaries.map { ($0.kind, $0) })
        return evaluationKindSidebarOrder.compactMap { kind in
            guard let summary = summariesByKind[kind], summary.assetCount > 0 else { return nil }
            return SidebarRow(
                id: "evaluation-kind-\(kind.rawValue)",
                title: evaluationKindSidebarTitle(kind),
                countText: sidebarCountText(summary.assetCount),
                tone: .accent,
                target: .evaluationKind(kind)
            )
        }
    }

    private static let evaluationKindSidebarOrder: [EvaluationKind] = [
        .faceCount,
        .faceQuality,
        .object,
        .ocrText,
        .focus,
        .motionBlur,
        .exposure,
        .aesthetics,
        .colorPalette,
        .novelty
    ]

    private static func evaluationKindSidebarTitle(_ kind: EvaluationKind) -> String {
        switch kind {
        case .faceCount:
            return "People"
        case .faceQuality:
            return "Faces"
        case .object:
            return "Objects"
        case .ocrText:
            return "Text"
        case .colorPalette:
            return "Color"
        default:
            return kind.displayName
        }
    }

    private static func visibleSavedAssetSets(_ assetSets: [AssetSet]) -> [AssetSet] {
        assetSets.filter { !$0.id.rawValue.hasPrefix("work-output-") && !$0.id.rawValue.hasPrefix("work-input-") }
    }

    private static func sidebarRow(for assetSet: AssetSet, count: Int?) -> SidebarRow {
        SidebarRow(
            id: "asset-set-\(assetSet.id.rawValue)",
            title: assetSet.name,
            detailText: assetSet.sidebarDetailText,
            countText: count.map(sidebarCountText),
            tone: assetSet.isDynamic ? .accent : .neutral,
            target: .assetSet(assetSet.id)
        )
    }

    private static func assetSetCounts(_ assetSets: [AssetSet], repository: CatalogRepository) throws -> [AssetSetID: Int] {
        let visibleAssetSets = visibleSavedAssetSets(assetSets)
        var counts: [AssetSetID: Int] = [:]
        for assetSet in visibleAssetSets {
            counts[assetSet.id] = try assetCount(for: assetSet, repository: repository)
        }
        return counts
    }

    private static func assetCount(for assetSet: AssetSet, repository: CatalogRepository) throws -> Int {
        switch assetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return try repository.assetCount(ids: ids)
        case .dynamic(let query):
            return try repository.assetCount(matching: query)
        }
    }

    private static func workSidebarRows(for activities: [AppWorkActivity], idPrefix: String) -> [SidebarRow] {
        activities.map { activity in
            SidebarRow(
                id: "\(idPrefix)-\(activity.id)",
                title: workSidebarTitle(for: activity),
                detailText: activity.sidebarDetailText,
                countText: activity.sidebarCountText,
                tone: activity.sidebarTone,
                target: .workSession(WorkSessionID(rawValue: activity.id))
            )
        }
    }

    fileprivate static func sidebarCountText(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    private static func workSidebarTitle(for activity: AppWorkActivity) -> String {
        let trimmedTitle = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = activity.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == "Import photos", !trimmedDetail.isEmpty {
            return trimmedDetail
        }
        return trimmedTitle.isEmpty && !trimmedDetail.isEmpty ? trimmedDetail : activity.title
    }

    fileprivate static func workKindTitle(_ kind: WorkSessionKind) -> String {
        switch kind {
        case .ingest:
            return "Import"
        case .previewGeneration:
            return "Previews"
        case .recognition:
            return "Recognition"
        case .culling:
            return "Culling"
        case .collecting:
            return "Collecting"
        case .searchSort:
            return "Search"
        case .keywording:
            return "Keywording"
        case .xmpSync:
            return "XMP"
        case .sourceScan:
            return "Source scan"
        case .export:
            return "Export"
        }
    }
}

private extension AssetSet {
    var sidebarDetailText: String {
        switch membership {
        case .dynamic:
            return "Smart collection"
        case .manual:
            return "Manual set"
        case .snapshot:
            return "Snapshot"
        }
    }
}

private extension AppWorkActivity {
    var sidebarDetailText: String? {
        switch status {
        case .running:
            return detail.isEmpty ? "Running" : detail
        case .paused:
            return detail.isEmpty ? "Paused" : detail
        case .queued:
            return detail.isEmpty ? "Queued" : detail
        case .failed:
            return detail.isEmpty ? "Failed" : detail
        case .cancelled:
            return detail.isEmpty ? "Cancelled" : detail
        case .completed:
            return AppModel.workKindTitle(kind)
        }
    }

    var sidebarCountText: String? {
        guard let totalUnitCount, totalUnitCount > 0 else {
            return completedUnitCount > 0 ? AppModel.sidebarCountText(completedUnitCount) : nil
        }
        return "\(completedUnitCount)/\(totalUnitCount)"
    }

    var sidebarTone: SidebarRowTone {
        switch status {
        case .completed:
            return .positive
        case .failed:
            return .destructive
        case .paused, .cancelled:
            return .warning
        case .queued, .running:
            return .accent
        }
    }

    func workSession(
        now: Date = Date(),
        intent: String? = nil,
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: kind,
            intent: intent ?? title,
            title: title,
            detail: detail,
            status: status,
            inputSetIDs: inputSetIDs,
            outputSetIDs: outputSetIDs,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            failureCount: failureCount,
            starred: starred,
            createdAt: now,
            updatedAt: now
        )
    }
}

extension SourceAvailability {
    var requiresCachedPreviewOnly: Bool {
        switch self {
        case .offline, .missing, .moved:
            return true
        case .online, .stale:
            return false
        }
    }
}

private final class AppImportProgressSink: @unchecked Sendable {
    private weak var model: AppModel?
    private let activityID: String

    init(model: AppModel, activityID: String) {
        self.model = model
        self.activityID = activityID
    }

    func handle(_ progress: LibraryImportProgress) {
        Task { @MainActor in
            self.apply(progress)
        }
    }

    @MainActor
    private func apply(_ progress: LibraryImportProgress) {
        guard let model, model.activeWork?.id == activityID else { return }
        model.applyImportProgress(progress)
    }
}
