import XCTest
import TeststripCore
@testable import TeststripApp

final class CullReadsCardPresentationTests: XCTestCase {
    func testThreeScoredKindsRenderVerdictAndGlyphEntriesIncludingFaceKinds() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.96), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 0.7)
        ])

        // (0.96 * 100 + 0.9 * 50 + 1.0 * 63) / 213 = 0.9577..., above Keep.
        XCTAssertEqual(presentation.verdictText, "Keep")
        XCTAssertEqual(presentation.verdictTone, .positive)
        // Every verdict input is visible on the card now — face kinds
        // included, in canonical order after the whole-photo kinds.
        XCTAssertEqual(presentation.glyphEntries, [
            CullReadsCardPresentation.GlyphEntry(
                kind: .focus, word: "Focus", score: 0.96, accessibilityText: "Focus 96%"),
            CullReadsCardPresentation.GlyphEntry(
                kind: .aesthetics, word: "Looks", score: 0.9, accessibilityText: "Looks 90%"),
            CullReadsCardPresentation.GlyphEntry(
                kind: .eyesOpen, word: "Eyes", score: 1.0, accessibilityText: "Eyes 100%")
        ])
        XCTAssertEqual(presentation.wholePhotoGlyphEntries.map(\.kind), [.focus, .aesthetics])
        XCTAssertEqual(presentation.faceGlyphEntries.map(\.kind), [.eyesOpen])
        XCTAssertEqual(presentation.verdictHelp, "Composed read 0.96 from 3 signals")
        XCTAssertNil(presentation.emptyState)
        XCTAssertNil(presentation.earlyReadCaveat)
    }

    // Order is fixed canonical order, independent of score: the four
    // whole-photo kinds, then the three face kinds.
    func testGlyphOrderIsCanonicalAndValueIndependent() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .eyeSharpness, value: .score(0.99), confidence: 1.0),
            signal(kind: .framing, value: .score(0.95), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.9), confidence: 1.0),
            signal(kind: .faceQuality, value: .score(0.97), confidence: 1.0),
            signal(kind: .motionBlur, value: .score(0.2), confidence: 1.0),
            signal(kind: .eyesOpen, value: .score(1.0), confidence: 1.0),
            signal(kind: .focus, value: .score(0.1), confidence: 1.0)
        ])

        XCTAssertEqual(
            presentation.glyphEntries.map(\.kind),
            [.focus, .motionBlur, .framing, .aesthetics, .eyesOpen, .faceQuality, .eyeSharpness]
        )
        XCTAssertEqual(
            presentation.glyphEntries.map(\.kind),
            CullReadsCardPresentation.canonicalSignalOrder
        )
    }

    // Kinds with no signal are simply absent — never a fake zero glyph.
    // smile is not rankable and never appears at all.
    func testMissingAndUnrankableKindsAreOmittedNotFakedAsZero() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.8), confidence: 1.0),
            signal(kind: .smile, value: .score(1.0), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.4), confidence: 1.0)
        ])

        XCTAssertEqual(presentation.glyphEntries.map(\.kind), [.focus, .aesthetics])
        XCTAssertTrue(presentation.faceGlyphEntries.isEmpty)
    }

    // motionBlur components are defect-inverted at the core layer; the
    // glyph shows that component score as-is (0.2 raw blur -> 0.8 shown).
    func testMotionGlyphUsesTheAlreadyInvertedComponentScore() {
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .motionBlur, value: .score(0.2), confidence: 1.0),
            signal(kind: .focus, value: .score(0.5), confidence: 1.0)
        ])

        let motion = presentation.glyphEntries.first { $0.kind == .motionBlur }
        XCTAssertEqual(motion?.score, 0.8)
        XCTAssertEqual(motion?.word, "Motion")
        XCTAssertEqual(motion?.accessibilityText, "Motion 80%")
    }

    // Exactly one scored kind — of ANY rankable kind, face included — is a
    // PARTIAL read: the one glyph renders with the early-read caveat and no
    // verdict. This retires the 2026-07-28 face-only fallback: face kinds
    // are first-class glyphs now, so there is nothing dishonest to fall
    // back from.
    func testExactlyOneScoredKindOfAnyKindIsAPartialRead() {
        for (kind, word) in [(EvaluationKind.focus, "Focus"), (.faceQuality, "Face")] {
            let presentation = CullReadsCardPresentation.presentation(for: [
                signal(kind: kind, value: .score(0.9), confidence: 1.0)
            ])

            XCTAssertNil(presentation.emptyState, "\(kind)")
            XCTAssertNil(presentation.verdictText, "\(kind)")
            XCTAssertNil(presentation.verdictHelp, "\(kind)")
            XCTAssertEqual(presentation.verdictTone, .waiting, "\(kind)")
            XCTAssertEqual(presentation.glyphEntries.map(\.word), [word], "\(kind)")
            XCTAssertEqual(presentation.earlyReadCaveat, "early read — 1 signal", "\(kind)")
        }
    }

    // A full read between the Toss and Keep thresholds is pure silence in
    // the verdict slot: glyphs render, verdictText/verdictHelp stay nil.
    func testNoCallFullReadRendersGlyphsWithPureSilence() {
        // (0.6 * 100 + 0.6 * 50) / 150 = 0.6 — between 0.5 and 0.7.
        let presentation = CullReadsCardPresentation.presentation(for: [
            signal(kind: .focus, value: .score(0.6), confidence: 1.0),
            signal(kind: .aesthetics, value: .score(0.6), confidence: 1.0)
        ])

        XCTAssertNil(presentation.verdictText)
        XCTAssertNil(presentation.verdictHelp)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.glyphEntries.count, 2)
        XCTAssertNil(presentation.emptyState)
        XCTAssertNil(presentation.earlyReadCaveat)
    }

    // Zero scored kinds is the only "No read yet" state now.
    func testZeroSignalsGatesTheWholeCard() {
        let presentation = CullReadsCardPresentation.presentation(for: [])

        XCTAssertEqual(presentation.emptyState, "No read yet")
        XCTAssertNil(presentation.verdictText)
        XCTAssertNil(presentation.verdictHelp)
        XCTAssertEqual(presentation.verdictTone, .waiting)
        XCTAssertEqual(presentation.glyphEntries, [])
        XCTAssertNil(presentation.earlyReadCaveat)
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
