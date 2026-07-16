import TeststripCore

/// The right-panel reads card model: the frame's Keep/Toss/Mixed verdict,
/// the short rationale phrases behind it, and a per-kind signal row for
/// each kind's defect-inverted bar. Reuses `CullingAssistPresentation`'s
/// verdict/rationale computations and `CullingStackRecommendation`'s
/// per-kind component scoring rather than re-deriving either.
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

    var verdictText: String?
    var verdictTone: CullingAssistPresentation.Tone
    var rationalePhrases: [String]
    var signalRows: [SignalRow]
    var emptyState: String?

    static func presentation(for signals: [EvaluationSignal]) -> CullReadsCardPresentation {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals),
              read.kindCount >= 2 else {
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                rationalePhrases: [],
                signalRows: [],
                emptyState: "No read yet"
            )
        }
        let verdict = CullingAssistPresentation.verdict(for: signals)
        return CullReadsCardPresentation(
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting,
            rationalePhrases: CullingAssistPresentation.rationalePhrases(for: signals),
            signalRows: Self.signalRows(for: signals),
            emptyState: nil
        )
    }

    // Strongest signal first, so the top bar in the card is the strongest
    // read; kind name breaks ties for a deterministic order.
    private static func signalRows(for signals: [EvaluationSignal]) -> [SignalRow] {
        CullingStackRecommendation.bestComponentByKind(for: signals)
            .map { SignalRow(kind: $0.key, score: $0.value.score) }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.kind.rawValue < rhs.kind.rawValue
            }
    }
}
