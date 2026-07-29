import TeststripCore

/// The right-panel reads card model: a fast triage cue — the frame's
/// Keep/Toss verdict plus one micro-glyph (donut + word) per scored rankable
/// kind, face kinds included, so every verdict input is visible in one
/// place. Reuses `CullingAssistPresentation`'s verdict computation and
/// `CullingStackRecommendation`'s per-kind component scoring rather than
/// re-deriving either; the close-ups rail keeps per-face detail (these
/// entries are the photo-level best component per kind, exactly what the
/// composite consumes, so the line and the verdict can never disagree).
///
/// Three states, gated on scored rankable kind count:
/// - Zero kinds: `emptyState` only ("No read yet").
/// - Exactly one kind (any kind, face included): a PARTIAL read — the one
///   glyph plus `earlyReadCaveat` in place of the verdict; no verdict is
///   ever computed off one signal.
/// - Two or more kinds: the full glyph line plus the verdict word — or pure
///   silence in the verdict slot when the composed read lands between the
///   Toss and Keep thresholds (a read that can't commit says nothing).
struct CullReadsCardPresentation: Equatable {
    struct GlyphEntry: Equatable {
        var kind: EvaluationKind
        var word: String
        var score: Double
        var accessibilityText: String
    }

    /// Fixed display order, identical for every photo regardless of score:
    /// the four whole-photo kinds, then the three face kinds.
    static let canonicalSignalOrder: [EvaluationKind] = [
        .focus, .motionBlur, .framing, .aesthetics,
        .eyesOpen, .faceQuality, .eyeSharpness
    ]

    /// The measure's inline word. "Looks" stands in for aesthetics so the
    /// line stays one line; nil for unrankable kinds (e.g. smile).
    static func word(for kind: EvaluationKind) -> String? {
        switch kind {
        case .focus: return "Focus"
        case .motionBlur: return "Motion"
        case .framing: return "Framing"
        case .aesthetics: return "Looks"
        case .eyesOpen: return "Eyes"
        case .faceQuality: return "Face"
        case .eyeSharpness: return "Eye sharp"
        default: return nil
        }
    }

    var verdictText: String?
    var verdictTone: CullingAssistPresentation.Tone
    /// Non-nil exactly when `verdictText` is — the one place the composition
    /// is stated, as hover/AX help, never on screen.
    var verdictHelp: String?
    var glyphEntries: [GlyphEntry]
    var emptyState: String?
    /// Non-nil only for a PARTIAL (exactly one scored kind) read.
    var earlyReadCaveat: String?

    /// The line wraps by domain, not by measurement: whole-photo glyphs on
    /// the first line, face glyphs on the second when present.
    var wholePhotoGlyphEntries: [GlyphEntry] {
        glyphEntries.filter { !Self.faceKinds.contains($0.kind) }
    }

    var faceGlyphEntries: [GlyphEntry] {
        glyphEntries.filter { Self.faceKinds.contains($0.kind) }
    }

    private static let faceKinds: Set<EvaluationKind> = [.eyesOpen, .faceQuality, .eyeSharpness]

    static func presentation(for signals: [EvaluationSignal]) -> CullReadsCardPresentation {
        guard let read = CullingStackRecommendation.normalizedQualityRead(for: signals) else {
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                verdictHelp: nil,
                glyphEntries: [],
                emptyState: "No read yet",
                earlyReadCaveat: nil
            )
        }
        let entries = glyphEntries(for: signals)
        guard read.kindCount >= 2 else {
            // PARTIAL read: one scored kind of any rankable kind. Never a
            // verdict off one signal — CullingAssistPresentation.verdict is
            // not consulted here.
            return CullReadsCardPresentation(
                verdictText: nil,
                verdictTone: .waiting,
                verdictHelp: nil,
                glyphEntries: entries,
                emptyState: nil,
                earlyReadCaveat: "early read — 1 signal"
            )
        }
        let verdict = CullingAssistPresentation.verdict(for: signals)
        return CullReadsCardPresentation(
            verdictText: verdict?.text,
            verdictTone: verdict?.tone ?? .waiting,
            verdictHelp: verdict.map { _ in
                String(format: "Composed read %.2f from %d signals", read.score, read.kindCount)
            },
            glyphEntries: entries,
            emptyState: nil,
            earlyReadCaveat: nil
        )
    }

    // Canonical order, not score order. Kinds with no signal are simply
    // absent (never a fake zero glyph). Component scores arrive already
    // defect-inverted from the core scorer — no second inversion here.
    private static func glyphEntries(for signals: [EvaluationSignal]) -> [GlyphEntry] {
        let bestComponentByKind = CullingStackRecommendation.bestComponentByKind(for: signals)
        return canonicalSignalOrder.compactMap { kind in
            guard let component = bestComponentByKind[kind], let word = word(for: kind) else {
                return nil
            }
            return GlyphEntry(
                kind: kind,
                word: word,
                score: component.score,
                accessibilityText: "\(word) \(EvaluationSignalPresentation.percentage(component.score))"
            )
        }
    }
}
