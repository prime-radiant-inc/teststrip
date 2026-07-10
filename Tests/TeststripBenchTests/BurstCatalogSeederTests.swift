import TeststripCore
import XCTest

@testable import TeststripBench

final class BurstCatalogSeederTests: XCTestCase {
    func testSeedBurstCatalogCommandParsesDirectory() throws {
        let command = BenchmarkCommand.parse(["TeststripBench", "seed-burst-catalog", "/tmp/burst"])
        XCTAssertEqual(
            command,
            .seedBurstCatalog(applicationSupportDirectory: URL(fileURLWithPath: "/tmp/burst"))
        )
    }

    func testBurstLayoutOffsetsGroupWithinTwoSecondsAndSeparateAcrossGroups() {
        let offsets = BurstFixtureLayout.captureOffsets()

        XCTAssertEqual(offsets.count, BurstFixtureLayout.totalAssetCount)
        // Within a group, consecutive frames sit inside the 2s auto-stack gap;
        // group boundaries and singles sit far outside it.
        var index = 0
        for frameCount in BurstFixtureLayout.burstFrameCounts {
            for frame in 1..<frameCount {
                XCTAssertLessThanOrEqual(
                    offsets[index + frame] - offsets[index + frame - 1],
                    AssetStackBuilder.defaultMaximumCaptureGap
                )
            }
            index += frameCount
        }
        for later in (offsets.count - BurstFixtureLayout.singleCount)..<offsets.count {
            XCTAssertGreaterThan(
                offsets[later] - offsets[later - 1],
                AssetStackBuilder.defaultMaximumCaptureGap
            )
        }
    }

    func testSeededBurstCatalogYieldsAutoGroupableStacks() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try SmokeCatalogSeeder(
            applicationSupportDirectory: directory,
            count: BurstFixtureLayout.totalAssetCount,
            captureOffsets: BurstFixtureLayout.captureOffsets()
        ).run()
        XCTAssertEqual(result.assetCount, BurstFixtureLayout.totalAssetCount)

        // Assert through the same path the app uses: load the catalog assets
        // in import order and group them with AssetStackBuilder's default 2s
        // capture gap (AppModel.candidateStackMaximumCaptureGap is also 2s).
        let database = try CatalogDatabase.open(at: result.catalogURL)
        let repository = CatalogRepository(database: database)
        let assets = try repository.allAssets(
            limit: BurstFixtureLayout.totalAssetCount,
            sort: .importOrder
        )
        let stacks = AssetStackBuilder().stacks(from: assets)

        let multiFrameSizes = stacks.filter { $0.assetIDs.count > 1 }.map { $0.assetIDs.count }
        XCTAssertEqual(multiFrameSizes, BurstFixtureLayout.burstFrameCounts)
        XCTAssertEqual(
            stacks.filter { $0.assetIDs.count == 1 }.count,
            BurstFixtureLayout.singleCount
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-burst-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
