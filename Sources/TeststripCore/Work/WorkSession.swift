import Foundation

public struct WorkSessionID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum WorkSessionKind: String, Codable, Sendable {
    case ingest
    case previewGeneration
    case recognition
    case culling
    case collecting
    case searchSort
    case keywording
    case xmpSync
    case export
}

public enum WorkSessionStatus: String, Codable, Sendable {
    case queued
    case running
    case paused
    case completed
    case failed
    case cancelled
}

public struct WorkSession: Codable, Equatable, Sendable {
    public var id: WorkSessionID
    public var kind: WorkSessionKind
    public var intent: String
    public var status: WorkSessionStatus
    public var inputSetIDs: [AssetSetID]
    public var outputSetIDs: [AssetSetID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: WorkSessionID,
        kind: WorkSessionKind,
        intent: String,
        status: WorkSessionStatus,
        inputSetIDs: [AssetSetID],
        outputSetIDs: [AssetSetID],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.status = status
        self.inputSetIDs = inputSetIDs
        self.outputSetIDs = outputSetIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
