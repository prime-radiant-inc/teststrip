import Foundation

public protocol StableID: Hashable, Codable, Sendable {
    var rawValue: String { get }
    init(rawValue: String)
}

public extension StableID {
    static func new() -> Self {
        Self(rawValue: UUID().uuidString)
    }
}
