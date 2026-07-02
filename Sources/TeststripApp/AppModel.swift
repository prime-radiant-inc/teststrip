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

public struct SidebarSection: Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var rows: [String]

    public init(title: String, rows: [String]) {
        self.title = title
        self.rows = rows
    }
}

@Observable
public final class AppModel {
    public var sidebarSections: [SidebarSection]
    public var selectedView: LibraryViewMode
    public var assets: [Asset]
    public var selectedAssetID: AssetID?
    public var statusMessage: String?
    public var errorMessage: String?

    @ObservationIgnored
    private var catalog: AppCatalog?

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public init(
        sidebarSections: [SidebarSection],
        selectedView: LibraryViewMode,
        assets: [Asset],
        catalog: AppCatalog? = nil,
        statusMessage: String? = nil,
        errorMessage: String? = nil
    ) {
        self.sidebarSections = sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.selectedAssetID = assets.first?.id
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.catalog = catalog
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
        AppModel(
            sidebarSections: defaultSidebarSections(),
            selectedView: .grid,
            assets: try repository.allAssets(limit: 500)
        )
    }

    public static func load(catalog: AppCatalog) throws -> AppModel {
        AppModel(
            sidebarSections: defaultSidebarSections(),
            selectedView: .grid,
            assets: try catalog.repository.allAssets(limit: 500),
            catalog: catalog
        )
    }

    public func select(_ assetID: AssetID) {
        selectedAssetID = assetID
    }

    public func reload() throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        replaceAssets(try catalog.repository.allAssets(limit: 500))
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
        let result = try catalog.importService.addFolderInPlace(folderURL, repository: catalog.repository)
        try reload()
        updateImportStatus(with: result)
        return result
    }

    @discardableResult
    @MainActor
    public func importFolderInBackground(_ folderURL: URL) async throws -> LibraryImportResult {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        errorMessage = nil
        statusMessage = "Importing \(folderURL.lastPathComponent)..."
        let paths = catalog.paths
        let output = try await Task.detached(priority: .userInitiated) {
            let backgroundCatalog = try AppCatalog.open(paths: paths)
            let result = try backgroundCatalog.importService.addFolderInPlace(folderURL, repository: backgroundCatalog.repository)
            let assets = try backgroundCatalog.repository.allAssets(limit: 500)
            return BackgroundImportOutput(result: result, assets: assets)
        }.value
        replaceAssets(output.assets)
        updateImportStatus(with: output.result)
        return output.result
    }

    private func updateImportStatus(with result: LibraryImportResult) {
        let photoLabel = result.importedAssets.count == 1 ? "photo" : "photos"
        statusMessage = "Imported \(result.importedAssets.count) \(photoLabel)"
        if !result.previewFailures.isEmpty {
            statusMessage?.append(" (\(result.previewFailures.count) preview failures)")
        }
    }

    private struct BackgroundImportOutput: Sendable {
        var result: LibraryImportResult
        var assets: [Asset]

        init(result: LibraryImportResult, assets: [Asset]) {
            self.result = result
            self.assets = assets
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
