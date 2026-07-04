import XCTest
import TeststripCore
@testable import TeststripApp

final class CompareSurveyPresentationTests: XCTestCase {
    func testSelectedAssetBecomesPrimaryAndAlternatesStayInCatalogOrder() {
        let assets = [
            makeAsset(id: "first"),
            makeAsset(id: "selected"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[1].id
        )

        XCTAssertEqual(presentation.primaryAsset?.id, assets[1].id)
        XCTAssertEqual(presentation.alternateAssets.map(\.id), [assets[0].id, assets[2].id])
        XCTAssertEqual(presentation.framePositionText, "Frame 2 of 3")
        XCTAssertEqual(presentation.groupCountText, "3 frames")
        XCTAssertEqual(presentation.recommendationText, "Suggests: keep 1 · reject 2")
    }

    func testFirstAssetBecomesPrimaryWhenSelectionIsOutsideCompareSet() {
        let assets = [
            makeAsset(id: "first"),
            makeAsset(id: "second")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "outside")
        )

        XCTAssertEqual(presentation.primaryAsset?.id, assets[0].id)
        XCTAssertEqual(presentation.alternateAssets.map(\.id), [assets[1].id])
        XCTAssertEqual(presentation.framePositionText, "Frame 1 of 2")
    }

    func testEmptyCompareSetIsSafe() {
        let presentation = CompareSurveyPresentation(assets: [], selectedAssetID: nil)

        XCTAssertNil(presentation.primaryAsset)
        XCTAssertEqual(presentation.alternateAssets, [])
        XCTAssertNil(presentation.framePositionText)
        XCTAssertEqual(presentation.groupCountText, "No frames")
        XCTAssertEqual(presentation.recommendationText, "No comparison set")
        XCTAssertEqual(presentation.primaryDecisionText, "No frame selected")
    }

    func testPrimaryDecisionTextSummarizesHumanMetadata() {
        XCTAssertEqual(
            CompareSurveyPresentation(
                assets: [makeAsset(id: "pick", metadata: AssetMetadata(flag: .pick))],
                selectedAssetID: nil
            ).primaryDecisionText,
            "Picked"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(
                assets: [makeAsset(id: "reject", metadata: AssetMetadata(flag: .reject))],
                selectedAssetID: nil
            ).primaryDecisionText,
            "Rejected"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(
                assets: [makeAsset(id: "rated", metadata: AssetMetadata(rating: 4))],
                selectedAssetID: nil
            ).primaryDecisionText,
            "4 stars"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(
                assets: [makeAsset(id: "color", metadata: AssetMetadata(colorLabel: .green))],
                selectedAssetID: nil
            ).primaryDecisionText,
            "Green label"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(
                assets: [makeAsset(id: "unreviewed")],
                selectedAssetID: nil
            ).primaryDecisionText,
            "Unreviewed"
        )
    }

    private func makeAsset(
        id: String,
        metadata: AssetMetadata = AssetMetadata()
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 3000,
                pixelHeight: 2000,
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        )
    }
}
