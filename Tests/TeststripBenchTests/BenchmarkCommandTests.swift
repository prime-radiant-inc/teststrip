import XCTest
import TeststripCore
@testable import TeststripBench

final class BenchmarkCommandTests: XCTestCase {
    func testDefaultCommandRunsCatalogScaleBenchmark() throws {
        XCTAssertEqual(BenchmarkCommand.parse(["TeststripBench"]), .catalogScale(count: 100_000))
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

    func testDeferredImportBenchmarkCatalogsAssetsAndQueuesPreviewWork() throws {
        let root = try makeTemporaryDirectory(named: "deferred-import-benchmark")

        let result = try ImportDeferredBenchmark(count: 250, root: root).run()

        XCTAssertEqual(result.importedAssetCount, 250)
        XCTAssertEqual(result.catalogAssetCount, 250)
        XCTAssertEqual(result.pendingPreviewCount, 250)
        XCTAssertLessThanOrEqual(result.progressEventCount, 8)
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
