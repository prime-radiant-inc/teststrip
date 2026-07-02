import XCTest
import TeststripCore

final class WorkerCommandExecutorTests: XCTestCase {
    func testGeneratePreviewCommandRendersRequestedPreviewFromCatalogAsset() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-command-executor")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.generatePreview(assetID: asset.id, level: .medium))

        XCTAssertEqual(result, .completed("generated medium preview for asset-1"))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .medium))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        let dimensions = try PreviewRenderer().dimensions(of: previewURL)
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.medium.maxPixelDimension!)
    }

    func testGeneratePreviewCommandClearsPendingPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-preview-queue-clear")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: asset.id, level: .grid))
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        )

        _ = try executor.execute(.generatePreview(assetID: asset.id, level: .grid))

        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [])
    }

    func testImportFolderCommandCatalogsAssetsAndDefersPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-folder")
        let sourceRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importFolder(root: sourceRoot))

        let imported = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.map(\.originalURL), [source])
        XCTAssertEqual(result, .completedImport("imported 1 photo from photos", importedAssetIDs: [asset.id]))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)).path))
    }

    func testImportCardCommandCopiesAssetsAndDefersPreviewGeneration() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-import-card")
        let sourceRoot = root.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1600, height: 1000)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])
        let sourceSidecar = XMPSidecarStore().sidecarURL(forOriginalAt: source)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sourceSidecar)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)

        let result = try executor.execute(.importCard(source: sourceRoot, destinationRoot: destinationRoot))

        let destination = destinationRoot.appendingPathComponent("source.jpg")
        let imported = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.map(\.originalURL), [destination])
        XCTAssertEqual(result, .completedImport("imported 1 photo from DCIM to Library", importedAssetIDs: [asset.id]))
        XCTAssertEqual(try repository.asset(id: asset.id).metadata, metadata)
        XCTAssertEqual(try Data(contentsOf: XMPSidecarStore().sidecarURL(forOriginalAt: destination)), sidecarData)
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid)).path))
    }

    func testSyncMetadataCommandWritesMissingSidecarFromCatalogMetadata() throws {
        let setup = try makeMetadataSyncSetup(named: "worker-sync-write", metadata: AssetMetadata(rating: 4, flag: .pick))

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("synced metadata for asset-1"))
        let sidecarData = try Data(contentsOf: setup.sidecarURL)
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, setup.asset.metadata)
        XCTAssertEqual(
            try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id),
            XMPSidecarStore.fingerprint(for: sidecarData)
        )
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
    }

    func testSyncMetadataCommandRecordsPendingWhenSidecarCannotBeWritten() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-sync-pending")
        let originalURL = root
            .appendingPathComponent("offline", isDirectory: true)
            .appendingPathComponent("asset.raw")
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: originalURL,
            volumeIdentifier: "offline-volume",
            fingerprint: FileFingerprint(size: 14, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .missing,
            metadata: AssetMetadata(rating: 4, flag: .pick)
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let executor = WorkerCommandExecutor(repository: repository, previewCache: previewCache)
        let catalogGeneration = try repository.catalogGeneration(assetID: asset.id)

        let result = try executor.execute(.syncMetadata(assetID: asset.id))

        XCTAssertEqual(result, .completed("metadata pending for asset-1"))
        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [
            MetadataSyncItem(
                assetID: asset.id,
                sidecarURL: originalURL.appendingPathExtension("xmp"),
                catalogGeneration: catalogGeneration,
                lastSyncedFingerprint: nil
            )
        ])
    }

    func testSyncMetadataCommandImportsExternallyChangedSidecarWhenCatalogIsUnchanged() throws {
        let catalogMetadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-import", metadata: catalogMetadata)
        let initialWrite = try XMPSidecarStore().write(metadata: catalogMetadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        let sidecarMetadata = AssetMetadata(rating: 5, colorLabel: .green, keywords: ["external"])
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("imported metadata for asset-1"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, sidecarMetadata)
        let currentSidecarData = try Data(contentsOf: setup.sidecarURL)
        XCTAssertEqual(
            try setup.repository.lastMetadataSyncFingerprint(assetID: setup.asset.id),
            XMPSidecarStore.fingerprint(for: currentSidecarData)
        )
        XCTAssertEqual(try setup.repository.pendingMetadataSyncItems(), [])
    }

    func testSyncMetadataCommandRefreshesNewerSidecarCheckpointWhenContentsMatch() throws {
        let metadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-newer-sidecar-checkpoint", metadata: metadata)
        let initialWrite = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        let initialSync = try XCTUnwrap(try setup.repository.metadataSyncItem(assetID: setup.asset.id)?.lastSyncedAt)
        Thread.sleep(forTimeInterval: 0.01)
        let newerModificationDate = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: newerModificationDate],
            ofItemAtPath: setup.sidecarURL.path
        )

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("imported metadata for asset-1"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata, metadata)
        let refreshedSync = try XCTUnwrap(try setup.repository.metadataSyncItem(assetID: setup.asset.id)?.lastSyncedAt)
        XCTAssertGreaterThan(refreshedSync.timeIntervalSince1970, initialSync.timeIntervalSince1970)
    }

    func testSyncMetadataCommandRecordsConflictWhenCatalogAndSidecarBothChanged() throws {
        let initialMetadata = AssetMetadata(rating: 2)
        let setup = try makeMetadataSyncSetup(named: "worker-sync-conflict", metadata: initialMetadata)
        let initialWrite = try XMPSidecarStore().write(metadata: initialMetadata, forOriginalAt: setup.asset.originalURL)
        try setup.repository.markMetadataSynced(
            assetID: setup.asset.id,
            sidecarURL: initialWrite.sidecarURL,
            catalogGeneration: try setup.repository.catalogGeneration(assetID: setup.asset.id),
            fingerprint: initialWrite.fingerprint
        )
        try setup.repository.updateMetadata(assetID: setup.asset.id) { metadata in
            metadata.rating = 4
        }
        let sidecarMetadata = AssetMetadata(rating: 5)
        try XMPPacket(metadata: sidecarMetadata).xmlData().write(to: setup.sidecarURL)

        let result = try setup.executor.execute(.syncMetadata(assetID: setup.asset.id))

        XCTAssertEqual(result, .completed("metadata conflict for asset-1"))
        XCTAssertEqual(try setup.repository.asset(id: setup.asset.id).metadata.rating, 4)
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: setup.sidecarURL)).metadata, sidecarMetadata)
        XCTAssertEqual(try setup.repository.metadataSyncConflictItems().map(\.assetID), [setup.asset.id])
    }

    func testRunEvaluationPersistsSignalsFromNamedProviderUsingCachedPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-evaluation")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cached preview".utf8).write(to: previewURL)
        let executor = WorkerCommandExecutor(
            repository: repository,
            previewCache: previewCache,
            evaluationProviders: [PreviewPathEvaluationProvider(name: "local")]
        )

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "local"))

        XCTAssertEqual(result, .completed("evaluated asset-1 with local"))
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id), [
            EvaluationSignal(
                assetID: asset.id,
                kind: .aesthetics,
                value: .text(previewURL.path),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: "local", model: "preview-path", version: "1", settingsHash: "default")
            )
        ])
    }

    func testRuntimeConfigurationRegistersLocalImageMetricsProvider() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-evaluation")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root
        ))

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "local-image-metrics"))

        XCTAssertEqual(result, .completed("evaluated asset-1 with local-image-metrics"))
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id).map(\.kind), [.exposure, .colorPalette])
    }

    func testRuntimeConfigurationRegistersAppleVisionProvider() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-apple-vision")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root
        ))

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "apple-vision"))

        XCTAssertEqual(result, .completed("evaluated asset-1 with apple-vision"))
    }

    func testRuntimeConfigurationRegistersLocalHTTPModelProviderWhenConfigured() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "worker-runtime-local-http-model")
        let source = root.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: previewURL, width: 512, height: 340)
        let transport = RecordingLocalHTTPModelTransport(response: .success(LocalHTTPModelHTTPResponse(
            statusCode: 200,
            data: try chatCompletionData(content: """
            {"signals":[{"kind":"aesthetics","label":"portfolio","confidence":0.71}]}
            """)
        )))
        let executor = try WorkerCommandExecutor(
            configuration: WorkerRuntimeConfiguration(
                catalogURL: catalogURL,
                previewCacheRoot: previewCache.root,
                localHTTPModel: LocalHTTPModelProviderConfiguration(
                    endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
                    model: "llava",
                    timeout: 6
                )
            ),
            localHTTPModelTransport: transport
        )

        let result = try executor.execute(.runEvaluation(assetID: asset.id, provider: "local-http-model"))

        XCTAssertEqual(result, .completed("evaluated asset-1 with local-http-model"))
        XCTAssertEqual(try repository.evaluationSignals(assetID: asset.id), [
            EvaluationSignal(
                assetID: asset.id,
                kind: .aesthetics,
                value: .label("portfolio"),
                confidence: 0.71,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            )
        ])
        let request = try XCTUnwrap(transport.requests().first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(request.timeoutInterval, 6)
    }

    func testRuntimeConfigurationParsesOptionalLocalHTTPModelArguments() throws {
        let configuration = try WorkerRuntimeConfiguration(arguments: [
            "--catalog",
            "/tmp/catalog.sqlite",
            "--preview-cache",
            "/tmp/previews",
            "--local-http-model-endpoint",
            "http://localhost:1234/v1/chat/completions",
            "--local-http-model",
            "llava",
            "--local-http-model-timeout",
            "6"
        ])

        XCTAssertEqual(configuration.localHTTPModel, LocalHTTPModelProviderConfiguration(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            timeout: 6
        ))
    }

    private func makeMetadataSyncSetup(
        named name: String,
        metadata: AssetMetadata
    ) throws -> (
        repository: CatalogRepository,
        executor: WorkerCommandExecutor,
        asset: Asset,
        sidecarURL: URL
    ) {
        let root = try TestDirectories.makeTemporaryDirectory(named: name)
        let originalURL = root.appendingPathComponent("asset.raw")
        try Data("original bytes".utf8).write(to: originalURL)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: originalURL,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 14, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: metadata
        )
        try repository.upsert(asset)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        return (
            repository: repository,
            executor: WorkerCommandExecutor(repository: repository, previewCache: previewCache),
            asset: asset,
            sidecarURL: originalURL.appendingPathExtension("xmp")
        )
    }
}

private struct PreviewPathEvaluationProvider: EvaluationProvider {
    var name: String

    func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        [
            EvaluationSignal(
                assetID: assetID,
                kind: .aesthetics,
                value: .text(previewURL.path),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: name, model: "preview-path", version: "1", settingsHash: "default")
            )
        ]
    }
}

private final class RecordingLocalHTTPModelTransport: LocalHTTPModelTransport, @unchecked Sendable {
    private let response: Result<LocalHTTPModelHTTPResponse, Error>
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    init(response: Result<LocalHTTPModelHTTPResponse, Error>) {
        self.response = response
    }

    func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
        return try response.get()
    }

    func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

private func chatCompletionData(content: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "choices": [
            [
                "message": [
                    "content": content
                ]
            ]
        ]
    ])
}
