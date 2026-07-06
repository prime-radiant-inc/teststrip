public enum EvaluationKind: String, Codable, Sendable {
    case focus
    case motionBlur
    case exposure
    case aesthetics
    case framing
    case object
    case faceCount
    case faceQuality
    case ocrText
    case colorPalette
    case novelty
    case visualSimilarity
}

public enum EvaluationValue: Codable, Equatable, Sendable {
    case score(Double)
    case label(String)
    case labels([String])
    case text(String)
    case count(Int)
    case vector([Double])
}

public struct EvaluationSignal: Codable, Equatable, Sendable {
    public var assetID: AssetID
    public var kind: EvaluationKind
    public var value: EvaluationValue
    public var confidence: Double
    public var provenance: ProviderProvenance

    public init(assetID: AssetID, kind: EvaluationKind, value: EvaluationValue, confidence: Double, provenance: ProviderProvenance) {
        self.assetID = assetID
        self.kind = kind
        self.value = value
        self.confidence = confidence
        self.provenance = provenance
    }
}
