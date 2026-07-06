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
        XCTAssertEqual(presentation.recommendationText, "No ranking yet")
    }

    func testRecommendationTextUsesPersistedQualitySignalsWhenPrimaryRanksHighest() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.96)],
                assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.78)],
                assets[2].id: [signal(assetID: assets[2].id, kind: .motionBlur, score: 0.8)]
            ]
        )

        XCTAssertEqual(presentation.recommendationText, "Suggests: keep 1 · reject 2")
    }

    func testRecommendationTextDoesNotSuggestPrimaryWhenAnotherFrameRanksHighest() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.72)],
                assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.95)]
            ]
        )

        XCTAssertEqual(presentation.recommendationText, "Top signal: frame 3 — sharpest")
        XCTAssertFalse(presentation.recommendationText.localizedCaseInsensitiveContains("suggests"))
    }

    func testGroupActionKeepsTopSignalWhenItIsNotTheSelectedPrimary() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.72)],
                assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.95)]
            ]
        )

        let actions = presentation.groupActions(canApplyPrimaryChoice: true)

        XCTAssertEqual(actions[0].title, "Keep top signal 3 · reject 2")
        XCTAssertEqual(actions[0].action, .keepRecommendedAndRejectAlternates(assets[2].id))
        XCTAssertTrue(actions[0].help.localizedCaseInsensitiveContains("top signal"))
    }

    func testEightFrameSurveyUsesFourByTwoLayout() {
        let assets = (0..<8).map { makeAsset(id: "survey-\($0)") }

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[2].id
        )

        XCTAssertEqual(presentation.surveyColumnCount, 4)
        XCTAssertEqual(presentation.surveyRowCount, 2)
        XCTAssertEqual(presentation.orderedAssets.count, 8)
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

    func testGroupActionTextNamesCurrentCompareSetWithoutOverstatingStackSupport() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        XCTAssertEqual(
            CompareSurveyPresentation(assets: assets, selectedAssetID: assets[0].id).groupActionText,
            "Keep primary · reject 2"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(assets: [assets[0]], selectedAssetID: assets[0].id).groupActionText,
            "Keep primary"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(assets: [], selectedAssetID: nil).groupActionText,
            "No group action"
        )
        XCTAssertEqual(
            CompareSurveyPresentation(assets: assets, selectedAssetID: assets[0].id).groupActionHelp,
            "Marks the current compare primary as Pick and the visible alternates as Reject"
        )
    }

    func testCandidateStackLabelDoesNotClaimDuplicateOrBestShotDetection() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            groupKind: .candidateStack
        )

        XCTAssertEqual(presentation.groupKindText, "Candidate stack")
        XCTAssertFalse(presentation.groupKindText.localizedCaseInsensitiveContains("best"))
        XCTAssertFalse(presentation.groupKindText.localizedCaseInsensitiveContains("duplicate"))
        XCTAssertFalse(presentation.groupKindText.localizedCaseInsensitiveContains("burst"))
    }

    func testGroupActionsExposeLiveKeepAllAndRemainingManualPlaceholder() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second")
        ]
        let presentation = CompareSurveyPresentation(assets: assets, selectedAssetID: assets[0].id)

        let actions = presentation.groupActions(canApplyPrimaryChoice: true)

        XCTAssertEqual(actions.map(\.title), ["Keep primary · reject 1", "Keep all", "Choose manually"])
        XCTAssertEqual(actions.map(\.isEnabled), [true, true, true])
        XCTAssertNil(actions[0].liveMockupPlaceholder)
        XCTAssertNil(actions[1].liveMockupPlaceholder)
        XCTAssertNil(actions[2].liveMockupPlaceholder)
    }

    func testFocusMetricsUseRealQualitySignalsWithoutClaimingBest() {
        let assetID = AssetID(rawValue: "quality-frame")
        let provenance = ProviderProvenance(
            provider: "local-image-metrics",
            model: "average-preview-metrics",
            version: "1",
            settingsHash: "default"
        )
        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .object, value: .label("camera"), confidence: 0.94, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .motionBlur, value: .score(0.21), confidence: 0.76, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .focus, value: .score(0.88), confidence: 0.81, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .exposure, value: .score(0.63), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Focus", "Motion blur", "Exposure"])
        XCTAssertEqual(metrics.map(\.value), ["88%", "21%", "+0.5 EV"])
        XCTAssertEqual(metrics.map(\.tone), [.positive, .positive, .neutral])
        XCTAssertFalse(metrics.contains { metric in
            [metric.title, metric.value, metric.detail].contains { $0.localizedCaseInsensitiveContains("best") }
        })
    }

    func testExposureRendersAsEVStyleDeltaWhileFocusStaysPercentage() {
        let assetID = AssetID(rawValue: "exposure-frame")
        let provenance = ProviderProvenance(
            provider: "local-image-metrics",
            model: "preview-color-focus-metrics",
            version: "1",
            settingsHash: "default"
        )

        let overexposed = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .exposure, value: .score(0.9), confidence: 1.0, provenance: provenance)
        ])
        let underexposed = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .exposure, value: .score(0.1), confidence: 1.0, provenance: provenance)
        ])
        let neutral = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .exposure, value: .score(0.5), confidence: 1.0, provenance: provenance)
        ])

        XCTAssertEqual(overexposed.map(\.value), ["+1.6 EV"])
        XCTAssertEqual(underexposed.map(\.value), ["-1.6 EV"])
        XCTAssertEqual(neutral.map(\.value), ["0.0 EV"])

        let combined = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .focus, value: .score(0.72), confidence: 0.81, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .exposure, value: .score(0.2), confidence: 1.0, provenance: provenance)
        ])
        XCTAssertEqual(combined.map(\.title), ["Focus", "Exposure"])
        XCTAssertEqual(combined.map(\.value), ["72%", "-1.2 EV"])
    }

    func testFocusMetricsIncludeLocalFramingAndAestheticScores() {
        let assetID = AssetID(rawValue: "composition-frame")
        let provenance = ProviderProvenance(
            provider: "local-image-metrics",
            model: "preview-color-focus-metrics",
            version: "1",
            settingsHash: "default"
        )

        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .aesthetics, value: .score(0.73), confidence: 0.55, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .framing, value: .score(0.81), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .focus, value: .score(0.88), confidence: 0.81, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Focus", "Framing", "Aesthetics"])
        XCTAssertEqual(metrics.map(\.value), ["88%", "81%", "73%"])
        XCTAssertEqual(metrics.map(\.tone), [.positive, .positive, .positive])
        XCTAssertFalse(metrics.contains { metric in
            [metric.title, metric.value, metric.detail].contains { $0.localizedCaseInsensitiveContains("best") }
        })
    }

    func testFocusMetricsShowNoReadWhenNoQualitySignalsExist() {
        let assetID = AssetID(rawValue: "unread-frame")
        let provenance = ProviderProvenance(
            provider: "apple-vision",
            model: "Vision-labels",
            version: "1",
            settingsHash: "default"
        )

        XCTAssertEqual(
            CompareFocusMetricPresentation.metrics(for: [
                EvaluationSignal(assetID: assetID, kind: .object, value: .label("camera"), confidence: 0.94, provenance: provenance)
            ]),
            [CompareFocusMetric(title: "No read yet", value: "Evaluate", detail: "No compare quality signals", tone: .waiting)]
        )
    }

    func testFocusMetricsIncludeEyeStateAndEyeSharpnessLanes() {
        let assetID = AssetID(rawValue: "expression-frame")
        let provenance = ProviderProvenance(
            provider: "core-image-faces",
            model: "CIDetectorFace",
            version: "1",
            settingsHash: "default"
        )

        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .focus, value: .score(0.88), confidence: 0.81, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyeSharpness, value: .score(0.74), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(1.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(1.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Focus", "Eye sharpness", "Eyes open", "Smile"])
        XCTAssertEqual(metrics.map(\.value), ["88%", "74%", "Open", "Smiling"])
        XCTAssertEqual(metrics.map(\.tone), [.positive, .positive, .positive, .neutral])
    }

    func testShutEyesAndSoftEyeLanesUseCautionTones() {
        let assetID = AssetID(rawValue: "blink-frame")
        let provenance = ProviderProvenance(
            provider: "core-image-faces",
            model: "CIDetectorFace",
            version: "1",
            settingsHash: "default"
        )

        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .eyeSharpness, value: .score(0.4), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(0.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Eye sharpness", "Eyes open", "Smile"])
        XCTAssertEqual(metrics.map(\.value), ["40%", "Shut", "No smile"])
        XCTAssertEqual(metrics.map(\.tone), [.caution, .caution, .neutral])
    }

    func testSignalBadgesFlagBestEyesClosedAndSoftFrames() {
        let best = makeAsset(id: "best")
        let blink = makeAsset(id: "blink")
        let soft = makeAsset(id: "soft")
        let presentation = CompareSurveyPresentation(
            assets: [best, blink, soft],
            selectedAssetID: best.id,
            evaluationSignalsByAssetID: [
                best.id: [
                    signal(assetID: best.id, kind: .focus, score: 0.94),
                    signal(assetID: best.id, kind: .eyesOpen, score: 1.0)
                ],
                blink.id: [
                    signal(assetID: blink.id, kind: .focus, score: 0.9),
                    signal(assetID: blink.id, kind: .eyesOpen, score: 0.0)
                ],
                soft.id: [
                    signal(assetID: soft.id, kind: .focus, score: 0.3)
                ]
            ]
        )

        XCTAssertEqual(presentation.signalBadges(for: best), [
            CompareDecisionBadge(text: "✦ BEST", tone: .best)
        ])
        XCTAssertEqual(presentation.signalBadges(for: blink), [
            CompareDecisionBadge(text: "EYES CLOSED", tone: .destructive)
        ])
        XCTAssertEqual(presentation.signalBadges(for: soft), [
            CompareDecisionBadge(text: "SOFT", tone: .destructive)
        ])
    }

    func testSignalBadgesStaySilentWithoutRankedContendersOrSignals() {
        let only = makeAsset(id: "only")
        let unread = makeAsset(id: "unread")
        let presentation = CompareSurveyPresentation(
            assets: [only, unread],
            selectedAssetID: only.id,
            evaluationSignalsByAssetID: [
                only.id: [signal(assetID: only.id, kind: .focus, score: 0.94)]
            ]
        )

        // A single ranked candidate is not a comparison; no BEST claim.
        XCTAssertEqual(presentation.signalBadges(for: only), [])
        XCTAssertEqual(presentation.signalBadges(for: unread), [])
    }

    func testRecommendationTextExplainsWhyTopSignalFrameLeads() {
        let assets = [
            makeAsset(id: "primary"),
            makeAsset(id: "second"),
            makeAsset(id: "third")
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.72)],
                assets[2].id: [
                    signal(assetID: assets[2].id, kind: .focus, score: 0.95),
                    signal(assetID: assets[2].id, kind: .eyesOpen, score: 1.0)
                ]
            ]
        )

        XCTAssertEqual(presentation.recommendationText, "Top signal: frame 3 — sharpest, eyes open")
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
