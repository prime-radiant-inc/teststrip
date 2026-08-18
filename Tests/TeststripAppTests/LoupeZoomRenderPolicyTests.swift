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

    func testFullResolutionNotRequiredWhenCachedLevelCoversAtScale() {
        // Large preview (3200px max) covering a 6000px asset at displayScale 2:
        // The loupe shows at most 3200/2 = 1600pt wide. At scale 2.0, the fitted
        // image is ~1000pt, so displaySize = 2000pt < 3200. No original needed.
        XCTAssertFalse(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .large,
            assetMaxPixelDimension: 6000,
            displayScale: 2.0,
            loupeScale: 2.0,
            fittedDisplayWidth: 1000
        ))
    }

    func testFullResolutionRequiredWhenScaleExceedsCachedLevel() {
        // Large preview (3200px) for a 12000px asset at displayScale 1:
        // At maxScale, displaySize = 12000pt >> 3200px. Original needed.
        XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: .large,
            assetMaxPixelDimension: 12000,
            displayScale: 1.0,
            loupeScale: 12.0,
            fittedDisplayWidth: 1000
        ))
    }

    func testFullResolutionRequiredWhenNoCachedLevel() {
        XCTAssertTrue(LoupeZoomRenderPolicy.fullResolutionIsRequired(
            cachedLevel: nil,
            assetMaxPixelDimension: 6000,
            displayScale: 2.0,
            loupeScale: 3.0,
            fittedDisplayWidth: 1000
        ))
    }
}
