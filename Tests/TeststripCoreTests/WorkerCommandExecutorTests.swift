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
