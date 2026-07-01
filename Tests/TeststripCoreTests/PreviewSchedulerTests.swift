import XCTest
@testable import TeststripCore

final class PreviewSchedulerTests: XCTestCase {
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
