import Foundation

public struct WorkSessionID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum WorkSessionKind: String, Codable, Hashable, Sendable {
    case ingest
    case previewGeneration
    case recognition
    case culling
    case collecting
    case searchSort
    case keywording
    case xmpSync
    case sourceScan
    case export
    case geocoding
}

public enum WorkSessionStatus: String, Codable, Hashable, Sendable {
    case queued
    case running
    case paused
    case completed
    case failed
    case cancelled
}

public struct WorkSessionIssue: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case skippedSourceFile
    }

    public var kind: Kind
    public var sourceURL: URL?
    public var message: String

    public init(kind: Kind, sourceURL: URL? = nil, message: String) {
        self.kind = kind
        self.sourceURL = sourceURL
        self.message = message
    }
}

public struct WorkSession: Codable, Equatable, Sendable {
    public var id: WorkSessionID
    public var kind: WorkSessionKind
    public var intent: String
    public var title: String
    public var detail: String
    public var status: WorkSessionStatus
    public var inputSetIDs: [AssetSetID]
    public var outputSetIDs: [AssetSetID]
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var failureCount: Int
    public var issues: [WorkSessionIssue]
    public var starred: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: WorkSessionID,
        kind: WorkSessionKind,
        intent: String,
        title: String = "",
        detail: String = "",
        status: WorkSessionStatus,
        inputSetIDs: [AssetSetID],
        outputSetIDs: [AssetSetID],
        completedUnitCount: Int = 0,
        totalUnitCount: Int? = nil,
        failureCount: Int = 0,
        issues: [WorkSessionIssue] = [],
        starred: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.title = title
        self.detail = detail
        self.status = status
        self.inputSetIDs = inputSetIDs
        self.outputSetIDs = outputSetIDs
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.failureCount = failureCount
        self.issues = issues
        self.starred = starred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
