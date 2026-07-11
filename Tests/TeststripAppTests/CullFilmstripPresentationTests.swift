import XCTest
import TeststripCore
@testable import TeststripApp

final class CullFilmstripPresentationTests: XCTestCase {
    func testDividersAppearExactlyBetweenStacks() {
        let assets = Self.assets(count: 5)
        let stacks = [
            AssetStack(assetIDs: [assets[0].id, assets[1].id]),
            AssetStack(assetIDs: [assets[2].id]),
            AssetStack(assetIDs: [assets[3].id, assets[4].id])
        ]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: nil)

        XCTAssertEqual(presentation.items, [
            .frame(assets[0].id),
            .frame(assets[1].id),
            .stackDivider,
            .frame(assets[2].id),
            .stackDivider,
            .frame(assets[3].id),
            .frame(assets[4].id)
        ])
    }

    func testNoDividerAtStartOrEndOrWithinAStack() {
        let assets = Self.assets(count: 3)
        let stacks = [AssetStack(assetIDs: assets.map(\.id))]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: nil)

        XCTAssertEqual(presentation.items, assets.map { CullFilmstripPresentation.Item.frame($0.id) })
        XCTAssertFalse(presentation.items.contains(.stackDivider))
    }

    func testSingleStackAssetsProduceNoDividers() {
        let assets = Self.assets(count: 4)
        let stacks = assets.map { AssetStack(assetIDs: [$0.id]) }

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: nil)

        XCTAssertEqual(presentation.items.filter { $0 == .stackDivider }.count, 3)
    }

    func testPositionTextReflectsFrameAndStackPosition() {
        let assets = Self.assets(count: 5)
        let stacks = [
            AssetStack(assetIDs: [assets[0].id, assets[1].id]),
            AssetStack(assetIDs: [assets[2].id]),
            AssetStack(assetIDs: [assets[3].id, assets[4].id])
        ]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: assets[3].id)

        XCTAssertEqual(presentation.positionText, "frame 4 / 5 · stack 3 / 3")
    }

    func testPositionTextWithoutSelectionFallsBackToCount() {
        let assets = Self.assets(count: 5)
        let stacks = [AssetStack(assetIDs: assets.map(\.id))]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: nil)

        XCTAssertEqual(presentation.positionText, "5 frames")
    }

    func testPositionTextWithEmptyAssets() {
        let presentation = CullFilmstripPresentation(assets: [], stacks: [], selectedAssetID: nil)

        XCTAssertEqual(presentation.positionText, "0 frames")
    }

    // MARK: - Toast

    func testToastTextForRejectDecision() {
        let feedback = CullingMetadataDecisionFeedback(
            assetID: AssetID(rawValue: "a"),
            filename: "DSCF1023.RAF",
            command: .reject,
            decisionText: "Rejected"
        )

        let toast = CullDecisionToastPresentation(feedback: feedback)

        XCTAssertEqual(toast.text, "✕ DSCF1023.RAF rejected — ⌘Z undoes")
    }

    func testToastTextForPickDecision() {
        let feedback = CullingMetadataDecisionFeedback(
            assetID: AssetID(rawValue: "a"),
            filename: "DSCF1024.RAF",
            command: .pick,
            decisionText: "Picked"
        )

        let toast = CullDecisionToastPresentation(feedback: feedback)

        XCTAssertEqual(toast.text, "✓ DSCF1024.RAF picked — ⌘Z undoes")
    }

    func testToastTextForRatingDecision() {
        let feedback = CullingMetadataDecisionFeedback(
            assetID: AssetID(rawValue: "a"),
            filename: "DSCF1025.RAF",
            command: .rating(3),
            decisionText: "Rated 3"
        )

        let toast = CullDecisionToastPresentation(feedback: feedback)

        XCTAssertEqual(toast.text, "★ DSCF1025.RAF rated 3 — ⌘Z undoes")
    }

    func testToastTextForClearedFlagDecision() {
        let feedback = CullingMetadataDecisionFeedback(
            assetID: AssetID(rawValue: "a"),
            filename: "DSCF1026.RAF",
            command: .clearFlag,
            decisionText: "Cleared flag"
        )

        let toast = CullDecisionToastPresentation(feedback: feedback)

        XCTAssertEqual(toast.text, "○ DSCF1026.RAF cleared flag — ⌘Z undoes")
    }

    func testToastTextForColorLabelDecision() {
        let feedback = CullingMetadataDecisionFeedback(
            assetID: AssetID(rawValue: "a"),
            filename: "DSCF1027.RAF",
            command: .colorLabel(.red),
            decisionText: "Red label"
        )

        let toast = CullDecisionToastPresentation(feedback: feedback)

        XCTAssertEqual(toast.text, "● DSCF1027.RAF red label — ⌘Z undoes")
    }

    private static func assets(count: Int) -> [Asset] {
        (0..<count).map { index in
            Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/Photos/asset-\(index).jpg"),
                volumeIdentifier: nil,
                fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
                availability: .online,
                metadata: AssetMetadata()
            )
        }
    }
}
