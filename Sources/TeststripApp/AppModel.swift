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

public struct SidebarSection: Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var rows: [String]

    public init(title: String, rows: [String]) {
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
}

public struct AppImportOutput: Sendable {
    public var result: LibraryImportResult
    public var assets: [Asset]
    public var totalAssetCount: Int

    public init(result: LibraryImportResult, assets: [Asset], totalAssetCount: Int) {
        self.result = result
        self.assets = assets
        self.totalAssetCount = totalAssetCount
    }
}

public typealias AppImportTaskFactory = @Sendable (
    AppCatalogPaths,
    URL,
    @escaping LibraryImportProgressHandler
) -> Task<AppImportOutput, Error>

private struct MetadataChange: Equatable {
    var assetID: AssetID
    var before: AssetMetadata
    var after: AssetMetadata
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
    public var pendingMetadataSyncItems: [MetadataSyncItem]
    public var backgroundWorkQueue: BackgroundWorkQueue

    @ObservationIgnored
    private var catalog: AppCatalog?

    @ObservationIgnored
    private let importTaskFactory: AppImportTaskFactory

    @ObservationIgnored
    private let workerSupervisor: WorkerSupervisor?

    @ObservationIgnored
    private var activeImportTask: Task<AppImportOutput, Error>?

    private var metadataUndoStack: [MetadataChange]
    private var metadataRedoStack: [MetadataChange]

    private static let assetPageSize = 500

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public var hasMoreAssets: Bool {
        assets.count < totalAssetCount
    }

    public var libraryCountText: String {
        if totalAssetCount > assets.count {
            return "Showing \(assets.count) of \(totalAssetCount) photographs"
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
        if let activeWork {
            return activeWork
        }
        if let backgroundItem = visibleBackgroundWorkItem {
            return AppWorkActivity(workItem: backgroundItem)
        }
        return recentWork.first
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
        pendingMetadataSyncItems: [MetadataSyncItem] = [],
        backgroundWorkQueue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        workerSupervisor: WorkerSupervisor? = nil,
        importTaskFactory: AppImportTaskFactory? = nil
    ) {
        self.sidebarSections = sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.totalAssetCount = totalAssetCount ?? assets.count
        self.selectedAssetID = assets.first?.id
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.activeWork = activeWork
        self.recentWork = recentWork
        self.pendingMetadataSyncItems = pendingMetadataSyncItems
        self.backgroundWorkQueue = backgroundWorkQueue
        self.catalog = catalog
        self.workerSupervisor = workerSupervisor
        self.importTaskFactory = importTaskFactory ?? Self.defaultImportTask
        self.metadataUndoStack = []
        self.metadataRedoStack = []
        self.workerSupervisor?.onQueueChanged = { [weak self] queue in
            self?.backgroundWorkQueue = queue
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
        return AppModel(
            sidebarSections: defaultSidebarSections(),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: try repository.assetCount()
        )
    }

    public static func load(
        catalog: AppCatalog,
        importTaskFactory: AppImportTaskFactory? = nil,
        workerSupervisor: WorkerSupervisor? = nil
    ) throws -> AppModel {
        let assets = try catalog.repository.allAssets(limit: Self.assetPageSize)
        return AppModel(
            sidebarSections: defaultSidebarSections(),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: try catalog.repository.assetCount(),
            catalog: catalog,
            pendingMetadataSyncItems: try catalog.repository.pendingMetadataSyncItems(),
            workerSupervisor: workerSupervisor,
            importTaskFactory: importTaskFactory
        )
    }

    public func select(_ assetID: AssetID) {
        selectedAssetID = assetID
    }

    public func openAssetInLoupe(_ assetID: AssetID) {
        select(assetID)
        selectedView = .loupe
    }

    public func selectNextAsset() {
        guard !assets.isEmpty else {
            selectedAssetID = nil
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectedAssetID = assets.first?.id
            return
        }
        selectedAssetID = assets[min(index + 1, assets.count - 1)].id
    }

    public func selectPreviousAsset() {
        guard !assets.isEmpty else {
            selectedAssetID = nil
            return
        }
        guard let currentSelection = selectedAssetID,
              let index = assets.firstIndex(where: { $0.id == currentSelection }) else {
            selectedAssetID = assets.first?.id
            return
        }
        selectedAssetID = assets[max(index - 1, 0)].id
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
            selectPreviousAsset()
        case .nextPhoto:
            selectNextAsset()
        case .rating(let rating):
            try applyCullingCommand(.rating(rating))
        case .pick:
            try applyCullingCommand(.pick)
        case .reject:
            try applyCullingCommand(.reject)
        case .clearFlag:
            try applyCullingCommand(.clearFlag)
        }
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

    private func upsertPendingMetadataSyncItem(_ item: MetadataSyncItem) {
        pendingMetadataSyncItems.removeAll { $0.assetID == item.assetID }
        pendingMetadataSyncItems.append(item)
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
            if let workerSupervisor {
                try workerSupervisor.cancelAll()
                syncBackgroundWorkQueueFromSupervisor()
            } else {
                backgroundWorkQueue.cancelAll()
            }
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

    public func requestVisibleLoupePreview(assetID: AssetID) throws {
        let request = PreviewScheduler().request(
            assetID: assetID,
            context: .loupe(isVisible: true, requestedFullResolution: false)
        )
        if previewURL(for: assetID, levels: [request.level]) != nil {
            return
        }
        if request.level == .large, previewURL(for: assetID, levels: [.medium]) == nil {
            try requestPreview(assetID: assetID, level: .medium)
        }
        try requestPreview(assetID: assetID, level: request.level)
    }

    private func syncBackgroundWorkQueueFromSupervisor() {
        if let workerSupervisor {
            backgroundWorkQueue = workerSupervisor.queue
        }
    }

    private var visibleBackgroundWorkItem: BackgroundWorkItem? {
        backgroundWorkQueue.runningItems.first ??
            backgroundWorkQueue.items.first { $0.status == .paused } ??
            backgroundWorkQueue.queuedItems.first ??
            backgroundWorkQueue.items.last { [.cancelled, .failed, .completed].contains($0.status) }
    }

    public func reload() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let loadedAssets = try catalog.repository.allAssets(limit: Self.assetPageSize)
        let count = try catalog.repository.assetCount()
        replaceAssets(loadedAssets)
        totalAssetCount = count
    }

    public func loadMoreAssets() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard hasMoreAssets else { return }
        let loadedAssets = try catalog.repository.allAssets(limit: Self.assetPageSize, offset: assets.count)
        assets.append(contentsOf: loadedAssets)
        totalAssetCount = try catalog.repository.assetCount()
        if selectedAssetID == nil {
            selectedAssetID = assets.first?.id
        }
    }

    public func refreshSelectedAssetAvailability() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let asset = try catalog.repository.asset(id: selectedAssetID)
        let availability = SourceAvailabilityProbe().availability(for: asset)
        try catalog.repository.updateAvailability(assetID: selectedAssetID, availability: availability)
        let updatedAsset = try catalog.repository.asset(id: selectedAssetID)
        guard let index = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return
        }
        assets[index] = updatedAsset
    }

    private func replaceAssets(_ loadedAssets: [Asset]) {
        let previousSelection = selectedAssetID
        assets = loadedAssets
        if let previousSelection, assets.contains(where: { $0.id == previousSelection }) {
            selectedAssetID = previousSelection
        } else {
            selectedAssetID = assets.first?.id
        }
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
            let result = try catalog.importService.addFolderInPlace(folderURL, repository: catalog.repository)
            try reload()
            updateImportStatus(with: result)
            completeImportActivity(folderURL: folderURL, result: result)
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
            replaceAssets(output.assets)
            totalAssetCount = output.totalAssetCount
            updateImportStatus(with: output.result)
            completeImportActivity(folderURL: folderURL, result: output.result)
            return output.result
        } catch {
            failImportActivity(folderURL: folderURL, error: error)
            throw error
        }
    }

    @MainActor
    public func beginImportFolder(_ folderURL: URL) {
        guard let catalog else {
            errorMessage = TeststripError.invalidState("app model has no catalog").localizedDescription
            return
        }
        guard activeImportTask == nil else {
            errorMessage = "Another import is already running"
            return
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
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
                self.replaceAssets(output.assets)
                self.totalAssetCount = output.totalAssetCount
                self.updateImportStatus(with: output.result)
                self.completeImportActivity(folderURL: folderURL, result: output.result)
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

    private func startImportActivity(folderURL: URL) {
        activeWork = AppWorkActivity(
            kind: .ingest,
            status: .running,
            title: "Import photos",
            detail: "Importing from \(folderURL.lastPathComponent)",
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
        guard var activity = activeWork else { return }
        activity.detail = progress.detail
        activity.completedUnitCount = progress.completedUnitCount
        activity.totalUnitCount = progress.totalUnitCount
        activeWork = activity
    }

    private func completeImportActivity(folderURL: URL, result: LibraryImportResult) {
        let photoLabel = result.importedAssets.count == 1 ? "photo" : "photos"
        let activity = AppWorkActivity(
            id: activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .completed,
            title: "Import photos",
            detail: "Imported \(result.importedAssets.count) \(photoLabel) from \(folderURL.lastPathComponent)",
            completedUnitCount: result.importedAssets.count,
            totalUnitCount: result.importedAssets.count,
            failureCount: result.previewFailures.count
        )
        activeWork = nil
        recentWork.insert(activity, at: 0)
    }

    private func failImportActivity(folderURL: URL, error: Error) {
        let activity = AppWorkActivity(
            id: activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .failed,
            title: "Import photos",
            detail: "Import failed from \(folderURL.lastPathComponent): \(error.localizedDescription)",
            completedUnitCount: 0,
            totalUnitCount: nil,
            failureCount: 1
        )
        activeWork = nil
        recentWork.insert(activity, at: 0)
    }

    private func cancelImportActivity(folderURL: URL) {
        let activity = AppWorkActivity(
            id: activeWork?.id ?? UUID().uuidString,
            kind: .ingest,
            status: .cancelled,
            title: "Import photos",
            detail: "Cancelled import from \(folderURL.lastPathComponent)",
            completedUnitCount: activeWork?.completedUnitCount ?? 0,
            totalUnitCount: activeWork?.totalUnitCount,
            failureCount: 0
        )
        activeWork = nil
        statusMessage = "Cancelled import"
        recentWork.insert(activity, at: 0)
    }

    private static func defaultImportTask(
        paths: AppCatalogPaths,
        folderURL: URL,
        progress: @escaping LibraryImportProgressHandler
    ) -> Task<AppImportOutput, Error> {
        Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.addFolderInPlace(
                folderURL,
                repository: backgroundCatalog.repository,
                progress: progress
            )
            try Task.checkCancellation()
            let assets = try backgroundCatalog.repository.allAssets(limit: Self.assetPageSize)
            let count = try backgroundCatalog.repository.assetCount()
            return AppImportOutput(result: result, assets: assets, totalAssetCount: count)
        }
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

    private static func defaultSidebarSections() -> [SidebarSection] {
        [
            SidebarSection(title: "Library", rows: ["All Photographs", "Folders", "People"]),
            SidebarSection(title: "Work", rows: ["Recent", "Starred"])
        ]
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
