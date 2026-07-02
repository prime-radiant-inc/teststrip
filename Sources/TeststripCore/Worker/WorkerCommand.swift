import Foundation

public enum WorkerControlKind: String, Codable, Equatable, Sendable {
    case pause
    case resume
    case cancelAll
}

public enum WorkerCommand: Equatable, Sendable {
    case importFolder(root: URL)
    case importCard(source: URL, destinationRoot: URL)
    case generatePreview(assetID: AssetID, level: PreviewLevel)
    case syncMetadata(assetID: AssetID)
    case runEvaluation(assetID: AssetID, provider: String)
    case pause
    case resume
    case cancelAll

    public var controlKind: WorkerControlKind? {
        switch self {
        case .pause: return .pause
        case .resume: return .resume
        case .cancelAll: return .cancelAll
        case .importFolder, .importCard, .generatePreview, .syncMetadata, .runEvaluation: return nil
        }
    }
}
