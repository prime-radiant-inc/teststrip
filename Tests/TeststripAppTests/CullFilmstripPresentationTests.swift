import XCTest
import TeststripCore
@testable import TeststripApp

final class CullFilmstripPresentationTests: XCTestCase {
    // MARK: - Triple counter (status bar)

    func testTripleCounterTextForMidStackSelection() {
        let assets = Self.assets(count: 5)
        let stacks = [
            AssetStack(assetIDs: [assets[0].id, assets[1].id, assets[2].id]),
            AssetStack(assetIDs: [assets[3].id, assets[4].id])
        ]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: assets[1].id)

        XCTAssertEqual(presentation.tripleCounterText, "2 of 5 · stack 1 of 2 · frame 2 of 3")
    }

    // A standalone is a stack of one, so "frame 1 of 1" carries no
    // information — the frame segment is dropped entirely.
    func testTripleCounterTextOmitsFrameSegmentForStandalone() {
        let assets = Self.assets(count: 3)
        let stacks = [
            AssetStack(assetIDs: [assets[0].id]),
            AssetStack(assetIDs: [assets[1].id]),
            AssetStack(assetIDs: [assets[2].id])
        ]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: assets[1].id)

        XCTAssertEqual(presentation.tripleCounterText, "2 of 3 · stack 2 of 3")
    }

    func testTripleCounterTextWithoutSelectionFallsBackToCount() {
        let assets = Self.assets(count: 5)
        let stacks = [AssetStack(assetIDs: assets.map(\.id))]

        let presentation = CullFilmstripPresentation(assets: assets, stacks: stacks, selectedAssetID: nil)

        XCTAssertEqual(presentation.tripleCounterText, "5 frames")
    }

    // Persona-7 count drift: with a 130-photo catalog and a 120-asset loaded
    // page, the counter must use the true frame number and total, not the
    // loaded window's size.
    func testTripleCounterTextUsesCatalogTotalWhenLoadedPageIsAWindow() {
        let assets = Self.assets(count: 5)
        let stacks = [AssetStack(assetIDs: assets.map(\.id))]

        let presentation = CullFilmstripPresentation(
            assets: assets,
            stacks: stacks,
            selectedAssetID: assets[1].id,
            frameNumberOffset: 120,
            totalFrameCount: 130
        )

        XCTAssertEqual(presentation.tripleCounterText, "122 of 130 · stack 1 of 1 · frame 2 of 5")
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
