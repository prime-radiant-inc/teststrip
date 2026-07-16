import XCTest
import TeststripCore
@testable import TeststripApp

// Direct unit coverage for the ranking-level `CullingStackRecommendation`
// static helpers — there's no dedicated test home for the ranking logic
// itself (it's otherwise only exercised indirectly through
// CullingStackRailPresentationTests and CompareSurveyPresentationTests).
final class CullingStackRecommendationTests: XCTestCase {
    func testMarginConstantIsThreeHundredthsOnTheNormalizedScale() {
        XCTAssertEqual(CullingStackRecommendation.tooCloseToCallMargin, 0.03)
    }

    func testTwoFramesWithinMarginAreTied() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second],
            evaluationSignalsByAssetID: [
                first: [signal(assetID: first, score: 0.80)],
                second: [signal(assetID: second, score: 0.79)]
            ]
        )

        XCTAssertEqual(tiedLeaderIDs, [first, second])
    }

    func testTwoFramesBeyondMarginAreNotTied() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second],
            evaluationSignalsByAssetID: [
                first: [signal(assetID: first, score: 0.80)],
                second: [signal(assetID: second, score: 0.76)]
            ]
        )

        XCTAssertNil(tiedLeaderIDs)
    }

    func testThreeWayTieReturnsAllThreeInCaptureOrder() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")
        let third = AssetID(rawValue: "third")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second, third],
            evaluationSignalsByAssetID: [
                first: [signal(assetID: first, score: 0.80)],
                second: [signal(assetID: second, score: 0.78)],
                third: [signal(assetID: third, score: 0.79)]
            ]
        )

        // Capture order (first, second, third), not read-descending order.
        XCTAssertEqual(tiedLeaderIDs, [first, second, third])
    }

    func testFourthPlaceOutsideMarginIsExcludedFromTheTie() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")
        let third = AssetID(rawValue: "third")
        let fourth = AssetID(rawValue: "fourth")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second, third, fourth],
            evaluationSignalsByAssetID: [
                first: [signal(assetID: first, score: 0.80)],
                second: [signal(assetID: second, score: 0.79)],
                third: [signal(assetID: third, score: 0.78)],
                fourth: [signal(assetID: fourth, score: 0.5)]
            ]
        )

        XCTAssertEqual(tiedLeaderIDs, [first, second, third])
    }

    func testSingleCandidateWithAReadIsNeverTied() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second],
            evaluationSignalsByAssetID: [
                first: [signal(assetID: first, score: 0.80)]
            ]
        )

        XCTAssertNil(tiedLeaderIDs)
    }

    func testNoCandidatesWithReadsReturnsNil() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second],
            evaluationSignalsByAssetID: [:]
        )

        XCTAssertNil(tiedLeaderIDs)
    }

    // The AI landing fallback (AppModel.recommendedCullingStackAssetID) uses
    // the first entry of a tie as the landing frame; capture order makes
    // that entry deterministic and stable.
    func testFirstTiedLeaderIsTheFirstInCaptureOrder() {
        let first = AssetID(rawValue: "first")
        let second = AssetID(rawValue: "second")
        let third = AssetID(rawValue: "third")

        let tiedLeaderIDs = CullingStackRecommendation.tiedLeaderIDs(
            stackAssetIDs: [first, second, third],
            evaluationSignalsByAssetID: [
                first: [signal(assetID: first, score: 0.79)],
                second: [signal(assetID: second, score: 0.80)],
                third: [signal(assetID: third, score: 0.78)]
            ]
        )

        XCTAssertEqual(tiedLeaderIDs?.first, first)
    }

    private func signal(assetID: AssetID, score: Double, confidence: Double = 0.9) -> EvaluationSignal {
        EvaluationSignal(
            assetID: assetID,
            kind: .focus,
            value: .score(score),
            confidence: confidence,
            provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
        )
    }
}
