import Foundation

public struct SetQuery: Codable, Equatable, Sendable {
    public enum Predicate: Codable, Equatable, Sendable {
        case text(String)
        case ratingAtLeast(Int)
        case flag(PickFlag)
        case colorLabel(ColorLabel)
        case keyword(String)
        case availability(SourceAvailability)
        case folderPrefix(String)
        case camera(String)
        case lens(String)
        case isoAtLeast(Int)
        case capturedAtOrAfter(Date)
        case capturedBefore(Date)
        case evaluationKind(EvaluationKind)
        case importBatch(String)
    }

    public var predicates: [Predicate]

    public init(predicates: [Predicate]) {
        self.predicates = predicates
    }
}
