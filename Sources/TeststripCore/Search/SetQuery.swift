import Foundation

public struct GeoBounds: Codable, Equatable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }
}

public struct SetQuery: Codable, Equatable, Sendable {
    public enum Predicate: Codable, Equatable, Sendable {
        case text(String)
        case ratingAtLeast(Int)
        case flag(PickFlag)
        case colorLabel(ColorLabel)
        case keyword(String)
        case person(String)
        case missingKeywords
        case availability(SourceAvailability)
        case folderPrefix(String)
        case camera(String)
        case lens(String)
        case isoAtLeast(Int)
        case capturedAtOrAfter(Date)
        case capturedBefore(Date)
        case withinGeoBounds(GeoBounds)
        case evaluationKind(EvaluationKind)
        case unevaluated
        case likelyIssue
        case likelyPick
        case evaluationFailure
        case metadataSyncPending
        case metadataSyncConflict
        case importBatch(String)
        case workSession(String)
        /// Membership in one saved set's STATIC membership (`.manual` /
        /// `.snapshot`). A `.dynamic` set's membership is its own query and
        /// reaches SQL that way instead, so it matches nothing here.
        case assetSet(AssetSetID)
        /// Membership in an explicit runtime scope that has no saved set.
        case assetIDs([AssetID])
    }

    public var predicates: [Predicate]

    public init(predicates: [Predicate]) {
        self.predicates = predicates
    }
}
