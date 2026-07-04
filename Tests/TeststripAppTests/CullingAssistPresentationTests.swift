import XCTest
import TeststripCore
@testable import TeststripApp

final class CullingAssistPresentationTests: XCTestCase {
    func testEmptySignalsShowUnevaluatedState() {
        let presentation = CullingAssistPresentation.presentation(for: [])

        XCTAssertEqual(presentation.title, "No read yet")
        XCTAssertEqual(presentation.detail, "Evaluate frame to show culling signals")
        XCTAssertEqual(presentation.tone, .waiting)
    }

    func testAestheticLabelBecomesPrimaryVerdict() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .aesthetics, value: .label("keeper"), confidence: 0.74)
        ])

        XCTAssertEqual(presentation.title, "Keeper")
        XCTAssertEqual(presentation.detail, "Aesthetics - local-http - 74% confidence")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testFocusScoreFormatsAsPercent() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.914), confidence: 0.82)
        ])

        XCTAssertEqual(presentation.title, "Focus 91%")
        XCTAssertEqual(presentation.detail, "Focus - local-http - 82% confidence")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testHighMotionBlurUsesCautionTone() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .motionBlur, value: .score(0.76), confidence: 0.68)
        ])

        XCTAssertEqual(presentation.title, "Motion blur 76%")
        XCTAssertEqual(presentation.detail, "Motion blur - local-http - 68% confidence")
        XCTAssertEqual(presentation.tone, .caution)
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
