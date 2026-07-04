import Foundation
import Observation
import TeststripCore

public enum LibraryViewMode: String, Sendable {
    case grid
    case search
    case loupe
    case compare
    case timeline
    case map
    case people
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
    case rating(Int)
    case colorLabel(ColorLabel?)
    case pick
    case reject
    case clearFlag

    public init?(key: CullingShortcutKey) {
        switch key {
        case .leftArrow:
            self = .previousPhoto
        case .rightArrow:
            self = .nextPhoto
        case .character(let character):
            switch character.lowercased() {
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
    case character(String)
}

public enum ReviewQueue: String, Equatable, Hashable, Sendable {
    case picks
    case rejects
    case fiveStars
    case needsKeywords
    case needsEvaluation
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
    public var previewFailureCount: Int
    public var failureText: String?
    public var previewStatusText: String
    public var cullingSessionName: String

    public var id: String { activityID }
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
    public var metadataSyncPendingFilter: Bool
    public var metadataSyncConflictFilter: Bool
    public var savedAssetSets: [AssetSet]
    public var assetSetCounts: [AssetSetID: Int]
    public var catalogFolders: [CatalogFolder]
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
    private var activeImportTask: Task<AppImportOutput, Error>?

    @ObservationIgnored
    private var workerImportContextsByItemID: [WorkSessionID: WorkerImportContext]

    @ObservationIgnored
    private var evaluationAssetIDsByItemID: [WorkSessionID: AssetID]

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
    private static let pendingMetadataSyncRecoveryBatchSize = 200
    private static let previewGenerationMaximumAutomaticAttempts = 3
    static let sourceAvailabilityBatchSize = 100
    private static let defaultCompareAssetLimit = 4

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public var selectedPreviewURL: URL? {
        selectedAssetID.flatMap { loupePreviewURL(for: $0) }
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

    public var canCancelBackgroundWork: Bool {
        backgroundWorkQueue.items.contains { [.queued, .running, .paused].contains($0.status) }
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

    public var canRefreshVisibleAssetAvailability: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var selectedEvaluationSignals: [EvaluationSignal] {
        guard let catalog, let selectedAssetID else { return [] }
        _ = evaluationSignalGeneration(for: selectedAssetID)
        return (try? catalog.repository.evaluationSignals(assetID: selectedAssetID)) ?? []
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
        var chips: [String] = []
        if let selectedAssetSet {
            chips.append(selectedAssetSet.name)
        }
        let trimmedSearch = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            chips.append("Search: \(trimmedSearch)")
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            chips.append("Keyword: \(trimmedKeyword)")
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            chips.append("Folder: \(URL(fileURLWithPath: trimmedFolder).lastPathComponent)")
        }
        if let minimumRatingFilter {
            chips.append("Rating >= \(minimumRatingFilter)")
        }
        if let flagFilter {
            chips.append(flagFilter.rawValue.capitalized)
        }
        if let colorLabelFilter {
            chips.append("\(colorLabelFilter.rawValue.capitalized) Label")
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            chips.append("Camera: \(trimmedCamera)")
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            chips.append("Lens: \(trimmedLens)")
        }
        if let minimumISOFilter {
            chips.append("ISO >= \(minimumISOFilter)")
        }
        if let captureDateStartFilter {
            chips.append("From \(captureDateStartFilter.formatted(date: .abbreviated, time: .omitted))")
        }
        if let captureDateEndFilter {
            chips.append("Before \(captureDateEndFilter.formatted(date: .abbreviated, time: .omitted))")
        }
        if let availabilityFilter {
            chips.append("Source: \(availabilityFilter.rawValue.capitalized)")
        }
        if let evaluationKindFilter {
            chips.append("Signal: \(evaluationKindFilter.displayName)")
        }
        if needsKeywordsFilter {
            chips.append("Needs Keywords")
        }
        if needsEvaluationFilter {
            chips.append("Needs Evaluation")
        }
        if metadataSyncPendingFilter {
            chips.append("XMP Pending")
        }
        if metadataSyncConflictFilter {
            chips.append("XMP Conflicts")
        }
        return chips
    }

    public var canSaveSelectedAssetAsManualSet: Bool {
        catalog != nil && selectedAssetID != nil
    }

    public var canBeginCullingSession: Bool {
        catalog != nil && !assets.isEmpty
    }

    public var latestImportCompletionSummary: ImportCompletionSummary? {
        guard let activity = recentWork.first(where: Self.isImportCompletionActivity) else {
            return nil
        }
        let previewFailureCount = activity.failureCount
        let failureText = previewFailureCount > 0
            ? "\(previewFailureCount) preview \(previewFailureCount == 1 ? "failure" : "failures")"
            : nil
        return ImportCompletionSummary(
            activityID: activity.id,
            title: "Import complete",
            detail: activity.detail,
            importedPhotoCount: activity.completedUnitCount,
            photoCountText: Self.photoCountDescription(activity.completedUnitCount),
            previewFailureCount: previewFailureCount,
            failureText: failureText,
            previewStatusText: failureText ?? activePreviewGenerationStatusText ?? "Previews ready",
            cullingSessionName: "\(activity.detail) Cull"
        )
    }

    public var suggestedSavedSearchName: String {
        var parts: [String] = []
        let trimmedSearch = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            parts.append(trimmedSearch)
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            parts.append(trimmedKeyword)
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            parts.append(URL(fileURLWithPath: trimmedFolder).lastPathComponent)
        }
        if let minimumRatingFilter {
            parts.append("\(minimumRatingFilter)+ Stars")
        }
        if let flagFilter {
            parts.append(flagFilter.rawValue.capitalized)
        }
        if let colorLabelFilter {
            parts.append("\(colorLabelFilter.rawValue.capitalized) Label")
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            parts.append(trimmedCamera)
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            parts.append(trimmedLens)
        }
        if let minimumISOFilter {
            parts.append("ISO \(minimumISOFilter)+")
        }
        if let availabilityFilter {
            parts.append(availabilityFilter.rawValue.capitalized)
        }
        if let evaluationKindFilter {
            parts.append("\(evaluationKindFilter.displayName) Signal")
        }
        if needsKeywordsFilter {
            parts.append("Needs Keywords")
        }
        if needsEvaluationFilter {
            parts.append("Needs Evaluation")
        }
        if metadataSyncPendingFilter {
            parts.append("XMP Pending")
        }
        if metadataSyncConflictFilter {
            parts.append("XMP Conflicts")
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
        previewGenerationQueueStates: [PreviewGenerationQueueState] = [],
        backgroundWorkQueue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        catalogFolders: [CatalogFolder] = [],
        sourceRoots: [CatalogSourceRoot] = [],
        sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary] = [],
        catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        selectedAssetSetID: AssetSetID? = nil,
        workerSupervisor: WorkerSupervisor? = nil,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil
    ) {
        let resolvedTotalAssetCount = totalAssetCount ?? assets.count
        self.sidebarSections = sidebarSections.isEmpty ? Self.defaultSidebarSections(
            totalAssetCount: resolvedTotalAssetCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
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
        self.metadataSyncPendingFilter = false
        self.metadataSyncConflictFilter = false
        self.savedAssetSets = savedAssetSets
        self.assetSetCounts = assetSetCounts
        self.catalogFolders = catalogFolders
        self.sourceRoots = sourceRoots
        self.sourceAvailabilitySummaries = sourceAvailabilitySummaries
        self.catalogEvaluationKindSummaries = catalogEvaluationKindSummaries
        self.reviewQueueCounts = reviewQueueCounts
        self.selectedAssetSetID = selectedAssetSetID
        self.catalog = catalog
        self.workerSupervisor = workerSupervisor
        self.previewCacheGenerationsByAssetID = [:]
        self.evaluationAssetIDsByItemID = [:]
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
        let sourceRoots = try repository.sourceRoots()
        let sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: repository)
        let catalogEvaluationKindSummaries = try repository.evaluationKindSummaries()
        let reviewQueueCounts = try Self.reviewQueueCounts(repository: repository)
        let pendingMetadataSyncItems = try repository.pendingMetadataSyncItems()
        let metadataSyncConflictItems = try repository.metadataSyncConflictItems()
        let recentWork = try repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let totalAssetCount = try repository.assetCount()
        return AppModel(
            sidebarSections: defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                catalogFolders: catalogFolders,
                sourceAvailabilitySummaries: sourceAvailabilitySummaries,
                catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
                reviewQueueCounts: reviewQueueCounts,
                pendingMetadataSyncItems: pendingMetadataSyncItems,
                metadataSyncConflictItems: metadataSyncConflictItems,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: totalAssetCount,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
            previewGenerationQueueStates: try repository.previewGenerationQueueStates(),
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
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
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> AppModel {
        try reconcileInterruptedIngestWorkSessions(repository: catalog.repository)
        let assets = try catalog.repository.allAssets(limit: Self.assetPageSize)
        let savedAssetSets = try catalog.repository.assetSets()
        let assetSetCounts = try Self.assetSetCounts(savedAssetSets, repository: catalog.repository)
        let catalogFolders = try catalog.repository.folders()
        let sourceRoots = try catalog.repository.sourceRoots()
        let sourceAvailabilitySummaries = try Self.sourceAvailabilitySummaries(repository: catalog.repository)
        let catalogEvaluationKindSummaries = try catalog.repository.evaluationKindSummaries()
        let reviewQueueCounts = try Self.reviewQueueCounts(repository: catalog.repository)
        let pendingMetadataSyncItems = try catalog.repository.pendingMetadataSyncItems()
        let metadataSyncConflictItems = try catalog.repository.metadataSyncConflictItems()
        let recentWork = try catalog.repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try catalog.repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let totalAssetCount = try catalog.repository.assetCount()
        let model = AppModel(
            sidebarSections: defaultSidebarSections(
                totalAssetCount: totalAssetCount,
                savedAssetSets: savedAssetSets,
                assetSetCounts: assetSetCounts,
                catalogFolders: catalogFolders,
                sourceAvailabilitySummaries: sourceAvailabilitySummaries,
                catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
                reviewQueueCounts: reviewQueueCounts,
                pendingMetadataSyncItems: pendingMetadataSyncItems,
                metadataSyncConflictItems: metadataSyncConflictItems,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: totalAssetCount,
            catalog: catalog,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
            previewGenerationQueueStates: try catalog.repository.previewGenerationQueueStates(),
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            sourceRoots: sourceRoots,
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            workerSupervisor: workerSupervisor,
            importTaskFactory: importTaskFactory,
            cardImportTaskFactory: cardImportTaskFactory
        )
        try model.enqueuePendingPreviewGeneration()
        try model.enqueuePendingMetadataSync()
        return model
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
            try enqueueMetadataSyncCheck(for: assetID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectSidebarRow(_ row: SidebarRow) throws {
        switch row.target {
        case .allPhotographs:
            selectedAssetSetID = nil
            try clearLibraryFilters()
        case .search:
            selectedAssetSetID = nil
            selectedView = .search
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
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            evaluationKindFilter = kind
            selectedView = .grid
            try reload()
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

    public func canToggleWorkSessionStarred(_ activity: AppWorkActivity) -> Bool {
        catalog != nil && persistedWorkActivityIDs.contains(activity.id)
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
        return compareWindowAssets(limit: boundedLimit, anchor: selectedAssetID)
    }

    private func compareWindowAssets(limit: Int, anchor: AssetID?) -> [Asset] {
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
        compareWindowAssets(limit: limit, anchor: anchor).map(\.id)
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

    public func applyCullingShortcut(_ shortcut: CullingShortcut) throws {
        switch shortcut {
        case .previousPhoto:
            try selectPreviousAssetForCulling()
        case .nextPhoto:
            try selectNextAssetForCulling()
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
        if let workerSupervisor {
            try catalog.repository.recordMetadataSyncPending(pendingItem)
            upsertPendingMetadataSyncItem(pendingItem)
            let itemID = WorkSessionID(rawValue: "xmp-\(asset.id.rawValue)-\(generation)")
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
            metadataSyncAssetIDsByItemID[itemID] = asset.id
            do {
                try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: asset.id))
            } catch {
                metadataSyncAssetIDsByItemID[itemID] = nil
                throw error
            }
            syncBackgroundWorkQueueFromSupervisor()
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

    private func metadataSyncConflictItem(assetID: AssetID, repository: CatalogRepository) throws -> MetadataSyncItem {
        if let item = metadataSyncConflictItems.first(where: { $0.assetID == assetID }) {
            return item
        }
        if let item = try repository.metadataSyncConflictItems().first(where: { $0.assetID == assetID }) {
            return item
        }
        throw TeststripError.invalidState("selected asset has no XMP conflict")
    }

    private func clearMetadataSyncState(assetID: AssetID) {
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
        let writeSyncID = "xmp-\(assetID.rawValue)-\(generation)"
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

    private func isSelectionMetadataSyncCheck(_ item: BackgroundWorkItem) -> Bool {
        item.kind == .xmpSync && item.title == "Check XMP"
    }

    private func upsertPendingMetadataSyncItem(_ item: MetadataSyncItem) {
        pendingMetadataSyncItems.removeAll { $0.assetID == item.assetID }
        pendingMetadataSyncItems.append(item)
    }

    private func refreshMetadataSyncState() throws {
        guard let catalog else { return }
        pendingMetadataSyncItems = try catalog.repository.pendingMetadataSyncItems()
        metadataSyncConflictItems = try catalog.repository.metadataSyncConflictItems()
        rebuildSidebarSections()
    }

    private func refreshPreviewGenerationQueueStates() throws {
        guard let catalog else { return }
        previewGenerationQueueStates = try catalog.repository.previewGenerationQueueStates()
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

    private func enqueuePendingPreviewGeneration() throws {
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
            maximumAttemptCount: Self.previewGenerationMaximumAutomaticAttempts
        ) {
            let itemID = Self.previewWorkItemID(assetID: pendingItem.assetID, level: pendingItem.level)
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
        guard let catalog, let workerSupervisor else { return }
        var enqueuedCount = 0
        for pendingItem in try catalog.repository.pendingMetadataSyncItems() {
            guard enqueuedCount < Self.pendingMetadataSyncRecoveryBatchSize else {
                break
            }
            let asset = try catalog.repository.asset(id: pendingItem.assetID)
            guard canAutomaticallyRetryMetadataSync(for: asset, sidecarURL: pendingItem.sidecarURL) else {
                continue
            }
            let itemID = WorkSessionID(rawValue: "xmp-\(pendingItem.assetID.rawValue)-\(pendingItem.catalogGeneration)")
            if backgroundWorkQueue.item(id: itemID) != nil {
                continue
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
                try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: pendingItem.assetID))
            } catch {
                metadataSyncAssetIDsByItemID[itemID] = nil
                throw error
            }
            enqueuedCount += 1
            syncBackgroundWorkQueueFromSupervisor()
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
        do {
            try workerSupervisor.enqueue(item, command: .runEvaluation(assetID: assetID, provider: provider))
        } catch {
            evaluationAssetIDsByItemID[itemID] = nil
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
        let didAccessSource = source.startAccessingSecurityScopedResource()
        let didAccessDestination = destinationRoot?.startAccessingSecurityScopedResource() ?? false
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
        case .completedImport(let itemID, _, let importedAssetIDs, let newAssetCount, let existingAssetCount):
            handleWorkerImportCompleted(
                itemID: itemID,
                importedAssetIDs: importedAssetIDs,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount
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
        evaluationSignalGenerationsByAssetID[assetID, default: 0] += 1
        refreshCatalogEvaluationKindSummaries()
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

    private static func isActiveBackgroundWorkStatus(_ status: WorkSessionStatus) -> Bool {
        [.queued, .running, .paused].contains(status)
    }

    private func handleWorkerImportCompleted(
        itemID: WorkSessionID?,
        importedAssetIDs: [AssetID],
        newAssetCount: Int,
        existingAssetCount: Int
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
        for itemID in evaluationAssetIDsByItemID.keys {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            evaluationAssetIDsByItemID[itemID] = nil
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

    private func stopAccessingWorkerImportResources(_ context: WorkerImportContext) {
        if context.didAccessSource {
            context.source.stopAccessingSecurityScopedResource()
        }
        if context.didAccessDestination {
            context.destinationRoot?.stopAccessingSecurityScopedResource()
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
        return importItems.first { $0.kind == .ingest && $0.status == .running } ??
            importItems.first { $0.kind == .ingest && $0.status == .paused } ??
            importItems.first { $0.kind == .ingest && $0.status == .queued }
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

    private func currentLibraryQuery() -> SetQuery? {
        var predicates: [SetQuery.Predicate] = []
        if let selectedDynamicSetQuery {
            predicates.append(contentsOf: selectedDynamicSetQuery.predicates)
        }
        let trimmedSearch = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            predicates.append(.text(trimmedSearch))
        }
        let trimmedKeyword = keywordFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            predicates.append(.keyword(trimmedKeyword))
        }
        let trimmedFolder = folderFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            predicates.append(.folderPrefix(trimmedFolder))
        }
        if let minimumRatingFilter {
            predicates.append(.ratingAtLeast(minimumRatingFilter))
        }
        if let flagFilter {
            predicates.append(.flag(flagFilter))
        }
        if let colorLabelFilter {
            predicates.append(.colorLabel(colorLabelFilter))
        }
        let trimmedCamera = cameraFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCamera.isEmpty {
            predicates.append(.camera(trimmedCamera))
        }
        let trimmedLens = lensFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLens.isEmpty {
            predicates.append(.lens(trimmedLens))
        }
        if let minimumISOFilter, minimumISOFilter > 0 {
            predicates.append(.isoAtLeast(minimumISOFilter))
        }
        if let captureDateStartFilter {
            predicates.append(.capturedAtOrAfter(captureDateStartFilter))
        }
        if let captureDateEndFilter {
            predicates.append(.capturedBefore(captureDateEndFilter))
        }
        if let availabilityFilter {
            predicates.append(.availability(availabilityFilter))
        }
        if let evaluationKindFilter {
            predicates.append(.evaluationKind(evaluationKindFilter))
        }
        if needsKeywordsFilter {
            predicates.append(.missingKeywords)
        }
        if needsEvaluationFilter {
            predicates.append(.unevaluated)
        }
        if metadataSyncPendingFilter {
            predicates.append(.metadataSyncPending)
        }
        if metadataSyncConflictFilter {
            predicates.append(.metadataSyncConflict)
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
            sourceAvailabilitySummaries: sourceAvailabilitySummaries,
            catalogEvaluationKindSummaries: catalogEvaluationKindSummaries,
            reviewQueueCounts: reviewQueueCounts,
            pendingMetadataSyncItems: pendingMetadataSyncItems,
            metadataSyncConflictItems: metadataSyncConflictItems,
            recentWork: recentWork,
            starredWork: starredWork
        )
    }

    private func refreshCatalogFolders() {
        guard let catalog else { return }
        do {
            catalogFolders = try catalog.repository.folders()
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
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        if workerSupervisor != nil {
            enqueueWorkerImport(source: folderURL, destinationRoot: nil, command: .importFolder(root: folderURL))
            return
        }
        startImportActivity(folderURL: folderURL)
        guard let activityID = activeWork?.id else { return }

        let didAccess = folderURL.startAccessingSecurityScopedResource()
        let task = importTaskFactory(
            catalog.paths,
            folderURL,
            importProgressHandler(activityID: activityID)
        )
        activeImportTask = task
        Task { @MainActor [weak self] in
            defer {
                if didAccess {
                    folderURL.stopAccessingSecurityScopedResource()
                }
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
        startImportActivity(folderURL: source, destinationRoot: destinationRoot)
        guard let activityID = activeWork?.id else { return }

        let didAccessSource = source.startAccessingSecurityScopedResource()
        let didAccessDestination = destinationRoot.startAccessingSecurityScopedResource()
        let task = cardImportTaskFactory(
            catalog.paths,
            source,
            destinationRoot,
            importProgressHandler(activityID: activityID)
        )
        activeImportTask = task
        Task { @MainActor [weak self] in
            defer {
                if didAccessSource {
                    source.stopAccessingSecurityScopedResource()
                }
                if didAccessDestination {
                    destinationRoot.stopAccessingSecurityScopedResource()
                }
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
        if !result.previewFailures.isEmpty {
            statusMessage?.append(" (\(result.previewFailures.count) preview failures)")
        }
    }

    private static func importCompletionStatus(result: LibraryImportResult) -> String {
        guard !result.importedAssets.isEmpty else {
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
            completedUnitCount: result.importedAssets.count,
            totalUnitCount: result.importedAssets.count,
            failureCount: result.previewFailures.count
        )
        let outputSetIDs = saveImportOutputSet(for: activity, result: result)
        refreshCatalogFolders()
        activeWork = nil
        recordRecentActivity(activity, outputSetIDs: outputSetIDs)
    }

    private static func importCompletionDetail(result: LibraryImportResult, sourceDescription: String) -> String {
        if result.importedAssets.isEmpty {
            return "No supported photos found in \(sourceDescription)"
        }
        if result.newAssetCount == 0 {
            return "No new photos found in \(sourceDescription)"
        }
        return "\(importCompletionStatus(result: result)) from \(sourceDescription)"
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
        activity.kind == .ingest && activity.status == .completed && activity.completedUnitCount > 0
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
        sourceAvailabilitySummaries: [CatalogSourceAvailabilitySummary] = [],
        catalogEvaluationKindSummaries: [CatalogEvaluationKindSummary] = [],
        reviewQueueCounts: [ReviewQueue: Int] = [:],
        pendingMetadataSyncItems: [MetadataSyncItem] = [],
        metadataSyncConflictItems: [MetadataSyncItem] = [],
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
        if !pendingMetadataSyncItems.isEmpty {
            syncRows.append(
                SidebarRow(
                    id: "sync-xmp-pending",
                    title: "XMP Pending",
                    countText: sidebarCountText(pendingMetadataSyncItems.count),
                    tone: .warning,
                    target: .metadataSyncPending
                )
            )
        }
        if !metadataSyncConflictItems.isEmpty {
            syncRows.append(
                SidebarRow(
                    id: "sync-xmp-conflicts",
                    title: "XMP Conflicts",
                    countText: sidebarCountText(metadataSyncConflictItems.count),
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
        let workRows = Self.workSidebarRows(recentWork: recentWork, starredWork: starredWork)
        if workRows.isEmpty {
            sections.append(SidebarSection(title: "Work", rows: workPlaceholderSidebarRows()))
        } else {
            sections.append(SidebarSection(title: "Work", rows: workRows))
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
        .needsEvaluation
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

    private static func workSidebarRows(
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity]
    ) -> [SidebarRow] {
        var rows = recentWork.prefix(5).map { activity in
            SidebarRow(
                id: "work-recent-\(activity.id)",
                title: workSidebarTitle(for: activity),
                detailText: activity.sidebarDetailText,
                countText: activity.sidebarCountText,
                tone: activity.sidebarTone,
                target: .workSession(WorkSessionID(rawValue: activity.id))
            )
        }
        let recentIDs = Set(recentWork.map(\.id))
        rows.append(contentsOf: starredWork.prefix(5).filter { !recentIDs.contains($0.id) }.map { activity in
            SidebarRow(
                id: "work-starred-\(activity.id)",
                title: workSidebarTitle(for: activity),
                detailText: activity.sidebarDetailText,
                countText: activity.sidebarCountText,
                tone: activity.sidebarTone,
                target: .workSession(WorkSessionID(rawValue: activity.id))
            )
        })
        return rows
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
