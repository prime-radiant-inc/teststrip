import XCTest
import TeststripCore
@testable import TeststripApp

final class LoupeZoomRenderPolicyTests: XCTestCase {
    func testOriginalLevelCacheSatisfiesFullResolution() {
        XCTAssertFalse(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .original,
            assetMaxPixelDimension: 8000
        ))
        XCTAssertFalse(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .original,
            assetMaxPixelDimension: nil
        ))
    }

    func testBoundedLevelCoveringAssetPixelsSatisfiesFullResolution() {
        XCTAssertFalse(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .large,
            assetMaxPixelDimension: 3200
        ))
        XCTAssertFalse(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .medium,
            assetMaxPixelDimension: 1600
        ))
    }

    func testBoundedLevelSmallerThanAssetRequiresFullResolution() {
        XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .large,
            assetMaxPixelDimension: 3201
        ))
        XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .grid,
            assetMaxPixelDimension: 6000
        ))
    }

    func testUnknownAssetPixelSizeRequiresFullResolution() {
        XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .large,
            assetMaxPixelDimension: nil
        ))
    }

    func testMissingCachedPreviewRequiresFullResolution() {
        XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: nil,
            assetMaxPixelDimension: 1000
        ))
    }
}
