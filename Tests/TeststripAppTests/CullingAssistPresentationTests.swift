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
        XCTAssertEqual(presentation.detail, "Aesthetics - local-http - 74% confidence · Focus 91%")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testDetailCombinesQualitySignalsIntoCompactRationale() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .motionBlur, value: .score(0.18), confidence: 0.68),
            signal(kind: .faceQuality, value: .score(0.84), confidence: 0.71),
            signal(kind: .object, value: .label("camera"), confidence: 0.88)
        ])

        XCTAssertEqual(presentation.title, "Motion blur 18%")
        XCTAssertEqual(presentation.detail, "Motion blur - local-http - 68% confidence · Focus 91% · Face quality 84%")
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

    func testStackGuidanceOverridesSelectedFrameReadWhenRecommendedActionExists() {
        let presentation = CullingAssistPresentation.presentation(
            for: [
                signal(kind: .focus, value: .score(0.42), confidence: 0.8)
            ],
            stackGuidance: CullingStackActionPresentation(
                action: .keepRecommended(AssetID(rawValue: "alternate")),
                title: "Keep recommended 3",
                isEnabled: true,
                help: "Keep frame 3 based on focus and quality signals.",
                liveMockupPlaceholder: nil,
                assistTitle: "Recommended frame 3"
            )
        )

        XCTAssertEqual(presentation.title, "Recommended frame 3")
        XCTAssertEqual(presentation.detail, "Stack recommendation - Keep frame 3 based on focus and quality signals. · Selected: Focus - local-http - 80% confidence")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testTopRankedStackGuidanceUsesStructuredReadTitle() {
        let presentation = CullingAssistPresentation.presentation(
            for: [
                signal(kind: .focus, value: .score(0.88), confidence: 0.82)
            ],
            stackGuidance: CullingStackActionPresentation(
                action: .keepTopRanked([
                    AssetID(rawValue: "alternate"),
                    AssetID(rawValue: "selected")
                ]),
                title: "Keep top 2",
                isEnabled: true,
                help: "Keep the two top-ranked frames based on focus and quality signals.",
                liveMockupPlaceholder: nil,
                assistTitle: "Top 2 frames"
            )
        )

        XCTAssertEqual(presentation.title, "Top 2 frames")
        XCTAssertEqual(presentation.detail, "Stack recommendation - Keep the two top-ranked frames based on focus and quality signals. · Selected: Focus - local-http - 82% confidence")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testIgnoredStackGuidancePreservesSelectedFrameRead() {
        let selectedSignals = [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82)
        ]
        let ignoredActions = [
            CullingStackActionPresentation(
                action: .keepRecommended(AssetID(rawValue: "alternate")),
                title: "Keep recommended 3",
                isEnabled: false,
                help: "Keep frame 3 based on focus and quality signals.",
                liveMockupPlaceholder: nil,
                assistTitle: "Recommended frame 3"
            ),
            CullingStackActionPresentation(
                action: .keepAll,
                title: "Keep all 3",
                isEnabled: true,
                help: "Keep every frame in this stack.",
                liveMockupPlaceholder: nil,
                assistTitle: "Keep all frames"
            )
        ]

        for action in ignoredActions {
            let presentation = CullingAssistPresentation.presentation(
                for: selectedSignals,
                stackGuidance: action
            )

            XCTAssertEqual(presentation.title, "Focus 91%")
            XCTAssertEqual(presentation.detail, "Focus - local-http - 82% confidence")
            XCTAssertEqual(presentation.tone, .positive)
        }
    }

    func testEyeSignalsJoinVerdictRationaleAfterFocus() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 0.7),
            signal(kind: .eyeSharpness, value: .score(0.84), confidence: 0.6)
        ])

        XCTAssertEqual(presentation.title, "Focus 91%")
        XCTAssertEqual(presentation.detail, "Focus - local-http - 82% confidence · Eyes open · Eyes sharp")
        XCTAssertEqual(presentation.tone, .positive)
    }

    func testAllEyesShutBecomesCautionVerdictWhenPrimary() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .eyesOpen, value: .score(0.0), confidence: 0.7)
        ])

        XCTAssertEqual(presentation.title, "Eyes shut")
        XCTAssertEqual(presentation.detail, "Eyes open - local-http - 70% confidence")
        XCTAssertEqual(presentation.tone, .caution)
    }

    func testPartialBlinkReadsAsSomeEyesShut() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .eyesOpen, value: .score(0.5), confidence: 0.7)
        ])

        XCTAssertEqual(presentation.detail, "Focus - local-http - 82% confidence · Some eyes shut")
    }

    func testSoftEyesUseCautionPhraseAndTone() {
        let presentation = CullingAssistPresentation.presentation(for: [
            signal(kind: .eyeSharpness, value: .score(0.3), confidence: 0.6)
        ])

        XCTAssertEqual(presentation.title, "Eyes soft")
        XCTAssertEqual(presentation.tone, .caution)
    }

    func testSmilePhraseAppearsOnlyWhenSomeoneSmiles() {
        let noSmiles = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .smile, value: .score(0.0), confidence: 0.7)
        ])
        XCTAssertEqual(noSmiles.detail, "Focus - local-http - 82% confidence")

        let allSmiling = CullingAssistPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.91), confidence: 0.82),
            signal(kind: .smile, value: .score(1.0), confidence: 0.7)
        ])
        XCTAssertEqual(allSmiling.detail, "Focus - local-http - 82% confidence · Smiling")
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
