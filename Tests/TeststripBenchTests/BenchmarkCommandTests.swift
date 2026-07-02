import XCTest
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

    func testDeferredImportBenchmarkCatalogsAssetsAndQueuesPreviewWork() throws {
        let root = try makeTemporaryDirectory(named: "deferred-import-benchmark")

        let result = try ImportDeferredBenchmark(count: 250, root: root).run()

        XCTAssertEqual(result.importedAssetCount, 250)
        XCTAssertEqual(result.catalogAssetCount, 250)
        XCTAssertEqual(result.pendingPreviewCount, 250)
        XCTAssertLessThanOrEqual(result.progressEventCount, 8)
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
