import Foundation

public protocol EvaluationProvider: Sendable {
    var name: String { get }
    func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal]
}

public struct FaceEvaluationOutcome: Equatable, Sendable {
    public var signals: [EvaluationSignal]
    public var faceObservations: [CatalogFaceObservation]

    public init(signals: [EvaluationSignal], faceObservations: [CatalogFaceObservation]) {
        self.signals = signals
        self.faceObservations = faceObservations
    }
}

public protocol FaceObservationEvaluationProvider: EvaluationProvider {
    var faceProvenance: ProviderProvenance { get }
    func evaluateWithFaces(assetID: AssetID, previewURL: URL) throws -> FaceEvaluationOutcome
}
