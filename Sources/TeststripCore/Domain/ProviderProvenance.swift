public struct ProviderProvenance: Codable, Equatable, Sendable {
    public var provider: String
    public var model: String
    public var version: String
    public var settingsHash: String

    public init(provider: String, model: String, version: String, settingsHash: String) {
        self.provider = provider
        self.model = model
        self.version = version
        self.settingsHash = settingsHash
    }
}
