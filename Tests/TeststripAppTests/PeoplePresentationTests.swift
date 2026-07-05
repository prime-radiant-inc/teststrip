import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class PeoplePresentationTests: XCTestCase {
    func testPresentationFramesFaceSignalsAsUnnamedFaceReview() {
        let presentation = PeoplePresentation(
            totalAssetCount: 1_204,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 38),
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 27),
                CatalogEvaluationKindSummary(kind: .object, assetCount: 81)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 38 photos with face signals")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · FACE REVIEW QUEUE")
        XCTAssertEqual(presentation.statusDetail, "Review 38 photos with unnamed face signals. Naming and clustering are still disabled.")
        XCTAssertEqual(presentation.signalRows.map(\.title), ["Unnamed faces", "Face quality review"])
        XCTAssertEqual(presentation.signalRows.map(\.detail), ["Review assets with local face detections", "Review assets with face-quality measurements"])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["38", "27"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [.faceCount, .faceQuality])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [true, true])
    }

    func testPresentationExplainsWhenNoFaceSignalsExist() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertEqual(presentation.headerSummary, "0 people · 42 photos")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · NO FACE REVIEW SIGNALS")
        XCTAssertEqual(presentation.statusDetail, "Run evaluation on catalog photos to populate local face review queues.")
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["0", "0"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [nil, nil])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [false, false])
    }

    func testUnnamedFaceReviewFallsBackToFaceQualityWhenFaceCountSignalsAreMissing() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 5)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 5 photos with face signals")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · FACE REVIEW QUEUE")
        XCTAssertEqual(presentation.statusDetail, "Review 5 photos with unnamed face signals. Naming and clustering are still disabled.")
        XCTAssertEqual(presentation.signalRows.map(\.title), ["Unnamed faces", "Face quality review"])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["5", "5"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [.faceQuality, .faceQuality])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [true, true])
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
