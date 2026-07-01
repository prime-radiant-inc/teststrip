import Foundation
import XCTest
import TeststripCore

final class PreviewSchedulerTests: XCTestCase {
    func testPreviewPublicAPISupportsExplicitConstruction() {
        let assetID = AssetID(rawValue: "asset-4")

        let key = PreviewCacheKey(assetID: assetID, level: .medium)
        XCTAssertEqual(key.assetID, assetID)
        XCTAssertEqual(key.level, .medium)

        let request = PreviewRequest(assetID: assetID, level: .large, priority: .visible)
        XCTAssertEqual(request.assetID, assetID)
        XCTAssertEqual(request.level, .large)
        XCTAssertEqual(request.priority, .visible)
    }

    func testPreviewCacheEncodesUnsafeAssetIDAsSinglePathComponent() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("teststrip-preview-cache", isDirectory: true)
        let cache = PreviewCache(root: root)
        let key = PreviewCacheKey(assetID: AssetID(rawValue: "../outside/path"), level: .grid)

        let url = cache.url(for: key).standardizedFileURL
        let standardizedRootPath = root.standardizedFileURL.path
        XCTAssertTrue(url.path.hasPrefix(standardizedRootPath + "/"))

        guard url.path.hasPrefix(standardizedRootPath + "/") else { return }

        let relativePath = String(url.path.dropFirst(standardizedRootPath.count + 1))
        let components = relativePath.split(separator: "/").map(String.init)
        XCTAssertEqual(components.count, 2)
        XCTAssertFalse(components[0].contains(".."))
        XCTAssertNotEqual(components[0], "outside")
        XCTAssertNotEqual(components[0], "path")
        XCTAssertEqual(components[1], "grid.jpg")
    }

    func testPreviewCacheKeepsDistinctUnsafeAndLiteralIDsSeparate() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("teststrip-preview-cache", isDirectory: true)
        let cache = PreviewCache(root: root)
        let unsafeKey = PreviewCacheKey(assetID: AssetID(rawValue: "a/b"), level: .grid)
        let literalKey = PreviewCacheKey(assetID: AssetID(rawValue: "a_2Fb"), level: .grid)

        let unsafeDirectory = cache.url(for: unsafeKey)
            .deletingLastPathComponent()
            .standardizedFileURL
        let literalDirectory = cache.url(for: literalKey)
            .deletingLastPathComponent()
            .standardizedFileURL

        XCTAssertNotEqual(unsafeDirectory, literalDirectory)
    }

    func testPreviewCacheKeepsEmptyIDSeparateFromLiteralFallbackName() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("teststrip-preview-cache", isDirectory: true)
        let cache = PreviewCache(root: root)
        let emptyKey = PreviewCacheKey(assetID: AssetID(rawValue: ""), level: .grid)
        let literalKey = PreviewCacheKey(assetID: AssetID(rawValue: "asset-cbf29ce484222325"), level: .grid)

        let emptyDirectory = cache.url(for: emptyKey)
            .deletingLastPathComponent()
            .standardizedFileURL
        let literalDirectory = cache.url(for: literalKey)
            .deletingLastPathComponent()
            .standardizedFileURL

        XCTAssertNotEqual(emptyDirectory, literalDirectory)
    }

    func testVisibleLoupeRequestPromotesToLargePreview() {
        let scheduler = PreviewScheduler()
        let request = scheduler.request(
            assetID: AssetID(rawValue: "asset-1"),
            context: .loupe(isVisible: true, requestedFullResolution: false)
        )

        XCTAssertEqual(request.level, .large)
        XCTAssertEqual(request.priority, .visible)
    }

    func testGridPrefetchUsesGridLevelWithNearbyPriority() {
        let scheduler = PreviewScheduler()
        let request = scheduler.request(
            assetID: AssetID(rawValue: "asset-2"),
            context: .grid(distanceFromViewport: 12)
        )

        XCTAssertEqual(request.level, .grid)
        XCTAssertEqual(request.priority, .nearby)
    }

    func testFullResolutionOnlyWhenRequested() {
        let scheduler = PreviewScheduler()
        let request = scheduler.request(
            assetID: AssetID(rawValue: "asset-3"),
            context: .loupe(isVisible: true, requestedFullResolution: true)
        )

        XCTAssertEqual(request.level, .original)
    }
}
