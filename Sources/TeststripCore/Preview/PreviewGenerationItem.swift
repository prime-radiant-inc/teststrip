public struct PreviewGenerationItem: Equatable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel

    public init(assetID: AssetID, level: PreviewLevel) {
        self.assetID = assetID
        self.level = level
    }
}
