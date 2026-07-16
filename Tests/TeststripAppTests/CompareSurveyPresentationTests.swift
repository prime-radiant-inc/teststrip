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

    // A tie can't defend a single winner: the group action falls back to the
    // user-chosen primary instead of crowning one tied leader as the "top
    // signal" frame to keep.
    func testTiedGroupActionFallsBackToKeepPrimaryWithoutNamingATopSignal() {
        let primary = makeAsset(id: "tie-action-primary")
        let other = makeAsset(id: "tie-action-other")

        let presentation = CompareSurveyPresentation(
            assets: [primary, other],
            selectedAssetID: primary.id,
            evaluationSignalsByAssetID: [
                primary.id: [signal(assetID: primary.id, kind: .focus, score: 0.79)],
                other.id: [signal(assetID: other.id, kind: .focus, score: 0.80)]
            ]
        )

        let actions = presentation.groupActions(canApplyPrimaryChoice: true)

        XCTAssertNil(presentation.recommendedAssetID)
        XCTAssertEqual(presentation.groupActionText, "Keep primary · reject 1")
        XCTAssertEqual(presentation.groupActionHelp, "Marks the current compare primary as Pick and the visible alternates as Reject")
        XCTAssertEqual(actions[0].action, .keepPrimaryAndRejectAlternates)
        XCTAssertFalse(actions.contains { if case .keepRecommendedAndRejectAlternates = $0.action { return true } else { return false } })
    }

    // Same rule for the header line: under a tie no frame is the "Top
    // signal", and "Suggests: keep 1" (a claim that the primary wins) is
    // equally indefensible — the honest read is the tie itself.
    func testTiedRecommendationTextReadsTooCloseToCallInsteadOfTopSignal() {
        let primary = makeAsset(id: "tie-text-primary")
        let other = makeAsset(id: "tie-text-other")

        let presentation = CompareSurveyPresentation(
            assets: [primary, other],
            selectedAssetID: primary.id,
            evaluationSignalsByAssetID: [
                primary.id: [signal(assetID: primary.id, kind: .focus, score: 0.79)],
                other.id: [signal(assetID: other.id, kind: .focus, score: 0.80)]
            ]
        )

        XCTAssertEqual(presentation.recommendationText, "Too close to call")
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

    func testContendersOnlyModeIsUnavailableWithoutRankingSignals() {
        let assets = (0..<5).map { makeAsset(id: "no-signal-\($0)") }

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            contendersOnly: true
        )

        XCTAssertFalse(presentation.isContendersModeAvailable)
        XCTAssertFalse(presentation.isContendersOnly)
        XCTAssertEqual(presentation.orderedAssets.count, assets.count)
        XCTAssertEqual(presentation.contenderAssets, [])
    }

    func testContendersOnlyModeNarrowsToTopRankedThree() {
        let assets = (0..<5).map { makeAsset(id: "ranked-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.5)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.9)],
            assets[3].id: [signal(assetID: assets[3].id, kind: .focus, score: 0.6)],
            assets[4].id: [signal(assetID: assets[4].id, kind: .focus, score: 0.8)]
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        XCTAssertTrue(presentation.isContendersModeAvailable)
        XCTAssertTrue(presentation.isContendersOnly)
        // Ranked by focus score descending: 2 (0.9), 4 (0.8), 0 (0.7).
        XCTAssertEqual(presentation.orderedAssets.map(\.id), [assets[2].id, assets[4].id, assets[0].id])
        XCTAssertEqual(presentation.contenderAssets.map(\.id), [assets[2].id, assets[4].id, assets[0].id])
    }

    // A too-close-to-call tie can reach past the default top 3: the 4th
    // frame here sits within the tie margin of the leader, so contenders-only
    // mode must widen to include it rather than silently drop it.
    func testContendersOnlyModeWidensPastTopThreeToIncludeATiedFourthPlace() {
        let assets = (0..<5).map { makeAsset(id: "tied-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.90)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.89)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.88)],
            assets[3].id: [signal(assetID: assets[3].id, kind: .focus, score: 0.875)],
            assets[4].id: [signal(assetID: assets[4].id, kind: .focus, score: 0.50)]
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        // 0/1/2/3 are all within the 0.03 tie margin of the 0.90 leader; 4
        // (0.50) is well outside it and stays excluded.
        XCTAssertEqual(presentation.contenderAssets.map(\.id), [assets[0].id, assets[1].id, assets[2].id, assets[3].id])
    }

    func testContendersOnlyModeIsReversibleBackToFullSet() {
        let assets = (0..<5).map { makeAsset(id: "reversible-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.9)],
            assets[4].id: [signal(assetID: assets[4].id, kind: .focus, score: 0.8)]
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: false
        )

        XCTAssertTrue(presentation.isContendersModeAvailable)
        XCTAssertFalse(presentation.isContendersOnly)
        XCTAssertEqual(presentation.orderedAssets.map(\.id), assets.map(\.id))
    }

    func testContendersToggleTitleDescribesTopThreeAndFullSet() {
        let assets = (0..<5).map { makeAsset(id: "toggle-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)]
        ]

        let off = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: false
        )
        let on = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        XCTAssertEqual(off.contendersToggleTitle, "Top 3 contenders")
        XCTAssertEqual(on.contendersToggleTitle, "Full set")
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

    func testContendersKeepTopTwoActionAppearsWithThreeRankedContendersInContendersMode() {
        let assets = (0..<3).map { makeAsset(id: "keep-top-two-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.9)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.5)]
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        let action = presentation.contendersKeepTopTwoAction(canApplyPrimaryChoice: true)

        // Ranked by focus descending: 1 (0.9), 0 (0.7), 2 (0.5).
        XCTAssertEqual(action?.title, "Keep #1 & #2")
        XCTAssertEqual(action?.action, .keepTopContendersAndRejectRemaining([assets[1].id, assets[0].id]))
        XCTAssertEqual(action?.isEnabled, true)
    }

    func testContendersKeepTopTwoActionIsNilWithFewerThanThreeRankedContenders() {
        let assets = (0..<2).map { makeAsset(id: "keep-top-two-few-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.9)]
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        XCTAssertNil(presentation.contendersKeepTopTwoAction(canApplyPrimaryChoice: true))
    }

    func testContendersKeepTopTwoActionIsNilOutsideContendersMode() {
        let assets = (0..<3).map { makeAsset(id: "keep-top-two-off-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.9)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.5)]
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: false
        )

        XCTAssertNil(presentation.contendersKeepTopTwoAction(canApplyPrimaryChoice: true))
    }

    func testContendersKeepTopTwoActionRespectsCanApplyPrimaryChoice() {
        let assets = (0..<3).map { makeAsset(id: "keep-top-two-disabled-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.9)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.5)]
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        let action = presentation.contendersKeepTopTwoAction(canApplyPrimaryChoice: false)

        XCTAssertNotNil(action)
        XCTAssertEqual(action?.isEnabled, false)
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
        XCTAssertEqual(metrics.map(\.value), ["88%", "21%", "Bright +0.5"])
        XCTAssertEqual(metrics.map(\.tone), [.positive, .positive, .neutral])
        XCTAssertFalse(metrics.contains { metric in
            [metric.title, metric.value, metric.detail].contains { $0.localizedCaseInsensitiveContains("best") }
        })
    }

    func testExposureRendersAsBrightnessDeltaWhileFocusStaysPercentage() {
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

        XCTAssertEqual(overexposed.map(\.value), ["Bright +1.6"])
        XCTAssertEqual(underexposed.map(\.value), ["Dark -1.6"])
        XCTAssertEqual(neutral.map(\.value), ["Balanced"])

        let combined = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .focus, value: .score(0.72), confidence: 0.81, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .exposure, value: .score(0.2), confidence: 1.0, provenance: provenance)
        ])
        XCTAssertEqual(combined.map(\.title), ["Focus", "Exposure"])
        XCTAssertEqual(combined.map(\.value), ["72%", "Dark -1.2"])
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
            EvaluationSignal(assetID: assetID, kind: .eyeSharpness, value: .score(0.2), confidence: 0.6, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .eyesOpen, value: .score(0.0), confidence: 0.7, provenance: provenance),
            EvaluationSignal(assetID: assetID, kind: .smile, value: .score(0.0), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.title), ["Eye sharpness", "Eyes open", "Smile"])
        XCTAssertEqual(metrics.map(\.value), ["20%", "Shut", "No smile"])
        XCTAssertEqual(metrics.map(\.tone), [.caution, .caution, .neutral])
    }

    func testTopQuartileCalibratedEyeSharpnessLaneReadsPositive() {
        let assetID = AssetID(rawValue: "sharp-eye-frame")
        let provenance = ProviderProvenance(
            provider: "core-image-faces",
            model: "CIDetectorFace",
            version: "2",
            settingsHash: "default"
        )

        // Calibrated eyeSharpness p75 is 0.33 (raw 0.05 / 0.15); lanes at or
        // above the corpus top quartile read positive.
        let metrics = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .eyeSharpness, value: .score(0.4), confidence: 0.6, provenance: provenance)
        ])

        XCTAssertEqual(metrics.map(\.value), ["40%"])
        XCTAssertEqual(metrics.map(\.tone), [.positive])
    }

    func testFaceQualityLaneUsesCalibratedStrongAnchor() {
        // Vision faceCaptureQuality maxes out at 0.703 on the study corpus,
        // so the shared 0.7 positive line rendered virtually every face
        // lane as caution. The lane tones at the calibrated strong anchor
        // (p75, 0.45) - the same line that admits an asset to Potential
        // Picks - so the queue and the lane cannot contradict each other.
        let assetID = AssetID(rawValue: "face-frame")
        let provenance = ProviderProvenance(
            provider: "apple-vision",
            model: "Vision",
            version: "1",
            settingsHash: "default"
        )

        let strong = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .faceQuality, value: .score(0.6), confidence: 0.7, provenance: provenance)
        ])
        let weak = CompareFocusMetricPresentation.metrics(for: [
            EvaluationSignal(assetID: assetID, kind: .faceQuality, value: .score(0.4), confidence: 0.7, provenance: provenance)
        ])

        XCTAssertEqual(strong.map(\.value), ["60%"])
        XCTAssertEqual(strong.map(\.tone), [.positive])
        XCTAssertEqual(weak.map(\.value), ["40%"])
        XCTAssertEqual(weak.map(\.tone), [.caution])
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

    func testSignalBadgesIgnorePartialBlinksAndAboveFloorFocus() {
        // Same calibrated defect anchors as likelyIssue: fractional eyesOpen
        // is CIDetector noise (only 0.0 - all eyes shut - earns the badge)
        // and the focus floor is the calibrated p5 (0.4), so a ~p20 frame at
        // 0.45 is not "SOFT".
        let best = makeAsset(id: "best")
        let partialBlink = makeAsset(id: "partial-blink")
        let midFocus = makeAsset(id: "mid-focus")
        let presentation = CompareSurveyPresentation(
            assets: [best, partialBlink, midFocus],
            selectedAssetID: best.id,
            evaluationSignalsByAssetID: [
                best.id: [
                    signal(assetID: best.id, kind: .focus, score: 0.94),
                    signal(assetID: best.id, kind: .eyesOpen, score: 1.0)
                ],
                partialBlink.id: [
                    signal(assetID: partialBlink.id, kind: .focus, score: 0.9),
                    signal(assetID: partialBlink.id, kind: .eyesOpen, score: 0.5)
                ],
                midFocus.id: [
                    signal(assetID: midFocus.id, kind: .focus, score: 0.45)
                ]
            ]
        )

        XCTAssertEqual(presentation.signalBadges(for: partialBlink), [])
        XCTAssertEqual(presentation.signalBadges(for: midFocus), [])
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

    // A tie can't defend a single winner: no tile may carry "✦ BEST" when the
    // group's recommendation is tie-suppressed.
    func testSignalBadgesSuppressBestClaimUnderATie() {
        let lead = makeAsset(id: "tie-best-lead")
        let alternate = makeAsset(id: "tie-best-alternate")
        let presentation = CompareSurveyPresentation(
            assets: [lead, alternate],
            selectedAssetID: lead.id,
            evaluationSignalsByAssetID: [
                lead.id: [signal(assetID: lead.id, kind: .focus, score: 0.80)],
                alternate.id: [signal(assetID: alternate.id, kind: .focus, score: 0.79)]
            ]
        )

        XCTAssertEqual(presentation.signalBadges(for: lead), [])
        XCTAssertEqual(presentation.signalBadges(for: alternate), [])
    }

    func testRankBadgesShowTopThreeRanksInContendersMode() {
        let assets = (0..<5).map { makeAsset(id: "rank-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.7)],
            assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.5)],
            assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.9)],
            assets[3].id: [signal(assetID: assets[3].id, kind: .focus, score: 0.6)],
            assets[4].id: [signal(assetID: assets[4].id, kind: .focus, score: 0.8)]
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )

        // Ranked by focus score descending: 2 (0.9), 4 (0.8), 0 (0.7); 1 and 3 are not contenders.
        XCTAssertEqual(presentation.rankBadges(for: assets[2]), [CompareDecisionBadge(text: "#1", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: assets[4]), [CompareDecisionBadge(text: "#2", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: assets[0]), [CompareDecisionBadge(text: "#3", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: assets[1]), [])
        XCTAssertEqual(presentation.rankBadges(for: assets[3]), [])
    }

    func testRankBadgesStaySilentOutsideContendersMode() {
        let assets = (0..<3).map { makeAsset(id: "no-rank-\($0)") }
        let signals: [AssetID: [EvaluationSignal]] = [
            assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.9)]
        ]

        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: false
        )

        XCTAssertEqual(presentation.rankBadges(for: assets[0]), [])
    }

    // Members of the tied-leader set render "tied" instead of a numeric
    // rank; the two genuinely non-tied contenders continue numbering after
    // the tied block (a 3-way tie is followed by #4). The non-tied frames
    // here use extra signal kinds so their raw quality-score sum (which
    // ranks the contenders list) diverges from the normalized read (which
    // decides the tie) enough to reach past the top 3 and widen the
    // contenders window to all 5 — exercising the renumbering against a
    // realistic raw/normalized ordering mismatch, not just a contiguous
    // top-of-list tie.
    func testRankBadgesLabelTiedLeadersAsTiedAndContinueNumberingAfterTheTiedBlock() {
        let leader = makeAsset(id: "tied-rank-leader")
        let tied2 = makeAsset(id: "tied-rank-tied2")
        let tied3 = makeAsset(id: "tied-rank-tied3")
        let nonTied1 = makeAsset(id: "tied-rank-nontied1")
        let nonTied2 = makeAsset(id: "tied-rank-nontied2")

        let presentation = CompareSurveyPresentation(
            assets: [leader, tied2, tied3, nonTied1, nonTied2],
            selectedAssetID: leader.id,
            evaluationSignalsByAssetID: [
                leader.id: [signal(assetID: leader.id, kind: .focus, score: 0.90)],
                tied2.id: [signal(assetID: tied2.id, kind: .focus, score: 0.88)],
                tied3.id: [signal(assetID: tied3.id, kind: .focus, score: 0.875)],
                nonTied1.id: [
                    signal(assetID: nonTied1.id, kind: .focus, score: 0.37),
                    signal(assetID: nonTied1.id, kind: .eyesOpen, score: 0.37),
                    signal(assetID: nonTied1.id, kind: .aesthetics, score: 0.37)
                ],
                nonTied2.id: [
                    signal(assetID: nonTied2.id, kind: .focus, score: 0.368),
                    signal(assetID: nonTied2.id, kind: .eyesOpen, score: 0.368),
                    signal(assetID: nonTied2.id, kind: .aesthetics, score: 0.368)
                ]
            ],
            contendersOnly: true
        )

        XCTAssertEqual(presentation.contenderAssets.count, 5)
        XCTAssertEqual(presentation.rankBadges(for: leader), [CompareDecisionBadge(text: "tied", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: tied2), [CompareDecisionBadge(text: "tied", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: tied3), [CompareDecisionBadge(text: "tied", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: nonTied1), [CompareDecisionBadge(text: "#4", tone: .rank)])
        XCTAssertEqual(presentation.rankBadges(for: nonTied2), [CompareDecisionBadge(text: "#5", tone: .rank)])
    }

    func testTileBadgesUseRankChipsInContendersModeAndSignalBadgesOtherwise() {
        let best = makeAsset(id: "tile-best")
        let second = makeAsset(id: "tile-second")
        let signals: [AssetID: [EvaluationSignal]] = [
            best.id: [signal(assetID: best.id, kind: .focus, score: 0.9)],
            second.id: [signal(assetID: second.id, kind: .focus, score: 0.5)]
        ]

        let contendersMode = CompareSurveyPresentation(
            assets: [best, second],
            selectedAssetID: best.id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: true
        )
        XCTAssertEqual(contendersMode.tileBadges(for: best), [
            CompareDecisionBadge(text: "PRIMARY", tone: .primary),
            CompareDecisionBadge(text: "#1", tone: .rank)
        ])
        XCTAssertEqual(contendersMode.tileBadges(for: second), [
            CompareDecisionBadge(text: "#2", tone: .rank)
        ])

        let fullSetMode = CompareSurveyPresentation(
            assets: [best, second],
            selectedAssetID: best.id,
            evaluationSignalsByAssetID: signals,
            contendersOnly: false
        )
        XCTAssertEqual(fullSetMode.tileBadges(for: best), [
            CompareDecisionBadge(text: "PRIMARY", tone: .primary),
            CompareDecisionBadge(text: "✦ BEST", tone: .best)
        ])
    }

    func testComparativeVerdictUsesPercentageDeltaWhenFocusScoresAreHonest() {
        let assets = [
            makeAsset(id: "verdict-a0"),
            makeAsset(id: "verdict-a1"),
            makeAsset(id: "verdict-a2")
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.1)],
                assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.50)],
                assets[2].id: [signal(assetID: assets[2].id, kind: .focus, score: 0.54)]
            ],
            contendersOnly: true
        )

        // Ranked by focus descending: frame 3 (0.54) leads frame 2 (0.50) by 8%.
        XCTAssertEqual(presentation.comparativeVerdictText, "Frame 3 edges it — 8% sharper")
    }

    func testComparativeVerdictAddsEyesOpenQualifierWhenLeaderHasEyesOpen() {
        let assets = [
            makeAsset(id: "verdict-eyes-a0"),
            makeAsset(id: "verdict-eyes-a1"),
            makeAsset(id: "verdict-eyes-a2")
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.1)],
                assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.50)],
                assets[2].id: [
                    signal(assetID: assets[2].id, kind: .focus, score: 0.54),
                    signal(assetID: assets[2].id, kind: .eyesOpen, score: 1.0)
                ]
            ],
            contendersOnly: true
        )

        XCTAssertEqual(presentation.comparativeVerdictText, "Frame 3 edges it — 8% sharper, eyes open")
    }

    func testComparativeVerdictFallsBackToQualitativeSharperWhenRunnerUpFocusIsNearZero() {
        let assets = [
            makeAsset(id: "verdict-nearzero-a0"),
            makeAsset(id: "verdict-nearzero-a1")
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.02)],
                assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.5)]
            ],
            contendersOnly: true
        )

        // Runner-up focus (0.02) is too close to zero for an honest percentage.
        XCTAssertEqual(presentation.comparativeVerdictText, "Frame 2 edges it — sharper")
    }

    func testComparativeVerdictOmitsSharperClaimWhenLeaderDoesNotLeadOnFocus() {
        let assets = [
            makeAsset(id: "verdict-notfocus-a0"),
            makeAsset(id: "verdict-notfocus-a1")
        ]
        let provenance = ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [
                    EvaluationSignal(assetID: assets[0].id, kind: .faceQuality, value: .score(1.0), confidence: 1.0, provenance: provenance),
                    EvaluationSignal(assetID: assets[0].id, kind: .focus, value: .score(0.3), confidence: 1.0, provenance: provenance)
                ],
                assets[1].id: [
                    EvaluationSignal(assetID: assets[1].id, kind: .focus, value: .score(0.9), confidence: 1.0, provenance: provenance)
                ]
            ],
            contendersOnly: true
        )

        // Frame 1 leads overall (face quality + focus outweighs frame 2's focus-only
        // score) but is not actually sharper, so the copy must not claim it is.
        XCTAssertEqual(presentation.comparativeVerdictText, "Frame 1 edges it")
    }

    func testComparativeVerdictIsNilOutsideContendersMode() {
        let assets = [
            makeAsset(id: "verdict-off-a0"),
            makeAsset(id: "verdict-off-a1")
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.9)],
                assets[1].id: [signal(assetID: assets[1].id, kind: .focus, score: 0.5)]
            ],
            contendersOnly: false
        )

        XCTAssertNil(presentation.comparativeVerdictText)
    }

    func testComparativeVerdictIsNilWithFewerThanTwoRankedContenders() {
        let assets = [
            makeAsset(id: "verdict-solo-a0"),
            makeAsset(id: "verdict-solo-a1")
        ]
        let presentation = CompareSurveyPresentation(
            assets: assets,
            selectedAssetID: assets[0].id,
            evaluationSignalsByAssetID: [
                assets[0].id: [signal(assetID: assets[0].id, kind: .focus, score: 0.9)]
            ],
            contendersOnly: true
        )

        XCTAssertTrue(presentation.isContendersOnly)
        XCTAssertEqual(presentation.contenderAssets.count, 1)
        XCTAssertNil(presentation.comparativeVerdictText)
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

    func testCatalogReadsHideRawScaleFocusRowsFromBadgesAndVerdicts() throws {
        // An asset whose only focus row is a superseded raw-scale read
        // (version 1, capped at ~0.148 on the study corpus) must not earn a
        // destructive SOFT badge, and a calibrated leader must not claim a
        // percentage sharpness delta against it across incompatible scales.
        let directory = try makeTemporaryDirectory(named: "compare-raw-scale-signals")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let stale = makeAsset(id: "stale-raw-scale")
        let fresh = makeAsset(id: "fresh-calibrated")
        try repository.upsert([stale, fresh])
        try repository.recordEvaluationSignals([
            EvaluationSignal(
                assetID: stale.id,
                kind: .focus,
                value: .score(0.14),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: fresh.id,
                kind: .focus,
                value: .score(0.93),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: "local-image-metrics", model: "preview-color-focus-metrics", version: "2", settingsHash: "default")
            )
        ])
        let signalsByAssetID: [AssetID: [EvaluationSignal]] = [
            stale.id: try repository.evaluationSignals(assetID: stale.id),
            fresh.id: try repository.evaluationSignals(assetID: fresh.id)
        ]

        XCTAssertEqual(CompareSurveyPresentation.flawBadges(for: signalsByAssetID[stale.id] ?? []), [])
        XCTAssertEqual(
            CullingStackRecommendation.comparativeQualifiers(
                leader: fresh.id,
                runnerUp: stale.id,
                evaluationSignalsByAssetID: signalsByAssetID
            ),
            []
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-compare-survey-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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
