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
/// Three states, gated on scored whole-photo kind count
/// (`CullingStackRecommendation.normalizedQualityRead`'s `kindCount`):
/// - Zero rankable kinds: no read at all — `emptyState` only, no rows, no
///   verdict ("No read yet").
/// - Exactly one kind: a PARTIAL read. The single row renders, but no
///   verdict is ever computed off one signal — `CullingAssistPresentation
///   .verdict` is not consulted for a partial read — and `earlyReadCaveat`
///   carries an explicit early-read disclosure the view renders in place of
///   the verdict line.
/// - Two or more kinds: a FULL read — verdict plus every scored row,
///   `earlyReadCaveat` nil. This is the FULL-read threshold, not a render
///   wall on the whole card.
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
    /// Non-nil only for a PARTIAL (exactly one scored kind) read — an
    /// explicit disclosure the view renders in place of the verdict line.
    var earlyReadCaveat: String?

    static func presentation(for signals: [EvaluationSignal]) -> CullReadsCardPresentation {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals) else {
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                signalRows: [],
                emptyState: "No read yet",
                earlyReadCaveat: nil
            )
        }
        guard read.kindCount >= 2 else {
            // PARTIAL read: exactly one scored kind. Render the single row,
            // but never synthesize a verdict off one signal.
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                signalRows: Self.signalRows(for: signals),
                emptyState: nil,
                earlyReadCaveat: "early read — 1 signal"
            )
        }
        let verdict = CullingAssistPresentation.verdict(for: signals)
        return CullReadsCardPresentation(
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting,
            signalRows: Self.signalRows(for: signals),
            emptyState: nil,
            earlyReadCaveat: nil
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
