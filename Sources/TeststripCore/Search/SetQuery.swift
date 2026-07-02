public struct SetQuery: Codable, Equatable, Sendable {
    public enum Predicate: Codable, Equatable, Sendable {
        case text(String)
        case ratingAtLeast(Int)
        case flag(PickFlag)
        case colorLabel(ColorLabel)
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
