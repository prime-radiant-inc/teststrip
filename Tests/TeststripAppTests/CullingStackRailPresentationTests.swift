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
        XCTAssertEqual(actions.map(\.title), ["Keep frame 2 · cut 2", "Keep all 3"])
        XCTAssertEqual(actions.map(\.isEnabled), [true, true])
        XCTAssertEqual(actions.map(\.liveMockupPlaceholder), [nil, nil])
        XCTAssertEqual(actions[0].help, "Keep selected frame and reject stack alternates")
        XCTAssertTrue(actions[1].help.localizedCaseInsensitiveContains("keep every frame"))
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
                alternateID: [
                    signal(assetID: alternateID, kind: .focus, score: 0.94)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, false, true])
        XCTAssertEqual(presentation.actions.map(\.title), ["Keep frame 2 · cut 2", "Keep recommended 3", "Keep all 3"])
        XCTAssertEqual(presentation.actions.map(\.isEnabled), [true, true, true])
        XCTAssertEqual(presentation.actions.map(\.liveMockupPlaceholder), [nil, nil, nil])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternateID))
        XCTAssertTrue(presentation.actions[1].help.localizedCaseInsensitiveContains("focus"))
    }

    func testKeepTopActionUsesTwoHighestPersistedQualitySignals() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8)),
            makeAsset(id: "miss", path: "/Photos/Job/miss.cr2", capturedAt: capturedAt.addingTimeInterval(2.4))
        ]
        let selectedID = AssetID(rawValue: "selected")
        let alternateID = AssetID(rawValue: "alternate")

        let presentation = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: selectedID,
            evaluationSignalsByAssetID: [
                AssetID(rawValue: "lead"): [
                    signal(assetID: AssetID(rawValue: "lead"), kind: .focus, score: 0.41)
                ],
                selectedID: [
                    signal(assetID: selectedID, kind: .focus, score: 0.88)
                ],
                alternateID: [
                    signal(assetID: alternateID, kind: .focus, score: 0.94)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 3)
        )

        XCTAssertEqual(presentation.items.map(\.assetID), assets.map(\.id))
        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, false, true, false])
        XCTAssertEqual(presentation.actions.map(\.title), ["Keep frame 2 · cut 3", "Keep top 2", "Keep all 4"])
        XCTAssertEqual(presentation.actions.map(\.isEnabled), [true, true, true])
        XCTAssertEqual(presentation.actions.map(\.liveMockupPlaceholder), [nil, nil, nil])
        XCTAssertEqual(presentation.actions[1].action, .keepTopRanked([alternateID, selectedID]))
        XCTAssertTrue(presentation.actions[1].help.localizedCaseInsensitiveContains("top-ranked"))
    }

    func testTwoFrameStackWithTwoSignalsStillOffersSingleRecommendedFrame() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let selected = makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [selected, alternate],
            selectedAssetID: selected.id,
            evaluationSignalsByAssetID: [
                selected.id: [
                    signal(assetID: selected.id, kind: .focus, score: 0.78)
                ],
                alternate.id: [
                    signal(assetID: alternate.id, kind: .focus, score: 0.93)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.actions.map(\.title), ["Keep frame 1 · cut 1", "Keep recommended 2", "Keep all 2"])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternate.id))
    }

    func testFallbackStackUsesPersistedVisualSimilaritySignals() {
        let selected = makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: Date(timeIntervalSince1970: 100))
        let visuallySimilar = makeAsset(id: "visually-similar", path: "/Photos/Other/visually-similar.cr2", capturedAt: Date(timeIntervalSince1970: 600))
        let unrelated = makeAsset(id: "unrelated", path: "/Photos/Other/unrelated.cr2", capturedAt: Date(timeIntervalSince1970: 900))

        let presentation = CullingStackRailPresentation(
            assets: [selected, visuallySimilar, unrelated],
            selectedAssetID: selected.id,
            evaluationSignalsByAssetID: [
                selected.id: [
                    vectorSignal(assetID: selected.id, vector: [0.10, 0.20, 0.30])
                ],
                visuallySimilar.id: [
                    vectorSignal(assetID: visuallySimilar.id, vector: [0.11, 0.20, 0.30])
                ],
                unrelated.id: [
                    vectorSignal(assetID: unrelated.id, vector: [0.90, 0.90, 0.90])
                ]
            ]
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.items.map(\.assetID), [selected.id, visuallySimilar.id])
        XCTAssertTrue(presentation.rationaleText?.contains("Visual similarity distance") == true)
    }

    func testExplicitPersistedStackScopeDoesNotRequireLoadedTimeAdjacency() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt)
        let selected = makeAsset(id: "selected", path: "/Photos/Other/selected.cr2", capturedAt: capturedAt.addingTimeInterval(60))
        let presentation = CullingStackRailPresentation(
            assets: [lead, selected],
            selectedAssetID: selected.id,
            explicitStackScope: CullingStackScope(
                assetIDs: [lead.id, selected.id],
                stackIndex: 2,
                stackCount: 5,
                rationaleText: "Saved stack from culling session"
            ),
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.titleText, "Stack 2 of 5")
        XCTAssertEqual(presentation.positionText, "Frame 2 of 2")
        XCTAssertEqual(presentation.rationaleText, "Saved stack from culling session")
        XCTAssertEqual(presentation.keepActionTitle, "Keep frame 2 · cut 1")
        XCTAssertEqual(presentation.items.map(\.assetID), [lead.id, selected.id])
        XCTAssertEqual(presentation.items.map(\.isSelected), [false, true])
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

    private func vectorSignal(assetID: AssetID, vector: [Double], confidence: Double = 0.9) -> EvaluationSignal {
        EvaluationSignal(
            assetID: assetID,
            kind: .visualSimilarity,
            value: .vector(vector),
            confidence: confidence,
            provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
        )
    }
}
