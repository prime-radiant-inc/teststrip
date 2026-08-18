import Foundation

public enum WorkerControlKind: String, Codable, Equatable, Sendable {
    case pause
    case resume
    case cancelAll
}

public enum WorkerCommand: Equatable, Sendable {
    case importFolder(
        root: URL,
        duplicateHandling: DuplicateHandling,
        selectedFiles: Set<URL>?,
        preIngestThumbnails: URL?
    )
    case importCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy,
        secondCopyDestination: URL?,
        duplicateHandling: DuplicateHandling,
        selectedFiles: Set<URL>?,
        preIngestThumbnails: URL?
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
    /// the supervisor declares the command timed out. This is a stall detector,
    /// not a hard ceiling — the timer resets on every progress event (including
    /// scanner heartbeats emitted every 15 seconds), so a working command can
    /// run indefinitely as long as it keeps producing output. The watchdog
    /// fires only when the worker is truly frozen (zero output for the full
    /// window). Import commands scan directories that may contain millions of
    /// non-photo files; the scanner emits heartbeats every 15 seconds, so a
    /// generous 30-minute window catches genuine freezes without killing slow
    /// but active scans. Other commands are per-asset and should complete in
    /// well under 2 minutes.
    public var silenceTimeout: TimeInterval {
        switch self {
        case .importFolder, .importCard:
            return 1800
        default:
            return 120
        }
    }

    public var operationDescription: String {
        switch self {
        case .importFolder(let root, _, _, _):
            return "import folder \(root.lastPathComponent)"
        case .importCard(let source, let destinationRoot, _, _, _, _, _):
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
