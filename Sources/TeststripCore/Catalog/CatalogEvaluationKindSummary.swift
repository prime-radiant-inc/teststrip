public struct CatalogEvaluationKindSummary: Equatable, Sendable {
    public var kind: EvaluationKind
    public var assetCount: Int

    public init(kind: EvaluationKind, assetCount: Int) {
        self.kind = kind
        self.assetCount = assetCount
    }
}
