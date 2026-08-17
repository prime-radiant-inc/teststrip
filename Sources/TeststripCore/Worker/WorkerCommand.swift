import Foundation

public enum WorkerControlKind: String, Codable, Equatable, Sendable {
    case pause
    case resume
    case cancelAll
}

public enum WorkerCommand: Equatable, Sendable {
    case importFolder(root: URL, duplicateHandling: DuplicateHandling)
    case importCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy,
        secondCopyDestination: URL?,
        duplicateHandling: DuplicateHandling
    )
    case generatePreview(assetID: AssetID, level: PreviewLevel)
    case syncMetadata(assetID: AssetID)
    case refreshAvailability(assetID: AssetID)
    case refreshAvailabilityBatch(assetIDs: [AssetID])
    case runEvaluation(assetID: AssetID, provider: String)
    case reverseGeocodeBatch(limit: Int)
    case backfillCoordinates(assetIDs: [AssetID])
    case pause
    case resume
    case cancelAll

    public var controlKind: WorkerControlKind? {
        switch self {
        case .pause: return .pause
        case .resume: return .resume
        case .cancelAll: return .cancelAll
        case .importFolder, .importCard, .generatePreview, .syncMetadata, .refreshAvailability, .refreshAvailabilityBatch, .runEvaluation, .reverseGeocodeBatch, .backfillCoordinates: return nil
        }
    }

    /// Per-command silence watchdog: how long without a progress event before
    /// the supervisor declares the command timed out. Import commands copy
    /// large files (RAW, video) from slow sources (SD cards, network); a
    /// single file can take minutes. Other commands are per-asset and should
    /// complete in well under 2 minutes.
    public var silenceTimeout: TimeInterval {
        switch self {
        case .importFolder, .importCard:
            return 600
        default:
            return 120
        }
    }

    public var operationDescription: String {
        switch self {
        case .importFolder(let root, _):
            return "import folder \(root.lastPathComponent)"
        case .importCard(let source, let destinationRoot, _, _, _):
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
        case .backfillCoordinates(let assetIDs):
            return "backfill coordinates for \(assetIDs.count) photos"
        case .pause:
            return "pause worker"
        case .resume:
            return "resume worker"
        case .cancelAll:
            return "cancel worker work"
        }
    }
}
