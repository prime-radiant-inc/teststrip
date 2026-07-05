import Foundation

public struct CatalogPerson: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var assetCount: Int

    public init(id: String, name: String, assetCount: Int) {
        self.id = id
        self.name = name
        self.assetCount = assetCount
    }
}
