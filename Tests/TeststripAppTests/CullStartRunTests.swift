import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 4: `startCullRun()` is a thin convenience that starts a cull run
// without a custom name, and `cullStartCardPresentation` provides batch stats
// for the ⌘R start card.
final class CullStartRunTests: XCTestCase {
    func testStartCullRunBeginsSessionAndSwitchesToLoupe() throws {
        let assets = (0..<5).map { index in
            Self.asset(id: "start-\(index)")
        }
        let (model, _) = try makeModelWithCatalogAssets(
            named: "start-cull-run",
            assets: assets
        )

        let session = try model.startCullRun()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty, "startCullRun should use a default session name")
    }

    func testCullStartCardPresentationReportsPhotoAndStackCounts() throws {
        let assets = (0..<4).map { index in
            Self.asset(id: "card-\(index)")
        }
        let (model, _) = try makeModelWithCatalogAssets(
            named: "start-card",
            assets: assets
        )

        let card = model.cullStartCardPresentation

        XCTAssertEqual(card.photoCount, 4)
        XCTAssertEqual(card.stackCount, 0, "standalone photos produce no multi-frame stacks")
        XCTAssertEqual(card.autoAdvanceEnabled, model.cullAutoAdvanceEnabled)
        XCTAssertEqual(card.landOnRecommended, model.cullLandOnRecommendedFrame)
    }

    // MARK: - Fixtures

    private static func asset(id: String) -> Asset {
        let metadata = AssetMetadata()
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata
        )
    }

}
