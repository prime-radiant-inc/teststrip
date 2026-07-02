import Foundation

public enum WorkerCommandResult: Equatable, Sendable {
    case accepted(String)
    case completed(String)

    public var responseLine: String {
        switch self {
        case .accepted(let message):
            "accepted \(message)"
        case .completed(let message):
            "completed \(message)"
        }
    }
}

public struct WorkerRuntimeConfiguration: Equatable, Sendable {
    public var catalogURL: URL
    public var previewCacheRoot: URL

    public init(catalogURL: URL, previewCacheRoot: URL) {
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
    }

    public init(arguments: [String]) throws {
        var catalogPath: String?
        var previewCachePath: String?
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            let valueIndex = arguments.index(after: index)
            switch argument {
            case "--catalog":
                guard valueIndex < arguments.endIndex else {
                    throw TeststripError.invalidState("missing value for --catalog")
                }
                catalogPath = arguments[valueIndex]
                index = arguments.index(after: valueIndex)
            case "--preview-cache":
                guard valueIndex < arguments.endIndex else {
                    throw TeststripError.invalidState("missing value for --preview-cache")
                }
                previewCachePath = arguments[valueIndex]
                index = arguments.index(after: valueIndex)
            default:
                throw TeststripError.invalidState("unknown worker argument \(argument)")
            }
        }

        guard let catalogPath, let previewCachePath else {
            throw TeststripError.invalidState("worker requires --catalog and --preview-cache")
        }

        self.catalogURL = URL(fileURLWithPath: catalogPath)
        self.previewCacheRoot = URL(fileURLWithPath: previewCachePath, isDirectory: true)
    }
}

public struct WorkerCommandExecutor {
    private let repository: CatalogRepository
    private let previewCache: PreviewCache
    private let renderer: PreviewRenderer
    private let evaluationProviders: [String: any EvaluationProvider]

    public init(
        repository: CatalogRepository,
        previewCache: PreviewCache,
        renderer: PreviewRenderer = PreviewRenderer(),
        evaluationProviders: [any EvaluationProvider] = []
    ) {
        self.repository = repository
        self.previewCache = previewCache
        self.renderer = renderer
        var providersByName: [String: any EvaluationProvider] = [:]
        for provider in evaluationProviders {
            providersByName[provider.name] = provider
        }
        self.evaluationProviders = providersByName
    }

    public init(configuration: WorkerRuntimeConfiguration) throws {
        let database = try CatalogDatabase.open(at: configuration.catalogURL)
        try database.migrate()
        self.init(
            repository: CatalogRepository(database: database),
            previewCache: PreviewCache(root: configuration.previewCacheRoot),
            evaluationProviders: [LocalImageMetricsEvaluationProvider()]
        )
    }

    public func execute(_ command: WorkerCommand) throws -> WorkerCommandResult {
        switch command {
        case .generatePreview(let assetID, let level):
            let asset = try repository.asset(id: assetID)
            try renderer.render(
                sourceURL: asset.originalURL,
                level: level,
                destinationURL: previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            )
            return .completed("generated \(level.rawValue) preview for \(assetID.rawValue)")
        case .syncMetadata(let assetID):
            return try syncMetadata(assetID: assetID)
        case .runEvaluation(let assetID, let provider):
            return try runEvaluation(assetID: assetID, providerName: provider)
        case .pause:
            return .accepted("pause")
        case .resume:
            return .accepted("resume")
        case .cancelAll:
            return .accepted("cancelAll")
        }
    }

    private func runEvaluation(assetID: AssetID, providerName: String) throws -> WorkerCommandResult {
        _ = try repository.asset(id: assetID)
        guard let provider = evaluationProviders[providerName] else {
            throw TeststripError.invalidState("unknown evaluation provider \(providerName)")
        }
        guard let previewURL = cachedPreviewURL(for: assetID) else {
            throw TeststripError.invalidState("no cached preview for \(assetID.rawValue)")
        }
        try repository.recordEvaluationSignals(try provider.evaluate(assetID: assetID, previewURL: previewURL))
        return .completed("evaluated \(assetID.rawValue) with \(providerName)")
    }

    private func cachedPreviewURL(for assetID: AssetID) -> URL? {
        for level in [PreviewLevel.large, .medium, .grid, .micro] {
            let url = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func syncMetadata(assetID: AssetID) throws -> WorkerCommandResult {
        let asset = try repository.asset(id: assetID)
        let sidecarStore = XMPSidecarStore()
        let sidecarURL = sidecarStore.sidecarURL(forOriginalAt: asset.originalURL)
        let sidecarData = try? Data(contentsOf: sidecarURL)
        let catalogGeneration = try repository.catalogGeneration(assetID: assetID)
        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: asset.metadata,
            catalogGeneration: catalogGeneration,
            lastSynced: try repository.metadataSyncItem(assetID: assetID),
            sidecarData: sidecarData
        )

        switch decision {
        case .upToDate:
            return .completed("metadata up to date for \(assetID.rawValue)")
        case .writeCatalog:
            let result = try sidecarStore.write(metadata: asset.metadata, forOriginalAt: asset.originalURL)
            try repository.markMetadataSynced(
                assetID: assetID,
                sidecarURL: result.sidecarURL,
                catalogGeneration: catalogGeneration,
                fingerprint: result.fingerprint
            )
            return .completed("synced metadata for \(assetID.rawValue)")
        case .importSidecar(let metadata):
            try repository.updateMetadata(assetID: assetID) { catalogMetadata in
                catalogMetadata = metadata
            }
            let importedGeneration = try repository.catalogGeneration(assetID: assetID)
            let importedData: Data
            if let sidecarData {
                importedData = sidecarData
            } else {
                importedData = try Data(contentsOf: sidecarURL)
            }
            try repository.markMetadataSynced(
                assetID: assetID,
                sidecarURL: sidecarURL,
                catalogGeneration: importedGeneration,
                fingerprint: XMPSidecarStore.fingerprint(for: importedData)
            )
            return .completed("imported metadata for \(assetID.rawValue)")
        case .conflict:
            try repository.recordMetadataSyncConflict(MetadataSyncItem(
                assetID: assetID,
                sidecarURL: sidecarURL,
                catalogGeneration: catalogGeneration,
                lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
            ))
            return .completed("metadata conflict for \(assetID.rawValue)")
        }
    }
}
