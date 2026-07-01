public struct SetQuery: Codable, Equatable, Sendable {
    public enum Predicate: Codable, Equatable, Sendable {
        case ratingAtLeast(Int)
        case keyword(String)
        case availability(SourceAvailability)
        case folderPrefix(String)
        case importBatch(String)
    }

    public var predicates: [Predicate]

    public init(predicates: [Predicate]) {
        self.predicates = predicates
    }
}
