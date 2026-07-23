import XCTest
import TeststripCore
@testable import TeststripApp

final class CullingAssistPresentationTests: XCTestCase {
    func testVerdictSynthesizesKeepFromStrongQualityKinds() {
        let verdict = CullingAssistPresentation.verdict(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0)
        ])

        // (0.96 * 100 + 0.9 * 50) / 150 = 0.94, above the Keep threshold.
        XCTAssertEqual(verdict?.text, "Keep")
        XCTAssertEqual(verdict?.tone, .positive)
    }

    func testVerdictSynthesizesTossFromDefects() {
        let verdict = CullingAssistPresentation.verdict(for: [
            signal(kind: .focus, value: .score(0.2), confidence: 1.0),
            signal(kind: .motionBlur, value: .score(0.9), confidence: 1.0)
        ])

        // (0.2 * 100 + (1 - 0.9) * 60) / 160 = 0.16, below the Toss threshold.
        XCTAssertEqual(verdict?.text, "Toss")
        XCTAssertEqual(verdict?.tone, .caution)
    }

    // A verdict that can't commit to Toss or Keep says nothing at all — no
    // "Mixed" label, per the honest-states philosophy (a pill that can't
    // commit renders absent, not a hedge word).
    func testVerdictReportsNothingBetweenThresholds() {
        let verdict = CullingAssistPresentation.verdict(for: [
            signal(kind: .focus, value: .score(0.6), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.6), confidence: 1.0)
        ])

        XCTAssertNil(verdict)
    }

    func testVerdictTossesWeakCalibratedReadBelowHalf() {
        // A weak frame on the calibrated scale: focus 0.4 is below the
        // corpus p5 anchor, so the read lands at (0.4 * 100 + 0.56 * 50)
        // / 150 = 0.45 - inside the recalibrated Toss band (<= 0.5).
        let verdict = CullingAssistPresentation.verdict(for: [
            signal(kind: .focus, value: .score(0.4), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.56), confidence: 1.0)
        ])

        XCTAssertEqual(verdict?.text, "Toss")
        XCTAssertEqual(verdict?.tone, .caution)
    }

    func testVerdictRequiresAtLeastTwoScoredQualityKinds() {
        XCTAssertNil(CullingAssistPresentation.verdict(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0)
        ]))
        XCTAssertNil(CullingAssistPresentation.verdict(for: []))
    }

    private func signal(kind: EvaluationKind, value: EvaluationValue, confidence: Double) -> EvaluationSignal {
        EvaluationSignal(
            assetID: AssetID(rawValue: "asset"),
            kind: kind,
            value: value,
            confidence: confidence,
            provenance: ProviderProvenance(
                provider: "local-http",
                model: "test-model",
                version: "1",
                settingsHash: "test"
            )
        )
    }
}
