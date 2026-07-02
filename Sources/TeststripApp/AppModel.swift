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
    public var id: UUID
    public var kind: WorkSessionKind
    public var status: WorkSessionStatus
    public var title: String
    public var detail: String
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var failureCount: Int

    public init(
        id: UUID = UUID(),
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

public typealias AppImportTaskFactory = @Sendable (AppCatalogPaths, URL) -> Task<AppImportOutput, Error>

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

    @ObservationIgnored
    private var catalog: AppCatalog?

    @ObservationIgnored
    private let importTaskFactory: AppImportTaskFactory

    @ObservationIgnored
    private var activeImportTask: Task<AppImportOutput, Error>?

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
        self.catalog = catalog
        self.importTaskFactory = importTaskFactory ?? Self.defaultImportTask
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

    public static func load(catalog: AppCatalog, importTaskFactory: AppImportTaskFactory? = nil) throws -> AppModel {
        let assets = try catalog.repository.allAssets(limit: Self.assetPageSize)
        return AppModel(
            sidebarSections: defaultSidebarSections(),
            selectedView: .grid,
            assets: assets,
            totalAssetCount: try catalog.repository.assetCount(),
            catalog: catalog,
            importTaskFactory: importTaskFactory
        )
    }

    public func select(_ assetID: AssetID) {
        selectedAssetID = assetID
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

    private func updateSelectedAssetMetadata(_ update: (inout AssetMetadata) throws -> Void) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard let selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        try catalog.repository.updateMetadata(assetID: selectedAssetID, update)
        let updatedAsset = try catalog.repository.asset(id: selectedAssetID)
        guard let index = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return
        }
        assets[index] = updatedAsset
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
        let paths = catalog.paths
        do {
            let output = try await importTaskFactory(paths, folderURL).value
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
        let task = importTaskFactory(catalog.paths, folderURL)
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

    private func completeImportActivity(folderURL: URL, result: LibraryImportResult) {
        let photoLabel = result.importedAssets.count == 1 ? "photo" : "photos"
        let activity = AppWorkActivity(
            id: activeWork?.id ?? UUID(),
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
            id: activeWork?.id ?? UUID(),
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
            id: activeWork?.id ?? UUID(),
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

    private static func defaultImportTask(paths: AppCatalogPaths, folderURL: URL) -> Task<AppImportOutput, Error> {
        Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.addFolderInPlace(folderURL, repository: backgroundCatalog.repository)
            try Task.checkCancellation()
            let assets = try backgroundCatalog.repository.allAssets(limit: Self.assetPageSize)
            let count = try backgroundCatalog.repository.assetCount()
            return AppImportOutput(result: result, assets: assets, totalAssetCount: count)
        }
    }

    public func gridPreviewURL(for assetID: AssetID) -> URL? {
        guard let catalog else { return nil }
        let url = catalog.previewCache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func defaultSidebarSections() -> [SidebarSection] {
        [
            SidebarSection(title: "Library", rows: ["All Photographs", "Folders", "People"]),
            SidebarSection(title: "Work", rows: ["Recent", "Starred"])
        ]
    }
}
