public struct CatalogSourceRoot: Equatable, Sendable {
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
