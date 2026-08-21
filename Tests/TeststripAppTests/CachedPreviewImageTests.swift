import XCTest
@testable import TeststripApp

final class CachedPreviewImageTests: XCTestCase {
    func testPreviewImageTransitionRetainsImageForDifferentLevelsOfSameAsset() {
        let micro = URL(fileURLWithPath: "/Previews/asset-1/micro.heic")
        let grid = URL(fileURLWithPath: "/Previews/asset-1/grid.heic")

        XCTAssertTrue(PreviewImageTransition.shouldRetainCurrentImage(loadedURL: micro, nextURL: grid))
    }

    func testPreviewImageTransitionClearsImageForDifferentAsset() {
        let current = URL(fileURLWithPath: "/Previews/asset-1/grid.heic")
        let next = URL(fileURLWithPath: "/Previews/asset-2/grid.heic")

        XCTAssertFalse(PreviewImageTransition.shouldRetainCurrentImage(loadedURL: current, nextURL: next))
    }

    func testPreviewImageTransitionClearsImageWhenNextURLIsMissing() {
        let current = URL(fileURLWithPath: "/Previews/asset-1/grid.heic")

        XCTAssertFalse(PreviewImageTransition.shouldRetainCurrentImage(loadedURL: current, nextURL: nil))
    }
}
