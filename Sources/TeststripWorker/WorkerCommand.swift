import Foundation
import TeststripCore

public enum WorkerControlKind: String, Codable, Equatable, Sendable {
    case pause
    case cancelAll
}

public enum WorkerCommand: Codable, Equatable, Sendable {
    case generatePreview(assetID: AssetID, level: PreviewLevel)
    case syncMetadata(assetID: AssetID)
    case runEvaluation(assetID: AssetID, provider: String)
    case pause
    case cancelAll

    public var controlKind: WorkerControlKind? {
        switch self {
        case .pause: return .pause
        case .cancelAll: return .cancelAll
        case .generatePreview, .syncMetadata, .runEvaluation: return nil
        }
    }
}
