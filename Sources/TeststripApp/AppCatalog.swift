import Foundation
import TeststripCore

public struct AppCatalogPaths: Equatable, Sendable {
    public var root: URL
    public var catalogURL: URL
    public var previewCacheRoot: URL

    public init(root: URL, catalogURL: URL, previewCacheRoot: URL) {
        self.root = root
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
    }
}

public struct AppCatalogRuntimePolicy: Equatable, Sendable {
    public var requiresSuccessfulSecurityScopedImportAccess: Bool
    public var workerImportsEnabled: Bool

    public init(
        requiresSuccessfulSecurityScopedImportAccess: Bool,
        workerImportsEnabled: Bool
    ) {
        self.requiresSuccessfulSecurityScopedImportAccess = requiresSuccessfulSecurityScopedImportAccess
        self.workerImportsEnabled = workerImportsEnabled
    }
}

public struct AppCatalog {
    public static let applicationSupportDirectoryEnvironmentKey = "TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY"
    public static let localHTTPModelEndpointEnvironmentKey = "TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT"
    public static let localHTTPModelNameEnvironmentKey = "TESTSTRIP_LOCAL_HTTP_MODEL"
    public static let localHTTPModelTimeoutEnvironmentKey = "TESTSTRIP_LOCAL_HTTP_MODEL_TIMEOUT"
    public static let requiredSecurityScopedImportAccessEnvironmentKey = "TESTSTRIP_REQUIRE_SECURITY_SCOPED_IMPORTS"
    // INVARIANT: every worker-dispatched WorkSessionKind MUST be capped at 1
    // here. WorkerCommandLoop keeps no per-lane state and relies entirely on
    // the supervisor never dispatching two same-kind commands concurrently;
    // a limit above 1 for any of these kinds would let the worker interleave
    // two commands of the same kind with no way to tell them apart. Adding a
    // worker command for a new kind REQUIRES adding that kind here too.
    static let managedWorkerKindRunningLimits: [WorkSessionKind: Int] = [
        .ingest: 1,
        .previewGeneration: 1,
        .recognition: 1,
        .xmpSync: 1,
        .sourceScan: 1,
        .geocoding: 1,
        .locationBackfill: 1
    ]

    public var paths: AppCatalogPaths
    public var repository: CatalogRepository
    public var previewCache: PreviewCache
    public var importService: LibraryImportService
    public var metadataSidecarStore: XMPSidecarStore

    public init(
        paths: AppCatalogPaths,
        repository: CatalogRepository,
        previewCache: PreviewCache,
        importService: LibraryImportService,
        metadataSidecarStore: XMPSidecarStore = XMPSidecarStore()
    ) {
        self.paths = paths
        self.repository = repository
        self.previewCache = previewCache
        self.importService = importService
        self.metadataSidecarStore = metadataSidecarStore
    }

    public static func defaultPaths() throws -> AppCatalogPaths {
        try defaultPaths(environment: ProcessInfo.processInfo.environment)
    }

    public static func defaultPaths(environment: [String: String]) throws -> AppCatalogPaths {
        if let override = environment[applicationSupportDirectoryEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return defaultPaths(applicationSupportDirectory: URL(fileURLWithPath: override, isDirectory: true))
        }

        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return defaultPaths(applicationSupportDirectory: applicationSupportDirectory)
    }

    public static func defaultPaths(applicationSupportDirectory: URL) -> AppCatalogPaths {
        let root = applicationSupportDirectory.appendingPathComponent("Teststrip", isDirectory: true)
        return AppCatalogPaths(
            root: root,
            catalogURL: root.appendingPathComponent("catalog.sqlite"),
            previewCacheRoot: root.appendingPathComponent("Previews", isDirectory: true)
        )
    }

    public static func open(paths: AppCatalogPaths) throws -> AppCatalog {
        try FileManager.default.createDirectory(at: paths.previewCacheRoot, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: paths.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: paths.previewCacheRoot)
        let ingestService = IngestService(
            scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions),
            decodeRegistry: DecodeRegistry(providers: [ImageIODecodeProvider()])
        )
        let importService = LibraryImportService(ingestService: ingestService, previewCache: previewCache)
        return AppCatalog(paths: paths, repository: repository, previewCache: previewCache, importService: importService)
    }

    public static func bundledWorkerExecutableURL(bundleURL: URL = Bundle.main.bundleURL) -> URL {
        bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("TeststripWorker")
    }

    public static func loadModel(
        paths: AppCatalogPaths,
        workerExecutableURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionRestoreDefaults: UserDefaults? = nil
    ) throws -> AppModel {
        let runtimePolicy = runtimePolicy(environment: environment)
        let workerSupervisor: WorkerSupervisor? = workerExecutableURL.flatMap { executableURL -> WorkerSupervisor? in
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                return nil
            }
            return WorkerSupervisor(
                queue: BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: managedWorkerKindRunningLimits),
                transport: FoundationWorkerTransport(
                    executableURL: executableURL,
                    arguments: workerArguments(paths: paths, environment: environment)
                ),
                maxDispatchedCommandCount: 8
            )
        }
        return try AppModel.load(
            catalog: open(paths: paths),
            workerSupervisor: workerSupervisor,
            workerExecutableURL: workerExecutableURL,
            resourceAccess: runtimePolicy.requiresSuccessfulSecurityScopedImportAccess ? .required : .permissive,
            workerImportsEnabled: runtimePolicy.workerImportsEnabled,
            backgroundWorkPublicationInterval: backgroundWorkPublicationCoalescingInterval,
            sessionRestoreDefaults: sessionRestoreDefaults
        )
    }

    // Preview drains fire queue transitions roughly twice per imported photo;
    // publishing each one re-renders every visible grid cell, so the app batches
    // background-work publication to a human-visible cadence.
    public static let backgroundWorkPublicationCoalescingInterval: TimeInterval = 0.25

    public static func runtimePolicy(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppCatalogRuntimePolicy {
        let requiresSecurityScope = configuredEnvironmentBoolean(
            environment[requiredSecurityScopedImportAccessEnvironmentKey]
        )
        return AppCatalogRuntimePolicy(
            requiresSuccessfulSecurityScopedImportAccess: requiresSecurityScope,
            workerImportsEnabled: !requiresSecurityScope
        )
    }

    public static func workerArguments(
        paths: AppCatalogPaths,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var arguments = [
            "--catalog",
            paths.catalogURL.path,
            "--preview-cache",
            paths.previewCacheRoot.path
        ]
        if let endpoint = configuredEnvironmentValue(environment[localHTTPModelEndpointEnvironmentKey]),
           let model = configuredEnvironmentValue(environment[localHTTPModelNameEnvironmentKey]) {
            arguments.append(contentsOf: [
                "--local-http-model-endpoint",
                endpoint,
                "--local-http-model",
                model
            ])
            if let timeout = configuredEnvironmentValue(environment[localHTTPModelTimeoutEnvironmentKey]) {
                arguments.append(contentsOf: [
                    "--local-http-model-timeout",
                    timeout
                ])
            }
        }
        return arguments
    }

    private static func configuredEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func configuredEnvironmentBoolean(_ value: String?) -> Bool {
        guard let configuredValue = configuredEnvironmentValue(value)?.lowercased() else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(configuredValue)
    }
}
