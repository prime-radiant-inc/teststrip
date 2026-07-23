import TeststripCore

/// The right-panel reads card model: the frame's Keep/Toss verdict plus a
/// per-kind signal row for each whole-photo read. Reuses
/// `CullingAssistPresentation`'s verdict computation and
/// `CullingStackRecommendation`'s per-kind component scoring rather than
/// re-deriving either.
///
/// One home per fact: each whole-photo signal appears exactly once, in a
/// fixed canonical order that never depends on score (so the card doesn't
/// reshuffle photo to photo). Face-specific kinds (faceQuality,
/// eyeSharpness, eyesOpen, smile) never appear here — they render on the
/// close-ups rail (`CloseUpFacesPresentation`) instead.
///
/// Strictly gated on the whole card, not just the verdict line: with fewer
/// than two scored quality kinds there is no card at all (`emptyState`
/// only), deliberately stricter than the HUD line, which still renders a
/// single-signal read.
struct CullReadsCardPresentation: Equatable {
    struct SignalRow: Equatable {
        var kind: EvaluationKind
        var score: Double
    }

    /// Fixed display order for whole-photo signal rows, identical for every
    /// photo regardless of score.
    static let canonicalSignalOrder: [EvaluationKind] = [.focus, .motionBlur, .framing, .aesthetics]

    var verdictText: String?
    var verdictTone: CullingAssistPresentation.Tone
    var signalRows: [SignalRow]
    var emptyState: String?

    static func presentation(for signals: [EvaluationSignal]) -> CullReadsCardPresentation {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals),
              read.kindCount >= 2 else {
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                signalRows: [],
                emptyState: "No read yet"
            )
        }
        let verdict = CullingAssistPresentation.verdict(for: signals)
        return CullReadsCardPresentation(
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting,
            signalRows: Self.signalRows(for: signals),
            emptyState: nil
        )
    }

    // Canonical order, not score order — a row present for a photo always
    // lands in the same place. Kinds with no signal are simply absent
    // (never a fake zero-scored row).
    private static func signalRows(for signals: [EvaluationSignal]) -> [SignalRow] {
        let bestComponentByKind = CullingStackRecommendation.bestComponentByKind(for: signals)
        return canonicalSignalOrder.compactMap { kind in
            bestComponentByKind[kind].map { SignalRow(kind: kind, score: $0.score) }
        }
    }
}
