import TeststripCore

struct CullingAssistPresentation {
    enum Tone: Equatable {
        case waiting
        case positive
        case caution
    }

    // Anchored to the 2026-07-06 calibration study on the calibrated
    // focus-family scale: Keep >= 0.7 selects the jointly-strong top quarter
    // of the corpus and Toss <= 0.5 the weak quarter (eyes-shut and
    // bottom-decile-focus frames), leaving roughly half Mixed.
    private static let keepReadThreshold = 0.7
    private static let tossReadThreshold = 0.5

    // Synthesized display-only read over the same components the stack
    // ranking uses; at least two scored quality kinds are required because
    // one signal is not a verdict. Not private: the reads card
    // (CullReadsCardPresentation) reuses this exact computation rather than
    // duplicating the Keep/Toss scoring. A read that lands between the two
    // thresholds is Mixed — and a verdict that can't commit to Toss or Keep
    // says nothing at all, so that case returns nil too, same as too few
    // scored kinds.
    static func verdict(for signals: [EvaluationSignal]) -> (text: String, tone: Tone)? {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals),
              read.kindCount >= 2 else {
            return nil
        }
        if read.score >= keepReadThreshold {
            return ("Keep", .positive)
        }
        if read.score <= tossReadThreshold {
            return ("Toss", .caution)
        }
        return nil
    }
}
