import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class PeoplePresentationTests: XCTestCase {
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
        XCTAssertEqual(presentation.reviewStripDetail, "44 photos have face-quality signals; named people are not built yet.")
        XCTAssertEqual(presentation.reviewCards.map(\.title), ["Unnamed faces", "Face quality checks"])
        XCTAssertEqual(presentation.reviewCards.map(\.countText), ["3 photos", "44 photos"])
        XCTAssertEqual(presentation.reviewCards.map(\.suggestedActionTitle), ["Review faces", "Review quality"])
        XCTAssertEqual(presentation.reviewCards.map(\.filterKind), [.faceCount, .faceQuality])
        XCTAssertEqual(presentation.reviewCards.map(\.target), [.reviewQueue(.facesFound), .evaluationKind(.faceQuality)])
        XCTAssertTrue(presentation.reviewCards.allSatisfy { !$0.isNamingEnabled })
        XCTAssertEqual(presentation.namedPeopleTitle, "ALL PEOPLE")
        XCTAssertEqual(presentation.namedPeopleEmptyText, "Named people will appear here after face clustering and confirmation ship.")
    }

    func testFaceReviewStripStaysHonestWithoutFaceSignals() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertEqual(presentation.headerSummary, "0 people · 42 photos")
        XCTAssertEqual(presentation.reviewStripTitle, "TESTSTRIP · NO FACE REVIEW SIGNALS")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · NO FACE REVIEW SIGNALS")
        XCTAssertEqual(presentation.statusDetail, "Run evaluation on catalog photos to populate local face review queues.")
        XCTAssertEqual(presentation.reviewCards, [])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["0", "0"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [nil, nil])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [false, false])
        XCTAssertEqual(presentation.namedPeopleEmptyText, "Run evaluation to find faces before naming people.")
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

    func testPresentationKeepsNamingActionsDisabledWithoutClusters() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertEqual(presentation.faceActionRows.map(\.title), ["Name clusters", "Merge duplicates", "Dismiss false positives"])
        XCTAssertEqual(presentation.faceActionRows.map(\.isEnabled), [false, false, false])
        XCTAssertEqual(
            presentation.faceActionRows.map(\.placeholder.id),
            [
                LiveMockupPlaceholders.peopleFaceActions.id,
                LiveMockupPlaceholders.peopleFaceActions.id,
                LiveMockupPlaceholders.peopleFaceActions.id
            ]
        )
    }
}
