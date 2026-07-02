import Foundation

public enum WorkerCommandResult: Equatable, Sendable {
    case accepted(String)
    case completed(String)
    case completedImport(String, importedAssetIDs: [AssetID])
}

public struct WorkerRuntimeConfiguration: Equatable, Sendable {
    public var catalogURL: URL
    public var previewCacheRoot: URL
    public var localHTTPModel: LocalHTTPModelProviderConfiguration?

    public init(
        catalogURL: URL,
        previewCacheRoot: URL,
        localHTTPModel: LocalHTTPModelProviderConfiguration? = nil
    ) {
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
        self.localHTTPModel = localHTTPModel
    }

    public init(arguments: [String]) throws {
        var catalogPath: String?
        var previewCachePath: String?
        var localHTTPModelEndpoint: URL?
        var localHTTPModelName: String?
        var localHTTPModelTimeout: TimeInterval?
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
            case "--local-http-model-endpoint":
                guard valueIndex < arguments.endIndex else {
                    throw TeststripError.invalidState("missing value for --local-http-model-endpoint")
                }
                guard let endpoint = URL(string: arguments[valueIndex]), endpoint.scheme != nil else {
                    throw TeststripError.invalidState("invalid value for --local-http-model-endpoint")
                }
                localHTTPModelEndpoint = endpoint
                index = arguments.index(after: valueIndex)
            case "--local-http-model":
                guard valueIndex < arguments.endIndex else {
                    throw TeststripError.invalidState("missing value for --local-http-model")
                }
                let model = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else {
                    throw TeststripError.invalidState("invalid value for --local-http-model")
                }
                localHTTPModelName = model
                index = arguments.index(after: valueIndex)
            case "--local-http-model-timeout":
                guard valueIndex < arguments.endIndex else {
                    throw TeststripError.invalidState("missing value for --local-http-model-timeout")
                }
                guard let timeout = TimeInterval(arguments[valueIndex]), timeout > 0 else {
                    throw TeststripError.invalidState("invalid value for --local-http-model-timeout")
                }
                localHTTPModelTimeout = timeout
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
        if localHTTPModelEndpoint != nil || localHTTPModelName != nil || localHTTPModelTimeout != nil {
            guard let endpoint = localHTTPModelEndpoint, let model = localHTTPModelName else {
                throw TeststripError.invalidState("local HTTP model requires endpoint and model")
            }
            self.localHTTPModel = LocalHTTPModelProviderConfiguration(
                endpoint: endpoint,
                model: model,
                timeout: localHTTPModelTimeout ?? 30
            )
        } else {
            self.localHTTPModel = nil
        }
    }
}

public struct WorkerCommandExecutor {
    private let repository: CatalogRepository
    private let previewCache: PreviewCache
    private let renderer: PreviewRenderer
    private let importService: LibraryImportService
    private let evaluationProviders: [String: any EvaluationProvider]

    public init(
        repository: CatalogRepository,
        previewCache: PreviewCache,
        renderer: PreviewRenderer = PreviewRenderer(),
        evaluationProviders: [any EvaluationProvider] = [],
        importService: LibraryImportService? = nil
    ) {
        self.repository = repository
        self.previewCache = previewCache
        self.renderer = renderer
        self.importService = importService ?? Self.defaultImportService(previewCache: previewCache)
        var providersByName: [String: any EvaluationProvider] = [:]
        for provider in evaluationProviders {
            providersByName[provider.name] = provider
        }
        self.evaluationProviders = providersByName
    }

    public init(
        configuration: WorkerRuntimeConfiguration,
        localHTTPModelTransport: (any LocalHTTPModelTransport)? = nil
    ) throws {
        let database = try CatalogDatabase.open(at: configuration.catalogURL)
        try database.migrate()
        var evaluationProviders: [any EvaluationProvider] = [
            LocalImageMetricsEvaluationProvider(),
            AppleVisionEvaluationProvider()
        ]
        if let localHTTPModel = configuration.localHTTPModel {
            evaluationProviders.append(LocalHTTPModelProvider(
                configuration: localHTTPModel,
                transport: localHTTPModelTransport ?? URLSessionLocalHTTPModelTransport()
            ))
        }
        self.init(
            repository: CatalogRepository(database: database),
            previewCache: PreviewCache(root: configuration.previewCacheRoot),
            evaluationProviders: evaluationProviders
        )
    }

    public func execute(_ command: WorkerCommand, progress: LibraryImportProgressHandler? = nil) throws -> WorkerCommandResult {
        switch command {
        case .importFolder(let root):
            let result = try importService.addFolderInPlace(
                root,
                repository: repository,
                previewPolicy: .deferGeneration,
                progress: progress
            )
            return .completedImport(
                "imported \(Self.photoCountDescription(result.importedAssets.count)) from \(root.lastPathComponent)",
                importedAssetIDs: result.importedAssets.map(\.id)
            )
        case .importCard(let source, let destinationRoot):
            let result = try importService.copyFromCard(
                source: source,
                destinationRoot: destinationRoot,
                repository: repository,
                previewPolicy: .deferGeneration,
                progress: progress
            )
            return .completedImport(
                "imported \(Self.photoCountDescription(result.importedAssets.count)) from \(source.lastPathComponent) to \(destinationRoot.lastPathComponent)",
                importedAssetIDs: result.importedAssets.map(\.id)
            )
        case .generatePreview(let assetID, let level):
            let asset = try repository.asset(id: assetID)
            try renderer.render(
                sourceURL: asset.originalURL,
                level: level,
                destinationURL: previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            )
            try repository.markPreviewGenerated(assetID: assetID, level: level)
            return .completed("generated \(level.rawValue) preview for \(Self.displayName(for: asset))")
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

    private static func defaultImportService(previewCache: PreviewCache) -> LibraryImportService {
        let decodeProvider = ImageIODecodeProvider()
        return LibraryImportService(
            ingestService: IngestService(
                scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.supportedExtensions),
                decodeRegistry: DecodeRegistry(providers: [decodeProvider])
            ),
            previewCache: previewCache
        )
    }

    private static func photoCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func displayName(for asset: Asset) -> String {
        let name = asset.originalURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? asset.id.rawValue : name
    }

    private func runEvaluation(assetID: AssetID, providerName: String) throws -> WorkerCommandResult {
        let asset = try repository.asset(id: assetID)
        guard let provider = evaluationProviders[providerName] else {
            throw TeststripError.invalidState("unknown evaluation provider \(providerName)")
        }
        guard let previewURL = cachedPreviewURL(for: assetID) else {
            throw TeststripError.invalidState("no cached preview for \(assetID.rawValue)")
        }
        try repository.recordEvaluationSignals(try provider.evaluate(assetID: assetID, previewURL: previewURL))
        return .completed("evaluated \(Self.displayName(for: asset)) with \(providerName)")
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
        let assetName = Self.displayName(for: asset)
        let sidecarStore = XMPSidecarStore()
        let sidecarURL = sidecarStore.sidecarURL(forOriginalAt: asset.originalURL)
        let sidecarData = try? Data(contentsOf: sidecarURL)
        let sidecarModificationDate: Date?
        if sidecarData != nil {
            sidecarModificationDate = try sidecarStore.modificationDate(forSidecarAt: sidecarURL)
        } else {
            sidecarModificationDate = nil
        }
        let catalogGeneration = try repository.catalogGeneration(assetID: assetID)
        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: asset.metadata,
            catalogGeneration: catalogGeneration,
            lastSynced: try repository.metadataSyncItem(assetID: assetID),
            sidecarData: sidecarData,
            sidecarModificationDate: sidecarModificationDate
        )

        switch decision {
        case .upToDate:
            return .completed("metadata up to date for \(assetName)")
        case .writeCatalog:
            do {
                let result = try sidecarStore.write(metadata: asset.metadata, forOriginalAt: asset.originalURL)
                try repository.markMetadataSynced(
                    assetID: assetID,
                    sidecarURL: result.sidecarURL,
                    catalogGeneration: catalogGeneration,
                    fingerprint: result.fingerprint
                )
                return .completed("synced metadata for \(assetName)")
            } catch {
                try repository.recordMetadataSyncPending(MetadataSyncItem(
                    assetID: assetID,
                    sidecarURL: sidecarURL,
                    catalogGeneration: catalogGeneration,
                    lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
                ))
                return .completed("metadata pending for \(assetName)")
            }
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
            return .completed("imported metadata for \(assetName)")
        case .conflict:
            try repository.recordMetadataSyncConflict(MetadataSyncItem(
                assetID: assetID,
                sidecarURL: sidecarURL,
                catalogGeneration: catalogGeneration,
                lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
            ))
            return .completed("metadata conflict for \(assetName)")
        }
    }
}
