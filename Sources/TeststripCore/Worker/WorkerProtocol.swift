import Foundation

public struct WorkerCommandRequest: Equatable, Sendable {
    public var command: WorkerCommand
    public var itemID: WorkSessionID?

    public init(command: WorkerCommand, itemID: WorkSessionID? = nil) {
        self.command = command
        self.itemID = itemID
    }
}

public enum WorkerEvent: Equatable, Sendable {
    case accepted(itemID: WorkSessionID?, message: String)
    case completed(itemID: WorkSessionID?, message: String)
    case failed(itemID: WorkSessionID?, message: String)

    public var itemID: WorkSessionID? {
        switch self {
        case .accepted(let itemID, _), .completed(let itemID, _), .failed(let itemID, _):
            return itemID
        }
    }

    public var message: String {
        switch self {
        case .accepted(_, let message), .completed(_, let message), .failed(_, let message):
            return message
        }
    }
}

public enum WorkerProtocolEncoder {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ command: WorkerCommand, itemID: WorkSessionID? = nil) throws -> String {
        let envelope: WorkerCommandEnvelope

        switch command {
        case .generatePreview(let assetID, let level):
            envelope = WorkerCommandEnvelope(
                command: "generatePreview",
                assetID: assetID.rawValue,
                level: level.rawValue,
                provider: nil,
                itemID: itemID?.rawValue
            )
        case .syncMetadata(let assetID):
            envelope = WorkerCommandEnvelope(
                command: "syncMetadata",
                assetID: assetID.rawValue,
                level: nil,
                provider: nil,
                itemID: itemID?.rawValue
            )
        case .runEvaluation(let assetID, let provider):
            envelope = WorkerCommandEnvelope(
                command: "runEvaluation",
                assetID: assetID.rawValue,
                level: nil,
                provider: provider,
                itemID: itemID?.rawValue
            )
        case .pause:
            envelope = WorkerCommandEnvelope(command: "pause", assetID: nil, level: nil, provider: nil, itemID: itemID?.rawValue)
        case .resume:
            envelope = WorkerCommandEnvelope(command: "resume", assetID: nil, level: nil, provider: nil, itemID: itemID?.rawValue)
        case .cancelAll:
            envelope = WorkerCommandEnvelope(command: "cancelAll", assetID: nil, level: nil, provider: nil, itemID: itemID?.rawValue)
        }

        let data = try encoder.encode(envelope)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    public static func encode(_ event: WorkerEvent) throws -> String {
        let envelope: WorkerEventEnvelope
        switch event {
        case .accepted(let itemID, let message):
            envelope = WorkerEventEnvelope(event: "accepted", itemID: itemID?.rawValue, message: message)
        case .completed(let itemID, let message):
            envelope = WorkerEventEnvelope(event: "completed", itemID: itemID?.rawValue, message: message)
        case .failed(let itemID, let message):
            envelope = WorkerEventEnvelope(event: "failed", itemID: itemID?.rawValue, message: message)
        }

        let data = try encoder.encode(envelope)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    public static func decode(_ line: String) throws -> WorkerCommand {
        try decodeRequest(line).command
    }

    public static func decodeRequest(_ line: String) throws -> WorkerCommandRequest {
        let envelope = try decoder.decode(WorkerCommandEnvelope.self, from: Data(line.utf8))
        let itemID = envelope.itemID.map(WorkSessionID.init(rawValue:))
        let command: WorkerCommand

        switch envelope.command {
        case "generatePreview":
            let assetID = try envelope.requiredAssetID()
            let level = try envelope.requiredPreviewLevel()
            command = .generatePreview(assetID: assetID, level: level)
        case "syncMetadata":
            command = .syncMetadata(assetID: try envelope.requiredAssetID())
        case "runEvaluation":
            let assetID = try envelope.requiredAssetID()
            let provider = try envelope.requiredProvider()
            command = .runEvaluation(assetID: assetID, provider: provider)
        case "pause":
            command = .pause
        case "resume":
            command = .resume
        case "cancelAll":
            command = .cancelAll
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unknown worker command: \(envelope.command)"
                )
            )
        }

        return WorkerCommandRequest(command: command, itemID: itemID)
    }

    public static func decodeEvent(_ line: String) throws -> WorkerEvent {
        let envelope = try decoder.decode(WorkerEventEnvelope.self, from: Data(line.utf8))
        let itemID = envelope.itemID.map(WorkSessionID.init(rawValue:))

        switch envelope.event {
        case "accepted":
            return .accepted(itemID: itemID, message: envelope.message)
        case "completed":
            return .completed(itemID: itemID, message: envelope.message)
        case "failed":
            return .failed(itemID: itemID, message: envelope.message)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unknown worker event: \(envelope.event)"
                )
            )
        }
    }

    private struct WorkerCommandEnvelope: Codable {
        var command: String
        var assetID: String?
        var level: String?
        var provider: String?
        var itemID: String?

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

    private struct WorkerEventEnvelope: Codable {
        var event: String
        var itemID: String?
        var message: String
    }
}
