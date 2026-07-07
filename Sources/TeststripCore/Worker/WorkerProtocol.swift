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
    case progress(itemID: WorkSessionID?, completedUnitCount: Int, totalUnitCount: Int?, detail: String, catalogedAssetIDs: [AssetID])
    case completed(itemID: WorkSessionID?, message: String)
    case completedImport(
        itemID: WorkSessionID?,
        message: String,
        importedAssetIDs: [AssetID],
        newAssetCount: Int,
        existingAssetCount: Int,
        skippedSourceFileCount: Int,
        skippedSourceFiles: [LibrarySkippedSourceFile]
    )
    case failed(itemID: WorkSessionID?, message: String)

    public var itemID: WorkSessionID? {
        switch self {
        case .accepted(let itemID, _),
             .progress(let itemID, _, _, _, _),
             .completed(let itemID, _),
             .completedImport(let itemID, _, _, _, _, _, _),
             .failed(let itemID, _):
            return itemID
        }
    }

    public var message: String {
        switch self {
        case .accepted(_, let message),
             .progress(_, _, _, let message, _),
             .completed(_, let message),
             .completedImport(_, let message, _, _, _, _, _),
             .failed(_, let message):
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
        case .importFolder(let root):
            envelope = WorkerCommandEnvelope(
                command: "importFolder",
                assetID: nil,
                level: nil,
                provider: nil,
                rootURL: root.path,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue
            )
        case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination):
            envelope = WorkerCommandEnvelope(
                command: "importCard",
                assetID: nil,
                level: nil,
                provider: nil,
                rootURL: nil,
                sourceURL: source.path,
                destinationRootURL: destinationRoot.path,
                itemID: itemID?.rawValue,
                destinationPolicy: destinationPolicy.rawValue,
                secondCopyDestinationRootURL: secondCopyDestination?.path
            )
        case .generatePreview(let assetID, let level):
            envelope = WorkerCommandEnvelope(
                command: "generatePreview",
                assetID: assetID.rawValue,
                level: level.rawValue,
                provider: nil,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue
            )
        case .syncMetadata(let assetID):
            envelope = WorkerCommandEnvelope(
                command: "syncMetadata",
                assetID: assetID.rawValue,
                level: nil,
                provider: nil,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue
            )
        case .refreshAvailability(let assetID):
            envelope = WorkerCommandEnvelope(
                command: "refreshAvailability",
                assetID: assetID.rawValue,
                level: nil,
                provider: nil,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue
            )
        case .refreshAvailabilityBatch(let assetIDs):
            envelope = WorkerCommandEnvelope(
                command: "refreshAvailabilityBatch",
                assetID: nil,
                level: nil,
                provider: nil,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue,
                assetIDs: assetIDs.map(\.rawValue)
            )
        case .runEvaluation(let assetID, let provider):
            envelope = WorkerCommandEnvelope(
                command: "runEvaluation",
                assetID: assetID.rawValue,
                level: nil,
                provider: provider,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue
            )
        case .reverseGeocodeBatch(let limit):
            envelope = WorkerCommandEnvelope(
                command: "reverseGeocodeBatch",
                assetID: nil,
                level: nil,
                provider: nil,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue,
                limit: limit
            )
        case .backfillCoordinates(let assetIDs):
            envelope = WorkerCommandEnvelope(
                command: "backfillCoordinates",
                assetID: nil,
                level: nil,
                provider: nil,
                rootURL: nil,
                sourceURL: nil,
                destinationRootURL: nil,
                itemID: itemID?.rawValue,
                assetIDs: assetIDs.map(\.rawValue)
            )
        case .pause:
            envelope = WorkerCommandEnvelope(command: "pause", assetID: nil, level: nil, provider: nil, rootURL: nil, sourceURL: nil, destinationRootURL: nil, itemID: itemID?.rawValue)
        case .resume:
            envelope = WorkerCommandEnvelope(command: "resume", assetID: nil, level: nil, provider: nil, rootURL: nil, sourceURL: nil, destinationRootURL: nil, itemID: itemID?.rawValue)
        case .cancelAll:
            envelope = WorkerCommandEnvelope(command: "cancelAll", assetID: nil, level: nil, provider: nil, rootURL: nil, sourceURL: nil, destinationRootURL: nil, itemID: itemID?.rawValue)
        }

        let data = try encoder.encode(envelope)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    public static func encode(_ event: WorkerEvent) throws -> String {
        let envelope: WorkerEventEnvelope
        switch event {
        case .accepted(let itemID, let message):
            envelope = WorkerEventEnvelope(
                event: "accepted",
                itemID: itemID?.rawValue,
                message: message,
                importedAssetIDs: nil,
                catalogedAssetIDs: nil,
                completedUnitCount: nil,
                totalUnitCount: nil
            )
        case .progress(let itemID, let completedUnitCount, let totalUnitCount, let detail, let catalogedAssetIDs):
            envelope = WorkerEventEnvelope(
                event: "progress",
                itemID: itemID?.rawValue,
                message: detail,
                importedAssetIDs: nil,
                catalogedAssetIDs: catalogedAssetIDs.map(\.rawValue),
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount
            )
        case .completed(let itemID, let message):
            envelope = WorkerEventEnvelope(
                event: "completed",
                itemID: itemID?.rawValue,
                message: message,
                importedAssetIDs: nil,
                catalogedAssetIDs: nil,
                completedUnitCount: nil,
                totalUnitCount: nil
            )
        case .completedImport(
            let itemID,
            let message,
            let importedAssetIDs,
            let newAssetCount,
            let existingAssetCount,
            let skippedSourceFileCount,
            let skippedSourceFiles
        ):
            envelope = WorkerEventEnvelope(
                event: "completed",
                itemID: itemID?.rawValue,
                message: message,
                importedAssetIDs: importedAssetIDs.map(\.rawValue),
                catalogedAssetIDs: nil,
                completedUnitCount: nil,
                totalUnitCount: nil,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount,
                skippedSourceFileCount: skippedSourceFileCount,
                skippedSourceFiles: skippedSourceFiles
            )
        case .failed(let itemID, let message):
            envelope = WorkerEventEnvelope(
                event: "failed",
                itemID: itemID?.rawValue,
                message: message,
                importedAssetIDs: nil,
                catalogedAssetIDs: nil,
                completedUnitCount: nil,
                totalUnitCount: nil
            )
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
        case "importFolder":
            command = .importFolder(root: try envelope.requiredRootURL())
        case "importCard":
            command = .importCard(
                source: try envelope.requiredSourceURL(),
                destinationRoot: try envelope.requiredDestinationRootURL(),
                destinationPolicy: try envelope.importDestinationPolicy(),
                secondCopyDestination: envelope.secondCopyDestinationURL()
            )
        case "generatePreview":
            let assetID = try envelope.requiredAssetID()
            let level = try envelope.requiredPreviewLevel()
            command = .generatePreview(assetID: assetID, level: level)
        case "syncMetadata":
            command = .syncMetadata(assetID: try envelope.requiredAssetID())
        case "refreshAvailability":
            command = .refreshAvailability(assetID: try envelope.requiredAssetID())
        case "refreshAvailabilityBatch":
            command = .refreshAvailabilityBatch(assetIDs: try envelope.requiredAssetIDs())
        case "runEvaluation":
            let assetID = try envelope.requiredAssetID()
            let provider = try envelope.requiredProvider()
            command = .runEvaluation(assetID: assetID, provider: provider)
        case "reverseGeocodeBatch":
            command = .reverseGeocodeBatch(limit: try envelope.requiredLimit())
        case "backfillCoordinates":
            command = .backfillCoordinates(assetIDs: try envelope.requiredAssetIDs())
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
        case "progress":
            return .progress(
                itemID: itemID,
                completedUnitCount: try envelope.requiredCompletedUnitCount(),
                totalUnitCount: envelope.totalUnitCount,
                detail: envelope.message,
                catalogedAssetIDs: try envelope.requiredCatalogedAssetIDs()
            )
        case "completed":
            if let importedAssetIDs = envelope.importedAssetIDs {
                return .completedImport(
                    itemID: itemID,
                    message: envelope.message,
                    importedAssetIDs: importedAssetIDs.map(AssetID.init(rawValue:)),
                    newAssetCount: try envelope.requiredNewAssetCount(),
                    existingAssetCount: try envelope.requiredExistingAssetCount(),
                    skippedSourceFileCount: try envelope.requiredSkippedSourceFileCount(),
                    skippedSourceFiles: envelope.skippedSourceFiles ?? []
                )
            }
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
        var rootURL: String?
        var sourceURL: String?
        var destinationRootURL: String?
        var itemID: String?
        var destinationPolicy: String? = nil
        var secondCopyDestinationRootURL: String? = nil
        var assetIDs: [String]? = nil
        var limit: Int? = nil

        func requiredAssetID() throws -> AssetID {
            AssetID(rawValue: try requiredField(assetID, key: .assetID))
        }

        func requiredAssetIDs() throws -> [AssetID] {
            try requiredField(assetIDs, key: .assetIDs).map(AssetID.init(rawValue:))
        }

        func requiredLimit() throws -> Int {
            guard let limit else {
                throw DecodingError.keyNotFound(
                    CodingKeys.limit,
                    DecodingError.Context(codingPath: [CodingKeys.limit], debugDescription: "Missing required field: limit")
                )
            }
            return limit
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

        func requiredRootURL() throws -> URL {
            URL(fileURLWithPath: try requiredField(rootURL, key: .rootURL), isDirectory: true)
        }

        func requiredSourceURL() throws -> URL {
            URL(fileURLWithPath: try requiredField(sourceURL, key: .sourceURL), isDirectory: true)
        }

        func requiredDestinationRootURL() throws -> URL {
            URL(fileURLWithPath: try requiredField(destinationRootURL, key: .destinationRootURL), isDirectory: true)
        }

        func importDestinationPolicy() throws -> ImportDestinationPolicy {
            guard let destinationPolicy else {
                return .flat
            }
            guard let policy = ImportDestinationPolicy(rawValue: destinationPolicy) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.destinationPolicy],
                        debugDescription: "Unknown destination policy: \(destinationPolicy)"
                    )
                )
            }
            return policy
        }

        func secondCopyDestinationURL() -> URL? {
            secondCopyDestinationRootURL.map { URL(fileURLWithPath: $0, isDirectory: true) }
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

        private func requiredField(_ value: [String]?, key: CodingKeys) throws -> [String] {
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
        var importedAssetIDs: [String]?
        var catalogedAssetIDs: [String]?
        var completedUnitCount: Int?
        var totalUnitCount: Int?
        var newAssetCount: Int? = nil
        var existingAssetCount: Int? = nil
        var skippedSourceFileCount: Int? = nil
        var skippedSourceFiles: [LibrarySkippedSourceFile]? = nil

        func requiredCompletedUnitCount() throws -> Int {
            guard let completedUnitCount else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.completedUnitCount],
                        debugDescription: "Missing completedUnitCount"
                    )
                )
            }
            return completedUnitCount
        }

        func requiredCatalogedAssetIDs() throws -> [AssetID] {
            guard let catalogedAssetIDs else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.catalogedAssetIDs],
                        debugDescription: "Missing catalogedAssetIDs"
                    )
                )
            }
            return catalogedAssetIDs.map(AssetID.init(rawValue:))
        }

        func requiredNewAssetCount() throws -> Int {
            guard let newAssetCount else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.newAssetCount],
                        debugDescription: "Missing newAssetCount"
                    )
                )
            }
            return newAssetCount
        }

        func requiredExistingAssetCount() throws -> Int {
            guard let existingAssetCount else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.existingAssetCount],
                        debugDescription: "Missing existingAssetCount"
                    )
                )
            }
            return existingAssetCount
        }

        func requiredSkippedSourceFileCount() throws -> Int {
            guard let skippedSourceFileCount else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.skippedSourceFileCount],
                        debugDescription: "Missing skippedSourceFileCount"
                    )
                )
            }
            return skippedSourceFileCount
        }
    }
}
