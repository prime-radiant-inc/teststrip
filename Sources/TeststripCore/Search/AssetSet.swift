public struct AssetSetID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AssetSet: Codable, Equatable, Sendable {
    public enum Membership: Codable, Equatable, Sendable {
        case manual([AssetID])
        case dynamic(SetQuery)
        case snapshot([AssetID])
    }

    public var id: AssetSetID
    public var name: String
    public var membership: Membership
    public var starred: Bool

    public var isDynamic: Bool {
        if case .dynamic = membership { return true }
        return false
    }

    public static func manual(id: AssetSetID, name: String, assetIDs: [AssetID]) -> AssetSet {
        AssetSet(id: id, name: name, membership: .manual(assetIDs), starred: false)
    }

    public static func dynamic(id: AssetSetID, name: String, query: SetQuery) -> AssetSet {
        AssetSet(id: id, name: name, membership: .dynamic(query), starred: false)
    }
}
