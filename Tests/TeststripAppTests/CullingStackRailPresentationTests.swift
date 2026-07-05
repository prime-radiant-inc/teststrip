import XCTest
import TeststripCore
@testable import TeststripApp

final class CullingStackRailPresentationTests: XCTestCase {
    func testShowsSelectedBurstStackPositionAndRationale() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8)),
            makeAsset(id: "other", path: "/Photos/Other/other.cr2", capturedAt: capturedAt.addingTimeInterval(2))
        ]

        let presentation = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.titleText, "Stack 1 of 2")
        XCTAssertEqual(presentation.positionText, "Frame 2 of 3")
        XCTAssertEqual(presentation.rationaleText, "Same folder, captured within 2s")
        XCTAssertEqual(presentation.keepActionTitle, "Keep frame 2 · cut 2")
        XCTAssertEqual(presentation.keepActionHelp, "Keep selected frame and reject stack alternates")
        XCTAssertEqual(presentation.items.map(\.assetID), assets[0..<3].map(\.id))
        XCTAssertEqual(presentation.items.map(\.label), ["1", "2", "3"])
        XCTAssertEqual(presentation.items.map(\.isSelected), [false, true, false])
    }

    func testActionsKeepPrimaryBehaviorSeparateWhenNoStackRankingSignalsExist() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))
        ]

        let presentation = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        let actions = presentation.actions
        XCTAssertEqual(actions.map(\.title), ["Keep frame 2 · cut 2", "Keep top 2", "Keep all 3"])
        XCTAssertEqual(actions.map(\.isEnabled), [true, false, false])
        XCTAssertEqual(actions.map(\.liveMockupPlaceholder), [nil, .cullingStackCull, .cullingStackCull])
        XCTAssertEqual(actions[0].help, "Keep selected frame and reject stack alternates")
        XCTAssertTrue(actions[1].help.localizedCaseInsensitiveContains("ranking"))
        XCTAssertTrue(actions[2].help.localizedCaseInsensitiveContains("unchanged"))
    }

    func testRecommendedActionUsesPersistedQualitySignals() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))
        ]
        let alternateID = AssetID(rawValue: "alternate")

        let presentation = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            evaluationSignalsByAssetID: [
                AssetID(rawValue: "selected"): [
                    signal(assetID: AssetID(rawValue: "selected"), kind: .focus, score: 0.62)
                ],
                alternateID: [
                    signal(assetID: alternateID, kind: .focus, score: 0.94)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, false, true])
        XCTAssertEqual(presentation.actions.map(\.title), ["Keep frame 2 · cut 2", "Keep recommended 3", "Keep all 3"])
        XCTAssertEqual(presentation.actions.map(\.isEnabled), [true, true, false])
        XCTAssertEqual(presentation.actions.map(\.liveMockupPlaceholder), [nil, nil, .cullingStackCull])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternateID))
        XCTAssertTrue(presentation.actions[1].help.localizedCaseInsensitiveContains("focus"))
    }

    func testHidesForSingletonSelection() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let asset = makeAsset(id: "single", path: "/Photos/Job/single.cr2", capturedAt: capturedAt)

        let presentation = CullingStackRailPresentation(
            assets: [asset],
            selectedAssetID: asset.id,
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertFalse(presentation.isVisible)
        XCTAssertEqual(presentation.items, [])
    }

    func testHidesWhenSelectionIsMissing() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let asset = makeAsset(id: "single", path: "/Photos/Job/single.cr2", capturedAt: capturedAt)

        let presentation = CullingStackRailPresentation(
            assets: [asset],
            selectedAssetID: AssetID(rawValue: "missing"),
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertFalse(presentation.isVisible)
        XCTAssertEqual(presentation.items, [])
    }

    private func makeAsset(id: String, path: String, capturedAt: Date?) -> Asset {
        let technicalMetadata = capturedAt.map { date in
            AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: date,
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        }
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: capturedAt ?? Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata
        )
    }

    private func signal(assetID: AssetID, kind: EvaluationKind, score: Double) -> EvaluationSignal {
        EvaluationSignal(
            assetID: assetID,
            kind: kind,
            value: .score(score),
            confidence: 0.9,
            provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
        )
    }
}
