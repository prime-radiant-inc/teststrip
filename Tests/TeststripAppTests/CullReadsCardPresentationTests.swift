import XCTest
import TeststripCore
@testable import TeststripApp

final class CullReadsCardPresentationTests: XCTestCase {
    func testThreeScoredKindsRenderVerdictAndRows() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 0.7)
        ])

        // (0.96 * 100 + 0.9 * 50 + 1.0 * 63) / 213 = 0.9577... -> 96%
        XCTAssertEqual(presentation.verdictText, "Keep read 96%")
        XCTAssertEqual(presentation.verdictTone, .positive)
        XCTAssertEqual(presentation.rationalePhrases, ["Aesthetics 90%", "Focus 96%", "Eyes open"])
        XCTAssertEqual(presentation.signalRows, [
            CullReadsCardPresentation.SignalRow(kind: .eyesOpen, score: 1.0),
            CullReadsCardPresentation.SignalRow(kind: .focus, score: 0.96),
            CullReadsCardPresentation.SignalRow(kind: .aesthetics, score: 0.9)
        ])
        XCTAssertNil(presentation.emptyState)
    }

    func testExactlyOneScoredKindGatesTheWholeCard() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.emptyState, "No read yet")
        XCTAssertNil(presentation.verdictText)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.rationalePhrases, [])
        XCTAssertEqual(presentation.signalRows, [])
    }

    func testZeroSignalsGatesTheWholeCard() {
        let presentation = CullReadsCardPresentation.presentation(for: [])

        XCTAssertEqual(presentation.emptyState, "No read yet")
        XCTAssertNil(presentation.verdictText)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.rationalePhrases, [])
        XCTAssertEqual(presentation.signalRows, [])
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
