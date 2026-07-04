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

    func testDecisionSummaryPrefersFlagThenRatingThenColorLabel() {
        let pick = makeAsset(id: "pick", metadata: AssetMetadata(rating: 5, colorLabel: .red, flag: .pick))
        let reject = makeAsset(id: "reject", metadata: AssetMetadata(rating: 5, colorLabel: .yellow, flag: .reject))
        let rated = makeAsset(id: "rated", metadata: AssetMetadata(rating: 4, colorLabel: .green))
        let labeled = makeAsset(id: "labeled", metadata: AssetMetadata(colorLabel: .blue))
        let unreviewed = makeAsset(id: "unreviewed")

        XCTAssertEqual(CompareSurveyPresentation.decisionSummary(for: pick), "Picked")
        XCTAssertEqual(CompareSurveyPresentation.decisionSummary(for: reject), "Rejected")
        XCTAssertEqual(CompareSurveyPresentation.decisionSummary(for: rated), "4 stars")
        XCTAssertEqual(CompareSurveyPresentation.decisionSummary(for: labeled), "Blue label")
        XCTAssertEqual(CompareSurveyPresentation.decisionSummary(for: unreviewed), "Unreviewed")
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
