import Foundation

public enum WorkerProtocolEncoder {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ command: WorkerCommand) throws -> String {
        let envelope: WorkerCommandEnvelope

        switch command {
        case .generatePreview(let assetID, let level):
            envelope = WorkerCommandEnvelope(command: "generatePreview", assetID: assetID.rawValue, level: level.rawValue, provider: nil)
        case .syncMetadata(let assetID):
            envelope = WorkerCommandEnvelope(command: "syncMetadata", assetID: assetID.rawValue, level: nil, provider: nil)
        case .runEvaluation(let assetID, let provider):
            envelope = WorkerCommandEnvelope(command: "runEvaluation", assetID: assetID.rawValue, level: nil, provider: provider)
        case .pause:
            envelope = WorkerCommandEnvelope(command: "pause", assetID: nil, level: nil, provider: nil)
        case .resume:
            envelope = WorkerCommandEnvelope(command: "resume", assetID: nil, level: nil, provider: nil)
        case .cancelAll:
            envelope = WorkerCommandEnvelope(command: "cancelAll", assetID: nil, level: nil, provider: nil)
        }

        let data = try encoder.encode(envelope)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    public static func decode(_ line: String) throws -> WorkerCommand {
        let envelope = try decoder.decode(WorkerCommandEnvelope.self, from: Data(line.utf8))

        switch envelope.command {
        case "generatePreview":
            let assetID = try envelope.requiredAssetID()
            let level = try envelope.requiredPreviewLevel()
            return .generatePreview(assetID: assetID, level: level)
        case "syncMetadata":
            return .syncMetadata(assetID: try envelope.requiredAssetID())
        case "runEvaluation":
            let assetID = try envelope.requiredAssetID()
            let provider = try envelope.requiredProvider()
            return .runEvaluation(assetID: assetID, provider: provider)
        case "pause":
            return .pause
        case "resume":
            return .resume
        case "cancelAll":
            return .cancelAll
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unknown worker command: \(envelope.command)"
                )
            )
        }
    }

    private struct WorkerCommandEnvelope: Codable {
        var command: String
        var assetID: String?
        var level: String?
        var provider: String?

        func requiredAssetID() throws -> AssetID {
            AssetID(rawValue: try requiredField(assetID, key: .assetID))
        }

        func requiredPreviewLevel() throws -> PreviewLevel {
            let rawValue = try requiredField(level, key: .level)
            guard let level = PreviewLevel(rawValue: rawValue) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.level],
                        debugDescription: "Unknown preview level: \(rawValue)"
                    )
                )
            }
            return level
        }

        func requiredProvider() throws -> String {
            try requiredField(provider, key: .provider)
        }

        private func requiredField(_ value: String?, key: CodingKeys) throws -> String {
            guard let value else {
                throw DecodingError.keyNotFound(
                    key,
                    DecodingError.Context(codingPath: [key], debugDescription: "Missing required field: \(key.stringValue)")
                )
            }
            return value
        }
    }
}
