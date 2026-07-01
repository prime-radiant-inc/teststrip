import Foundation

public struct PreviewCacheKey: Hashable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel
}

public struct PreviewCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for key: PreviewCacheKey) -> URL {
        root
            .appendingPathComponent(key.assetID.rawValue, isDirectory: true)
            .appendingPathComponent("\(key.level.rawValue).jpg")
    }
}
