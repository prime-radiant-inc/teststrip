import XCTest
import TeststripCore
@testable import TeststripBench

final class BenchmarkCommandTests: XCTestCase {
    func testDefaultCommandRunsCatalogScaleBenchmark() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench"]), .catalogScale(count: 500_000))
    }

    func testCatalogBaselineCommandRunsBaselineScaleBenchmark() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench", "catalog-baseline"]), .catalogScale(count: 500_000))
    }

    func testCatalogStressCommandRunsStressScaleBenchmark() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench", "catalog-stress"]), .catalogScale(count: 1_000_000))
    }

    func testNumericArgumentRunsCatalogScaleBenchmark() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench", "250000"]), .catalogScale(count: 250_000))
    }

    func testImportDeferredCommandParsesCount() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench", "import-deferred", "250"]), .importDeferred(count: 250))
    }

    func testMetadataWriteCommandParsesCount() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench", "metadata-write", "250"]), .metadataWrite(count: 250))
    }

    func testPreviewRenderCommandParsesCount() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench", "preview-render", "250"]), .previewRender(count: 250))
    }

    func testSamplePreviewRenderCommandParsesPhotoDirectory() throws {
        XCTAssertEqual(
            BenchmarkCommand.parse(["TeststripBench", "sample-preview-render", "/tmp/teststrip-samples"]),
            .samplePreviewRender(photoDirectory: URL(fileURLWithPath: "/tmp/teststrip-samples"))
        )
    }

    func testLocalHTTPModelSmokeCommandParsesConnectionArguments() throws {
        XCTAssertEqual(
            BenchmarkCommand.parse([
                "TeststripBench",
                "local-http-smoke",
                "http://localhost:1234/v1/chat/completions",
                "llava",
                "/tmp/frame.jpg",
                "12"
            ]),
            .localHTTPSmoke(
                endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
                model: "llava",
                imagePath: "/tmp/frame.jpg",
                timeout: 12
            )
        )
    }

    func testSeedAppCatalogCommandParsesApplicationSupportDirectoryAndCount() throws {
        XCTAssertEqual(
            BenchmarkCommand.parse(["TeststripBench", "seed-app-catalog", "/tmp/teststrip-smoke", "12"]),
            .seedAppCatalog(applicationSupportDirectory: URL(fileURLWithPath: "/tmp/teststrip-smoke"), count: 12)
        )
    }

    func testSeedSampleCatalogCommandParsesApplicationSupportDirectoryAndPhotoDirectory() throws {
        XCTAssertEqual(
            BenchmarkCommand.parse(["TeststripBench", "seed-sample-catalog", "/tmp/teststrip-sample", "/tmp/teststrip-photos"]),
            .seedSampleCatalog(
                applicationSupportDirectory: URL(fileURLWithPath: "/tmp/teststrip-sample"),
                photoDirectory: URL(fileURLWithPath: "/tmp/teststrip-photos")
            )
        )
    }

    func testDeferredImportBenchmarkCatalogsAssetsAndQueuesPreviewWork() throws {
        let root = try makeTemporaryDirectory(named: "deferred-import-benchmark")

        let result = try ImportDeferredBenchmark(count: 250, root: root).run()

        XCTAssertEqual(result.importedAssetCount, 250)
        XCTAssertEqual(result.catalogAssetCount, 250)
        XCTAssertEqual(result.pendingPreviewCount, 500)
        XCTAssertLessThanOrEqual(result.progressEventCount, 8)
    }

    func testCatalogScaleBenchmarkMeasuresRepresentativeIndexedFilters() throws {
        let root = try makeTemporaryDirectory(named: "catalog-scale-benchmark")

        let result = try CatalogScaleBenchmark(count: 120, root: root).run()

        XCTAssertEqual(result.assetCount, 120)
        XCTAssertEqual(result.firstPageRows, 120)
        XCTAssertEqual(result.middlePageRows, 60)
        XCTAssertEqual(result.filteredRating4PlusCount, 40)
        XCTAssertEqual(result.filteredPageRows, 40)
        XCTAssertEqual(result.pickedCount, 40)
        XCTAssertEqual(result.greenLabelCount, 24)
        XCTAssertEqual(result.keywordBatch10Count, 10)
        XCTAssertEqual(result.offlineCount, 60)
        XCTAssertEqual(result.folderFrameCount, 120)
        XCTAssertEqual(result.cameraSmokeCam2Count, 40)
        XCTAssertEqual(result.lens50mmCount, 30)
        XCTAssertEqual(result.isoAtLeast500Count, 72)
        XCTAssertEqual(result.recentCaptureCount, 60)
    }

    func testMetadataWriteBenchmarkUpdatesCatalogAndWritesSidecars() throws {
        let root = try makeTemporaryDirectory(named: "metadata-write-benchmark")

        let result = try MetadataWriteBenchmark(count: 250, root: root).run()

        XCTAssertEqual(result.updatedAssetCount, 250)
        XCTAssertEqual(result.catalogAssetCount, 250)
        XCTAssertEqual(result.sidecarCount, 250)
        XCTAssertEqual(result.syncedFingerprintCount, 250)
        XCTAssertEqual(result.pendingSyncCount, 0)
        XCTAssertEqual(result.unchangedOriginalCount, 250)
    }

    func testPreviewRenderBenchmarkCreatesCachedPreviews() throws {
        let root = try makeTemporaryDirectory(named: "preview-render-benchmark")

        let result = try PreviewRenderBenchmark(count: 12, root: root).run()

        XCTAssertEqual(result.sourceImageCount, 12)
        XCTAssertEqual(result.renderedPreviewCount, 48)
        XCTAssertEqual(result.cachedPreviewCount, 48)
    }

    func testSamplePreviewRenderBenchmarkCreatesCachedPreviewsFromExistingPhotos() throws {
        let root = try makeTemporaryDirectory(named: "sample-preview-render-benchmark")
        let photoDirectory = try makeTemporaryDirectory(named: "sample-preview-render-photos")
        try writeTestPNG(to: photoDirectory.appendingPathComponent("one.png"))
        try writeTestPNG(to: photoDirectory.appendingPathComponent("two.png"))

        let result = try SamplePreviewRenderBenchmark(root: root, photoDirectory: photoDirectory).run()

        XCTAssertEqual(result.sourceImageCount, 2)
        XCTAssertEqual(result.catalogAssetCount, 2)
        XCTAssertEqual(result.cachedPreviewCount, 4)
    }

    func testLocalHTTPModelSmokeEvaluatesOpenAICompatibleEndpoint() throws {
        let root = try makeTemporaryDirectory(named: "local-http-smoke")
        let previewURL = root.appendingPathComponent("frame.jpg")
        try Data("preview".utf8).write(to: previewURL)
        let endpoint = URL(string: "http://localhost:1234/v1/chat/completions")!
        let transport = RecordingSmokeTransport()

        let result = try LocalHTTPModelSmoke(
            endpoint: endpoint,
            model: "llava",
            imageURL: previewURL,
            timeout: 12,
            transport: transport
        ).run()

        XCTAssertEqual(result, LocalHTTPModelSmokeResult(signalCount: 1, signalKinds: [.focus]))
        XCTAssertEqual(transport.request?.url, endpoint)
        XCTAssertEqual(transport.request?.timeoutInterval, 12)
    }

    func testSmokeCatalogSeederCreatesAppCatalogAssetsAndPreviews() throws {
        let applicationSupportDirectory = try makeTemporaryDirectory(named: "smoke-app-support")

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            count: 8
        ).run()

        let database = try CatalogDatabase.open(at: result.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try repository.allAssets(limit: 20)
        let previewCache = PreviewCache(root: result.previewCacheRoot)

        XCTAssertEqual(result.assetCount, 8)
        XCTAssertEqual(result.sourceImageCount, 8)
        XCTAssertEqual(result.cachedPreviewCount, 32)
        XCTAssertEqual(try repository.assetCount(), 8)
        XCTAssertEqual(assets.count, 8)
        XCTAssertEqual(assets.first?.metadata.rating, 0)
        XCTAssertEqual(assets.first?.technicalMetadata?.cameraMake, "Teststrip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets[0].originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: assets[0].id, level: .grid)).path))
    }

    func testSmokeCatalogSeederCreatesStarredPicksSet() throws {
        let applicationSupportDirectory = try makeTemporaryDirectory(named: "smoke-picks-app-support")

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            count: 8
        ).run()

        let database = try CatalogDatabase.open(at: result.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let picks = try XCTUnwrap(try repository.assetSets().first { $0.name == "Smoke Picks" })

        XCTAssertTrue(picks.starred)
        XCTAssertEqual(picks.membership, .manual([
            AssetID(rawValue: "smoke-4"),
            AssetID(rawValue: "smoke-5")
        ]))
    }

    func testSmokeCatalogSeederRefusesExistingCatalog() throws {
        let applicationSupportDirectory = try makeTemporaryDirectory(named: "existing-smoke-app-support")
        let catalogURL = applicationSupportDirectory
            .appendingPathComponent("Teststrip", isDirectory: true)
            .appendingPathComponent("catalog.sqlite")
        try FileManager.default.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing catalog".utf8).write(to: catalogURL)

        XCTAssertThrowsError(try SmokeCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            count: 1
        ).run()) { error in
            XCTAssertTrue(error.localizedDescription.contains("refusing to seed smoke catalog over existing catalog"))
        }
    }

    func testSampleCatalogSeederImportsExistingPhotosAndPreviews() throws {
        let applicationSupportDirectory = try makeTemporaryDirectory(named: "sample-app-support")
        let photoDirectory = try makeTemporaryDirectory(named: "sample-photos")
        try writeTestPNG(to: photoDirectory.appendingPathComponent("one.png"))
        try writeTestPNG(to: photoDirectory.appendingPathComponent("two.png"))

        let result = try SampleCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            photoDirectory: photoDirectory
        ).run()

        let database = try CatalogDatabase.open(at: result.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try repository.allAssets(limit: 20)
        let previewCache = PreviewCache(root: result.previewCacheRoot)

        XCTAssertEqual(result.sourceImageCount, 2)
        XCTAssertEqual(result.assetCount, 2)
        XCTAssertEqual(result.cachedPreviewCount, 4)
        XCTAssertEqual(try repository.assetCount(), 2)
        XCTAssertEqual(Set(assets.map { $0.originalURL.deletingLastPathComponent() }), [photoDirectory])
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewCache.url(for: PreviewCacheKey(assetID: assets[0].id, level: .grid)).path))
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [PreviewGenerationItem]())
    }

    func testSampleCatalogSeederRefusesExistingCatalog() throws {
        let applicationSupportDirectory = try makeTemporaryDirectory(named: "existing-sample-app-support")
        let photoDirectory = try makeTemporaryDirectory(named: "existing-sample-photos")
        let catalogURL = applicationSupportDirectory
            .appendingPathComponent("Teststrip", isDirectory: true)
            .appendingPathComponent("catalog.sqlite")
        try FileManager.default.createDirectory(at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing catalog".utf8).write(to: catalogURL)

        XCTAssertThrowsError(try SampleCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            photoDirectory: photoDirectory
        ).run()) { error in
            XCTAssertTrue(error.localizedDescription.contains("refusing to seed sample catalog over existing catalog"))
        }
    }

    func testBenchmarkSummaryEmitsDecodableMachineReadableLine() throws {
        let summary = BenchmarkSummary(
            benchmark: "catalog_scale",
            count: 500_000,
            metrics: [
                "asset_count": 500_000,
                "first_page_rows": 500
            ],
            measurements: [
                "load_first_page": 0.008
            ]
        )

        let line = try summary.machineReadableLine()

        XCTAssertTrue(line.hasPrefix("benchmark-summary\t"))
        let payload = String(line.dropFirst("benchmark-summary\t".count))
        let decoded = try JSONDecoder().decode(BenchmarkSummary.self, from: Data(payload.utf8))
        XCTAssertEqual(decoded, summary)
    }

    func testBenchmarkSummaryRecorderCapturesMetricsAndMeasurements() throws {
        var recorder = BenchmarkSummaryRecorder(benchmark: "preview_render", count: 12)

        recorder.recordMetric("rendered_previews", 48)
        let value = recorder.measure("preview_render") {
            "rendered"
        }

        XCTAssertEqual(value, "rendered")
        XCTAssertEqual(recorder.summary.benchmark, "preview_render")
        XCTAssertEqual(recorder.summary.count, 12)
        XCTAssertEqual(recorder.summary.metrics["rendered_previews"], 48)
        XCTAssertNotNil(recorder.summary.measurements["preview_render"])
    }

    func testBenchmarkWorkspaceCreatesUniqueTemporaryRoots() {
        let first = BenchmarkWorkspace.temporaryRoot()
        let second = BenchmarkWorkspace.temporaryRoot()

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("teststrip-bench-"))
        XCTAssertTrue(second.lastPathComponent.hasPrefix("teststrip-bench-"))
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-bench-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeTestPNG(to url: URL) throws {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try data.write(to: url)
    }
}

private final class RecordingSmokeTransport: LocalHTTPModelTransport, @unchecked Sendable {
    private(set) var request: URLRequest?

    func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse {
        self.request = request
        let content = #"{"signals":[{"kind":"focus","score":0.91,"confidence":0.82}]}"#
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [
                ["message": ["content": content]]
            ]
        ])
        return LocalHTTPModelHTTPResponse(statusCode: 200, data: body)
    }
}
