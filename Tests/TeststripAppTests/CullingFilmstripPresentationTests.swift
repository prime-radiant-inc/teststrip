import XCTest
import TeststripCore
@testable import TeststripApp

final class CullingFilmstripPresentationTests: XCTestCase {
    func testFilmstripCentersSelectedAssetWhenPossible() {
        let assets = Self.assets(count: 20)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: assets[10].id,
            visibleLimit: 6
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[7..<13].map(\.id))
        XCTAssertEqual(presentation.positionText, "Frame 11 of 20")
    }

    func testFilmstripClampsNearBeginning() {
        let assets = Self.assets(count: 20)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: assets[1].id,
            visibleLimit: 6
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[0..<6].map(\.id))
        XCTAssertEqual(presentation.positionText, "Frame 2 of 20")
    }

    func testFilmstripClampsNearEnd() {
        let assets = Self.assets(count: 20)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: assets[19].id,
            visibleLimit: 6
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[14..<20].map(\.id))
        XCTAssertEqual(presentation.positionText, "Frame 20 of 20")
    }

    func testFilmstripFallsBackToStartWhenSelectionIsMissing() {
        let assets = Self.assets(count: 8)

        let presentation = CullingFilmstripPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "missing"),
            visibleLimit: 4
        )

        XCTAssertEqual(presentation.visibleAssets.map(\.id), assets[0..<4].map(\.id))
        XCTAssertEqual(presentation.positionText, "8 frames")
    }

    func testDecisionStateReflectsAssetFlag() {
        let picked = Self.asset(id: "picked", flag: .pick)
        let rejected = Self.asset(id: "rejected", flag: .reject)
        let undecided = Self.asset(id: "undecided", flag: nil)
        let presentation = CullingFilmstripPresentation(
            assets: [picked, rejected, undecided],
            selectedAssetID: nil
        )

        XCTAssertEqual(presentation.decisionState(for: picked), .picked)
        XCTAssertEqual(presentation.decisionState(for: rejected), .rejected)
        XCTAssertEqual(presentation.decisionState(for: undecided), .undecided)
    }

    func testOnlyRejectedDecisionStateIsDimmed() {
        XCTAssertTrue(CullingFilmstripPresentation.DecisionState.rejected.isDimmed)
        XCTAssertFalse(CullingFilmstripPresentation.DecisionState.picked.isDimmed)
        XCTAssertFalse(CullingFilmstripPresentation.DecisionState.undecided.isDimmed)
    }

    private static func assets(count: Int) -> [Asset] {
        (0..<count).map { index in
            asset(id: "asset-\(index)")
        }
    }

    private static func asset(id: String, flag: PickFlag? = nil) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(flag: flag)
        )
    }
}
