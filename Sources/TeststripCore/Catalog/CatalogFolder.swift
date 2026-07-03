public struct CatalogFolder: Equatable, Sendable {
    public var path: String
    public var name: String
    public var assetCount: Int

    public init(path: String, name: String, assetCount: Int) {
        self.path = path
        self.name = name
        self.assetCount = assetCount
    }
}
