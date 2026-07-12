import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class PeoplePresentationTests: XCTestCase {
    func testBuildsNamedPeopleFromConfirmedCatalogPeople() {
        let presentation = PeoplePresentation(
            totalAssetCount: 1204,
            namedPeople: [
                CatalogPerson(id: "person-maya", name: "Maya", assetCount: 2),
                CatalogPerson(id: "person-lee", name: "Lee", assetCount: 1)
            ],
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "2 people · 3 photos with face signals")
        XCTAssertEqual(presentation.namedPeople.map(\.name), ["Maya", "Lee"])
        XCTAssertEqual(presentation.namedPeople.map(\.countText), ["2 confirmed photos", "1 confirmed photo"])
    }

    func testBuildsFaceReviewStripFromRealFaceSignals() {
        let presentation = PeoplePresentation(
            totalAssetCount: 1204,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3),
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 44)
            ],
            faceObservationAssetCount: 44
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 44 photos with face signals")
        XCTAssertEqual(presentation.reviewStripTitle, "3 photos need face review")
        XCTAssertEqual(presentation.reviewStripStatusText, "2 queues")
        XCTAssertEqual(presentation.reviewStripDetail, "44 photos have face-quality signals; review queues can be named from selected photos.")
        XCTAssertEqual(presentation.reviewCards.map(\.title), ["Unnamed faces", "Face quality checks"])
        XCTAssertEqual(presentation.reviewCards.map(\.countText), ["3 photos", "44 photos"])
        XCTAssertEqual(presentation.reviewCards.map(\.suggestedActionTitle), ["Review faces", "Review quality"])
        XCTAssertEqual(presentation.reviewCards.map(\.filterKind), [.faceCount, .faceQuality])
        XCTAssertEqual(presentation.reviewCards.map(\.target), [.reviewQueue(.facesFound), .evaluationKind(.faceQuality)])
        XCTAssertFalse(presentation.reviewCards.contains(where: \.showsUnbuiltFaceActionLock))
        XCTAssertEqual(presentation.namedPeopleTitle, "ALL PEOPLE")
        XCTAssertEqual(presentation.namedPeopleEmptyText, "No confirmed people yet. Review face queues, select photos, then name the selection.")
    }

    // persona-6 Priya: the workspace said "Scan ready" forever while the
    // scan could never actually run because the catalog's photo sources were
    // offline. When sources are unavailable the status line must say so
    // instead of advertising a scan that will silently do nothing.
    func testOfflineSourcesReplaceScanReadyStatus() {
        let presentation = PeoplePresentation(
            totalAssetCount: 11,
            evaluationSummaries: [],
            canRequestCurrentScopeFaceScan: true,
            hasUnavailableSources: true
        )

        XCTAssertEqual(presentation.reviewStripStatusText, "Photo sources offline — reconnect to scan")
    }

    func testOfflineSourcesReplaceZeroQueuesStatusWhenScanCannotStart() {
        let presentation = PeoplePresentation(
            totalAssetCount: 11,
            evaluationSummaries: [],
            canRequestCurrentScopeFaceScan: false,
            hasUnavailableSources: true
        )

        XCTAssertEqual(presentation.reviewStripStatusText, "Photo sources offline — reconnect to scan")
    }

    func testScanReadyStatusStandsWhenSourcesAreAvailable() {
        let presentation = PeoplePresentation(
            totalAssetCount: 11,
            evaluationSummaries: [],
            canRequestCurrentScopeFaceScan: true
        )

        XCTAssertEqual(presentation.reviewStripStatusText, "Scan ready")
    }

    // persona-6 Priya: "Name Selection" gave no hint of what was selected,
    // so a leftover Library selection attached "Sally K. Ride" to a Buzz
    // Aldrin portrait. The sheet's subtitle now carries the count.
    func testNameSelectionSubtitleCountsTheSelectedPhotos() {
        XCTAssertEqual(
            PeoplePresentation.nameSelectionSubtitle(selectedPhotoCount: 1),
            "Groups the 1 selected photo under a new named person."
        )
        XCTAssertEqual(
            PeoplePresentation.nameSelectionSubtitle(selectedPhotoCount: 3),
            "Groups the 3 selected photos under a new named person."
        )
    }

    func testNameFaceGroupSubtitleCountsTheGroupsFacesAndPhotos() {
        XCTAssertEqual(
            PeoplePresentation.nameFaceGroupSubtitle(faceCount: 1, photoCount: 1),
            "Groups this face group's 1 face across 1 photo under a new named person."
        )
        XCTAssertEqual(
            PeoplePresentation.nameFaceGroupSubtitle(faceCount: 4, photoCount: 3),
            "Groups this face group's 4 faces across 3 photos under a new named person."
        )
    }

    func testFaceReviewStatusPointsToManualNamingAction() {
        let presentation = PeoplePresentation(
            totalAssetCount: 1204,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3)
            ]
        )

        XCTAssertEqual(
            presentation.statusDetail,
            "Review 3 photos with unnamed face signals. Select photos, then name the selection."
        )
    }

    func testFaceReviewStripStaysHonestWithoutFaceSignals() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertEqual(presentation.headerSummary, "0 people · 42 photos")
        XCTAssertEqual(presentation.reviewStripTitle, "No faces found yet")
        XCTAssertEqual(presentation.reviewStripStatusText, "0 queues")
        XCTAssertEqual(presentation.statusTitle, "No faces found yet")
        XCTAssertEqual(presentation.statusDetail, "Scan these photos to find faces to review.")
        XCTAssertEqual(presentation.reviewCards, [])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["0", "0"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [nil, nil])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [false, false])
        // The scan prompt and the named-people empty state must not render the
        // identical sentence twice on one screen.
        XCTAssertEqual(presentation.namedPeopleEmptyText, "Once Teststrip finds faces, name them here.")
        XCTAssertEqual(presentation.faceReviewEmptyPrompt, "Scan to find faces in these photos.")
        XCTAssertNotEqual(presentation.faceReviewEmptyPrompt, presentation.namedPeopleEmptyText)
        XCTAssertNil(presentation.scanAction)
    }

    func testCurrentScopeFaceScanActionUsesLocalAppleVisionWhenAvailable() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [],
            canRequestCurrentScopeFaceScan: true
        )

        XCTAssertEqual(presentation.scanAction?.title, "Scan for Faces")
        XCTAssertEqual(presentation.scanAction?.detail, "Runs local Apple Vision on cached previews for these photos. If a photo's detected faces change, its confirmed and dismissed faces are cleared for re-review.")
        XCTAssertEqual(presentation.scanAction?.systemImage, "viewfinder")
        XCTAssertEqual(presentation.reviewStripStatusText, "Scan ready")
    }

    func testUnnamedFaceReviewFallsBackToFaceQualityWhenFaceCountSignalsAreMissing() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 5)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 5 photos with face signals")
        XCTAssertEqual(presentation.reviewStripTitle, "5 photos need face review")
        XCTAssertEqual(presentation.signalRows.map(\.title), ["Unnamed faces", "Face quality review"])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["5", "5"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [.faceQuality, .faceQuality])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [true, true])
        XCTAssertEqual(presentation.reviewCards.map(\.target), [.evaluationKind(.faceQuality), .evaluationKind(.faceQuality)])
    }

    func testFaceCountRowCountMatchesItsFilterWhenFaceQualityCountIsHigher() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 2),
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 5)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 5 photos with face signals")
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["2", "5"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [.faceCount, .faceQuality])
    }

    func testReviewCardsDoNotMarkManualPeopleReviewAsUnbuiltFaceActions() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 2),
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 5)
            ]
        )

        XCTAssertEqual(presentation.reviewCards.map(\.suggestedActionTitle), ["Review faces", "Review quality"])
        XCTAssertTrue(presentation.reviewCards.allSatisfy(\.isActionEnabled))
        XCTAssertFalse(presentation.reviewCards.contains(where: \.showsUnbuiltFaceActionLock))
        XCTAssertTrue(presentation.visibleDeferredFaceActionTitles.isEmpty)
    }

    func testPresentationTracksUnavailableFaceActionsAsStatusCopyInsteadOfDisabledButtons() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertTrue(presentation.visibleDeferredFaceActionTitles.isEmpty)
        XCTAssertEqual(
            presentation.faceActionStatus,
            "Confirm a suggested group, name faces yourself, or merge people. Nothing is saved until you confirm."
        )
    }

    func testEmptyStateCopySpeaksUserLanguage() {
        // The first-run People screen must not speak developer: no internal
        // jargon or release-notes phrasing in the empty state.
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])
        let bannedTerms = [
            "evaluation", "queue", "deferred", "face-box", "catalog photos",
            "embedding", "provisional", "signal"
        ]

        XCTAssertEqual(
            presentation.reviewStripDetail,
            "These photos haven’t been scanned for faces yet. Scan for faces to see who’s in your photos."
        )
        for copy in [presentation.reviewStripDetail, presentation.faceActionStatus] {
            for term in bannedTerms {
                XCTAssertFalse(
                    copy.localizedCaseInsensitiveContains(term),
                    "empty-state copy contains internal jargon '\(term)': \(copy)"
                )
            }
        }
    }

    private func matchSuggestion() -> PeopleFaceSuggestion {
        PeopleFaceSuggestion(
            id: "face-match-person-maya",
            kind: .matchExisting(personID: "person-maya", personName: "Maya"),
            faceIDs: [FaceID(assetID: AssetID(rawValue: "incoming"), faceIndex: 0)],
            representativeFace: FaceID(assetID: AssetID(rawValue: "incoming"), faceIndex: 0),
            representativeBoundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            assetIDs: [AssetID(rawValue: "incoming")]
        )
    }

    private func clusterSuggestion() -> PeopleFaceSuggestion {
        PeopleFaceSuggestion(
            id: "face-cluster-group-a-0",
            kind: .newPerson,
            faceIDs: [
                FaceID(assetID: AssetID(rawValue: "group-a"), faceIndex: 0),
                FaceID(assetID: AssetID(rawValue: "group-b"), faceIndex: 0)
            ],
            representativeFace: FaceID(assetID: AssetID(rawValue: "group-a"), faceIndex: 0),
            representativeBoundingBox: FaceBoundingBox(x: 0.2, y: 0.3, width: 0.25, height: 0.25),
            assetIDs: [AssetID(rawValue: "group-a"), AssetID(rawValue: "group-b")]
        )
    }

    func testFaceSuggestionBandPresentsNeedsANameCards() {
        let presentation = PeoplePresentation(
            totalAssetCount: 100,
            evaluationSummaries: [CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3)],
            faceSuggestions: [matchSuggestion(), clusterSuggestion()],
            faceObservationAssetCount: 4
        )

        XCTAssertEqual(presentation.reviewStripTitle, "3 faces need a name")
        XCTAssertEqual(presentation.reviewStripStatusText, "1 group matches confirmed people")
        XCTAssertEqual(
            presentation.reviewStripDetail,
            "Face groups are provisional until you confirm. Confirming writes people to the catalog; dismissing hides the group."
        )
        XCTAssertEqual(presentation.suggestionCards.map(\.title), ["Is this Maya?", "Who is this?"])
        XCTAssertEqual(presentation.suggestionCards.map(\.confirmActionTitle), ["Maya", "Name…"])
        XCTAssertEqual(presentation.suggestionCards.map(\.countText), ["1 face · 1 photo", "2 faces · 2 photos"])
        XCTAssertEqual(presentation.suggestionCards.map(\.isOneTapConfirm), [true, false])
    }

    func testFaceBandPromptsRescanWhenSignalsPredateGrouping() {
        let presentation = PeoplePresentation(
            totalAssetCount: 100,
            evaluationSummaries: [CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 3)],
            faceSuggestions: [],
            faceObservationAssetCount: 0
        )

        XCTAssertEqual(presentation.suggestionCards, [])
        XCTAssertEqual(
            presentation.reviewStripDetail,
            "Face signals predate grouping; run Scan for Faces to compute face embeddings."
        )
    }
}
