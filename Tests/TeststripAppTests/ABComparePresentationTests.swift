import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class ABComparePresentationTests: XCTestCase {
    func testPairsAnchorWithRecommendedContender() {
        let a = asset("a")
        let b = asset("b")
        let c = asset("c")
        let presentation = ABComparePresentation(
            assets: [a, b, c],
            selectedAssetID: a.id,
            recommendedAssetID: c.id
        )

        XCTAssertEqual(presentation.primaryAsset?.id, a.id)
        XCTAssertEqual(presentation.contenderAsset?.id, c.id)
        XCTAssertTrue(presentation.canCompare)
    }

    func testExplicitOverrideWinsOverRecommendation() {
        let a = asset("a")
        let b = asset("b")
        let c = asset("c")
        let presentation = ABComparePresentation(
            assets: [a, b, c],
            selectedAssetID: a.id,
            recommendedAssetID: c.id,
            contenderOverrideID: b.id
        )

        XCTAssertEqual(presentation.contenderAsset?.id, b.id)
    }

    func testFallsBackToNextNeighborWhenNoRecommendation() {
        let a = asset("a")
        let b = asset("b")
        let presentation = ABComparePresentation(
            assets: [a, b],
            selectedAssetID: a.id
        )

        XCTAssertEqual(presentation.contenderAsset?.id, b.id)
    }

    func testUsesPreviousNeighborWhenAnchorIsLastFrame() {
        let a = asset("a")
        let b = asset("b")
        let presentation = ABComparePresentation(
            assets: [a, b],
            selectedAssetID: b.id
        )

        XCTAssertEqual(presentation.primaryAsset?.id, b.id)
        XCTAssertEqual(presentation.contenderAsset?.id, a.id)
    }

    func testSkipsRecommendationEqualToAnchorAndUsesNeighbor() {
        let a = asset("a")
        let b = asset("b")
        let presentation = ABComparePresentation(
            assets: [a, b],
            selectedAssetID: a.id,
            recommendedAssetID: a.id
        )

        XCTAssertEqual(presentation.contenderAsset?.id, b.id)
    }

    func testCannotCompareWithASingleFrame() {
        let a = asset("a")
        let presentation = ABComparePresentation(assets: [a], selectedAssetID: a.id)

        XCTAssertEqual(presentation.primaryAsset?.id, a.id)
        XCTAssertNil(presentation.contenderAsset)
        XCTAssertFalse(presentation.canCompare)
    }

    private func asset(_ id: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }
}
