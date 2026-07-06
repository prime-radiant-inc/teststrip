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
        XCTAssertEqual(presentation.reviewStripTitle, "TESTSTRIP · 3 PHOTOS NEED FACE REVIEW")
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
        XCTAssertEqual(presentation.reviewStripTitle, "TESTSTRIP · NO FACE REVIEW SIGNALS")
        XCTAssertEqual(presentation.reviewStripStatusText, "0 queues")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · NO FACE REVIEW SIGNALS")
        XCTAssertEqual(presentation.statusDetail, "Run evaluation on catalog photos to populate local face review queues.")
        XCTAssertEqual(presentation.reviewCards, [])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["0", "0"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [nil, nil])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [false, false])
        XCTAssertEqual(presentation.namedPeopleEmptyText, "Run evaluation to find faces before naming people.")
        XCTAssertNil(presentation.scanAction)
    }

    func testCurrentScopeFaceScanActionUsesLocalAppleVisionWhenAvailable() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [],
            canRequestCurrentScopeFaceScan: true
        )

        XCTAssertEqual(presentation.scanAction?.title, "Scan current scope")
        XCTAssertEqual(presentation.scanAction?.detail, "Runs local Apple Vision on cached previews for the current catalog or search scope.")
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
        XCTAssertEqual(presentation.reviewStripTitle, "TESTSTRIP · 5 PHOTOS NEED FACE REVIEW")
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

    func testPresentationTracksDeferredFaceActionsAsStatusCopyInsteadOfDisabledButtons() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertTrue(presentation.visibleDeferredFaceActionTitles.isEmpty)
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("automatic grouping"))
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("split"))
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("face-box naming"))
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

        XCTAssertEqual(presentation.reviewStripTitle, "TESTSTRIP · 3 FACES NEED A NAME")
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
            "Face signals predate grouping; run Scan current scope to compute face embeddings."
        )
    }
}
