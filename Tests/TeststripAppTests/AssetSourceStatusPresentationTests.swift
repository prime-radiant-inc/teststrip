import XCTest
import TeststripCore
@testable import TeststripApp

final class AssetSourceStatusPresentationTests: XCTestCase {
    func testOnlineAssetsDoNotShowSourceWarning() {
        XCTAssertNil(AssetSourceStatusPresentation.presentation(for: .online))
    }

    func testUnavailableSourceWarningsUsePhotographerReadableLabels() throws {
        XCTAssertEqual(
            AssetSourceStatusPresentation.presentation(for: .offline),
            AssetSourceStatusPresentation(
                title: "Offline",
                detail: "Original offline; cached previews only",
                systemImage: "externaldrive.badge.xmark"
            )
        )
        XCTAssertEqual(
            AssetSourceStatusPresentation.presentation(for: .missing),
            AssetSourceStatusPresentation(
                title: "Missing",
                detail: "Original missing; cached previews only",
                systemImage: "photo.badge.exclamationmark"
            )
        )
        XCTAssertEqual(
            AssetSourceStatusPresentation.presentation(for: .moved),
            AssetSourceStatusPresentation(
                title: "Moved",
                detail: "Original moved; cached previews only",
                systemImage: "arrowshape.turn.up.right"
            )
        )
        XCTAssertEqual(
            AssetSourceStatusPresentation.presentation(for: .stale),
            AssetSourceStatusPresentation(
                title: "Stale",
                detail: "Original changed on disk",
                systemImage: "clock.badge.exclamationmark"
            )
        )
    }
}
