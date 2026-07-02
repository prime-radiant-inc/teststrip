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

    public init(
        repository: CatalogRepository,
        previewCache: PreviewCache,
        renderer: PreviewRenderer = PreviewRenderer()
    ) {
        self.repository = repository
        self.previewCache = previewCache
        self.renderer = renderer
    }

    public init(configuration: WorkerRuntimeConfiguration) throws {
        let database = try CatalogDatabase.open(at: configuration.catalogURL)
        try database.migrate()
        self.init(
            repository: CatalogRepository(database: database),
            previewCache: PreviewCache(root: configuration.previewCacheRoot)
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
            return .accepted("syncMetadata \(assetID.rawValue)")
        case .runEvaluation(let assetID, let provider):
            return .accepted("runEvaluation \(assetID.rawValue) \(provider)")
        case .pause:
            return .accepted("pause")
        case .resume:
            return .accepted("resume")
        case .cancelAll:
            return .accepted("cancelAll")
        }
    }
}
