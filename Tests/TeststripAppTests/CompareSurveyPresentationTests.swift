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
        XCTAssertEqual(presentation.orderedAssets.map(\.id), [assets[1].id, assets[0].id, assets[2].id])
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

    func testDecisionBadgesUseRealMetadataWithoutClaimingBest() {
        let primary = makeAsset(id: "primary")
        let picked = makeAsset(id: "picked", metadata: AssetMetadata(rating: 5, colorLabel: .red, flag: .pick))
        let rejected = makeAsset(id: "rejected", metadata: AssetMetadata(flag: .reject))
        let rated = makeAsset(id: "rated", metadata: AssetMetadata(rating: 4))
        let labeled = makeAsset(id: "labeled", metadata: AssetMetadata(colorLabel: .blue))
        let unreviewed = makeAsset(id: "unreviewed")
        let presentation = CompareSurveyPresentation(
            assets: [primary, picked, rejected, rated, labeled, unreviewed],
            selectedAssetID: primary.id
        )

        XCTAssertEqual(presentation.decisionBadges(for: primary), [
            CompareDecisionBadge(text: "PRIMARY", tone: .primary)
        ])
        XCTAssertEqual(presentation.decisionBadges(for: picked), [
            CompareDecisionBadge(text: "PICKED", tone: .positive)
        ])
        XCTAssertEqual(presentation.decisionBadges(for: rejected), [
            CompareDecisionBadge(text: "REJECTED", tone: .destructive)
        ])
        XCTAssertEqual(presentation.decisionBadges(for: rated), [
            CompareDecisionBadge(text: "4 STAR", tone: .rating)
        ])
        XCTAssertEqual(presentation.decisionBadges(for: labeled), [
            CompareDecisionBadge(text: "BLUE", tone: .label)
        ])
        XCTAssertEqual(presentation.decisionBadges(for: unreviewed), [])
    }

    func testPrimaryBadgeCombinesWithActualFlagButNotWithRatingOrLabel() {
        let primary = makeAsset(id: "primary", metadata: AssetMetadata(rating: 5, colorLabel: .red, flag: .pick))
        let presentation = CompareSurveyPresentation(assets: [primary], selectedAssetID: primary.id)

        XCTAssertEqual(presentation.decisionBadges(for: primary), [
            CompareDecisionBadge(text: "PRIMARY", tone: .primary),
            CompareDecisionBadge(text: "PICKED", tone: .positive)
        ])
    }

    func testDisabledGroupActionTextDoesNotOverstateStackSupport() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        XCTAssertEqual(
            CompareSurveyPresentation(assets: assets, selectedAssetID: assets[0].id).disabledGroupActionText,
            "Keep primary · reject 2"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(assets: [assets[0]], selectedAssetID: assets[0].id).disabledGroupActionText,
            "Keep primary"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(assets: [], selectedAssetID: nil).disabledGroupActionText,
            "No group action"
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
