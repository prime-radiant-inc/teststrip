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
            .appendingPathComponent("\(key.level.rawValue).jpg")
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
