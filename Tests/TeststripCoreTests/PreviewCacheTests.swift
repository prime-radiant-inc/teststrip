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
}
