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
            ]
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
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("Automatic clustering"))
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("split"))
        XCTAssertTrue(presentation.deferredFaceActionStatus.localizedCaseInsensitiveContains("face-box naming"))
    }
}
