import Foundation

public struct PreviewCacheKey: Hashable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel

    public init(assetID: AssetID, level: PreviewLevel) {
        self.assetID = assetID
        self.level = level
    }
}

public struct PreviewCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for key: PreviewCacheKey) -> URL {
        let assetDirectoryName = PathSafeName.encode(key.assetID.rawValue)

        return root
            .appendingPathComponent(assetDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.physicalFile(for: key.level))
    }

    public static func physicalFile(for level: PreviewLevel) -> String {
        switch level {
        case .micro, .grid:   return "grid.heic"
        case .medium, .large: return "large.heic"
        case .original:       return "full.heic"
        }
    }

    /// Returns all logical levels served by the same physical files as the
    /// requested levels. Micro and grid share one file; medium and large
    /// share another; original is standalone.
    public static func allLevelsServedBy(_ levels: [PreviewLevel]) -> [PreviewLevel] {
        var result = Set<PreviewLevel>()
        for level in levels {
            switch level {
            case .micro, .grid:
                result.insert(.micro)
                result.insert(.grid)
            case .medium, .large:
                result.insert(.medium)
                result.insert(.large)
            case .original:
                result.insert(.original)
            }
        }
        return PreviewLevel.allCases.filter { result.contains($0) }
    }

    /// Deletes every cached preview level for an asset (its whole per-asset
    /// directory). Used when an asset's catalog row is removed — e.g. moving
    /// a reject to the Trash — so a stale preview never outlives its row. A
    /// no-op when nothing is cached.
    public func deleteAll(for assetID: AssetID) throws {
        let directory = root.appendingPathComponent(PathSafeName.encode(assetID.rawValue), isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
