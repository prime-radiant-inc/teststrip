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
}

@Observable
public final class AppModel {
    public var sidebarSections: [SidebarSection]
    public var selectedView: LibraryViewMode
    public var assets: [Asset]
    public var selectedAssetID: AssetID?

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public init(sidebarSections: [SidebarSection], selectedView: LibraryViewMode, assets: [Asset]) {
        self.sidebarSections = sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.selectedAssetID = assets.first?.id
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
            sidebarSections: [
                SidebarSection(title: "Library", rows: ["All Photographs", "Folders", "People", "Places"]),
                SidebarSection(title: "Work", rows: ["Recent", "Starred"])
            ],
            selectedView: .grid,
            assets: [asset]
        )
    }

    public static func load(repository: CatalogRepository) throws -> AppModel {
        AppModel(
            sidebarSections: [
                SidebarSection(title: "Library", rows: ["All Photographs", "Folders", "People", "Places"]),
                SidebarSection(title: "Work", rows: ["Recent", "Starred"])
            ],
            selectedView: .grid,
            assets: try repository.allAssets(limit: 500)
        )
    }

    public func select(_ assetID: AssetID) {
        selectedAssetID = assetID
    }
}
