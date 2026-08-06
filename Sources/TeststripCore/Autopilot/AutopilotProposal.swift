import Foundation

public struct AutopilotRunID: StableID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct AutopilotProposalID: StableID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum AutopilotProposalKind: String, Codable, Hashable, Sendable {
    case pick
    case reject
    case keyword
}

/// One run's working proposal, in memory only. Produced by
/// `AutopilotProposalPlanner` and consumed by the run that applies it as a
/// tentative AI label; nothing persists it. The durable record of "the machine
/// proposed a flag" is the ghost in `metadata_json` (`AutopilotGhost`).
public struct AutopilotProposal: Codable, Equatable, Sendable {
    public var id: AutopilotProposalID
    public var runID: AutopilotRunID
    public var assetID: AssetID
    public var kind: AutopilotProposalKind
    public var keyword: String?
    public var rationale: String
    public var confidence: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: AutopilotProposalID,
        runID: AutopilotRunID,
        assetID: AssetID,
        kind: AutopilotProposalKind,
        keyword: String?,
        rationale: String,
        confidence: Double,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.runID = runID
        self.assetID = assetID
        self.kind = kind
        self.keyword = keyword
        self.rationale = rationale
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
