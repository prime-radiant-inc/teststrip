import Foundation
import XCTest
@testable import TeststripCore

final class PreviewCacheTests: XCTestCase {
    func testDeleteAllRemovesEveryCachedLevelForAnAsset() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-delete-all")
        let cache = PreviewCache(root: directory)
        let assetID = AssetID(rawValue: "asset-1")
        let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
        try FileManager.default.createDirectory(at: gridURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("grid".utf8).write(to: gridURL)
        try Data("large".utf8).write(to: largeURL)

        try cache.deleteAll(for: assetID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: gridURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: largeURL.path))
    }

    func testDeleteAllForUncachedAssetDoesNotThrow() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-delete-all-missing")
        let cache = PreviewCache(root: directory)

        XCTAssertNoThrow(try cache.deleteAll(for: AssetID(rawValue: "never-cached")))
    }

    func testMicroAndGridMapToSamePhysicalFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping")
        let cache = PreviewCache(root: directory)
        let assetID = AssetID(rawValue: "asset-1")

        let microURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .micro))
        let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))

        XCTAssertEqual(microURL, gridURL)
        XCTAssertEqual(microURL.pathExtension, "heic")
        XCTAssertEqual(microURL.lastPathComponent, "grid.heic")
    }

    func testMediumAndLargeMapToSamePhysicalFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping-medium")
        let cache = PreviewCache(root: directory)
        let assetID = AssetID(rawValue: "asset-1")

        let mediumURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .medium))
        let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))

        XCTAssertEqual(mediumURL, largeURL)
        XCTAssertEqual(mediumURL.pathExtension, "heic")
        XCTAssertEqual(mediumURL.lastPathComponent, "large.heic")
    }

    func testOriginalMapsToFullHeic() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping-original")
        let cache = PreviewCache(root: directory)
        let assetID = AssetID(rawValue: "asset-1")

        let originalURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .original))

        XCTAssertEqual(originalURL.pathExtension, "heic")
        XCTAssertEqual(originalURL.lastPathComponent, "full.heic")
    }

    func testThreePhysicalFilesAreDistinct() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-cache-mapping-distinct")
        let cache = PreviewCache(root: directory)
        let assetID = AssetID(rawValue: "asset-1")

        let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
        let fullURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .original))

        XCTAssertNotEqual(gridURL, largeURL)
        XCTAssertNotEqual(gridURL, fullURL)
        XCTAssertNotEqual(largeURL, fullURL)
    }

    func testAllLevelsServedByExpandsEachLevelToItsCoLocatedSiblings() {
        // grid.heic serves both .micro and .grid; large.heic serves .medium
        // and .large; full.heic serves only .original.
        XCTAssertEqual(PreviewCache.allLevelsServedBy([.micro]), [.micro, .grid])
        XCTAssertEqual(PreviewCache.allLevelsServedBy([.grid]), [.micro, .grid])
        XCTAssertEqual(PreviewCache.allLevelsServedBy([.medium]), [.medium, .large])
        XCTAssertEqual(PreviewCache.allLevelsServedBy([.large]), [.medium, .large])
        XCTAssertEqual(PreviewCache.allLevelsServedBy([.original]), [.original])
    }

    func testAllLevelsServedByDeduplicatesAndOrdersByCaseOrder() {
        XCTAssertEqual(
            PreviewCache.allLevelsServedBy([.large, .micro, .grid, .medium, .original]),
            [.micro, .grid, .medium, .large, .original]
        )
        XCTAssertEqual(PreviewCache.allLevelsServedBy([.grid, .micro]), [.micro, .grid])
        XCTAssertEqual(PreviewCache.allLevelsServedBy([]), [])
    }
}
