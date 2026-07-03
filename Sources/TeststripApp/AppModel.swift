import Foundation
import Observation
import TeststripCore

public enum LibraryViewMode: String, Sendable {
    case grid
    case loupe
    case compare
    case timeline
    case map
    case people
}

public enum CullingCommand: Equatable, Sendable {
    case rating(Int)
    case pick
    case reject
    case clearFlag
}

public enum CullingShortcut: Equatable, Sendable {
    case previousPhoto
    case nextPhoto
    case rating(Int)
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

public enum SidebarRowTarget: Equatable, Sendable {
    case allPhotographs
    case placeholder
    case assetSet(AssetSetID)
    case workSession(WorkSessionID)
}

public struct SidebarRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var target: SidebarRowTarget

    public init(id: String, title: String, target: SidebarRowTarget = .placeholder) {
        self.id = id
        self.title = title
        self.target = target
    }

    public var isSelectable: Bool {
        target != .placeholder
    }
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

public struct AppWorkActivity: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: WorkSessionKind
    public var status: WorkSessionStatus
    public var title: String
    public var detail: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var failureCount: Int

    public init(
        id: String = UUID().uuidString,
        kind: WorkSessionKind,
        status: WorkSessionStatus,
        title: String,
        detail: String,
        completedUnitCount: Int,
        totalUnitCount: Int?,
        failureCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.failureCount = failureCount
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
            failureCount: workSession.failureCount
        )
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
}

@Observable
public final class AppModel {
    public var sidebarSections: [SidebarSection]
    public var selectedView: LibraryViewMode
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
    public var backgroundWorkQueue: BackgroundWorkQueue
    public var librarySearchText: String
    public var minimumRatingFilter: Int?
    public var flagFilter: PickFlag?
    public var cameraFilterText: String
    public var lensFilterText: String
    public var minimumISOFilter: Int?
    public var captureDateStartFilter: Date?
    public var captureDateEndFilter: Date?
    public var savedAssetSets: [AssetSet]
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

    private var previewCacheGenerationsByAssetID: [AssetID: Int]
    private var evaluationSignalGenerationsByAssetID: [AssetID: Int]
    private var metadataUndoStack: [MetadataChange]
    private var metadataRedoStack: [MetadataChange]
    private var assetPageOffset: Int

    public static let defaultEvaluationProviderName = "local-image-metrics"
    public static let defaultEvaluationProviderNames = [defaultEvaluationProviderName, "apple-vision"]
    private static let assetPageSize = 500
    private static let loadedAssetWindowSize = assetPageSize * 2
    private static let pendingPreviewRecoveryBatchSize = 200

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
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

    public var canPauseBackgroundWork: Bool {
        !backgroundWorkQueue.runningItems.isEmpty
    }

    public var canResumeBackgroundWork: Bool {
        backgroundWorkQueue.isPaused
    }

    public var canCancelBackgroundWork: Bool {
        backgroundWorkQueue.items.contains { [.queued, .running, .paused].contains($0.status) }
    }

    public var isImporting: Bool {
        if activeWork?.kind == .ingest, let status = activeWork?.status, [.queued, .running, .paused].contains(status) {
            return true
        }
        return backgroundWorkQueue.items.contains { item in
            item.kind == .ingest && [.queued, .running, .paused].contains(item.status)
        }
    }

    public var canRequestSelectedAssetEvaluation: Bool {
        selectedAssetID != nil && workerSupervisor != nil
    }

    public var selectedEvaluationSignals: [EvaluationSignal] {
        guard let catalog, let selectedAssetID else { return [] }
        _ = evaluationSignalGeneration(for: selectedAssetID)
        return (try? catalog.repository.evaluationSignals(assetID: selectedAssetID)) ?? []
    }

    public var starredAssetSets: [AssetSet] {
        savedAssetSets.filter(\.starred)
    }

    public var canSaveCurrentLibraryQuery: Bool {
        currentLibraryQuery() != nil
    }

    public var hasActiveLibraryFilters: Bool {
        selectedAssetSetID != nil || currentLibraryQuery() != nil
    }

    public var canSaveSelectedAssetAsManualSet: Bool {
        catalog != nil && selectedAssetID != nil
    }

    public var suggestedSavedSearchName: String {
        var parts: [String] = []
        let trimmedSearch = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            parts.append(trimmedSearch)
        }
        if let minimumRatingFilter {
            parts.append("\(minimumRatingFilter)+ Stars")
        }
        if let flagFilter {
            parts.append(flagFilter.rawValue.capitalized)
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
        backgroundWorkQueue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        savedAssetSets: [AssetSet] = [],
        selectedAssetSetID: AssetSetID? = nil,
        workerSupervisor: WorkerSupervisor? = nil,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil
    ) {
        self.sidebarSections = sidebarSections.isEmpty ? Self.defaultSidebarSections(
            savedAssetSets: savedAssetSets,
            recentWork: recentWork,
            starredWork: starredWork
        ) : sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.totalAssetCount = totalAssetCount ?? assets.count
        self.selectedAssetID = assets.first?.id
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.activeWork = activeWork
        self.recentWork = recentWork
        self.starredWork = starredWork
        self.pendingMetadataSyncItems = pendingMetadataSyncItems
        self.metadataSyncConflictItems = metadataSyncConflictItems
        self.backgroundWorkQueue = backgroundWorkQueue
        self.librarySearchText = ""
        self.minimumRatingFilter = nil
        self.flagFilter = nil
        self.cameraFilterText = ""
        self.lensFilterText = ""
        self.minimumISOFilter = nil
        self.captureDateStartFilter = nil
        self.captureDateEndFilter = nil
        self.savedAssetSets = savedAssetSets
        self.selectedAssetSetID = selectedAssetSetID
        self.catalog = catalog
        self.workerSupervisor = workerSupervisor
        self.previewCacheGenerationsByAssetID = [:]
        self.evaluationAssetIDsByItemID = [:]
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
        self.workerImportContextsByItemID = [:]
        self.workerSupervisor?.onQueueChanged = { [weak self] queue in
            self?.backgroundWorkQueue = queue
            try? self?.refreshMetadataSyncState()
            self?.releaseInactiveWorkerImportContexts(in: queue)
            self?.releaseInactiveEvaluationContexts(in: queue)
        }
        self.workerSupervisor?.onCommandCompleted = { [weak self] event in
            self?.handleWorkerCommandCompleted(event)
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
            sidebarSections: defaultSidebarSections(),
            selectedView: .grid,
            assets: [asset]
        )
    }

    public static func load(repository: CatalogRepository) throws -> AppModel {
        let assets = try repository.allAssets(limit: Self.assetPageSize)
        let savedAssetSets = try repository.assetSets()
        let recentWork = try repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        return AppModel(
            sidebarSections: defaultSidebarSections(
                savedAssetSets: savedAssetSets,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: try repository.assetCount(),
            recentWork: recentWork,
            starredWork: starredWork,
            savedAssetSets: savedAssetSets
        )
    }

    public static func load(
        catalog: AppCatalog,
        importTaskFactory: AppImportTaskFactory? = nil,
        cardImportTaskFactory: AppCardImportTaskFactory? = nil,
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> AppModel {
        let assets = try catalog.repository.allAssets(limit: Self.assetPageSize)
        let savedAssetSets = try catalog.repository.assetSets()
        let recentWork = try catalog.repository.workSessions(limit: 10).map(AppWorkActivity.init)
        let starredWork = try catalog.repository.workSessions(limit: 10, starredOnly: true).map(AppWorkActivity.init)
        let model = AppModel(
            sidebarSections: defaultSidebarSections(
                savedAssetSets: savedAssetSets,
                recentWork: recentWork,
                starredWork: starredWork
            ),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: try catalog.repository.assetCount(),
            catalog: catalog,
            recentWork: recentWork,
            starredWork: starredWork,
            pendingMetadataSyncItems: try catalog.repository.pendingMetadataSyncItems(),
            metadataSyncConflictItems: try catalog.repository.metadataSyncConflictItems(),
            savedAssetSets: savedAssetSets,
            workerSupervisor: workerSupervisor,
            importTaskFactory: importTaskFactory,
            cardImportTaskFactory: cardImportTaskFactory
        )
        try model.enqueuePendingPreviewGeneration()
        try model.enqueuePendingMetadataSync()
        return model
    }

    public func select(_ assetID: AssetID) {
        selectAssetID(assetID)
    }

    private func selectAssetID(_ assetID: AssetID?) {
        selectedAssetID = assetID
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
            return
        }
        statusMessage = session.detail.isEmpty ? session.title : session.detail
    }

    public func applyAssetSet(id: AssetSetID) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let assetSet = try assetSetForSelection(id: id, repository: catalog.repository)
        if !savedAssetSets.contains(where: { $0.id == assetSet.id }) {
            savedAssetSets.append(assetSet)
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
        selectedAssetSetID = assetSet.id
        clearLibraryQueryFilters()
        rebuildSidebarSections()
        try reload()
        statusMessage = "Saved \(assetSet.name)"
        return assetSet
    }

    public func openAssetInLoupe(_ assetID: AssetID) {
        select(assetID)
        selectedView = .loupe
    }

    public func compareAssets(limit: Int = 4) -> [Asset] {
        guard !assets.isEmpty else { return [] }
        let boundedLimit = max(1, limit)
        let selectedIndex = selectedAssetID.flatMap { selectedID in
            assets.firstIndex { $0.id == selectedID }
        } ?? 0
        let maximumStartIndex = max(assets.count - boundedLimit, 0)
        let startIndex = min(max(selectedIndex - 1, 0), maximumStartIndex)
        let endIndex = min(startIndex + boundedLimit, assets.count)
        return Array(assets[startIndex..<endIndex])
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
            try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: asset.id))
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

    private func enqueueMetadataSyncCheck(for assetID: AssetID) throws {
        guard let catalog, let workerSupervisor else { return }
        let generation = try catalog.repository.catalogGeneration(assetID: assetID)
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
        try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: assetID))
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func hasActiveMetadataSyncWork(assetID: AssetID, generation: Int) -> Bool {
        let writeSyncID = "xmp-\(assetID.rawValue)-\(generation)"
        let selectionCheckPrefix = "xmp-check-\(assetID.rawValue)-\(generation)-"
        return backgroundWorkQueue.items.contains { item in
            item.kind == .xmpSync
                && [.queued, .running, .paused].contains(item.status)
                && (item.id.rawValue == writeSyncID || item.id.rawValue.hasPrefix(selectionCheckPrefix))
        }
    }

    private func upsertPendingMetadataSyncItem(_ item: MetadataSyncItem) {
        pendingMetadataSyncItems.removeAll { $0.assetID == item.assetID }
        pendingMetadataSyncItems.append(item)
    }

    private func refreshMetadataSyncState() throws {
        guard let catalog else { return }
        pendingMetadataSyncItems = try catalog.repository.pendingMetadataSyncItems()
        metadataSyncConflictItems = try catalog.repository.metadataSyncConflictItems()
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

    public func requestPreview(assetID: AssetID, level: PreviewLevel) throws {
        if previewURL(for: assetID, levels: [level]) != nil {
            return
        }
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
        }
        let itemID = WorkSessionID(rawValue: "preview-\(assetID.rawValue)-\(level.rawValue)")
        if backgroundWorkQueue.item(id: itemID) != nil {
            return
        }

        let item = BackgroundWorkItem(
            id: itemID,
            kind: .previewGeneration,
            title: "Generate preview",
            detail: "Rendering \(level.rawValue) preview",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        try workerSupervisor.enqueue(item, command: .generatePreview(assetID: assetID, level: level))
        syncBackgroundWorkQueueFromSupervisor()
    }

    private func enqueuePendingPreviewGeneration() throws {
        guard let catalog, workerSupervisor != nil else { return }
        for item in try catalog.repository.pendingPreviewGenerationItems(limit: Self.pendingPreviewRecoveryBatchSize) {
            if previewURL(for: item.assetID, levels: [item.level]) != nil {
                try catalog.repository.markPreviewGenerated(assetID: item.assetID, level: item.level)
                continue
            }
            try requestPreview(assetID: item.assetID, level: item.level)
        }
    }

    private func enqueuePendingMetadataSync() throws {
        guard let catalog, let workerSupervisor else { return }
        for pendingItem in try catalog.repository.pendingMetadataSyncItems() {
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
            try workerSupervisor.enqueue(item, command: .syncMetadata(assetID: pendingItem.assetID))
            syncBackgroundWorkQueueFromSupervisor()
        }
    }

    public func requestVisibleGridPreview(assetID: AssetID) throws {
        if let asset = assets.first(where: { $0.id == assetID }),
           [.offline, .missing].contains(asset.availability) {
            return
        }

        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .grid(distanceFromViewport: 0)
        )
        try requestPreview(assetID: request.assetID, level: request.level)
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
        if try refreshAvailability(for: assetID) == .missing {
            return
        }
        if request.level == .large, previewURL(for: assetID, levels: [.medium]) == nil {
            try requestPreview(assetID: assetID, level: .medium)
        }
        try requestPreview(assetID: assetID, level: request.level)
    }

    public func requestVisibleComparePreviews() throws {
        let compareAssets = compareAssets()
        if let selectedAssetID,
           compareAssets.contains(where: { $0.id == selectedAssetID }),
           previewURL(for: selectedAssetID, levels: [.medium]) != nil {
            try requestPreview(assetID: selectedAssetID, level: .large)
        }

        for asset in compareAssets {
            try requestPreview(assetID: asset.id, level: .medium)
        }
    }

    public func requestEvaluation(assetID: AssetID, provider: String = AppModel.defaultEvaluationProviderName) throws {
        guard let workerSupervisor else {
            throw TeststripError.invalidState("worker supervisor is not configured")
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

    private func syncBackgroundWorkQueueFromSupervisor() {
        if let workerSupervisor {
            backgroundWorkQueue = workerSupervisor.queue
        }
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
            if completedPreview {
                do {
                    try enqueuePendingPreviewGeneration()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .completedImport(let itemID, _, let importedAssetIDs):
            handleWorkerImportCompleted(itemID: itemID, importedAssetIDs: importedAssetIDs)
        case .accepted, .progress, .failed:
            return
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

    private func handleWorkerImportCompleted(itemID: WorkSessionID?, importedAssetIDs: [AssetID]) {
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
            let result = LibraryImportResult(importedAssets: importedAssets, previewFailures: [])
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
        for itemID in workerImportContextsByItemID.keys {
            guard let item = queue.item(id: itemID), [.cancelled, .failed].contains(item.status) else {
                continue
            }
            if let context = workerImportContextsByItemID.removeValue(forKey: itemID) {
                stopAccessingWorkerImportResources(context)
                if item.status == .failed {
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

    private var activeBackgroundImportItem: BackgroundWorkItem? {
        backgroundWorkQueue.runningItems.first { $0.kind == .ingest } ??
            backgroundWorkQueue.items.first { $0.kind == .ingest && $0.status == .paused } ??
            backgroundWorkQueue.queuedItems.first { $0.kind == .ingest }
    }

    private func isVisibleInactiveBackgroundWork(_ item: BackgroundWorkItem) -> Bool {
        guard [.cancelled, .failed, .completed].contains(item.status) else {
            return false
        }
        return !(item.status == .completed && item.kind == .xmpSync && item.title == "Check XMP")
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

    public func refreshSelectedAssetAvailability() throws {
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        _ = try refreshAvailability(for: selectedAssetID)
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
        if let minimumRatingFilter {
            predicates.append(.ratingAtLeast(minimumRatingFilter))
        }
        if let flagFilter {
            predicates.append(.flag(flagFilter))
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
        return predicates.isEmpty ? nil : SetQuery(predicates: predicates)
    }

    private func clearLibraryQueryFilters() {
        librarySearchText = ""
        minimumRatingFilter = nil
        flagFilter = nil
        cameraFilterText = ""
        lensFilterText = ""
        minimumISOFilter = nil
        captureDateStartFilter = nil
        captureDateEndFilter = nil
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

    private func assetSetForSelection(id: AssetSetID, repository: CatalogRepository) throws -> AssetSet {
        if let assetSet = savedAssetSets.first(where: { $0.id == id }) {
            return assetSet
        }
        return try repository.assetSet(id: id)
    }

    private func rebuildSidebarSections() {
        sidebarSections = Self.defaultSidebarSections(
            savedAssetSets: savedAssetSets,
            recentWork: recentWork,
            starredWork: starredWork
        )
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
        let photoLabel = result.importedAssets.count == 1 ? "photo" : "photos"
        statusMessage = "Imported \(result.importedAssets.count) \(photoLabel)"
        if !result.previewFailures.isEmpty {
            statusMessage?.append(" (\(result.previewFailures.count) preview failures)")
        }
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
        let photoLabel = result.importedAssets.count == 1 ? "photo" : "photos"
        let activity = AppWorkActivity(
            id: id ?? activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .completed,
            title: "Import photos",
            detail: "Imported \(result.importedAssets.count) \(photoLabel) from \(importSourceDescription(folderURL: folderURL, destinationRoot: destinationRoot))",
            completedUnitCount: result.importedAssets.count,
            totalUnitCount: result.importedAssets.count,
            failureCount: result.previewFailures.count
        )
        let outputSetIDs = saveImportOutputSet(for: activity, result: result)
        activeWork = nil
        recordRecentActivity(activity, outputSetIDs: outputSetIDs)
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

    private func cancelImportActivity(folderURL: URL, destinationRoot: URL? = nil) {
        let activity = AppWorkActivity(
            id: activeWork?.id ?? UUID().uuidString,
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
            }
            return [outputSetID]
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func recordRecentActivity(
        _ activity: AppWorkActivity,
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) {
        recentWork.removeAll { $0.id == activity.id }
        recentWork.insert(activity, at: 0)
        rebuildSidebarSections()
        guard let catalog else { return }
        do {
            try catalog.repository.save(activity.workSession(inputSetIDs: inputSetIDs, outputSetIDs: outputSetIDs))
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

    public func gridPreviewURL(for assetID: AssetID) -> URL? {
        previewURL(for: assetID, levels: [.grid])
    }

    public func loupePreviewURL(for assetID: AssetID) -> URL? {
        previewURL(for: assetID, levels: [.large, .medium, .grid])
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

    private static func defaultSidebarSections(
        savedAssetSets: [AssetSet] = [],
        recentWork: [AppWorkActivity] = [],
        starredWork: [AppWorkActivity] = []
    ) -> [SidebarSection] {
        var sections = [
            SidebarSection(title: "Library", rows: [
                SidebarRow(id: "library-all", title: "All Photographs", target: .allPhotographs),
                SidebarRow(id: "library-folders", title: "Folders"),
                SidebarRow(id: "library-people", title: "People")
            ])
        ]
        let starredRows = savedAssetSets.filter(\.starred).map { Self.sidebarRow(for: $0) }
        if !starredRows.isEmpty {
            sections.append(SidebarSection(title: "Starred", rows: starredRows))
        }
        if !savedAssetSets.isEmpty {
            sections.append(SidebarSection(title: "Saved Sets", rows: savedAssetSets.map { Self.sidebarRow(for: $0) }))
        }
        let workRows = Self.workSidebarRows(recentWork: recentWork, starredWork: starredWork)
        if workRows.isEmpty {
            sections.append(SidebarSection(title: "Work", rows: ["Recent", "Starred"]))
        } else {
            sections.append(SidebarSection(title: "Work", rows: workRows))
        }
        return sections
    }

    private static func sidebarRow(for assetSet: AssetSet) -> SidebarRow {
        SidebarRow(
            id: "asset-set-\(assetSet.id.rawValue)",
            title: assetSet.name,
            target: .assetSet(assetSet.id)
        )
    }

    private static func workSidebarRows(
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity]
    ) -> [SidebarRow] {
        var rows = recentWork.prefix(5).map { activity in
            SidebarRow(
                id: "work-recent-\(activity.id)",
                title: activity.title,
                target: .workSession(WorkSessionID(rawValue: activity.id))
            )
        }
        let recentIDs = Set(recentWork.map(\.id))
        rows.append(contentsOf: starredWork.prefix(5).filter { !recentIDs.contains($0.id) }.map { activity in
            SidebarRow(
                id: "work-starred-\(activity.id)",
                title: activity.title,
                target: .workSession(WorkSessionID(rawValue: activity.id))
            )
        })
        return rows
    }
}

private extension AppWorkActivity {
    func workSession(
        now: Date = Date(),
        inputSetIDs: [AssetSetID] = [],
        outputSetIDs: [AssetSetID] = []
    ) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: kind,
            intent: title,
            title: title,
            detail: detail,
            status: status,
            inputSetIDs: inputSetIDs,
            outputSetIDs: outputSetIDs,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            failureCount: failureCount,
            createdAt: now,
            updatedAt: now
        )
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
