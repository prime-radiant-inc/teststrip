import Foundation

/// Pure defect-inverted quality scoring shared by the app's stack-culling
/// recommendation and the autopilot proposal planner, so the banner's read
/// and the proposal ranking can never disagree.
public enum CullingQualityScore {
    /// Defect-inverted score plus confidence-scaled weight for one signal.
    /// Returns nil for a signal that carries no rankable `.score` value.
    public static func qualityComponent(for signal: EvaluationSignal) -> (score: Double, weight: Double)? {
        guard case .score(let rawScore) = signal.value else { return nil }
        let clampedScore = min(max(rawScore, 0), 1)
        let confidence = min(max(signal.confidence, 0), 1)
        switch signal.kind {
        case .focus:
            return (clampedScore, confidence * 100)
        case .eyesOpen:
            return (clampedScore, confidence * 90)
        case .faceQuality:
            return (clampedScore, confidence * 80)
        case .eyeSharpness:
            return (clampedScore, confidence * 70)
        case .motionBlur:
            return (1 - clampedScore, confidence * 60)
        case .aesthetics:
            return (clampedScore, confidence * 50)
        case .framing:
            return (clampedScore, confidence * 45)
        default:
            return nil
        }
    }

    /// Summed defect-inverted quality across the best-weighted component per
    /// kind. Returns nil when no signal carries a rankable `.score` value.
    public static func qualityScore(for signals: [EvaluationSignal]) -> Double? {
        var scoreByKind: [EvaluationKind: Double] = [:]
        for signal in signals {
            guard let component = qualityComponent(for: signal) else { continue }
            let weightedScore = component.score * component.weight
            scoreByKind[signal.kind] = max(scoreByKind[signal.kind] ?? 0, weightedScore)
        }
        guard !scoreByKind.isEmpty else { return nil }
        return scoreByKind.values.reduce(0, +)
    }
}
