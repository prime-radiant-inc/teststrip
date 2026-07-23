import XCTest
import TeststripCore
@testable import TeststripApp

final class CullReadsCardPresentationTests: XCTestCase {
    func testThreeScoredKindsRenderVerdictAndCanonicalOrderRows() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 0.7)
        ])

        // (0.96 * 100 + 0.9 * 50 + 1.0 * 63) / 213 = 0.9577..., above the Keep threshold.
        XCTAssertEqual(presentation.verdictText, "Keep")
        XCTAssertEqual(presentation.verdictTone, .positive)
        // eyesOpen is face-specific — it never appears in the whole-photo
        // row list, even though it's scored and drives the verdict above.
        XCTAssertEqual(presentation.signalRows, [
            CullReadsCardPresentation.SignalRow(kind: .focus, score: 0.96),
            CullReadsCardPresentation.SignalRow(kind: .aesthetics, score: 0.9)
        ])
        XCTAssertNil(presentation.emptyState)
    }

    // The row order is a fixed canonical order — identical for every photo,
    // independent of score. Shuffling which kind has the highest value must
    // not reorder the rows: framing/aesthetics score higher here than
    // focus/motionBlur, yet focus and motionBlur still lead.
    func testRowOrderIsCanonicalAndValueIndependent() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .framing, value: .score(0.95), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .motionBlur, value: .score(0.2), confidence: 1.0),
            signal(kind: .focus, value: .score(0.1), confidence: 1.0)
        ])

        XCTAssertEqual(
            presentation.signalRows.map(\.kind),
            CullReadsCardPresentation.canonicalSignalOrder
        )
    }

    // Kinds the photo has no signal for are simply absent — never a fake
    // zero-scored row.
    func testMissingKindsAreOmittedNotFakedAsZero() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.8), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.4), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.signalRows.map(\.kind), [.focus, .aesthetics])
    }

    // Face-specific kinds (faceQuality, eyeSharpness, eyesOpen, smile) never
    // populate the whole-photo row list, no matter how strongly scored —
    // they belong to the close-ups rail instead.
    func testFaceSpecificKindsNeverAppearInSignalRows() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.8), confidence: 1.0),
            signal(kind: .faceQuality, value: .score(0.9), confidence: 1.0),
            signal(kind: .eyeSharpness, value: .score(0.9), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 1.0),
            signal(kind: .smile, value: .score(1.0), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.signalRows.map(\.kind), [.focus])
    }

    func testExactlyOneScoredKindGatesTheWholeCard() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.emptyState, "No read yet")
        XCTAssertNil(presentation.verdictText)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.signalRows, [])
    }

    func testZeroSignalsGatesTheWholeCard() {
        let presentation = CullReadsCardPresentation.presentation(for: [])

        XCTAssertEqual(presentation.emptyState, "No read yet")
        XCTAssertNil(presentation.verdictText)
        XCTAssertEqual(presentation.verdictTone, .waiting)
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
