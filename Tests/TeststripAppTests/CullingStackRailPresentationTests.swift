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
        XCTAssertTrue(presentation.isMultiFrameStack)
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

    // A standalone (single-photo) stop still shows in the rail — just its
    // own thumb, no stack-only chrome: no rank/✦ (a single frame can't have
    // a recommended sibling), no "Frame N of M" (there's no M), but its
    // pick/reject decision still renders.
    func testShowsSingleEntryRailForStandaloneSelection() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let asset = makeAsset(id: "single", path: "/Photos/Job/single.cr2", capturedAt: capturedAt, flag: .pick)

        let presentation = CullingStackRailPresentation(
            assets: [asset],
            selectedAssetID: asset.id,
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.isMultiFrameStack)
        XCTAssertEqual(presentation.items.map(\.assetID), [asset.id])
        XCTAssertEqual(presentation.items.map(\.isSelected), [true])
        XCTAssertEqual(presentation.items.map(\.isRecommended), [false])
        XCTAssertEqual(presentation.items.map(\.decision), [.picked])
        XCTAssertTrue(presentation.actions.isEmpty)
        XCTAssertEqual(presentation.titleText, "Standalone")
        XCTAssertEqual(presentation.positionText, "")
        XCTAssertNil(presentation.recommendedAssetID)
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

    func testRecommendedActionExplainsSharpestEyesOpenRationale() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let selected = makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [selected, alternate],
            selectedAssetID: selected.id,
            evaluationSignalsByAssetID: [
                selected.id: [
                    signal(assetID: selected.id, kind: .focus, score: 0.62)
                ],
                alternate.id: [
                    signal(assetID: alternate.id, kind: .focus, score: 0.94),
                    signal(assetID: alternate.id, kind: .eyesOpen, score: 1.0)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, true])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternate.id))
        XCTAssertEqual(presentation.actions[1].help, "Keep frame 2 — sharpest, eyes open.")
        XCTAssertEqual(presentation.actions[1].assistTitle, "Recommended frame 2")
    }

    func testEyesOpenSignalBreaksFocusTieInRecommendation() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let selected = makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [selected, alternate],
            selectedAssetID: selected.id,
            evaluationSignalsByAssetID: [
                selected.id: [
                    signal(assetID: selected.id, kind: .focus, score: 0.9),
                    signal(assetID: selected.id, kind: .eyesOpen, score: 0.0)
                ],
                alternate.id: [
                    signal(assetID: alternate.id, kind: .focus, score: 0.9),
                    signal(assetID: alternate.id, kind: .eyesOpen, score: 1.0)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, true])
        XCTAssertEqual(presentation.actions[1].action, .keepRecommended(alternate.id))
        // Focus is tied, so "sharpest" is not claimed; eyes decide.
        XCTAssertEqual(presentation.actions[1].help, "Keep frame 2 — eyes open.")
    }

    func testRecommendedAssetIDSurfacesTheRankedWinner() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))
        ]
        let alternateID = AssetID(rawValue: "alternate")

        let ranked = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            evaluationSignalsByAssetID: [
                alternateID: [signal(assetID: alternateID, kind: .focus, score: 0.94)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )
        let unranked = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(ranked.recommendedAssetID, alternateID)
        XCTAssertNil(unranked.recommendedAssetID)
    }

    func testTooCloseToCallTieSuppressesTheRecommendationAndSurfacesTheBanner() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [lead, alternate],
            selectedAssetID: lead.id,
            evaluationSignalsByAssetID: [
                lead.id: [signal(assetID: lead.id, kind: .focus, score: 0.80)],
                alternate.id: [signal(assetID: alternate.id, kind: .focus, score: 0.79)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, false])
        XCTAssertNil(presentation.recommendedAssetID)
        XCTAssertEqual(presentation.tooCloseBanner, "too close to call — 1·2")
    }

    func testThreeWayTieBannerListsAllTiedFramesInCaptureOrder() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))
        ]

        let presentation = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            evaluationSignalsByAssetID: [
                AssetID(rawValue: "lead"): [signal(assetID: AssetID(rawValue: "lead"), kind: .focus, score: 0.80)],
                AssetID(rawValue: "selected"): [signal(assetID: AssetID(rawValue: "selected"), kind: .focus, score: 0.78)],
                AssetID(rawValue: "alternate"): [signal(assetID: AssetID(rawValue: "alternate"), kind: .focus, score: 0.79)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 3)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [false, false, false])
        XCTAssertNil(presentation.recommendedAssetID)
        XCTAssertEqual(presentation.tooCloseBanner, "too close to call — 1·2·3")
    }

    func testBeyondMarginDifferenceStillShowsASingleRecommendationWithNoBanner() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [lead, alternate],
            selectedAssetID: lead.id,
            evaluationSignalsByAssetID: [
                lead.id: [signal(assetID: lead.id, kind: .focus, score: 0.80)],
                alternate.id: [signal(assetID: alternate.id, kind: .focus, score: 0.76)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.isRecommended), [true, false])
        XCTAssertEqual(presentation.recommendedAssetID, lead.id)
        XCTAssertNil(presentation.tooCloseBanner)
    }

    // A tie can't defend a single winner: the banner + Compare are the
    // resolution paths, so "Keep recommended X" must not appear alongside
    // them. "Keep selected & cut" and "Keep all" are user-chosen quantities,
    // not machine claims, so they remain.
    func testTiedTwoFrameStackOffersNoKeepRecommendedAction() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt)
        let alternate = makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1))

        let presentation = CullingStackRailPresentation(
            assets: [lead, alternate],
            selectedAssetID: lead.id,
            evaluationSignalsByAssetID: [
                lead.id: [signal(assetID: lead.id, kind: .focus, score: 0.80)],
                alternate.id: [signal(assetID: alternate.id, kind: .focus, score: 0.79)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertNotNil(presentation.tooCloseBanner)
        XCTAssertEqual(presentation.actions.map(\.title), ["Keep frame 1 · cut 1", "Keep all 2"])
        XCTAssertFalse(presentation.actions.contains { if case .keepRecommended = $0.action { return true } else { return false } })
    }

    // "Keep top 2" names a user-chosen quantity, not a machine winner, so it
    // remains even under a 3-way tie; only "Keep recommended" is suppressed.
    func testTiedThreeFrameStackStillOffersKeepTopTwoButNoKeepRecommendedAction() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let assets = [
            makeAsset(id: "lead", path: "/Photos/Job/lead.cr2", capturedAt: capturedAt),
            makeAsset(id: "selected", path: "/Photos/Job/selected.cr2", capturedAt: capturedAt.addingTimeInterval(1)),
            makeAsset(id: "alternate", path: "/Photos/Job/alternate.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))
        ]

        let presentation = CullingStackRailPresentation(
            assets: assets,
            selectedAssetID: AssetID(rawValue: "selected"),
            evaluationSignalsByAssetID: [
                AssetID(rawValue: "lead"): [signal(assetID: AssetID(rawValue: "lead"), kind: .focus, score: 0.80)],
                AssetID(rawValue: "selected"): [signal(assetID: AssetID(rawValue: "selected"), kind: .focus, score: 0.78)],
                AssetID(rawValue: "alternate"): [signal(assetID: AssetID(rawValue: "alternate"), kind: .focus, score: 0.79)]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 3)
        )

        XCTAssertNotNil(presentation.tooCloseBanner)
        XCTAssertEqual(presentation.actions.map(\.title), ["Keep frame 2 · cut 2", "Keep top 2", "Keep all 3"])
        XCTAssertFalse(presentation.actions.contains { if case .keepRecommended = $0.action { return true } else { return false } })
    }

    func testItemsCarryCompactFlawBadgesFromPersistedSignals() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let sharpEyesOpen = makeAsset(id: "sharp-open", path: "/Photos/Job/sharp-open.cr2", capturedAt: capturedAt)
        let blink = makeAsset(id: "blink", path: "/Photos/Job/blink.cr2", capturedAt: capturedAt.addingTimeInterval(1))
        let soft = makeAsset(id: "soft", path: "/Photos/Job/soft.cr2", capturedAt: capturedAt.addingTimeInterval(1.8))

        let presentation = CullingStackRailPresentation(
            assets: [sharpEyesOpen, blink, soft],
            selectedAssetID: sharpEyesOpen.id,
            evaluationSignalsByAssetID: [
                sharpEyesOpen.id: [
                    signal(assetID: sharpEyesOpen.id, kind: .focus, score: 0.95),
                    signal(assetID: sharpEyesOpen.id, kind: .eyesOpen, score: 1.0)
                ],
                blink.id: [
                    signal(assetID: blink.id, kind: .focus, score: 0.9),
                    signal(assetID: blink.id, kind: .eyesOpen, score: 0.0)
                ],
                soft.id: [
                    signal(assetID: soft.id, kind: .focus, score: 0.3)
                ]
            ],
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        XCTAssertEqual(presentation.items.map(\.assetID), [sharpEyesOpen.id, blink.id, soft.id])
        XCTAssertEqual(presentation.items[0].flawBadges, [])
        // .flaw, not .destructive: a flaw badge is a quality read, not a
        // decision — red stays reserved for genuinely destructive states.
        XCTAssertEqual(presentation.items[1].flawBadges, [CompareDecisionBadge(text: "EYES CLOSED", tone: .flaw)])
        XCTAssertEqual(presentation.items[2].flawBadges, [CompareDecisionBadge(text: "SOFT", tone: .flaw)])
    }

    func testItemsCarryPickRejectDecisionFromAssetFlag() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let picked = makeAsset(id: "picked", path: "/Photos/Job/picked.cr2", capturedAt: capturedAt, flag: .pick)
        let rejected = makeAsset(id: "rejected", path: "/Photos/Job/rejected.cr2", capturedAt: capturedAt.addingTimeInterval(1), flag: .reject)
        let undecided = makeAsset(id: "undecided", path: "/Photos/Job/undecided.cr2", capturedAt: capturedAt.addingTimeInterval(1.8), flag: nil)

        let presentation = CullingStackRailPresentation(
            assets: [picked, rejected, undecided],
            selectedAssetID: picked.id,
            stackBuilder: AssetStackBuilder(maximumCaptureGap: 2)
        )

        let byID = Dictionary(uniqueKeysWithValues: presentation.items.map { ($0.assetID, $0.decision) })
        XCTAssertEqual(byID[picked.id], .picked)
        XCTAssertEqual(byID[rejected.id], .rejected)
        XCTAssertEqual(byID[undecided.id], .undecided)
    }

    func testOnlyRejectedDecisionStateIsDimmed() {
        XCTAssertTrue(CullingStackRailPresentation.DecisionState.rejected.isDimmed)
        XCTAssertFalse(CullingStackRailPresentation.DecisionState.picked.isDimmed)
        XCTAssertFalse(CullingStackRailPresentation.DecisionState.undecided.isDimmed)
    }

    private func makeAsset(id: String, path: String, capturedAt: Date?, flag: PickFlag? = nil) -> Asset {
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
            metadata: AssetMetadata(flag: flag),
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
