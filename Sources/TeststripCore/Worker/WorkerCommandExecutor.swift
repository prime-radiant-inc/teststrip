import Foundation

public enum WorkerCommandResult: Equatable, Sendable {
    case accepted(String)
    case completed(String)
    case completedImport(
        String,
        importedAssetIDs: [AssetID],
        newAssetCount: Int,
        existingAssetCount: Int,
        skippedSourceFileCount: Int,
        skippedSourceFiles: [LibrarySkippedSourceFile]
    )
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
    // A conservative read of CLGeocoder's undocumented throttle: 50 requests per
    // minute, one every 1.2 s. Failures re-queue (Task 6), so an over-eager
    // budget self-corrects, but this errs slow. Tunable.
    public static let reverseGeocodeRequestsPerMinuteBudget = 50
    public static let reverseGeocodeMinimumRequestInterval = 60.0 / Double(reverseGeocodeRequestsPerMinuteBudget)
    public static let reverseGeocodeMaximumAttemptCount = 5

    private let repository: CatalogRepository
    private let previewCache: PreviewCache
    private let renderer: PreviewRenderer
    private let importService: LibraryImportService
    private let evaluationProviders: [String: any EvaluationProvider]
    private let reverseGeocoder: (any ReverseGeocoder)?
    private let reverseGeocodeRequestInterval: TimeInterval

    public init(
        repository: CatalogRepository,
        previewCache: PreviewCache,
        renderer: PreviewRenderer = PreviewRenderer(),
        evaluationProviders: [any EvaluationProvider] = [],
        importService: LibraryImportService? = nil,
        reverseGeocoder: (any ReverseGeocoder)? = nil,
        reverseGeocodeRequestInterval: TimeInterval? = nil
    ) {
        self.repository = repository
        self.previewCache = previewCache
        self.renderer = renderer
        self.importService = importService ?? Self.defaultImportService(previewCache: previewCache)
        self.reverseGeocoder = reverseGeocoder
        self.reverseGeocodeRequestInterval = reverseGeocodeRequestInterval ?? Self.reverseGeocodeMinimumRequestInterval
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
            AppleVisionEvaluationProvider(),
            FaceExpressionEvaluationProvider()
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
            evaluationProviders: evaluationProviders,
            reverseGeocoder: CLGeocoderReverseGeocoder()
        )
    }

    public func execute(_ command: WorkerCommand, progress: LibraryImportProgressHandler? = nil) throws -> WorkerCommandResult {
        switch command {
        case .importFolder(let root, let duplicateHandling):
            let result = try importService.addFolderInPlace(
                root,
                repository: repository,
                previewPolicy: .deferGeneration,
                duplicateHandling: duplicateHandling,
                progress: progress
            )
            return .completedImport(
                "imported \(Self.photoCountDescription(result.importedAssets.count)) from \(root.lastPathComponent)",
                importedAssetIDs: result.importedAssets.map(\.id),
                newAssetCount: result.newAssetCount,
                existingAssetCount: result.existingAssetCount,
                skippedSourceFileCount: result.skippedSourceFileCount,
                skippedSourceFiles: result.skippedSourceFiles
            )
        case .importCard(let source, let destinationRoot, let destinationPolicy, let secondCopyDestination, let duplicateHandling):
            let result = try importService.copyFromCard(
                source: source,
                destinationRoot: destinationRoot,
                destinationPolicy: destinationPolicy,
                secondCopyDestination: secondCopyDestination,
                repository: repository,
                previewPolicy: .deferGeneration,
                duplicateHandling: duplicateHandling,
                progress: progress
            )
            return .completedImport(
                "imported \(Self.photoCountDescription(result.importedAssets.count)) from \(source.lastPathComponent) to \(destinationRoot.lastPathComponent)",
                importedAssetIDs: result.importedAssets.map(\.id),
                newAssetCount: result.newAssetCount,
                existingAssetCount: result.existingAssetCount,
                skippedSourceFileCount: result.skippedSourceFileCount,
                skippedSourceFiles: result.skippedSourceFiles
            )
        case .generatePreview(let assetID, let level):
            let asset = try repository.asset(id: assetID)
            if let availability = try markPreviewBlockingAvailabilityIfNeeded(asset) {
                throw TeststripError.io("original is \(availability.rawValue) for \(Self.displayName(for: asset))")
            }
            do {
                try renderer.render(
                    sourceURL: asset.originalURL,
                    level: level,
                    destinationURL: previewCache.url(for: PreviewCacheKey(assetID: assetID, level: level))
                )
            } catch {
                if let availability = try markPreviewBlockingAvailabilityIfNeeded(asset) {
                    throw TeststripError.io("original is \(availability.rawValue) for \(Self.displayName(for: asset))")
                }
                try repository.recordPreviewGenerationFailure(
                    assetID: assetID,
                    level: level,
                    errorMessage: error.localizedDescription
                )
                throw error
            }
            try repository.markPreviewGenerated(assetID: assetID, level: level)
            return .completed("generated \(level.rawValue) preview for \(Self.displayName(for: asset))")
        case .syncMetadata(let assetID):
            return try syncMetadata(assetID: assetID)
        case .refreshAvailability(let assetID):
            return try refreshAvailability(assetID: assetID)
        case .refreshAvailabilityBatch(let assetIDs):
            return try refreshAvailabilityBatch(assetIDs: assetIDs, progress: progress)
        case .runEvaluation(let assetID, let provider):
            return try runEvaluation(assetID: assetID, providerName: provider)
        case .reverseGeocodeBatch(let limit):
            return try reverseGeocodeBatch(limit: limit, progress: progress)
        case .backfillCoordinates(let assetIDs):
            return try backfillCoordinates(assetIDs: assetIDs, progress: progress)
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
                scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions),
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

    private func markPreviewBlockingAvailabilityIfNeeded(_ asset: Asset) throws -> SourceAvailability? {
        let availability = SourceAvailabilityProbe().availability(for: asset)
        switch availability {
        case .offline, .missing, .stale:
            try repository.updateAvailability(assetID: asset.id, availability: availability)
            return availability
        case .online, .moved:
            return nil
        }
    }

    private func refreshAvailability(assetID: AssetID) throws -> WorkerCommandResult {
        let asset = try repository.asset(id: assetID)
        let availability = SourceAvailabilityProbe().availability(for: asset)
        try repository.updateAvailability(assetID: assetID, availability: availability)
        return .completed("source \(availability.rawValue) for \(Self.displayName(for: asset))")
    }

    private func refreshAvailabilityBatch(
        assetIDs: [AssetID],
        progress: LibraryImportProgressHandler?
    ) throws -> WorkerCommandResult {
        for (index, assetID) in assetIDs.enumerated() {
            try Task.checkCancellation()
            let asset = try repository.asset(id: assetID)
            let availability = SourceAvailabilityProbe().availability(for: asset)
            try repository.updateAvailability(assetID: assetID, availability: availability)
            let completedCount = index + 1
            progress?(LibraryImportProgress(
                completedUnitCount: completedCount,
                totalUnitCount: assetIDs.count,
                detail: "Checked \(completedCount) of \(assetIDs.count) sources"
            ))
        }
        return .completed("checked \(assetIDs.count) sources")
    }

    private func reverseGeocodeBatch(
        limit: Int,
        progress: LibraryImportProgressHandler?
    ) throws -> WorkerCommandResult {
        guard let reverseGeocoder else {
            throw TeststripError.invalidState("worker has no reverse geocoder configured")
        }
        let items = try repository.pendingGeocodeItems(
            limit: limit,
            maximumAttemptCount: Self.reverseGeocodeMaximumAttemptCount
        )
        var resolvedCount = 0
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            if index > 0, reverseGeocodeRequestInterval > 0 {
                Thread.sleep(forTimeInterval: reverseGeocodeRequestInterval)
            }
            do {
                // A nil result (no place found) is still cached with all-nil
                // components so the coordinate leaves the queue and is never
                // retried forever.
                let geocoded = try reverseGeocoder.reverseGeocode(latitude: item.latitude, longitude: item.longitude)
                try repository.recordPlaceName(CatalogPlaceName(
                    coordinateKey: item.coordinateKey,
                    locality: geocoded?.locality,
                    administrativeArea: geocoded?.administrativeArea,
                    country: geocoded?.country,
                    displayName: CatalogPlaceName.displayName(
                        locality: geocoded?.locality,
                        administrativeArea: geocoded?.administrativeArea,
                        country: geocoded?.country
                    )
                ))
                resolvedCount += 1
            } catch {
                try repository.recordGeocodeFailure(
                    coordinateKey: item.coordinateKey,
                    errorMessage: error.localizedDescription
                )
            }
            let completedCount = index + 1
            progress?(LibraryImportProgress(
                completedUnitCount: completedCount,
                totalUnitCount: items.count,
                detail: "Read \(completedCount) of \(items.count) locations"
            ))
        }
        return .completed("reverse-geocoded \(resolvedCount) \(resolvedCount == 1 ? "location" : "locations")")
    }

    private func backfillCoordinates(
        assetIDs: [AssetID],
        progress: LibraryImportProgressHandler?
    ) throws -> WorkerCommandResult {
        var updatedCount = 0
        for (index, assetID) in assetIDs.enumerated() {
            try Task.checkCancellation()
            // A missing asset, unavailable original, or decode failure is skipped
            // (not fatal), matching refreshAvailabilityBatch's per-item resilience.
            if var asset = try? repository.asset(id: assetID),
               let reRead = importService.ingestService.reReadTechnicalMetadata(for: asset.originalURL),
               let latitude = reRead.latitude {
                if var technicalMetadata = asset.technicalMetadata {
                    technicalMetadata.latitude = latitude
                    technicalMetadata.longitude = reRead.longitude
                    technicalMetadata.altitude = reRead.altitude
                    asset.technicalMetadata = technicalMetadata
                } else {
                    asset.technicalMetadata = reRead
                }
                // Targeted column write: a full-row upsert here would clobber a
                // concurrent .sourceScan lane's updateAvailability (lost update).
                try repository.updateTechnicalMetadata(assetID: assetID, technicalMetadata: asset.technicalMetadata!)
                updatedCount += 1
            }
            let completedCount = index + 1
            progress?(LibraryImportProgress(
                completedUnitCount: completedCount,
                totalUnitCount: assetIDs.count,
                detail: "Read locations for \(completedCount) of \(assetIDs.count) photos"
            ))
        }
        return .completed("read locations for \(updatedCount) \(updatedCount == 1 ? "photo" : "photos")")
    }

    private func runEvaluation(assetID: AssetID, providerName: String) throws -> WorkerCommandResult {
        let asset = try repository.asset(id: assetID)
        guard let provider = evaluationProviders[providerName] else {
            throw TeststripError.invalidState("unknown evaluation provider \(providerName)")
        }
        guard let previewURL = cachedPreviewURL(for: assetID) else {
            throw TeststripError.invalidState("no cached preview for \(assetID.rawValue)")
        }
        if let faceProvider = provider as? any FaceObservationEvaluationProvider {
            let outcome = try faceProvider.evaluateWithFaces(assetID: assetID, previewURL: previewURL)
            try repository.recordEvaluationSignals(outcome.signals)
            try repository.replaceFaceObservations(
                assetID: assetID,
                provenance: faceProvider.faceProvenance,
                with: outcome.faceObservations
            )
        } else {
            try repository.recordEvaluationSignals(try provider.evaluate(assetID: assetID, previewURL: previewURL))
        }
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
        // A recorded conflict is the user's decision point: a routine sync
        // check must never auto-resolve it, or a later-parsable or externally
        // updated sidecar would be imported over the user's catalog edit with
        // no choice ever offered. Refresh the row and wait for an explicit
        // resolution (Use Catalog / Use Sidecar / merge), each of which
        // transitions the row out of "conflict" itself.
        if try repository.metadataSyncConflictItem(assetID: assetID) != nil {
            try repository.recordMetadataSyncConflict(MetadataSyncItem(
                assetID: assetID,
                sidecarURL: sidecarURL,
                catalogGeneration: catalogGeneration,
                lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
            ))
            return .completed("metadata conflict for \(assetName)")
        }
        let syncItem = try repository.metadataSyncItem(assetID: assetID)
        let decision: MetadataSyncDecision
        do {
            decision = try metadataSyncDecision(
                catalogMetadata: asset.metadata,
                catalogGeneration: catalogGeneration,
                syncItem: syncItem,
                sidecarData: sidecarData,
                sidecarModificationDate: sidecarModificationDate
            )
        } catch {
            if let conflict = try recordConflictForUnreadableSidecar(
                assetID: assetID,
                assetName: assetName,
                sidecarURL: sidecarURL,
                sidecarData: sidecarData,
                catalogGeneration: catalogGeneration
            ) {
                return conflict
            }
            throw error
        }

        switch decision {
        case .upToDate:
            if let sidecarData {
                try repository.markMetadataSynced(
                    assetID: assetID,
                    sidecarURL: sidecarURL,
                    catalogGeneration: catalogGeneration,
                    fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
                )
            }
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
                if let conflict = try recordConflictForUnreadableSidecar(
                    assetID: assetID,
                    assetName: assetName,
                    sidecarURL: sidecarURL,
                    sidecarData: sidecarData,
                    catalogGeneration: catalogGeneration
                ) {
                    return conflict
                }
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
                catalogMetadata = catalogMetadata.mergingConfirmedSidecar(metadata)
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

    /// A sync step that fails because the existing sidecar cannot be parsed would otherwise
    /// retry forever as a silently pending item. Recording the existing conflict state instead
    /// routes the asset into XMP Conflicts review, where the inspector surfaces the unreadable
    /// sidecar and offers Use Catalog to recreate it. Returns nil when the sidecar is absent or
    /// parses cleanly, so unrelated failures keep their current handling.
    func recordConflictForUnreadableSidecar(
        assetID: AssetID,
        assetName: String,
        sidecarURL: URL,
        sidecarData: Data?,
        catalogGeneration: Int
    ) throws -> WorkerCommandResult? {
        guard let sidecarData, (try? XMPPacket.parse(sidecarData)) == nil else {
            return nil
        }
        // A file another tool is mid-way through writing (Finder/SMB copy,
        // non-atomic saver) reads as torn bytes that fail to parse exactly
        // like a genuinely corrupt sidecar. Only record a durable conflict
        // when a fresh read returns the same still-unparsable bytes; otherwise
        // let the original error fail the command so the next check sees the
        // finished file.
        guard let currentData = try? Data(contentsOf: sidecarURL), currentData == sidecarData else {
            return nil
        }
        try repository.recordMetadataSyncConflict(MetadataSyncItem(
            assetID: assetID,
            sidecarURL: sidecarURL,
            catalogGeneration: catalogGeneration,
            lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
        ))
        return .completed("metadata conflict for \(assetName)")
    }

    private func metadataSyncDecision(
        catalogMetadata: AssetMetadata,
        catalogGeneration: Int,
        syncItem: MetadataSyncItem?,
        sidecarData: Data?,
        sidecarModificationDate: Date?
    ) throws -> MetadataSyncDecision {
        if let syncItem,
           syncItem.lastSyncedFingerprint == nil,
           let sidecarData,
           try repository.pendingMetadataSyncItem(assetID: syncItem.assetID) != nil,
           let pendingUpdatedAt = try repository.metadataSyncStateUpdatedAt(assetID: syncItem.assetID) {
            if let sidecarModificationDate, sidecarModificationDate > pendingUpdatedAt {
                return .conflict(
                    catalogMetadata: catalogMetadata,
                    sidecarMetadata: try XMPPacket.parse(sidecarData).metadata
                )
            }
            return .writeCatalog
        }

        return try MetadataSyncPlanner().decision(
            catalogMetadata: catalogMetadata,
            catalogGeneration: catalogGeneration,
            lastSynced: syncItem,
            sidecarData: sidecarData,
            sidecarModificationDate: sidecarModificationDate
        )
    }
}
