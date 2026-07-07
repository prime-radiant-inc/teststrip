import Foundation

public enum WorkerControlKind: String, Codable, Equatable, Sendable {
    case pause
    case resume
    case cancelAll
}

public enum WorkerCommand: Equatable, Sendable {
    case importFolder(root: URL)
    case importCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy,
        secondCopyDestination: URL?
    )
    case generatePreview(assetID: AssetID, level: PreviewLevel)
    case syncMetadata(assetID: AssetID)
    case refreshAvailability(assetID: AssetID)
    case refreshAvailabilityBatch(assetIDs: [AssetID])
    case runEvaluation(assetID: AssetID, provider: String)
    case reverseGeocodeBatch(limit: Int)
    case pause
    case resume
    case cancelAll

    public var controlKind: WorkerControlKind? {
        switch self {
        case .pause: return .pause
        case .resume: return .resume
        case .cancelAll: return .cancelAll
        case .importFolder, .importCard, .generatePreview, .syncMetadata, .refreshAvailability, .refreshAvailabilityBatch, .runEvaluation, .reverseGeocodeBatch: return nil
        }
    }

    public var operationDescription: String {
        switch self {
        case .importFolder(let root):
            return "import folder \(root.lastPathComponent)"
        case .importCard(let source, let destinationRoot, _, _):
            return "import card \(source.lastPathComponent) to \(destinationRoot.lastPathComponent)"
        case .generatePreview(let assetID, let level):
            return "generate \(level.rawValue) preview for \(assetID.rawValue)"
        case .syncMetadata(let assetID):
            return "sync metadata for \(assetID.rawValue)"
        case .refreshAvailability(let assetID):
            return "refresh source for \(assetID.rawValue)"
        case .refreshAvailabilityBatch(let assetIDs):
            return "refresh \(assetIDs.count) sources"
        case .runEvaluation(let assetID, let provider):
            return "run \(provider) evaluation for \(assetID.rawValue)"
        case .reverseGeocodeBatch(let limit):
            return "reverse-geocode up to \(limit) locations"
        case .pause:
            return "pause worker"
        case .resume:
            return "resume worker"
        case .cancelAll:
            return "cancel worker work"
        }
    }
}
