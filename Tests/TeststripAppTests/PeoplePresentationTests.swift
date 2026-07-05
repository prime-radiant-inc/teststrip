import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class PeoplePresentationTests: XCTestCase {
    func testPresentationUsesFaceEvaluationSummaries() {
        let presentation = PeoplePresentation(
            totalAssetCount: 1_204,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceCount, assetCount: 38),
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 27),
                CatalogEvaluationKindSummary(kind: .object, assetCount: 81)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 38 photos with face signals")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · FACE GROUPING NOT BUILT")
        XCTAssertEqual(presentation.statusDetail, "38 photos have face signals. Naming starts after clustering ships.")
        XCTAssertEqual(presentation.signalRows.map(\.title), ["Photos with faces", "Face quality reads"])
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["38", "27"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [.faceCount, .faceQuality])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [true, true])
    }

    func testPresentationExplainsWhenNoFaceSignalsExist() {
        let presentation = PeoplePresentation(totalAssetCount: 42, evaluationSummaries: [])

        XCTAssertEqual(presentation.headerSummary, "0 people · 42 photos")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · NO FACE SIGNALS YET")
        XCTAssertEqual(presentation.statusDetail, "Run evaluation on catalog photos to populate local face signals.")
        XCTAssertEqual(presentation.signalRows.map(\.countText), ["0", "0"])
        XCTAssertEqual(presentation.signalRows.map(\.filterKind), [nil, nil])
        XCTAssertEqual(presentation.signalRows.map(\.isActionEnabled), [false, false])
    }

    func testPresentationCountsFaceQualitySignalsWhenFaceCountIsMissing() {
        let presentation = PeoplePresentation(
            totalAssetCount: 42,
            evaluationSummaries: [
                CatalogEvaluationKindSummary(kind: .faceQuality, assetCount: 5)
            ]
        )

        XCTAssertEqual(presentation.headerSummary, "0 people · 5 photos with face signals")
        XCTAssertEqual(presentation.statusTitle, "TESTSTRIP · FACE GROUPING NOT BUILT")
        XCTAssertEqual(presentation.statusDetail, "5 photos have face signals. Naming starts after clustering ships.")
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
}
