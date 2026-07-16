import TeststripCore

struct CullingAssistPresentation: Equatable {
    enum Tone: Equatable {
        case waiting
        case positive
        case caution
        case neutral
    }

    var title: String
    var detail: String
    var tone: Tone
    var verdictText: String?
    var verdictTone: Tone

    // Anchored to the 2026-07-06 calibration study on the calibrated
    // focus-family scale: Keep >= 0.7 selects the jointly-strong top quarter
    // of the corpus and Toss <= 0.5 the weak quarter (eyes-shut and
    // bottom-decile-focus frames), leaving roughly half Mixed.
    private static let keepReadThreshold = 0.7
    private static let tossReadThreshold = 0.5

    static func presentation(
        for signals: [EvaluationSignal],
        stackGuidance: CullingStackActionPresentation? = nil
    ) -> CullingAssistPresentation {
        let verdict = verdict(for: signals)
        if let stackGuidance,
           stackGuidance.isEnabled,
           let stackTitle = stackGuidanceTitle(for: stackGuidance) {
            return CullingAssistPresentation(
                title: stackTitle,
                detail: stackGuidanceDetail(for: stackGuidance, selectedSignals: signals),
                tone: .positive,
                verdictText: verdict?.text,
                verdictTone: verdict?.tone ?? .waiting
            )
        }
        guard let signal = signals.sorted(by: signalSort).first else {
            return CullingAssistPresentation(
                title: "No read yet",
                detail: "Evaluate frame to show culling signals",
                tone: .waiting,
                verdictText: verdict?.text,
                verdictTone: verdict?.tone ?? .waiting
            )
        }
        return CullingAssistPresentation(
            title: title(for: signal),
            detail: detail(primarySignal: signal, signals: signals),
            tone: tone(for: signal),
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting
        )
    }

    // Synthesized display-only read over the same components the stack
    // ranking uses; at least two scored quality kinds are required because
    // one signal is not a verdict. Not private: the reads card
    // (CullReadsCardPresentation) reuses this exact computation rather than
    // duplicating the Keep/Toss/Mixed scoring.
    static func verdict(for signals: [EvaluationSignal]) -> (text: String, tone: Tone)? {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals),
              read.kindCount >= 2 else {
            return nil
        }
        let percentText = EvaluationSignalPresentation.percentage(read.score)
        if read.score >= keepReadThreshold {
            return ("Keep read \(percentText)", .positive)
        }
        if read.score <= tossReadThreshold {
            return ("Toss read \(percentText)", .caution)
        }
        return ("Mixed read \(percentText)", .neutral)
    }

    /// Short rationale phrases for the top signals, in display order — the
    /// same primary-signal-then-rationale composition `detail(primarySignal:
    /// signals:)` joins into one line, but as discrete phrases for the reads
    /// card's row-per-phrase layout. Reused rather than duplicated so the
    /// HUD line and the reads card can never disagree on the reasons shown.
    static func rationalePhrases(for signals: [EvaluationSignal]) -> [String] {
        guard let primarySignal = signals.sorted(by: signalSort).first else { return [] }
        return [title(for: primarySignal)] + rationaleTexts(for: signals, excluding: primarySignal)
    }

    private static func stackGuidanceTitle(for action: CullingStackActionPresentation) -> String? {
        switch action.action {
        case .keepRecommended, .keepTopRanked:
            return action.assistTitle ?? action.title
        case .keepSelectedAndRejectAlternates, .keepAll:
            return nil
        }
    }

    private static func stackGuidanceDetail(
        for action: CullingStackActionPresentation,
        selectedSignals: [EvaluationSignal]
    ) -> String {
        var parts = ["Stack recommendation - \(action.help)"]
        if let selectedSignal = selectedSignals.sorted(by: signalSort).first {
            parts.append("Selected: \(detail(primarySignal: selectedSignal, signals: selectedSignals))")
        }
        return parts.joined(separator: " · ")
    }

    private static func detail(primarySignal: EvaluationSignal, signals: [EvaluationSignal]) -> String {
        var parts = [
            "\(EvaluationSignalPresentation.displayName(for: primarySignal.kind)) - \(primarySignal.provenance.provider) - \(EvaluationSignalPresentation.percentage(primarySignal.confidence)) confidence"
        ]
        parts.append(contentsOf: rationaleTexts(for: signals, excluding: primarySignal))
        return parts.joined(separator: " · ")
    }

    private static func rationaleTexts(
        for signals: [EvaluationSignal],
        excluding primarySignal: EvaluationSignal,
        limit: Int = 3
    ) -> [String] {
        var seenKinds = [primarySignal.kind]
        var rationales: [String] = []
        for signal in signals.sorted(by: signalSort) where signal != primarySignal {
            guard rationales.count < limit,
                  !seenKinds.contains(signal.kind),
                  let rationale = rationaleText(for: signal) else {
                continue
            }
            rationales.append(rationale)
            seenKinds.append(signal.kind)
        }
        return rationales
    }

    private static func expressionPhrase(for signal: EvaluationSignal) -> String? {
        guard case .score(let score) = signal.value else { return nil }
        switch signal.kind {
        case .eyesOpen:
            if score >= 1.0 { return "Eyes open" }
            if score <= 0.0 { return "Eyes shut" }
            return "Some eyes shut"
        case .eyeSharpness:
            return score >= EvaluationSignalPresentation.eyeSharpnessSharpThreshold ? "Eyes sharp" : "Eyes soft"
        case .smile:
            if score >= 1.0 { return "Smiling" }
            if score > 0.0 { return "Some smiling" }
            return nil
        default:
            return nil
        }
    }

    private static func rationaleText(for signal: EvaluationSignal) -> String? {
        switch signal.kind {
        case .eyesOpen, .eyeSharpness, .smile:
            return expressionPhrase(for: signal)
        case .focus, .motionBlur, .exposure, .aesthetics, .framing, .faceQuality, .faceCount, .novelty, .colorPalette, .visualSimilarity:
            return title(for: signal)
        case .object, .ocrText:
            return nil
        }
    }

    private static func signalSort(_ lhs: EvaluationSignal, _ rhs: EvaluationSignal) -> Bool {
        let lhsRank = rank(for: lhs.kind)
        let rhsRank = rank(for: rhs.kind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.confidence > rhs.confidence
    }

    private static func rank(for kind: EvaluationKind) -> Int {
        switch kind {
        case .aesthetics:
            return 0
        case .framing:
            return 1
        case .motionBlur:
            return 2
        case .focus:
            return 3
        case .faceQuality:
            return 4
        case .eyesOpen:
            return 5
        case .eyeSharpness:
            return 6
        case .smile:
            return 7
        case .faceCount:
            return 8
        case .exposure:
            return 9
        case .object:
            return 10
        case .ocrText:
            return 11
        case .novelty:
            return 12
        case .colorPalette:
            return 13
        case .visualSimilarity:
            return 14
        }
    }

    private static func title(for signal: EvaluationSignal) -> String {
        if let phrase = expressionPhrase(for: signal) {
            return phrase
        }
        switch signal.value {
        case .score(let score):
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) \(EvaluationSignalPresentation.percentage(score))"
        case .label(let label):
            return EvaluationSignalPresentation.capitalized(label, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .labels(let labels):
            return EvaluationSignalPresentation.capitalized(labels.joined(separator: ", "), fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .text(let text):
            return EvaluationSignalPresentation.capitalized(text, fallback: EvaluationSignalPresentation.displayName(for: signal.kind))
        case .count(let count):
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) \(count)"
        case .vector:
            return "\(EvaluationSignalPresentation.displayName(for: signal.kind)) sampled"
        }
    }

    private static func tone(for signal: EvaluationSignal) -> Tone {
        switch (signal.kind, signal.value) {
        case (.motionBlur, .score(let score)):
            return score >= 0.5 ? .caution : .positive
        case (.focus, .score(let score)):
            return score >= 0.7 ? .positive : .caution
        case (.faceQuality, .score(let score)):
            return score >= EvaluationSignalPresentation.faceQualityStrongThreshold ? .positive : .caution
        case (.aesthetics, .label(let label)), (.framing, .label(let label)):
            return cautionLabels.contains(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ? .caution : .positive
        case (.faceCount, .count(let count)):
            return count > 0 ? .positive : .neutral
        case (.eyesOpen, .score(let score)):
            return score >= 1.0 ? .positive : .caution
        case (.eyeSharpness, .score(let score)):
            return score >= EvaluationSignalPresentation.eyeSharpnessSharpThreshold ? .positive : .caution
        case (.smile, .score(let score)):
            return score > 0.0 ? .positive : .neutral
        default:
            return .neutral
        }
    }

    private static let cautionLabels: Set<String> = [
        "blur",
        "blurry",
        "reject",
        "soft",
        "eyes closed",
        "closed eyes"
    ]

}
